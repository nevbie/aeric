import 'package:flutter/material.dart';

import '../core/landing.dart';
import '../core/site.dart';
import '../services/app_state.dart';

/// Bottom sheet to add an own takeoff or landing field at [lat]/[lon] (long-press on the map).
Future<void> showPlaceEditor(BuildContext context, double lat, double lon) async {
  final app = AppState.instance;
  double? ele;
  try {
    ele = await app.elevation.elevation(lat, lon);
  } catch (_) {}
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PlaceEditor(lat: lat, lon: lon, elevation: ele),
  );
}

class _PlaceEditor extends StatefulWidget {
  const _PlaceEditor({required this.lat, required this.lon, this.elevation});
  final double lat;
  final double lon;
  final double? elevation;

  @override
  State<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<_PlaceEditor> {
  static const _points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  bool landing = false;
  final _name = TextEditingController();
  late final _ele = TextEditingController(text: widget.elevation?.round().toString() ?? '');
  final Set<String> _dirs = {};

  @override
  void dispose() {
    _name.dispose();
    _ele.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && double.tryParse(_ele.text) != null && (landing || _dirs.isNotEmpty);

  Future<void> _save() async {
    final app = AppState.instance;
    final id = 'user-${DateTime.now().millisecondsSinceEpoch}';
    final ele = double.parse(_ele.text);
    if (landing) {
      await app.addUserLanding(LandingField(
        id: id, name: _name.text.trim(), lat: widget.lat, lon: widget.lon, elevationM: ele, userDefined: true,
      ));
    } else {
      await app.addUserSite(Site(
        id: id, name: _name.text.trim(), lat: widget.lat, lon: widget.lon, takeoffElevationM: ele,
        sectors: [for (final d in _points.where(_dirs.contains)) WindSector.ofCompass(d)!],
      ));
      app.refreshForecasts();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.paragliding), label: Text('Takeoff')),
            ButtonSegment(value: true, icon: Icon(Icons.flag_outlined), label: Text('Landing')),
          ],
          selected: {landing},
          onSelectionChanged: (v) => setState(() => landing = v.first),
        ),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), onChanged: (_) => setState(() {})),
        TextField(
          controller: _ele,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Elevation (m)',
            helperText: widget.elevation == null ? null : 'From terrain model – correct it if you know better',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (!landing) ...[
          const SizedBox(height: 12),
          const Text('Launch directions (wind from)'),
          Wrap(spacing: 6, children: [
            for (final d in _points)
              FilterChip(
                label: Text(d),
                selected: _dirs.contains(d),
                onSelected: (v) => setState(() => v ? _dirs.add(d) : _dirs.remove(d)),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        Text('${widget.lat.toStringAsFixed(5)}, ${widget.lon.toStringAsFixed(5)}', style: Theme.of(context).textTheme.bodySmall),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _valid ? _save : null, child: const Text('Save')),
        ),
      ]),
    );
  }
}
