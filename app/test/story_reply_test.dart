import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/story_reply_page.dart';
import 'package:sanjaal/stories_page.dart';

import 'story_session_test.dart' as viewer;

import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

import 'profile_journey_test.dart' as review;

class ReplySession extends Session {
  ReplySession({bool supported = true}) : super(unregisterPush: (_) async {}) {
    user = {'public_id': 'reader', 'username': 'reader'};
    storyRepliesEnabled = supported;
    loading = false;
  }
  final sent = <Map<String, dynamic>>[];
  Future<dynamic> Function(Map<String, dynamic>)? respond;
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    expect(method, 'POST');
    expect(path, '/stories/stable-story-id/reply');
    final data = Map<String, dynamic>.from(body!);
    sent.add(data);
    return respond == null
        ? {
            'message': {'public_id': 'message', 'kind': 'storyreply', ...data},
          }
        : respond!(data);
  }

  void retire() {
    user = {'public_id': 'replacement', 'username': 'replacement'};
    notifyListeners();
  }
}

Future<void> mount(
  WidgetTester t,
  ReplySession session, {
  double scale = 1,
  double keyboard = 0,
  Brightness brightness = Brightness.light,
}) async {
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        brightness,
        fontFamily: 'Roboto',
        fontFamilyFallback: ['NotoDev'],
      ),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: w!,
      ),
      home: StoryReplyPage(
        session: session,
        storyId: 'stable-story-id',
        authorName: '@story_owner',
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
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
  testWidgets('no send before explicit action and confirmed success is final', (
    t,
  ) async {
    final s = ReplySession();
    await mount(t, s);
    expect(s.sent, isEmpty);
    await t.enterText(find.byType(TextField), 'Lovely view');
    await t.pump();
    expect(s.sent, isEmpty);
    await t.tap(find.text('Send reply'));
    await t.pumpAndSettle();
    expect(s.sent.single['body'], 'Lovely view');
    expect(find.text('Reply sent. Find it in your chat.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(s.sent.length, 1);
  });
  testWidgets(
    'unknown outcome locks text and retries exactly the same message key',
    (t) async {
      final s = ReplySession();
      var requests = 0;
      s.respond = (body) async {
        if (++requests == 1) throw StateError('Synthetic offline');
        return {
          'message': {'kind': 'storyreply', ...body},
        };
      };
      await mount(t, s);
      await t.enterText(find.byType(TextField), 'Original words');
      await t.pump();
      await t.tap(find.text('Send reply'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.textContaining('Delivery is unconfirmed.'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(s.sent.length, 2);
      expect(s.sent.first, s.sent.last);
      expect(find.text('Reply sent. Find it in your chat.'), findsOneWidget);
    },
  );
  testWidgets(
    'pending send blocks repeated sends and retired session ignores late result',
    (t) async {
      final s = ReplySession();
      final result = Completer<dynamic>();
      s.respond = (_) => result.future;
      await mount(t, s);
      await t.enterText(find.byType(TextField), 'Private reply');
      await t.pump();
      await t.tap(find.text('Send reply'));
      await t.pump();
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      s.retire();
      await t.pump();
      result.complete({
        'message': {'kind': 'storyreply', ...s.sent.single},
      });
      await t.pumpAndSettle();
      expect(find.text('Private reply'), findsNothing);
      expect(find.text('Reply sent. Find it in your chat.'), findsNothing);
      expect(s.sent.length, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('older server has no enabled reply write', (t) async {
    final s = ReplySession(supported: false);
    await mount(t, s);
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(
      find.text('Story replies are not available on this server.'),
      findsOneWidget,
    );
    expect(s.sent, isEmpty);
  });
  testWidgets(
    'malformed success stays unconfirmed and route-back warns before losing retry',
    (t) async {
      final s = ReplySession();
      s.respond = (_) async => {
        'message': {'kind': 'text', 'client_id': 'wrong'},
      };
      await mount(t, s);
      await t.enterText(find.byType(TextField), 'Hello');
      await t.pump();
      await t.tap(find.text('Send reply'));
      await t.pumpAndSettle();
      expect(find.textContaining('Delivery is unconfirmed.'), findsOneWidget);
      expect(find.text('Reply sent. Find it in your chat.'), findsNothing);
      unawaited(t.binding.handlePopRoute());
      await t.pumpAndSettle();
      expect(find.text('Leave an unconfirmed reply?'), findsOneWidget);
      await t.tap(find.text('Stay here'));
      await t.pumpAndSettle();
      expect(find.byType(StoryReplyPage), findsOneWidget);
      expect(s.sent.length, 1);
    },
  );
  for (final enabled in [false, true]) {
    testWidgets('story viewer reply entry obeys service capability $enabled', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1; addTearDown(t.view.reset);
      await viewer.fixture((s) async {
        s.storyRepliesEnabled = enabled;
        final photo = File('/downloads/sanjaal-highfidelity/cat.jpg').readAsBytesSync();
        s.photo = Future.value(photo);
        final item = viewer.group();
        item['author'] = {
          'public_id': 'story-owner',
          'username': 'story_owner',
        };
        await t.pumpWidget(
          RepaintBoundary(key: const ValueKey('review'), child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
            home: StoryViewer(session: s, group: item),
          )),
        );
        await viewer.flush(t);
        await t.runAsync(() => precacheImage(MemoryImage(photo), t.element(find.byType(StoryViewer))));
        await t.pump();
        expect(
          find.text('Reply to story'),
          enabled ? findsOneWidget : findsNothing,
        );
        if (enabled) {
          await review.shot(t, 'story-viewer-reply-entry');
          await t.tap(find.text('Reply to story'));
          await viewer.flush(t);
          expect(find.byType(StoryReplyPage), findsOneWidget);
          expect(find.text('@story_owner'), findsOneWidget);
          expect(s.requests.where((x) => x.endsWith('/reply')), isEmpty);
          await t.pump(const Duration(seconds: 8));
          expect(find.byType(StoryReplyPage), findsOneWidget);
          await t.pageBack();
          await viewer.flush(t);
          expect(find.byType(StoryViewer), findsOneWidget);
        }
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(t.takeException(), isNull);
      });
    });
  }
  for (final language in ['en', 'ne']) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('reply keyboard layout $language ${brightness.name}', (
        t,
      ) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        prefs.lang = language;
        addTearDown(() => prefs.lang = 'en');
        final s = ReplySession();
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('review'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(
                brightness,
                fontFamily: 'Roboto',
                fontFamilyFallback: ['NotoDev'],
              ),
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c).copyWith(
                  textScaler: TextScaler.linear(1.8),
                  viewInsets: const EdgeInsets.only(bottom: 240),
                ),
                child: w!,
              ),
              home: StoryReplyPage(
                session: s,
                storyId: 'stable-story-id',
                authorName: '@story_owner',
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byType(TextField),
          language == 'en'
              ? 'A lovely view. Thank you for sharing.'
              : 'सुन्दर दृश्य। साझा गर्नुभएकोमा धन्यवाद।',
        );
        await t.ensureVisible(find.byType(FilledButton));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await review.shot(t, 'story-reply-$language-${brightness.name}');
        expect(s.sent, isEmpty);
      });
    }
  }
}
