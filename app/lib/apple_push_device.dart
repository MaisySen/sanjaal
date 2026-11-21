import 'dart:async';

import 'push_registration.dart';

/// Apple-specific provider boundary. A real bridge must initialize the iOS app's
/// own Firebase configuration, never the Android FirebaseOptions.
abstract class ApplePushBridge {
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<String?> apnsToken();
  Future<String?> fcmToken();
  Stream<String> get refreshes;
  Future<void> deleteToken();
}

/// Client adapter preparation, not APNs capability or delivery proof.
/// Deliberately not selected by Push until real native/provider setup is ready.
class ApplePushDevice implements PushDevice {
  ApplePushDevice(
    this.bridge, {
    this.apnsAttempts = 10,
    Future<void> Function()? wait,
  }) : _wait =
           wait ??
           (() => Future<void>.delayed(const Duration(milliseconds: 500))) {
    if (apnsAttempts < 1 || apnsAttempts > 20) {
      throw ArgumentError.value(apnsAttempts, 'apnsAttempts');
    }
  }

  final ApplePushBridge bridge;
  final int apnsAttempts;
  final Future<void> Function() _wait;
  Future<void>? _initializing;
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;

  Future<void> _ready() async {
    final current = _initializing ??= bridge.initialize();
    try {
      await current;
    } catch (_) {
      if (identical(_initializing, current)) _initializing = null;
      rethrow;
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<bool> permission() async {
    await _ready();
    return bridge.requestPermission();
  }

  @override
  Future<String?> token() async {
    final epoch = _epoch;
    await _ready();
    for (var attempt = 0; attempt < apnsAttempts; attempt++) {
      if (epoch != _epoch) return null;
      final apns = await bridge.apnsToken();
      if (epoch != _epoch) return null;
      if (apns != null && apns.trim().isNotEmpty) {
        return _serial(() async {
          if (epoch != _epoch) return null;
          final token = await bridge.fcmToken();
          return epoch == _epoch ? token : null;
        });
      }
      if (attempt + 1 < apnsAttempts) await _wait();
    }
    // No FCM request without an APNs token. No claim that a token proves delivery.
    return null;
  }

  @override
  Stream<String> get refreshes => bridge.refreshes;

  @override
  Future<void> invalidate() {
    ++_epoch;
    return _serial(() async {
      await _ready();
      await bridge.deleteToken();
    });
  }
}
