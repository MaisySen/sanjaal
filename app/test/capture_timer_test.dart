// Controlled clock and fake camera only. No phone permission, capture or upload proof.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/capture_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/media_visibility.dart' show mediaRoutes;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'capture_library_test.dart' as h;

Future<void> mount(
  WidgetTester t,
  h.FakeCamera camera, {
  bool video = false,
  int maximum = 60,
  String lang = 'en',
  double scale = 1,
  void Function(CreatorMedia?)? result,
}) async {
  final clockStart = t.binding.clock.now();
  prefs.lang = lang;
  addTearDown(() => prefs.lang = 'en');
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('timer-review'),
      child: MaterialApp(
        navigatorObservers: [mediaRoutes],
        debugShowCheckedModeBanner: false,
        theme: buildTheme(
          Brightness.dark,
          fontFamily: 'Roboto',
          fontFamilyFallback: ['NotoDev'],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final value = await Navigator.of(context).push<CreatorMedia>(
                  MaterialPageRoute(
                    builder: (_) => CapturePage(
                      startVideo: video,
                      maxSeconds: maximum,
                      recordingClock: () =>
                          t.binding.clock.now().difference(clockStart),
                      deviceFactory: (_, _) => camera,
                    ),
                  ),
                );
                result?.call(value);
              },
              child: const Text('Open camera fixture'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open camera fixture'));
  await h.flush(t);
  await h.flush(t);
}

Future<void> choose(WidgetTester t, int delay) async {
  final presses = delay == 3
      ? 1
      : delay == 10
      ? 2
      : 3;
  for (var i = 0; i < presses; i++) {
    await t.tap(find.byKey(const ValueKey('capture-delay')));
    await t.pump();
  }
}

Future<void> shutter(WidgetTester t, [String label = 'Take a photo']) async {
  await t.tap(find.bySemanticsLabel(t_(label)));
  await t.pump();
}

Future<void> capture(WidgetTester t, String name) async {
  final folder = Platform.environment['SANJAAL_CAPTURE_TIMER_OUTPUT'];
  if (folder == null) return;
  await t.pump();
  await t.runAsync(() async {
    final image = await t
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('timer-review')),
        )
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(folder).createSync(recursive: true);
    File('$folder/widget_$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final p in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(p.$1)..addFont(
            Future.value(ByteData.sublistView(File(p.$2).readAsBytesSync())),
          ))
          .load();
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFF2C656C), BlendMode.src);
    final image = await recorder.endRecording().toImage(20, 20);
    h.imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
  });
  testWidgets(
    'timer is off by default and cycling back off preserves immediate capture',
    (t) async {
      final camera = h.FakeCamera();
      CreatorMedia? result;
      await mount(t, camera, result: (v) => result = v);
      await capture(t, 'timer_off');
      await choose(t, 0);
      await shutter(t);
      await h.flush(t);
      expect(camera.calls.where((s) => s == 'photo').length, 1);
      expect(result?.isVideo, isFalse);
      expect(t.takeException(), isNull);
    },
  );
  for (final delay in [3, 10]) {
    testWidgets('$delay second photo waits then captures once for review', (
      t,
    ) async {
      final camera = h.FakeCamera();
      CreatorMedia? result;
      await mount(t, camera, result: (v) => result = v);
      await choose(t, delay);
      await shutter(t);
      await t.pump(Duration(seconds: delay - 1));
      expect(camera.calls, isNot(contains('photo')));
      expect(result, isNull);
      await t.pump(const Duration(seconds: 1));
      await h.flush(t);
      expect(camera.calls.where((s) => s == 'photo').length, 1);
      expect(result?.isVideo, isFalse);
      await t.pump(const Duration(seconds: 15));
      expect(camera.calls.where((s) => s == 'photo').length, 1);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'cancelled countdown never fires and requires another explicit shutter',
    (t) async {
      final camera = h.FakeCamera();
      await mount(t, camera);
      await choose(t, 3);
      await shutter(t);
      await t.pump(const Duration(seconds: 1));
      await shutter(t, 'Cancel countdown');
      await t.pump(const Duration(seconds: 15));
      expect(camera.calls, isNot(contains('photo')));
      expect(find.bySemanticsLabel('Take a photo'), findsOneWidget);
      await shutter(t);
      await t.pump(const Duration(seconds: 3));
      await h.flush(t);
      expect(camera.calls.where((s) => s == 'photo').length, 1);
    },
  );
  testWidgets(
    'retained mode settings and timer controls cannot alter an armed capture',
    (t) async {
      final camera = h.FakeCamera();
      await mount(t, camera);
      await choose(t, 3);
      final timer = t
          .widget<IconButton>(find.byKey(const ValueKey('capture-delay')))
          .onPressed!;
      final mode = t
          .widget<TextButton>(find.widgetWithText(TextButton, 'Video'))
          .onPressed!;
      final flip = t
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Switch camera'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!;
      final flash = t
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Flash off'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!;
      await shutter(t);
      timer();
      mode();
      flip();
      flash();
      await t.pump();
      expect(camera.calls, ['init']);
      expect(find.bySemanticsLabel('Cancel countdown'), findsOneWidget);
      expect(
        t
            .widget<IconButton>(find.byKey(const ValueKey('capture-delay')))
            .onPressed,
        isNull,
      );
      await shutter(t, 'Cancel countdown');
    },
  );
  for (final exit in ['close', 'back', 'dispose', 'background', 'covered']) {
    testWidgets(
      '$exit cancels armed countdown without hidden capture or automatic restart',
      (t) async {
        final camera = h.FakeCamera();
        await mount(t, camera);
        await choose(t, 3);
        await shutter(t);
        await t.pump(const Duration(seconds: 1));
        if (exit == 'close') {
          await t.tap(find.byTooltip('Close camera'));
        }
        if (exit == 'back') {
          await t.binding.handlePopRoute();
        }
        if (exit == 'dispose') {
          await t.pumpWidget(const SizedBox());
        }
        if (exit == 'background') {
          h.background(t);
        }
        if (exit == 'covered') {
          final nav = t.state<NavigatorState>(find.byType(Navigator));
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered fixture')),
            ),
          );
          await t.pump();
          nav.pop();
        }
        await h.flush(t);
        await t.pump(const Duration(seconds: 15));
        expect(camera.calls, isNot(contains('photo')));
        expect(camera.calls, isNot(contains('start')));
        if (exit == 'background') {
          h.foreground(t);
          await h.flush(t);
          await t.pump(const Duration(seconds: 5));
          expect(camera.calls, isNot(contains('photo')));
        }
        await t.pumpWidget(const SizedBox());
        h.foreground(t);
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'video delay does not consume recording duration and Stop is immediate',
    (t) async {
      final camera = h.FakeCamera();
      CreatorMedia? result;
      await mount(
        t,
        camera,
        video: true,
        maximum: 2,
        result: (v) => result = v,
      );
      await choose(t, 3);
      await shutter(t, 'Start recording');
      await t.pump(const Duration(seconds: 2));
      expect(camera.calls, isNot(contains('start')));
      await t.pump(const Duration(seconds: 1));
      await h.flush(t);
      expect(camera.calls.where((s) => s == 'start').length, 1);
      expect(camera.calls, isNot(contains('stop')));
      await shutter(t, 'Stop recording');
      await h.flush(t);
      expect(camera.calls.where((s) => s == 'stop').length, 1);
      expect(result?.isVideo, isTrue);
      expect(t.takeException(), isNull);
    },
  );
  for (final lang in ['en', 'ne']) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'countdown and cancel are readable at 320 pixels $lang $scale',
        (t) async {
          final camera = h.FakeCamera();
          await mount(t, camera, lang: lang, scale: scale);
          await choose(t, 10);
          await shutter(t);
          expect(
            find.bySemanticsLabel(t_('Cancel countdown')).hitTestable(),
            findsOneWidget,
          );
          expect(find.text('10'), findsWidgets);
          expect(
            t.getSize(find.byKey(const ValueKey('capture-delay'))).width,
            greaterThanOrEqualTo(48),
          );
          final number = t.getRect(
            find.byKey(const ValueKey('capture-countdown-number')),
          );
          final circle = t
              .getRect(find.byKey(const ValueKey('capture-countdown-circle')))
              .deflate(8);
          expect(circle.contains(number.topLeft), isTrue);
          expect(circle.contains(number.bottomRight), isTrue);
          expect(t.takeException(), isNull);
          await capture(t, 'countdown_${lang}_$scale');
          await shutter(t, 'Cancel countdown');
        },
      );
    }
  }
}
