// Tab/network and creator-return fixture tests, not device latency or live writes.
import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/reels_page.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:sanjaal/feed_page.dart' show ComposePage;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 100));
  }
}
http.Response json(Object data) => http.Response(jsonEncode(data), 200);
Future<void> fixture(WidgetTester t, Future<void> Function(Session, List<Uri>) run, {Future<http.Response?> Function(http.Request)? onRequest}) async {
  SharedPreferences.setMockInitialValues({});
  final reads = <Uri>[];
  await http.runWithClient(() async {
    final s = Session();
    await s.login('fixture', 'not-a-password');
    await run(s, reads);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }, () => MockClient((r) async {
    if (r.url.path.endsWith('/oauth/token')) return json({'access_token': 'fixture', 'expires_in': 3600});
    if (r.url.path.endsWith('/auth/me')) return json({'user': {'public_id': 'me', 'username': 'fixture', 'name': 'Fixture member'}});
    reads.add(r.url);
    final custom = await onRequest?.call(r);
    if (custom != null) return custom;
    if (r.url.path.endsWith('/users/fixture')) return json({'user': {'public_id': 'me', 'username': 'fixture', 'name': 'Fixture member'}});
    if (r.url.path.endsWith('/wallet')) return json({'balance': 0, 'entries': [], 'topup': {}});
    return json({'data': [], 'next_cursor': null, 'unread_messages': 0});
  }));
}
Future<void> select(WidgetTester t, String name) async {
  await t.tap(find.descendant(of: find.byType(GlassNavBar), matching: find.text(name)));
  await flush(t);
}
class _PickedFixture extends ImagePickerPlatform {
  @override
  Future<XFile?> getVideo({required ImageSource source, CameraDevice preferredCameraDevice = CameraDevice.rear, Duration? maxDuration}) async =>
      XFile.fromData(Uint8List.fromList([1, 2, 3, 4]), name: 'fixture.mp4', mimeType: 'video/mp4');
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async =>
      XFile.fromData(Uint8List.fromList([1, 2, 3, 4]), name: 'fixture.jpg', mimeType: 'image/jpeg');
}

void main() {
  testWidgets('startup loads only the visible Home data and unread summary', (t) async {
    await fixture(t, (s, reads) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: HomeShell(session: s)));
      await flush(t);
      expect(reads.map((u) => '${u.path}?${u.query}').toList(), [
        '/api/v1/notifications/summary?', '/api/v1/posts?kind=post', '/api/v1/stories?',
      ], reason: 'unvisited reels, chats, wallet and profile must not compete with Home startup');
      expect(t.takeException(), isNull);
    });
  });
  testWidgets('destinations load on first visit and retain their state on return', (t) async {
    await fixture(t, (s, reads) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: HomeShell(session: s)));
      await flush(t);
      int path(String name) => reads.where((u) => u.path.endsWith(name)).length;
      expect(path('/wallet'), 0);
      expect(path('/users/fixture'), 0);
      await select(t, 'Wallet');
      expect(path('/wallet'), 1);
      await select(t, 'Home');
      await select(t, 'Wallet');
      expect(path('/wallet'), 1, reason: 'revisiting does not rebuild the wallet state');
      await select(t, 'Me');
      expect(path('/users/fixture'), 1);
      await select(t, 'Home');
      await select(t, 'Me');
      expect(path('/users/fixture'), 1);
      expect(reads.where((u) => u.queryParameters['kind'] == 'reel'), isEmpty);
      await select(t, 'Reels');
      expect(reads.where((u) => u.queryParameters['kind'] == 'reel').length, 1);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('visited chats stop polling while hidden and refresh on return', (t) async {
    await fixture(t, (s, reads) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: HomeShell(session: s)));
      await flush(t);
      int chats() => reads.where((u) => u.path.endsWith('/conversations')).length;
      await select(t, 'Chats');
      expect(chats(), 1);
      await select(t, 'Home');
      await t.pump(const Duration(seconds: 13));
      await flush(t);
      expect(chats(), 1);
      await select(t, 'Chats');
      expect(chats(), 2);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('background stops shell polling and resume refreshes it', (t) async {
    addTearDown(() => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await fixture(t, (s, reads) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: HomeShell(session: s)));
      await flush(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      final pausedReads = reads.length;
      await t.pump(const Duration(seconds: 31));
      await flush(t);
      expect(reads.length, pausedReads, reason: 'no periodic HTTP work while backgrounded');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(t);
      expect(reads.where((u) => u.path.endsWith('/calls/incoming')).length, 1);
      expect(reads.where((u) => u.path.endsWith('/notifications/summary')).length, 2);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('reel publish revision arriving during load queues a fresh read', (t) async {
    final first = Completer<http.Response>();
    var requests = 0;
    await fixture(t, (s, reads) async {
      Future<void> show(int revision) async {
        await t.pumpWidget(MaterialApp(home: ReelsPage(session: s, active: true, contentRevision: revision)));
        await flush(t);
      }
      await show(0);
      await show(1);
      expect(requests, 1);
      first.complete(json({'data': [], 'next_cursor': null}));
      await flush(t);
      expect(requests, 2);
      expect(find.text('No reels yet'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, onRequest: (r) async {
      requests++;
      return requests == 1 ? first.future : json({'data': [], 'next_cursor': null});
    });
  });

  testWidgets('new story revision wins over a late older stories response', (t) async {
    final first = Completer<http.Response>();
    var requests = 0;
    Object groups(String username) => {'data': [{'author': {'username': username}, 'all_viewed': false, 'items': []}]};
    await fixture(t, (s, reads) async {
      Future<void> show(int revision) async {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: StoriesBar(session: s, contentRevision: revision))));
        await flush(t);
      }
      await show(0);
      await show(1);
      expect(find.text('new_story'), findsOneWidget);
      first.complete(json(groups('stale_story')));
      await flush(t);
      expect(find.text('new_story'), findsOneWidget);
      expect(find.text('stale_story'), findsNothing);
      expect(t.takeException(), isNull);
    }, onRequest: (r) async { requests++; return requests == 1 ? first.future : json(groups('new_story')); });
  });

  testWidgets('empty Reels creates directly, load failure retries instead', (t) async {
    var fail = false;
    var creates = 0;
    await fixture(t, (s, reads) async {
      Future<void> show() async {
        await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReelsPage(key: UniqueKey(), session: s, active: true, onCreate: () async => creates++)));
        await flush(t);
      }
      await show();
      await t.tap(find.text('Create a reel'));
      expect(creates, 1);
      fail = true;
      await show();
      expect(find.text('Create a reel'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      fail = false;
      await t.tap(find.text('Try again'));
      await flush(t);
      expect(find.text('Create a reel'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, onRequest: (r) async => fail ? http.Response(jsonEncode({'message': 'Fixture reels failure'}), 503) : null);
  });

  testWidgets('actual shell reveals a new reel after publish without refreshing manually', (t) async {
    final picker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _PickedFixture();
    addTearDown(() => ImagePickerPlatform.instance = picker);
    var published = false;
    var writes = 0;
    final post = {'public_id': 'new-reel', 'kind': 'reel', 'body': 'Community reel fixture', 'media': [], 'author': {'public_id': 'me', 'username': 'fixture'}, 'likes_count': 0, 'comments_count': 0};
    await fixture(t, (s, reads) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: HomeShell(session: s)));
      await flush(t);
      await select(t, 'Reels');
      await t.tap(find.text('Create a reel'));
      await t.pumpAndSettle();
      expect(find.byType(ComposePage), findsOneWidget);
      await t.tap(find.text('Choose a video'));
      await flush(t);
      expect(find.text('Posts as a reel'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Community reel fixture');
      await t.tap(find.widgetWithText(FilledButton, 'Post'));
      await flush(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(writes, 1);
      expect(find.byType(ComposePage), findsNothing);
      expect(find.text('Community reel fixture'), findsOneWidget);
      expect(find.text('No reels yet'), findsNothing);
      expect(t.takeException(), isNull);
    }, onRequest: (r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/posts')) { writes++; published = true; return json({'post': post}); }
      if (r.url.queryParameters['kind'] == 'reel') return json({'data': published ? [post] : [], 'next_cursor': null});
      return null;
    });
  });

  testWidgets('actual shell refreshes story rings after publishing through Create', (t) async {
    final picker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _PickedFixture();
    addTearDown(() => ImagePickerPlatform.instance = picker);
    var writes = 0;
    var storyReads = 0;
    await fixture(t, (s, reads) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: HomeShell(session: s)));
      await flush(t);
      expect(storyReads, 1);
      await t.tap(find.byTooltip('Post'));
      await t.pumpAndSettle();
      await t.tap(find.text('Story'));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Continue'));
      await t.pumpAndSettle();
      await t.tap(find.text('Choose a photo'));
      await flush(t);
      expect(writes, 0, reason: 'selection must not publish before review');
      expect(find.byType(StoryComposePage), findsOneWidget);
      await t.tap(find.text('Share story'));
      await flush(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(writes, 1);
      expect(storyReads, 1, reason: 'the confirmed story is inserted without a second list request');
      expect(find.byType(GlassNavBar), findsOneWidget);
      expect(t.takeException(), isNull);
    }, onRequest: (r) async {
      if (r.url.path.endsWith('/stories')) {
        if (r.method == 'POST') { writes++; return json({'story': {'public_id': 'new-story', 'url':'https://fixture.invalid/story.jpg', 'type':'image', 'caption':'', 'created_at':'2026-11-16T23:00:00Z'}}); }
        storyReads++;
        return json({'data': writes == 0 ? [] : [{'author': {'username': 'fixture'}, 'items': [], 'all_viewed': false}]});
      }
      return null;
    });
  });

}
