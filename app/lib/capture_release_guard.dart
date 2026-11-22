/// If native cleanup is uncertain, another camera must not be opened in the
/// same process. Restarting the app creates a new guard and native session.
class CaptureReleaseGuard {
  bool _uncertain = false;
  bool get restartRequired => _uncertain;
  void markUncertain() => _uncertain = true;
  void ensureAvailable() {
    if (_uncertain) throw const CaptureRestartRequired();
  }
}

class CaptureRestartRequired implements Exception {
  const CaptureRestartRequired();
}
