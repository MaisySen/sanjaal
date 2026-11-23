import 'native_transport.dart';
import 'native_report_restart.dart';
import 'native_chat_text_restart.dart';
import 'package:sanjaal/chat_pages.dart';
import 'native_capture_barrier.dart';
import 'native_group_journey.dart';
import 'native_first_use_journey.dart';
// Harness adaptation for the reviewed runtime: compact tabs retain tooltips/semantics.
// Real iOS simulator and plugins against a disposable local API only.
// Does not prove Auth0, APNs, phone camera/mic, store signing or physical iPhone behavior.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:sanjaal/video_poster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:sanjaal/api.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/device_access_page.dart';
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
 SemanticsHandle? suiteSemantics;
 setUpAll(() async {
  // Own the suite's accessibility interest before WidgetTester records its
  // per-test baseline. iOS may answer this asynchronously with a platform
  // handle, which otherwise appears to be a test leak during first focus.
  suiteSemantics=binding.ensureSemantics();
  final deadline=DateTime.now().add(const Duration(seconds:10));
  while(!ui.PlatformDispatcher.instance.semanticsEnabled && DateTime.now().isBefore(deadline)){
   await Future<void>.delayed(const Duration(milliseconds:100));
  }
  await stage('semantics baseline handles=${binding.debugOutstandingSemanticsHandles} platform=${ui.PlatformDispatcher.instance.semanticsEnabled}');
 });
 tearDownAll(() {suiteSemantics?.dispose();});
 Future<void> capture(String name) async {
  final previousPolicy = binding.framePolicy;
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  try {
  // Present real application frames, including decoded SVGs and opacity/theme
  // animations, while the host captures OS pixels. A widget predicate alone
  // can otherwise leave a stale native surface under the test frame policy.
  await binding.pump();
  await binding.runAsync(() => Future<void>.delayed(const Duration(milliseconds:400)));
  await binding.pump();
  final result=await binding.takeScreenshot(name);
  final bytes=result;
  final dir=await getTemporaryDirectory();
  final evidence=Directory('${dir.path}/ios-evidence');await evidence.create(recursive:true);
  await File('${evidence.path}/$name.png').writeAsBytes(bytes,flush:true);
  // Stop at each visual boundary until the host captures actual OS pixels.
  await stage('native capture requested $name');
  await nativeCaptureBarrier(
    name: name,
    runAsync: (body) => binding.runAsync(body),
    acknowledge: () async {
      final pending=File('${evidence.path}/$name.native-pending');
      final done=File('${evidence.path}/$name.native-done');
      final request='${DateTime.now().microsecondsSinceEpoch}-$name';
      if(await done.exists())await done.delete();
      final writing=File('${pending.path}-tmp');
      await writing.writeAsString(request,flush:true);
      await writing.rename(pending.path);
      // Native evidence collection can exceed20s on a hosted runner.
      // The barrier still fails closed rather than advancing a stale frame.
      final deadline=DateTime.now().add(const Duration(seconds:120));
      while(DateTime.now().isBefore(deadline)){
        if(await done.exists() && await done.readAsString()==request)return true;
        await Future<void>.delayed(const Duration(milliseconds:100));
      }
      return false;
    },
  );
  await stage('native capture acknowledged $name');
  } finally {
    binding.framePolicy = previousPolicy;
  }
 }
 testWidgets('iOS keychain migration restore five tabs post and draft storage', (t) async {
  try {
  await withNativeTransport((transport) async {
  addTearDown(() async {try {await capture('ios_test_teardown');}catch(_) {}});
  final support = await t.runAsync(getApplicationSupportDirectory);
  final reportRecover = File('${support!.path}/report-restart-recover').existsSync();
  if (reportRecover) {
    final restoredSession = Session();
    await t.runAsync(restoredSession.restore);
    expect(restoredSession.user, isNotNull);
    await nativeChatTextRestartJourney(t, restoredSession, recover:true, waitUntil:(ready)=>until(t,ready), capture:capture, stage:stage);
    await nativeReportRestartJourney(t, restoredSession, recover: true, waitUntil: (ready) => until(t, ready), capture: capture);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(restoredSession.logout);
    await stage('report restart complete');
    return;
  }
  await stage('start');
  expect(Platform.isIOS,isTrue);
  final p=await SharedPreferences.getInstance();await p.clear();
  await RefreshStore.clear();
  await p.setString('theme','light');
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
  final firstUseSession=await nativeFirstUseJourney(t,
      waitUntil: (ready) => until(t, ready), capture: capture, stage: stage);
  await p.setString('refresh_token','local-e2e');
  expect(await RefreshStore.read(),'local-e2e');expect(p.getString('refresh_token'),isNull);
  await t.runAsync(()=>firstUseSession.restore());
  await until(t,()=>find.textContaining('Sunrise over Phewa').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_home');
  await stage('five tabs');
  for(final tab in ['Reels','Chats','Wallet','Me','Home']) {
   await t.tap(find.descendant(of: find.byType(GlassNavBar), matching: find.byTooltip(tab)).hitTestable());
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
  final rootSession=t.widget<app.HomeShell>(find.byType(app.HomeShell)).session;
  final rootUploads=UploadCenter.of(rootSession);
  final feed=find.byType(FeedPage);
  expect(MediaQuery.paddingOf(t.element(feed)).top,0);
  final feedState=t.state(find.byType(FeedList).first);
  expect(await t.runAsync(()=>transport.proveOffline(rootSession)),isTrue,
      reason:'Actual native Session must receive a transport error and increment the socket gate rejection count');
  await t.pumpAndSettle();
  expect(find.text('Your post is up.'),findsOneWidget);
  expect(find.text('No connection. Some things may be out of date.'),findsOneWidget);
  expect(MediaQuery.paddingOf(t.element(feed)).top,0);
  expect(rootUploads.result,isNotNull,reason:'Both-strip native request must start while the real acknowledgement is active');
  // The shipped8s acknowledgement keeps its real wall-clock lifetime. Host
  // simctl capture may take longer, so do not demand it survive capture.
  // Inspect the actual native frame before accepting both-strip pixels.
  await capture('ios_both_status_strips');
  expect(rootSession.offline,isTrue,reason:'Native capture must not silently clear offline');
  rootUploads.finishAcknowledgement();await t.pump(const Duration(milliseconds:600));
  expect(MediaQuery.paddingOf(t.element(feed)).top,0);
  await capture('ios_offline_status_strip');
  expect(await t.runAsync(()=>transport.proveOnline(rootSession)),isTrue,
      reason:'Same native Session must reconnect through the socket gate');
  await t.pumpAndSettle();
  expect(MediaQuery.paddingOf(t.element(feed)).top,greaterThan(0));
  expect(identical(feedState,t.state(find.byType(FeedList).first)),isTrue);
  await capture('ios_status_strips_retired');

  await stage('manual lost-reply journey');
  const base=String.fromEnvironment('E2E_TOKEN_BASE');
  const token=String.fromEnvironment('E2E_TOKEN');
  final headers={'Authorization':'Bearer $token','Accept':'application/json'};
  Future<int> copies(String marker) async {
   final response=await t.runAsync(()=>http.get(Uri.parse('$base/api/v1/posts?kind=post'),headers:headers).timeout(const Duration(seconds:30)));
   expect(response!.statusCode,200);
   final data=jsonDecode(utf8.decode(response.bodyBytes)) as Map;
   return (data['data'] as List).where((p)=>p['body']==marker).length;
  }
  final armed=await t.runAsync(()=>http.post(Uri.parse('$base/e2e/fault-arm'),headers:headers).timeout(const Duration(seconds:20)));
  expect(armed!.statusCode,200);
  await t.tap(find.byTooltip('Post'));await until(t,()=>find.text('Continue').evaluate().isNotEmpty);
  await t.tap(find.text('Post').last);await t.pump();
  await t.tap(find.widgetWithText(FilledButton,'Continue'));
  await until(t,()=>find.byType(TextField).evaluate().isNotEmpty);
  final retryMarker='iOS manual retry ${DateTime.now().millisecondsSinceEpoch}';
  await t.enterText(find.byType(TextField).first,retryMarker);
  await t.pump(const Duration(milliseconds:600));
  expect(t.widget<TextField>(find.byType(TextField).first).controller!.text,retryMarker);
  await t.tap(find.widgetWithText(FilledButton,'Post'));
  await until(t,()=>find.text('Try again').evaluate().isNotEmpty);
  expect(find.text('Your post is up.'),findsNothing);
  final uploadCenter=UploadCenter.of(t.widget<app.HomeShell>(find.byType(app.HomeShell)).session);
  expect(uploadCenter.error,isA<ApiError>());
  expect((uploadCenter.error as ApiError).status,503);
  expect(find.text('Could not confirm the result. Check before trying again.'),findsOneWidget);
  expect(find.textContaining('Service temporarily unavailable'),findsNothing);
  await t.pump(const Duration(milliseconds:600));await capture('ios_upload_reply_lost_retry_offered');
  expect(await copies(retryMarker),1,reason:'server committed before its response was lost');
  final faults=await t.runAsync(()=>http.get(Uri.parse('$base/e2e/fault-count'),headers:headers).timeout(const Duration(seconds:20)));
  expect(jsonDecode(faults!.body)['fired'],1);
  await t.tap(find.text('Try again'));
  await until(t,()=>find.text('Your post is up.').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));await capture('ios_upload_manual_retry_confirmed');
  expect(await copies(retryMarker),1,reason:'manual retry reuses original and cannot create duplicate');
  expect(find.text('Try again'),findsNothing);
  await stage('manual retry exactly one post before and after');
  await stage('chat navigation');
  await t.tap(find.descendant(of: find.byType(GlassNavBar), matching: find.byTooltip('Chats')).hitTestable());
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
  final chatTextConversation=Map<String,dynamic>.of(t.widget<ChatPage>(find.byType(ChatPage)).convo);
  await t.pageBack();await t.pump(const Duration(milliseconds:600));
  await stage('rooms navigation');
  await t.tap(find.widgetWithText(TextButton,'Live rooms'));
  await until(t,()=>find.text('No rooms live right now').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_rooms_loaded');
  await t.pageBack();await t.pump(const Duration(milliseconds:600));
  await nativeGroupJourney(t, rootSession,
      waitUntil: (ready) => until(t, ready), capture: capture, stage: stage);
  await t.tap(find.descendant(of: find.byType(GlassNavBar), matching: find.byTooltip('Me')).hitTestable());
  await until(t,()=>find.byTooltip('Settings').evaluate().isNotEmpty);
  await stage('settings navigation');
  await t.tap(find.byTooltip('Settings'));
  await until(t,()=>find.text('Settings and activity').evaluate().isNotEmpty);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_settings');
  await stage('native device access through settings search');
  await t.tap(find.widgetWithText(TextField,'Search settings'));
  await t.enterText(find.widgetWithText(TextField,'Search settings'),'device');
  await until(t,()=>find.text('Device access').evaluate().isNotEmpty);
  await t.tap(find.text('Device access'));
  await until(t,()=>find.byType(DeviceAccessPage).evaluate().isNotEmpty &&
      find.text('Photos and videos').evaluate().isNotEmpty && t.view.viewInsets.bottom==0);
  final access=await t.runAsync(()=>const DeviceAccessGateway().read());
  expect(access!.platform,'ios');
  expect(access.values['photos'],access.values['videos']);
  for(final key in ['camera','microphone','photos']){
    expect(access.values[key],isNot('unknown'));
    expect(find.text(deviceAccessStates[access.values[key]]!),findsWidgets);
  }
  final openSettings=find.widgetWithText(FilledButton,'Open device settings');
  await t.ensureVisible(openSettings);
  expect(openSettings.hitTestable(),findsOneWidget);
  await t.pump(const Duration(milliseconds:600));
  await capture('ios_native_device_access');
  await t.pageBack();
  await until(t,()=>find.text('Settings and activity').evaluate().isNotEmpty);
  await stage('chat text restart seed');
  await nativeChatTextRestartJourney(t, session, recover:false, conversation:chatTextConversation, waitUntil:(ready)=>until(t,ready), capture:capture, stage:stage);
  await stage('report restart seed');
  await nativeReportRestartJourney(t, session, recover: false, waitUntil: (ready) => until(t, ready), capture: capture);
  await stage('report restart seed complete');
  // Preserve this synthetic session for a new process, not a new install.
  await t.pumpWidget(const SizedBox());
  return;
  });
  } catch (error, stack) {
    // Preserve the test's own cause before the driver exits and OS logs swamp
    // stdout. Only this disposable fixture runs this integration entry point.
    final detail = error.toString(), trace = stack.toString();
    try {
      await stage('native journey failure: ${detail.length > 12000 ? detail.substring(0, 12000) : detail}');
      await stage('native journey stack: ${trace.length > 12000 ? trace.substring(0, 12000) : trace}');
    } catch (_) { /* Diagnostic I/O must not replace the original failure. */ }
    rethrow;
  }
 });
}
