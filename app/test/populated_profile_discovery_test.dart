// Licensed review-only images and synthetic accounts. No writes or native playback.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/main.dart' show HomeShell,buildTheme;
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/search_page.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';

final member=<String,dynamic>{'public_id':'review','username':'mira','name':'Mira Chen','bio':'Mountain trails, quiet streets and everyday finds.','posts_count':24,'followers_count':12340,'following_count':204,'avatar_url':null,'is_me':true};
class PopulatedSession extends Session {
  final reads=<String>[];
  PopulatedSession(){user=member;loading=false;}
  @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query}) async {
    if(method!='GET')throw StateError('Review disallows mutations');reads.add('$path ${query??{}}');
    if(path=='/users/search')return {'users':[for(final name in ['mira','mira_trails','mira_everyday','mira_architecture']){'public_id':name,'username':name,'name':name=='mira'?'Mira Chen':name=='mira_trails'?'Mira · Himalayan trails':name=='mira_everyday'?'Mira Everyday':'Mira Architecture','following':name=='mira_trails'}],'hashtags':['mountainwalks','morninglight']};
    if(path.startsWith('/users/'))return {'user':member};
    if(path=='/posts')return {'data':[for(var i=0;i<12;i++){'public_id':'fixture-$i','kind':query?['kind']=='reel'?'reel':'post','body':'Review moment ${i+1}','author':member,'media':[{'type':query?['kind']=='reel'?'video':'image','url':query?['kind']=='reel'?'https://fixture.invalid/clip-$i.mp4':'https://fixture.invalid/photo-$i.jpg',if(query?['kind']=='reel')'thumbnail_url':'https://fixture.invalid/photo-$i.jpg'}],'created_at':'2026-11-21T00:00:00Z','likes_count':8,'comments_count':2,'hashtags':[]}],'next_cursor':null};
    if(path=='/notifications/summary')return {'unread_messages':128};
    if(path=='/stories')return {'data':[]};
    return {'data':[],'next_cursor':null};
  }
}
Future<void> save(WidgetTester t,GlobalKey key,String name)async {
  await t.runAsync(()async {
    final image=await(key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final data=await image.toByteData(format:ui.ImageByteFormat.png);
    File('/downloads/sanjaal-populated-review/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}
void main(){
  setUpAll(()async {
    for(final entry in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final font=FontLoader(entry.$1)..addFont(File(entry.$2).readAsBytes().then((b)=>ByteData.sublistView(b)));await font.load();}
  });
  for(final width in [390.0,320.0]){for(final scale in [1.0,1.8]){for(final dark in [false,true]){
    testWidgets('populated journeys $width $scale dark=$dark',(t)async {
      SharedPreferences.setMockInitialValues({});prefs.lang=width==320?'ne':'en';addTearDown(()=>prefs.lang='en');
      t.view.physicalSize=Size(width,844);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
      final images=[for(final n in ['mountain','patan-bell','cat'])File('/downloads/sanjaal-highfidelity/$n.jpg').readAsBytesSync()];
      feedImageProvider=(url){final i=int.tryParse(RegExp(r'photo-(\d+)').firstMatch(url)?.group(1)??'0')??0;return MemoryImage(images[[0,1,2,2,0,1,1,2,0,0,2,1][i%12]]);};addTearDown(()=>feedImageProvider=null);
      final session=PopulatedSession(),key=GlobalKey();
      await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(dark?Brightness.dark:Brightness.light,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!),home:HomeShell(session:session))));
      await t.pumpAndSettle();
      t.widget<GlassNavBar>(find.byType(GlassNavBar)).onSelected(4);await t.pumpAndSettle();
      for(var i=0;i<3;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:40)));await t.pumpAndSettle();}
      final suffix='${width.toInt()}-$scale-${dark?'dark':'light'}';
      await save(t,key,'profile-$suffix');
      expect(find.byType(MePage),findsOneWidget);expect(find.byType(Image),findsWidgets);expect(t.takeException(),isNull);
      await t.drag(find.byType(CustomScrollView).last,const Offset(0,-250));await t.pumpAndSettle();await save(t,key,'profile-scrolled-$suffix');
      expect(t.takeException(),isNull);
      // Reels profile tab is a real separately fetched grid, not playback proof.
      await t.drag(find.byType(CustomScrollView).last,const Offset(0,800));await t.pumpAndSettle();
      final tab=find.descendant(of:find.byType(ProfilePosts),matching:find.byWidgetPredicate((w)=>w is Semantics && w.properties.button==true && w.properties.label!=null && w.properties.selected==false));
      expect(tab,findsOneWidget);
      {await t.tap(tab);await t.pumpAndSettle();await save(t,key,'profile-reels-$suffix');expect(session.reads.any((p)=>p.contains('kind: reel')),isTrue);}
      t.widget<GlassNavBar>(find.byType(GlassNavBar)).onSearch!();await t.pumpAndSettle();
      expect(find.byType(SearchPage),findsOneWidget);
      await t.enterText(find.byType(TextField),'mira');await t.pump(const Duration(milliseconds:400));await t.pumpAndSettle();
      expect(find.text('#mountainwalks'),findsOneWidget);expect(find.text('Mira Chen'),findsWidgets);
      await save(t,key,'discovery-$suffix');expect(t.takeException(),isNull);
      await t.tap(find.text('Mira Chen').last);await t.pumpAndSettle();expect(find.byType(UserProfilePage),findsOneWidget);expect(t.takeException(),isNull);
      await t.pumpWidget(const SizedBox());await t.pump();
    });
  }}}
}
