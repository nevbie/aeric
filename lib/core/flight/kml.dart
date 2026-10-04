import 'fix.dart';

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// KML for Google Earth: the track in 3D (absolute altitude, extruded to the ground).
String writeKml(List<Fix> fixes, {String name = 'aeric flight'}) {
  final coords = fixes.map((f) => '${f.lon.toStringAsFixed(6)},${f.lat.toStringAsFixed(6)},${f.altM.round()}').join(' ');
  return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document><name>${_esc(name)}</name>
<Style id="track"><LineStyle><color>ff00a5ff</color><width>3</width></LineStyle><PolyStyle><color>4000a5ff</color></PolyStyle></Style>
<Placemark><name>${_esc(name)}</name><styleUrl>#track</styleUrl>
<LineString><extrude>1</extrude><tessellate>1</tessellate><altitudeMode>absolute</altitudeMode>
<coordinates>$coords</coordinates></LineString></Placemark>
</Document></kml>
''';
}
