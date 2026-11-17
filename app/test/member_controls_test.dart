// Synthetic settings HTTP/widget fixtures. Not a live-server or device test.
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
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/member_controls_page.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
http.Response json(Object value,[int code=200])=>http.Response(jsonEncode(value),code);
Map<String,dynamic> value({int revision=0,String scope='everyone',bool share=true})=>{'controls':{'revision':revision,'comments_from':scope,'share_to_chat':share}};
Future<void> flush(WidgetTester t)async{await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await t.pump();await t.pump(const Duration(milliseconds:400));}
Future<void> fixture(WidgetTester t,Future<http.Response>Function(http.Request) respond,Future<void>Function(Session)run,{bool capability=true,bool settings=false,Brightness mode=Brightness.light,String language='en',double scale=1})async{
 SharedPreferences.setMockInitialValues({});prefs.lang=language;addTearDown(()=>prefs.lang='en');t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
 await http.runWithClient(()async{
 final s=Session();await s.login('fixture','not-a-password');
 await t.pumpWidget(RepaintBoundary(key:const ValueKey('controls-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!),home:settings?SettingsPage(session:s):Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()=>Navigator.of(c).push(MaterialPageRoute(builder:(_)=>MemberControlsPage(session:s))),child:const Text('Open controls fixture')))))));if(!settings){await t.tap(find.text('Open controls fixture'));}await flush(t);await run(s);await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:2));
 },()=>MockClient((r)async{
 if(r.url.path.endsWith('/oauth/token'))return json({'access_token':'fixture','expires_in':3600});
 if(r.url.path.endsWith('/auth/me'))return json({'user':{'public_id':'me','username':'me'},'features':{if(capability)'interaction_controls':true}});
 return respond(r);
 }));
}
TextButton saveButton(WidgetTester t)=>t.widget<TextButton>(find.widgetWithText(TextButton,t_('Save')));
void main(){
 setUpAll(()async{Directory('test/renders').createSync(recursive:true);for(final f in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final file=File(f.$2);if(file.existsSync()){final loader=FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));await loader.load();}}});
 for(final supported in [false,true])testWidgets('Settings route respects live server capability $supported',(t)async{
 await fixture(t,(_)async=>json(value()),(s)async{
 expect(s.interactionControlsEnabled,supported);await t.enterText(find.byType(TextField),'Comments');await t.pump();expect(find.text('Comments and sharing'),supported?findsOneWidget:findsNothing);
 if(supported){await t.tap(find.text('Comments and sharing'));await flush(t);expect(find.byType(MemberControlsPage),findsOneWidget);}
 },capability:supported,settings:true);
 });
 testWidgets('confirmed save carries revision freezes edits and never claims success before response',(t)async{
 final pending=Completer<http.Response>();var writes=0;Map? body;
 await fixture(t,(r)async{if(r.method=='PATCH'){writes++;body=jsonDecode(r.body);return pending.future;}return json(value(revision:4));},(s)async{
 expect(saveButton(t).onPressed,isNull);await t.tap(find.text('People you follow'));await flush(t);expect(saveButton(t).onPressed,isNotNull);
 await t.tap(find.text('Save'));await flush(t);expect(writes,1);expect(body,{'revision':4,'comments_from':'following','share_to_chat':true});expect(find.text('Settings saved.'),findsNothing);expect(saveButton(t).onPressed,isNull);
 expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNull);
 pending.complete(json(value(revision:5,scope:'following')));await flush(t);expect(find.text('Settings saved.'),findsOneWidget);expect(saveButton(t).onPressed,isNull);
 });
 });
 for(final code in [409,503,0])testWidgets('uncertain or stale save $code needs explicit readback and never replays',(t)async{
 var reads=0,writes=0;await fixture(t,(r)async{
 if(r.method=='PATCH'){writes++;if(code==0)throw const SocketException('fixture lost response');return json({'message':'Fixture result unconfirmed'},code);}
 reads++;return json(reads==1?value():value(revision:1,scope:'nobody'));
 },(s)async{
 await t.tap(find.text('Nobody else'));await flush(t);await t.tap(find.text('Save'));await flush(t);expect(writes,1);expect(saveButton(t).onPressed,isNull);expect(find.text('Settings saved.'),findsNothing);
 await t.tap(find.text('Reload current settings'));await flush(t);expect(reads,2);expect(writes,1);expect(saveButton(t).onPressed,isNull);expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNotNull);
 });
 });
 testWidgets('failed initial read offers retry and no guessed preferences',(t)async{
 var reads=0;await fixture(t,(_)async=>++reads==1?json({'message':'Fixture read failed'},503):json(value(scope:'following',share:false)),(s)async{
 expect(find.byType(SwitchListTile),findsNothing);expect(saveButton(t).onPressed,isNull);await t.tap(find.text('Try again'));await flush(t);expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,isFalse);
 });
 });
 for(final mode in [Brightness.light,Brightness.dark])for(final language in ['en','ne'])testWidgets('small large-text controls render ${mode.name} $language',(t)async{
 await fixture(t,(_)async=>json(value(scope:'following',share:false)),(s)async{
 expect(t.takeException(),isNull);await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('controls-shot'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/controls_${mode.name}_$language.png').writeAsBytesSync(data!.buffer.asUint8List());});
 await t.drag(find.byType(ListView),const Offset(0,-500));await flush(t);expect(t.takeException(),isNull);expect(find.byType(SwitchListTile),findsOneWidget);await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('controls-shot'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/controls_${mode.name}_${language}_scrolled.png').writeAsBytesSync(data!.buffer.asUint8List());});
 },mode:mode,language:language,scale:1.8);
 });
}
