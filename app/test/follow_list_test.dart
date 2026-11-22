// Synthetic members/API only. No live relationship read or mutation.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/follow_list_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'upload_center_test.dart' as h;
import 'profile_journey_test.dart' as p;

Map<String, dynamic> member(String name) => {
  'public_id': 'id-$name',
  'username': name,
  'name': 'Member $name',
  'avatar_url': null,
};
Map<String, dynamic> page(
  List<String> names, {
  String? next,
  String owner = 'fixture',
  String direction = 'followers',
}) => {
  'owner': {
    ...member(owner),
    'public_id': owner == 'fixture'
        ? 'me'
        : owner == 'asha'
        ? 'asha'
        : 'id-$owner',
  },
  'direction': direction,
  'data': names.map(member).toList(),
  'next_cursor': next,
};
void main() {
  setUpAll(() async {
    Directory('test/renders').createSync(recursive: true);
    for (final f in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      final file = File(f.$2);
      final loader = FontLoader(f.$1)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
  test('server capability is opt-in and clears on logout', () async {
    SharedPreferences.setMockInitialValues({});
    var enabled = true;
    await http.runWithClient(
      () async {
        final session = Session();
        expect(session.followListsEnabled, isFalse);
        await session.login('fixture', 'fixture');
        expect(session.followListsEnabled, isTrue);
        await session.logout();
        expect(session.followListsEnabled, isFalse);
        enabled = false;
        await session.login('fixture', 'fixture');
        expect(session.followListsEnabled, isFalse);
        session.dispose();
      },
      () => MockClient(
        (r) async => r.url.path.endsWith('/oauth/token')
            ? h.json({'access_token': 'fixture', 'expires_in': 3600})
            : h.json({
                'user': {'public_id': 'me', 'username': 'fixture'},
                'features': enabled
                    ? {'follow_lists': true}
                    : <String, dynamic>{},
              }),
      ),
    );
  });
  testWidgets('disabled capability makes no relationship request', (t) async {
    var reads = 0;
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(
          MaterialApp(
            home: FollowListPage(
              session: s,
              username: 'fixture',
              kind: FollowListKind.followers,
            ),
          ),
        );
        await h.flush(t);
        expect(find.text('This member list is unavailable.'), findsOneWidget);
        expect(reads, 0);
      },
      respond: (_) async {
        reads++;
        return h.json(page([]));
      },
    );
  });
  testWidgets('initial failure retries and empty list remains refreshable', (
    t,
  ) async {
    var reads = 0;
    await h.fixture(t, (s, c) async {
      s.followListsEnabled = true;
      await t.pumpWidget(
        MaterialApp(
          home: FollowListPage(
            session: s,
            username: 'fixture',
            kind: FollowListKind.followers,
          ),
        ),
      );
      await h.flush(t);
      expect(find.text('Member list could not be loaded.'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await h.flush(t);
      expect(find.text('No followers to show'), findsOneWidget);
      await t.tap(find.byTooltip('Refresh'));
      await h.flush(t);
      expect(reads, 3);
    }, respond: (_) async => ++reads == 1 ? h.json({}, 503) : h.json(page([])));
  });
  testWidgets(
    'pagination failure retries same cursor without losing existing rows',
    (t) async {
      final cursors = <String?>[];
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: FollowListPage(
                session: s,
                username: 'fixture',
                kind: FollowListKind.followers,
              ),
            ),
          );
          await h.flush(t);
          await t.tap(find.text('Load more'));
          await h.flush(t);
          expect(find.text('@first'), findsOneWidget);
          await t.tap(find.text('Try again'));
          await h.flush(t);
          expect(find.text('@first'), findsOneWidget);
          expect(find.text('@second'), findsOneWidget);
          expect(find.text('Load more'), findsNothing);
          expect(cursors, [null, 'opaque-one', 'opaque-one']);
        },
        respond: (r) async {
          expect(r.method, 'GET');
          cursors.add(r.url.queryParameters['cursor']);
          return cursors.length == 1
              ? h.json(page(['first'], next: 'opaque-one'))
              : cursors.length == 2
              ? h.json({}, 503)
              : h.json(page(['first', 'second']));
        },
      );
    },
  );
  testWidgets(
    'long page uses lazy rows and pagination failure remains recoverable at list end',
    (t) async {
      var reads = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('review'),
              child: MaterialApp(
                home: FollowListPage(
                  session: s,
                  username: 'fixture',
                  kind: FollowListKind.followers,
                ),
              ),
            ),
          );
          await h.flush(t);
          expect(find.byType(ListTile).evaluate().length, lessThan(30));
          await t.scrollUntilVisible(find.text('Load more'), 400);
          await t.tap(find.text('Load more'));
          await h.flush(t);
          expect(find.text('Try again').hitTestable(), findsOneWidget);
          await p.shot(t, 'follow_list_more_error');
          await t.tap(find.text('Try again'));
          await h.flush(t);
          expect(reads, 3);
        },
        respond: (_) async => ++reads == 1
            ? h.json(
                page(List.generate(30, (i) => 'member$i'), next: 'opaque-one'),
              )
            : reads == 2
            ? h.json({}, 503)
            : h.json(page(['lastmember'])),
      );
    },
  );
  testWidgets(
    'returning from a member refreshes removed rows and duplicate opening is locked',
    (t) async {
      var reads = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: FollowListPage(
                session: s,
                username: 'fixture',
                kind: FollowListKind.followers,
              ),
            ),
          );
          await h.flush(t);
          final open = t
              .widget<ListTile>(find.widgetWithText(ListTile, '@first'))
              .onTap!;
          open();
          open();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(UserProfilePage), findsOneWidget);
          await t.pageBack();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(reads, 2);
          expect(find.text('No followers to show'), findsOneWidget);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/followers')) {
            return h.json(page(++reads == 1 ? ['first'] : []));
          }
          if (r.url.path.endsWith('/users/first')) {
            return h.json({
              'user': {
                ...p.person(),
                'username': 'first',
                'public_id': 'id-first',
              },
            });
          }
          return h.json({'data': [], 'next_cursor': null});
        },
      );
    },
  );
  for (final malformed in [
    'owner',
    'ownerId',
    'direction',
    'row',
    'root',
    'cursor',
    'oversize',
  ]) {
    testWidgets('malformed $malformed list never publishes a partial roster', (
      t,
    ) async {
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: FollowListPage(
                session: s,
                username: 'fixture',
                kind: FollowListKind.followers,
                ownerId: 'me',
              ),
            ),
          );
          await h.flush(t);
          expect(find.text('Member list could not be loaded.'), findsOneWidget);
          expect(find.text('@first'), findsNothing);
          expect(t.takeException(), isNull);
        },
        respond: (_) async {
          final value = page(['first']);
          switch (malformed) {
            case 'owner':
              value['owner'] = member('wrong');
            case 'ownerId':
              value['owner'] = {
                ...member('fixture'),
                'public_id': 'wrong-owner',
              };
            case 'direction':
              value['direction'] = 'following';
            case 'row':
              value['data'] = [
                member('first'),
                {'username': 5},
              ];
            case 'cursor':
              value['next_cursor'] = 8;
            case 'oversize':
              value['data'] = List.generate(31, (i) => member('member$i'));
          }
          return h.json(malformed == 'root' ? [] : value);
        },
      );
    });
  }
  testWidgets(
    'same-member replacement clears list and retained callbacks cannot borrow login',
    (t) async {
      var reads = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: FollowListPage(
                session: s,
                username: 'fixture',
                kind: FollowListKind.followers,
              ),
            ),
          );
          await h.flush(t);
          final more = t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Load more'),
              )
              .onPressed!;
          final refresh = t
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh;
          final open = t
              .widget<ListTile>(find.widgetWithText(ListTile, '@first'))
              .onTap!;
          await s.login('same', 'fixture');
          s.followListsEnabled = true;
          await h.flush(t);
          more();
          open();
          await refresh();
          await h.flush(t);
          expect(find.byType(UserProfilePage), findsNothing);
          expect(find.text('@first'), findsNothing);
          expect(find.text('Load more'), findsNothing);
          expect(reads, 1);
          expect(
            find.text(
              'This screen is from an earlier sign-in. Go back to continue.',
            ),
            findsOneWidget,
          );
        },
        respond: (_) async {
          reads++;
          return h.json(page(['first'], next: 'opaque-one'));
        },
      );
    },
  );
  testWidgets('late list response cannot publish into replacement login', (
    t,
  ) async {
    final reply = Completer<http.Response>();
    await h.fixture(t, (s, c) async {
      s.followListsEnabled = true;
      await t.pumpWidget(
        MaterialApp(
          home: FollowListPage(
            session: s,
            username: 'fixture',
            kind: FollowListKind.followers,
          ),
        ),
      );
      await h.flush(t);
      await s.login('same', 'fixture');
      s.followListsEnabled = true;
      await h.flush(t);
      reply.complete(h.json(page(['private'])));
      await h.flush(t);
      expect(find.text('@private'), findsNothing);
    }, respond: (_) async => reply.future);
  });
  testWidgets(
    'changed target on retained widget permanently retires previous list',
    (t) async {
      var reads = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: FollowListPage(
                key: const ValueKey('retained'),
                session: s,
                username: 'fixture',
                kind: FollowListKind.followers,
              ),
            ),
          );
          await h.flush(t);
          await t.pumpWidget(
            MaterialApp(
              home: FollowListPage(
                key: const ValueKey('retained'),
                session: s,
                username: 'other',
                kind: FollowListKind.followers,
              ),
            ),
          );
          await h.flush(t);
          expect(find.text('@first'), findsNothing);
          expect(reads, 1);
        },
        respond: (_) async {
          reads++;
          return h.json(page(['first']));
        },
      );
    },
  );
  testWidgets(
    'profile counts open read-only list only when server capability exists',
    (t) async {
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: UserProfilePage(session: s, username: 'asha'),
            ),
          );
          await h.flush(t);
          await t.tap(find.text('Followers'));
          await h.flush(t);
          expect(find.byType(FollowListPage), findsOneWidget);
          expect(find.text('@first'), findsOneWidget);
        },
        respond: (r) async {
          expect(r.method, 'GET');
          if (r.url.path.endsWith('/followers')) {
            return h.json(page(['first'], owner: 'asha'));
          }
          if (r.url.path.endsWith('/users/asha')) {
            return h.json({'user': p.person()});
          }
          return h.json({'data': [], 'next_cursor': null});
        },
      );
    },
  );

  testWidgets(
    'own profile opens following and old callback cannot borrow replacement login',
    (t) async {
      var lists = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.followListsEnabled = true;
          await t.pumpWidget(MaterialApp(home: MePage(session: s)));
          await h.flush(t);
          final oldOpen = t
              .widget<ProfileHeader>(find.byType(ProfileHeader))
              .onFollowing!;
          await s.login('same', 'fixture');
          s.followListsEnabled = true;
          await h.flush(t);
          oldOpen();
          await h.flush(t);
          expect(find.byType(FollowListPage), findsNothing);
          expect(lists, 0);
          await t.pumpWidget(
            MaterialApp(
              home: MePage(key: const ValueKey('new-login-root'), session: s),
            ),
          );
          await h.flush(t);
          await t.tap(find.text('Following'));
          await h.flush(t);
          expect(lists, 1);
          expect(find.byType(FollowListPage), findsOneWidget);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/following')) {
            lists++;
            return h.json(page([], direction: 'following'));
          }
          if (r.url.path.endsWith('/users/fixture')) {
            return h.json({
              'user': {
                ...member('fixture'),
                'public_id': 'me',
                'followers_count': 2,
                'following_count': 3,
                'posts_count': 0,
              },
            });
          }
          return h.json({'data': [], 'next_cursor': null});
        },
      );
    },
  );
  testWidgets('disabled profile keeps counts inert', (t) async {
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(
          MaterialApp(
            home: UserProfilePage(session: s, username: 'asha'),
          ),
        );
        await h.flush(t);
        final header = t.widget<ProfileHeader>(find.byType(ProfileHeader));
        expect(header.onFollowers, isNull);
        expect(header.onFollowing, isNull);
      },
      respond: (r) async => r.url.path.endsWith('/users/asha')
          ? h.json({'user': p.person()})
          : h.json({'data': [], 'next_cursor': null}),
    );
  });

  for (final lang in ['en', 'ne']) {
    testWidgets(
      'enabled profile and routed list keep alignment and Back at large text $lang',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await p.fixture(
          t,
          (s) {
            s.followListsEnabled = true;
            return UserProfilePage(session: s, username: 'asha');
          },
          () async {
            await h.flush(t);
            await t.pumpAndSettle();
            await p.shot(t, 'follow_profile_enabled_$lang');
            await t.tap(find.text(t_('Followers')));
            await h.flush(t);
            expect(find.byType(BackButton), findsWidgets);
            expect(t.takeException(), isNull);
            await h.flush(t);
            await t.pumpAndSettle();
            await p.shot(t, 'follow_list_routed_$lang');
          },
          respond: (r) async {
            expect(r.method, 'GET');
            if (r.url.path.endsWith('/followers')) {
              return h.json(page(['first'], owner: 'asha'));
            }
            if (r.url.path.endsWith('/users/asha')) {
              return h.json({'user': p.person()});
            }
            return h.json({'data': [], 'next_cursor': null});
          },
          brightness: lang == 'en' ? Brightness.light : Brightness.dark,
          scale: 1.8,
          language: lang,
        );
      },
    );
  }
  for (final lang in ['en', 'ne']) {
    for (final state in ['loaded', 'error', 'empty']) {
      testWidgets('follow list $state fits narrow large text $lang', (t) async {
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await h.fixture(
          t,
          (s, c) async {
            s.followListsEnabled = true;
            await t.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('review'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildTheme(
                    lang == 'en' ? Brightness.light : Brightness.dark,
                    fontFamily: 'Roboto',
                    fontFamilyFallback: ['NotoDev'],
                  ),
                  builder: (context, w) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.8)),
                    child: w!,
                  ),
                  home: FollowListPage(
                    session: s,
                    username: 'fixture',
                    kind: FollowListKind.followers,
                  ),
                ),
              ),
            );
            await h.flush(t);
            expect(t.takeException(), isNull);
            await p.shot(t, 'follow_list_${state}_$lang');
            if (state == 'error') {
              expect(find.text(t_('Try again')), findsOneWidget);
            }
          },
          respond: (_) async => state == 'error'
              ? h.json({}, 503)
              : h.json(
                  page(
                    state == 'empty' ? [] : ['first', 'second'],
                    next: state == 'loaded' ? 'opaque-one' : null,
                  ),
                ),
        );
      });
    }
  }
}
