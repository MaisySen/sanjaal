// Isolated synthetic fixture. Native secure storage and encrypted private files.
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
  final session=NoNetworkSession()..user={'public_id':_owner,'username':'synthetic'};
  print('GROUP_STAGE phase=$phase');
  if(phase=='seed'){
   expect(await t.runAsync(()=>store.read(_owner)),isNull);
   final first=(await t.runAsync(()=>store.save(_owner,title:title,people:[{'public_id':'stable-friend-fixture','username':'fixture-friend','name':'Synthetic friend'}])))!;
   final saved=(await t.runAsync(()=>store.markAttempt(_owner,first)))!;
   await t.runAsync(()=>identity.writeAsString(jsonEncode(saved.toJson()),flush:true));
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
  expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
  expect(session.requests,0);
  await capture(phase=='seed'?'media_restart_1_group_saved':'media_restart_2_group_reopened_guarded');
  if(phase=='seed')return;
  await t.tap(find.byTooltip('Delete saved group draft'));await t.pumpAndSettle();
  await t.tap(find.text('Keep'));await t.pumpAndSettle();
  expect(await t.runAsync(()=>store.read(_owner)),isNotNull);
  await t.tap(find.byTooltip('Delete saved group draft'));await t.pumpAndSettle();
  await t.tap(find.text('Delete'));
  await _until(t,()=>find.text(title).evaluate().isEmpty);
  expect(await t.runAsync(()=>store.read(_owner)),isNull);expect(session.requests,0);
  await capture('media_restart_3_group_explicit_delete');
  print('GROUP_STAGE exact identity and attempted marker recovered; other owner isolated; no requests; explicit Keep/Delete');
 });
}
class NoNetworkSession extends Session{
 var requests=0;
 @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{requests++;throw StateError('No group fixture may contact API');}
}
