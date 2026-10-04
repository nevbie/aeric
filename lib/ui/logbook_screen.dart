import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/flight/igc.dart';
import '../core/flight/kml.dart';
import '../core/geo.dart';
import '../services/app_state.dart';
import '../services/flight_controller.dart';
import '../services/logbook.dart';
import 'common.dart';

String _dur(Duration d) => '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')} h';

/// Logbook: recorded and imported flights with statistics, thermals and their weather.
class LogbookScreen extends StatefulWidget {
  const LogbookScreen({super.key});

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  final book = Logbook.instance;

  @override
  void initState() {
    super.initState();
    book.load();
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['igc', 'zip']);
    if (picked.isEmpty) return;
    final files = <(String, Uint8List)>[];
    for (final f in picked) {
      files.add((f.name, await f.xFile.readAsBytes()));
    }
    await book.importFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final e = book.entries;
        final airtime = e.fold(Duration.zero, (a, x) => a + x.airtime);
        final thermals = e.fold(0, (a, x) => a + x.thermals.length);
        return Column(children: [
          ListTile(
            title: Text('${e.length} flights · ${_dur(airtime)}'),
            subtitle: Text('$thermals thermals found – shown as "My thermals" on the map'),
            trailing: book.busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton.tonalIcon(onPressed: _import, icon: const Icon(Icons.file_open), label: const Text('Import IGC')),
          ),
          if (book.message != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(book.message!)),
          const Divider(height: 1),
          Expanded(
            child: e.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No flights yet. Record one on the Flight tab, or import IGC files – e.g. the ZIP from '
                      'XContest → My flights → Download: IGC.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(children: [for (final x in e) _EntryTile(x)]),
          ),
        ]);
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.e);
  final LogEntry e;

  Future<void> _share(BuildContext context, {required bool kml}) async {
    final igc = await Logbook.instance.readIgc(e);
    if (igc == null) return;
    final name = 'aeric-${e.id}.${kml ? 'kml' : 'igc'}';
    final data = kml ? writeKml(parseIgc(igc).fixes, name: e.siteName ?? name) : igc;
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(Uint8List.fromList(utf8.encode(data)), name: name, mimeType: kml ? 'application/vnd.google-earth.kml+xml' : 'text/plain')],
      fileNameOverrides: [name],
    ));
  }

  Future<void> _replay(BuildContext context) async {
    final igc = await Logbook.instance.readIgc(e);
    if (igc == null) return;
    AppState.instance.setTab(3);
    await FlightController.instance.startReplay(parseIgc(igc));
  }

  @override
  Widget build(BuildContext context) {
    final local = e.takeoff.toLocal();
    final small = Theme.of(context).textTheme.bodySmall;
    return ExpansionTile(
      leading: Icon(e.source == 'recorded' ? Icons.paragliding : Icons.file_download_done),
      title: Text('${local.day}.${local.month}.${local.year} · ${e.siteName ?? 'Unknown site'}'),
      subtitle: Text('${_dur(e.airtime)} · ${e.trackKm.toStringAsFixed(1)} km · max ${e.maxAltM.round()} m · '
          '↑${e.maxClimbMs.toStringAsFixed(1)} m/s · ${e.thermals.length} thermals'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Takeoff ${hhmm(local)} · landing ${hhmm(e.landing.toLocal())} · furthest ${e.maxFromTakeoffKm.toStringAsFixed(1)} km from takeoff',
            style: small),
        const SizedBox(height: 6),
        for (final t in e.thermals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(children: [
              Dot(climbColor(t.spot.avgClimbMs), size: 10),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${hhmm(t.spot.start.toLocal())} · ${t.spot.avgClimbMs.toStringAsFixed(1)} m/s · '
                  '+${t.spot.gainM.round()} m to ${t.spot.topAltM.round()} m'
                  '${t.condition == null ? ' · weather pending' : ' · wind ${t.condition!.windKmh.round()} km/h ${compass(t.condition!.windFromDeg)}'
                      '${t.condition!.cloudCover == null ? '' : ', ☁${t.condition!.cloudCover!.round()} %'}'}',
                  style: small,
                ),
              ),
            ]),
          ),
        Wrap(spacing: 4, children: [
          TextButton.icon(onPressed: () => _replay(context), icon: const Icon(Icons.play_arrow), label: const Text('Replay')),
          TextButton.icon(onPressed: () => _share(context, kml: false), icon: const Icon(Icons.share), label: const Text('IGC')),
          TextButton.icon(onPressed: () => _share(context, kml: true), icon: const Icon(Icons.public), label: const Text('Google Earth')),
          TextButton.icon(
            onPressed: () => Logbook.instance.delete(e),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ]),
      ],
    );
  }
}
