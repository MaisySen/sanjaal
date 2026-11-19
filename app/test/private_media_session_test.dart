// Synthetic HTTP responses only. No real account mutation or media upload.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(jsonEncode(data), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final method in ['chat bytes', 'protected story']) {
    for (final change in ['logout', 'other account', 'same account new login']) {
      test('$method rejects delayed bytes after $change', () async {
        final session = Session();
        var account = 'owner-a';
        final pending = Completer<http.Response>();
        final entered = Completer<void>();
        var mediaReads = 0;
        await http.runWithClient(() async {
          await session.login('fixture', 'not-a-password');
          final url = '$apiBase/private-media/synthetic';
          final bytes = method == 'chat bytes'
            ? session.fetchBytes(url) : session.fetchProtectedBytes(url);
          final rejected = expectLater(bytes, throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)));
          await entered.future;
          if (change == 'logout') {
            await session.logout();
          } else {
            if (change == 'other account') account = 'owner-b';
            await session.login('replacement', 'not-a-password');
          }
          pending.complete(http.Response.bytes([1, 2, 3], 200));
          await rejected;
          expect(mediaReads, 1);
          expect(session.user?['public_id'], change == 'logout' ? null : account);
        }, () => MockClient((r) async {
          if (r.url.path.endsWith('/oauth/token')) return reply({'access_token': 'fixture-access', 'expires_in': 3600});
          if (r.url.path.endsWith('/auth/me')) return reply({'user': {'public_id': account}});
          if (r.url.path.endsWith('/devices/remove')) return reply({});
          mediaReads++;
          if (!entered.isCompleted) entered.complete();
          return pending.future;
        }));
      });
    }
  }
  test('private media headers never escape a superseded session', () async {
    final session = Session();
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-password');
      final headers = session.privateMediaHeaders('$apiBase/private-media/synthetic');
      final rejected = expectLater(headers, throwsA(isA<ApiError>()));
      // Login increments the epoch synchronously before its first await.
      await session.login('replacement', 'not-a-password');
      await rejected;
    }, () => MockClient((r) async => r.url.path.endsWith('/oauth/token')
      ? reply({'access_token': 'fixture-access', 'expires_in': 3600})
      : reply({'user': {'public_id': 'owner-a'}})));
  });
}
