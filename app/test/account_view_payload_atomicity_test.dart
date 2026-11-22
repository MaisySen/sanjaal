// Synthetic account payloads only. No provider or private-account request.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/refresh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Object data) => http.Response(jsonEncode(data), 200);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('cold restore malformed feature payload preserves rotated grant for current recovery', () async {
    FlutterSecureStorage.setMockInitialValues({
      'refresh_token': 'saved-fixture',
    });
    final s = Session();
    var repaired = false, grants = 0;
    await http.runWithClient(
      () async {
        await s.restore();
        expect(s.user, isNull);
        expect(s.restoreError, isNotNull);
        expect(s.accountViewNeedsRefresh, isTrue);
        expect(await RefreshStore.read(), 'rotated-fixture');
        repaired = true;
        await s.recoverAccountView();
        expect(s.user?['public_id'], 'restored');
        expect(s.restoreError, isNull);
        expect(s.accountViewNeedsRefresh, isFalse);
        expect(s.followListsEnabled, isFalse);
        expect(grants, 1);
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/oauth/token')) {
          grants++;
          return reply({
            'access_token': 'restored-fixture',
            'refresh_token': 'rotated-fixture',
            'expires_in': 3600,
          });
        }
        return reply({
          'user': {'public_id': 'restored', 'username': 'restored'},
          if (!repaired) 'features': [],
        });
      }),
    );
    s.dispose();
  });
  for (final malformed in <Object>[[], true, 'invalid', 42]) {
    for (final replacing in [false, true]) {
      test(
        'account view commits atomically with features $malformed replacement $replacing',
        () async {
          final s = Session();
          var replacement = false, repaired = false;
          await http.runWithClient(
            () async {
              if (replacing) await s.login('first', 'fixture');
              replacement = true;
              Object? failure;
              try {
                await s.login('second', 'fixture');
              } catch (e) {
                failure = e;
              }
              expect(
                {
                  'api_error': failure is ApiError,
                  'identity': s.user?['public_id'],
                  'needs_recovery': s.accountViewNeedsRefresh,
                  'recovery_error': s.restoreError != null,
                  'follow_lists': s.followListsEnabled,
                  'discovery': s.discoveryEnabled,
                },
                {
                  'api_error': true,
                  'identity': replacing ? 'first' : null,
                  'needs_recovery': true,
                  'recovery_error': true,
                  'follow_lists': replacing,
                  'discovery': replacing,
                },
              );
              repaired = true;
              await s.recoverAccountView();
              expect(s.user?['public_id'], 'second');
              expect(s.accountViewNeedsRefresh, isFalse);
              expect(s.restoreError, isNull);
              expect(s.followListsEnabled, isFalse);
              expect(s.discoveryEnabled, isFalse);
              expect(s.protectedStoriesEnabled, isFalse);
            },
            () => MockClient((r) async {
              if (r.url.path.endsWith('/oauth/token')) {
                return reply({
                  'access_token': replacement
                      ? 'second-fixture'
                      : 'first-fixture',
                  'expires_in': 3600,
                });
              }
              return reply({
                'user': {
                  'public_id': replacement ? 'second' : 'first',
                  'username': replacement ? 'second' : 'first',
                },
                if (!replacement)
                  'features': {
                    'follow_lists': true,
                    'discovery_v1': true,
                    'protected_stories': true,
                  },
                if (replacement && !repaired) 'features': malformed,
              });
            }),
          );
          s.dispose();
        },
      );
    }
  }
}
