import 'dart:async';

import 'package:flutter/foundation.dart';

abstract class PushDevice {
  Future<bool> permission();
  Future<String?> token();
  Stream<String> get refreshes;
  Future<void> invalidate();
}

abstract class PushAccount {
  String? get owner;
  Future<void> registerToken(String token);
  Future<void> removeToken(String token);
}

/// One owner per device registration. Generation guards stop late permission,
/// token and network callbacks from attaching a signed-out account again.
/// Provider delivery remains a separate, unverified capability.
class PushRegistration {
  PushRegistration(this.device);
  final PushDevice device;
  final status = ValueNotifier<String>('Not set up yet');
  int _epoch = 0;
  PushAccount? _active;
  String? _owner, _token;
  StreamSubscription<String>? _refresh;
  Future<void> _tail = Future.value();
  bool _closed = false;
  bool _owns(int epoch, PushAccount account, String owner) =>
      !_closed &&
      epoch == _epoch &&
      identical(_active, account) &&
      account.owner == owner;
  Future<void> _serial(Future<void> Function() action) {
    final done = _tail.then((_) => action());
    _tail = done.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return done;
  }

  String? _deviceOwner;
  Future<void> register(PushAccount account) async {
    if (_closed || account.owner == null) return;
    final epoch = ++_epoch;
    final owner = account.owner!;
    _active = account;
    _owner = owner;
    final oldRefresh = _refresh;
    _refresh = null;
    await oldRefresh?.cancel();
    if (!_owns(epoch, account, owner)) return;
    status.value = 'Checking notification permission...';
    try {
      // A system permission prompt may remain open. It must not block logout.
      final allowed = await device.permission();
      if (!_owns(epoch, account, owner)) return;
      if (!allowed) {
        status.value = 'Off: allow notifications in system settings';
        return;
      }
      await _serial(() async {
        if (!_owns(epoch, account, owner)) return;
        // Never deliberately reuse another owner's token when invalidation failed.
        if (_deviceOwner != null && _deviceOwner != owner) {
          await device.invalidate().timeout(const Duration(seconds: 10));
          _deviceOwner = null;
        }
      });
      if (!_owns(epoch, account, owner)) return;
      final token = await device.token().timeout(const Duration(seconds: 20));
      if (!_owns(epoch, account, owner)) return;
      if (token == null) {
        status.value =
            'Off: no device token. Try again after reopening Sanjaal';
        return;
      }
      await _serial(() async {
        if (!_owns(epoch, account, owner)) return;
        _token = token;
        _deviceOwner = owner;
        await account.registerToken(token);
        if (!_owns(epoch, account, owner)) return;
        status.value = 'Device registered. Push delivery has not been verified';
        _refresh = device.refreshes.listen(
          (next) {
            if (!_owns(epoch, account, owner)) return;
            unawaited(
              _serial(() async {
                if (!_owns(epoch, account, owner)) return;
                _token = next;
                try {
                  await account.registerToken(next);
                  if (_owns(epoch, account, owner)) status.value = 'Device registered. Push delivery has not been verified';
                } catch (_) {
                  if (_owns(epoch, account, owner)) {
                    status.value =
                        'Notification registration needs another try';
                  }
                }
              }),
            );
          },
          onError: (_) {
            if (_owns(epoch, account, owner)) {
              status.value = 'Notification registration needs another try';
            }
          },
        );
      });
    } catch (_) {
      if (_owns(epoch, account, owner)) status.value = 'Not available on this device yet. Try again after reopening Sanjaal';
    }
  }

  Future<void> unregister(PushAccount account, {
    Future<void> Function(String)? removeForSignedOutAccount,
  }) {
    // A late sign-out for another Session must not remove the current binding.
    if (_closed || !identical(_active, account)) return Future.value();
    ++_epoch;
    final owner = _owner;
    _active = null;
    _owner = null;
    final oldRefresh = _refresh;
    _refresh = null;
    status.value = 'Signing out of notifications...';
    return _serial(() async {
      try { await oldRefresh?.cancel(); } catch (_) {}
      final token = _token;
      _token = null;
      if (token != null && (removeForSignedOutAccount != null || account.owner == owner)) {
        try {
          await (removeForSignedOutAccount ?? account.removeToken)(token).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      // Remove the local FCM token as well: server removal alone can fail offline.
      // A queued new owner registers only after this invalidation completes.
      var invalidated = false;
      try {
        await device.invalidate().timeout(const Duration(seconds: 10));
        invalidated = true;
        _deviceOwner = null;
      } catch (_) {}
      if (_active == null && !_closed) {
        status.value = invalidated
            ? 'Local notification token removed'
            : 'Signed out. Notification token cleanup could not be confirmed';
      }
    });
  }

  Future<void> dispose() async {
    _closed = true;
    ++_epoch;
    _active = null;
    await _refresh?.cancel();
    _refresh = null;
    await _tail;
    status.dispose();
  }
}
