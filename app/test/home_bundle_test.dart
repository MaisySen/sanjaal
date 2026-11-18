import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response ok(Object body) => http.Response(jsonEncode(body), 200);

MockClient fixture(List<String> paths, {bool homeFails = false, Duration homeDelay = Duration.zero}) => MockClient((r) async {
  if (r.url.path.endsWith('/oauth/token')) return ok({'access_token': 'tok', 'expires_in': 3600});
  paths.add(r.url.path);
  if (r.url.path.endsWith('/home')) {
    if (homeDelay > Duration.zero) await Future<void>.delayed(homeDelay);
    return homeFails ? http.Response('{}', 500) : ok({'feed': {'data': [{'public_id': 'p1'}], 'next_cursor': null}, 'stories': {'data': []}, 'unread_messages': 3});
  }
  return ok({'user': {'public_id': 'member-1'}});
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'saved-fixture'});
  });

  test('disabled by default under test: nothing fetched and nothing handed over', () async {
    final paths = <String>[];
    final s = Session();
    await http.runWithClient(() async {
      await s.restore();
      s.prefetchHome();
      expect(await s.takeHome('feed'), isNull);
    }, () => fixture(paths));
    expect(paths.any((p) => p.endsWith('/home')), isFalse);
  });

  test('each part is handed over exactly once, from one request', () async {
    final paths = <String>[];
    final s = Session()..homeBundleEnabled = true;
    await http.runWithClient(() async {
      await s.restore();
      s.prefetchHome();
      final feed = await s.takeHome('feed') as Map;
      expect((feed['data'] as List).length, 1);
      expect(await s.takeHome('feed'), isNull);
      expect(await s.takeHome('unread_messages'), 3);
      expect(await s.takeHome('stories'), isA<Map>());
    }, () => fixture(paths));
    expect(paths.where((p) => p.endsWith('/home')).length, 1);
  });

  test('a failing bundle falls back: callers get null and make their own request', () async {
    final paths = <String>[];
    final s = Session()..homeBundleEnabled = true;
    await http.runWithClient(() async {
      await s.restore();
      s.prefetchHome();
      expect(await s.takeHome('feed'), isNull);
      expect(await s.takeHome('stories'), isNull);
    }, () => fixture(paths, homeFails: true));
  });

  test('sign-in as another account drops an unconsumed bundle', () async {
    final paths = <String>[];
    final s = Session()..homeBundleEnabled = true;
    await http.runWithClient(() async {
      await s.restore();
      s.prefetchHome();
      await s.login('another', 'not-a-password');
      expect(await s.takeHome('feed'), isNull);
      expect(await s.takeHome('unread_messages'), isNull);
    }, () => fixture(paths));
  });

  test('a slow reply (older than the window by the time it lands) is still handed over fresh', () async {
    final paths = <String>[];
    final s = Session()..homeBundleEnabled = true;
    await http.runWithClient(() async {
      await s.restore();
      s.prefetchHome();
      final feed = await s.takeHome('feed') as Map;
      expect((feed['data'] as List).length, 1);
    }, () => fixture(paths, homeDelay: const Duration(milliseconds: 5300)));
    expect(paths.where((p) => p.endsWith('/home')).length, 1);
  });
  test('late old-account bundle cannot clear the new account pending bundle', () async {
    final oldReply = Completer<http.Response>();
    final newReply = Completer<http.Response>();
    var homeCalls = 0;
    final s = Session()..homeBundleEnabled = true;
    await http.runWithClient(() async {
      await s.login('first', 'fixture');
      s.prefetchHome();
      final oldTake = s.takeHome('feed');
      await Future<void>.delayed(Duration.zero);
      await s.login('second', 'fixture');
      s.prefetchHome();
      await Future<void>.delayed(Duration.zero);
      oldReply.complete(ok({'feed': {'data': ['old-private']}}));
      expect(await oldTake, isNull);
      expect(s.homePending, isTrue, reason: 'old work must not discard the replacement bundle');
      newReply.complete(ok({'feed': {'data': ['new-account']}}));
      expect(await s.takeHome('feed'), {'data': ['new-account']});
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) return ok({'access_token':'fixture','expires_in':3600});
      if (r.url.path.endsWith('/home')) return ++homeCalls == 1 ? oldReply.future : newReply.future;
      return ok({'user':{'public_id':'member-$homeCalls'}});
    }));
  });

  test('superseded same-account bundle cannot overwrite the newest handover', () async {
    final first = Completer<http.Response>(), second = Completer<http.Response>();
    var count = 0;
    final s = Session()..homeBundleEnabled = true;
    await http.runWithClient(() async {
      await s.restore(); s.prefetchHome(); final oldTake = s.takeHome('feed');
      await Future<void>.delayed(Duration.zero);
      s.prefetchHome(); await Future<void>.delayed(Duration.zero);
      first.complete(ok({'feed': {'data':['superseded']}}));
      expect(await oldTake,isNull); expect(s.homePending,isTrue);
      second.complete(ok({'feed': {'data':['newest']}}));
      final parts = await Future.wait([s.takeHome('feed'),s.takeHome('feed')]);
      expect(parts.whereType<Map>().toList(),[{'data':['newest']}]);
      expect(parts.where((p)=>p==null).length,1);
    },()=>MockClient((r) async {
      if(r.url.path.endsWith('/oauth/token')) return ok({'access_token':'fixture','expires_in':3600});
      if(r.url.path.endsWith('/home')) return ++count==1 ? first.future : second.future;
      return ok({'user':{'public_id':'member'}});
    }));
  });

}
