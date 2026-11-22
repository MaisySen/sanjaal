import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';
http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type':'application/json; charset=utf-8'});
Future<void> flush(WidgetTester t) async { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25))); await t.pump(); await t.pump(const Duration(milliseconds: 400)); }
Future<void> fixture(WidgetTester t, Widget Function(Session) page, Future<void> Function() run, {Future<http.Response> Function(http.Request)? respond, Brightness brightness = Brightness.light, double scale = 1, String language = 'en', bool intents = true, double keyboard = 0}) async {
  SharedPreferences.setMockInitialValues({});
  prefs.lang = language; addTearDown(() => prefs.lang = 'en');
  await http.runWithClient(() async {
    final s = Session(); await s.login('fixture','not-a-password');
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('review'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(brightness, fontFamily: 'Roboto', fontFamilyFallback: ['NotoDev']), builder: (c,w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), viewInsets: EdgeInsets.only(bottom: keyboard)), child: w!), home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => page(s))), child: const Text('Create fixture')))))));
    await t.tap(find.text('Create fixture')); await flush(t);
    await run();
    await t.pumpWidget(const SizedBox()); await t.pump(const Duration(seconds: 1));
  }, () => MockClient((r) async {
    if (r.url.path.endsWith('/oauth/token')) return json({'access_token':'fixture','expires_in':3600});
    if (r.method=='GET' && r.url.path.endsWith('/auth/me')) return json({'features':{'polls':true,'upload_intents':intents},'user':{'public_id':'me','username':'fixture','name':'Fixture Name','bio':'Original bio'}});
    return respond == null ? json({}) : respond(r);
  }));
}
Map<String,dynamic> person({bool own=false,bool following=false,int followers=4,int posts=0})=>{'public_id':own?'me':'asha','username':own?'fixture':'asha','name':'Asha Gurung','bio':'Community music and weekend walks.','following':following,'followers_count':followers,'following_count':3,'posts_count':posts};
class PendingPicker extends ImagePickerPlatform {
  final result=Completer<XFile?>();
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options=const ImagePickerOptions()})=>result.future;
}
Future<void> shot(WidgetTester t,String name) async {await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('review')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());});}
void main(){
  setUpAll(()async{
    for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final f=File(p.$2);if(f.existsSync()){final l=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await l.load();}}
  });
  testWidgets('empty Posts section does not deny existing reel activity',(t)async{
    await fixture(t,(s)=>MePage(session:s),()async{
      expect(find.text('5'),findsOneWidget);
      expect(find.text('No photo or text posts yet'),findsOneWidget);
      expect(find.text('You have not posted yet'),findsNothing);
    },respond:(r)async=>r.url.path.contains('/users/')?json({'user':person(own:true,posts:5)}):json({'data':[],'next_cursor':null}));
  });
  testWidgets('unchanged edit leaves without a discard question',(t)async{
    await fixture(t,(s)=>EditProfilePage(session:s),()async{await t.pageBack();await t.pumpAndSettle();expect(find.byType(EditProfilePage),findsNothing);expect(find.text('Discard this draft?'),findsNothing);});
  });
  testWidgets('avatar picker locks controls and forced disposal never uploads',(t)async{
    final prior=ImagePickerPlatform.instance;final picker=PendingPicker();ImagePickerPlatform.instance=picker;addTearDown(()=>ImagePickerPlatform.instance=prior);var writes=0;
    await fixture(t,(s)=>EditProfilePage(session:s),()async{
      await t.tap(find.byTooltip('Change photo'));await flush(t);expect(t.widgetList<TextFormField>(find.byType(TextFormField)).every((w)=>w.enabled==false),isTrue);
      await t.pumpWidget(const SizedBox());picker.result.complete(XFile.fromData(Uint8List.fromList([1,2,3]),name:'fixture.jpg'));await flush(t);expect(t.takeException(),isNull);expect(writes,0);
    },respond:(_)async{writes++;return json({});});
  });
  testWidgets('saving only an avatar keeps text draft unsaved and guarded',(t)async{
    final prior=ImagePickerPlatform.instance;final picker=PendingPicker();ImagePickerPlatform.instance=picker;addTearDown(()=>ImagePickerPlatform.instance=prior);var writes=0;
    await fixture(t,(s)=>EditProfilePage(session:s),()async{
      await t.enterText(find.byType(TextFormField).first,'Unsaved name');await t.tap(find.byTooltip('Change photo'));await flush(t);picker.result.complete(XFile.fromData(Uint8List.fromList([1,2,3]),name:'fixture.jpg'));await flush(t);
      expect(writes,1);expect(find.text('Unsaved name'),findsOneWidget);expect(find.text('Photo saved. Text changes still need Save.'),findsOneWidget);await t.pageBack();await flush(t);expect(find.text('Discard this draft?'),findsOneWidget);
    },respond:(r)async{expect(r.url.path,endsWith('/avatar'));writes++;return json({'user':{'name':'Fixture Name','username':'fixture','bio':'Original bio'}});});
  });

  testWidgets('pending follow blocks repeat actions and retains last profile',(t)async{
    final pending=Completer<http.Response>();var writes=0;
    await fixture(t,(s)=>UserProfilePage(session:s,username:'asha'),()async{
      await t.tap(find.text('Follow'));await flush(t);await t.tap(find.text('Follow'));await flush(t);expect(writes,1);expect(find.text('Asha Gurung'),findsOneWidget);
      pending.complete(json({'message':'Fixture follow rejected'},422));await flush(t);expect(find.text('Follow'),findsOneWidget);expect(find.text('4'),findsOneWidget);expect(find.text('Check the details and try again.'),findsOneWidget);
    },respond:(r)async{if(r.url.path.endsWith('/follow')){writes++;return pending.future;}return r.url.path.endsWith('/users/asha')?json({'user':person()}):json({'data':[],'next_cursor':null});});
  });
  testWidgets('canceling avatar selection unlocks unchanged editor without a write',(t)async{
    final prior=ImagePickerPlatform.instance;final picker=PendingPicker();ImagePickerPlatform.instance=picker;addTearDown(()=>ImagePickerPlatform.instance=prior);
    await fixture(t,(s)=>EditProfilePage(session:s),()async{
      await t.tap(find.byTooltip('Change photo'));await flush(t);picker.result.complete(null);await flush(t);expect(t.widgetList<TextFormField>(find.byType(TextFormField)).every((w)=>w.enabled==true),isTrue);await t.pageBack();await t.pumpAndSettle();expect(find.byType(EditProfilePage),findsNothing);
    },respond:(_)async=>throw StateError('Canceled selection must not upload'));
  });
  testWidgets('invalid edit does not send and preserves input',(t)async{
    await fixture(t,(s)=>EditProfilePage(session:s),()async{
      await t.enterText(find.byType(TextFormField).at(1),'!');await t.tap(find.text('Save'));await flush(t);expect(find.text('Use 3 to 30 letters, numbers, dots or underscores'),findsOneWidget);expect(find.text('!'),findsOneWidget);
    },respond:(_)async=>throw StateError('Invalid draft must not send'));
  });
  testWidgets('initial member profile failure offers retry',(t)async{
    var reads=0;await fixture(t,(s)=>UserProfilePage(session:s,username:'asha'),()async{
      expect(find.text('Could not load this.'),findsOneWidget);await t.tap(find.text('Try again'));await flush(t);expect(find.text('Asha Gurung'),findsOneWidget);
    },respond:(r)async=>r.url.path.endsWith('/users/asha')?(++reads==1?json({'message':'Fixture offline'},503):json({'user':person()})):json({'data':[],'next_cursor':null}));
  });
  testWidgets('successful follow survives failed reconciliation and retry does not repeat mutation',(t)async{
    var reads=0,writes=0;await fixture(t,(s)=>UserProfilePage(session:s,username:'asha'),()async{
      await t.tap(find.text('Follow'));await flush(t);expect(writes,1);expect(find.text('Unfollow'),findsOneWidget);expect(find.text('5'),findsOneWidget);expect(find.text('Could not load this.'),findsOneWidget);
      await t.tap(find.text('Try again'));await flush(t);expect(reads,3);expect(writes,1);expect(find.text('Unfollow'),findsOneWidget);
    },respond:(r)async{if(r.url.path.endsWith('/follow')){writes++;return json({'following':true});}if(r.url.path.endsWith('/users/asha')){reads++;return reads==2?json({'message':'Fixture refresh failed'},503):json({'user':person(following:reads>1,followers:reads>1?5:4)});}return json({'data':[],'next_cursor':null});});
  });
  testWidgets('own profile retry preserves identity and loads current counts',(t)async{
    var reads=0;await fixture(t,(s)=>MePage(session:s),()async{
      expect(find.text('Fixture Name'),findsOneWidget);expect(find.text('Could not load this.'),findsOneWidget);await t.tap(find.text('Try again'));await flush(t);expect(find.text('7'),findsOneWidget);expect(find.text('Fixture Name'),findsOneWidget);
    },respond:(r)async=>r.url.path.endsWith('/users/fixture')?(++reads==1?json({'message':'Fixture counts failed'},503):json({'user':person(own:true,posts:7)})):json({'data':[],'next_cursor':null}));
  });
  testWidgets('own profile newer publish counts win over an older response',(t)async{
    final old=Completer<http.Response>();var reads=0;final revision=ValueNotifier(0);addTearDown(revision.dispose);
    await fixture(t,(s)=>ValueListenableBuilder<int>(valueListenable:revision,builder:(_,v,__)=>MePage(session:s,contentRevision:v)),()async{
      revision.value=1;await flush(t);expect(find.text('9'),findsOneWidget);old.complete(json({'user':person(own:true,posts:1)}));await flush(t);expect(find.text('9'),findsOneWidget);
    },respond:(r)async=>r.url.path.endsWith('/users/fixture')?(++reads==1?old.future:json({'user':person(own:true,posts:9)})):json({'data':[],'next_cursor':null}));
  });
  testWidgets('unchanged edit closes directly and changed text requires explicit discard',(t)async{
    await fixture(t,(s)=>EditProfilePage(session:s),()async{
      await t.enterText(find.byType(TextFormField).first,'Edited name');await t.pump();await t.pageBack();await flush(t);expect(find.text('Discard this draft?'),findsOneWidget);await t.tap(find.text('Keep editing'));await flush(t);expect(find.text('Edited name'),findsOneWidget);
      await t.pageBack();await flush(t);await t.tap(find.text('Discard'));await flush(t);await t.pumpAndSettle();expect(find.byType(EditProfilePage),findsNothing);
    });
  });
  testWidgets('busy save freezes fields, keeps route and sends one snapshot',(t)async{
    final pending=Completer<http.Response>();var writes=0;String? body;
    await fixture(t,(s)=>EditProfilePage(session:s),()async{
      await t.enterText(find.byType(TextFormField).first,'Edited name');await t.tap(find.text('Save'));await flush(t);
      expect(t.widgetList<TextFormField>(find.byType(TextFormField)).every((w)=>w.enabled==false),isTrue);await t.pageBack();await flush(t);expect(find.byType(EditProfilePage),findsOneWidget);expect(writes,1);
      pending.complete(json({'user':{'name':'Edited name','username':'fixture','bio':'Original bio'}}));await flush(t);await t.pump();await t.pumpAndSettle();expect(find.byType(EditProfilePage),findsNothing);expect(jsonDecode(body!)['name'],'Edited name');
    },respond:(r){writes++;body=r.body;return pending.future;});
  });
  testWidgets('rejected save retains fields and permits explicit retry',(t)async{
    var writes=0;await fixture(t,(s)=>EditProfilePage(session:s),()async{
      await t.enterText(find.byType(TextFormField).first,'Retained name');await t.tap(find.text('Save'));await flush(t);expect(find.text('Retained name'),findsOneWidget);expect(find.text('Check the details and try again.'),findsOneWidget);expect(t.widget<TextFormField>(find.byType(TextFormField).first).enabled,isTrue);
      await t.tap(find.text('Save'));await flush(t);expect(writes,2);await t.pumpAndSettle();expect(find.byType(EditProfilePage),findsNothing);
    },respond:(_)async=>++writes==1?json({'message':'Name not available'},422):json({'user':{'name':'Retained name','username':'fixture'}}));
  });
  for(final save in [false,true]){
    testWidgets('forced disposal during ${save?'save':'profile read'} is safe',(t)async{
      final pending=Completer<http.Response>();await fixture(t,(s)=>save?EditProfilePage(session:s):UserProfilePage(session:s,username:'asha'),()async{
        if(save){await t.enterText(find.byType(TextFormField).first,'Pending');await t.tap(find.text('Save'));await flush(t);}
        await t.pumpWidget(const SizedBox());pending.complete(json({'user':person()}));await flush(t);expect(t.takeException(),isNull);
      },respond:(_)=>pending.future);
    });
  }
  for(final scale in [1.0,1.8]){for(final lang in ['en','ne']){
    testWidgets('reference profile groups identity with readable real metrics $scale $lang',(t)async{
      t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
      await fixture(t,(s)=>MePage(session:s,onCompose:()async{}),()async{
        await flush(t);await t.pumpAndSettle();
        final edit=find.text(lang=='en'?'Edit profile':'प्रोफाइल सम्पादन');
        final posts=find.text(lang=='en'?'Posts':'पोस्ट');
        expect(t.getTopLeft(posts).dy,lessThan(t.getTopLeft(edit).dy));
        expect(find.text('1.2K'),findsOneWidget);expect(find.text('12'),findsOneWidget);
        final label=t.widget<Text>(find.text(lang=='en'?'Followers':'फलोअर'));
        final painter=TextPainter(text:TextSpan(text:label.data,style:Theme.of(t.element(find.byType(ProfileHeader))).textTheme.bodySmall),textDirection:TextDirection.ltr,textScaler:TextScaler.linear(scale))..layout(maxWidth:scale>1?220:80);
        expect(painter.computeLineMetrics().length,1,reason:'metric label must not split into letter fragments');
        final create=find.widgetWithText(FilledButton,lang=='en'?'Create a post':'पोस्ट बनाउनुहोस्');
        await t.ensureVisible(create);await t.pumpAndSettle();
        expect(t.getBottomRight(create).dy,lessThanOrEqualTo(640));
        expect(t.takeException(),isNull);await shot(t,'profile_first_action_${lang}_${scale==1?'normal':'large'}');
      },scale:scale,language:lang,respond:(r)async=>r.url.path.contains('/users/')?json({'user':person(own:true,followers:1250,posts:12)}):json({'data':[],'next_cursor':null}));
    });
  }}
  for(final page in ['edit','member','me']){for(final lang in ['en','ne']){for(final b in [Brightness.light,Brightness.dark]){
    testWidgets('profile small large text $page $lang ${b.name}',(t)async{
      t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
      await fixture(t,(s)=>page=='edit'?EditProfilePage(session:s):page=='member'?UserProfilePage(session:s,username:'asha'):MePage(session:s),()async{
        await flush(t);await t.pumpAndSettle();expect(t.takeException(),isNull);await shot(t,'profile_${page}_${lang}_${b.name}');
      },brightness:b,scale:1.8,language:lang,respond:(r)async=>r.url.path.contains('/users/')?json({'user':person(own:page=='me',followers:1250,posts:12)}):json({'data':[],'next_cursor':null}));
    });
  }}}

  for(final lang in ['en','ne']){for(final b in [Brightness.light,Brightness.dark]){
    testWidgets('profile retry and edit keyboard $lang ${b.name}',(t)async{
      t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
      await fixture(t,(s)=>UserProfilePage(session:s,username:'asha'),()async{await flush(t);await t.pumpAndSettle();expect(t.takeException(),isNull);await shot(t,'profile_retry_${lang}_${b.name}');},brightness:b,scale:1.8,language:lang,respond:(_)async=>json({'message':lang=='ne'?'प्रोफाइल लोड हुन सकेन।':'Profile could not be loaded.'},503));
      await fixture(t,(s)=>EditProfilePage(session:s),()async{await flush(t);await t.scrollUntilVisible(find.byKey(const ValueKey('profile-bio')),120,scrollable:find.descendant(of:find.byType(ListView),matching:find.byType(Scrollable)).first);await t.enterText(find.byKey(const ValueKey('profile-bio')),'A changed bio to keep');await t.pumpAndSettle();expect(t.takeException(),isNull);await shot(t,'profile_edit_keyboard_${lang}_${b.name}');},brightness:b,scale:1.8,language:lang,keyboard:240);
    });
  }}

}
