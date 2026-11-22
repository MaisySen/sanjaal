// Synthetic post-card mutations only. Never live deletions.
import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/post_page.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/reactions.dart';

http.Response reply(Object value) => http.Response(jsonEncode(value), 200);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final change in ['same member', 'other member', 'logout']) {
    testWidgets('post delete confirmation cannot send after $change', (
      t,
    ) async {
      var deletes = 0;
      String owner = 'owner';
      await http.runWithClient(
        () async {
          final s = Session(unregisterPush: (_) async {});
          await s.login('fixture', 'not-a-password');
          await t.pumpWidget(
            MaterialApp(
              home: PostPage(session: s, postId: 'fixture'),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.byType(PopupMenuButton<String>));
          await t.pumpAndSettle();
          await t.tap(find.text('Delete'));
          await t.pumpAndSettle();
          expect(find.text('Delete post?'), findsOneWidget);
          if (change == 'logout') {
            await s.logout();
          } else {
            if (change == 'other member') owner = 'other';
            await s.login('replacement', 'not-a-password');
          }
          await t.pumpAndSettle();
          if (find
              .widgetWithText(FilledButton, 'Delete')
              .evaluate()
              .isNotEmpty) {
            await t.tap(find.widgetWithText(FilledButton, 'Delete'));
            await t.pumpAndSettle();
          }
          expect(find.text('Delete post?'), findsNothing);
          expect(deletes, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/oauth/token')) {
            return reply({'access_token': 'fixture', 'expires_in': 3600});
          }
          if (r.url.path.endsWith('/auth/me')) {
            return reply({
              'user': {'public_id': owner, 'username': owner},
            });
          }
          if (r.method == 'DELETE') {
            deletes++;
            return reply({});
          }
          return reply({
            'post': {
              'public_id': 'fixture',
              'kind': 'post',
              'body': 'Local owned post',
              'media': [],
              'hashtags': [],
              'author': {
                'public_id': 'owner',
                'username': 'owner',
                'name': 'Owner',
              },
              'created_at': '2026-11-21T00:00:00Z',
              'likes_count': 0,
              'comments_count': 0,
            },
          });
        }),
      );
    });
  }
  for (final outcome in ['success', 'failure']) {
    for (final action in ['delete', 'save', 'reaction']) {
      testWidgets('post $action late $outcome cannot update a re-login', (
        t,
      ) async {
        var writes = 0, removed = 0;
        final response = Completer<http.Response>();
        final post = <String, dynamic>{
          'public_id': 'fixture',
          'kind': 'post',
          'body': 'Old card contents',
          'media': [],
          'hashtags': [],
          'author': {
            'public_id': 'owner',
            'username': 'owner',
            'name': 'Owner',
          },
          'created_at': '2026-11-21T00:00:00Z',
          'likes_count': 0,
          'comments_count': 0,
        };
        await http.runWithClient(
          () async {
            final s = Session();
            await s.login('fixture', 'not-a-password');
            await t.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: PostCard(
                    session: s,
                    post: post,
                    onRemoved: () => removed++,
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            if (action == 'reaction') {
              await t.tap(find.byType(ReactionButton));
            } else {
              await t.tap(find.byType(PopupMenuButton<String>));
              await t.pumpAndSettle();
              await t.tap(find.text(action == 'save' ? 'Save' : 'Delete'));
              if (action == 'delete') {
                await t.pumpAndSettle();
                await t.tap(find.widgetWithText(FilledButton, 'Delete'));
              }
            }
            await t.pump();
            expect(writes, 1);
            await s.login('replacement', 'not-a-password');
            await t.pump();
            expect(find.text('Old card contents'), findsNothing);
            response.complete(
              http.Response(
                jsonEncode(
                  outcome == 'failure'
                      ? {'message': 'Old result error'}
                      : {'my_reaction': 'love', 'likes_count': 1},
                ),
                outcome == 'failure' ? 422 : 200,
              ),
            );
            await t.pumpAndSettle();
            expect(removed, 0);
            expect(find.text('Old result error'), findsNothing);
            expect(find.text('Saved'), findsNothing);
            expect(writes, 1);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/oauth/token')) {
              return reply({'access_token': 'fixture', 'expires_in': 3600});
            }
            if (r.url.path.endsWith('/auth/me')) {
              return reply({
                'user': {'public_id': 'owner', 'username': 'owner'},
              });
            }
            writes++;
            return response.future;
          }),
        );
      });
    }
  }
  testWidgets('old reaction picker choice cannot mutate after re-login', (
    t,
  ) async {
    var writes = 0;
    await http.runWithClient(
      () async {
        final s = Session();
        await s.login('fixture', 'not-a-password');
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReactionButton(
                session: s,
                post: {'public_id': 'fixture', 'likes_count': 0},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.longPress(find.byType(ReactionButton));
        await t.pumpAndSettle();
        expect(find.text(reactionEmoji['like']!), findsOneWidget);
        await s.login('replacement', 'not-a-password');
        await t.pumpAndSettle();
        if (find.text(reactionEmoji['like']!).evaluate().isNotEmpty) {
          await t.tap(find.text(reactionEmoji['like']!));
        }
        await t.pumpAndSettle();
        expect(writes, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/oauth/token')) {
          return reply({'access_token': 'fixture', 'expires_in': 3600});
        }
        if (r.url.path.endsWith('/auth/me')) {
          return reply({
            'user': {'public_id': 'owner', 'username': 'owner'},
          });
        }
        writes++;
        return reply({});
      }),
    );
  });
  testWidgets(
    'unchanged-session delete still requires confirmation and completes once',
    (t) async {
      var deletes = 0;
      await http.runWithClient(
        () async {
          final s = Session();
          await s.login('fixture', 'not-a-password');
          await t.pumpWidget(
            MaterialApp(
              home: PostPage(session: s, postId: 'fixture'),
            ),
          );
          await t.pumpAndSettle();
          Future<void> open() async {
            await t.tap(find.byType(PopupMenuButton<String>));
            await t.pumpAndSettle();
            await t.tap(find.text('Delete'));
            await t.pumpAndSettle();
          }

          await open();
          await t.tap(find.text('Cancel'));
          await t.pumpAndSettle();
          expect(deletes, 0);
          await open();
          await t.tap(find.widgetWithText(FilledButton, 'Delete'));
          await t.pumpAndSettle();
          expect(deletes, 1);
          expect(find.text('Post unavailable'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/oauth/token')) {
            return reply({'access_token': 'fixture', 'expires_in': 3600});
          }
          if (r.url.path.endsWith('/auth/me')) {
            return reply({
              'user': {'public_id': 'owner', 'username': 'owner'},
            });
          }
          if (r.method == 'DELETE') {
            deletes++;
            return reply({});
          }
          return reply({
            'post': {
              'public_id': 'fixture',
              'kind': 'post',
              'body': 'Local owned post',
              'media': [],
              'hashtags': [],
              'author': {
                'public_id': 'owner',
                'username': 'owner',
                'name': 'Owner',
              },
              'created_at': '2026-11-21T00:00:00Z',
              'likes_count': 0,
              'comments_count': 0,
            },
          });
        }),
      );
    },
  );
}
