// Saved/hashtag feed ownership using actual routes and synthetic HTTP only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';

http.Response reply(Object value) => http.Response(jsonEncode(value), 200);
Map<String, dynamic> post() => {
  'public_id': 'old-post',
  'kind': 'post',
  'body': 'Old saved content',
  'media': [],
  'author': {'public_id': 'author', 'username': 'author'},
  'created_at': '2026-11-22T00:00:00Z',
  'comments_count': 0,
  'likes_count': 0,
};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final route in ['saved', 'hashtag']) {
    for (final pending in [false, true]) {
      for (final change in ['same', 'other', 'logout']) {
        testWidgets(
          '$route feed retires ${pending ? 'pending' : 'loaded'} after $change and cannot refresh with new login',
          (t) async {
            var reads = 0;
            String owner = 'me';
            final response = Completer<http.Response>();
            await http.runWithClient(
              () async {
                final s = Session(unregisterPush: (_) async {});
                await s.login('fixture', 'not-a-password');
                await t.pumpWidget(
                  MaterialApp(
                    home: route == 'saved'
                        ? SavedPage(session: s)
                        : HashtagPage(session: s, tag: 'fixture'),
                  ),
                );
                await t.pump();
                await t.pump(const Duration(milliseconds: 400));
                final feed = t.state<FeedListState>(find.byType(FeedList));
                expect(reads, 1);
                if (change == 'logout') {
                  await s.logout();
                } else {
                  if (change == 'other') owner = 'new';
                  await s.login('fixture', 'not-a-password');
                }
                await t.pump();
                if (pending) {
                  response.complete(
                    reply({
                      'data': [post()],
                      'next_cursor': null,
                    }),
                  );
                  await t.pump();
                }
                await feed.load(refresh: true);
                await t.pumpAndSettle();
                expect(
                  reads,
                  1,
                  reason: 'old feed may not issue reads for replacement login',
                );
                expect(feed.posts, isEmpty);
                expect(find.text('Old saved content'), findsNothing);
                expect(
                  find.text(
                    change == 'logout' ? 'Back to sign in' : 'Back to account',
                  ),
                  findsOneWidget,
                );
                feed.insertFirst(post());
                expect(feed.posts, isEmpty);
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
                reads++;
                return pending && reads == 1
                    ? response.future
                    : reply({
                        'data': [post()],
                        'next_cursor': null,
                      });
              }),
            );
          },
        );
      }
    }
  }
}
