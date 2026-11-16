/// Runs connection steps only while the call screen still owns the operation.
/// A completed network/native step cannot be cancelled, so recheck ownership
/// after each await before opening the next media capability. The caller owns
/// disconnect/end cleanup when this returns false or throws.
Future<bool> connectCallWhileActive({
  required bool Function() isActive,
  required Future<void> Function() requestToken,
  required Future<void> Function() connect,
  required Future<void> Function() microphone,
  required Future<void> Function() camera,
  required bool video,
}) async {
  if (!isActive()) return false;
  await requestToken();
  if (!isActive()) return false;
  await connect();
  if (!isActive()) return false;
  await microphone();
  if (!isActive()) return false;
  if (video) {
    await camera();
    if (!isActive()) return false;
  }
  return true;
}
