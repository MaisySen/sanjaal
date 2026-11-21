import 'native_transport.dart';
// Android emulator journey against a LOCAL, disposable copy of this API (port 8001) with replay-safe
// uploads switched ON and a one-shot fault: the server saves the post, then the reply is lost (503).
// Real taps and typing through the creator UI, real HTTP, real upload strip. The test checks that
// (1) the member sees a retry, (2) exactly one post exists before the retry, and (3) after Try again
// still exactly one post exists and the strip says it is up. This is local fixture evidence on an
// emulator. It does not change or exercise production, where replay-safe uploads stay off.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:sanjaal/api.dart' show ApiError;
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = String.fromEnvironment('E2E_TOKEN_BASE');
const _token = String.fromEnvironment('E2E_TOKEN');

Future<void> _settle(WidgetTester t, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _until(WidgetTester t, Finder f, {int tries = 40}) async {
  for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
  if (f.evaluate().isNotEmpty) return;
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((s) => s.isNotEmpty).take(25).toList();
  throw TestFailure('Timed out waiting for $f. Visible text: $texts');
}

Future<int> _copies(WidgetTester t, String marker) async {
  final r = await t.runAsync(() => http.get(Uri.parse('$_base/api/v1/posts?kind=post'), headers: {'Authorization': 'Bearer $_token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 30)));
  expect(r?.statusCode, 200);
  return marker.allMatches(utf8.decode(r!.bodyBytes)).length;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('upload: reply lost after the server saved it, then Try again keeps exactly one post', (tester) async {
  await withNativeTransport((transport) async {
    expect(_token, isNotEmpty, reason: 'E2E_TOKEN dart-define missing');
    SharedPreferences.setMockInitialValues({'theme':'light'});
    final p = await SharedPreferences.getInstance();
    await p.setString('refresh_token', 'local-e2e');
    app.main();
    await _settle(tester, 24);
    // Same fixture-only notification setup the flows test uses, so a system dialog does not cover the UI.
    final ready = await tester.runAsync(() => http.post(
      Uri.parse('$_base/e2e/native-tap'),
      headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      body: jsonEncode({'prepare_notifications': true}),
    ).timeout(const Duration(seconds: 45)));
    // ignore: avoid_print
    print('Upload-retry notification setup status ${ready?.statusCode}');
    await tester.pump();
    await _until(tester, find.text('For you'));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();

    final marker = 'Retry journey ${DateTime.now().millisecondsSinceEpoch}';
    final armed = await tester.runAsync(() => http.post(Uri.parse('$_base/e2e/fault-arm'), headers: {'Authorization': 'Bearer $_token'}).timeout(const Duration(seconds: 20)));
    expect(armed?.statusCode, 200, reason: 'fault switch must be armed on the disposable server');

    await tester.tap(find.byTooltip('Post'));
    await _until(tester, find.text('Continue'));
    await tester.tap(find.text('Post').last);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await _until(tester, find.byType(TextField));
    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.showKeyboard(find.byType(TextField).first);
    tester.testTextInput.enterText(marker);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));

    // The reply is lost (server saved, 503 sent). The app may offer Try again or retry by itself; either way the
    // server must end with exactly one copy and the user must see success, never a duplicate or a false failure.
    for (var i = 0; i < 80 && find.text('Try again').evaluate().isEmpty && find.text('Your post is up.').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final offeredRetry = find.text('Try again').evaluate().isNotEmpty;
    expect(offeredRetry, isTrue, reason: 'a lost reply on a replay-safe upload must offer Try again, not claim success');
    // Status proves the intended response was received. Server prose is data,
    // deliberately replaced by reviewed fixed copy in this candidate.
    final center = UploadCenter.of(tester.widget<app.HomeShell>(find.byType(app.HomeShell)).session);
    expect(center.error, isA<ApiError>());
    expect((center.error as ApiError).status, 503);
    expect(find.text('Could not confirm the result. Check before trying again.'), findsOneWidget);
    expect(find.textContaining('Service temporarily unavailable'), findsNothing);
    expect(find.text('Your post is up.'), findsNothing);
    // ignore: avoid_print
    print('Upload-retry after lost reply: offered Try again = $offeredRetry');
    // The widget assertion can precede the raster frame used by the native
    // screenshot extension. Flush rendering before collecting visual evidence.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await binding.takeScreenshot('upload_retry_1_lost_reply');
    final fired = await tester.runAsync(() => http.get(Uri.parse('$_base/e2e/fault-count'), headers: {'Authorization': 'Bearer $_token'}).timeout(const Duration(seconds: 20)));
    // ignore: avoid_print
    print('Upload-retry fault status ${fired?.statusCode} body ${fired?.body}');
    expect(jsonDecode(fired!.body)['fired'], 1, reason: 'the lost-reply fault must have fired exactly once');
    expect(await _copies(tester, marker), 1, reason: 'the server saved the post before the reply was lost');
    if (offeredRetry) {
      await tester.tap(find.text('Try again'));
    }
    await _until(tester, find.text('Your post is up.'));
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('upload_retry_2_after_retry');
    final rootSession=tester.widget<app.HomeShell>(find.byType(app.HomeShell)).session;
    expect(MediaQuery.paddingOf(tester.element(find.byType(FeedPage))).top,0);
    transport.offline=true;await tester.runAsync(transport.idle);
    try { await tester.runAsync(()=>rootSession.call('GET','/calls/incoming')); fail('Offline transport must reject'); } on ApiError { /* Expected real transport failure. */ }
    expect(transport.rejected,greaterThan(0));expect(rootSession.offline,isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Your post is up.'),findsOneWidget);
    expect(find.text('No connection. Some things may be out of date.'),findsOneWidget);
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:250)));
    await binding.takeScreenshot('upload_retry_3_both_status_strips');
    expect(rootSession.offline,isTrue);expect(find.text('Your post is up.'),findsOneWidget);
    center.finishAcknowledgement();await tester.pump(const Duration(milliseconds:600));
    expect(MediaQuery.paddingOf(tester.element(find.byType(FeedPage))).top,0);
    await binding.takeScreenshot('upload_retry_4_offline_only');
    transport.offline=false;
    await tester.runAsync(()=>rootSession.call('GET','/calls/incoming'));
    expect(rootSession.offline,isFalse);await tester.pumpAndSettle();
    await binding.takeScreenshot('upload_retry_5_status_strips_retired');

    expect(find.text('Try again'), findsNothing);
    expect(await _copies(tester, marker), 1, reason: 'retry must reuse the original, never create a second post');
    // ignore: avoid_print
    print('Upload failure/retry journey passed on Android: one post before and after Try again');
  });
  });
}
