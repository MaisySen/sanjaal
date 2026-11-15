// Runs the real app on an Android emulator in CI: starts it, waits for the first screen and
// saves a screenshot. It does not sign in and sends nothing to the API. It shows the app starts
// and draws on a real Android runtime. It says nothing about audio, calls, push or media playback.
import 'package:flutter_test/flutter_test.dart';
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
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('first_screen');
    final seen = find.textContaining('Nepali').evaluate().isNotEmpty ||
        find.textContaining('Sanjaal').evaluate().isNotEmpty ||
        find.textContaining('Sign in').evaluate().isNotEmpty;
    expect(seen, isTrue);
  });
}
