import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry DSN, set at build time: `flutter build apk --dart-define=SENTRY_DSN=https://…`.
/// Without it (local and CI test builds) nothing is reported.
const _dsn = String.fromEnvironment('SENTRY_DSN');

/// Initialises the app inside Sentry so uncaught Flutter, Dart and native errors are reported.
/// No personal data is sent (no IP, no user, no screenshots; flight tracks and positions are never attached).
/// [after] runs once the app is shown (e.g. start loading data).
Future<void> runWithCrashReporting(Future<void> Function() init, Widget Function() app,
    {void Function()? after}) async {
  if (_dsn.isEmpty) {
    WidgetsFlutterBinding.ensureInitialized();
    await init();
    runApp(app());
    after?.call();
    return;
  }
  await SentryFlutter.init(
    (o) {
      o.dsn = _dsn;
      o.sendDefaultPii = false;
      o.tracesSampleRate = 0;
    },
    appRunner: () async {
      await init();
      runApp(app());
      after?.call();
    },
  );
}

/// For best-effort steps whose failure does not matter (stopping audio, closing a Bluetooth
/// connection, an optional lookup): logs the error instead of swallowing it silently, and keeps
/// it as a breadcrumb so it shows up next to a later crash report.
void logIgnored(String what, Object error) {
  debugPrint('$what failed (ignored): $error');
  Sentry.addBreadcrumb(Breadcrumb(message: '$what failed: $error', level: SentryLevel.warning, category: 'ignored'));
}
