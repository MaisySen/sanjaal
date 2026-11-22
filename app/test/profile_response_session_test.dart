// Isolated synthetic profile/avatar HTTP responses. No native picker or live account.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';

http.Response json(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  signOutRace();
  envelopeCases();
  startCases();
  statusCases();
  for (final avatar in [false, true]) {
    for (final invalid in <String, Map<String, dynamic>>{
      'foreign owner': {
        'public_id': 'other',
        'username': 'other',
        'name': 'Other member',
      },
      'null owner': {'public_id': null},
      'typed name': {'name': <String>[]},
      'typed username': {'username': 7},
      'typed bio': {
        'bio': <String, String>{'unexpected': 'shape'},
      },
      'null name': {'name': null},
      'null username': {'username': null},
      'typed avatar URL': {'avatar_url': <String>[]},
      'numeric owner': {'public_id': 7},
      'empty owner': {'public_id': ''},
      'mixed valid and invalid fields': {
        'name': 'Must not apply',
        'username': 7,
      },
      'unknown fields only': {
        'capabilities': {'admin': true},
      },
    }.entries) {
      test(
        '${avatar ? 'avatar' : 'profile'} rejects ${invalid.key} before changing the session view',
        () async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          var writes = 0;
          await http.runWithClient(
            () async {
              final s = Session();
              await s.login('fixture', 'not-a-password');
              final before = Map<String, dynamic>.from(s.user!);
              var notifications = 0;
              s.addListener(() => notifications++);
              try {
                if (avatar) {
                  await s.uploadAvatar(
                    UploadFile(
                      Uint8List.fromList([1, 2, 3]),
                      'image/jpeg',
                      'fixture.jpg',
                    ),
                  );
                } else {
                  await s.updateProfile({'name': 'Updated name'});
                }
              } catch (_) {}
              expect(writes, 1);
              expect(s.user, before);
              expect(notifications, 0);
            },
            () => MockClient((r) async {
              if (r.url.path.endsWith('/oauth/token')) {
                return json({'access_token': 'fixture', 'expires_in': 3600});
              }
              if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
                return json({
                  'user': {
                    'public_id': 'me',
                    'username': 'fixture',
                    'name': 'Original name',
                    'bio': 'Original bio',
                  },
                });
              }
              writes++;
              return json({'user': invalid.value});
            }),
          );
        },
      );
    }
    test(
      '${avatar ? 'avatar' : 'profile'} existing partial-response behavior control',
      () async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        await http.runWithClient(
          () async {
            final s = Session();
            await s.login('fixture', 'not-a-password');
            if (avatar) {
              await s.uploadAvatar(
                UploadFile(
                  Uint8List.fromList([1, 2, 3]),
                  'image/jpeg',
                  'fixture.jpg',
                ),
              );
            } else {
              await s.updateProfile({'name': 'Updated name'});
            }
            expect(s.user?['public_id'], 'me');
            expect(s.user?['name'], 'Updated name');
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/oauth/token')) {
              return json({'access_token': 'fixture', 'expires_in': 3600});
            }
            if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
              return json({
                'user': {
                  'public_id': 'me',
                  'username': 'fixture',
                  'name': 'Original name',
                  'bio': 'Original bio',
                },
              });
            }
            return json({
              'user': {'name': 'Updated name'},
            });
          }),
        );
      },
    );
  }
}

void signOutRace() {
  test('profile response cannot repopulate identity after offline-listener sign-out', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    Future<void>? signedOut;
    var changed = false;
    await http.runWithClient(
      () async {
        final s = Session(unregisterPush: (_) async {});
        await s.login('fixture', 'not-a-password');
        s.setOffline(true);
        s.addListener(() {
          if (!changed && !s.offline) {
            changed = true;
            signedOut = s.logout();
          }
        });
        try {
          await s.updateProfile({'name': 'Updated name'});
        } catch (_) {}
        expect(changed, isTrue);
        await signedOut;
        expect(s.user, isNull);
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/oauth/token')) {
          return json({'access_token': 'fixture', 'expires_in': 3600});
        }
        if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
          return json({
            'user': {
              'public_id': 'me',
              'username': 'fixture',
              'name': 'Original name',
              'bio': 'Original bio',
            },
          });
        }
        return json({
          'user': {
            'public_id': 'me',
            'username': 'fixture',
            'name': 'Updated name',
            'bio': 'Original bio',
          },
        });
      }),
    );
  });
}

Future<void> mutate(Session session, bool avatar) => avatar
    ? session.uploadAvatar(UploadFile([1, 2, 3], 'image/jpeg', 'fixture.jpg'))
    : session.updateProfile({'name': 'Updated name'});

void envelopeCases() {
  for (final avatar in [false, true]) {
    final invalid = <String, http.Response>{
      'broken JSON': http.Response('{', 200),
      'empty body': http.Response('', 200),
      'null envelope': json(null),
      'list envelope': json([]),
      'scalar envelope': json('untrusted fixture'),
      'missing user': json({}),
      'null user': json({'user': null}),
      'list user': json({'user': []}),
      'scalar user': json({'user': 7}),
      'empty user': json({'user': {}}),
    };
    for (final entry in invalid.entries) {
      test(
        '${avatar ? 'avatar' : 'profile'} normalizes ${entry.key} without a session commit',
        () async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          var writes = 0;
          await http.runWithClient(
            () async {
              final s = Session();
              await s.login('fixture', 'not-a-password');
              final before = Map<String, dynamic>.from(s.user!);
              var notifications = 0;
              s.addListener(() => notifications++);
              Object? failure;
              try {
                await mutate(s, avatar);
              } catch (e) {
                failure = e;
              }
              expect(failure, isA<ApiError>());
              expect(
                (failure as ApiError).message,
                'Could not confirm the result. Check before trying again.',
              );
              expect(s.user, before);
              expect(writes, 1);
              expect(notifications, 0);
            },
            () => MockClient((r) async {
              if (r.url.path.endsWith('/oauth/token')) {
                return json({'access_token': 'fixture', 'expires_in': 3600});
              }
              if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
                return json({
                  'user': {
                    'public_id': 'me',
                    'username': 'fixture',
                    'name': 'Original name',
                    'bio': 'Original bio',
                  },
                });
              }
              writes++;
              return entry.value;
            }),
          );
        },
      );
    }
    test(
      '${avatar ? 'avatar' : 'profile'} commits supported nullable fields once and ignores unrelated metadata',
      () async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        await http.runWithClient(
          () async {
            final s = Session();
            await s.login('fixture', 'not-a-password');
            var notifications = 0;
            s.addListener(() => notifications++);
            await mutate(s, avatar);
            expect(s.user, {
              'public_id': 'me',
              'username': 'fixture',
              'name': 'Updated name',
              'bio': null,
              'avatar_url': null,
              'retained_fixture': 'original',
            });
            expect(s.pollsEnabled, isTrue);
            expect(notifications, 1);
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/oauth/token')) {
              return json({'access_token': 'fixture', 'expires_in': 3600});
            }
            if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
              return json({
                'features': {'polls': true},
                'user': {
                  'public_id': 'me',
                  'username': 'fixture',
                  'name': 'Original name',
                  'bio': 'Original bio',
                  'retained_fixture': 'original',
                },
              });
            }
            return json({
              'user': {
                'public_id': 'me',
                'username': 'fixture',
                'name': 'Updated name',
                'bio': null,
                'avatar_url': null,
                'retained_fixture': 'must not replace',
                'features': {'polls': false},
              },
            });
          }),
        );
      },
    );
  }
}

void startCases() {
  for (final avatar in [false, true]) {
    for (final state in [
      'signed out',
      'missing owner',
      'empty owner',
      'numeric owner',
      'unloaded replacement view',
      'replacement authenticating',
    ]) {
      test(
        '${avatar ? 'avatar' : 'profile'} refuses request start while $state',
        () async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          var writes = 0, malformedView = false, holdGrant = false;
          final grant = Completer<http.Response>();
          Future<void>? replacement;
          await http.runWithClient(
            () async {
              final s = Session();
              if (state != 'signed out') {
                await s.login('fixture', 'not-a-password');
              }
              if (state == 'missing owner') s.user!.remove('public_id');
              if (state == 'empty owner') s.user!['public_id'] = '';
              if (state == 'numeric owner') s.user!['public_id'] = 7;
              if (state == 'unloaded replacement view') {
                malformedView = true;
                try {
                  await s.login('replacement', 'not-a-password');
                } catch (_) {}
                expect(s.accountViewNeedsRefresh, isTrue);
              }
              if (state == 'replacement authenticating') {
                holdGrant = true;
                replacement = s.login('replacement', 'not-a-password');
                expect(s.authenticating, isTrue);
              }
              try {
                await expectLater(
                  mutate(s, avatar),
                  throwsA(
                    isA<ApiError>().having((e) => e.status, 'status', 401),
                  ),
                );
                expect(writes, 0);
              } finally {
                if (replacement != null) {
                  grant.complete(
                    json({'access_token': 'replacement', 'expires_in': 3600}),
                  );
                  await replacement;
                }
              }
            },
            () => MockClient((r) async {
              if (r.url.path.endsWith('/oauth/token')) {
                return holdGrant
                    ? grant.future
                    : json({'access_token': 'fixture', 'expires_in': 3600});
              }
              if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
                return json({
                  'user': malformedView
                      ? {}
                      : {
                          'public_id': 'me',
                          'username': 'fixture',
                          'name': 'Original name',
                        },
                });
              }
              writes++;
              return json({
                'user': {'public_id': 'me', 'name': 'Updated name'},
              });
            }),
          );
        },
      );
    }
  }
}

void statusCases() {
  for (final avatar in [false, true]) {
    for (final status in [422, 503]) {
      test(
        '${avatar ? 'avatar' : 'profile'} preserves HTTP $status rejection without merging its user object',
        () async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          var writes = 0;
          await http.runWithClient(
            () async {
              final s = Session();
              await s.login('fixture', 'not-a-password');
              final before = Map<String, dynamic>.from(s.user!);
              await expectLater(
                mutate(s, avatar),
                throwsA(
                  isA<ApiError>().having((e) => e.status, 'status', status),
                ),
              );
              expect(s.user, before);
              expect(writes, 1);
            },
            () => MockClient((r) async {
              if (r.url.path.endsWith('/oauth/token')) {
                return json({'access_token': 'fixture', 'expires_in': 3600});
              }
              if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
                return json({
                  'user': {
                    'public_id': 'me',
                    'username': 'fixture',
                    'name': 'Original name',
                  },
                });
              }
              writes++;
              return http.Response(
                jsonEncode({
                  'user': {'public_id': 'other', 'name': 'Must not apply'},
                }),
                status,
              );
            }),
          );
        },
      );
    }
  }
}
