import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/airspace.dart';
import '../core/open_meteo.dart';
import 'http.dart';

/// The pilot's airspace file (OpenAIR), stored on the device.
class AirspaceStore extends ChangeNotifier {
  AirspaceStore({Future<Directory> Function()? dir, HttpGet? get})
      : _dirFn = dir ?? (() async => getApplicationDocumentsDirectory()),
        _get = get;
  static final instance = AirspaceStore();

  final Future<Directory> Function() _dirFn;
  final HttpGet? _get;
  List<Airspace> airspaces = const [];
  String? source;
  String? error;
  bool loaded = false;

  Future<File> get _file async => File('${(await _dirFn()).path}/airspace.openair');

  Future<void> load() async {
    if (loaded) return;
    loaded = true;
    try {
      final f = await _file;
      if (f.existsSync()) {
        airspaces = parseOpenAir(await f.readAsString());
        source = 'saved file';
      }
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  /// Replaces the airspaces with an OpenAIR text; returns how many were found.
  Future<int> importText(String text, {required String from}) async {
    final parsed = parseOpenAir(text);
    if (parsed.isEmpty) {
      error = 'No airspaces found in $from (is it an OpenAIR file?)';
      notifyListeners();
      return 0;
    }
    await (await _file).writeAsString(text);
    airspaces = parsed;
    source = from;
    error = null;
    notifyListeners();
    return parsed.length;
  }

  Future<int> importBytes(List<int> bytes, {required String from}) =>
      importText(utf8.decode(bytes, allowMalformed: true), from: from);

  Future<int> download(String url) async {
    try {
      return await importText(await (_get ?? networkGet())(Uri.parse(url.trim())), from: url.trim());
    } catch (e) {
      error = 'Download failed: $e';
      notifyListeners();
      return 0;
    }
  }

  Future<void> clear() async {
    final f = await _file;
    if (f.existsSync()) await f.delete();
    airspaces = const [];
    source = null;
    notifyListeners();
  }
}
