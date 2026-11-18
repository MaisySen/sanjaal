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
import 'package:sanjaal/api.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/media_library_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:video_player/video_player.dart';
import 'package:sanjaal/video_poster.dart';

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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
      // A ready controller can precede its first camera frame. Allow real frames
      // before capture; the decoded photo below must contain varied pixels.
      await t.pump(const Duration(seconds: 2));
      await bridge(t, 'camera');
      await t.tap(find.bySemanticsLabel('Take a photo'));
      await wait(t, () => capture != null);
      final image = await t.runAsync(() async {
        final bytes = await capture!.file.readAsBytes();
        expect(bytes.length, greaterThan(100));
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final dimensions = (frame.image.width, frame.image.height);
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final colors = <int>{};
        final data = pixels!.buffer.asUint8List();
        for (
          var y = 0;
          y < frame.image.height;
          y += (frame.image.height ~/ 20).clamp(1, frame.image.height)
        ) {
          for (
            var x = 0;
            x < frame.image.width;
            x += (frame.image.width ~/ 20).clamp(1, frame.image.width)
          ) {
            final offset = (y * frame.image.width + x) * 4;
            colors.add(
              (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2],
            );
          }
        }
        expect(
          colors.length,
          greaterThan(4),
          reason:
              'The actual emulator capture must not be a blank first frame.',
        );
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
      final nativePoster = await t.runAsync(() => VideoPoster.fromPath(capture!.file.path));
      expect(nativePoster, isNotNull, reason: 'Actual local camera video must produce a native first-frame poster.');
      expect(nativePoster!.length, inInclusiveRange(1, 256 * 1024));
      await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(nativePoster);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, inInclusiveRange(1, 320));
        expect(frame.image.height, inInclusiveRange(1, 320));
        frame.image.dispose(); codec.dispose();
      });
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Open actual gallery'));
      // The bridge seeded a known synthetic image in Android MediaStore. No fake
      // library adapter, thumbnail override or request bypass is used here.
      await wait(t, () => find.byType(Image).evaluate().isNotEmpty);
      await t.tap(find.text('Photos'));
      await wait(
        t,
        () => t
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      await bridge(t, 'gallery');
      final thumbnail = find
          .ancestor(
            of: find.byWidgetPredicate((w) => w is RawImage && w.image != null),
            matching: find.byType(Image),
          )
          .first;
      await t.ensureVisible(thumbnail);
      await t.tap(thumbnail);
      await wait(t, () => selection != null);
      expect(selection!.length, 1);
      expect(selection!.single.isVideo, false);
      expect(
        selection!.single.file.name,
        'selected-photo.png',
        reason:
            'An empty IO filename causes PHP to discard the multipart file.',
      );
      expect(
        await t.runAsync(() => selection!.single.file.length()),
        greaterThan(0),
      );
      await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          await selection!.single.file.readAsBytes(),
        );
        final frame = await codec.getNextFrame();
        expect(
          (frame.image.width, frame.image.height),
          (160, 240),
          reason:
              'Select the known MediaStore fixture, not an unrelated asset.',
        );
        frame.image.dispose();
        codec.dispose();
      });
      // Same real selected file, production composer and authenticated HTTP to
      // the throwaway local API. This is never a live member or publication.
      SharedPreferences.setMockInitialValues({});
      final session = Session();
      await t.runAsync(() => session.login('fixture', 'local-fixture-only'));
      expect(session.protectedStoriesEnabled, true);
      expect(session.videoPostersEnabled, true);
      final posterPost = await t.runAsync(() async => session.createPost('',
        files: [UploadFile(await capture!.file.readAsBytes(), 'video/mp4', 'native-camera.mp4', poster: nativePoster)],
        reel: true, intent: newUploadIntent()));
      final posterUrl = (posterPost!['media'] as List).single['thumbnail_url'] as String;
      final posterRead = await t.runAsync(() => http.get(Uri.parse(posterUrl)));
      expect(posterRead!.statusCode, 200);
      expect(posterRead.headers['content-type'], contains('image/jpeg'));
      await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(posterRead.bodyBytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, inInclusiveRange(1, 320));
        expect(frame.image.height, inInclusiveRange(1, 320));
        frame.image.dispose(); codec.dispose();
      });
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: Scaffold(
        appBar: AppBar(title: const Text('Native camera poster')),
        body: Center(child: Image.memory(posterRead.bodyBytes, fit: BoxFit.contain)),
      )));
      await wait(t, () => t.widgetList<RawImage>(find.byType(RawImage)).any((image) => image.image != null));
      await t.pump(const Duration(milliseconds: 500));
      await bridge(t, 'poster'); // Full Android display, including system dialogs.
      await t.runAsync(() => session.call('DELETE', '/posts/${posterPost['public_id']}'));
      final removedPoster = await t.runAsync(() => http.get(Uri.parse(posterUrl)));
      expect(removedPoster!.statusCode, 404);

      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute(
                    builder: (_) => StoryComposePage(
                      session: session,
                      file: selection!.single.file,
                      isVideo: false,
                    ),
                  ),
                ),
                child: const Text('Review selected story'),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Review selected story'));
      await wait(t, () => find.text('Followers').evaluate().isNotEmpty);
      await t.tap(find.byTooltip('Who can see this story'));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Only me'));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Only me').hitTestable(), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      await t.pump();
      await binding.takeScreenshot('protected_story_composer_native');
      await t.tap(find.text('Share story'));
      await wait(
        t,
        () =>
            find.byType(StoryComposePage).evaluate().isEmpty &&
            find
                .text('Review selected story')
                .hitTestable()
                .evaluate()
                .isNotEmpty,
      );
      expect(find.byType(StoryComposePage), findsNothing);
      final listed =
          await t.runAsync(() => session.call('GET', '/stories')) as Map;
      final own = (listed['data'] as List).cast<Map>().singleWhere(
        (g) => (g['author'] as Map)['public_id'] == session.user!['public_id'],
      );
      final story = (own['items'] as List).cast<Map>().singleWhere(
        (s) => s['audience'] == 'only_me',
      );
      expect(story['protected_media'], true);
      final storyUrl = story['url'] as String;
      final denied = await t.runAsync(() => http.get(Uri.parse(storyUrl)));
      expect(denied!.statusCode, 401);
      const viewerToken = String.fromEnvironment('E2E_VIEWER_TOKEN');
      expect(viewerToken, isNotEmpty);
      final viewerHeaders = {
        'Authorization': 'Bearer $viewerToken',
        'Accept': 'application/json',
      };
      final viewerMe = await t.runAsync(
        () => http.get(Uri.parse('$apiBase/auth/me'), headers: viewerHeaders),
      );
      expect(viewerMe!.statusCode, 200);
      expect(
        (jsonDecode(viewerMe.body)['user'] as Map)['username'],
        'asha_e2e',
      );
      final privateDenied = await t.runAsync(
        () => http.get(Uri.parse(storyUrl), headers: viewerHeaders),
      );
      expect(
        privateDenied!.statusCode,
        404,
        reason: 'A valid second member must not read Only me bytes.',
      );
      final bytes = await t.runAsync(
        () => session.fetchProtectedBytes(storyUrl),
      );
      expect(bytes, isNotEmpty);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: StoryViewer(
            session: session,
            group: {
              'author': own['author'],
              'items': [Map<String, dynamic>.from(story)],
            },
          ),
        ),
      );
      await wait(
        t,
        () => t
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      await t.pump(const Duration(milliseconds: 500));
      await bridge(t, 'story'); // System-level capture must show the actual story.
      await binding.takeScreenshot('protected_story_viewer_native');
      await t.pumpWidget(const SizedBox());
      await t.runAsync(
        () => session.call('DELETE', '/stories/${story['public_id']}'),
      );
      final gone = await t.runAsync(
        () => http.get(Uri.parse(storyUrl), headers: session.mediaHeadersFor(storyUrl)),
      );
      expect(gone!.statusCode, 404);
      // A second synthetic member goes from no access to allowed, then loses
      // access again, including Range/ETag and viewed-state writes. All HTTP is
      // to the throwaway runner API, never a live member or live publication.
      await t.runAsync(
        () => session.call(
          'PUT',
          '/auth/me/story-audience/asha_e2e',
          body: {'revision': 0, 'close_friend': true, 'hide_story': false},
        ),
      );
      final close = await t.runAsync(
        () => session.upload(
          '/stories',
          fields: {'protected_media': '1', 'audience': 'close_friends'},
          file: UploadFile(bytes!, 'image/png', 'selected-photo.png'),
        ),
      );
      final shared = close!['story'] as Map;
      final sharedUrl = shared['url'] as String;
      final allowed = await t.runAsync(
        () => http.get(Uri.parse(sharedUrl), headers: viewerHeaders),
      );
      expect(allowed!.statusCode, 200);
      expect(allowed.headers['cache-control'], contains('no-store'));
      final etag = allowed.headers['etag'];
      expect(etag, isNotNull);
      await t.runAsync(
        () => session.call(
          'PUT',
          '/auth/me/story-audience/asha_e2e',
          body: {'revision': 1, 'close_friend': true, 'hide_story': true},
        ),
      );
      for (final extra in <Map<String, String>>[
        {},
        {'Range': 'bytes=0-15'},
        {'If-None-Match': etag!},
      ]) {
        final revoked = await t.runAsync(
          () => http.get(
            Uri.parse(sharedUrl),
            headers: {...viewerHeaders, ...extra},
          ),
        );
        expect(
          revoked!.statusCode,
          404,
          reason:
              'Hide-story revocation precedes any private byte/cache response.',
        );
      }
      final viewDenied = await t.runAsync(
        () => http.post(
          Uri.parse('$apiBase/stories/${shared['public_id']}/view'),
          headers: viewerHeaders,
        ),
      );
      expect(viewDenied!.statusCode, 404);
      final hiddenList = await t.runAsync(
        () => http.get(Uri.parse('$apiBase/stories'), headers: viewerHeaders),
      );
      expect(hiddenList!.statusCode, 200);
      expect(
        (jsonDecode(hiddenList.body)['data'] as List).where(
          (g) =>
              (g['author'] as Map)['public_id'] == session.user!['public_id'],
        ),
        isEmpty,
      );
      await t.runAsync(
        () => session.call('DELETE', '/stories/${shared['public_id']}'),
      );
      await t.runAsync(
        () => session.call(
          'PUT',
          '/auth/me/story-audience/asha_e2e',
          body: {'revision': 2, 'close_friend': false, 'hide_story': false},
        ),
      );
      session.dispose();
      // ignore: avoid_print
      print(
        'Native photo decode, video playback initialization, first-frame poster upload/read/delete, MediaStore selection and protected-story composer/read/delete passed against the throwaway local API. No live content posted.',
      );
    },
  );
}
