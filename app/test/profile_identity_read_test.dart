// Synthetic profile payload identities only. No live profile/relationship action.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/profile_pages.dart';

import 'upload_center_test.dart' as h;
import 'profile_journey_test.dart' as p;
import 'other_profile_list_entry_test.dart' as e;

import 'package:sanjaal/ui.dart' show t_;

Map<String, dynamic> person(
  String id,
  String username,
  int count, [
  String name = 'Verified member',
]) => {
  'public_id': id,
  'username': username,
  'name': name,
  'posts_count': count,
  'followers_count': count,
  'following_count': count,
  'following': false,
  'blocked': false,
};
void main() {
  additionalCases();
  for (final own in [true, false]) {
    for (final first in [true, false]) {
      testWidgets(
        '${own ? 'own' : 'other'} profile rejects ${first ? 'initial wrong identity' : 'refresh identity replacement'}',
        (t) async {
          var reads = 0, writes = 0;
          await h.fixture(
            t,
            (s, c) async {
              await t.pumpWidget(
                MaterialApp(
                  home: own
                      ? MePage(session: s)
                      : UserProfilePage(session: s, username: 'asha'),
                ),
              );
              await h.flush(t);
              VoidCallback? oldFollow;
              if (!own && !first) {
                oldFollow = t
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Follow'),
                    )
                    .onPressed;
              }
              if (!first) {
                await t.tap(find.byTooltip('Refresh profile'));
                await h.flush(t);
              }
              final wrong = find.text('777').evaluate().length;
              final replaced = find.text('Changed person').evaluate().length;
              final preserved = find.text('8').evaluate().length;
              if (oldFollow != null) {
                oldFollow();
                await h.flush(t);
              }
              final invalidWrites = writes;
              if (find.text('Try again').evaluate().isNotEmpty) {
                await t.tap(find.text('Try again'));
                await h.flush(t);
              }
              final recovered = find.text('9').evaluate().length;
              await t.pumpWidget(const SizedBox());
              await h.flush(t);
              expect(wrong, 0);
              expect(replaced, 0);
              if (!first) expect(preserved, 3);
              expect(invalidWrites, 0);
              expect(recovered, 3);
              expect(t.takeException(), isNull);
            },
            respond: (r) async {
              if (r.method != 'GET') {
                writes++;
                return h.json({'following': true});
              }
              if (!r.url.path.contains('/users/')) {
                return h.json({'data': [], 'next_cursor': null});
              }
              reads++;
              final bad = reads == (first ? 1 : 2);
              return h.json({
                'user': bad
                    ? person(
                        'different-person',
                        own
                            ? 'unrelated'
                            : first
                            ? 'unrelated'
                            : 'asha',
                        777,
                        'Changed person',
                      )
                    : person(
                        own ? 'me' : 'asha',
                        own ? 'fixture' : 'asha',
                        reads == 1 ? 8 : 9,
                      ),
              });
            },
          );
        },
      );
    }
  }
}

void additionalCases() {
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(
            Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final field in ['public_id', 'username']) {
    for (final empty in [false, true]) {
      testWidgets(
        'own read rejects ${empty ? 'blank' : 'missing'} $field and recovers',
        (t) async {
          var reads = 0;
          await p.fixture(
            t,
            (s) => MePage(session: s),
            () async {
              expect(find.text('777'), findsNothing);
              expect(find.text('-'), findsNWidgets(3));
              await t.tap(find.text('Try again'));
              await p.flush(t);
              expect(find.text('9'), findsNWidgets(3));
              expect(t.takeException(), isNull);
            },
            respond: (r) async {
              if (!r.url.path.contains('/users/')) {
                return p.json({'data': [], 'next_cursor': null});
              }
              final value = person('me', 'fixture', ++reads == 1 ? 777 : 9);
              if (reads == 1) {
                if (empty) {
                  value[field] = ' ';
                } else {
                  value.remove(field);
                }
              }
              return p.json({'user': value});
            },
          );
        },
      );
    }
  }
  for (final action in [
    'Message',
    'report',
    'block',
    'unblock',
    'followers',
    'following',
  ]) {
    testWidgets(
      'retained $action cannot act after a profile identity failure',
      (t) async {
        var reads = 0, writes = 0, memberReads = 0;
        await h.fixture(
          t,
          (s, c) async {
            s.followListsEnabled = true;
            final routes = e.Routes();
            await t.pumpWidget(
              MaterialApp(
                navigatorObservers: [routes],
                home: UserProfilePage(session: s, username: 'asha'),
              ),
            );
            await h.flush(t);
            late VoidCallback old;
            if (action == 'Message') {
              old = t
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Message'),
                  )
                  .onPressed!;
            } else if (action == 'followers' || action == 'following') {
              final header = t.widget<ProfileHeader>(
                find.byType(ProfileHeader),
              );
              old = (action == 'followers'
                  ? header.onFollowers
                  : header.onFollowing)!;
            } else {
              final selected = t
                  .widget<PopupMenuButton<String>>(
                    find.byType(PopupMenuButton<String>),
                  )
                  .onSelected!;
              old = () => selected(action);
            }
            await t.tap(find.byTooltip('Refresh profile'));
            await h.flush(t);
            expect(find.text('Profile could not be loaded.'), findsOneWidget);
            old();
            await h.flush(t);
            expect(writes, 0);
            expect(memberReads, 0);
            expect(routes.pushes, 1);
            expect(find.byType(AlertDialog), findsNothing);
            expect(find.byType(SimpleDialog), findsNothing);
            expect(
              t
                  .widget<PopupMenuButton<String>>(
                    find.byType(PopupMenuButton<String>),
                  )
                  .enabled,
              isFalse,
            );
            final header = t.widget<ProfileHeader>(find.byType(ProfileHeader));
            expect(header.onFollowers, isNull);
            expect(header.onFollowing, isNull);
            await t.tap(find.text('Try again'));
            await h.flush(t);
            expect(
              t
                  .widget<PopupMenuButton<String>>(
                    find.byType(PopupMenuButton<String>),
                  )
                  .enabled,
              isTrue,
            );
            expect(
              t.widget<ProfileHeader>(find.byType(ProfileHeader)).onFollowers,
              action == 'unblock' ? isNull : isNotNull,
            );
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method != 'GET') {
              writes++;
              return h.json({'following': true});
            }
            if (r.url.path.endsWith('/users/asha')) {
              return h.json({
                'user': {
                  ...person(
                    ++reads == 2 ? 'changed-person' : 'asha',
                    'asha',
                    8,
                  ),
                  'blocked': action == 'unblock',
                },
              });
            }
            if (r.url.path.endsWith('/followers') ||
                r.url.path.endsWith('/following')) {
              memberReads++;
            }
            return h.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
  for (final own in [true, false]) {
    for (final lang in ['en', 'ne']) {
      testWidgets(
        'identity failure fits narrow large text ${own ? 'own' : 'other'} $lang',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          var reads = 0;
          await p.fixture(
            t,
            (s) => own
                ? MePage(session: s)
                : UserProfilePage(session: s, username: 'asha'),
            () async {
              if (!own) {
                await t.tap(find.byTooltip(t_('Refresh profile')));
                await p.flush(t);
              }
              expect(find.text('777'), findsNothing);
              expect(
                find.text(t_('Profile could not be loaded.')),
                findsOneWidget,
              );
              expect(find.text(own ? '-' : '8'), findsNWidgets(3));
              expect(t.takeException(), isNull);
              await p.shot(
                t,
                'profile_identity_${own ? 'own' : 'other'}_$lang',
              );
              await t.tap(find.text(t_('Try again')));
              await p.flush(t);
              expect(find.text('9'), findsNWidgets(3));
              expect(t.takeException(), isNull);
            },
            language: lang,
            brightness: lang == 'ne' ? Brightness.dark : Brightness.light,
            scale: 1.8,
            respond: (r) async {
              if (!r.url.path.contains('/users/')) {
                return p.json({'data': [], 'next_cursor': null});
              }
              final bad = ++reads == (own ? 1 : 2);
              return p.json({
                'user': person(
                  bad
                      ? 'changed-person'
                      : own
                      ? 'me'
                      : 'asha',
                  own ? 'fixture' : 'asha',
                  bad
                      ? 777
                      : reads == 1
                      ? 8
                      : 9,
                ),
              });
            },
          );
        },
      );
    }
  }
}
