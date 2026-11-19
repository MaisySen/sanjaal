/// A late join response must not connect a room after its page has closed.
/// The caller owns native cleanup when setup returns false or throws.
Future<bool> connectRoomWhileActive({
  required bool Function() isActive,
  required Future<void> Function() requestToken,
  required Future<void> Function() connect,
  required Future<void> Function() prepareMicrophone,
}) async {
  if (!isActive()) return false;
  await requestToken();
  if (!isActive()) return false;
  await connect();
  if (!isActive()) return false;
  await prepareMicrophone();
  return isActive();
}

/// Stop capture immediately, then let an already-started native connect settle
/// before disposing the objects it still owns. Every cleanup step is attempted.
Future<void> releaseRoomAfterJoin({
  required Future<void> joining,
  required Future<void> Function() closeMicrophone,
  required Future<void> Function() disconnect,
  required void Function() disposeMicrophone,
  required Future<void> Function() disposeRoom,
}) async {
  Future<void> attempt(Future<void> Function() action) async {
    try { await action(); } catch (_) {}
  }
  await attempt(closeMicrophone);
  await attempt(disconnect);
  try { await joining; } catch (_) {}
  await attempt(disconnect);
  try { disposeMicrophone(); } finally { await attempt(disposeRoom); }
}

/// A failed permission/setup step must not leave an otherwise-connected room
/// capturing or listening behind the error screen. Disconnect even if native
/// microphone teardown itself fails.
Future<void> stopRoomAfterJoinFailure({
  required Future<void> Function() stopMicrophone,
  required Future<void> Function() disconnect,
}) async {
  try { await stopMicrophone(); } catch (_) {}
  try { await disconnect(); } catch (_) {}
}
