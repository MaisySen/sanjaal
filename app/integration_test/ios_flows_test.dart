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
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('iOS keychain migration restore five tabs post and draft storage', (t) async {
  expect(Platform.isIOS,isTrue);
  final p=await SharedPreferences.getInstance();await p.clear();
  await RefreshStore.clear();
  await p.setString('refresh_token','local-e2e');
  expect(await RefreshStore.read(),'local-e2e');expect(p.getString('refresh_token'),isNull);
  const drafts=CreatorDraftStore();
  final draft=await drafts.save('ios-synthetic-owner',text:'Native iOS fixture');
  expect((await drafts.read('ios-synthetic-owner')).any((d)=>d.id==draft.id&&d.text=='Native iOS fixture'),isTrue);
  expect(await drafts.read('ios-other-owner'),isEmpty);
  await drafts.remove('ios-synthetic-owner',draft.id);
  // Actual iOS video plugin and native AVFoundation poster method. The clip
  // is generated synthetic test media served by this job's local API only.
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
  await binding.takeScreenshot('ios_native_avfoundation_poster');
  app.main();
  await until(t,()=>find.textContaining('Sunrise over Phewa').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await binding.takeScreenshot('ios_home');
  for(final tab in ['Reels','Chats','Wallet','Me','Home']) {
   await t.tap(find.text(tab).last);
   await until(t,()=>find.byType(CircularProgressIndicator).evaluate().isEmpty);
   expect(find.text('Could not load this page.'),findsNothing);
   // A predicate can observe rebuilt widgets before the native frame/route
   // transition is presented. Settle that presentation before capturing.
   await t.pump(const Duration(milliseconds:600));
   await binding.takeScreenshot('ios_tab_${tab.toLowerCase()}');
  }
  final session=Session();await t.runAsync(()=>session.restore());
  expect(session.user?['name'],'Synthetic Member');
  await t.tap(find.byTooltip('Post'));
  await until(t,()=>find.text('Post').evaluate().isNotEmpty);
  await until(t,()=>find.text('Continue').evaluate().isNotEmpty);
  await t.tap(find.text('Post').last);await t.pump(const Duration(milliseconds:300));
  await t.tap(find.widgetWithText(FilledButton,'Continue'));
  await until(t,()=>find.byType(TextField).evaluate().isNotEmpty);
  final caption='iOS simulator local post ${DateTime.now().millisecondsSinceEpoch}';
  await t.tap(find.byType(TextField).first);await t.enterText(find.byType(TextField).first,caption);
  await t.pump(const Duration(milliseconds:400));await binding.takeScreenshot('ios_post_test_text_input');
  await t.tap(find.widgetWithText(FilledButton,'Post'));
  await until(t,()=>find.text(caption).evaluate().isNotEmpty&&find.text('Your post is up.').evaluate().isNotEmpty);
  await binding.takeScreenshot('ios_post_confirmed');
  await t.tap(find.text('Chats').last);
  await until(t,()=>find.byTooltip('New chat').evaluate().isNotEmpty);
  await t.tap(find.byTooltip('New chat'));
  await until(t,()=>find.byType(TextField).evaluate().isNotEmpty);
  await t.enterText(find.byType(TextField).first,'asha');
  await until(t,()=>find.text('Asha Gurung').evaluate().isNotEmpty);
  await t.tap(find.text('Asha Gurung').first);
  await until(t,()=>find.byTooltip('Send message').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  const message='iOS simulator server-confirmed local message';
  final messageField=find.widgetWithText(TextField,'Message');
  await t.tap(messageField);await t.pump(const Duration(milliseconds:300));
  await t.enterText(messageField,message);await t.pump(const Duration(milliseconds:400));
  expect(t.widget<TextField>(messageField).controller!.text,message);
  await binding.takeScreenshot('ios_chat_before_send');
  expect(find.byTooltip('Send message').hitTestable(),findsOneWidget);
  await t.tap(find.byTooltip('Send message'));
  await t.pump(const Duration(milliseconds:400));
  await until(t,()=>find.text(message).evaluate().isNotEmpty && find.text('Sending').evaluate().isEmpty);
  expect(find.text('Delivery unconfirmed. Tap to retry.'),findsNothing);
  await t.pump(const Duration(milliseconds:600));
  await binding.takeScreenshot('ios_chat_server_confirmed');
  await t.pageBack();await t.pump(const Duration(milliseconds:600));
  await t.tap(find.widgetWithText(TextButton,'Live rooms'));
  await until(t,()=>find.text('No rooms live right now').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await binding.takeScreenshot('ios_rooms_loaded');
  await t.pageBack();await t.pump(const Duration(milliseconds:600));
  await t.tap(find.text('Me').last);
  await until(t,()=>find.byTooltip('Settings').evaluate().isNotEmpty);
  await t.tap(find.byTooltip('Settings'));
  await until(t,()=>find.text('Settings').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await binding.takeScreenshot('ios_settings');
  await t.runAsync(()=>session.logout());expect(await RefreshStore.read(),isNull);
  expect(p.getString('refresh_token'),isNull);
  await t.pumpWidget(const SizedBox());
  print('iOS simulator local keychain/draft/restore/five-tab/post checks passed; no live service or physical iPhone proof.');
 });
}
