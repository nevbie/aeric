import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/flight/glide.dart';
import '../core/flight/vario_tone.dart';

/// Pilot and instrument settings, persisted with shared_preferences.
class Settings extends ChangeNotifier {
  Settings._();
  static final instance = Settings._();

  SharedPreferences? _p;

  String pilot = '';
  String glider = '';

  /// Certification class of the glider (EN-A … CCC, Tandem), if chosen from the list.
  String gliderClass = '';

  /// Glider polar at trim speed.
  double trimKmh = 38;
  double trimSinkMs = 1.1;

  /// Height to keep above a landing field for final glide.
  double safetyMarginM = 150;

  /// Vario sound: lift threshold, sink alarm and volume (0..1).
  double liftThresholdMs = 0.2;
  double sinkAlarmMs = -2.5;
  double volume = 0.6;
  bool voice = true;

  /// Instrument page layouts (JSON, see ui/instruments.dart); null = defaults.
  String? pagesJson;

  /// Manual QNH in hPa; null = calibrate automatically on the launch height / GPS.
  double? qnhHpa;

  Polar get polar => Polar(trimKmh: trimKmh, trimSinkMs: trimSinkMs);
  VarioToneMapper get toneMapper => VarioToneMapper(liftThresholdMs: liftThresholdMs, sinkThresholdMs: sinkAlarmMs);

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      final p = _p!;
      pilot = p.getString('pilot') ?? pilot;
      glider = p.getString('glider') ?? glider;
      gliderClass = p.getString('gliderClass') ?? gliderClass;
      trimKmh = p.getDouble('trimKmh') ?? trimKmh;
      trimSinkMs = p.getDouble('trimSink') ?? trimSinkMs;
      safetyMarginM = p.getDouble('safety') ?? safetyMarginM;
      liftThresholdMs = p.getDouble('lift') ?? liftThresholdMs;
      sinkAlarmMs = p.getDouble('sink') ?? sinkAlarmMs;
      volume = p.getDouble('volume') ?? volume;
      voice = p.getBool('voice') ?? voice;
      qnhHpa = p.getDouble('qnh');
      pagesJson = p.getString('pages');
    } catch (e) {
      debugPrint('settings: $e');
    }
    notifyListeners();
  }

  Future<void> update(void Function(Settings s) change) async {
    change(this);
    notifyListeners();
    final p = _p;
    if (p == null) return;
    await p.setString('pilot', pilot);
    await p.setString('glider', glider);
    await p.setString('gliderClass', gliderClass);
    await p.setDouble('trimKmh', trimKmh);
    await p.setDouble('trimSink', trimSinkMs);
    await p.setDouble('safety', safetyMarginM);
    await p.setDouble('lift', liftThresholdMs);
    await p.setDouble('sink', sinkAlarmMs);
    await p.setDouble('volume', volume);
    await p.setBool('voice', voice);
    if (pagesJson == null) {
      await p.remove('pages');
    } else {
      await p.setString('pages', pagesJson!);
    }
    if (qnhHpa == null) {
      await p.remove('qnh');
    } else {
      await p.setDouble('qnh', qnhHpa!);
    }
  }
}
