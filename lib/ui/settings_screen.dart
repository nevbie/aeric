import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/airspace_store.dart';
import '../services/app_state.dart';
import '../services/settings.dart';

/// Pilot, glider, final glide, vario sound and altimeter settings; own sites.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final st = Settings.instance;
  late final _pilot = TextEditingController(text: st.pilot);
  late final _glider = TextEditingController(text: st.glider);
  late final _qnh = TextEditingController(text: st.qnhHpa?.toStringAsFixed(1) ?? '');
  final _airUrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    AirspaceStore.instance.load();
  }

  Future<void> _importAirspace() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final f = picked.first;
    await AirspaceStore.instance.importBytes(await f.xFile.readAsBytes(), from: f.name);
  }

  @override
  void dispose() {
    _pilot.dispose();
    _glider.dispose();
    _qnh.dispose();
    _airUrl.dispose();
    super.dispose();
  }

  Widget _slider(String label, double value, double min, double max, int divisions, String Function(double) fmt,
      void Function(Settings s, double v) set) {
    return ListTile(
      title: Text('$label: ${fmt(value)}'),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) => st.update((s) => set(s, v)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([st, app, AirspaceStore.instance]),
        builder: (context, _) => ListView(children: [
          const _Header('Pilot (written into recorded IGC files)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _pilot,
              decoration: const InputDecoration(labelText: 'Pilot name'),
              onChanged: (v) => st.update((s) => s.pilot = v.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _glider,
              decoration: const InputDecoration(labelText: 'Glider'),
              onChanged: (v) => st.update((s) => s.glider = v.trim()),
            ),
          ),
          const _Header('Glider polar and final glide'),
          _slider('Trim speed', st.trimKmh, 25, 60, 35, (v) => '${v.round()} km/h', (s, v) => s.trimKmh = v),
          _slider('Sink at trim', st.trimSinkMs, 0.7, 2.0, 26, (v) => '${v.toStringAsFixed(2)} m/s', (s, v) => s.trimSinkMs = v),
          ListTile(dense: true, title: Text('Glide ratio at trim ≈ ${st.polar.glideRatio.toStringAsFixed(1)}')),
          _slider('Safety margin above landing', st.safetyMarginM, 0, 400, 16, (v) => '${v.round()} m', (s, v) => s.safetyMarginM = v),
          const _Header('Vario sound'),
          _slider('Lift beeps from', st.liftThresholdMs, 0, 1, 20, (v) => '+${v.toStringAsFixed(2)} m/s', (s, v) => s.liftThresholdMs = v),
          _slider('Sink alarm below', st.sinkAlarmMs, -6, -1, 20, (v) => '${v.toStringAsFixed(1)} m/s', (s, v) => s.sinkAlarmMs = v),
          _slider('Volume', st.volume, 0, 1, 10, (v) => '${(v * 100).round()} %', (s, v) => s.volume = v),
          SwitchListTile(
            title: const Text('Voice callouts'),
            value: st.voice,
            onChanged: (v) => st.update((s) => s.voice = v),
          ),
          const _Header('Altimeter'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _qnh,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'QNH (hPa)',
                helperText: 'Empty = calibrate automatically on the launch height or GPS when the flight starts',
              ),
              onChanged: (v) {
                final q = double.tryParse(v.replaceAll(',', '.'));
                st.update((s) => s.qnhHpa = q != null && q > 900 && q < 1100 ? q : null);
              },
            ),
          ),
          const _Header('Airspace (OpenAIR)'),
          ListTile(
            title: Text(AirspaceStore.instance.airspaces.isEmpty
                ? 'No airspace loaded'
                : '${AirspaceStore.instance.airspaces.length} airspaces from ${AirspaceStore.instance.source}'),
            subtitle: const Text('Warnings for CTR, restricted, prohibited, danger areas and classes A–D, TMZ/RMZ. '
                'Get a current file from your national association or openAIP (keep it up to date!).'),
          ),
          if (AirspaceStore.instance.error case final e?)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(onPressed: _importAirspace, icon: const Icon(Icons.file_open), label: const Text('Import file')),
              if (AirspaceStore.instance.airspaces.isNotEmpty)
                TextButton(onPressed: AirspaceStore.instance.clear, child: const Text('Remove')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: TextField(controller: _airUrl, decoration: const InputDecoration(labelText: 'or load from URL'))),
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => AirspaceStore.instance.download(_airUrl.text),
              ),
            ]),
          ),
          const _Header('Own takeoffs and landings (long-press the map to add)'),
          for (final s in app.sites.where((s) => s.userDefined))
            ListTile(
              leading: const Icon(Icons.paragliding),
              title: Text(s.name),
              subtitle: Text('${s.takeoffElevationM.round()} m'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => app.removeUserSite(s)),
            ),
          for (final l in app.landings.where((l) => l.userDefined))
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l.name),
              subtitle: Text('Landing · ${l.elevationM.round()} m'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => app.removeUserLanding(l)),
            ),
          if (!app.sites.any((s) => s.userDefined) && !app.landings.any((l) => l.userDefined))
            const ListTile(dense: true, title: Text('None yet.')),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

void openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
