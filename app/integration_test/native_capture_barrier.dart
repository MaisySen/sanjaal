// Test-only OS screenshot boundary. A swallowed runAsync error must not let
// the journey change the UI before the host captures its named image.
Future<void> nativeCaptureBarrier({
  required String name,
  required Future<bool?> Function(Future<bool> Function()) runAsync,
  required Future<bool> Function() acknowledge,
}) async {
  final confirmed = await runAsync(acknowledge);
  if (confirmed != true) {
    throw StateError('Native display capture was not acknowledged: $name');
  }
}
