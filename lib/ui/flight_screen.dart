import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/airspace.dart';
import '../core/flight/geo.dart';
import '../core/geo.dart';
import '../services/flight_controller.dart';
import '../services/settings.dart';
import '../services/task_store.dart';
import '../core/task/task.dart';
import 'common.dart';
import 'instruments.dart';
import 'settings_screen.dart';
import 'task_sheet.dart';
import 'thermal_assistant_view.dart';

/// In-flight instruments: vario, altitude, height above ground, speed, wind, glide.
class FlightScreen extends StatelessWidget {
  const FlightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = FlightController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([fc, TaskStore.instance]),
      builder: (context, _) {
        return Column(children: [
          if (fc.airspaceWarnings.isNotEmpty) _AirspaceBanner(fc.airspaceWarnings),
          _VarioPanel(fc.varioMs, fc.avg30Ms, fc.thermalAvgMs, fc.thermalGainM, fc.varioSource),
          if (fc.assist case final a?) ThermalAssistantView(a, trackDeg: fc.trackDeg),
          if (TaskStore.instance.task != null) _TaskCard(fc),
          Expanded(child: _InstrumentPages(fc)),
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
                tooltip: 'Competition task',
                icon: const Icon(Icons.flag_circle_outlined),
                onPressed: () => showTaskSheet(context),
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

class _TaskCard extends StatelessWidget {
  const _TaskCard(this.fc);
  final FlightController fc;

  @override
  Widget build(BuildContext context) {
    final p = TaskStore.instance.progress!;
    final t = Theme.of(context).textTheme;
    final next = p.nextTurnpoint;
    final route = fc.taskRoute;
    final f = fc.fix;
    String line;
    if (next == null) {
      line = 'Goal reached${p.speedSectionTime == null ? '' : ' · SS ${p.speedSectionTime!.inMinutes} min'}';
    } else if (route == null || f == null || route.legsM.isEmpty) {
      line = 'Next: ${next.name}';
    } else {
      final toNext = route.legsM.first;
      final touch = route.points.first;
      final brg = bearingDeg(f.lat, f.lon, touch.$1, touch.$2);
      final eta = fc.groundSpeedKmh > 5 ? Duration(seconds: (toNext / (fc.groundSpeedKmh / 3.6)).round()) : null;
      line = '${next.name} ${(toNext / 1000).toStringAsFixed(1)} km ${compass(brg)}'
          '${eta == null ? '' : ' · ${eta.inMinutes} min'}'
          ' · goal ${(route.totalM / 1000).toStringAsFixed(1)} km'
          '${fc.taskRequiredGlide == null ? '' : ' · L/D ${fc.taskRequiredGlide!.toStringAsFixed(1)}'}';
    }
    final gate = p.stage == TaskStage.beforeStart && f != null ? p.nextGate(f.time) : null;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.flag_circle),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (gate != null) Text('Start gate opens in ${gate.inMinutes}:${(gate.inSeconds % 60).toString().padLeft(2, '0')}', style: t.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

/// Swipeable pages of instrument tiles; editable (tap a tile to change it).
class _InstrumentPages extends StatefulWidget {
  const _InstrumentPages(this.fc);
  final FlightController fc;

  @override
  State<_InstrumentPages> createState() => _InstrumentPagesState();
}

class _InstrumentPagesState extends State<_InstrumentPages> {
  final _controller = PageController();
  late List<InstrumentPage> pages = decodePages(Settings.instance.pagesJson);
  int page = 0;
  bool editing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Settings.instance.update((s) => s.pagesJson = encodePages(pages));
    setState(() {});
  }

  Future<void> _pick(int pageIndex, int? tileIndex) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true, // as tall as the chips need
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          // Chips instead of a long list: everything fits on one screen.
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            if (tileIndex != null)
              ActionChip(
                avatar: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove tile'),
                onPressed: () => Navigator.pop(ctx, 'remove'),
              ),
            for (final i in Instrument.values) ActionChip(label: Text(i.label), onPressed: () => Navigator.pop(ctx, i)),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    final tiles = pages[pageIndex].tiles;
    if (choice == 'remove' && tileIndex != null) {
      tiles.removeAt(tileIndex);
    } else if (choice is Instrument) {
      tileIndex == null ? tiles.add(choice) : tiles[tileIndex] = choice;
    }
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 0),
        child: Row(children: [
          for (var i = 0; i < pages.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == page ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(child: Text(pages[page].name, style: t.labelMedium, overflow: TextOverflow.ellipsis)),
          if (editing) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add page',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () {
                pages.add(InstrumentPage('Page ${pages.length + 1}', [Instrument.altitude, Instrument.groundSpeed]));
                _save();
              },
            ),
            if (pages.length > 1)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete page',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  pages.removeAt(page);
                  page = 0;
                  _controller.jumpToPage(0);
                  _save();
                },
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Reset pages',
              icon: const Icon(Icons.restart_alt),
              onPressed: () {
                pages = defaultPages();
                page = 0;
                _controller.jumpToPage(0);
                Settings.instance.update((s) => s.pagesJson = null);
                setState(() {});
              },
            ),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: editing ? 'Done' : 'Edit pages',
            icon: Icon(editing ? Icons.check : Icons.dashboard_customize_outlined),
            onPressed: () => setState(() => editing = !editing),
          ),
        ]),
      ),
      Expanded(
        child: PageView.builder(
          controller: _controller,
          itemCount: pages.length,
          onPageChanged: (i) => setState(() => page = i),
          itemBuilder: (context, pi) {
            final tiles = pages[pi].tiles;
            return GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 1.05,
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var i = 0; i < tiles.length; i++)
                  InstrumentTile(tiles[i], widget.fc, editing: editing, onTap: editing ? () => _pick(pi, i) : null),
                if (editing)
                  OutlinedButton(
                    onPressed: () => _pick(pi, null),
                    child: const Icon(Icons.add),
                  ),
              ],
            );
          },
        ),
      ),
    ]);
  }
}
