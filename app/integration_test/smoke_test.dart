// Runs the real app on an Android emulator in CI: starts it, waits for the first screen and
// saves a screenshot. It does not sign in and sends nothing to the API. It shows the app starts
// and draws on a real Android runtime. It says nothing about audio, calls, push or media playback.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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
        expect(value!['available'], isA<bool>());
        expect(value['flexibleAllowed'], isA<bool>());
        expect(value['installStatus'], isA<int>());
      } on PlatformException catch (error) {
        expect(error.code, 'PLAY_UNAVAILABLE');
      }
      // MissingPluginException and timeouts deliberately fail this gate.
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
