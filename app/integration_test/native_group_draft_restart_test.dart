// Isolated synthetic fixture. Native secure storage, fake search/create replies.
// One installed binary, separate seed/recovery processes. Never contacts API.
import 'dart:convert';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/group_draft_store.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanjaal/api.dart';




const _id=String.fromEnvironment('MARKER_ID');
const _owner='synthetic-group-process-death-fixture';
const _person={'public_id':'00000000-0000-4000-8000-000000000088','username':'fixture-friend','name':'Synthetic friend'};
Future<void> _until(WidgetTester t,bool Function() ready)async{
 for(var i=0;i<100 && !ready();i++){await t.pump(const Duration(milliseconds:100));}
 expect(ready(),isTrue,reason:'native media recovery must settle');
}
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 SemanticsHandle? suiteSemantics;
 setUpAll(()async{
  if(Platform.isIOS){
   suiteSemantics=binding.ensureSemantics();
   final deadline=DateTime.now().add(const Duration(seconds:10));
   while(!ui.PlatformDispatcher.instance.semanticsEnabled && DateTime.now().isBefore(deadline)){await Future<void>.delayed(const Duration(milliseconds:100));}
  }
 });
 tearDownAll(()=>suiteSemantics?.dispose());
 var converted=false;
 Future<void> capture(String name)async{
  if(Platform.isAndroid){if(!converted){await binding.convertFlutterSurfaceToImage();converted=true;}await binding.pump();}
  await binding.takeScreenshot(name);
  if(Platform.isIOS){
   final dir=await getApplicationSupportDirectory();
   await binding.runAsync(()async{
    final pending=File('${dir.path}/$name.native-pending');final done=File('${dir.path}/$name.native-done');
    await pending.writeAsString('waiting',flush:true);
    final deadline=DateTime.now().add(const Duration(seconds:20));
    while(!await done.exists()){
     if(DateTime.now().isAfter(deadline))throw TestFailure('Native screenshot missing $name');
     await Future<void>.delayed(const Duration(milliseconds:100));
    }
   });
  }
 }
 testWidgets('saved group and attempted state survive process death without creation',(t)async{
  final dir=(await t.runAsync(getApplicationSupportDirectory))!;
  final sentinel=Platform.isAndroid?File('/data/user/0/au.fintex.sanjaal/files/synthetic-marker-recover'):File('${dir.path}/synthetic-marker-recover');
  final phase=sentinel.existsSync()?'recover':'seed';
  const store=GroupDraftStore();final title='Private group $_id';
  final identity=File('${dir.path}/saved-group-identity.json');
  final session=NoNetworkSession()..user={'public_id':_owner,'username':'synthetic'}..groupMemberRefsEnabled=true;
  print('GROUP_STAGE phase=$phase');
  if(phase=='seed'){
   expect(await t.runAsync(()=>store.read(_owner)),isNull);
   await t.pumpWidget(MaterialApp(home:NewChatPage(session:session)));
   await t.tap(find.byTooltip('New group'));await t.pumpAndSettle();
   await t.enterText(find.byType(TextField).first,title);
   await t.enterText(find.byType(TextField).last,'fixture-friend');
   await _until(t,()=>find.text('Synthetic friend').evaluate().isNotEmpty);
   await t.tap(find.text('Synthetic friend'));await t.pumpAndSettle();
   FocusManager.instance.primaryFocus?.unfocus();await t.pumpAndSettle();
   await t.ensureVisible(find.byTooltip('Save group draft'));
   await t.tap(find.byTooltip('Save group draft'));
   await _until(t,()=>find.byTooltip('Delete saved group draft').evaluate().isNotEmpty);
   final saved=(await t.runAsync(()=>store.read(_owner)))!;
   expect(saved.title,title);expect(saved.people,[_person]);expect(saved.attempted,false);
   expect(session.posts,0);
   await t.pumpWidget(const SizedBox());await t.pumpAndSettle();
  }else{
   final expected=jsonDecode(await identity.readAsString());
   expect((await t.runAsync(()=>store.read(_owner)))!.toJson(),expected);
   expect(await t.runAsync(()=>store.read('other-group-owner')),isNull);
  }
  await t.pumpWidget(MaterialApp(home:NewChatPage(session:session)));
  await t.tap(find.byTooltip('Open saved group draft'));
  await _until(t,()=>find.text(title).evaluate().isNotEmpty);
  await t.pumpAndSettle();
  expect(find.text('@fixture-friend'),findsOneWidget);
  if(phase=='seed'){
   expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
   await t.ensureVisible(find.byType(FilledButton));await t.tap(find.byType(FilledButton));
   await _until(t,()=>find.text('The chat may already exist. Check Chats before starting it again.').evaluate().isNotEmpty);
   final marked=(await t.runAsync(()=>store.read(_owner)))!;
   expect(marked.attempted,true);expect(marked.title,title);expect(marked.people,[_person]);
   await t.runAsync(()=>identity.writeAsString(jsonEncode(marked.toJson()),flush:true));
  }
  expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
  expect(session.posts,phase=='seed'?1:0);expect(session.reads,phase=='seed'?2:0);
  await capture(phase=='seed'?'media_restart_1_group_saved':'media_restart_2_group_reopened_guarded');
  if(phase=='seed')return;
  await t.tap(find.byTooltip('Delete saved group draft'));await t.pumpAndSettle();
  await t.tap(find.text('Keep'));await t.pumpAndSettle();
  expect(await t.runAsync(()=>store.read(_owner)),isNotNull);
  await t.tap(find.byTooltip('Delete saved group draft'));await t.pumpAndSettle();
  await t.tap(find.text('Delete'));
  await _until(t,()=>find.text(title).evaluate().isEmpty);
  expect(await t.runAsync(()=>store.read(_owner)),isNull);expect(session.posts,phase=='seed'?1:0);expect(session.reads,phase=='seed'?2:0);
  await capture('media_restart_3_group_explicit_delete');
  print('GROUP_STAGE UI Save then simulated lost creation reply; exact identity and attempt marker recovered; other owner isolated; zero actual network; recovery issues no API requests; explicit Keep/Delete');
 });
}
class NoNetworkSession extends Session{
 var posts=0,reads=0;
 @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{
  if(method=='GET' && path=='/users/search') {reads++;return {'users':[_person]};}
  if(method=='POST' && path=='/conversations'){
   posts++;
   final saved=await const GroupDraftStore().read(_owner);
   expect(saved!.attempted,true,reason:'native marker must be durable before simulated create');
   expect(body!['member_refs'],[{'public_id':_person['public_id'],'username':_person['username']}]);
   throw ApiError('Synthetic lost creation reply',503);
  }
  throw StateError('No group fixture may contact API');
 }
}
