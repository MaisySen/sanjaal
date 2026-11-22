import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/glass/glass_settings.dart';
import 'package:sanjaal/glass/glass_surface.dart';
import 'package:sanjaal/glass/glass_sheet.dart';

void main() {
  testWidgets('nav responds to local tint changes without reconstruction', (t) async {
    SharedPreferences.setMockInitialValues({});
    await glassSettings.setReduced(false);
    await glassSettings.setTransparency(0);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: GlassNavBar(items: const [NavItem('Home','house','house-fill')], index: 0, onSelected: (_) {}))));
    double opacity() => t.widget<GlassSurface>(find.byType(GlassSurface)).opacity!;
    expect(opacity(), closeTo(.22, .001));
    await glassSettings.setTransparency(1);
    await t.pumpAndSettle();
    expect(opacity(), closeTo(.48, .001));
    await glassSettings.setTransparency(.5);
  });
  for (final dismissible in [false,true]) {
    testWidgets('sheet preserves dismissal policy $dismissible', (t) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showReviewedGlassSheet<void>(context:c,isDismissible:dismissible,enableDrag:dismissible,builder: (_) => const SizedBox(height:200,child:Text('Sheet contents'))),child:const Text('Open'))))));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      final sheet = t.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.enableDrag,dismissible);
      await t.tapAt(const Offset(20,20));
      await t.pumpAndSettle();
      expect(find.text('Sheet contents'),dismissible ? findsNothing : findsOneWidget);
      expect(t.takeException(),isNull);
    });
  }
}
