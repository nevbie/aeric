/// EN/LTF certification class of a paraglider.
enum GliderClass {
  a('EN-A', 36, 1.15),
  b('EN-B', 37.5, 1.08),
  c('EN-C', 39, 1.02),
  d('EN-D', 40, 1.0),
  ccc('CCC', 41, 0.98),
  tandem('Tandem', 36, 1.25);

  const GliderClass(this.label, this.trimKmh, this.trimSinkMs);
  final String label;

  /// Typical trim speed and sink at trim for the class (starting values for the polar).
  final double trimKmh;
  final double trimSinkMs;
}

class GliderModel {
  const GliderModel(this.brand, this.name, this.cls);
  final String brand;
  final String name;
  final GliderClass cls;

  String get fullName => '$brand $name';
}

const _a = GliderClass.a, _b = GliderClass.b, _c = GliderClass.c, _d = GliderClass.d;
const _ccc = GliderClass.ccc, _t = GliderClass.tandem;

/// Popular paragliders of the main brands (current and widely flown recent models).
/// The class is the certification of most sizes – check your glider's manual.
const gliders = <GliderModel>[
  // Advance
  GliderModel('Advance', 'Alpha 8', _a),
  GliderModel('Advance', 'Alpha 8 DLS', _a),
  GliderModel('Advance', 'Epsilon DLS', _b),
  GliderModel('Advance', 'Iota DLS', _b),
  GliderModel('Advance', 'Sigma DLS', _c),
  GliderModel('Advance', 'Omega X-Alps 3', _d),
  GliderModel('Advance', 'Bi Beta 6', _t),
  // Ozone
  GliderModel('Ozone', 'Moxie', _a),
  GliderModel('Ozone', 'Buzz Z7', _b),
  GliderModel('Ozone', 'Vibe GT', _b),
  GliderModel('Ozone', 'Rush 6', _b),
  GliderModel('Ozone', 'Swift 6', _b),
  GliderModel('Ozone', 'Alpina 4', _c),
  GliderModel('Ozone', 'Delta 5', _c),
  GliderModel('Ozone', 'Zeno 2', _d),
  GliderModel('Ozone', 'Enzo 3', _ccc),
  GliderModel('Ozone', 'Magnum 4', _t),
  // Gin
  GliderModel('Gin', 'Bolero 7', _a),
  GliderModel('Gin', 'Atlas 3', _b),
  GliderModel('Gin', 'Evora', _b),
  GliderModel('Gin', 'Explorer 2', _b),
  GliderModel('Gin', 'Camino', _b),
  GliderModel('Gin', 'Bonanza 3', _c),
  GliderModel('Gin', 'Leopard', _d),
  GliderModel('Gin', 'Boomerang 13', _ccc),
  // Nova
  GliderModel('Nova', 'Aonic', _a),
  GliderModel('Nova', 'Prion 6', _a),
  GliderModel('Nova', 'Ion 7', _b),
  GliderModel('Nova', 'Mentor 7', _b),
  GliderModel('Nova', 'Codex', _c),
  GliderModel('Nova', 'Vortex', _c),
  GliderModel('Nova', 'Xenon', _d),
  GliderModel('Nova', 'Bion 3', _t),
  // Skywalk
  GliderModel('Skywalk', 'Mescal 6', _a),
  GliderModel('Skywalk', 'Tequila 6', _b),
  GliderModel('Skywalk', 'Chili 6', _b),
  GliderModel('Skywalk', 'Cayenne 6', _c),
  GliderModel('Skywalk', 'Poison 4', _d),
  GliderModel('Skywalk', 'X-Alps 6', _d),
  GliderModel('Skywalk', "Join't 3", _t),
  // Niviuk
  GliderModel('Niviuk', 'Wilko', _a),
  GliderModel('Niviuk', 'Koyot 6', _a),
  GliderModel('Niviuk', 'Hook 6', _b),
  GliderModel('Niviuk', 'Artik R 2', _c),
  GliderModel('Niviuk', 'Peak 6', _d),
  GliderModel('Niviuk', 'Icepeak X-One', _ccc),
  GliderModel('Niviuk', 'Takoo 6', _t),
  // UP
  GliderModel('UP', 'Rimo 2', _a),
  GliderModel('UP', 'Makalu 5', _b),
  GliderModel('UP', 'Lhotse X', _b),
  GliderModel('UP', 'Kantega XC4', _b),
  GliderModel('UP', 'Torre', _c),
  // Phi
  GliderModel('Phi', 'Viola 2', _a),
  GliderModel('Phi', 'Symphonia 2', _b),
  GliderModel('Phi', 'Maestro 3', _b),
  GliderModel('Phi', 'Allegro 2', _c),
  GliderModel('Phi', 'Scala 2 Light', _d),
  GliderModel('Phi', 'Rondo', _t),
  // Swing
  GliderModel('Swing', 'Verso RS', _a),
  GliderModel('Swing', 'Nyra RS', _b),
  GliderModel('Swing', 'Serac RS', _b),
  GliderModel('Swing', 'Nyos RS', _b),
  GliderModel('Swing', 'Agera RS', _c),
  // BGD
  GliderModel('BGD', 'Adam 2', _a),
  GliderModel('BGD', 'Base 3', _b),
  GliderModel('BGD', 'Echo 2', _b),
  GliderModel('BGD', 'Lynx 2', _b),
  GliderModel('BGD', 'Cure 3', _c),
  GliderModel('BGD', 'Dual 2', _t),
  // Gradient
  GliderModel('Gradient', 'Bright 5', _a),
  GliderModel('Gradient', 'Nevada 2', _b),
  GliderModel('Gradient', 'Aspen 7', _c),
  GliderModel('Gradient', 'Bi Golden 5', _t),
  // Mac Para
  GliderModel('Mac Para', 'Muse 6', _a),
  GliderModel('Mac Para', 'Eden 7', _b),
  GliderModel('Mac Para', 'Elan 3', _c),
  // AirDesign
  GliderModel('AirDesign', 'Vivo 2', _a),
  GliderModel('AirDesign', 'Rise 5', _b),
  GliderModel('AirDesign', 'SuSi XPed', _c),
  GliderModel('AirDesign', 'Hero XPed', _d),
  // Supair
  GliderModel('Supair', 'Leaf 2', _b),
  GliderModel('Supair', 'Savage 2', _c),
  // Triple Seven
  GliderModel('Triple Seven', 'Pawn 2', _a),
  GliderModel('Triple Seven', 'Rook 3', _b),
  GliderModel('Triple Seven', 'Knight 2', _b),
  GliderModel('Triple Seven', 'Queen 3', _c),
];

List<String> get gliderBrands => {for (final g in gliders) g.brand}.toList();

/// Search by brand or model name (case-insensitive, all words must match).
List<GliderModel> searchGliders(String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return gliders;
  return gliders.where((g) {
    final hay = '${g.fullName} ${g.cls.label}'.toLowerCase();
    return words.every(hay.contains);
  }).toList();
}
