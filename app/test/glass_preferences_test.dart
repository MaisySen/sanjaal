import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/glass/glass_settings.dart';
import 'package:sanjaal/glass/glass_surface.dart';
import 'package:sanjaal/main.dart' show buildTheme;

void main() {
  test('glass preferences clamp, persist and restore locally', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = GlassSettings();
    await settings.setTransparency(2);
    await settings.setReduced(true);
    final restored = GlassSettings();
    await restored.load();
    expect(restored.transparency, 1);
    expect(restored.reduced, true);
    await restored.setTransparency(-1);
    expect(restored.transparency, 0);
  });
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('glass keeps tint independent and becomes opaque on request ${b.name}', (t) async {
      SharedPreferences.setMockInitialValues({});
      await glassSettings.setTransparency(0);
      await glassSettings.setReduced(false);
      Future<void> show() => t.pumpWidget(MaterialApp(theme:buildTheme(b),home:const Scaffold(body:GlassSurface(child:SizedBox(width:200,height:100,child:Text('Text'))))));
      await show();
      expect(find.byType(BackdropFilter),findsOneWidget);
      final fill = t.widget<ColoredBox>(find.descendant(of:find.byType(GlassSurface),matching:find.byType(ColoredBox)).first).color;
      expect(fill.a, closeTo(b == Brightness.light ? .55 : .70, .005));
      final c = t.element(find.text('Text'));
      expect(Theme.of(c).colorScheme.onSurfaceVariant, Theme.of(c).colorScheme.onSurface);
      await glassSettings.setReduced(true);
      await t.pump();
      expect(find.byType(BackdropFilter),findsNothing);
      await glassSettings.setReduced(false);
      await glassSettings.setTransparency(.5);
    });
  }
}
