// In-memory draft safety and explicit story publication. Synthetic API/files only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;
import 'package:shared_preferences/shared_preferences.dart';

late Uint8List photo;
http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
Future<void> flush(WidgetTester t) async { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30))); await t.pumpAndSettle(); }
Future<void> fixture(WidgetTester t, Widget Function(Session) page, Future<void> Function() run, {Future<http.Response> Function(http.Request)? respond, Brightness brightness = Brightness.light, double scale = 1, String language = 'en', bool intents = true}) async {
  SharedPreferences.setMockInitialValues({});
  prefs.lang = language; addTearDown(() => prefs.lang = 'en');
  await http.runWithClient(() async {
    final s = Session(); await s.login('fixture','not-a-password');
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('review'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(brightness, fontFamily: 'Roboto', fontFamilyFallback: ['NotoDev']), builder: (c,w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!), home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => page(s))), child: const Text('Create fixture')))))));
    await t.tap(find.text('Create fixture')); await flush(t);
    await run();
    await t.pumpWidget(const SizedBox()); await t.pump(const Duration(seconds: 1));
  }, () => MockClient((r) async {
    if (r.url.path.endsWith('/oauth/token')) return json({'access_token':'fixture','expires_in':3600});
    if (r.url.path.endsWith('/auth/me')) return json({'features':{'polls':true,'upload_intents':intents},'user':{'public_id':'me','username':'fixture'}});
    return respond == null ? json({}) : respond(r);
  }));
}
Widget story(Session s) => StoryComposePage(session:s, file:XFile.fromData(photo,path:'/fixture.png',name:'fixture.png',mimeType:'image/png'), isVideo:false);
Future<void> shot(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('review')));
    final image = await b.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('test/renders').createSync(recursive: true);
    File('test/renders/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
void main() {
  setUpAll(() async {
    final f = File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    if (f.existsSync()) { final loader=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync()))); await loader.load(); }
    final icons=File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) { final loader=FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))); await loader.load(); }
    final ne=File('assets/fonts/NotoSansDevanagari.ttf');
    final neloader=FontLoader('NotoDev')..addFont(Future.value(ByteData.sublistView(ne.readAsBytesSync()))); await neloader.load();
    final rec=ui.PictureRecorder(); final canvas=Canvas(rec);
    canvas.drawRect(const Rect.fromLTWH(0,0,400,600),Paint()..shader=ui.Gradient.linear(Offset.zero,const Offset(0,600), const [Color(0xFF16254F),Color(0xFFD9708A),Color(0xFFF2B77A)],const [0,0.6,1]));
    canvas.drawPath(Path()..moveTo(0,500)..lineTo(120,240)..lineTo(220,380)..lineTo(310,200)..lineTo(400,500)..lineTo(400,600)..lineTo(0,600)..close(),Paint()..color=const Color(0xFF1B1F2A));
    final image=await rec.endRecording().toImage(400,600); photo=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  testWidgets('empty post can leave without a discard prompt', (t) async {
    await fixture(t,(s)=>ComposePage(session:s),() async {
      await t.pageBack(); await t.pumpAndSettle(); expect(find.byType(ComposePage),findsNothing); expect(find.text('Discard this draft?'),findsNothing);
    });
  });
  testWidgets('back preserves text and poll unless discard is explicit', (t) async {
    await fixture(t,(s)=>ComposePage(session:s),() async {
      await t.enterText(find.byType(TextField),'A draft question'); await t.tap(find.text('Poll')); await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField,'Option 1'),'Saturday');
      await t.binding.handlePopRoute(); await t.pumpAndSettle(); expect(find.text('Discard this draft?'),findsOneWidget);
      await t.tap(find.text('Keep editing')); await t.pumpAndSettle(); expect(find.text('A draft question'),findsOneWidget); expect(find.text('Saturday'),findsOneWidget);
      await t.pageBack(); await t.pumpAndSettle(); await t.tap(find.text('Discard')); await t.pumpAndSettle();
      expect(find.byType(ComposePage),findsNothing);
    },respond:(_)async=>throw StateError('Leaving must not upload'));
  });
  testWidgets('post cannot disappear during upload and returns only after success', (t) async {
    final pending=Completer<http.Response>(); var writes=0;
    await fixture(t,(s)=>ComposePage(session:s),() async {
      await t.enterText(find.byType(TextField),'Uploading draft'); await t.tap(find.widgetWithText(FilledButton,'Post')); await t.pump();
      await t.binding.handlePopRoute(); await t.pump(); expect(find.byType(ComposePage),findsOneWidget); expect(t.widget<TextField>(find.byType(TextField)).enabled,isFalse);
      pending.complete(json({'post':{'public_id':'p'}})); await flush(t); expect(writes,1); expect(find.byType(ComposePage),findsNothing); expect(find.text('Discard this draft?'),findsNothing);
    },respond:(_) {writes++;return pending.future;});
  });
  testWidgets('story selection waits for share; failure retains file and caption for retry', (t) async {
    var writes=0; final bodies=<String>[];
    await fixture(t,story,() async {
      expect(writes,0); expect(find.byType(Image),findsOneWidget); await t.enterText(find.byType(TextField),'A caption worth keeping');
      await t.tap(find.text('Share story')); await flush(t); expect(find.text('Fixture offline'),findsOneWidget); expect(find.text('A caption worth keeping'),findsOneWidget);
      await t.tap(find.text('Try again')); await flush(t); expect(writes,2); expect(bodies, everyElement(contains('A caption worth keeping'))); expect(bodies, everyElement(contains('image/png'))); expect(find.byType(StoryComposePage),findsNothing);
    },respond:(r)async {bodies.add(latin1.decode(r.bodyBytes));return ++writes==1?json({'message':'Fixture offline'},503):json({'story':{}},201);});
  });
  testWidgets('leaving a reviewed story requires discard and never uploads', (t) async {
    await fixture(t,story,() async {
      await t.pageBack(); await t.pumpAndSettle(); await t.tap(find.text('Keep editing')); await t.pumpAndSettle(); expect(find.byType(StoryComposePage),findsOneWidget);
      await t.pageBack(); await t.pumpAndSettle(); await t.tap(find.text('Discard')); await t.pumpAndSettle(); expect(find.byType(StoryComposePage),findsNothing);
    },respond:(_)async=>throw StateError('Discard must not upload'));
  });

  testWidgets('response lost after post commit retries the same intent and returns the original', (t) async {
    final keys=<String>[]; var created=0;
    await fixture(t,(s)=>ComposePage(session:s),() async {
      await t.enterText(find.byType(TextField),'A retry-safe post');
      await t.tap(find.widgetWithText(FilledButton,'Post')); await flush(t);
      expect(find.text('Upload interrupted. Your draft is kept. Retry to check the original result.'),findsOneWidget);
      await t.tap(find.text('Try again')); await flush(t);
      expect(keys.length,2); expect(keys[0],isNotEmpty); expect(keys[1],keys[0]); expect(created,1);
      expect(find.byType(ComposePage),findsNothing);
    },respond:(r)async {
      final body=latin1.decode(r.bodyBytes);
      final key=RegExp(r'name="upload_intent"\r\n\r\n([^\r]+)').firstMatch(body)!.group(1)!;
      keys.add(key);
      if(keys.length==1) {created++;throw const SocketException('fixture lost response after commit');}
      return json({'post':{'public_id':'original'},'replayed':true});
    });
  });
  testWidgets('story response loss retries the original key and keeps caption bytes', (t) async {
    final keys=<String>[];
    await fixture(t,story,() async {
      await t.enterText(find.byType(TextField),'Original caption'); await t.tap(find.text('Share story')); await flush(t);
      expect(find.text('Original caption'),findsOneWidget);
      await t.tap(find.text('Try again')); await flush(t); expect(keys.length,2); expect(keys[0],keys[1]); expect(find.byType(StoryComposePage),findsNothing);
    },respond:(r)async {
      final body=latin1.decode(r.bodyBytes); expect(body,contains('Original caption'));
      keys.add(RegExp(r'name="upload_intent"\r\n\r\n([^\r]+)').firstMatch(body)!.group(1)!);
      if(keys.length==1) throw const SocketException('fixture lost response');
      return json({'story':{'public_id':'original'},'replayed':true});
    });
  });
  testWidgets('changed draft conflict preserves edits and requires explicit new preparation before a new send', (t) async {
    final keys=<String>[];
    await fixture(t,(s)=>ComposePage(session:s),() async {
      await t.enterText(find.byType(TextField),'Original'); await t.tap(find.widgetWithText(FilledButton,'Post')); await flush(t);
      await t.enterText(find.byType(TextField),'Edited draft'); await t.tap(find.text('Try again')); await flush(t);
      expect(find.text('Open original'),findsOneWidget); expect(find.text('Edited draft'),findsOneWidget);
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Post')).onPressed,isNull);
      await t.tap(find.text('Prepare a new post')); await t.pumpAndSettle(); await t.tap(find.text('Prepare new upload')); await t.pumpAndSettle(); expect(keys.length,2,reason:'preparation alone cannot send');
      await t.tap(find.widgetWithText(FilledButton,'Post')); await flush(t);
      expect(keys[0],keys[1]); expect(keys[2],isNot(keys[0]));
    },respond:(r)async {
      keys.add(RegExp(r'name="upload_intent"\r\n\r\n([^\r]+)').firstMatch(latin1.decode(r.bodyBytes))!.group(1)!);
      if(keys.length==1) throw const SocketException('fixture lost response');
      if(keys.length==2) return json({'message':'Original already exists','code':'upload_intent_conflict','resource_id':'original'},409);
      return json({'post':{'public_id':'new'}});
    });
  });
  testWidgets('old API transport ambiguity blocks ordinary retry and sends no unsupported intent', (t) async {
    var writes=0;
    await fixture(t,story,() async {
      await t.tap(find.text('Share story')); await flush(t);
      expect(find.text('The upload result is unknown. Check your posts or stories before sharing again.'),findsOneWidget);
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
      expect(writes,1);
    },intents:false,respond:(r)async {writes++;expect(latin1.decode(r.bodyBytes),isNot(contains('upload_intent')));throw const SocketException('fixture unknown');});
  });
  testWidgets('removed or expired upload never retries the same terminal intent automatically', (t) async {
    var writes=0;
    await fixture(t,story,() async {
      await t.tap(find.text('Share story')); await flush(t); expect(writes,1);
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
      await t.tap(find.text('Prepare a new story')); await t.pumpAndSettle(); await t.tap(find.text('Prepare new upload')); await t.pumpAndSettle(); expect(writes,1); expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
    },respond:(r)async {writes++;return json({'message':'Original expired','code':'upload_intent_gone'},410);});
  });


  testWidgets('malformed success is ambiguous and does not turn a legacy retry into a second send', (t) async {
    var writes=0;
    await fixture(t,(s)=>ComposePage(session:s),() async {
      await t.enterText(find.byType(TextField),'An unconfirmed upload');
      await t.tap(find.widgetWithText(FilledButton,'Post')); await flush(t);
      expect(find.byType(ComposePage),findsOneWidget); expect(find.text('The upload result is unknown. Check your posts or stories before sharing again.'),findsOneWidget);
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Post')).onPressed,isNull); expect(writes,1);
    },intents:false,respond:(_)async {writes++;return http.Response('<html>proxy page</html>',200);});
  });
  testWidgets('new-upload preparation can be cancelled without changing the old terminal intent', (t) async {
    var writes=0;
    await fixture(t,story,() async {
      await t.tap(find.text('Share story')); await flush(t);
      await t.tap(find.text('Prepare a new story')); await t.pumpAndSettle(); await t.tap(find.text('Cancel')); await t.pumpAndSettle();
      expect(writes,1); expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    },respond:(_)async {writes++;return json({'message':'Gone','code':'upload_intent_gone'},410);});
  });
  testWidgets('story conflict opens the current original without sending the edited draft', (t) async {
    var writes=0;
    await fixture(t,story,() async {
      await t.tap(find.text('Share story')); await flush(t);
      await t.tap(find.text('Open original')); await flush(t);
      expect(find.byType(StoryViewer),findsOneWidget); expect(writes,1);
    },respond:(r)async {
      if(r.method=='POST') {
        if(r.url.path.endsWith('/view')) return json({});
        writes++;return json({'message':'Original already exists','code':'upload_intent_conflict','resource_id':'original'},409);
      }
      return json({'data':[{'author':{'username':'fixture'},'items':[{'public_id':'original','type':'image','url':'https://fixture.invalid/photo','created_at':'2026-11-17T00:00:00Z','caption':'Original caption'}]}]});
    });
  });
  for (final b in [Brightness.light,Brightness.dark]) {
    for (final lang in ['en','ne']) {
    for (final isStory in [false,true]) {
      testWidgets('upload conflict layout ${b.name} story=$isStory $lang small large-text and keyboard inset', (t) async {
        t.view.physicalSize=const Size(960,1920); t.view.devicePixelRatio=3; addTearDown(t.view.reset);
        await fixture(t,isStory?story:(s)=>ComposePage(session:s),() async {
          if(!isStory) await t.enterText(find.byType(TextField),'An edited draft worth keeping');
          await t.tap(find.text(t_(isStory?'Share story':'Post'))); await flush(t);
          expect(find.text(t_('Open original')),findsOneWidget);
          await shot(t,'upload_conflict_${isStory?'story':'post'}_${b.name}_$lang');
          t.view.viewInsets=const FakeViewPadding(bottom:720); await t.pumpAndSettle();
          expect(t.takeException(),isNull);
          await shot(t,'upload_conflict_keyboard_${isStory?'story':'post'}_${b.name}_$lang');
          t.view.viewInsets=const FakeViewPadding(); await t.pumpAndSettle();
          await t.tap(find.text(t_(isStory?'Prepare a new story':'Prepare a new post'))); await t.pumpAndSettle();
          expect(t.takeException(),isNull); await shot(t,'upload_new_confirmation_${isStory?'story':'post'}_${b.name}_$lang');
        },brightness:b,scale:1.8,language:lang,respond:(_)async=>json({'message':'This draft was already submitted with different content. Check the original before sharing again.','code':'upload_intent_conflict','resource_id':'original'},409));
      });
    }
  }
    }
  for (final b in [Brightness.light,Brightness.dark]) {
    for (final lang in ['en','ne']) {
    testWidgets('story review and discard layout ${b.name} $lang small/large text', (t) async {
      t.view.physicalSize=const Size(960,1920);t.view.devicePixelRatio=3;addTearDown(t.view.reset);
      await fixture(t,story,() async {
        await shot(t,'story_review_top_${b.name}_$lang');
        await t.scrollUntilVisible(find.byType(TextField), 150, scrollable: find.byType(Scrollable).first); await t.enterText(find.byType(TextField),'A moment from the ridge.'); await t.pumpAndSettle(); await shot(t,'story_review_${b.name}_$lang');
        await t.pageBack(); await t.pumpAndSettle(); expect(t.takeException(),isNull); await shot(t,'draft_discard_${b.name}_$lang');
      },brightness:b,scale:1.8,language:lang);
    });
    }
  }
}
