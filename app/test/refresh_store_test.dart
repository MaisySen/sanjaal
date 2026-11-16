import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/refresh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const storage = FlutterSecureStorage();
  test('legacy refresh token migrates then leaves ordinary preferences', () async {
    SharedPreferences.setMockInitialValues({'refresh_token': 'legacy-fixture', 'language': 'ne'});
    expect(await RefreshStore.read(), 'legacy-fixture');
    expect(await storage.read(key: 'refresh_token'), 'legacy-fixture');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('refresh_token'), isFalse);
    expect(prefs.getString('language'), 'ne');
  });

  test('secure token wins over a stale legacy copy', () async {
    SharedPreferences.setMockInitialValues({'refresh_token': 'stale-fixture'});
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'secure-fixture'});
    expect(await RefreshStore.read(), 'secure-fixture');
    expect((await SharedPreferences.getInstance()).containsKey('refresh_token'), isFalse);
  });

  test('new token is written only to secure storage', () async {
    SharedPreferences.setMockInitialValues({});
    await RefreshStore.write('new-fixture');
    expect(await storage.read(key: 'refresh_token'), 'new-fixture');
    expect((await SharedPreferences.getInstance()).containsKey('refresh_token'), isFalse);
  });

  test('sign-out clears secure and legacy copies', () async {
    SharedPreferences.setMockInitialValues({'refresh_token': 'legacy-fixture'});
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'secure-fixture'});
    await RefreshStore.clear();
    expect(await RefreshStore.read(), isNull);
    expect(await storage.read(key: 'refresh_token'), isNull);
  });

  test('new login without refresh cannot inherit a previous account token', () async {
    SharedPreferences.setMockInitialValues({});
    await RefreshStore.write('old-account-fixture');
    final session = Session();
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        return http.Response(jsonEncode({'access_token': 'test-only-fixture', 'expires_in': 3600}), 200);
      }
      return http.Response(jsonEncode({'user': {'public_id': 'new-account-fixture'}}), 200);
    });
    await http.runWithClient(() async => session.login('qa-fixture', 'not-a-real-credential'), () => client);
    expect(session.user?['public_id'], 'new-account-fixture');
    expect(await RefreshStore.read(), isNull);
  });
}
