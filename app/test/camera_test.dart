// Story and Reel capture: the picker is asked for the camera or the gallery as chosen, cancelling uploads nothing,
// a refused permission explains itself and uploads nothing, and a returned file is uploaded exactly once.
// A fake picker platform stands in for the device; no real camera or permission prompt is involved.
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart' show ComposePage;
import 'package:sanjaal/stories_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Do { cancel, deny, give }

class _Fake extends ImagePickerPlatform {
  _Fake(this.mode);
  final _Do mode;
  final calls = <String>[];
  Future<XFile?> _answer(String name) async {
    if (mode == _Do.deny) throw PlatformException(code: 'camera_access_denied');
    if (mode == _Do.cancel) return null;
    return XFile.fromData(Uint8List.fromList([1, 2, 3, 4]), name: name, mimeType: name.endsWith('mp4') ? 'video/mp4' : 'image/jpeg');
  }

  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    calls.add('image ${source.name}');
    return _answer('shot.jpg');
  }

  @override
  Future<XFile?> getVideo({required ImageSource source, CameraDevice preferredCameraDevice = CameraDevice.rear, Duration? maxDuration}) async {
    calls.add('video ${source.name} ${maxDuration?.inSeconds}');
    return _answer('clip.mp4');
  }
}

Future<Session> _session(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
  final s = Session();
  await tester.runAsync(() => s.restore());
  return s;
}

http.Client _client(List<String> posts, List<String> bodies) => MockClient((r) async {
      final h = {'content-type': 'application/json'};
      if (r.url.path == '/oauth/token') return http.Response(jsonEncode({'access_token': 'x', 'expires_in': 3600, 'refresh_token': 'r'}), 200, headers: h);
      if (r.url.path.endsWith('/auth/me')) return http.Response(jsonEncode({'user': {'public_id': 'me', 'name': 'B', 'username': 'b'}}), 200, headers: h);
      if (r.method == 'POST') {
        posts.add(r.url.path);
        bodies.add(latin1.decode(r.bodyBytes));
      }
      return http.Response(jsonEncode({'story': {}, 'post': {'public_id': 'p9', 'kind': 'post', 'body': '', 'media': [], 'hashtags': [], 'author': {'public_id': 'me', 'name': 'B', 'username': 'b'}}}), 201, headers: h);
    });

void main() {
  final choices = {
    'Take a photo': 'image camera',
    'Choose a photo': 'image gallery',
    'Record a video': 'video camera 20',
    'Choose a video': 'video gallery 20',
  };
  for (final mode in _Do.values) {
    for (final e in choices.entries) {
      testWidgets('story ${mode.name}: ${e.key}', (tester) async {
        final fake = _Fake(mode);
        ImagePickerPlatform.instance = fake;
        final posts = <String>[];
        final bodies = <String>[];
        await http.runWithClient(() async {
          final s = await _session(tester);
          Future<bool>? done;
          await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => done = addStory(c, s), child: const Text('Start'))))));
          await tester.tap(find.text('Start'));
          await tester.pumpAndSettle();
          expect(fake.calls, isEmpty, reason: 'nothing is requested before a choice');
          await tester.tap(find.text(e.key));
          await tester.pump();
          late bool ok;
          await tester.runAsync(() async => ok = await done!);
          await tester.pump();
          expect(fake.calls, [e.value]);
          expect(ok, mode == _Do.give);
          expect(posts.where((p) => p.endsWith('/stories')).length, mode == _Do.give ? 1 : 0);
          if (mode == _Do.give) {
            final isVideo = e.key.contains('video');
            expect(bodies.single, contains(isVideo ? 'video/mp4' : 'image/jpeg'));
          }
          if (mode == _Do.deny) expect(find.textContaining('Camera access is off'), findsOneWidget);
          if (mode != _Do.deny) expect(find.textContaining('access is off'), findsNothing);
          await tester.pumpWidget(const SizedBox());
        }, () => _client(posts, bodies));
      });
    }
  }

  for (final mode in _Do.values) {
    for (final pick in ['Record a video', 'Choose a video']) {
      testWidgets('reel ${mode.name}: $pick', (tester) async {
        final fake = _Fake(mode);
        ImagePickerPlatform.instance = fake;
        final posts = <String>[];
        final bodies = <String>[];
        await http.runWithClient(() async {
          final s = await _session(tester);
          tester.view.physicalSize = const Size(1080, 2160);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(home: ComposePage(session: s)));
          await tester.pump();
          await tester.tap(find.text('Reel'));
          await tester.pumpAndSettle();
          expect(fake.calls, isEmpty);
          await tester.tap(find.text(pick));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pumpAndSettle();
          expect(fake.calls, [pick.startsWith('Record') ? 'video camera 60' : 'video gallery 60']);
          expect(find.text('Posts as a reel'), mode == _Do.give ? findsOneWidget : findsNothing);
          expect(posts, isEmpty, reason: 'picking alone uploads nothing');
          if (mode == _Do.deny) expect(find.textContaining('Camera access is off'), findsOneWidget);
          if (mode == _Do.give) {
            await tester.tap(find.widgetWithText(FilledButton, 'Post'));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
            await tester.pump();
            expect(posts.where((p) => p.endsWith('/posts')).length, 1);
            expect(bodies.last, contains('video/mp4'));
          }
          await tester.pumpWidget(const SizedBox());
        }, () => _client(posts, bodies));
      });
    }
  }
}
