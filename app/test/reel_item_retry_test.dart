import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

import 'profile_journey_test.dart' as review;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/reels_page.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'story_session_test.dart' as fixture;

class ReelsFixture extends Session {
  ReelsFixture() : super(unregisterPush: (_) async {}) {
    user = {'public_id': 'reader', 'username': 'reader'};
    loading = false;
  }
  int reads = 0;
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    expect(method, 'GET');
    expect(path, '/posts');
    reads++;
    return {
      'data': [for (var i = 0; i < 3; i++) reel(i)],
      'next_cursor': null,
    };
  }

  void retire() {
    user = null;
    notifyListeners();
  }
}

Map<String, dynamic> reel(int id) => {
  'public_id': 'reel-$id',
  'author': {'public_id': 'author', 'username': 'author'},
  'body': 'Synthetic reel $id',
  'media': [
    {'type': 'video', 'url': 'https://fixture.invalid/$id.mp4'},
  ],
  'likes_count': 0,
  'comments_count': 0,
};
Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await t.pump(const Duration(milliseconds: 200));
  await t.pump();
}

void main() {
  setUpAll(() async {
    for (final pair in [
      (
        'Roboto',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      final loader = FontLoader(pair.$1)
        ..addFont(
          Future.value(ByteData.sublistView(File(pair.$2).readAsBytesSync())),
        );
      await loader.load();
    }
  });
  late fixture.StoryVideo video;
  late VideoPlayerPlatform previous;
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    video = fixture.StoryVideo();
    VideoPlayerPlatform.instance = video;
  });
  tearDown(() {
    VideoPlayerPlatform.instance = previous;
  });
  for (final lang in ['en', 'ne']) {
    for (final mode in [Brightness.light, Brightness.dark]) {
      testWidgets('failed item retry large-text pixels $lang ${mode.name}', (
        t,
      ) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        final s = ReelsFixture();
        video.failNext = true;
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('review'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(
                mode,
                fontFamily: 'Roboto',
                fontFamilyFallback: ['NotoDev'],
              ),
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(1.8)),
                child: w!,
              ),
              home: ReelsPage(session: s, active: true, bottomInset: 140),
            ),
          ),
        );
        await flush(t);
        await review.shot(t, 'reel-item-retry-$lang-${mode.name}');
        expect(t.takeException(), isNull);
        await t.tap(
          find
              .text(prefs.lang == 'en' ? 'Try again' : 'फेरि प्रयास गर्नुहोस्')
              .first,
        );
        await flush(t);
        expect(s.reads, 1);
        expect(video.nextId, 3);
        await t.pumpWidget(const SizedBox());
        await flush(t);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'item retry replaces only failed pooled player without refetch or page reset',
    (t) async {
      final session = ReelsFixture();
      video.failNext = true;
      await t.pumpWidget(
        MaterialApp(home: ReelsPage(session: session, active: true)),
      );
      await flush(t);
      expect(find.text('Video could not load'), findsOneWidget);
      expect(video.nextId, 2);
      expect(session.reads, 1);
      await t.tap(find.text('Try again').first);
      await flush(t);
      expect(find.text('Video could not load'), findsNothing);
      expect(video.nextId, 3);
      expect(session.reads, 1);
      expect(video.calls, contains('dispose:0'));
      expect(video.calls, isNot(contains('dispose:1')));
      expect(video.playing[2], isTrue);
      expect(t.widget<PageView>(find.byType(PageView)).controller!.page, 0);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('runtime decoder error exposes the same bounded retry', (
    t,
  ) async {
    final session = ReelsFixture();
    await t.pumpWidget(
      MaterialApp(home: ReelsPage(session: session, active: true)),
    );
    await flush(t);
    video.streams[0]!.addError(
      PlatformException(
        code: 'VideoError',
        message: 'Synthetic runtime decoder error',
      ),
    );
    await flush(t);
    expect(find.text('Video could not load'), findsOneWidget);
    await t.tap(find.text('Try again').first);
    await flush(t);
    expect(video.nextId, 3);
    expect(session.reads, 1);
    expect(video.playing[2], isTrue);
    await t.pumpWidget(const SizedBox());
    await flush(t);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'pool retry ignores healthy or pending replacements and preserves neighbours',
    (t) async {
      video.failNext = true;
      final pool = ReelPlayerPool();
      final list = [reel(0), reel(1), reel(2)];
      pool.warm(list, 1);
      await flush(t);
      final healthy = pool.forReel(list[1]);
      expect(pool.discardFailedFor(list[1]), isFalse);
      expect(pool.discardFailedFor(list[0]), isTrue);
      pool.warm(list, 1);
      expect(pool.discardFailedFor(list[0]), isFalse);
      await flush(t);
      expect(identical(healthy, pool.forReel(list[1])), isTrue);
      expect(pool.length, 3);
      expect(video.nextId, 4);
      expect(video.playing.values.any((x) => x), isFalse);
      pool.dispose();
      await flush(t);
    },
  );
  testWidgets('standalone item can retry once and respects inactive playback', (
    t,
  ) async {
    final session = ReelsFixture();
    video.failNext = true;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelItem(
            session: session,
            reel: reel(0),
            playing: true,
            muted: true,
            onToggleMute: () {},
          ),
        ),
      ),
    );
    await flush(t);
    await t.tap(find.text('Try again'));
    await flush(t);
    expect(video.nextId, 2);
    expect(find.text('Video could not load'), findsNothing);
    expect(video.playing[1], isTrue);
    await t.pumpWidget(const SizedBox());
    await flush(t);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'inactive tab cannot trigger retry and retired session cannot start late replacement',
    (t) async {
      final session = ReelsFixture();
      final active = ValueNotifier(true);
      video.failNext = true;
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, value, _) =>
                ReelsPage(session: session, active: value),
          ),
        ),
      );
      await flush(t);
      active.value = false;
      await t.pump();
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Try again').first,
            )
            .onPressed,
        isNull,
      );
      expect(video.nextId, 2);
      active.value = true;
      await t.pump();
      video.delayed = true;
      await t.tap(find.text('Try again'));
      await flush(t);
      expect(video.nextId, 3);
      session.retire();
      await t.pump();
      video.initialize(2);
      await flush(t);
      expect(video.playing.values.any((x) => x), isFalse);
      expect(find.text('Try again'), findsNothing);
      expect(session.reads, 1);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      active.dispose();
      expect(t.takeException(), isNull);
    },
  );
}
