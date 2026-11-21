// Synthetic status/keyboard insets on the actual retained shell, not OS proof.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/reels_page.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/glass/glass_app_bar.dart';
import 'package:sanjaal/upload_center.dart';

import 'upload_acknowledgement_test.dart' show AckStore, post;

class InsetSession extends Session {
  bool populated = false;
  InsetSession() {
    user = {'public_id': 'inset-member', 'username': 'inset_member'};
  }
  @override
  void prefetchHome() {}
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method != 'GET') throw StateError('Unexpected mutation');
    return {
      'data': populated && query?['kind'] == 'reel'
          ? [
              {...post('retained-reel'), 'kind': 'reel'},
            ]
          : [],
      'next_cursor': null,
      'unread_messages': 0,
    };
  }

  void connection(bool value) {
    offline = value;
    notifyListeners();
  }
}

Future<void> frames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> picture(WidgetTester t, GlobalKey key, String label) async {
  await t.pump(const Duration(milliseconds:300));
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  repaint(key.currentContext!.findRenderObject()!);
  await t.pump(const Duration(milliseconds: 100));
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/downloads/sj-inset-$label.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader('NotoDev')..addFont(
          File('assets/fonts/NotoSansDevanagari.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        ))
        .load();
    for (final name in ['Roboto', 'MaterialIcons']) {
      final ext = name == 'Roboto'
          ? 'Roboto-Regular.ttf'
          : 'MaterialIcons-Regular.otf';
      await (FontLoader(name)..addFont(
            File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/$ext',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  for (final scale in [1.0, 1.8]) {
    for (final keyboard in [false, true]) {
      testWidgets('shell owns top inset once scale$scale keyboard$keyboard', (
        t,
      ) async {
        prefs.lang = 'en';
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        t.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        t.view.padding = FakeViewPadding(top: 59, bottom: keyboard ? 0 : 34);
        t.view.viewInsets = FakeViewPadding(bottom: keyboard ? 300 : 0);
        addTearDown(t.view.reset);
        final s = InsetSession(), store = AckStore(), key = GlobalKey();
        final c = UploadCenter.of(s, store: store);
        await frames(t);
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: HomeShell(session: s),
            ),
          ),
        );
        await frames(t);
        final feed = find.byType(FeedPage);
        final originalState = t.state(find.byType(FeedList).first);
        expect(MediaQuery.paddingOf(t.element(feed)).top, 59);
        final baseline = t.getRect(find.byType(ReviewedAppBar).first).height;
        final baselineBottom = MediaQuery.viewPaddingOf(t.element(feed)).bottom;
        final baselineNav = t.getRect(find.byType(GlassNavBar));
        if (scale == 1 && !keyboard) await picture(t, key, 'no-strip');
        c.start('post', () async => post('inset-post'));
        await frames(t);
        expect(t.takeException(), isNull, reason: 'ack transition');
        expect(find.text('Your post is up.'), findsOneWidget);
        final ackBottom = t.getRect(find.byType(UploadStrip)).bottom;
        final header = t.getRect(find.byType(ReviewedAppBar).first);
        expect(header.top, closeTo(ackBottom, .01));
        expect(baseline - header.height, closeTo(59, .01));
        expect(MediaQuery.paddingOf(t.element(feed)).top, 0);
        expect(
          MediaQuery.viewPaddingOf(t.element(feed)).bottom,
          baselineBottom,
        );
        expect(t.getRect(find.byType(GlassNavBar)), baselineNav);
        expect(
          identical(originalState, t.state(find.byType(FeedList).first)),
          isTrue,
        );
        if (scale == 1 && !keyboard) await picture(t, key, 'ack-corrected');
        s.connection(true);
        await frames(t);
        expect(t.takeException(), isNull, reason: 'offline transition');
        expect(
          find.text('No connection. Some things may be out of date.'),
          findsOneWidget,
        );
        expect(
          find.text('Your post is up.'),
          findsOneWidget,
          reason: 'both independent strips remain until acknowledgement expiry',
        );
        final offlineText = t.getRect(
          find.text('No connection. Some things may be out of date.'),
        );
        expect(offlineText.top - ackBottom, lessThan(40 * scale));
        expect(MediaQuery.paddingOf(t.element(feed)).top, 0);
        if (scale == 1 && !keyboard) await picture(t, key, 'both-corrected');
        c.finishAcknowledgement();
        await frames(t);
        expect(t.takeException(), isNull, reason: 'ack transition');
        expect(find.text('Your post is up.'), findsNothing);
        expect(MediaQuery.paddingOf(t.element(feed)).top, 0);
        s.connection(false);
        await frames(t);
        expect(MediaQuery.paddingOf(t.element(feed)).top, 59);
        expect(t.getRect(find.byType(ReviewedAppBar).first).height, baseline);
        expect(
          identical(originalState, t.state(find.byType(FeedList).first)),
          isTrue,
        );
        await t.tap(
          find.descendant(
            of: find.byType(GlassNavBar),
            matching: find.byTooltip('Reels'),
          ),
        );
        await frames(t);
        final reels = find.byType(ReelsPage);
        final reelState = t.state(reels);
        expect(MediaQuery.paddingOf(t.element(reels)).top, 59);
        expect(
          t.getTopLeft(reels).dy,
          0,
          reason: 'no-strip Reels keeps full-bleed origin',
        );
        s.connection(true);
        await frames(t);
        expect(t.takeException(), isNull, reason: 'offline transition');
        expect(MediaQuery.paddingOf(t.element(reels)).top, 0);
        expect(t.getTopLeft(reels).dy, greaterThan(59));
        final pending = Completer<Map<String, dynamic>>();
        c.start('reel', () => pending.future);
        await frames(t);
        expect(MediaQuery.paddingOf(t.element(reels)).top, 0);
        s.connection(false);
        await frames(t);
        expect(t.takeException(), isNull, reason: 'busy only transition');
        expect(MediaQuery.paddingOf(t.element(reels)).top, 0);
        if (scale == 1.8 && keyboard) {
          await picture(t, key, 'large-keyboard-reels-busy');
        }
        pending.completeError(
          UploadError(
            'The upload result is unknown. Check your posts or stories before sharing again.',
            uncertain: true,
          ),
        );
        await frames(t);
        expect(t.takeException(), isNull, reason: 'uncertain with keyboard');
        expect(MediaQuery.paddingOf(t.element(reels)).top, 0);
        expect(identical(reelState, t.state(reels)), isTrue);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump();
      });
    }
  }
  for (final top in [0.0, 59.0]) {
    testWidgets('populated immersive Reels preserves full-bleed top$top', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      t.view.padding = FakeViewPadding(top: top, bottom: 34);
      t.view.viewPadding = FakeViewPadding(top: top, bottom: 34);
      addTearDown(t.view.reset);
      final s = InsetSession()..populated = true,
          c = UploadCenter.of(s, store: AckStore());
      await frames(t);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
          home: HomeShell(session: s),
        ),
      );
      await frames(t);
      await t.tap(
        find.descendant(
          of: find.byType(GlassNavBar),
          matching: find.byTooltip('Reels'),
        ),
      );
      await frames(t);
      final reels = find.byType(ReelsPage);
      expect(find.byType(ReelItem), findsOneWidget);
      final state = t.state(reels);
      expect(t.getTopLeft(reels).dy, 0);
      expect(MediaQuery.paddingOf(t.element(reels)).top, top);
      final pending = Completer<Map<String, dynamic>>();
      c.start('reel', () => pending.future);
      await frames(t);
      expect(MediaQuery.paddingOf(t.element(reels)).top, 0);
      expect(t.getTopLeft(reels).dy, greaterThanOrEqualTo(top));
      pending.complete({...post('retained-reel'),'kind':'reel'});
      await frames(t);
      c.finishAcknowledgement();
      await frames(t);
      expect(t.getTopLeft(reels).dy, 0);
      expect(identical(state, t.state(reels)), isTrue);
      expect(MediaQuery.paddingOf(t.element(reels)).top, top);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
  }
}
