// Real Android plugins against the throwaway CI emulator. No user account,
// network upload, live service, Samsung camera or microphone acceptance implied.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/capture_page.dart';
import 'package:sanjaal/media_library_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:video_player/video_player.dart';

Future<void> wait(
  WidgetTester t,
  bool Function() condition, {
  int tries = 80,
}) async {
  for (var i = 0; i < tries; i++) {
    if (condition()) return;
    await t.pump(const Duration(milliseconds: 250));
  }
  throw TestFailure(
    'Native media condition timed out. Visible text: ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList()}',
  );
}

Future<void> bridge(WidgetTester t, String action) async {
  final response = await t.runAsync(
    () => http
        .post(
          Uri.parse(
            '${const String.fromEnvironment('E2E_TOKEN_BASE')}/e2e/native-media',
          ),
          headers: {
            'Authorization':
                'Bearer ${const String.fromEnvironment('E2E_TOKEN')}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'action': action}),
        )
        .timeout(const Duration(seconds: 40)),
  );
  expect(
    response?.statusCode,
    200,
    reason: 'Native fixture preparation/focus must pass: ${response?.body}',
  );
  expect(jsonDecode(response!.body)['app_focused'], true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native camera photo video codec and authorized gallery return only local review files',
    (t) async {
      CreatorMedia? capture;
      List<CreatorMedia>? selection;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Builder(
            builder: (c) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      capture = await Navigator.of(c).push<CreatorMedia>(
                        MaterialPageRoute(builder: (_) => const CapturePage()),
                      );
                    },
                    child: const Text('Open actual camera'),
                  ),
                  TextButton(
                    onPressed: () async {
                      selection = await chooseCreatorMedia(
                        c,
                        CreatorKind.story,
                      );
                    },
                    child: const Text('Open actual gallery'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(seconds: 2));
      await bridge(t, 'prepare');
      await t.tap(find.text('Open actual camera'));
      await wait(
        t,
        () =>
            find.bySemanticsLabel('Take a photo').evaluate().isNotEmpty &&
            t
                    .widget<InkResponse>(
                      find.descendant(
                        of: find.bySemanticsLabel('Take a photo'),
                        matching: find.byType(InkResponse),
                      ),
                    )
                    .onTap !=
                null,
      );
      await bridge(t, 'camera');
      await t.tap(find.bySemanticsLabel('Take a photo'));
      await wait(t, () => capture != null);
      final image = await t.runAsync(() async {
        final bytes = await capture!.file.readAsBytes();
        expect(bytes.length, greaterThan(100));
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final dimensions = (frame.image.width, frame.image.height);
        frame.image.dispose();
        codec.dispose();
        return dimensions;
      });
      expect(image!.$1, greaterThan(0));
      expect(image.$2, greaterThan(0));
      // This is local file validity, never an upload or API publication assertion.
      expect(capture!.isVideo, false);
      capture = null;
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Open actual camera'));
      await wait(t, () => find.text('Video').evaluate().isNotEmpty);
      await t.tap(find.text('Video'));
      await wait(
        t,
        () =>
            find.bySemanticsLabel('Start recording').evaluate().isNotEmpty &&
            t
                    .widget<InkResponse>(
                      find.descendant(
                        of: find.bySemanticsLabel('Start recording'),
                        matching: find.byType(InkResponse),
                      ),
                    )
                    .onTap !=
                null,
      );
      await t.tap(find.bySemanticsLabel('Start recording'));
      await wait(
        t,
        () => find.bySemanticsLabel('Stop recording').evaluate().isNotEmpty,
      );
      await t.pump(const Duration(seconds: 3));
      await bridge(t, 'recording');
      await t.tap(find.bySemanticsLabel('Stop recording'));
      await wait(t, () => capture != null);
      expect(capture!.isVideo, true);
      expect(await t.runAsync(() => capture!.file.length()), greaterThan(100));
      final video = VideoPlayerController.file(File(capture!.file.path));
      await t.runAsync(
        () => video.initialize().timeout(const Duration(seconds: 30)),
      );
      expect(video.value.isInitialized, true);
      expect(video.value.duration.inMilliseconds, greaterThan(0));
      await video.dispose();
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Open actual gallery'));
      // The bridge seeded a known synthetic image in Android MediaStore. No fake
      // library adapter, thumbnail override or request bypass is used here.
      await wait(t, () => find.byType(Image).evaluate().isNotEmpty);
      await bridge(t, 'gallery');
      final thumbnail = find.byType(Image).first;
      await t.ensureVisible(thumbnail);
      await t.tap(thumbnail);
      await wait(t, () => selection != null);
      expect(selection!.length, 1);
      expect(selection!.single.isVideo, false);
      expect(
        await t.runAsync(() => selection!.single.file.length()),
        greaterThan(0),
      );
      // ignore: avoid_print
      print(
        'Native photo decode, video playback initialization and MediaStore gallery selection passed; no content posted.',
      );
    },
  );
}
