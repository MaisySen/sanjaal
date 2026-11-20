// Runs the real app on an Android emulator in CI: starts it, waits for the first screen and
// saves a screenshot. It does not sign in and sends nothing to the API. It shows the app starts
// and draws on a real Android runtime. It says nothing about audio, calls, push or media playback.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/creator_draft_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanjaal/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts and shows onboarding or sign in', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    // Real native channel registration only. A sideloaded CI emulator is not
    // a Play-owned test device and must not claim that update download works.
    await tester.runAsync(() async {
      const channel = MethodChannel('au.fintex.sanjaal/updates');
      try {
        final value = await channel
            .invokeMapMethod<String, dynamic>('check')
            .timeout(const Duration(seconds: 30));
        expect(value, isNotNull);
        expect(value!['availability'], isA<int>());
        expect(value['available'], value['availability'] == 2);
        expect(value['available'], isA<bool>());
        expect(value['flexibleAllowed'], isA<bool>());
        expect(value['installStatus'], isA<int>());
      } on PlatformException catch (error) {
        expect(error.code, 'PLAY_UNAVAILABLE');
      }
      // MissingPluginException and timeouts deliberately fail this gate.
      // Real device storage plugin round trip with synthetic text only. This
      // is not process-death recovery, Samsung storage or media-draft proof.
      const drafts = CreatorDraftStore();
      final saved = await drafts
          .save('ci-synthetic-draft-owner', text: 'Native draft fixture')
          .timeout(const Duration(seconds: 20));
      try {
        expect(
          (await drafts.read('ci-synthetic-draft-owner'))
              .any((d) => d.id == saved.id && d.text == saved.text),
          isTrue,
        );
        expect(await drafts.read('ci-other-synthetic-owner'), isEmpty);
      } finally {
        await drafts.remove('ci-synthetic-draft-owner', saved.id, expectedRevision: saved.revision);
      }
    });
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('first_screen');
    final seen =
        find.textContaining('Nepali').evaluate().isNotEmpty ||
        find.textContaining('Sanjaal').evaluate().isNotEmpty ||
        find.textContaining('Sign in').evaluate().isNotEmpty;
    expect(seen, isTrue);
  });
}
