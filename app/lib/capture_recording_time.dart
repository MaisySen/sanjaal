/// Active recording time, preserving fractions across every pause. The caller
/// supplies a monotonic clock and confirms native pause/resume separately.
class CaptureRecordingTime {
  CaptureRecordingTime(this.now);
  final Duration Function() now;
  Duration _recorded = Duration.zero;
  Duration _last = Duration.zero;
  Duration? _started;

  Duration _read() {
    final value = now();
    if (value > _last) _last = value;
    return _last;
  }

  Duration get elapsed =>
      _recorded + (_started == null ? Duration.zero : _read() - _started!);
  bool get running => _started != null;

  void begin() {
    _recorded = Duration.zero;
    _started = _read();
  }

  void pause() {
    if (_started == null) return;
    _recorded = elapsed;
    _started = null;
  }

  void resume() {
    _started ??= _read();
  }
}
