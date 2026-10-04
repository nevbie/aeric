import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/airspace.dart';
import '../core/geo.dart';
import '../services/flight_controller.dart';
import '../services/settings.dart';
import 'common.dart';
import 'settings_screen.dart';

/// In-flight instruments: vario, altitude, height above ground, speed, wind, glide.
class FlightScreen extends StatelessWidget {
  const FlightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = FlightController.instance;
    return ListenableBuilder(
      listenable: fc,
      builder: (context, _) {
        final f = fc.fix;
        final fg = fc.finalGlideToLanding;
        final w = fc.wind;
        return Column(children: [
          if (fc.airspaceWarnings.isNotEmpty) _AirspaceBanner(fc.airspaceWarnings),
          _VarioPanel(fc.varioMs, fc.avg30Ms, fc.thermalAvgMs, fc.thermalGainM, fc.varioSource),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 1.05,
              padding: const EdgeInsets.all(6),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                _Tile('Altitude', f == null ? '–' : '${f.altM.round()}', 'm${fc.hasBarometer ? ' baro' : ' GPS'}'),
                _Tile('Above ground', fc.aglM == null ? '–' : '${fc.aglM!.round()}', 'm AGL'),
                _Tile('Ground speed', f == null ? '–' : fc.groundSpeedKmh.toStringAsFixed(0), 'km/h'),
                _Tile('Track', fc.trackDeg == null ? '–' : '${fc.trackDeg!.round()}°', fc.trackDeg == null ? '' : compass(fc.trackDeg!)),
                _WindTile(w?.fromDeg, w?.speedKmh, fc.trackDeg),
                _Tile('Glide', fc.glideRatio == null ? '–' : fc.glideRatio!.toStringAsFixed(1), 'L/D last 30 s'),
                _Tile(
                  'Landing',
                  fg == null ? '–' : '${fg.distanceKm.toStringAsFixed(1)} km',
                  fc.landing == null ? 'none within 40 km' : '${fc.landing!.name} · ${compass(fg!.bearingDeg)}',
                ),
                _Tile(
                  'Needed L/D',
                  fg?.requiredGlideRatio == null ? '–' : fg!.requiredGlideRatio!.toStringAsFixed(1),
                  'incl. ${Settings.instance.safetyMarginM.round()} m margin',
                  color: fg == null ? null : (fg.reachable ? goColor : noGoColor),
                ),
                _Tile(
                  'Arrival',
                  fg == null || fg.arrivalHeightM.isInfinite ? '–' : '${fg.arrivalHeightM.round()}',
                  'm above margin',
                  color: fg == null ? null : (fg.reachable ? goColor : noGoColor),
                ),
              ],
            ),
          ),
          if (fc.error != null) ErrorText(fc.error!),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Expanded(
                child: fc.mode == FlightMode.idle
                    ? FilledButton.icon(
                        icon: const Icon(Icons.fiber_manual_record),
                        label: const Text('Start flight'),
                        onPressed: fc.startLive,
                      )
                    : FilledButton.tonalIcon(
                        icon: const Icon(Icons.stop),
                        label: Text(fc.mode == FlightMode.replay ? 'Stop replay' : 'Stop & save'),
                        onPressed: fc.stop,
                      ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: fc.audio.muted ? 'Vario sound on' : 'Mute vario',
                icon: Icon(fc.audio.muted ? Icons.volume_off : Icons.volume_up),
                onPressed: fc.toggleMute,
              ),
              IconButton.filledTonal(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => openSettings(context),
              ),
              IconButton.filledTonal(
                tooltip: fc.voice ? 'Voice off' : 'Voice on',
                icon: Icon(fc.voice ? Icons.record_voice_over : Icons.voice_over_off),
                onPressed: fc.toggleVoice,
              ),
            ]),
          ),
          if (fc.mode != FlightMode.idle)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                fc.mode == FlightMode.replay
                    ? 'Replay (10×) – nothing is recorded'
                    : fc.flying
                        ? 'Flying since ${hhmm(fc.takeoffTime!.toLocal())} · ${fc.track.length} fixes'
                        : 'Waiting for takeoff · ${fc.track.length} fixes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ]);
      },
    );
  }
}

class _AirspaceBanner extends StatelessWidget {
  const _AirspaceBanner(this.warnings);
  final List<AirspaceWarning> warnings;

  @override
  Widget build(BuildContext context) {
    final w = warnings.first;
    final color = switch (w.level) {
      AirspaceLevel.inside => noGoColor,
      AirspaceLevel.warning => marginalColor,
      AirspaceLevel.info => Colors.blueGrey,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            w.text + (warnings.length > 1 ? '  (+${warnings.length - 1})' : ''),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

class _VarioPanel extends StatelessWidget {
  const _VarioPanel(this.v, this.avg, this.thermalAvg, this.thermalGain, this.source);
  final double v;
  final String source;
  final double? avg;
  final double? thermalAvg;
  final double? thermalGain;

  @override
  Widget build(BuildContext context) {
    final color = v >= 0.2 ? goColor : (v <= -2 ? noGoColor : Theme.of(context).colorScheme.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        // Vertical bar ±5 m/s.
        SizedBox(
          width: 18,
          height: 110,
          child: CustomPaint(painter: _BarPainter(v, color, Theme.of(context).colorScheme.outline)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vario · $source', style: Theme.of(context).textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}',
              style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: color, height: 1.0),
            ),
            Text('m/s', style: Theme.of(context).textTheme.labelMedium),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Ø 30 s', style: Theme.of(context).textTheme.labelSmall),
          Text(avg == null ? '–' : avg!.toStringAsFixed(1), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text('Thermal Ø', style: Theme.of(context).textTheme.labelSmall),
          Text(
            thermalAvg == null ? '–' : '${thermalAvg!.toStringAsFixed(1)} · +${thermalGain!.round()} m',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ]),
      ]),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.v, this.color, this.outline);
  final double v;
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = outline.withValues(alpha: 0.2));
    final h = (v.clamp(-5.0, 5.0) / 5) * mid;
    canvas.drawRect(Rect.fromLTRB(0, math.min(mid, mid - h), size.width, math.max(mid, mid - h)), Paint()..color = color);
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = outline);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.v != v || old.color != color;
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.unit, {this.color});
  final String label;
  final String value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        // The value takes the remaining height and shrinks on small screens.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ),
        ),
        Text(unit, style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _WindTile extends StatelessWidget {
  const _WindTile(this.fromDeg, this.speedKmh, this.trackDeg);
  final double? fromDeg;
  final double? speedKmh;
  final double? trackDeg;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Wind (circling)', style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (fromDeg != null)
                // Arrow points where the wind blows to.
                Transform.rotate(angle: (fromDeg! + 180) * math.pi / 180, child: const Icon(Icons.navigation, size: 22)),
              const SizedBox(width: 4),
              Text(speedKmh == null ? '–' : speedKmh!.toStringAsFixed(0), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        Text(fromDeg == null ? 'circle once' : 'km/h from ${compass(fromDeg!)}', style: t.labelSmall, maxLines: 1),
      ]),
    );
  }
}
