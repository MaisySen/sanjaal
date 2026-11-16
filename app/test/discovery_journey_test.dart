// Search response ordering and retry fixtures. No live service or real members.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/search_page.dart';
import 'package:sanjaal/post_page.dart';
import 'package:sanjaal/notifications_page.dart';
import 'package:sanjaal/share_post.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Object body, [int code = 200]) => http.Response(jsonEncode(body), code);
http.Response results(String name) => reply({'users': [{'public_id': name, 'username': name, 'name': name}], 'hashtags': []});
Future<void> flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
  await t.pump();
}
Future<void> fixture(WidgetTester t, Future<void> Function() run, Future<http.Response> Function(http.Request) api, {Widget Function(Session)? home}) async {
  SharedPreferences.setMockInitialValues({});
  await http.runWithClient(() async {
    final s = Session();
    await s.login('fixture', 'not-a-password');
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: home?.call(s) ?? SearchPage(session: s)));
    await t.pump();
    await run();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }, () => MockClient((r) async {
    if (r.url.path.endsWith('/oauth/token')) return reply({'access_token': 'fixture', 'expires_in': 3600});
    if (r.url.path.endsWith('/auth/me')) return reply({'user': {'username': 'fixture', 'public_id': 'me'}});
    return api(r);
  }));
}

void main() {
  testWidgets('clearing search ignores a late response and stops the spinner', (t) async {
    final pending = Completer<http.Response>();
    await fixture(t, () async {
      await t.enterText(find.byType(TextField), 'old');
      await t.pump(const Duration(milliseconds: 400));
      await flush(t);
      await t.enterText(find.byType(TextField), '');
      pending.complete(results('old-result'));
      await flush(t);
      expect(find.text('old-result'), findsNothing);
      expect(find.text('Find people to follow'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }, (_) => pending.future);
  });
  testWidgets('editing search invalidates the previous query before debounce', (t) async {
    final pending = Completer<http.Response>();
    await fixture(t, () async {
      await t.enterText(find.byType(TextField), 'old');
      await t.pump(const Duration(milliseconds: 400));
      await flush(t);
      await t.enterText(find.byType(TextField), 'new');
      pending.complete(results('old-result'));
      await flush(t);
      expect(find.text('old-result'), findsNothing);
      await t.pump(const Duration(milliseconds: 400));
      await flush(t);
      expect(find.text('new-result'), findsOneWidget);
      expect(find.text('old-result'), findsNothing);
    }, (r) => r.url.queryParameters['q'] == 'old' ? pending.future : Future.value(results('new-result')));
  });
  testWidgets('failed search retries the same query without retyping', (t) async {
    var reads = 0;
    await fixture(t, () async {
      await t.enterText(find.byType(TextField), 'asha');
      await t.pump(const Duration(milliseconds: 400));
      await flush(t);
      expect(find.text('Fixture unavailable'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await flush(t);
      expect(find.text('asha-result'), findsOneWidget);
      expect(reads, 2);
    }, (r) async => ++reads == 1 ? reply({'message': 'Fixture unavailable'}, 503) : results('asha-result'));
  });
  testWidgets('a post notification opens the current post, not the actor profile', (t) async {
    final reads = <String>[];
    await fixture(t, () async {
      await flush(t);
      await t.tap(find.text('@asha liked your post'));
      await t.pumpAndSettle();
      await flush(t);
      expect(find.byType(PostPage), findsOneWidget);
      expect(find.text('The complete original post'), findsOneWidget);
      expect(reads, ['/api/v1/notifications', '/api/v1/posts/original']);
    }, (r) async {
      reads.add(r.url.path);
      return r.url.path.endsWith('/notifications')
        ? reply({'data': [{'type': 'like', 'actor': 'asha', 'post_id': 'original', 'created_at': '2026-11-17T00:00:00Z'}]})
        : reply({'post': {'public_id': 'original', 'body': 'The complete original post', 'media': [], 'author': {'public_id': 'me', 'username': 'fixture'}}});
    }, home: (s) => NotificationsPage(session: s));
  });
  testWidgets('removed post has a clear unavailable state without a retry loop', (t) async {
    await fixture(t, () async {
      await flush(t);
      expect(find.text('Post unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(t.takeException(), isNull);
    }, (_) async => reply({'message': 'Not found'}, 404), home: (s) => PostPage(session: s, postId: 'removed'));
  });
  testWidgets('a post network error can retry the same destination', (t) async {
    var reads = 0;
    await fixture(t, () async {
      await flush(t);
      expect(find.text('Fixture unavailable'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await flush(t);
      expect(find.text('Recovered post'), findsOneWidget);
      expect(reads, 2);
    }, (_) async => ++reads == 1 ? reply({'message': 'Fixture unavailable'}, 503)
      : reply({'post': {'public_id': 'original', 'body': 'Recovered post', 'media': [], 'author': {'public_id': 'me', 'username': 'fixture'}}}), home: (s) => PostPage(session: s, postId: 'original'));
  });
  testWidgets('shared post tap selects its post id rather than the author', (t) async {
    String? opened;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SharedPostCard(post: const {'public_id': 'post-123', 'author': {'username': 'asha'}, 'excerpt': 'Shared original'}, onOpenPost: (id) => opened = id, onOpenAuthor: (_) => fail('wrong destination')))));
    await t.tap(find.text('Shared original'));
    expect(opened, 'post-123');
  });

}
