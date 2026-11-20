/// Serial local call controls. A failed native acknowledgment does not prove
/// capture stayed unchanged. Latch the call closed to further media changes,
/// then try each stop independently. These callbacks cannot prove hardware off.
class CallMediaGuard {
  bool busy = false;
  bool failed = false;

  Future<bool> change({
    required bool Function() isActive,
    required Future<void> Function() apply,
    required void Function() onFailure,
    required Future<void> Function() stopMicrophone,
    required Future<void> Function() stopCamera,
    required Future<void> Function() disconnect,
  }) async {
    if (busy || failed || !isActive()) return false;
    busy = true;
    try {
      await apply();
      return isActive();
    } catch (_) {
      failed = true;
      // Latch before awaiting cleanup. Even a failed stop cannot unlock capture.
      try { onFailure(); } catch (_) {}
      for (final stop in [stopMicrophone, stopCamera, disconnect]) {
        try { await stop(); } catch (_) {}
      }
      rethrow;
    } finally {
      busy = false;
    }
  }
}
