// Synthetic cold-start fixtures only. These are not Samsung acceptance evidence.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/refresh_store.dart';
import 'package:sanjaal/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds:50)));
  await t.pumpAndSettle();
}
void main() {
  setUpAll(() async {
    for (final f in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]) {
      final loader = FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())));
      await loader.load();
    }
  });
  testWidgets('root shows startup retry rather than auth; explicit grant rejection then opens auth', (t) async {
    SharedPreferences.setMockInitialValues({'onboarded':true});
    FlutterSecureStorage.setMockInitialValues({'refresh_token':'saved-fixture'});
    var reads = 0;
    await http.runWithClient(() async {
      await t.pumpWidget(const SanjaalApp()); await flush(t);
      expect(find.byType(RestoreSessionPage),findsOneWidget);
      expect(find.byType(AuthPage),findsNothing);
      expect(await RefreshStore.read(),'saved-fixture');
      await t.tap(find.text('Try again')); await flush(t);
      expect(reads,2); expect(find.byType(RestoreSessionPage),findsNothing);
      expect(find.byType(AuthPage),findsOneWidget);
      expect(await RefreshStore.read(),isNull);
      await t.pumpWidget(const SizedBox()); await flush(t);
    }, () => MockClient((_) async {
      reads++;
      return reads == 1 ? http.Response('unavailable',503) : http.Response(jsonEncode({'error':'invalid_grant'}),400);
    }));
  });
  for (final lang in ['en','ne']) {
    for (final mode in [Brightness.light,Brightness.dark]) {
      for (final scale in [1.0,1.8]) {
        testWidgets('retry screen readable and scrollable $lang ${mode.name} $scale', (t) async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({'refresh_token':'saved-fixture'});
          prefs.lang=lang; addTearDown(()=>prefs.lang='en');
          t.view.physicalSize=const Size(320,640); t.view.devicePixelRatio=1; addTearDown(t.view.reset);
          await http.runWithClient(() async {
            final s=Session(); await s.restore();
            await t.pumpWidget(RepaintBoundary(key:const ValueKey('restore-render'),child:MaterialApp(
              debugShowCheckedModeBanner:false,
              theme:buildTheme(mode,fontFamily:'Roboto'),
              builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!),
              home:RestoreSessionPage(session:s),
            ))); await flush(t);
            final retry=find.widgetWithText(OutlinedButton,t_('Try again'));
            await t.ensureVisible(retry); await t.pumpAndSettle();
            expect(t.getRect(retry).bottom,lessThanOrEqualTo(640));
            expect(t.getRect(retry).height,greaterThanOrEqualTo(48));
            expect(t.takeException(),isNull);
            await t.runAsync(() async {
              final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('restore-render')));
              final image=await b.toImage(pixelRatio:2); final data=await image.toByteData(format:ui.ImageByteFormat.png);
              File('test/renders/restore_${lang}_${mode.name}_$scale.png').writeAsBytesSync(data!.buffer.asUint8List());
            });
            await t.pumpWidget(const SizedBox()); await flush(t);
          },()=>MockClient((_) async=>http.Response('unavailable',503)));
        });
      }
    }
  }
}
