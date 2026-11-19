// Plugin-mocked local drafts and synthetic account/server responses only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/group_draft_store.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs,t_;
const people=[{'public_id':'friend-id','username':'asha','name':'Asha Gurung'}];
http.Response reply(Object v,[int status=200])=>http.Response(jsonEncode(v),status);
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
class GroupSession extends Session{
 String owner='a';var posts=0,reads=0;bool capability=true;
 Future<dynamic> Function(String,String,Map<String,dynamic>?)? response;
 @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{
  if(path=='/auth/me')return {'user':{'public_id':owner,'username':owner},'features':{'group_member_refs':capability}};
  if(method=='POST')posts++;else reads++;
  return response==null?{'users':people}:response!(method,path,body);
 }
}
Future<void> fixture(WidgetTester t,Future<void> Function(GroupSession,Future<void> Function()) run,{String lang='en',Brightness mode=Brightness.light,bool large=false})async{
 await http.runWithClient(()async{
  final s=GroupSession();await s.login('fixture','not-a-password');
  Future<void> reopen()async{await t.pumpWidget(const SizedBox());await flush(t);await t.pumpWidget(RepaintBoundary(key:const ValueKey('group-draft-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(large?1.8:1)),child:w!),home:NewChatPage(session:s))));await flush(t);}
  prefs.lang=lang;addTearDown(()=>prefs.lang='en');await reopen();await run(s,reopen);await t.pumpWidget(const SizedBox());await flush(t);
 },()=>MockClient((_)async=>reply({'access_token':'fixture','expires_in':3600})));
}
Future<void> open(WidgetTester t)async{await t.tap(find.byTooltip(t_('Open saved group draft')));await flush(t);}
Future<void> create(WidgetTester t)async{await t.ensureVisible(find.byType(FilledButton));await t.tap(find.byType(FilledButton));await flush(t);}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();const store=GroupDraftStore();
 setUp((){FlutterSecureStorage.setMockInitialValues({});SharedPreferences.setMockInitialValues({});prefs.lang='en';});
 test('new store restores exact bounded title and selected stable identities',()async{
  final saved=await store.save('a',title:'Weekend\nनमस्ते',people:people);final restored=await const GroupDraftStore().read('a');
  expect(restored!.toJson(),saved.toJson());expect(restored.people,people);expect(restored.attempted,false);
  expect(()=>restored.people.add({}),throwsUnsupportedError);expect(()=>restored.people.single['username']='different',throwsUnsupportedError);
 });
 test('accounts cannot read or overwrite another key',()async{
  final a=await store.save('a',title:'Private',people:people);expect(await store.read('b'),isNull);await store.save('b',title:'Other',people:[]);expect((await store.read('a'))!.toJson(),a.toJson());
 });
 test('stale edits deletes and attempted updates cannot replace a newer revision',()async{
  final a=await store.save('a',title:'First',people:people);final b=await store.save('a',title:'Second',people:people,expectedRevision:a.revision);
  await expectLater(store.save('a',title:'Stale',people:people,expectedRevision:a.revision),throwsStateError);
  await expectLater(store.remove('a',a),throwsStateError);await expectLater(store.markAttempt('a',a),throwsStateError);expect((await store.read('a'))!.revision,b.revision);
 });
 test('concurrent first saves preserve one copy and reject silent overwrite',()async{
  var successes=0,failures=0;
  await Future.wait(List.generate(3,(i)=>store.save('a',title:'Plan$i',people:people).then((_)=>successes++,onError:(Object _){failures++;return 0;})));
  expect(successes,1);expect(failures,2);expect(await store.read('a'),isNotNull);
 });
 test('attempt marker survives reopen and refuses saving over uncertain creation',()async{
  final first=await store.save('a',title:'First',people:people);final marked=await store.markAttempt('a',first);expect((await const GroupDraftStore().read('a'))!.attempted,true);
  await expectLater(store.save('a',title:'Changed',people:people,expectedRevision:marked.revision),throwsStateError);
  final reset=await store.markAttempt('a',marked,attempted:false);expect(reset.attempted,false);await store.remove('a',reset);expect(await store.read('a'),isNull);
 });
 test('malformed index is preserved instead of overwritten or deleted',()async{
  final key='group_draft_v1_${sha256.convert(utf8.encode('a'))}';const secure=FlutterSecureStorage();
  await secure.write(key:key,value:'broken');await expectLater(store.read('a'),throwsFormatException);
  await expectLater(store.save('a',title:'New',people:people),throwsFormatException);expect(await secure.read(key:key),'broken');
 });
 for(final data in [<Map<String,dynamic>>[{'public_id':'x','username':'','name':'Bad'}],<Map<String,dynamic>>[...people,...people],List<Map<String,dynamic>>.generate(50,(i)=>{'public_id':'$i','username':'name$i','name':''})]){
  test('invalid duplicate or excessive identities cannot be saved ${data.length}',()async{await expectLater(store.save('a',title:'Plan',people:data),throwsFormatException);expect(await store.read('a'),isNull);});
 }
 test('blank or oversized group plans cannot be saved',()async{
  await expectLater(store.save('a',title:'',people:[]),throwsArgumentError);await expectLater(store.save('a',title:'x'*81,people:people),throwsFormatException);
 });
 testWidgets('save dispose reopen restores title people without a creation request',(t)async{
  await fixture(t,(s,reopen)async{
   await t.tap(find.byTooltip('New group'));await flush(t);await t.enterText(find.byType(TextField).first,'Sydney meetup');await t.enterText(find.byType(TextField).last,'asha');await flush(t);await t.tap(find.text('Asha Gurung'));await flush(t);
   await t.tap(find.byTooltip('Save group draft'));await flush(t);expect((await store.read('a'))!.title,'Sydney meetup');expect(s.posts,0);
   await reopen();await open(t);expect(find.text('Sydney meetup'),findsOneWidget);expect(find.text('@asha'),findsOneWidget);expect(s.posts,0);expect(t.takeException(),isNull);
  });
 });
 testWidgets('reopened create verifies stable IDs and writes attempt before handing request to server',(t)async{
  await store.save('a',title:'Plan',people:people);
  await fixture(t,(s,reopen)async{
   s.response=(m,p,b)async{
    if(m=='GET')return {'users':people};
    expect((await store.read('a'))!.attempted,true);expect(b!['member_refs'],[{'public_id':'friend-id','username':'asha'}]);return {'conversation':{'public_id':'new-group'}};
   };
   await open(t);expect(s.reads,0);expect(s.posts,0);await create(t);expect(s.reads,1);expect(s.posts,1);expect((await store.read('a'))!.attempted,true);expect(t.takeException(),isNull);
  });
 });
 for(final condition in ['renamed','reassigned','unavailable','capability-off','edited']){
  testWidgets('$condition refuses saved group creation without any POST',(t)async{
   await store.save('a',title:'Plan',people:people);
   await fixture(t,(s,reopen)async{
    if(condition=='capability-off'){s.capability=false;await s.login('again','not-a-password');await reopen();}
    s.response=(m,p,b)async=>{'users':condition=='unavailable'?[]:[{'public_id':condition=='reassigned'?'different':'friend-id','username':condition=='renamed'?'new-name':'asha'}]};
    await open(t);if(condition=='edited')await t.enterText(find.byType(TextField).first,'Changed');await create(t);
    expect(s.posts,0);expect((await store.read('a'))!.attempted,false);expect(t.takeException(),isNull);
   });
  });
 }
 for(final rejected in [false,true]){
  testWidgets('${rejected?'explicit rejection':'lost reply'} keeps appropriate restart guard',(t)async{
   await store.save('a',title:'Plan',people:people);
   await fixture(t,(s,reopen)async{
    s.response=(m,p,b)async{if(m=='GET')return {'users':people};throw ApiError('Fixture unavailable',rejected?422:503);};
    await open(t);await create(t);expect(s.posts,1);expect((await store.read('a'))!.attempted,!rejected);
    await reopen();await open(t);expect(s.posts,1);expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,rejected?isNotNull:isNull);
    if(!rejected){await create(t);expect(s.posts,1);}expect(t.takeException(),isNull);
   });
  });
 }
 testWidgets('replacement while checking a recovered person cannot create or mark a group',(t)async{
  await store.save('a',title:'Plan',people:people);final pending=Completer<dynamic>();
  await fixture(t,(s,reopen)async{
   s.response=(m,p,b)=>pending.future;await open(t);await create(t);expect(s.reads,1);
   s.owner='b';await s.login('replacement','not-a-password');await flush(t);pending.complete({'users':people});await flush(t);
   expect(s.posts,0);expect(find.text('Plan'),findsNothing);expect((await store.read('a'))!.attempted,false);expect(await store.read('b'),isNull);expect(t.takeException(),isNull);
  });
 });
 testWidgets('explicit delete removes local uncertain plan only and sends nothing',(t)async{
  final first=await store.save('a',title:'Plan',people:people);await store.markAttempt('a',first);
  await fixture(t,(s,reopen)async{
   await open(t);await t.tap(find.byTooltip('Delete saved group draft'));await flush(t);expect(find.textContaining('only the local plan'),findsOneWidget);
   await t.tap(find.text('Keep'));await flush(t);expect(await store.read('a'),isNotNull);
   await t.tap(find.byTooltip('Delete saved group draft'));await flush(t);await t.tap(find.text('Delete'));await flush(t);expect(await store.read('a'),isNull);expect(s.posts,0);expect(s.reads,0);expect(t.takeException(),isNull);
  });
 });
 testWidgets('archive icon for saved group action exists in bundled assets',(t)async{
  final asset=await rootBundle.loadString('assets/icons/archive.svg');expect(asset,contains('<svg'));
 });
 testWidgets('replacement closes a stale saved-group delete dialog without touching storage',(t)async{
  final saved=await store.save('a',title:'Private group plan',people:people);
  await fixture(t,(s,reopen)async{
   await open(t);await t.ensureVisible(find.byTooltip('Delete saved group draft'));await t.tap(find.byTooltip('Delete saved group draft'));await flush(t);expect(find.byType(AlertDialog),findsOneWidget);
   s.owner='b';await s.login('replacement','not-a-password');await flush(t);
   expect(find.byType(AlertDialog),findsNothing);expect(find.text('Private group plan'),findsNothing);expect((await store.read('a'))!.revision,saved.revision);expect(s.posts,0);expect(t.takeException(),isNull);
  });
 });
 for(final lang in ['en','ne'])for(final mode in [Brightness.light,Brightness.dark]){
  testWidgets('saved group plan large text $lang ${mode.name}',(t)async{
   for(final f in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final l=FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())));await l.load();}
   t.view.physicalSize=const Size(320,720);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   final first=await store.save('a',title:'Weekend meetup',people:people);await store.markAttempt('a',first);
   await fixture(t,(s,reopen)async{
    await open(t);
    await t.drag(find.byType(CustomScrollView),const Offset(0,3000));await flush(t);
    final openButton=find.byTooltip(t_('Open saved group draft'));expect(t.getRect(openButton).left,greaterThanOrEqualTo(0));expect(t.getRect(openButton).right,lessThanOrEqualTo(320));
    await t.ensureVisible(find.byTooltip(t_('Delete saved group draft')));await flush(t);
    expect(t.getRect(find.byTooltip(t_('Delete saved group draft'))).bottom,lessThan(650));
    expect(t.takeException(),isNull);
    await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('group-draft-shot'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/group_draft_top_${lang}_${mode.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
    await t.tap(find.byTooltip(t_('Delete saved group draft')));await flush(t);expect(find.byType(AlertDialog),findsOneWidget);await t.tap(find.text(t_('Keep')));await flush(t);expect(await store.read('a'),isNotNull);
    await t.ensureVisible(find.text(t_('Back to Chats')));await flush(t);expect(s.posts,0);expect(t.takeException(),isNull);
    await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('group-draft-shot'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/group_draft_${lang}_${mode.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
   },lang:lang,mode:mode,large:true);
  });
 }
}
