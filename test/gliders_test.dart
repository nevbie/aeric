import 'package:aeric/core/gliders.dart';
import 'package:aeric/services/settings.dart';
import 'package:aeric/ui/glider_picker.dart';
import 'package:aeric/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('glider list: unique models, every class present, popular brands covered', () {
    expect(gliders.map((g) => g.fullName).toSet(), hasLength(gliders.length));
    for (final c in GliderClass.values) {
      expect(gliders.any((g) => g.cls == c), isTrue, reason: c.label);
    }
    for (final b in ['Advance', 'Ozone', 'Gin', 'Nova', 'Skywalk', 'Niviuk', 'UP', 'Phi', 'Swing', 'BGD']) {
      expect(gliders.where((g) => g.brand == b).length, greaterThanOrEqualTo(4), reason: b);
    }
    // Faster, flatter-gliding polar with higher class (tandem aside).
    expect(GliderClass.d.trimKmh, greaterThan(GliderClass.a.trimKmh));
    expect(GliderClass.d.trimSinkMs, lessThan(GliderClass.a.trimSinkMs));
  });

  test('search', () {
    expect(searchGliders('').length, gliders.length);
    expect(searchGliders('iota').single.fullName, 'Advance Iota DLS');
    expect(searchGliders('ozone en-b').every((g) => g.brand == 'Ozone' && g.cls == GliderClass.b), isTrue);
    expect(searchGliders('nothing like this'), isEmpty);
  });

  testWidgets('Schirm wählen sets glider, class and polar', (tester) async {
    await Settings.instance.load();
    await tester.binding.setSurfaceSize(const Size(340, 800));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    expect(find.text('aeric'), findsOneWidget); // logo header
    await tester.tap(find.text('Schirm wählen'));
    await tester.pumpAndSettle();
    expect(find.byType(GliderPickerScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'chili');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skywalk Chili 6'));
    await tester.pumpAndSettle();
    final st = Settings.instance;
    expect(st.glider, 'Skywalk Chili 6');
    expect(st.gliderClass, 'EN-B');
    expect(st.trimKmh, GliderClass.b.trimKmh);
    expect(find.text('Skywalk Chili 6'), findsOneWidget); // back on settings
    final p = await SharedPreferences.getInstance();
    expect(p.getString('glider'), 'Skywalk Chili 6');
  });
}
