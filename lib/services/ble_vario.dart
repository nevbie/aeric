import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import '../core/devices/vario_protocols.dart';
import 'crash_reporting.dart';

enum BleState { idle, scanning, connecting, connected, error }

/// Bluetooth LE varios (XC Tracer, Skytraxx, FlyMaster, BlueFly, Oudie, OpenVario …).
/// They send NMEA-style text over a serial-like characteristic; we subscribe to every
/// notifying characteristic and parse whatever lines arrive.
class BleVario extends ChangeNotifier {
  BleVario._();
  static final instance = BleVario._();

  static const _savedKey = 'bleVarioId';

  BleState state = BleState.idle;
  String? error;
  final Map<String, BleDevice> devices = {};
  String? deviceId;
  String? deviceName;
  VarioSample? last;
  DateTime? lastAt;
  final Map<String, int> sentences = {};

  final _samples = StreamController<VarioSample>.broadcast();
  Stream<VarioSample> get samples => _samples.stream;

  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<bool>? _connSub;
  final List<StreamSubscription<Uint8List>> _valueSubs = [];
  final _assembler = LineAssembler();

  bool get connected => state == BleState.connected;

  Future<void> scan() async {
    error = null;
    devices.clear();
    try {
      await UniversalBle.requestPermissions();
      state = BleState.scanning;
      notifyListeners();
      await _scanSub?.cancel();
      _scanSub = UniversalBle.scanStream.listen((d) {
        if ((d.name ?? '').isEmpty) return;
        devices[d.deviceId] = d;
        notifyListeners();
      });
      await UniversalBle.startScan();
      Future.delayed(const Duration(seconds: 12), stopScan);
    } catch (e) {
      _fail('Scan failed: $e');
    }
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await UniversalBle.stopScan();
    } catch (e) {
      logIgnored('Stopping BLE scan', e);
    }
    if (state == BleState.scanning) {
      state = BleState.idle;
      notifyListeners();
    }
  }

  Future<void> connect(String deviceId, {String? name}) async {
    await stopScan();
    state = BleState.connecting;
    this.deviceId = deviceId;
    deviceName = name ?? devices[deviceId]?.name ?? deviceId;
    error = null;
    notifyListeners();
    try {
      await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));
      await _connSub?.cancel();
      _connSub = UniversalBle.connectionStream(deviceId).listen((up) {
        if (!up && state == BleState.connected) _fail('$deviceName disconnected');
      });
      final services = await UniversalBle.discoverServices(deviceId);
      for (final s in services) {
        for (final c in s.characteristics) {
          final notify = c.properties.contains(CharacteristicProperty.notify);
          final indicate = c.properties.contains(CharacteristicProperty.indicate);
          if (!notify && !indicate) continue;
          _valueSubs.add(UniversalBle.characteristicValueStream(deviceId, c.uuid).listen(_onBytes));
          try {
            notify
                ? await UniversalBle.subscribeNotifications(deviceId, s.uuid, c.uuid)
                : await UniversalBle.subscribeIndications(deviceId, s.uuid, c.uuid);
          } catch (e) {
            debugPrint('subscribe ${c.uuid}: $e');
          }
        }
      }
      state = BleState.connected;
      (await SharedPreferences.getInstance()).setString(_savedKey, '$deviceId|$deviceName');
      notifyListeners();
    } catch (e) {
      _fail('Connection failed: $e');
    }
  }

  /// Reconnects to the last used vario, if any.
  Future<void> reconnect() async {
    if (state == BleState.connected || state == BleState.connecting) return;
    final saved = (await SharedPreferences.getInstance()).getString(_savedKey);
    if (saved == null) return;
    final parts = saved.split('|');
    await connect(parts.first, name: parts.length > 1 ? parts[1] : null);
  }

  Future<void> disconnect({bool forget = false}) async {
    for (final s in _valueSubs) {
      await s.cancel();
    }
    _valueSubs.clear();
    await _connSub?.cancel();
    final id = deviceId;
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (e) {
        logIgnored('BLE disconnect', e);
      }
    }
    if (forget) (await SharedPreferences.getInstance()).remove(_savedKey);
    state = BleState.idle;
    notifyListeners();
  }

  void _onBytes(Uint8List bytes) {
    for (final line in _assembler.add(bytes)) {
      final s = parseVarioLine(line);
      if (s == null) continue;
      handleSample(s);
    }
  }

  /// Entry point for parsed samples (also used by tests).
  void handleSample(VarioSample s) {
    last = s;
    lastAt = DateTime.now();
    sentences[s.source] = (sentences[s.source] ?? 0) + 1;
    _samples.add(s);
    notifyListeners();
  }

  void _fail(String message) {
    error = message;
    state = BleState.error;
    notifyListeners();
  }
}
