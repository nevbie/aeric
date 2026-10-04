import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/task/task.dart';
import '../services/task_store.dart';

String _km(double m) => '${(m / 1000).toStringAsFixed(1)} km';

String _tod(Duration d) =>
    '${(d.inHours % 24).toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')} UTC';

/// Competition task: import (QR code or .xctsk file), overview, restart, remove.
Future<void> showTaskSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _TaskSheet(),
    );

class _TaskSheet extends StatelessWidget {
  const _TaskSheet();

  Future<void> _file(BuildContext context) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final text = String.fromCharCodes(await picked.first.xFile.readAsBytes());
    await TaskStore.instance.import(text);
  }

  Future<void> _scan(BuildContext context) async {
    final text = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
    if (text != null) await TaskStore.instance.import(text);
  }

  @override
  Widget build(BuildContext context) {
    final store = TaskStore.instance;
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final task = store.task;
        final p = store.progress;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Competition task', style: t.titleLarge),
            if (store.error != null) Text(store.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (task == null)
              const Text('Scan the XCTrack QR code from the task briefing, or import an .xctsk file.')
            else ...[
              Text(
                '${task.turnpoints.length} turnpoints · ${_km(task.optimisedDistanceM)} optimised · '
                'start ${task.sssDirection == SssDirection.exit ? 'EXIT' : 'ENTER'} '
                '${task.timeGates.isEmpty ? '' : task.timeGates.map(_tod).join(', ')}'
                '${task.deadline == null ? '' : ' · deadline ${_tod(task.deadline!)}'}',
                style: t.bodySmall,
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(shrinkWrap: true, children: [
                  for (var i = 0; i < task.turnpoints.length; i++)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        p != null && i < p.next ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: p != null && i == p.next ? Theme.of(context).colorScheme.primary : null,
                      ),
                      title: Text('${task.turnpoints[i].name}'
                          '${task.turnpoints[i].type == TurnpointType.none ? '' : ' · ${task.turnpoints[i].type.name.toUpperCase()}'}'),
                      subtitle: Text('${task.turnpoints[i].radiusM.round()} m'
                          '${task.turnpoints[i].description.isEmpty ? '' : ' · ${task.turnpoints[i].description}'}'),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(onPressed: () => _scan(context), icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan QR')),
              FilledButton.tonalIcon(onPressed: () => _file(context), icon: const Icon(Icons.file_open), label: const Text('File')),
              if (task != null) TextButton(onPressed: store.restart, child: const Text('Restart')),
              if (task != null) TextButton(onPressed: store.clear, child: const Text('Remove')),
            ]),
          ]),
        );
      },
    );
  }
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan task QR code')),
        body: MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && v.startsWith('XCTSK')) {
                _done = true;
                Navigator.of(context).pop(v);
                return;
              }
            }
          },
        ),
      );
}
