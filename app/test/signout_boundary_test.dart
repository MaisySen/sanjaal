// Synthetic HTTP/storage and delayed notification cleanup only. No live push proof.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';

http.Response reply(Object value, [int status = 200]) => http.Response(jsonEncode(value), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('signout clears identity before pending cleanup completes', () async {
    final cleanup = Completer<void>();
    final session = Session(unregisterPush: (_) => cleanup.future);
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-password');
      var signedOutNotified = false;
      session.addListener(() { if (session.user == null) signedOutNotified = true; });
      final logout = session.logout();
      // Inspect synchronously, before allowing the cleanup future to settle.
      final cleared = session.user == null;
      final notified = signedOutNotified;
      cleanup.complete();
      await logout;
      expect(cleared ? null : 'identity still present', isNull);
      expect(notified, isTrue);
    }, () => MockClient((r) async => r.url.path.endsWith('/oauth/token')
        ? reply({'access_token': 'fixture-old', 'expires_in': 3600})
        : reply({'user': {'public_id': 'owner-a'}})));
  });

  test('late signout cleanup cannot clear a replacement login', () async {
    final cleanup = Completer<void>();
    final session = Session(unregisterPush: (_) => cleanup.future);
    var owner = 'owner-a';
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-password');
      final logout = session.logout();
      owner = 'owner-b';
      await session.login('replacement', 'not-a-password');
      cleanup.complete();
      await logout;
      expect(session.user?['public_id'], 'owner-b');
      expect((await session.privateMediaHeaders('$apiBase/private-media/synthetic'))['Authorization'], 'Bearer fixture-owner-b');
    }, () => MockClient((r) async => r.url.path.endsWith('/oauth/token')
        ? reply({'access_token': 'fixture-$owner', 'expires_in': 3600})
        : reply({'user': {'public_id': owner}})));
  });

  test('private bytes are rejected while signout cleanup is still pending', () async {
    final cleanup = Completer<void>();
    final response = Completer<http.Response>();
    final entered = Completer<void>();
    final session = Session(unregisterPush: (_) => cleanup.future);
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-password');
      final bytes = session.fetchBytes('$apiBase/private-media/synthetic');
      final rejected = expectLater(bytes, throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)));
      await entered.future;
      final logout = session.logout();
      response.complete(http.Response.bytes([1, 2, 3], 200));
      try { await rejected; } finally { cleanup.complete(); await logout; }
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) return reply({'access_token': 'fixture-old', 'expires_in': 3600});
      if (r.url.path.endsWith('/auth/me')) return reply({'user': {'public_id': 'owner-a'}});
      entered.complete();
      return response.future;
    }));
  });

  test('cleanup failure does not restore the signed-out identity', () async {
    final cleanup = Completer<void>();
    final session = Session(unregisterPush: (_) => cleanup.future);
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-password');
      final logout = session.logout();
      final failed = expectLater(logout, throwsStateError);
      cleanup.completeError(StateError('synthetic cleanup failure'));
      await failed;
      expect(session.user, isNull);
      await expectLater(session.privateMediaHeaders('$apiBase/private-media/synthetic'), throwsA(isA<ApiError>()));
    }, () => MockClient((r) async => r.url.path.endsWith('/oauth/token')
        ? reply({'access_token': 'fixture-old', 'expires_in': 3600})
        : reply({'user': {'public_id': 'owner-a'}})));
  });

  for (final status in [200, 302, 401]) {
    test('detached removal uses only old credential and fixed route for status $status', () async {
      final session = Session(unregisterPush: (_) async {});
      var owner = 'owner-a';
      final removals = <http.Request>[];
      await http.runWithClient(() async {
        await session.login('fixture', 'not-a-password');
        final remove = session.capturePushRemoval();
        await session.logout();
        owner = 'owner-b';
        await session.login('replacement', 'not-a-password');
        final removal = remove('fixture-device');
        if (status == 200) { await removal; } else { await expectLater(removal, throwsA(isA<ApiError>())); }
        expect(removals, hasLength(1));
        final request = removals.single;
        expect(request.url.toString(), '$apiBase/devices/remove');
        expect(request.method, 'POST');
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], 'Bearer fixture-owner-a');
        expect(jsonDecode(request.body), {'token': 'fixture-device'});
        expect(session.user?['public_id'], 'owner-b');
      }, () => MockClient((r) async {
        if (r.url.path.endsWith('/oauth/token')) return reply({'access_token': 'fixture-$owner', 'expires_in': 3600});
        if (r.url.path.endsWith('/auth/me')) return reply({'user': {'public_id': owner}});
        removals.add(r);
        return reply({}, status);
      }));
    });
  }
}
