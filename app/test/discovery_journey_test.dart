// Search response ordering and retry fixtures. No live service or real members.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
Future<void> review(WidgetTester t, String name) async {
  t.view.physicalSize = const Size(960, 1920); t.view.devicePixelRatio = 3; addTearDown(t.view.reset);
  final fontFile = File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  if (fontFile.existsSync()) {
    final font = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(fontFile.readAsBytesSync())));
    await t.runAsync(() => font.load());
  }
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary = t.firstState(find.byType(WidgetsApp)).context.findAncestorRenderObjectOfType<RenderRepaintBoundary>();
    // Root boundary wraps the complete route and any modal sheet.
    final image = await boundary!.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('test/renders').createSync(recursive: true);
    File('test/renders/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
Future<void> fixture(WidgetTester t, Future<void> Function() run, Future<http.Response> Function(http.Request) api, {Widget Function(Session)? home, double textScale = 1}) async {
  SharedPreferences.setMockInitialValues({});
  await http.runWithClient(() async {
    final s = Session();
    await s.login('fixture', 'not-a-password');
    await t.pumpWidget(RepaintBoundary(child: MaterialApp(debugShowCheckedModeBanner: false, builder: (c,w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)), child: w!), theme: buildTheme(Brightness.light, fontFamily: 'Roboto'), home: home?.call(s) ?? SearchPage(session: s))));
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
    }, home: (s) => NotificationsPage(session: s), textScale: 1.8);
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

  testWidgets('empty notifications can refresh and discover a new item', (t) async {
    var reads = 0;
    await fixture(t, () async {
      await flush(t); expect(find.text('Nothing yet'), findsOneWidget);
      final refresh = t.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      await refresh.onRefresh(); await flush(t);
      expect(find.text('@asha liked your post'), findsOneWidget);
      expect(reads, 2);
    }, (_) async => reply({'data': ++reads == 1 ? [] : [{'type': 'like', 'actor': 'asha', 'post_id': 'p'}]}), home: (s) => NotificationsPage(session: s), textScale: 1.8);
  });
  testWidgets('failed notification refresh keeps items, explains staleness and retries', (t) async {
    var reads = 0;
    await fixture(t, () async {
      await flush(t);
      await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh(); await flush(t);
      expect(find.text('@asha liked your post'), findsOneWidget);
      expect(find.text('Could not refresh.'), findsOneWidget);
      await review(t, 'notifications_refresh_recovery');
      await t.tap(find.text('Try again')); await flush(t);
      expect(find.text('@new liked your post'), findsOneWidget);
      expect(find.text('Could not refresh.'), findsNothing);
    }, (_) async {
      reads++;
      return reads == 2 ? reply({'message': 'Temporary failure'}, 503) : reply({'data': [{'type': 'like', 'actor': reads == 1 ? 'asha' : 'new', 'post_id': 'p'}]});
    }, home: (s) => NotificationsPage(session: s), textScale: 1.8);
  });
  testWidgets('overlapping notification refresh does not make competing requests', (t) async {
    var reads = 0;
    final pending = Completer<http.Response>();
    await fixture(t, () async {
      await flush(t);
      final refresh = t.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final first = refresh.onRefresh();
      await refresh.onRefresh(); await flush(t); expect(reads, 2);
      pending.complete(reply({'data': []})); await first; await flush(t);
      expect(find.text('Nothing yet'), findsOneWidget);
    }, (_) async => ++reads == 1 ? reply({'data': []}) : pending.future, home: (s) => NotificationsPage(session: s), textScale: 1.8);
  });
  testWidgets('failed share-list load retries without sending a message or losing the post', (t) async {
    var reads = 0;
    await fixture(t, () async {
      await t.tap(find.text('Share fixture')); await t.pumpAndSettle(); await flush(t);
      expect(find.text('Temporary failure'), findsOneWidget);
      await review(t, 'share_retry_recovery');
      await t.tap(find.text('Try again')); await flush(t);
      expect(find.text('Community picnic'), findsOneWidget);
      expect(find.text('Temporary failure'), findsNothing);
      expect(reads, 2);
    }, (r) async {
      expect(r.method, 'GET');
      return ++reads == 1 ? reply({'message': 'Temporary failure'}, 503) : reply({'data': [{'public_id': 'c', 'title': 'Community picnic'}]});
    }, home: (s) => Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => shareToChat(c, s, 'p'), child: const Text('Share fixture')))), textScale: 1.8);
  });

}
