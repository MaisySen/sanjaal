// Synthetic device/library futures and actual routes only. No native picker/camera.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/chat_pages.dart';

import 'profile_journey_test.dart' as pf;

import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    as picker;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/capture_page.dart';
import 'package:sanjaal/media_library_page.dart';
import 'package:sanjaal/ui.dart';

import 'capture_library_test.dart' as p;

class HeldPicker extends picker.ImagePickerPlatform {
  var calls = 0;
  final result = Completer<picker.XFile?>();
  @override
  Future<picker.XFile?> getVideo({
    required picker.ImageSource source,
    picker.CameraDevice preferredCameraDevice = picker.CameraDevice.rear,
    Duration? maxDuration,
  }) {
    calls++;
    return result.future;
  }

  @override
  Future<picker.XFile?> getImageFromSource({
    required picker.ImageSource source,
    picker.ImagePickerOptions options = const picker.ImagePickerOptions(),
  }) {
    calls++;
    return result.future;
  }
}

class HeldLength extends picker.XFile {
  HeldLength() : super('fixture.png');
  final result = Completer<int>();
  var reads = 0;
  @override
  Future<int> length() {
    reads++;
    return result.future;
  }
}

void cover(NavigatorState nav) => nav.push(
  MaterialPageRoute<void>(
    builder: (_) => const Scaffold(body: Text('Media cover')),
  ),
);

void main() {
  guardCases();
  ownershipExtras();
  consumerCases();
  setUpAll(() async {
    Directory('test/renders').createSync(recursive: true);
    for (final f in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      await (FontLoader(f.$1)..addFont(
            Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())),
          ))
          .load();
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFF224466), BlendMode.src);
    final image = await recorder.endRecording().toImage(40, 40);
    p.imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
  });
  for (final action in ['camera', 'picker', 'asset']) {
    for (final retired in ['covered', 'disposed']) {
      testWidgets('retained library $action entry is refused when $retired', (
        t,
      ) async {
        final old = picker.ImagePickerPlatform.instance, fake = HeldPicker();
        picker.ImagePickerPlatform.instance = fake;
        addTearDown(() => picker.ImagePickerPlatform.instance = old);
        final library = p.FakeLibrary();
        var cameras = 0;
        await p.start(
          t,
          MediaLibraryPage(
            kind: CreatorKind.reel,
            library: library,
            captureBuilder: (_, _) {
              cameras++;
              return const Scaffold(body: Text('Fixture camera'));
            },
          ),
        );
        final dynamic state = t.state(find.byType(MediaLibraryPage));
        final nav = Navigator.of(t.element(find.byType(MediaLibraryPage)));
        if (retired == 'covered') {
          cover(nav);
          await t.pumpAndSettle();
        } else {
          nav.pop();
          await t.pumpAndSettle();
        }
        Object? failure;
        final task =
            Future<void>.sync(() {
              if (action == 'camera') return state.capture();
              if (action == 'picker') return state.fallback();
              return state.choose(const LibraryAsset('a1', video: false));
            }).catchError((Object e) {
              failure = e;
            });
        await p.flush(t);
        if (cameras > 0) {
          nav.pop();
          await p.flush(t);
        }
        if (fake.calls > 0) fake.result.complete(null);
        await task;
        await p.flush(t);
        expect(failure, isNull);
        expect(fake.calls, 0);
        expect(cameras, 0);
        expect(library.fileReads, 0);
        expect(t.takeException(), isNull);
        if (retired == 'covered') {
          expect(find.text('Media cover'), findsOneWidget);
        }
      });
    }
  }
  for (final stage in ['picker', 'file', 'length', 'camera']) {
    testWidgets(
      'library $stage completion preserves a later cover and never auto returns',
      (t) async {
        final old = picker.ImagePickerPlatform.instance, fake = HeldPicker();
        picker.ImagePickerPlatform.instance = fake;
        addTearDown(() => picker.ImagePickerPlatform.instance = old);
        final library = p.FakeLibrary(), length = HeldLength();
        if (stage == 'file') library.delayedFile = Completer<picker.XFile?>();
        if (stage == 'length') {
          library.delayedFile = Completer<picker.XFile?>()..complete(length);
        }
        Route<dynamic>? camera;
        var returns = 0;
        await p.start(
          t,
          MediaLibraryPage(
            kind: CreatorKind.reel,
            library: library,
            captureBuilder: (_, _) => Builder(
              builder: (c) {
                camera = ModalRoute.of(c);
                return const Scaffold(body: Text('Fixture camera'));
              },
            ),
          ),
          result: (_) => returns++,
        );
        final nav = Navigator.of(t.element(find.byType(MediaLibraryPage)));
        if (stage == 'picker') {
          await t.tap(find.text('Device picker').first);
        } else if (stage == 'camera') {
          await t.tap(find.text('Camera').first);
        } else {
          await t.tap(find.byKey(const ValueKey('a1')));
        }
        await p.flush(t);
        if (stage == 'length') expect(length.reads, 1);
        cover(nav);
        await t.pumpAndSettle();
        if (stage == 'picker') {
          fake.result.complete(
            picker.XFile.fromData(p.imageBytes, name: 'fixture.png'),
          );
        } else if (stage == 'file') {
          library.delayedFile!.complete(
            picker.XFile.fromData(p.imageBytes, name: 'fixture.png'),
          );
        } else if (stage == 'length') {
          length.result.complete(p.imageBytes.length);
        } else {
          nav.removeRoute(
            camera!,
            CreatorMedia(
              picker.XFile.fromData(p.imageBytes, name: 'fixture.png'),
              isVideo: false,
            ),
          );
        }
        await p.flush(t);
        await t.pumpAndSettle();
        expect(find.text('Media cover'), findsOneWidget);
        expect(returns, 0);
        expect(t.takeException(), isNull);
        nav.pop();
        await t.pumpAndSettle();
        expect(find.byType(MediaLibraryPage), findsOneWidget);
        expect(returns, 0);
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Device picker'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );
  }
  for (final mode in ['covered choice', 'duplicate choice']) {
    testWidgets('story fallback $mode cannot dismiss another route', (t) async {
      final old = picker.ImagePickerPlatform.instance, fake = HeldPicker();
      picker.ImagePickerPlatform.instance = fake;
      addTearDown(() => picker.ImagePickerPlatform.instance = old);
      await p.start(
        t,
        MediaLibraryPage(kind: CreatorKind.story, library: p.FakeLibrary()),
      );
      final nav = Navigator.of(t.element(find.byType(MediaLibraryPage)));
      await t.tap(find.text('Device picker').first);
      await p.flush(t);
      final choice = t
          .widget<ListTile>(find.widgetWithText(ListTile, 'Choose a photo'))
          .onTap!;
      if (mode == 'covered choice') {
        cover(nav);
        await t.pumpAndSettle();
        choice();
        await p.flush(t);
        await t.pumpAndSettle();
        expect(find.text('Media cover'), findsOneWidget);
        expect(fake.calls, 0);
        nav.pop();
        await t.pumpAndSettle();
      } else {
        choice();
        choice();
        await p.flush(t);
        await t.pumpAndSettle();
        expect(find.byType(MediaLibraryPage), findsOneWidget);
        expect(fake.calls, 1);
        fake.result.complete(null);
        await p.flush(t);
      }
      expect(t.takeException(), isNull);
    });
  }
}

void guardCases() {
  for (final retirement in ['covered', 'disposed']) {
    for (final event in ['result', 'permission', 'failure']) {
      testWidgets(
        'shared picker ignores $event after its route is $retirement',
        (t) async {
          final pending = Completer<String?>();
          late BuildContext owner;
          Object? value, failure;
          var calls = 0;
          await t.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (c) {
                  owner = c;
                  return Scaffold(
                    body: TextButton(
                      onPressed: () async {
                        try {
                          value = await guardPick(c, () {
                            calls++;
                            return pending.future;
                          });
                        } catch (e) {
                          failure = e;
                        }
                      },
                      child: const Text('Pick fixture'),
                    ),
                  );
                },
              ),
            ),
          );
          await t.tap(find.text('Pick fixture'));
          await t.pump();
          final nav = Navigator.of(owner);
          if (retirement == 'covered') {
            cover(nav);
            await t.pumpAndSettle();
          } else {
            await t.pumpWidget(const SizedBox());
          }
          if (event == 'result') {
            pending.complete('private fixture');
          } else if (event == 'permission') {
            pending.completeError(
              PlatformException(code: 'camera_access_denied'),
            );
          } else {
            pending.completeError(StateError('fixture failure'));
          }
          await p.flush(t);
          expect(calls, 1);
          expect(value, isNull);
          expect(failure, isNull);
          expect(find.textContaining('Camera access is off'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final retirement in ['covered', 'disposed']) {
    testWidgets('shared picker refuses a retained $retirement start', (
      t,
    ) async {
      late BuildContext owner;
      var calls = 0;
      Object? value, failure;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              owner = c;
              return const Scaffold(body: Text('Fixture owner'));
            },
          ),
        ),
      );
      if (retirement == 'covered') {
        cover(Navigator.of(owner));
        await t.pumpAndSettle();
      } else {
        await t.pumpWidget(const SizedBox());
      }
      try {
        value = await guardPick(owner, () async {
          calls++;
          return 'private fixture';
        });
      } catch (e) {
        failure = e;
      }
      expect(calls, 0);
      expect(value, isNull);
      expect(failure, isNull);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'current shared picker preserves selection and permission explanation',
    (t) async {
      late BuildContext owner;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              owner = c;
              return const Scaffold();
            },
          ),
        ),
      );
      expect(
        await guardPick(owner, () async => 'current fixture'),
        'current fixture',
      );
      expect(
        await guardPick<String>(
          owner,
          () async => throw PlatformException(code: 'photo_access_denied'),
        ),
        isNull,
      );
      await p.flush(t);
      expect(find.textContaining('Photo access is off'), findsOneWidget);
      await expectLater(
        guardPick<String>(
          owner,
          () async => throw StateError('fixture failure'),
        ),
        throwsStateError,
      );
    },
  );
}

void ownershipExtras() {
  for (final beforeBuild in [false, true]) {
    testWidgets(
      'library retirement removes its exact story choice before build $beforeBuild',
      (t) async {
        await p.start(
          t,
          MediaLibraryPage(kind: CreatorKind.story, library: p.FakeLibrary()),
        );
        final context = t.element(find.byType(MediaLibraryPage));
        final owner = ModalRoute.of(context)!, nav = Navigator.of(context);
        final dynamic state = t.state(find.byType(MediaLibraryPage));
        var finished = false;
        unawaited(
          (state.fallback() as Future<void>).whenComplete(
            () => finished = true,
          ),
        );
        if (!beforeBuild) {
          await p.flush(t);
          cover(nav);
          await t.pumpAndSettle();
        }
        nav.removeRoute(owner);
        await p.flush(t);
        await t.pumpAndSettle();
        expect(
          find.widgetWithText(ListTile, 'Choose a photo', skipOffstage: false),
          findsNothing,
        );
        expect(finished, isTrue);
        expect(t.takeException(), isNull);
        if (!beforeBuild) expect(find.text('Media cover'), findsOneWidget);
      },
    );
  }
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'current device picker denial stays readable and retryable $lang',
      (t) async {
        final old = picker.ImagePickerPlatform.instance, fake = HeldPicker();
        picker.ImagePickerPlatform.instance = fake;
        addTearDown(() => picker.ImagePickerPlatform.instance = old);
        await p.start(
          t,
          MediaLibraryPage(
            kind: CreatorKind.reel,
            library: p.FakeLibrary()..access = LibraryAccess.denied,
          ),
          language: lang,
          scale: 1.8,
        );
        await t.tap(find.text(t_('Device picker')).first);
        await p.flush(t);
        fake.result.completeError(
          PlatformException(code: 'photo_access_denied'),
        );
        await p.flush(t);
        expect(
          find.text(
            t_(
              'Photo access is off. Turn it on in Settings to choose photos or videos.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, t_('Device picker')),
              )
              .onPressed,
          isNotNull,
        );
        expect(find.byType(MediaLibraryPage), findsOneWidget);
        expect(t.takeException(), isNull);
        if (Platform.environment['MEDIA_ROUTE_CAPTURE'] == '1') {
          for (var i = 0; i < 4; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await t.pump(const Duration(milliseconds: 16));
          }
          await p.shot(t, 'media_route_permission_$lang');
        }
      },
    );
  }
}

void consumerCases() {
  for (final screen in ['profile', 'chat']) {
    for (final outcome in ['selection', 'permission']) {
      testWidgets(
        '$screen shared picker $outcome under a cover never uploads or announces to that cover',
        (t) async {
          final old = picker.ImagePickerPlatform.instance, fake = HeldPicker();
          picker.ImagePickerPlatform.instance = fake;
          addTearDown(() => picker.ImagePickerPlatform.instance = old);
          var writes = 0;
          await pf.fixture(
            t,
            (s) => screen == 'profile'
                ? EditProfilePage(session: s)
                : ChatPage(
                    session: s,
                    convo: {
                      'public_id': 'fixture-chat',
                      'type': 'direct',
                      'title': 'Fixture chat',
                    },
                  ),
            () async {
              final label = screen == 'profile'
                  ? 'Change photo'
                  : 'Attach photo';
              await t.tap(find.byTooltip(label));
              await pf.flush(t);
              expect(fake.calls, 1);
              final nav = Navigator.of(
                t.element(
                  find.byType(screen == 'profile' ? EditProfilePage : ChatPage),
                ),
              );
              cover(nav);
              await t.pumpAndSettle();
              if (outcome == 'selection') {
                fake.result.complete(
                  picker.XFile.fromData(p.imageBytes, name: 'fixture.png'),
                );
              } else {
                fake.result.completeError(
                  PlatformException(code: 'photo_access_denied'),
                );
              }
              await pf.flush(t);
              await t.pumpAndSettle();
              expect(find.text('Media cover'), findsOneWidget);
              expect(writes, 0);
              expect(find.byType(SnackBar), findsNothing);
              expect(t.takeException(), isNull);
            },
            respond: (http.Request r) async {
              if (r.url.path.endsWith('/read')) return pf.json({});
              if (r.method == 'GET') {
                return pf.json({'data': [], 'next_cursor': null});
              }
              writes++;
              return pf.json({
                'user': {
                  'public_id': 'me',
                  'username': 'fixture',
                  'name': 'Fixture Name',
                  'bio': 'Original bio',
                },
                'message': {
                  'public_id': 'fixture-message',
                  'conversation_id': 'fixture-chat',
                  'sender': {'public_id': 'me', 'username': 'fixture'},
                  'kind': 'image',
                  'seq': 1,
                },
              });
            },
          );
        },
      );
    }
  }
}
