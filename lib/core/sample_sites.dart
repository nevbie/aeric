import 'site.dart';

/// Starter sites so the app is useful out of the box. Coordinates/orientations are approximate –
/// always check the local club/DHV site guide before flying.
const sampleSites = [
  Site(
    id: 'tegelberg', name: 'Tegelberg (DE)', lat: 47.5600, lon: 10.7740,
    takeoffElevationM: 1720, landingElevationM: 800,
    sectors: [WindSector(270, 360)],
  ),
  Site(
    id: 'wallberg', name: 'Wallberg (DE)', lat: 47.6620, lon: 11.7950,
    takeoffElevationM: 1620, landingElevationM: 780,
    sectors: [WindSector(315, 45)],
  ),
  Site(
    id: 'brauneck', name: 'Brauneck (DE)', lat: 47.6640, lon: 11.5180,
    takeoffElevationM: 1500, landingElevationM: 700,
    sectors: [WindSector(135, 225)],
  ),
  Site(
    id: 'kossen', name: 'Kössen Unterberg (AT)', lat: 47.6510, lon: 12.4180,
    takeoffElevationM: 1450, landingElevationM: 590,
    sectors: [WindSector(270, 340)],
  ),
  Site(
    id: 'greifenburg', name: 'Greifenburg Emberger Alm (AT)', lat: 46.7660, lon: 13.1630,
    takeoffElevationM: 1780, landingElevationM: 600,
    sectors: [WindSector(135, 225)],
  ),
];
