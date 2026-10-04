import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import '../core/flight/vario_tone.dart';

/// Streams vario beeps through the platform audio output. The PCM is generated in Dart from
/// the current climb rate in 50 ms chunks, so pitch and beep rate follow the vario quickly.
class VarioAudio {
  static const _rate = 22050;
  static const _chunk = _rate ~/ 20; // 50 ms

  final _synth = ToneSynth(sampleRate: _rate);
  VarioToneMapper mapper = const VarioToneMapper();
  double Function() climb = () => 0;
  bool _running = false;
  bool muted = false;

  Future<void> start(double Function() climbSource) async {
    climb = climbSource;
    if (_running) return;
    try {
      await FlutterPcmSound.setup(sampleRate: _rate, channelCount: 1, iosAllowBackgroundAudio: true);
      await FlutterPcmSound.setFeedThreshold(_chunk * 2);
      FlutterPcmSound.setFeedCallback(_feed);
      _running = true;
      FlutterPcmSound.start();
    } catch (e) {
      debugPrint('vario audio unavailable: $e');
    }
  }

  void _feed(int remaining) {
    if (!_running) return;
    final tone = muted ? Tone.silent : mapper.toneFor(climb());
    final pcm = _synth.render(tone, _chunk * 2);
    FlutterPcmSound.feed(PcmArrayInt16.fromList(pcm));
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      FlutterPcmSound.setFeedCallback(null);
      await FlutterPcmSound.release();
    } catch (_) {}
  }
}
