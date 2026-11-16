// Checks that the Story and Reel pickers ask the platform for the camera or the gallery as the user chose.
// A fake picker platform records the request; no device camera is involved.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/stories_page.dart';

class _Fake extends ImagePickerPlatform {
  final calls = <String>[];
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    calls.add('image ${source.name}');
    return null;
  }

  @override
  Future<XFile?> getVideo({required ImageSource source, CameraDevice preferredCameraDevice = CameraDevice.rear, Duration? maxDuration}) async {
    calls.add('video ${source.name} ${maxDuration?.inSeconds}');
    return null;
  }
}

void main() {
  final cases = {
    'Take a photo': 'image camera',
    'Choose a photo': 'image gallery',
    'Record a video': 'video camera 20',
    'Choose a video': 'video gallery 20',
  };
  for (final e in cases.entries) {
    testWidgets('story: ${e.key} asks for ${e.value}', (tester) async {
      final fake = _Fake();
      ImagePickerPlatform.instance = fake;
      final s = Session();
      Future<bool>? done;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => done = addStory(c, s), child: const Text('Start'))))));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(fake.calls, isEmpty, reason: 'nothing is requested before a choice');
      await tester.tap(find.text(e.key));
      await tester.pumpAndSettle();
      expect(await done, isFalse);
      expect(fake.calls, [e.value]);
    });
  }
}
