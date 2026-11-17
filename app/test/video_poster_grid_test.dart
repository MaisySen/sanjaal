// Visual contract fixtures only. No live/native thumbnail extraction.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
void main() {
  setUpAll(() async {
    for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]) {
      final l=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(File(p.$2).readAsBytesSync())));await l.load();
    }
  });
  for(final lang in ['en','ne']) { for(final mode in [Brightness.light,Brightness.dark]) {
    testWidgets('profile uses real poster URL and nonblank legacy fallback $lang ${mode.name}',(t) async {
      SharedPreferences.setMockInitialValues({});prefs.lang=lang;addTearDown(()=>prefs.lang='en');
      t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
      final seen=<String>[];
      final rec=ui.PictureRecorder();final c=Canvas(rec);
      c.drawRect(const Rect.fromLTWH(0,0,240,360),Paint()..color=const Color(0xFF173B52));
      c.drawCircle(const Offset(175,80),32,Paint()..color=const Color(0xFFDAB581));
      c.drawPath(Path()..moveTo(0,360)..lineTo(100,160)..lineTo(240,360)..close(),Paint()..color=const Color(0xFF39717E));
      final picture=rec.endRecording();
      final bytes=(await t.runAsync(() async { final image=await picture.toImage(240,360);return (await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List(); }))!;
      feedImageProvider=(url){seen.add(url);return MemoryImage(bytes);};addTearDown(()=>feedImageProvider=null);
      await http.runWithClient(() async {
        final s=Session();await s.login('fixture','fixture');
        await t.pumpWidget(RepaintBoundary(key:const ValueKey('poster-grid'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto'),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:const TextScaler.linear(1.8)),child:w!),home:Scaffold(appBar:AppBar(title:const Text('@fixture')),body:FeedList(session:s,query:const {},grid:true)))));
        for(var i=0;i<5;i++) { await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));await t.pumpAndSettle(); }
        expect(seen,contains('https://fixture.invalid/poster.jpg'));
        expect(seen,contains('https://fixture.invalid/photo.jpg'));
        expect(seen, isNot(contains('https://fixture.invalid/clip.mp4')));
        expect(find.bySemanticsLabel(t_('Video preview unavailable')),findsOneWidget);
        expect(t.takeException(),isNull);
        await t.runAsync(() async {
          final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('poster-grid')));final im=await b.toImage(pixelRatio:2);final data=await im.toByteData(format:ui.ImageByteFormat.png);
          File('test/renders/video_poster_grid_${lang}_${mode.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox());await t.pump();
      },()=>MockClient((r) async {
        if(r.url.path.endsWith('/oauth/token'))return http.Response(jsonEncode({'access_token':'fixture','expires_in':3600}),200);
        if(r.url.path.endsWith('/auth/me'))return http.Response(jsonEncode({'user':{'public_id':'fixture'}}),200);
        return http.Response(jsonEncode({'data':[
          {'public_id':'poster','kind':'reel','body':null,'media':[{'type':'video','url':'https://fixture.invalid/clip.mp4','thumbnail_url':'https://fixture.invalid/poster.jpg'}]},
          {'public_id':'legacy','kind':'reel','body':null,'media':[{'type':'video','url':'https://fixture.invalid/legacy.mp4'}]},
          {'public_id':'photo','kind':'post','body':'Photo','media':[{'type':'image','url':'https://fixture.invalid/photo.jpg'}]},
        ],'next_cursor':null}),200);
      }));
    });
  }}
}
