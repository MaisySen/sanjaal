// Interaction run on an Android emulator against a LOCAL copy of this API with a synthetic member
// (api/tests/E2E). Real taps and typing, real HTTP to the local API. It is not evidence about Auth0,
// the live service, LiveKit, push or media. Nothing here is a real account.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

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

    // Like a post.
    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await _settle(tester, 4);
    expect(find.byIcon(Icons.favorite_border), findsWidgets);
    await binding.takeScreenshot('flow2_after_like');

    // Compose a post.
    await tester.tap(find.byTooltip('Post'));
    await _settle(tester, 4);
    await tester.enterText(find.byType(TextField).first, 'Posted from the emulator run #sanjaal');
    await tester.pump();
    await binding.takeScreenshot('flow3_compose');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await _settle(tester, 8);
    expect(find.textContaining('Posted from the emulator run'), findsWidgets);
    await binding.takeScreenshot('flow4_post_in_feed');

    // Start a chat and send a message.
    await tester.tap(find.text('Chats'));
    await _settle(tester, 4);
    await tester.tap(find.text('New chat'));
    await _settle(tester, 3);
    await tester.enterText(find.byType(TextField).first, 'asha');
    await _settle(tester, 4);
    await binding.takeScreenshot('flow5_find_member');
    await tester.tap(find.text('Asha Gurung').first);
    await _settle(tester, 6);
    await tester.enterText(find.byType(TextField).last, 'Hello from the emulator run');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await _settle(tester, 6);
    expect(find.text('Hello from the emulator run'), findsWidgets);
    await binding.takeScreenshot('flow6_chat_sent');
    await tester.pageBack();
    await _settle(tester, 4);
    await binding.takeScreenshot('flow7_chat_list');

    // Live rooms list (list only; no room is joined, no LiveKit).
    await tester.tap(find.byTooltip('Live rooms'));
    await _settle(tester, 6);
    await binding.takeScreenshot('flow8_rooms_list');
    await tester.pageBack();
    await _settle(tester, 3);

    // Wallet.
    await tester.tap(find.text('Wallet'));
    await _settle(tester, 8);
    await binding.takeScreenshot('flow9_wallet');
  });
}
