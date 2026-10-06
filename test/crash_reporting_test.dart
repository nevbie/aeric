import 'package:aeric/services/crash_reporting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logIgnored works without Sentry (builds without SENTRY_DSN)', () {
    expect(() => logIgnored('Something optional', Exception('boom')), returnsNormally);
  });
}
