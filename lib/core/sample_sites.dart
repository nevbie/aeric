import 'site.dart';

// Northern Black Forest takeoffs from the DHV site database (service.dhv.de) and the clubs.
// Coordinates and sectors are approximate. Most sites need club membership/day
// membership and a briefing – always check the club and DHV site guide before flying.

const _loffenau = 'Drachen- und Gleitschirmclub Loffenau (teufels-flieger.de). Both launches are in the forest: '
    'only launch with clear headwind. Landing Loffenau.';
const _oppenau = 'Oppenauer Gleitschirmflieger – four launches around Oppenau cover NE through W wind.';

const blackForestSites = [
  Site(
    id: 'loffenau-west', name: 'Loffenau Teufelsmühle West', lat: 48.7567, lon: 8.4072,
    takeoffElevationM: 890, landingElevationM: 389, landingLat: 48.7727, landingLon: 8.3981,
    sectors: [WindSector(240, 280)], maxWindKmh: 20,
    notes: '$_loffenau West launch on the summit between inn and tower; suitable for beginners.',
  ),
  Site(
    id: 'loffenau-nw', name: 'Loffenau Teufelsmühle Nordwest', lat: 48.7583, lon: 8.4060,
    takeoffElevationM: 834, landingElevationM: 389, landingLat: 48.7727, landingLon: 8.3981,
    sectors: [WindSector(280, 330)], maxWindKmh: 20,
    notes: '$_loffenau Natural ramp below the tower, main direction 304°.',
  ),
  Site(
    id: 'merkur-west', name: 'Merkur West, Baden-Baden', lat: 48.7647, lon: 8.2794,
    takeoffElevationM: 651, landingElevationM: 250, landingLat: 48.7632, landingLon: 8.2619,
    sectors: [WindSector(220, 300)], maxWindKmh: 20,
    notes: 'Gleitschirmverein Baden (Schwarzwaldgeier). Funicular to the top; steep but well levelled launch. Landings West (250 m) and Großmatte (240 m).',
  ),
  Site(
    id: 'merkur-no', name: 'Merkur Nordost, Baden-Baden', lat: 48.7646, lon: 8.2816,
    takeoffElevationM: 660, landingElevationM: 360, landingLat: 48.7669, landingLon: 8.2953,
    sectors: [WindSector(20, 50)], maxWindKmh: 20,
    notes: 'Gleitschirmverein Baden (Schwarzwaldgeier). Launch direction 30°. Landing Nordost above Staufenberg (360 m).',
  ),
  Site(
    id: 'hornisgrinde', name: 'Hornisgrinde Katzenkopf', lat: 48.5969, lon: 8.1962,
    takeoffElevationM: 1123, landingElevationM: 463, landingLat: 48.5901, landingLon: 8.1633,
    sectors: [WindSector(230, 280)], maxWindKmh: 10,
    notes: 'Seebach. DHV: wind 230–280°, max. 10 km/h. Briefing, B licence and day membership required. '
        'Long glide over forest with hardly any emergency landing options.',
  ),
  Site(
    id: 'oppenau-rossbuehl', name: 'Oppenau Rossbühl (SW–W)', lat: 48.4870, lon: 8.2391,
    takeoffElevationM: 930, landingElevationM: 500, landingLat: 48.4797, landingLon: 8.2214,
    sectors: [WindSector(202.5, 292.5)], maxWindKmh: 20,
    notes: '$_oppenau Spacious launch with top-landing; landing Nockenbauernhof.',
  ),
  Site(
    id: 'oppenau-sandkopf', name: 'Oppenau Sandkopf (S)', lat: 48.4965, lon: 8.2328,
    takeoffElevationM: 930, landingElevationM: 500, landingLat: 48.4797, landingLon: 8.2214,
    sectors: [WindSector(157.5, 202.5)], maxWindKmh: 20,
    notes: '$_oppenau Access on foot; landing Nockenbauernhof.',
  ),
  Site(
    id: 'oppenau-schaefersfeld', name: 'Oppenau Schäfersfeld (E–SE)', lat: 48.4357, lon: 8.1520,
    takeoffElevationM: 770, landingElevationM: 305, landingLat: 48.4512, landingLon: 8.1654,
    sectors: [WindSector(67.5, 157.5)], maxWindKmh: 20,
    notes: '$_oppenau Landing Bruhansenhof.',
  ),
  Site(
    id: 'oppenau-ibach', name: 'Oppenau Ibacher Holzplatz (NE)', lat: 48.4475, lon: 8.1460,
    takeoffElevationM: 740, landingElevationM: 305, landingLat: 48.4512, landingLon: 8.1654,
    sectors: [WindSector(22.5, 67.5)], maxWindKmh: 20,
    notes: '$_oppenau Bird protection area: fly only from 2 h after sunrise to 1 h before sunset. Landing Bruhansenhof.',
  ),
];

/// Alpine sites from the first version, kept for trips.
const alpineSites = [
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

const sampleSites = [...blackForestSites, ...alpineSites];

/// Favourites on first start: Loffenau, Merkur, Hornisgrinde and Oppenau.
final defaultFavouriteIds = {for (final s in blackForestSites) s.id};
