import 'dart:convert';
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
}
