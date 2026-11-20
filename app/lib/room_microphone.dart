import 'package:flutter/foundation.dart';

/// Local microphone consent. A verified host may offer the stage or revoke it,
/// but only a local button can enable capture. Native mutations are ordered.
class RoomMicrophone extends ChangeNotifier {
  RoomMicrophone(this.setEnabled);
  final Future<void> Function(bool) setEnabled;
  bool speaker = false, muted = true, busy = false;
  bool stopUnconfirmed = false;
  bool _closed = false;
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
    if (_closed) return;
    speaker = true;
    muted = true;
    await toggle();
  }

  Future<void> toggle() async {
    if (_closed || !speaker || busy || stopUnconfirmed) return;
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
          // Native failures can arrive after capture has already changed.
          // Reconcile to off before allowing another local enable. Keep this
          // stop inside the same queue slot, ahead of any revoke/close.
          try {
            await setEnabled(false);
            muted = true;
            stopUnconfirmed = false;
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
      stopUnconfirmed = false;
    } catch (_) {
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
