import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/open_meteo.dart';

const userAgent = 'aeric/0.1 (paragliding planner; https://github.com/nevbie/aeric)';

/// Network GET with a sensible timeout and User-Agent.
HttpGet networkGet({http.Client? client}) {
  final c = client ?? http.Client();
  return (Uri url) async {
    final res = await c.get(url, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode > 299) {
      final body = res.body.length > 300 ? res.body.substring(0, 300) : res.body;
      throw HttpException('HTTP ${res.statusCode}: $body', uri: url);
    }
    return res.body;
  };
}

/// Caches successful responses on disk forever. Only for immutable data such as the
/// historical archive (a fixed past date range never changes).
HttpGet diskCached(HttpGet delegate, Future<Directory> Function() dir) {
  return (Uri url) async {
    final d = await dir();
    final file = File('${d.path}/${_fnv1a(url.toString())}.json');
    if (await file.exists()) return file.readAsString();
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
