// Signed-in flow on an Android emulator against a LOCAL copy of this API with a synthetic member
// (see api/tests/E2E). The app is built with E2E_TOKEN_BASE pointing at the local fixture, which answers
// the token request with a token signed by a throwaway key that the local API trusts. Every API request is
// real HTTP to the local API. This shows the app and API code work together. It is not evidence about
// Auth0 or the live service. The token is a throwaway for a local database, never a real credential.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:sanjaal/main.dart' as app;
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
  });
}
