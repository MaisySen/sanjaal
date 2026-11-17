import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/refresh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'saved-fixture'});
  });
  test('no saved grant opens ordinary authentication without a restore error', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = Session();
    await http.runWithClient(s.restore, () => MockClient((_) => throw StateError('No network expected')));
    expect(s.restoreError, isNull); expect(s.user, isNull); expect(s.loading, isFalse);
  });
  test('transport failure preserves saved grant and exposes explicit retry', () async {
    final s = Session();
    await http.runWithClient(s.restore, () => MockClient((_) => throw http.ClientException('fixture offline')));
    expect(s.restoreError, isNotNull); expect(s.user, isNull); expect(s.loading, isFalse);
    expect(await RefreshStore.read(), 'saved-fixture');
    await http.runWithClient(s.restore, () => MockClient((r) async => r.url.path.endsWith('/oauth/token')
      ? reply({'access_token':'access-fixture','expires_in':3600})
      : reply({'user':{'public_id':'member-fixture'}})));
    expect(s.restoreError, isNull); expect(s.user?['public_id'], 'member-fixture');
  });
  test('only explicit invalid_grant rejection removes the saved refresh', () async {
    final s = Session();
    await http.runWithClient(s.restore, () => MockClient((_) async => reply({'error':'invalid_grant'},400)));
    expect(s.restoreError, isNull); expect(s.user, isNull); expect(await RefreshStore.read(), isNull);
  });
  for (final status in [400,401,403,429,500,503]) {
    test('token endpoint $status without explicit grant rejection remains retryable', () async {
      final s = Session();
      await http.runWithClient(s.restore, () => MockClient((_) async => reply({'error':'service_fixture'},status)));
      expect(s.restoreError, isNotNull); expect(await RefreshStore.read(), 'saved-fixture');
    });
  }
  for (final status in [401,403,503]) {
    test('account read $status does not erase the successfully rotated grant', () async {
      final s = Session();
      await http.runWithClient(s.restore, () => MockClient((r) async => r.url.path.endsWith('/oauth/token')
        ? reply({'access_token':'access-fixture','refresh_token':'rotated-fixture','expires_in':3600})
        : reply({'message':'fixture unavailable'},status)));
      expect(s.restoreError, isNotNull); expect(s.user, isNull); expect(await RefreshStore.read(), 'rotated-fixture');
    });
  }
  test('double retry cannot concurrently reuse a rotating refresh token', () async {
    final pending = Completer<http.Response>(); var calls = 0; final s = Session();
    await http.runWithClient(() async {
      final first = s.restore(); await Future<void>.delayed(Duration.zero);
      final second = s.restore(); await Future<void>.delayed(Duration.zero);
      expect(calls,1); pending.complete(reply({'error':'service_fixture'},503));
      await Future.wait([first,second]);
    }, () => MockClient((_) { calls++; return pending.future; }));
    expect(s.restoreError,isNotNull); expect(s.loading,isFalse);
  });
}
