import 'package:flutter/material.dart';

import '../core/gliders.dart';
import '../services/settings.dart';

/// "Schirm wählen": pick the glider by brand and model; sets the name (IGC) and a typical polar
/// for its class, which can be fine-tuned in the settings.
class GliderPickerScreen extends StatefulWidget {
  const GliderPickerScreen({super.key});

  @override
  State<GliderPickerScreen> createState() => _GliderPickerScreenState();
}

class _GliderPickerScreenState extends State<GliderPickerScreen> {
  final _search = TextEditingController();
  String? _brand;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _choose(GliderModel g) async {
    await Settings.instance.update((s) {
      s.glider = g.fullName;
      s.gliderClass = g.cls.label;
      s.trimKmh = g.cls.trimKmh;
      s.trimSinkMs = g.cls.trimSinkMs;
    });
    if (mounted) Navigator.of(context).pop(g);
  }

  Future<void> _custom() async {
    final name = TextEditingController(text: Settings.instance.glider);
    var cls = GliderClass.b;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Anderer Schirm'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Brand and model')),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (final c in GliderClass.values)
                ChoiceChip(label: Text(c.label), selected: cls == c, onSelected: (_) => setD(() => cls = c)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final parts = name.text.trim().split(' ');
      await _choose(GliderModel(parts.first, parts.skip(1).join(' '), cls));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = Settings.instance.glider;
    final query = _search.text.trim();
    final results = query.isEmpty && _brand != null
        ? gliders.where((g) => g.brand == _brand).toList()
        : searchGliders(query);
    return Scaffold(
      appBar: AppBar(title: const Text('Schirm wählen')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search brand or model, e.g. "ozone b"'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (query.isEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final b in gliderBrands)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(b),
                      selected: _brand == b,
                      onSelected: (v) => setState(() => _brand = v ? b : null),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView(children: [
            for (final g in results)
              ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: _classColor(g.cls),
                  child: Text(g.cls == GliderClass.tandem ? 'T' : g.cls.label.replaceAll('EN-', ''),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                title: Text(g.fullName),
                subtitle: Text('${g.cls.label} · trim ≈ ${g.cls.trimKmh.round()} km/h'),
                trailing: g.fullName == current ? const Icon(Icons.check) : null,
                onTap: () => _choose(g),
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Anderer Schirm (other glider)'),
              onTap: _custom,
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'The class is the certification of most sizes; speed and sink are typical values for the class. '
                'Fine-tune them under Settings → Glider polar.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

Color _classColor(GliderClass c) => switch (c) {
      GliderClass.a => const Color(0xFF43A047),
      GliderClass.b => const Color(0xFF1E88E5),
      GliderClass.c => const Color(0xFFFB8C00),
      GliderClass.d => const Color(0xFFE53935),
      GliderClass.ccc => const Color(0xFF6A1B9A),
      GliderClass.tandem => const Color(0xFF546E7A),
    };
