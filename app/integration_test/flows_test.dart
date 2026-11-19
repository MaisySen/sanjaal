// Interaction run on an Android emulator against a LOCAL copy of this API with a synthetic member
// (api/tests/E2E). Real taps and typing, real HTTP to the local API. It is not evidence about Auth0,
// the live service, LiveKit, push or media. Nothing here is a real account.
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:sanjaal/reactions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Waits for [f]. On timeout it throws with what is on screen, so the failure names the real state
/// (route, visible text, tooltips) instead of a later tap failing on a missing widget.
Future<void> _until(WidgetTester t, Finder f, {int tries = 24}) async {
  for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
  if (f.evaluate().isNotEmpty) return;
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '').where((s) => s.isNotEmpty).take(25).toList();
  final tips = find.byType(Tooltip).evaluate().map((e) => (e.widget as Tooltip).message ?? '').where((s) => s.isNotEmpty).take(25).toList();
  final routes = find.byType(Scaffold).evaluate().length;
  throw TestFailure('Timed out waiting for $f. Scaffolds: $routes. Visible text: $texts. Tooltips: $tips');
}

Future<void> _type(WidgetTester t, Finder f, String text) async {
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 500));
  await t.showKeyboard(f);
  t.testTextInput.enterText(text);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _settle(WidgetTester t, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flows: like, post, start a chat and send, wallet, rooms list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await p.setString('refresh_token', 'local-e2e');
    app.main();
    await _settle(tester, 24);
    // Synthetic Flutter taps can run behind Android's notification permission
    // window. Resolve only that expected permission for the throwaway CI app,
    // and require native window focus before any input/keyboard assertions.
    final ready = await tester.runAsync(() => http.post(
      Uri.parse('${const String.fromEnvironment('E2E_TOKEN_BASE')}/e2e/native-tap'),
      headers: {'Authorization': 'Bearer ${const String.fromEnvironment('E2E_TOKEN')}', 'Content-Type': 'application/json'},
      body: jsonEncode({'prepare_notifications': true}),
    ).timeout(const Duration(seconds: 45)));
    expect(ready?.statusCode, 200, reason: 'CI notification setup must return native focus to the fixture app. See native_window/native_before artifacts.');
    final nativeReady = jsonDecode(ready!.body) as Map;
    expect(nativeReady['app_focused'], isTrue);
    expect(nativeReady['notification_permission_prepared'], isTrue);
    await tester.pump();
    expect(find.textContaining('Sunrise over Phewa'), findsWidgets);

    // The native-input gate runs before screenshot conversion ever swaps the
    // FlutterView surface. Restoring a previously swapped view can retain focus
    // without making Android's input client perceptible.
    var screenshotConverted = false;
    Future<void> screenshotsReady() async {
      if (screenshotConverted) return;
      await binding.convertFlutterSurfaceToImage();
      screenshotConverted = true;
      await tester.pump();
    }
    final failed = <String>[];
    Future<void> step(String name, Future<void> Function() f) async {
      // ignore: avoid_print
      print('Flow start $name');
      try {
        await f();
        // ignore: avoid_print
        print('Flow passed $name');
      } catch (e, st) {
        failed.add(name);
        // ignore: avoid_print
        print('Error-diag stack $name: ${st.toString().split('\n').where((l) => l.contains('flows_test') || l.contains('widget_tester') || l.contains('finders')).take(4).join(' | ')}');
        // ignore: avoid_print
        print('Error-diag step $name: ${e.toString().split('\n').take(3).join(' | ')}');
        try {
          await screenshotsReady();
          await binding.takeScreenshot('fail_$name');
        } catch (_) {}
        // Return to the tabs so later steps are not hidden behind a pushed page.
        for (var i = 0; i < 4 && find.text('Wallet').evaluate().isEmpty; i++) {
          try {
            await tester.pageBack();
            await tester.pump(const Duration(milliseconds: 500));
            // A failed creator gate can leave a real unsaved draft. Discard it
            // explicitly during cleanup, never bypass the production guard.
            if (find.text('Discard this draft?').evaluate().isNotEmpty) {
              await tester.tap(find.text('Discard'));
              await tester.pump(const Duration(milliseconds: 500));
            }
          } catch (_) {}
        }
      }
    }

    await step('poll', () async {
      await tester.tap(find.byTooltip('Post'));
      await _until(tester, find.text('Continue'));
      await tester.tap(find.text('Post').last);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await _until(tester, find.byType(TextField));
      await _type(tester, find.byType(TextField), 'Emulator poll: meetup day?');
      await tester.tap(find.text('Poll'));
      await _settle(tester, 2);
      await tester.scrollUntilVisible(find.text('Option 2'), 120, scrollable: find.byType(Scrollable).first);
      // Use a native Android pointer for this gate, not the synthetic text
      // channel. This bridge exists only in the throwaway CI fixture router.
      final field = find.widgetWithText(TextField, 'Option 2');
      // Establish the real input client on the untouched Android surface.
      await tester.tap(field);
      await tester.pump();
      await tester.showKeyboard(field);
      await tester.pump();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      final point = tester.getCenter(field) * tester.view.devicePixelRatio;
      // ignore: avoid_print
      print('Native tap coordinates: $point, ratio=${tester.view.devicePixelRatio}, field=${tester.getRect(field)}');
      // Live binding drops physical pointers by default, including adb taps.
      final remove = find.widgetWithText(TextButton, 'Remove poll');
      binding.shouldPropagateDevicePointerEvents = true;
      try {
      final native = await tester.runAsync(() => http.post(
        Uri.parse('${const String.fromEnvironment('E2E_TOKEN_BASE')}/e2e/native-tap'),
        headers: {'Authorization': 'Bearer ${const String.fromEnvironment('E2E_TOKEN')}', 'Content-Type': 'application/json'},
        body: jsonEncode({'x': point.dx.round(), 'y': point.dy.round()}),
      ).timeout(const Duration(seconds: 20)));
      expect(native?.statusCode, 200, reason: 'Native fixture tap must execute, not silently fall back to a mock.');
      for (var i = 0; i < 30 && tester.view.viewInsets.bottom == 0; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
      // ignore: avoid_print
      print('Native IME geometry: test=${tester.view.viewInsets.bottom}, platform=${ui.PlatformDispatcher.instance.implicitView?.viewInsets.bottom}, mocked=${binding.testTextInput.isRegistered}');
      expect(binding.testTextInput.isRegistered, isFalse);
      expect(tester.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText))).widget.focusNode.hasFocus, isTrue, reason: 'The native pointer must focus Option 2, not another control.');
      final inset = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(inset, greaterThan(0), reason: 'This check requires the native emulator keyboard, not only synthetic text input.');
      expect(remove.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(remove).dy, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio - inset));
      } finally {
        binding.shouldPropagateDevicePointerEvents = false;
        // Restore screenshots even when an assertion fails so later checks
        // retain their own evidence instead of cascading surface errors.
        await screenshotsReady();
      }
      await binding.takeScreenshot('flow_poll_native_keyboard');
      await tester.tap(remove);
      await _settle(tester, 2);
      expect(find.text('Photos'), findsOneWidget);
      await tester.tap(find.text('Poll'));
      await _settle(tester, 2);
      await tester.scrollUntilVisible(find.text('Option 1'), 100, scrollable: find.byType(Scrollable).first);
      await _type(tester, find.widgetWithText(TextField, 'Option 1'), 'Saturday');
      await tester.scrollUntilVisible(find.text('Option 2'), 100, scrollable: find.byType(Scrollable).first);
      await _type(tester, find.widgetWithText(TextField, 'Option 2'), 'Sunday');
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await _settle(tester, 6);
      await _until(tester, find.textContaining('Emulator poll: meetup day?'));
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await _settle(tester, 2);
      await tester.ensureVisible(find.text('Saturday'));
      await tester.tap(find.text('Saturday'));
      await _settle(tester, 4);
      expect(find.text('1 vote'), findsOneWidget);
      await binding.takeScreenshot('flow_poll_vote_confirmed');
      await tester.tap(find.text('Remove vote'));
      await _settle(tester, 4);
      expect(find.text('0 votes'), findsOneWidget);
    });
    await screenshotsReady();
    await binding.takeScreenshot('flow1_feed');
    await step('s0', () async {
      await _until(tester, find.byType(ReactionButton));
      await tester.tap(find.byType(ReactionButton).first);
      await _settle(tester, 4);
      expect(find.text('❤️'), findsWidgets);
      await binding.takeScreenshot('flow2_after_like');
    });
    await step('s1', () async {
      await tester.tap(find.byTooltip('Post'));
      await _until(tester, find.text('Continue'));
      await tester.tap(find.text('Post').last);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await _until(tester, find.byType(TextField));
      await _type(tester, find.byType(TextField), 'Posted from the emulator run #sanjaal');
      await tester.pump();
      await binding.takeScreenshot('flow3_compose');
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await _settle(tester, 8);
      // Returning from publish must reveal the post without a manual refresh.
      await _until(tester, find.textContaining('Posted from the emulator run'));
      expect(find.textContaining('Posted from the emulator run'), findsWidgets);
      await binding.takeScreenshot('flow4_post_in_feed');
    });
    await step('s2', () async {
      await tester.tap(find.text('Chats'));
      await _settle(tester, 4);
      await tester.tap(find.byTooltip('New chat'));
      await _settle(tester, 3);
      await _type(tester, find.byType(TextField), 'asha');
      await _settle(tester, 4);
      await binding.takeScreenshot('flow5_find_member');
      await tester.tap(find.text('Asha Gurung').first);
      await _settle(tester, 6);
      await _type(tester, find.byType(TextField), 'Hello from the emulator run');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await _until(tester, find.text('Hello from the emulator run'));
      for(var i=0;i<48 && find.text('Sending').evaluate().isNotEmpty;i++){
        await tester.pump(const Duration(milliseconds:250));
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
      }
      expect(find.text('Sending'), findsNothing, reason:'A local outgoing bubble is not server-confirmed delivery.');
      expect(find.text('Delivery unconfirmed. Tap to retry.'), findsNothing);
      expect(find.text('Hello from the emulator run'), findsWidgets);
      await binding.takeScreenshot('flow6_chat_sent');
      await tester.pageBack();
      await _settle(tester, 4);
      await binding.takeScreenshot('flow7_chat_list');
    });
    await step('s3', () async {
      await tester.tap(find.widgetWithText(TextButton, 'Live rooms'));
      await _until(tester,find.text('No rooms live right now'));
      expect(find.byType(CircularProgressIndicator),findsNothing);
      await binding.takeScreenshot('flow8_rooms_list');
      await tester.pageBack();
      await _settle(tester, 3);
    });
    await step('s4', () async {
      await tester.tap(find.text('Wallet'));
      await _until(tester,find.text('Coins'));
      expect(find.byType(CircularProgressIndicator),findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Add coins')).onPressed,isNull);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Cash out')).onPressed,isNull);
      await binding.takeScreenshot('flow9_wallet');
    });
    expect(failed, isEmpty, reason: 'failed steps: $failed');
  });
}
