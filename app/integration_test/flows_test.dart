// Interaction run on an Android emulator against a LOCAL copy of this API with a synthetic member
// (api/tests/E2E). Real taps and typing, real HTTP to the local API. It is not evidence about Auth0,
// the live service, LiveKit, push or media. Nothing here is a real account.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _until(WidgetTester t, Finder f, {int tries = 24}) async {
  for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
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
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    expect(find.textContaining('Sunrise over Phewa'), findsWidgets);
    await binding.takeScreenshot('flow1_feed');

    final failed = <String>[];
    Future<void> step(String name, Future<void> Function() f) async {
      try {
        await f();
      } catch (e, st) {
        failed.add(name);
        // ignore: avoid_print
        print('Error-diag stack $name: ${st.toString().split('\n').where((l) => l.contains('flows_test') || l.contains('widget_tester') || l.contains('finders')).take(4).join(' | ')}');
        // ignore: avoid_print
        print('Error-diag step $name: ${e.toString().split('\n').take(3).join(' | ')}');
        try {
          await binding.takeScreenshot('fail_$name');
        } catch (_) {}
        // Return to the tabs so later steps are not hidden behind a pushed page.
        for (var i = 0; i < 4 && find.text('Wallet').evaluate().isEmpty; i++) {
          try {
            await tester.pageBack();
            await tester.pump(const Duration(milliseconds: 500));
          } catch (_) {}
        }
      }
    }

    await step('s0', () async {
      await tester.tap(find.byIcon(Icons.favorite_border).first);
      await _settle(tester, 4);
      expect(find.byIcon(Icons.favorite_border), findsWidgets);
      await binding.takeScreenshot('flow2_after_like');
    });
    await step('s1', () async {
      await tester.tap(find.byTooltip('Post'));
      await _until(tester, find.byType(TextField));
      await _type(tester, find.byType(TextField), 'Posted from the emulator run #sanjaal');
      await tester.pump();
      await binding.takeScreenshot('flow3_compose');
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await _settle(tester, 8);
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
      await _settle(tester, 6);
      expect(find.text('Hello from the emulator run'), findsWidgets);
      await binding.takeScreenshot('flow6_chat_sent');
      await tester.pageBack();
      await _settle(tester, 4);
      await binding.takeScreenshot('flow7_chat_list');
    });
    await step('s3', () async {
      await tester.tap(find.byTooltip('More'));
      await _settle(tester, 2);
      await tester.tap(find.text('Live rooms'));
      await _settle(tester, 6);
      await binding.takeScreenshot('flow8_rooms_list');
      await tester.pageBack();
      await _settle(tester, 3);
    });
    await step('s4', () async {
      await tester.tap(find.text('Wallet'));
      await _settle(tester, 8);
      await binding.takeScreenshot('flow9_wallet');
    });
    expect(failed, isEmpty, reason: 'failed steps: $failed');
  });
}
