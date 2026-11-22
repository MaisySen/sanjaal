// Fake camera and controlled clock. Not native capture, hardware or codec proof.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/capture_page.dart';
import 'package:sanjaal/capture_release_guard.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'capture_library_test.dart' as h;
import 'capture_timer_test.dart' as timer;

class PausableCamera extends h.FakeCamera implements PausableCaptureDevice {
  Completer<void>? pausePending, resumePending;
  bool failPause = false,
      failResume = false,
      failStop = false,
      failRelease = false;
  @override
  Future<void> pauseRecording() async {
    calls.add('pause');
    if (pausePending != null) await pausePending!.future;
    if (failPause) throw StateError('Synthetic pause failure');
  }

  @override
  Future<void> resumeRecording() async {
    calls.add('resume');
    if (resumePending != null) await resumePending!.future;
    if (failResume) throw StateError('Synthetic resume failure');
  }

  @override
  Future<XFile> stop() async {
    if (failStop) {
      calls.add('stop');
      throw StateError('Synthetic stop failure');
    }
    return super.stop();
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    if (failRelease) throw StateError('Synthetic release failure');
  }
}

Future<void> toggle(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('recording-pause')));
  await t.pump();
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
  });

  test('uncertain native release blocks another initialization until process restart', () async {
    final guard = CaptureReleaseGuard();
    guard.ensureAvailable();
    guard.markUncertain();
    expect(guard.restartRequired, isTrue);
    final native = NativeCaptureDevice(
      video: true,
      front: false,
      releaseGuard: guard,
    );
    await expectLater(
      native.initialize(),
      throwsA(isA<CaptureRestartRequired>()),
    );
    expect(native.controller, isNull);
  });

  testWidgets(
    'pause excludes waiting and resume keeps one clip and the remaining limit',
    (t) async {
      final camera = PausableCamera();
      CreatorMedia? result;
      await timer.mount(
        t,
        camera,
        video: true,
        maximum: 5,
        result: (v) => result = v,
      );
      await timer.shutter(t, 'Start recording');
      await t.pump(const Duration(milliseconds: 600));
      await toggle(t);
      expect(find.textContaining('Paused ·'), findsOneWidget);
      final frozen = t.widget<Text>(find.textContaining('Paused ·')).data;
      await t.pump(const Duration(minutes: 10));
      expect(t.widget<Text>(find.textContaining('Paused ·')).data, frozen);
      expect(camera.calls, isNot(contains('stop')));
      expect(result, isNull);
      await toggle(t);
      await t.pump(const Duration(seconds: 1));
      expect(camera.calls, isNot(contains('stop')));
      await t.pump(const Duration(seconds: 5));
      await h.flush(t);
      expect(result?.isVideo, isTrue);
      expect(camera.calls.where((v) => v == 'start').length, 1);
      expect(camera.calls.where((v) => v == 'pause').length, 1);
      expect(camera.calls.where((v) => v == 'resume').length, 1);
      expect(camera.calls.where((v) => v == 'stop').length, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pause label waits for native confirmation and retained taps cannot overlap',
    (t) async {
      final camera = PausableCamera()..pausePending = Completer<void>();
      await timer.mount(t, camera, video: true);
      await timer.shutter(t, 'Start recording');
      final button = find.byKey(const ValueKey('recording-pause'));
      final retained = t.widget<TextButton>(button).onPressed!;
      await toggle(t);
      retained();
      await t.pump();
      expect(find.text('Pausing recording...'), findsOneWidget);
      expect(find.textContaining('Paused ·'), findsNothing);
      expect(t.widget<TextButton>(button).onPressed, isNull);
      expect(camera.calls.where((v) => v == 'pause').length, 1);
      camera.pausePending!.complete();
      await t.pump();
      await t.pump();
      expect(find.textContaining('Paused ·'), findsOneWidget);
      await timer.shutter(t, 'Stop recording');
      await h.flush(t);
    },
  );

  testWidgets(
    'resume is explicit and does not claim paused while native resume is pending',
    (t) async {
      final camera = PausableCamera()..resumePending = Completer<void>();
      await timer.mount(t, camera, video: true);
      await timer.shutter(t, 'Start recording');
      await toggle(t);
      await toggle(t);
      expect(find.text('Resuming recording...'), findsOneWidget);
      expect(find.textContaining('Paused ·'), findsNothing);
      camera.resumePending!.complete();
      await t.pump();
      await t.pump();
      expect(find.text('Pause recording'), findsOneWidget);
      await timer.shutter(t, 'Stop recording');
      await h.flush(t);
    },
  );

  for (final failed in ['pause', 'resume']) {
    testWidgets(
      '$failed failure preserves confirmed clip for explicit review, never restarts',
      (t) async {
        final camera = PausableCamera();
        CreatorMedia? result;
        await timer.mount(t, camera, video: true, result: (v) => result = v);
        await timer.shutter(t, 'Start recording');
        if (failed == 'resume') await toggle(t);
        camera.failPause = failed == 'pause';
        camera.failResume = failed == 'resume';
        await toggle(t);
        await h.flush(t);
        expect(
          find.text(
            'Recording controls failed. Your saved clip is ready to review. Nothing was posted.',
          ),
          findsOneWidget,
        );
        expect(result, isNull);
        expect(camera.calls.where((v) => v == 'stop').length, 1);
        expect(camera.calls.where((v) => v == 'dispose').length, 1);
        expect(camera.calls.where((v) => v == 'start').length, 1);
        await t.ensureVisible(find.text('Review capture'));
        await t.tap(find.text('Review capture'));
        await h.flush(t);
        expect(result?.isVideo, isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'stop failure does not invent a saved clip and confirmed release allows retry',
    (t) async {
      final camera = PausableCamera()
        ..failPause = true
        ..failStop = true;
      await timer.mount(t, camera, video: true);
      await timer.shutter(t, 'Start recording');
      await toggle(t);
      await h.flush(t);
      expect(
        find.text(
          'Recording controls failed and no clip could be recovered. Nothing was posted.',
        ),
        findsOneWidget,
      );
      expect(find.text('Review capture'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(camera.calls.where((v) => v == 'dispose').length, 1);
    },
  );

  testWidgets(
    'failed cleanup cannot offer another camera session or a silent restart',
    (t) async {
      final camera = PausableCamera()
        ..failPause = true
        ..failRelease = true;
      await timer.mount(t, camera, video: true);
      await timer.shutter(t, 'Start recording');
      await toggle(t);
      await h.flush(t);
      expect(
        find.textContaining('Camera cleanup could not be confirmed.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      h.background(t);
      await h.flush(t);
      h.foreground(t);
      await h.flush(t);
      expect(camera.calls.where((v) => v == 'init').length, 1);
      expect(camera.calls.where((v) => v == 'start').length, 1);
    },
  );

  testWidgets(
    'timeout quarantines the session and a late pause cannot alter recovery',
    (t) async {
      final camera = PausableCamera()..pausePending = Completer<void>();
      await timer.mount(t, camera, video: true);
      await timer.shutter(t, 'Start recording');
      await toggle(t);
      await t.pump(const Duration(seconds: 9));
      await h.flush(t);
      expect(
        find.textContaining('Camera cleanup could not be confirmed.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      camera.pausePending!.complete();
      await h.flush(t);
      expect(find.byKey(const ValueKey('recording-pause')), findsNothing);
      expect(camera.calls.where((v) => v == 'stop').length, 1);
      expect(camera.calls.where((v) => v == 'dispose').length, 1);
      expect(t.takeException(), isNull);
    },
  );

  for (final pending in [false, true]) {
    testWidgets(
      'background while paused or awaiting pause saves once without automatic resume $pending',
      (t) async {
        final camera = PausableCamera();
        if (pending) camera.pausePending = Completer<void>();
        await timer.mount(t, camera, video: true);
        await timer.shutter(t, 'Start recording');
        await toggle(t);
        h.background(t);
        await t.pump();
        if (pending) {
          expect(camera.calls, isNot(contains('stop')));
          camera.pausePending!.complete();
        }
        await h.flush(t);
        h.foreground(t);
        await h.flush(t);
        expect(find.text('Review capture'), findsOneWidget);
        expect(camera.calls.where((v) => v == 'stop').length, 1);
        expect(camera.calls.where((v) => v == 'dispose').length, 1);
        expect(camera.calls, isNot(contains('resume')));
        expect(camera.calls.where((v) => v == 'start').length, 1);
      },
    );
  }

  testWidgets(
    'late photo on a covered route cannot pop it or hand media to it',
    (t) async {
      final camera = PausableCamera()..photoPending = Completer<XFile>();
      CreatorMedia? result;
      await timer.mount(t, camera, result: (v) => result = v);
      await timer.shutter(t);
      final nav = t.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered fixture')),
        ),
      );
      await t.pump();
      camera.photoPending!.complete(
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fixture.png'),
      );
      await h.flush(t);
      expect(find.text('Covered fixture'), findsOneWidget);
      expect(result, isNull);
      nav.pop();
      await h.flush(t);
      await t.pumpAndSettle();
      expect(find.text('Review capture'), findsOneWidget);
      await t.ensureVisible(find.text('Review capture'));
      await t.tap(find.text('Review capture'));
      await h.flush(t);
      expect(result?.isVideo, isFalse);
    },
  );

  testWidgets(
    'retained review callback cannot return a clip through another route',
    (t) async {
      final camera = PausableCamera()..failPause = true;
      CreatorMedia? result;
      await timer.mount(t, camera, video: true, result: (v) => result = v);
      await timer.shutter(t, 'Start recording');
      await toggle(t);
      await h.flush(t);
      final retained = t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review capture'),
          )
          .onPressed!;
      final nav = t.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered fixture')),
        ),
      );
      await t.pump();
      retained();
      await h.flush(t);
      expect(find.text('Covered fixture'), findsOneWidget);
      expect(result, isNull);
      nav.pop();
      await h.flush(t);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Review capture'));
      await t.tap(find.text('Review capture'));
      await h.flush(t);
      expect(result?.isVideo, isTrue);
    },
  );

  testWidgets('devices without pause capability do not advertise it', (
    t,
  ) async {
    final camera = h.FakeCamera();
    await timer.mount(t, camera, video: true);
    await timer.shutter(t, 'Start recording');
    expect(find.byKey(const ValueKey('recording-pause')), findsNothing);
    await timer.shutter(t, 'Stop recording');
    await h.flush(t);
  });

  for (final lang in ['en', 'ne']) {
    for (final scale in [1.0, 1.8]) {
      for (final uncertain in [false, true]) {
        testWidgets(
          'pause controls and recovery stay readable $lang $scale uncertain=$uncertain',
          (t) async {
            final camera = PausableCamera();
            await timer.mount(t, camera, video: true, lang: lang, scale: scale);
            await timer.shutter(t, 'Start recording');
            await toggle(t);
            final pause = find.byKey(const ValueKey('recording-pause'));
            expect(pause.hitTestable(), findsOneWidget);
            expect(find.text(t_('Resume recording')), findsOneWidget);
            expect(
              t
                  .getRect(pause)
                  .overlaps(
                    t.getRect(find.bySemanticsLabel(t_('Stop recording'))),
                  ),
              isFalse,
            );
            await timer.capture(t, 'paused_${lang}_$scale');
            camera.failResume = true;
            camera.failRelease = uncertain;
            await toggle(t);
            await h.flush(t);
            await t.ensureVisible(find.text(t_('Review capture')));
            await t.pump();
            expect(
              find.text(t_('Review capture')).hitTestable(),
              findsOneWidget,
            );
            await timer.capture(
              t,
              '${uncertain ? 'pause_cleanup_warning' : 'pause_recovery'}_${lang}_$scale',
            );
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
}
