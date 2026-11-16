// Real media widgets against a fake video platform. No codec, device, speaker,
// microphone, camera or live delivery is exercised.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/reels_page.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:sanjaal/media_visibility.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Video extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final playing = <int, bool>{};
  final calls = <String>[];
  var nextId = 0;
  bool delayed = false;
  @override
  Future<void> init() async {}
  void initialize(int id) => streams[id]!.add(VideoEvent(eventType: VideoEventType.initialized, size: const Size(100, 100), duration: const Duration(seconds: 30)));
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = nextId++;
    streams[id] = StreamController<VideoEvent>();
    playing[id] = false;
    if (!delayed) initialize(id);
    return id;
  }
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async { calls.add('dispose:$playerId'); playing[playerId] = false; }
  @override
  Future<void> play(int playerId) async { calls.add('play:$playerId'); playing[playerId] = true; }
  @override
  Future<void> pause(int playerId) async { calls.add('pause:$playerId'); playing[playerId] = false; }
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(color: Colors.black);
}
Future<void> flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await t.pump(const Duration(milliseconds: 400));
}
Widget app(Widget child, {GlobalKey<NavigatorState>? nav}) => MaterialApp(navigatorKey: nav, navigatorObservers: [mediaRoutes], home: Scaffold(body: child));
Widget reel({bool active = true}) => ReelItem(session: Session(), reel: {'public_id': 'reel', 'body': 'Fixture', 'media': [{'type': 'video', 'url': 'https://fixture.invalid/video.mp4'}], 'author': {'username': 'fixture'}}, playing: active, muted: false, onToggleMute: () {});
Widget story() => StoryViewer(session: Session(), group: {'author': {'username': 'fixture'}, 'items': [{'public_id': 'story', 'type': 'video', 'url': 'https://fixture.invalid/story.mp4', 'created_at': '2026-11-16T14:00:00Z'}]});
void background(WidgetTester t) {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    t.binding.handleAppLifecycleStateChanged(state);
  }
}
void foreground(WidgetTester t) {
  for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    t.binding.handleAppLifecycleStateChanged(state);
  }
}
void main() {
  late _Video video;
  late VideoPlayerPlatform old;
  setUp(() { old = VideoPlayerPlatform.instance; video = _Video(); VideoPlayerPlatform.instance = video; });
  tearDown(() { VideoPlayerPlatform.instance = old; });
  testWidgets('Reels pool retains previous/current/next without restarting a back swipe', (t) async {
    final pool=ReelPlayerPool();
    final items=[for(var i=0;i<6;i++) <String,dynamic>{'public_id':'r$i','media':[{'type':'video','url':'https://fixture.invalid/$i.mp4'}]}];
    pool.warm(items,1); await flush(t); expect(pool.length,3); expect(video.nextId,3);
    final previous=pool.forReel(items[1]);
    pool.warm(items,2); await flush(t); expect(pool.length,3); expect(video.nextId,4);
    expect(identical(pool.forReel(items[1]),previous),isTrue);
    pool.warm(items,1); await flush(t); expect(identical(pool.forReel(items[1]),previous),isTrue);
    expect(video.playing.values.every((p)=>!p),isTrue,reason:'preparation must never autoplay an adjacent reel');
    pool.dispose();await flush(t);expect(video.calls.where((c)=>c.startsWith('dispose:')).length,video.nextId);
  });
  testWidgets('Reels pool stops and discards players outside its three-item window', (t) async {
    final pool=ReelPlayerPool(); final items=[for(var i=0;i<6;i++) <String,dynamic>{'media':[{'type':'video','url':'https://fixture.invalid/$i.mp4'}]}];
    pool.warm(items,0);await flush(t);final old=pool.forReel(items[0])!;
    pool.warm(items,4);await flush(t);expect(old.disposed,isTrue);expect(pool.length,3);
    pool.warm(items,4);await flush(t);expect(video.nextId,5,reason:'repeated builds do not initialize players again');
    pool.dispose();await flush(t);
  });
  testWidgets('local story preview waits for play, pauses in background and stays paused on resume', (t) async {
    await t.pumpWidget(app(StoryComposePage(session: Session(), file: XFile.fromData(Uint8List.fromList([1,2,3]), path: '/fixture.mp4', name: 'fixture.mp4'), isVideo: true)));
    await flush(t); expect(video.playing[0], isFalse);
    await t.tap(find.byTooltip('Play')); await flush(t); expect(video.playing[0], isTrue);
    background(t); await flush(t); expect(video.playing[0], isFalse);
    foreground(t); await flush(t); expect(video.playing[0], isFalse);
    await t.pumpWidget(const SizedBox()); await flush(t); expect(video.calls, contains('dispose:0')); expect(t.takeException(), isNull);
  });
  testWidgets('local story preview pauses when another route covers it', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(app(StoryComposePage(session: Session(), file: XFile.fromData(Uint8List.fromList([1,2,3]), path: '/fixture.mp4', name: 'fixture.mp4'), isVideo: true), nav: nav));
    await flush(t); await t.tap(find.byTooltip('Play')); await flush(t); expect(video.playing[0], isTrue);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Cover'))));
    await flush(t); expect(video.playing[0], isFalse);
    nav.currentState!.pop(); await flush(t); expect(video.playing[0], isFalse);
    await t.pumpWidget(const SizedBox()); await flush(t); expect(t.takeException(), isNull);
  });
  for (final type in ['reel', 'feed']) {
    testWidgets('$type pauses under a pushed route and does not play while covered', (t) async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(type == 'reel' ? reel() : const VideoTile(url: 'https://fixture.invalid/feed.mp4'), nav: nav));
      await flush(t);
      if (type == 'feed') { await t.tap(find.byType(VideoTile)); await flush(t); }
      expect(video.playing[0], isTrue);
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Cover'))));
      await flush(t);
      expect(video.playing[0], isFalse);
      nav.currentState!.pop();
      await flush(t);
      expect(video.playing[0], type == 'reel', reason: 'autoplay reel resumes, manually played feed stays paused');
      await t.pumpWidget(const SizedBox());
      await flush(t);
      expect(video.playing[0], isFalse);
      expect(t.takeException(), isNull);
    });
    testWidgets('$type stops when its tab ticker is hidden', (t) async {
      Future<void> show(bool enabled) async {
        await t.pumpWidget(app(TickerMode(enabled: enabled, child: type == 'reel' ? reel() : const VideoTile(url: 'https://fixture.invalid/feed.mp4'))));
        await flush(t);
      }
      await show(true);
      if (type == 'feed') { await t.tap(find.byType(VideoTile)); await flush(t); }
      expect(video.playing[0], isTrue);
      await show(false);
      expect(video.playing[0], isFalse);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('late reel initialization does not autoplay under a covered route', (t) async {
    video.delayed = true;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(app(reel(), nav: nav));
    await flush(t);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Cover'))));
    await flush(t);
    video.initialize(0);
    await flush(t);
    expect(video.calls, isNot(contains('play:0')));
    nav.currentState!.pop();
    await flush(t);
    expect(video.playing[0], isTrue);
    await t.pumpWidget(const SizedBox());
    await flush(t);
    expect(t.takeException(), isNull);
  });
  testWidgets('reel pauses in background and resumes only in foreground', (t) async {
    addTearDown(() => foreground(t));
    await t.pumpWidget(app(reel()));
    await flush(t);
    expect(video.playing[0], isTrue);
    background(t);
    await flush(t);
    expect(video.playing[0], isFalse);
    foreground(t);
    await flush(t);
    expect(video.playing[0], isTrue);
    await t.pumpWidget(const SizedBox());
    await flush(t);
    expect(t.takeException(), isNull);
  });
  testWidgets('story timer and video stop under another route and background', (t) async {
    addTearDown(() => foreground(t));
    await http.runWithClient(() async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(story(), nav: nav));
      await flush(t);
      expect(video.playing[0], isTrue);
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Cover'))));
      await flush(t);
      expect(video.playing[0], isFalse);
      await t.pump(const Duration(seconds: 31));
      expect(find.text('Cover'), findsOneWidget);
      nav.currentState!.pop();
      await flush(t);
      expect(find.byType(StoryViewer), findsOneWidget);
      expect(video.playing[0], isTrue);
      background(t);
      await flush(t);
      expect(video.playing[0], isFalse);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      expect(t.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode({}), 200)));
  });
  testWidgets('story long press pauses actual controller and release resumes', (t) async {
    await http.runWithClient(() async {
      await t.pumpWidget(app(story()));
      await flush(t);
      expect(video.playing[0], isTrue);
      final gesture = await t.startGesture(const Offset(400, 300));
      await t.pump(const Duration(milliseconds: 600));
      await flush(t);
      expect(video.playing[0], isFalse);
      await gesture.up();
      await flush(t);
      expect(video.playing[0], isTrue);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      expect(t.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });
  testWidgets('reel pauses beneath a modal sheet and resumes after dismissal', (t) async {
    await t.pumpWidget(app(reel()));
    await flush(t);
    expect(video.playing[0], isTrue);
    showModalBottomSheet<void>(context: t.element(find.byType(ReelItem)), builder: (_) => const SizedBox(height: 100));
    await flush(t);
    expect(video.playing[0], isFalse);
    Navigator.of(t.element(find.byType(ReelItem))).pop();
    await flush(t);
    expect(video.playing[0], isTrue);
    await t.pumpWidget(const SizedBox());
    await flush(t);
    expect(t.takeException(), isNull);
  });
  testWidgets('late story initialization after exit cannot start playback', (t) async {
    video.delayed = true;
    await http.runWithClient(() async {
      await t.pumpWidget(app(story()));
      await flush(t);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      video.initialize(0);
      await flush(t);
      expect(video.calls, isNot(contains('play:0')));
      expect(video.calls, contains('dispose:0'));
      expect(t.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });
}
