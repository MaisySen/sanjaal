import 'package:flutter/foundation.dart';

/// Local microphone consent. A verified host may offer the stage or revoke it,
/// but only a local button can enable capture. Native mutations are ordered.
class RoomMicrophone extends ChangeNotifier {
  RoomMicrophone(this.setEnabled, {this.onFailure});
  final void Function()? onFailure;
  final Future<void> Function(bool) setEnabled;
  bool speaker = false, muted = true, busy = false;
  bool stopUnconfirmed = false;
  bool _closed = false;
  bool _failed = false;
  int _epoch = 0;
  Future<void> _tail = Future.value();
  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  /// Sender identity must come from the SFU participant, never packet content.
  Future<bool> hostPacket({
    required String? sender,
    required String? host,
    required String? me,
    required Object? target,
    required Object? allow,
  }) async {
    if (_closed ||
        (_failed && allow == true) ||
        sender == null ||
        sender.isEmpty ||
        host == null ||
        host.isEmpty ||
        me == null ||
        me.isEmpty ||
        sender != host ||
        target != me ||
        allow is! bool ||
        sender == me)
      return false;
    if (allow) {
      if (!speaker) {
        speaker = true;
        muted = true;
        _changed();
      }
      // Duplicate host grants cannot unmute or replace a local mute choice.
    } else {
      await revoke();
    }
    return true;
  }

  /// Called only by explicit local Go live after API/SFU connect succeeds.
  Future<void> startHost() async {
    if (_closed || _failed) return;
    speaker = true;
    muted = true;
    await toggle();
  }

  Future<void> toggle() async {
    if (_closed || _failed || !speaker || busy || stopUnconfirmed) return;
    final epoch = _epoch;
    final enable = muted;
    busy = true;
    _changed();
    try {
      await _serial(() async {
        if (_closed || !speaker || epoch != _epoch) return;
        try {
          await setEnabled(enable);
          if (!_closed && speaker && epoch == _epoch) muted = !enable;
        } catch (_) {
          // A high-level off acknowledgment may skip a native stop if the
          // SDK already considers its track muted. Any toggle failure is
          // terminal even when cleanup returns. The page must disconnect.
          _failed = true;
          stopUnconfirmed = true;
          _changed();
          try { onFailure?.call(); } catch (_) {}
          try {
            await setEnabled(false);
            muted = true;
          } catch (_) {
            stopUnconfirmed = true;
          }
          rethrow;
        }
      });
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> revoke() async {
    if (_closed) return;
    ++_epoch;
    speaker = false;
    muted = true;
    _changed();
    // An in-flight enable settles before this disable, never after it.
    try {
      await _serial(() => setEnabled(false));
      if (!_failed) stopUnconfirmed = false;
    } catch (_) {
      _failed = true;
      stopUnconfirmed = true;
      _changed();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_epoch;
    speaker = false;
    muted = true;
    await _serial(() => setEnabled(false));
  }
}
