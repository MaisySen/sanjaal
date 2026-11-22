// Screenshot-led layout and retained-state journeys. Synthetic data only.
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
import 'package:sanjaal/main.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/reels_page.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object value)=>http.Response(jsonEncode(value),200);
Map<String,dynamic> person={'public_id':'me','username':'fixture','name':'Fixture Member','bio':'A community for everyday moments.','posts_count':6,'followers_count':12,'following_count':8};
Map<String,dynamic> post(int i,{String kind='post'})=>{'public_id':'p$i','kind':kind,'body':'A community moment $i','media':[{'type':'image','url':'https://fixture.invalid/$i.png'}],'author':person,'likes_count':i,'comments_count':0};
Future<void> flush(WidgetTester t)async{for(var i=0;i<4;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:15)));await t.pump(const Duration(milliseconds:150));}}
Future<void> shot(WidgetTester t,String name)async{await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('reference-shot')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/reference_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());});}
Future<void> fixture(WidgetTester t,Future<void>Function(Session,List<Uri>)run,{Brightness mode=Brightness.dark,double scale=1,String language='en',bool small=false})async{
 SharedPreferences.setMockInitialValues({});prefs.lang=language;addTearDown(()=>prefs.lang='en');
 t.view.physicalSize=small?const Size(320,640):const Size(390,844);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
 final reads=<Uri>[];
 await http.runWithClient(()async{final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(RepaintBoundary(key:const ValueKey('reference-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale),padding:const EdgeInsets.only(top:24,bottom:24),viewPadding:const EdgeInsets.only(top:24,bottom:24)),child:w!),home:HomeShell(session:s))));await flush(t);await run(s,reads);await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:5));},()=>MockClient((r)async{
  if(r.url.path.endsWith('/oauth/token'))return json({'access_token':'x','expires_in':3600});
  if(r.url.path.endsWith('/auth/me'))return json({'user':person});reads.add(r.url);
  if(r.url.path.contains('/users/')&&!r.url.path.endsWith('/blocked'))return json({'user':person});
  if(r.url.path.endsWith('/posts'))return json({'data':[for(var i=0;i<9;i++)post(i,kind:r.url.queryParameters['kind']??'post')],'next_cursor':null});
  if(r.url.path.endsWith('/stories'))return json({'data':[{'author':{'public_id':'other','username':'community'},'items':[],'all_viewed':false}]});
  return json({'data':[],'next_cursor':null,'balance':0,'entries':[],'unread_messages':0});
 }));
}
Future<void> select(WidgetTester t,String text)async{await t.tap(find.descendant(of:find.byType(GlassNavBar),matching:find.byTooltip(t_(text))));await flush(t);}
void main(){
 setUpAll(()async{Directory('test/renders').createSync(recursive:true);
  for(final f in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final file=File(f.$2);if(file.existsSync()){final loader=FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));await loader.load();}}
  final pic=ui.PictureRecorder();final c=Canvas(pic);c.drawRect(const Rect.fromLTWH(0,0,400,600),Paint()..shader=ui.Gradient.linear(Offset.zero,const Offset(400,600),const [Color(0xFF123442),Color(0xFFDBAE72)]));c.drawPath(Path()..moveTo(0,600)..lineTo(180,240)..lineTo(400,600)..close(),Paint()..color=const Color(0xFF16454C));final image=await pic.endRecording().toImage(400,600);final data=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();feedImageProvider=(_)=>MemoryImage(data);
 });
 tearDownAll(()=>feedImageProvider=null);
 testWidgets('Home is a scrolling feed and its story row survives scrolling and feed-tab return',(t)async{
  await fixture(t,(s,reads)async{
   expect(find.byType(PageView).evaluate().where((e)=>(e.widget as PageView).scrollDirection==Axis.vertical),isEmpty);
   int stories()=>reads.where((u)=>u.path.endsWith('/stories')).length;
   expect(stories(),1);await t.drag(find.byWidgetPredicate((w)=>w is ListView && w.scrollDirection==Axis.vertical).first,const Offset(0,-2100));await flush(t);
   await t.drag(find.byWidgetPredicate((w)=>w is ListView && w.scrollDirection==Axis.vertical).first,const Offset(0,2400));await flush(t);expect(stories(),1);
   await t.tap(find.text('Following'));await flush(t);await t.tap(find.text('For you'));await flush(t);
   expect(reads.where((u)=>u.path.endsWith('/posts')&&u.queryParameters['scope']==null).length,1,reason:'switching feed filters must not refetch For you');expect(stories(),1);expect(t.takeException(),isNull);
  });
 });
 testWidgets('Home keeps exact offset and no extra request across all five tabs and route back',(t)async{
   await fixture(t,(session,reads)async{
     final feed=t.state<FeedListState>(find.byType(FeedList).first);
     feed.scroll.jumpTo(420);await flush(t);
     final offset=feed.scroll.offset;
     int homeReads()=>reads.where((u)=>u.path.endsWith('/posts')&&u.queryParameters['kind']=='post'&&u.queryParameters['scope']==null&&u.queryParameters['username']==null).length;
     final before=homeReads();
     for(final tab in ['Reels','Chats','Wallet','Me','Home']){await select(t,tab);}
     expect(feed.scroll.offset,offset);expect(homeReads(),before);
     await select(t,'Me');await t.tap(find.byTooltip('Settings'));await flush(t);await t.pageBack();await flush(t);await select(t,'Home');
     expect(feed.scroll.offset,offset);expect(homeReads(),before);
     expect(t.takeException(),isNull);
   });
 });
 // Image-only reel fixtures isolate navigation/index behavior, not media playback.
 testWidgets('Reels keeps exact page on tab returns and inserts upload without refetch',(t)async{
   await fixture(t,(session,reads)async{
     await select(t,'Reels');
     final pages=find.byWidgetPredicate((w)=>w is PageView&&w.scrollDirection==Axis.vertical);
     final pager=t.widget<PageView>(pages).controller!;
     pager.jumpToPage(2);await flush(t);
     final before=reads.where((u)=>u.path.endsWith('/posts')&&u.queryParameters['kind']=='reel').length;
     final current=t.widgetList<ReelItem>(find.byType(ReelItem)).where((w)=>w.playing).single.reel['public_id'];
     for(final tab in ['Home','Chats','Wallet','Me','Reels']){await select(t,tab);}
     expect(pager.page,2);expect(reads.where((u)=>u.path.endsWith('/posts')&&u.queryParameters['kind']=='reel').length,before);
     final published={...post(99,kind:'reel'),'public_id':'new-reel'};
     final center=UploadCenter.of(session);expect(center.start('reel',()async=>published),isTrue);await flush(t);
     expect(center.result?['public_id'],'new-reel');
     expect(pager.page,3,reason:'insert is visible in the list without replacing the viewed reel');
     expect(t.widgetList<ReelItem>(find.byType(ReelItem)).where((w)=>w.playing).single.reel['public_id'],current);
     pager.jumpToPage(0);await flush(t);
     expect(t.widgetList<ReelItem>(find.byType(ReelItem)).where((w)=>w.playing).single.reel['public_id'],'new-reel');
     expect(reads.where((u)=>u.path.endsWith('/posts')&&u.queryParameters['kind']=='reel').length,before);
     expect(t.takeException(),isNull);
   });
 });
 testWidgets('profile Settings opens searchable controls and a real blocked destination',(t)async{
  await fixture(t,(s,reads)async{
   await select(t,'Me');final settings=find.byTooltip('Settings');expect(settings,findsOneWidget);await t.tap(settings);await flush(t);expect(find.byType(SettingsPage),findsOneWidget);
   await t.enterText(find.descendant(of:find.byType(SettingsPage),matching:find.byType(TextField)),'blocked');await t.pumpAndSettle();expect(find.descendant(of:find.byType(SettingsPage),matching:find.text('Blocked people')),findsOneWidget);expect(find.descendant(of:find.byType(SettingsPage),matching:find.text('Saved')),findsNothing);await t.tap(find.descendant(of:find.byType(SettingsPage),matching:find.text('Blocked people')));await flush(t);expect(reads.any((u)=>u.path.endsWith('/users/blocked')),isTrue);expect(t.takeException(),isNull);
  });
 });
 for(final mode in [Brightness.dark,Brightness.light]){for(final language in ['en','ne']){
  testWidgets('reference Home profile grid and grouped settings ${mode.name} $language',(t)async{
   await fixture(t,(s,reads)async{
    await shot(t,'home_${mode.name}_$language');await select(t,'Me');
    expect(find.byType(SliverGrid),findsOneWidget);final grid=t.widget<SliverGrid>(find.byType(SliverGrid));expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount,3);
    expect(t.getTopLeft(find.text(t_('Posts'))).dy,lessThan(t.getTopLeft(find.text(t_('Edit profile'))).dy));
    await shot(t,'profile_${mode.name}_$language');await t.tap(find.byTooltip(t_('Settings')));await flush(t);await shot(t,'settings_${mode.name}_$language');expect(t.takeException(),isNull);
   },mode:mode,language:language);
  });
 }}
 testWidgets('floating bar compacts on scrolling and expands on touch with five reachable destinations',(t)async{
  final semantics=t.ensureSemantics();
  await fixture(t,(s,reads)async{
   await t.drag(find.byWidgetPredicate((w)=>w is ListView && w.scrollDirection==Axis.vertical).first,const Offset(0,-300));await flush(t);
   expect(t.widget<GlassNavBar>(find.byType(GlassNavBar)).compact,isTrue);
   for(final text in ['Home','Reels','Chats','Wallet','Me'])expect(find.bySemanticsLabel(text),findsOneWidget);
   await shot(t,'nav_compact');await t.tap(find.bySemanticsLabel('Wallet'));await flush(t);
   expect(t.widget<GlassNavBar>(find.byType(GlassNavBar)).compact,isFalse);expect(t.widget<GlassNavBar>(find.byType(GlassNavBar)).index,3);expect(t.takeException(),isNull);await shot(t,'nav_expanded');
  },small:true);
  semantics.dispose();
 });
 for(final compact in [false,true]){for(final scale in [1.0,1.8]){
  testWidgets('Reels controls stay above ${compact?'compact':'expanded'} nav at320x640 text$scale',(t)async{
   await fixture(t,(s,reads)async{
    await select(t,'Reels');
    if(compact){await t.pump(const Duration(seconds:4));await flush(t);}
    final bar=find.byType(GlassNavBar);final top=t.getTopLeft(bar).dy;
    final sound=find.byTooltip('Sound');expect(sound,findsOneWidget);expect(t.getBottomLeft(sound).dy,lessThan(top));
    final center=t.getCenter(sound);expect(center.dy,greaterThan(24));await t.tap(sound);await t.pump();expect(find.byTooltip('Muted'),findsOneWidget);
    await shot(t,'reel_clearance_${compact?'compact':'expanded'}_${scale==1?'normal':'large'}');expect(t.takeException(),isNull);
   },small:true,scale:scale);
  });
 }}
}
