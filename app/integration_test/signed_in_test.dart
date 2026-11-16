// Signed-in flow on an Android emulator against a LOCAL copy of this API with a synthetic member
// (see api/tests/E2E). The app is built with E2E_TOKEN_BASE pointing at the local fixture, which answers
// the token request with a token signed by a throwaway key that the local API trusts. Every API request is
// real HTTP to the local API. This shows the app and API code work together. It is not evidence about
// Auth0 or the live service. The token is a throwaway for a local database, never a real credential.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:sanjaal/api.dart' show Session;
import 'package:sanjaal/refresh_store.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

const _token = String.fromEnvironment('E2E_TOKEN');
const _api = String.fromEnvironment('API_BASE_URL');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed in: feed shows seeded post, profile shows the member', (tester) async {
    expect(_token, isNotEmpty, reason: 'E2E_TOKEN dart-define missing');
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await p.setString('refresh_token', 'local-e2e');
    try {
      final r = await http.get(Uri.parse('$_api/auth/me'), headers: {'Authorization': 'Bearer $_token', 'Accept': 'application/json'});
      // ignore: avoid_print
      print('Error-diag me status ${r.statusCode}');
    } catch (e) {
      // ignore: avoid_print
      print('Error-diag me threw ${e.runtimeType}');
    }
    app.main();
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('signed_in_feed');
    expect(find.textContaining('Sunrise over Phewa'), findsWidgets);

    await tester.tap(find.text('Me'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('signed_in_profile');
    expect(find.textContaining('Synthetic Member'), findsWidgets);

    // Dark theme capture (same fixture, same screens).
    await prefs.setMode(ThemeMode.dark);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('dark_profile');
    await tester.tap(find.text('Home'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('dark_feed');
    await tester.tap(find.text('Wallet'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('dark_wallet');

    // This runs on Android's real plugin, not the unit-test secure-store mock.
    // The fixture credential must migrate out of ordinary preferences and let
    // a fresh Session restore. This is local fixture evidence, not Auth0 proof.
    expect(p.getString('refresh_token'), isNull);
    expect(await RefreshStore.read(), 'local-e2e');
    final restored = Session();
    await restored.restore();
    expect(restored.user?['name'], 'Synthetic Member');
    await restored.logout();
    expect(await RefreshStore.read(), isNull);
    expect(p.getString('refresh_token'), isNull);
    // ignore: avoid_print
    print('Secure storage migration, new-session restore and logout passed on Android');
  });
}
