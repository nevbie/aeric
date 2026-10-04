import 'dart:math' as math;
import 'dart:typed_data';

/// What the vario should sound like for a vertical speed.
class Tone {
  const Tone({required this.frequencyHz, required this.periodS, required this.duty});

  static const silent = Tone(frequencyHz: 0, periodS: 1, duty: 0);

  final double frequencyHz;

  /// Beep cycle length; [duty] = sounding share of it (1 = continuous).
  final double periodS;
  final double duty;

  bool get isSilent => frequencyHz <= 0 || duty <= 0;
}

/// Classic vario sound: rising beeps in lift (higher and faster the stronger), silence in
/// normal sink, a low continuous tone in strong sink.
class VarioToneMapper {
  const VarioToneMapper({
    this.liftThresholdMs = 0.2,
    this.sinkThresholdMs = -2.5,
    this.baseHz = 600,
    this.hzPerMs = 120,
  });

  final double liftThresholdMs;
  final double sinkThresholdMs;
  final double baseHz;
  final double hzPerMs;

  Tone toneFor(double vMs) {
    if (vMs >= liftThresholdMs) {
      final v = vMs.clamp(0.0, 8.0);
      return Tone(
        frequencyHz: (baseHz + hzPerMs * v).clamp(200.0, 1800.0),
        periodS: (0.65 - 0.06 * v).clamp(0.15, 0.65),
        duty: 0.5,
      );
    }
    if (vMs <= sinkThresholdMs) {
      return Tone(frequencyHz: (380 + 25 * (vMs - sinkThresholdMs)).clamp(180.0, 380.0), periodS: 1, duty: 1);
    }
    return Tone.silent;
  }
}

/// Generates 16-bit mono PCM for a [Tone], keeping phase and beep position continuous between
/// chunks so the sound never clicks when the climb rate changes.
class ToneSynth {
  ToneSynth({this.sampleRate = 44100, this.volume = 0.6});

  final int sampleRate;
  double volume;
  double _phase = 0;
  double _beepPos = 0; // seconds into the current beep cycle

  Int16List render(Tone tone, int samples) {
    final out = Int16List(samples);
    if (tone.isSilent) {
      _beepPos = 0;
      return out;
    }
    final dt = 1 / sampleRate;
    final onFor = tone.periodS * tone.duty;
    const fade = 0.004; // 4 ms fade in/out against clicks
    for (var i = 0; i < samples; i++) {
      final on = _beepPos < onFor;
      if (on) {
        final env = math.min(1.0, math.min(_beepPos, onFor - _beepPos) / fade);
        out[i] = (math.sin(_phase) * env * volume * 32767).round();
        _phase += 2 * math.pi * tone.frequencyHz * dt;
        if (_phase > 2 * math.pi) _phase -= 2 * math.pi;
      }
      _beepPos += dt;
      if (_beepPos >= tone.periodS) _beepPos -= tone.periodS;
    }
    return out;
  }
}
