import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/refresh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const owner = '12345678-1234-1234-1234-123456789abc';
const other = 'abcdefab-1234-1234-1234-123456789abc';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('verified owner lease survives store reload and is not in preferences', () async {
    final first = await RefreshStore.callLease(owner);
    expect(first, matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(await RefreshStore.callLease(owner), first);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
  test('owner replacement, corrupt metadata and explicit clear cannot reuse lease', () async {
    final first = await RefreshStore.callLease(owner);
    final second = await RefreshStore.callLease(other);
    expect(second, isNot(first));
    FlutterSecureStorage.setMockInitialValues({'native_call_login_lease_v1': '{invalid'});
    final third = await RefreshStore.callLease(owner);
    expect(third, isNot(first));
    await RefreshStore.clear();
    expect(await RefreshStore.callLease(owner), isNot(third));
    expect(await RefreshStore.callLease('malformed'), isNull);
  });
  test('real Session restores same login lease but rotates same-account replacement', () async {
    final client = MockClient((r) async => http.Response(jsonEncode(r.url.path.endsWith('/oauth/token')
      ? {'access_token': 'synthetic', 'refresh_token': 'synthetic-refresh', 'expires_in':3600}
      : {'user': {'public_id': owner}}), 200));
    await http.runWithClient(() async {
      final first = Session(unregisterPush: (_) async {});
      expect(first.nativeCallLease, isNull);
      await first.login('fixture', 'fixture');
      // App root normally clears loading through restore first.
      first.loading = false;
      final lease = first.nativeCallLease;
      expect(lease, isNotNull);
      final restored = Session(unregisterPush: (_) async {});
      await restored.restore();
      expect(restored.nativeCallLease, lease);
      await restored.login('fixture', 'fixture');
      expect(restored.nativeCallLease, isNot(lease));
      expect(restored.nativeCallLease, isNotNull);
      await restored.logout();
      expect(restored.nativeCallLease, isNull);
      expect(await const FlutterSecureStorage().read(key:'native_call_login_lease_v1'), isNull);
    }, () => client);
  });
  test('replacement login hides lease immediately while network is pending', () async {
    final pending = Completer<http.Response>();
    var grants = 0;
    await http.runWithClient(() async {
      final session = Session();
      session.loading = false;
      await session.login('first', 'fixture');
      expect(session.nativeCallLease, isNotNull);
      final login = session.login('second', 'fixture');
      expect(session.nativeCallLease, isNull);
      pending.complete(http.Response(jsonEncode({'error':'invalid_grant'}), 400));
      await expectLater(login, throwsA(isA<ApiError>()));
      expect(session.nativeCallLease, isNull);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        if (++grants == 2) return pending.future;
        return http.Response(jsonEncode({'access_token':'synthetic','refresh_token':'synthetic-refresh'}),200);
      }
      return http.Response(jsonEncode({'user':{'public_id':owner}}),200);
    }));
  });
  test('ordinary access-token refresh retains restored login lease', () async {
    var expired = true;
    await http.runWithClient(() async {
      final session = Session()..loading = false;
      await session.login('fixture','fixture');
      final lease = session.nativeCallLease;
      await session.call('GET','/posts');
      expect(session.nativeCallLease, lease);
      expect(await RefreshStore.callLease(owner), lease);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        return http.Response(jsonEncode({'access_token':'synthetic','refresh_token':'rotating-synthetic'}),200);
      }
      if (r.url.path.endsWith('/auth/me')) return http.Response(jsonEncode({'user':{'public_id':owner}}),200);
      if (expired) { expired = false; return http.Response('{}',401); }
      return http.Response('{}',200);
    }));
  });
  test('failed identity restoration never exposes persisted lease', () async {
    await RefreshStore.write('fixture');
    await RefreshStore.callLease(owner);
    final session = Session();
    await http.runWithClient(session.restore, () => MockClient((r) async => http.Response(jsonEncode(
      r.url.path.endsWith('/oauth/token') ? {'access_token':'synthetic'} : {'message':'unavailable'}),
      r.url.path.endsWith('/oauth/token') ? 200 : 503)));
    expect(session.nativeCallLease, isNull);
    expect(session.restoreError, isNotNull);
  });
}
