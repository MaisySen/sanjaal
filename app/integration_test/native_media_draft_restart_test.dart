// Isolated synthetic fixture. Native secure storage and encrypted private files.
// One installed binary, separate seed/recovery processes. Never contacts API.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/creator_drafts_page.dart';
import 'package:sanjaal/creator_media_draft_store.dart';
import 'package:sanjaal/upload_center.dart';

const _id=String.fromEnvironment('MARKER_ID');
const _owner='synthetic-media-process-death-fixture';
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
 testWidgets('encrypted photo and video survive process death without resend',(t)async{
  final dir=(await t.runAsync(getApplicationSupportDirectory))!;
  final sentinel=Platform.isAndroid?File('/data/user/0/au.fintex.sanjaal/files/synthetic-marker-recover'):File('${dir.path}/synthetic-marker-recover');
  final phase=sentinel.existsSync()?'recover':'seed';
  const store=CreatorMediaDraftStore();
  final session=Session()..user={'public_id':_owner,'username':'synthetic'};
  final identity=File('${dir.path}/saved-media-identity.json');
  final caption='Saved photo $_id';final videoCaption='Guarded video $_id';final storyCaption='Private story $_id';
  print('MEDIA_STAGE phase=$phase');
  if(phase=='seed'){
   expect(await t.runAsync(()=>store.read(_owner)),isEmpty);
   final rows=<Map<String,dynamic>>[];
   for(final selection in [(false,false),(true,false),(false,true)]){
    final video=selection.$1;final story=selection.$2;
    final asset=video?'test/fixtures/ios_synthetic_video.mp4':'test/fixtures/ridge.png';
    final bytes=(await rootBundle.load(asset)).buffer.asUint8List();
    final source=File('${dir.path}/temporary-picker.${video?'mp4':'png'}');
    await t.runAsync(()=>source.writeAsBytes(bytes,flush:true));
    var draft=(await t.runAsync(()=>store.save(_owner,text:story?storyCaption:video?videoCaption:caption,video:video,files:[XFile(source.path)],story:story,audience:story?'only_me':null)))!;
    if(video || story)draft=(await t.runAsync(()=>store.attempted(_owner,draft,value:true)))!;
    rows.add({'draft':draft.toJson(),'sha256':sha256.convert(bytes).toString()});
    await t.runAsync(source.delete);
    expect(source.existsSync(),isFalse);
   }
   await t.runAsync(()=>identity.writeAsString(jsonEncode(rows),flush:true));
   await t.pumpWidget(MaterialApp(home:CreatorDraftsPage(session:session)));
   await _until(t,()=>find.text(caption).evaluate().isNotEmpty);
   expect(find.text(videoCaption),findsOneWidget);
   await capture('media_restart_1_saved_picker_deleted');
   return;
  }
  expect(File('${dir.path}/temporary-picker.png').existsSync(),isFalse);
  expect(File('${dir.path}/temporary-picker.mp4').existsSync(),isFalse);
  final expected=jsonDecode(await identity.readAsString()) as List;
  final drafts=(await t.runAsync(()=>store.read(_owner)))!;
  expect(drafts.length,3);
  expect(await t.runAsync(()=>store.read('other-media-owner')),isEmpty);
  for(final row in expected){
   final prior=CreatorMediaDraft.decode(row['draft']);
   final current=drafts.singleWhere((d)=>d.id==prior.id);
   expect(current.toJson(),prior.toJson());
   final files=(await t.runAsync(()=>store.open(_owner,current)))!;
   expect(sha256.convert(await files.single.readAsBytes()).toString(),row['sha256']);
   expect(files.single.name,current.names.single);
   await expectLater(t.runAsync(()=>store.open('other-media-owner',current)),throwsStateError);
  }
  await t.pumpWidget(MaterialApp(home:CreatorDraftsPage(session:session)));
  await _until(t,()=>find.text(caption).evaluate().isNotEmpty);
  await t.tap(find.text(caption));
  await _until(t,()=>find.byType(TextField).evaluate().isNotEmpty);
  await t.pumpAndSettle();
  expect(t.widget<TextField>(find.byType(TextField)).controller!.text,caption);
  expect(find.byType(Image),findsWidgets);
  await capture('media_restart_2_photo_reopened');
  await t.pageBack();await t.pumpAndSettle();
  await t.tap(find.text(videoCaption));
  await _until(t,()=>find.text('Prepare a separate upload').evaluate().isNotEmpty);
  await t.pumpAndSettle();
  expect(find.text('media.mp4'),findsOneWidget);
  expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Post')).onPressed,isNull);
  await capture('media_restart_3_video_guarded');
  await t.pageBack();await t.pumpAndSettle();
  session.protectedStoriesEnabled=true;
  await t.tap(find.text(storyCaption));
  await _until(t,()=>find.text('Prepare a separate upload').evaluate().isNotEmpty);
  await t.pumpAndSettle();
  expect(find.text('Only me'),findsOneWidget);
  await t.scrollUntilVisible(find.byType(TextField),150,scrollable:find.byType(Scrollable).first);
  expect(t.widget<TextField>(find.byType(TextField)).controller!.text,storyCaption);
  await t.drag(find.byType(ListView).first,const Offset(0,700));await t.pumpAndSettle();
  expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Share story')).onPressed,isNull);
  await capture('media_restart_4_story_only_me_guarded');
  await t.pageBack();await t.pumpAndSettle();
  for(var i=0;i<3;i++){
   await t.tap(find.byTooltip('Delete draft').first);await t.pumpAndSettle();
   await t.tap(find.text('Keep'));await t.pumpAndSettle();
   expect((await t.runAsync(()=>store.read(_owner)))!.length,3-i);
   await t.tap(find.byTooltip('Delete draft').first);await t.pumpAndSettle();
   await t.tap(find.widgetWithText(TextButton,'Delete'));await t.pumpAndSettle();
   await _until(t,()=>find.byTooltip('Delete draft').evaluate().length==2-i);
  }
  expect(await t.runAsync(()=>store.read(_owner)),isEmpty);
  expect(UploadCenter.of(session).result,isNull);
  expect(UploadCenter.of(session).confirmedPosts,isEmpty);
  expect(UploadCenter.of(session).occupied,isFalse);
  await capture('media_restart_5_explicit_delete');
  print('MEDIA_STAGE exact bytes photo/video restored; picker absent; other owner isolated; attempted guard retained; no send; explicit deletes');
 });
}
