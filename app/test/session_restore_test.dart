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
  test('concurrent expired API requests share one refresh exchange', () async {
    final s = Session(); var grants = 0; final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await s.login('fixture', 'fixture');
      final requests = ['/posts', '/stories', '/rooms'].map((p) => s.call('GET', p)).toList();
      await Future<void>.delayed(Duration.zero);
      expect(grants, 1);
      pending.complete(reply({'access_token':'renewed-fixture','refresh_token':'next-fixture','expires_in':3600}));
      await Future.wait(requests);
      expect(grants, 1); expect(await RefreshStore.read(), 'next-fixture');
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        final form = Uri.splitQueryString(r.body);
        if (form['grant_type'] == 'password') return reply({'access_token':'old-fixture','refresh_token':'saved-fixture','expires_in':3600});
        grants++; return pending.future;
      }
      if (r.url.path.endsWith('/auth/me')) return reply({'user':{'public_id':'member-fixture'}});
      if (r.headers['Authorization'] == 'Bearer old-fixture') return reply({'message':'expired'},401);
      expect(r.headers['Authorization'], 'Bearer renewed-fixture');
      return reply({'data':[]});
    }));
  });
  test('account replacement rejects the old refresh without overwriting the new grant', () async {
    final s = Session(); final pending = Completer<http.Response>(); var oldReads = 0;
    await http.runWithClient(() async {
      await s.login('first', 'fixture');
      final request = expectLater(s.call('GET', '/posts'), throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      await s.login('second','fixture');
      pending.complete(reply({'access_token':'late-first','refresh_token':'late-first-grant','expires_in':3600}));
      await request;
      expect(s.user?['public_id'],'second'); expect(await RefreshStore.read(),'second-grant'); expect(oldReads,0);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        final form = Uri.splitQueryString(r.body);
        if (form['grant_type'] == 'password') {
          final name = form['username'];
          return reply({'access_token':'$name-access','refresh_token':'$name-grant','expires_in':3600});
        }
        return pending.future;
      }
      if (r.url.path.endsWith('/auth/me')) return reply({'user':{'public_id':r.headers['Authorization'] == 'Bearer second-access' ? 'second' : 'first'}});
      if (r.headers['Authorization'] == 'Bearer first-access') return reply({'message':'expired'},401);
      oldReads++; return reply({'data':[]});
    }));
  });
  test('an old account API response is rejected after signing into another account', () async {
    final s = Session(); final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await s.login('first','fixture');
      final request = expectLater(s.call('GET','/posts'),throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      await s.login('second','fixture');
      pending.complete(reply({'data':['first-private-content']}));
      await request; expect(s.user?['public_id'],'second');
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        final name = Uri.splitQueryString(r.body)['username'];
        return reply({'access_token':'$name-access','refresh_token':'$name-grant','expires_in':3600});
      }
      if (r.url.path.endsWith('/auth/me')) return reply({'user':{'public_id':r.headers['Authorization'] == 'Bearer second-access' ? 'second' : 'first'}});
      return pending.future;
    }));
  });
  test('logout rejects a refresh response that arrives after the session was cleared', () async {
    final s = Session(); final pending = Completer<http.Response>(); var lateReads = 0;
    await http.runWithClient(() async {
      await s.login('fixture', 'fixture');
      final request = expectLater(s.call('GET', '/posts'), throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      await s.logout();
      pending.complete(reply({'access_token':'late-fixture','refresh_token':'late-grant','expires_in':3600}));
      await request;
      expect(s.user,isNull); expect(await RefreshStore.read(),isNull); expect(lateReads,0);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        if (Uri.splitQueryString(r.body)['grant_type'] == 'password') return reply({'access_token':'old-fixture','refresh_token':'saved-fixture','expires_in':3600});
        return pending.future;
      }
      if (r.url.path.endsWith('/auth/me')) return reply({'user':{'public_id':'member-fixture'}});
      if (r.headers['Authorization'] == 'Bearer old-fixture') return reply({'message':'expired'},401);
      lateReads++; return reply({'data':[]});
    }));
  });
  test('failed shared refresh releases its guard and keeps the grant for a later retry', () async {
    final s = Session(); var grants = 0; final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await s.login('fixture', 'fixture');
      final a = expectLater(s.call('GET', '/posts'), throwsA(isA<ApiError>()));
      final b = expectLater(s.call('GET', '/stories'), throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero); expect(grants, 1);
      pending.complete(reply({'error':'temporarily_unavailable'},503));
      await Future.wait([a,b]);
      expect(await RefreshStore.read(), 'saved-fixture');
      await s.call('GET', '/posts'); expect(grants, 2);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        final form = Uri.splitQueryString(r.body);
        if (form['grant_type'] == 'password') return reply({'access_token':'old-fixture','refresh_token':'saved-fixture','expires_in':3600});
        grants++;
        return grants == 1 ? pending.future : reply({'access_token':'retry-fixture','expires_in':3600});
      }
      if (r.url.path.endsWith('/auth/me')) return reply({'user':{'public_id':'member-fixture'}});
      if (r.headers['Authorization'] == 'Bearer old-fixture') return reply({'message':'expired'},401);
      return reply({'data':[]});
    }));
  });

}
