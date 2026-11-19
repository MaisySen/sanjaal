// Real iOS simulator and plugins against a disposable local API only.
// Does not prove Auth0, APNs, phone camera/mic, store signing or physical iPhone behavior.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:sanjaal/video_poster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:sanjaal/api.dart';
import 'package:sanjaal/refresh_store.dart';
import 'package:sanjaal/creator_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> until(WidgetTester t, bool Function() ready) async {
  for (var i=0;i<100;i++) {
    await t.pump(const Duration(milliseconds:200));
    await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
    if(ready()) return;
  }
  throw TestFailure('iOS local flow did not settle. Visible: ${t.widgetList<Text>(find.byType(Text)).map((w)=>w.data).whereType<String>().take(35).toList()}');
}
Future<void> stage(String value) async {
 final dir=await getTemporaryDirectory();
 await File('${dir.path}/ios-stages.log').writeAsString('${DateTime.now().toIso8601String()} $value\n',mode:FileMode.append,flush:true);
}
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 Future<void> capture(String name) async {
  final result=await binding.takeScreenshot(name);
  final bytes=result;
  final dir=await getTemporaryDirectory();
  final evidence=Directory('${dir.path}/ios-evidence');await evidence.create(recursive:true);
  await File('${evidence.path}/$name.png').writeAsBytes(bytes,flush:true);
  // Stop at each visual boundary until the host captures actual OS pixels.
  await binding.runAsync(() async {
  final pending=File('${evidence.path}/$name.native-pending');
  final done=File('${evidence.path}/$name.native-done');
  await pending.writeAsString('waiting',flush:true);
  final deadline=DateTime.now().add(const Duration(seconds:20));
  while(!await done.exists()){
    if(DateTime.now().isAfter(deadline))throw TestFailure('Native display capture did not acknowledge $name');
    await Future<void>.delayed(const Duration(milliseconds:100));
  }
  });
 }
 testWidgets('iOS keychain migration restore five tabs post and draft storage', (t) async {
  addTearDown(() async {try {await capture('ios_test_teardown');}catch(_) {}});
  await stage('start');
  expect(Platform.isIOS,isTrue);
  final p=await SharedPreferences.getInstance();await p.clear();
  await RefreshStore.clear();
  await p.setString('refresh_token','local-e2e');
  expect(await RefreshStore.read(),'local-e2e');expect(p.getString('refresh_token'),isNull);
  const drafts=CreatorDraftStore();
  final draft=await drafts.save('ios-synthetic-owner',text:'Native iOS fixture');
  expect((await drafts.read('ios-synthetic-owner')).any((d)=>d.id==draft.id&&d.text=='Native iOS fixture'),isTrue);
  expect(await drafts.read('ios-other-owner'),isEmpty);
  await drafts.remove('ios-synthetic-owner',draft.id, expectedRevision: draft.revision);
  // Actual iOS video plugin and native AVFoundation poster method. The clip
  // is generated synthetic test media served by this job's local API only.
  await stage('native video start');
  final nativePoster=await t.runAsync(() async {
    final r=await http.get(Uri.parse('${const String.fromEnvironment('E2E_TOKEN_BASE')}/ios-native-fixture.mp4'));
    expect(r.statusCode,200);
    final dir=await getTemporaryDirectory();
    final file=File('${dir.path}/ios-native-fixture.mp4');await file.writeAsBytes(r.bodyBytes);
    final controller=VideoPlayerController.file(file);
    try {
      await controller.initialize();
      expect(controller.value.duration.inMilliseconds,greaterThan(0));
      expect(controller.value.size.width,160);
      final poster=await VideoPoster.fromPath(file.path);expect(poster,isNotNull);
      final codec=await ui.instantiateImageCodec(poster!);final frame=await codec.getNextFrame();
      expect(frame.image.width,inInclusiveRange(1,320));expect(frame.image.height,inInclusiveRange(1,320));
      frame.image.dispose();codec.dispose();
      await controller.play();await Future<void>.delayed(const Duration(milliseconds:350));await controller.pause();
      expect(controller.value.hasError,isFalse);expect(controller.value.position.inMilliseconds,greaterThan(0));
      return poster;
    } finally {await controller.dispose();await file.delete();}
  });
  expect(nativePoster,isNotNull);
  await t.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(title:const Text('iOS native video poster')),body:Center(child:Image.memory(nativePoster!)))));
  await until(t,()=>t.widgetList<RawImage>(find.byType(RawImage)).any((image)=>image.image!=null));
  await capture('ios_native_avfoundation_poster');
  await stage('app start');
  app.main();
  await until(t,()=>find.textContaining('Sunrise over Phewa').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_home');
  await stage('five tabs');
  for(final tab in ['Reels','Chats','Wallet','Me','Home']) {
   await t.tap(find.text(tab).last);
   await until(t,()=>find.byType(CircularProgressIndicator).evaluate().isEmpty);
   expect(find.text('Could not load this page.'),findsNothing);
   // A predicate can observe rebuilt widgets before the native frame/route
   // transition is presented. Settle that presentation before capturing.
   await t.pump(const Duration(milliseconds:600));
   await capture('ios_tab_${tab.toLowerCase()}');
  }
  await stage('session restore');
  final session=Session();await t.runAsync(()=>session.restore());
  expect(session.user?['name'],'Synthetic Member');
  await stage('post composer');
  await t.tap(find.byTooltip('Post'));
  await until(t,()=>find.text('Post').evaluate().isNotEmpty);
  await until(t,()=>find.text('Continue').evaluate().isNotEmpty);
  await t.tap(find.text('Post').last);await t.pump(const Duration(milliseconds:300));
  await t.tap(find.widgetWithText(FilledButton,'Continue'));
  await until(t,()=>find.byType(TextField).evaluate().isNotEmpty);
  final caption='iOS simulator local post ${DateTime.now().millisecondsSinceEpoch}';
  await t.tap(find.byType(TextField).first);await t.enterText(find.byType(TextField).first,caption);
  await t.pump(const Duration(milliseconds:400));await capture('ios_post_test_text_input');
  await t.tap(find.widgetWithText(FilledButton,'Post'));
  await until(t,()=>find.text(caption).evaluate().isNotEmpty&&find.text('Your post is up.').evaluate().isNotEmpty);
  await capture('ios_post_confirmed');
  await stage('chat navigation');
  await t.tap(find.text('Chats').last);
  await until(t,()=>find.byTooltip('New chat').evaluate().isNotEmpty);
  await t.tap(find.byTooltip('New chat'));
  await until(t,()=>find.byType(TextField).evaluate().isNotEmpty);
  await t.enterText(find.byType(TextField).first,'asha');
  await until(t,()=>find.text('Asha Gurung').evaluate().isNotEmpty);
  await stage('member selected');
  FocusManager.instance.primaryFocus?.unfocus();
  await until(t,()=>t.view.viewInsets.bottom==0);
  await t.pump(const Duration(milliseconds:600));
  await t.tap(find.text('Asha Gurung').first);
  await until(t,()=>find.byTooltip('Send message').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  const message='iOS simulator server-confirmed local message';
  await stage('message input');
  final messageField=find.widgetWithText(TextField,'Message');
  await t.tap(messageField);
  final editable=find.descendant(of:messageField,matching:find.byType(EditableText));
  await until(t,()=>t.widget<EditableText>(editable).focusNode.hasFocus && t.view.viewInsets.bottom>0);
  await t.pump(const Duration(milliseconds:600));
  await stage('chat native keyboard focused inset=${t.view.viewInsets.bottom}');
  await capture('ios_chat_native_keyboard_ready');
  await t.enterText(messageField,message);
  await stage('chat immediate controller=${t.widget<TextField>(messageField).controller!.text.length}');
  expect(t.widget<TextField>(messageField).controller!.text,message);
  await t.pump(const Duration(milliseconds:600));
  await stage('chat settled controller=${t.widget<TextField>(messageField).controller!.text.length}');
  expect(t.widget<TextField>(messageField).controller!.text,message);
  await capture('ios_chat_before_send');
  expect(find.byTooltip('Send message').hitTestable(),findsOneWidget);
  await stage('send tap');
  await t.tap(find.byTooltip('Send message'));
  await t.pump(const Duration(milliseconds:400));
  await stage('await confirmed message');
  await until(t,()=>find.text(message).evaluate().isNotEmpty && find.text('Sending').evaluate().isEmpty);
  expect(find.text('Delivery unconfirmed. Tap to retry.'),findsNothing);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_chat_server_confirmed');
  await t.pageBack();await t.pump(const Duration(milliseconds:600));
  await stage('rooms navigation');
  await t.tap(find.widgetWithText(TextButton,'Live rooms'));
  await until(t,()=>find.text('No rooms live right now').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_rooms_loaded');
  await t.pageBack();await t.pump(const Duration(milliseconds:600));
  await t.tap(find.text('Me').last);
  await until(t,()=>find.byTooltip('Settings').evaluate().isNotEmpty);
  await stage('settings navigation');
  await t.tap(find.byTooltip('Settings'));
  await until(t,()=>find.text('Settings and activity').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_settings');
  await stage('logout');
  await t.runAsync(()=>session.logout());expect(await RefreshStore.read(),isNull);
  expect(p.getString('refresh_token'),isNull);
  await stage('complete');
  await t.pumpWidget(const SizedBox());
  print('iOS simulator local keychain/draft/restore/five-tab/post checks passed; no live service or physical iPhone proof.');
 });
}
