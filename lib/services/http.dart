import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/open_meteo.dart';

const userAgent = 'aeric/0.1 (paragliding planner; https://github.com/nevbie/aeric)';

/// Error from a web service, with the status code and a short reason (no URL).
class ServiceException implements Exception {
  const ServiceException(this.status, this.reason, this.host);
  final int status;
  final String reason;
  final String host;

  @override
  String toString() => 'HTTP $status from $host: $reason';
}

/// At most [_perHost] requests to the same host at a time; more would be rejected by
/// Open-Meteo ("429 Too many concurrent requests").
const _perHost = 2;
final _active = <String, int>{};
final _waiting = <String, List<Completer<void>>>{};

Future<void> _acquire(String host) async {
  while ((_active[host] ?? 0) >= _perHost) {
    final c = Completer<void>();
    _waiting.putIfAbsent(host, () => []).add(c);
    await c.future;
  }
  _active[host] = (_active[host] ?? 0) + 1;
}

void _release(String host) {
  _active[host] = (_active[host] ?? 1) - 1;
  final q = _waiting[host];
  if (q != null && q.isNotEmpty) q.removeAt(0).complete();
}

/// Network GET with a timeout, User-Agent, a per-host concurrency limit and retries with
/// backoff when the server is busy (429/503).
HttpGet networkGet({http.Client? client, int retries = 3, Duration backoff = const Duration(seconds: 2)}) {
  final c = client ?? http.Client();
  return (Uri url) async {
    for (var attempt = 0;; attempt++) {
      await _acquire(url.host);
      http.Response res;
      try {
        res = await c.get(url, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 30));
      } finally {
        _release(url.host);
      }
      if (res.statusCode >= 200 && res.statusCode <= 299) return res.body;
      final busy = res.statusCode == 429 || res.statusCode == 503;
      if (busy && attempt < retries) {
        await Future<void>.delayed(backoff * (1 << attempt));
        continue;
      }
      throw ServiceException(res.statusCode, _reason(res.body), url.host);
    }
  };
}

/// The "reason" field of an Open-Meteo style JSON error, or the start of the body.
String _reason(String body) {
  final m = RegExp(r'"reason"\s*:\s*"([^"]*)"').firstMatch(body);
  if (m != null) return m.group(1)!;
  final text = body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

/// A short message for the UI (no URLs).
String friendlyError(Object e) {
  if (e is ServiceException) {
    return switch (e.status) {
      429 => 'Weather service busy (${e.reason}). Tap refresh in a minute.',
      >= 500 => 'Weather service unavailable (HTTP ${e.status}). Try again later.',
      _ => 'Weather service error (HTTP ${e.status}): ${e.reason}',
    };
  }
  if (e is SocketException || e is TimeoutException || e is http.ClientException) {
    return 'No connection to the weather service. Check your internet connection.';
  }
  final s = '$e';
  return s.length > 140 ? '${s.substring(0, 140)}…' : s;
}

/// Caches successful responses on disk forever. Only for immutable data such as the
/// historical archive (a fixed past date range never changes).
///
/// With [maxAge], entries older than that are fetched again (for listings that change).
HttpGet diskCached(HttpGet delegate, Future<Directory> Function() dir, {Duration? maxAge}) {
  return (Uri url) async {
    final d = await dir();
    final file = File('${d.path}/${_fnv1a(url.toString())}.json');
    if (await file.exists() &&
        (maxAge == null || DateTime.now().difference(await file.lastModified()) < maxAge)) {
      return file.readAsString();
    }
    final body = await delegate(url);
    await d.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(file.path);
    return body;
  };
}

/// 64-bit FNV-1a, stable across runs (unlike String.hashCode).
String _fnv1a(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
