import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/flight/thermal_assistant.dart';
import 'common.dart';

/// Lift map around the pilot while circling: dots coloured by climb, an arrow to the core.
/// Track-up: the pilot flies "up" the screen.
class ThermalAssistantView extends StatelessWidget {
  const ThermalAssistantView(this.assist, {super.key, this.trackDeg, this.rangeM = 150});

  final ThermalAssist assist;
  final double? trackDeg;
  final double rangeM;

  @override
  Widget build(BuildContext context) {
    final rel = trackDeg == null ? null : assist.relativeToTrack(trackDeg!);
    final side = rel == null
        ? ''
        : rel.abs() < 30
            ? 'ahead'
            : rel.abs() > 150
                ? 'behind'
                : rel > 0
                    ? 'to the right'
                    : 'to the left';
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        SizedBox(
          width: 150,
          height: 150,
          child: CustomPaint(
            painter: _AssistPainter(assist, trackDeg ?? 0, rangeM, Theme.of(context).colorScheme.outline),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Thermal assistant', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              'Core ${assist.coreDistanceM.round()} m $side',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text('best ${assist.coreClimbMs.toStringAsFixed(1)} m/s · circle Ø ${assist.averageClimbMs.toStringAsFixed(1)} m/s',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('Shift the circle towards the arrow.', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class _AssistPainter extends CustomPainter {
  _AssistPainter(this.a, this.trackDeg, this.rangeM, this.outline);
  final ThermalAssist a;
  final double trackDeg;
  final double rangeM;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final scale = size.shortestSide / 2 / rangeM;
    final rot = -trackDeg * math.pi / 180; // track-up
    Offset toScreen(double e, double n) {
      final x = e * math.cos(rot) - n * math.sin(rot);
      final y = e * math.sin(rot) + n * math.cos(rot);
      return c + Offset(x * scale, -y * scale);
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = outline.withValues(alpha: 0.4);
    canvas.drawCircle(c, size.shortestSide / 2 - 1, ring);
    canvas.drawCircle(c, size.shortestSide / 4, ring);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final p in a.points) {
      final r = 3.0 + 2.0 * p.climbMs.clamp(0.0, 4.0);
      canvas.drawCircle(toScreen(p.eastM, p.northM), r, Paint()..color = climbColor(p.climbMs).withValues(alpha: 0.85));
    }
    final core = toScreen(a.coreEastM, a.coreNorthM);
    canvas.drawCircle(core, 8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = goColor);
    canvas.restore();
    // Arrow from the pilot to the core.
    final arrow = Paint()
      ..color = goColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final dir = (core - c);
    if (dir.distance > 4) {
      final tip = c + dir / dir.distance * math.min(dir.distance, size.shortestSide / 2 - 6);
      canvas.drawLine(c, tip, arrow);
      final ang = math.atan2(dir.dy, dir.dx);
      for (final s in [-0.5, 0.5]) {
        canvas.drawLine(tip, tip - Offset(math.cos(ang + s), math.sin(ang + s)) * 12, arrow);
      }
    }
    // Pilot (pointing up = track).
    final glider = Path()
      ..moveTo(c.dx, c.dy - 9)
      ..lineTo(c.dx - 7, c.dy + 7)
      ..lineTo(c.dx + 7, c.dy + 7)
      ..close();
    canvas.drawPath(glider, Paint()..color = outline);
  }

  @override
  bool shouldRepaint(_AssistPainter old) => true;
}
