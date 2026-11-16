// Explicit opt-in, read-only live verification using an existing QA identity.
// SANJAAL_QA_LOGIN_FILE points at a private JSON file with username/password.
// Never create identities, publish posts, contact people, or spend from this test.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sanjaal/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReadOnlyClient extends http.BaseClient {
  final _inner = IOClient();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final token = request.url == Uri.https(auth0Domain, '/oauth/token');
    if (!(token && request.method == 'POST') && request.method != 'GET') {
      throw StateError('Live verification forbids API mutations.');
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

void main() {
  final credentialFile = Platform.environment['SANJAAL_QA_LOGIN_FILE'];
  test('existing QA login and read-only API routes use the real Session client', () async {
    final credentials = jsonDecode(await File(credentialFile!).readAsString()) as Map;
    SharedPreferences.setMockInitialValues({});
    await http.runWithClient(() async {
        final session = Session();
        await session.login(credentials['username'] as String, credentials['password'] as String);
        expect(session.user?['public_id'], isNotEmpty);
        for (final path in ['/posts', '/saved', '/conversations', '/wallet/withdrawals', '/rooms']) {
          final result = await session.call('GET', path) as Map;
          expect(result['data'], isA<List>(), reason: '$path schema');
        }
        final wallet = await session.call('GET', '/wallet') as Map;
        expect(wallet['cashout'], isA<Map>());
        expect((wallet['cashout'] as Map)['available'], isFalse);
        await session.logout();
        expect(session.user, isNull);
    }, () => _ReadOnlyClient());
  }, skip: credentialFile == null ? 'SANJAAL_QA_LOGIN_FILE not set' : false,
    timeout: const Timeout(Duration(minutes: 3)));
}
