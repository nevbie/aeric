import 'dart:convert';

import 'package:aeric/core/open_meteo.dart';
import 'package:aeric/main.dart';
import 'package:aeric/services/app_state.dart';
import 'package:aeric/services/http.dart';
import 'package:aeric/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> location(double wind) => {
      'elevation': 500,
      'utc_offset_seconds': 7200,
      'hourly': {
        'time': ['2026-10-04T12:00', '2026-10-04T13:00'],
        'wind_speed_10m': [wind, wind],
        'wind_direction_10m': [270, 270],
      },
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapScreen.tilesEnabled = false;
  });

  test('forecasts for many sites come from one request, in order', () async {
    final asked = <Uri>[];
    final client = OpenMeteoClient((u) async {
      asked.add(u);
      final n = u.queryParameters['latitude']!.split(',').length;
      return jsonEncode([for (var i = 0; i < n; i++) location(i.toDouble())]);
    });
    final pts = [for (var i = 0; i < 14; i++) (48.0 + i / 100, 8.0)];
    final res = await client.forecastMany(pts, pastDays: 1);
    expect(asked, hasLength(1));
    expect(asked.single.queryParameters['latitude']!.split(','), hasLength(14));
    expect(asked.single.queryParameters['past_days'], '1');
    expect(res, hasLength(14));
    expect(res[5].first.windSpeed10m, 5);
    // Big lists are split into chunks.
    asked.clear();
    await client.forecastMany([for (var i = 0; i < 30; i++) (48.0, 8.0)], chunk: 25);
    expect(asked, hasLength(2));
  });

  test('a single location response (object, not list) still works', () async {
    final client = OpenMeteoClient((u) async => jsonEncode(location(7)));
    final res = await client.forecastMany([(48.0, 8.0)]);
    expect(res.single.first.windSpeed10m, 7);
  });

  test('429 is retried with backoff, then succeeds', () async {
    var calls = 0;
    final get = networkGet(
      client: MockClient((r) async {
        calls++;
        return calls < 3
            ? http.Response('{"error":true,"reason":"Too many concurrent requests"}', 429)
            : http.Response('ok', 200);
      }),
      backoff: const Duration(milliseconds: 1),
    );
    expect(await get(Uri.parse('https://api.open-meteo.com/v1/forecast')), 'ok');
    expect(calls, 3);
  });

  test('persistent 429 gives a short, friendly error without the URL', () async {
    final get = networkGet(
      client: MockClient((r) async => http.Response('{"error":true,"reason":"Too many concurrent requests"}', 429)),
      backoff: const Duration(milliseconds: 1),
      retries: 2,
    );
    try {
      await get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=48.1&longitude=8.2&hourly=x'));
      fail('should throw');
    } catch (e) {
      expect(e, isA<ServiceException>());
      final msg = friendlyError(e);
      expect(msg, contains('busy'));
      expect(msg, contains('Too many concurrent requests'));
      expect(msg, isNot(contains('latitude')));
      expect(msg.length, lessThan(120));
    }
    expect(friendlyError(const ServiceException(503, '', 'x')), contains('unavailable'));
  });

  test('never more than two requests to the same host at once', () async {
    var inFlight = 0, maxInFlight = 0;
    final get = networkGet(client: MockClient((r) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      inFlight--;
      return http.Response('ok', 200);
    }));
    await Future.wait([for (var i = 0; i < 8; i++) get(Uri.parse('https://api.open-meteo.com/v1/x?i=$i'))]);
    expect(maxInFlight, 2);
  });

  testWidgets('a failed refresh shows one short error line on the Fly tab', (tester) async {
    final app = AppState(get: (u) async => throw const ServiceException(429, 'Too many concurrent requests', 'api.open-meteo.com'));
    await app.loadFavourites();
    await app.refreshForecasts();
    expect(app.forecastError, contains('busy'));
    expect(app.forecastErrors.length, app.sites.length);

    // The singleton shows the same state in the UI.
    AppState.instance.forecastError = app.forecastError;
    AppState.instance.forecasts.clear();
    AppState.instance.setTab(0);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(const AericApp());
    await tester.pump();
    expect(find.textContaining('Weather service busy'), findsOneWidget);
    expect(find.textContaining('api.open-meteo.com'), findsNothing);
    AppState.instance.forecastError = null;
    await tester.pumpWidget(const SizedBox());
  });
}
