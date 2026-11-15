// Signed-in flow on an Android emulator against a LOCAL copy of this API with a synthetic member
// (see api/tests/E2E). The Auth0 token endpoint is answered by the test with a token signed by a
// throwaway key that the local API trusts; every other request goes to the local API for real.
// This shows the app and API code work together. It is not evidence about Auth0 or the live service.
// The token is a throwaway for a local database, passed with --dart-define, never a real credential.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanjaal/api.dart' show auth0Domain;
import 'package:sanjaal/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

const _token = String.fromEnvironment('E2E_TOKEN');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed in: feed shows seeded post, profile shows the member', (tester) async {
    expect(_token, isNotEmpty, reason: 'E2E_TOKEN dart-define missing');
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await p.setString('refresh_token', 'local-e2e');
    // Created outside runWithClient so forwarding does not call the mock again (that recursed and ran out of memory).
    final real = http.Client();
    await http.runWithClient(() async {
      try {
        final r = await http.get(Uri.parse('${const String.fromEnvironment('API_BASE_URL')}/auth/me'), headers: {'Authorization': 'Bearer $_token', 'Accept': 'application/json'});
        // ignore: avoid_print
        print('Error-diag me status ${r.statusCode} body ${r.body.length > 120 ? r.body.substring(0, 120) : r.body}');
      } catch (e) {
        // ignore: avoid_print
        print('Error-diag me threw ${e.runtimeType} $e');
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
    }, () => MockClient.streaming((req, body) async {
      if (req.url.host == auth0Domain) {
        final b = utf8.encode(jsonEncode({'access_token': _token, 'expires_in': 3000, 'refresh_token': 'local-e2e'}));
        return http.StreamedResponse(Stream.value(b), 200, headers: {'content-type': 'application/json'});
      }
      final r = await real.send(http.Request(req.method, req.url)
        ..headers.addAll(req.headers)
        ..bodyBytes = await body.toBytes());
      return r;
    }));
  });
}
