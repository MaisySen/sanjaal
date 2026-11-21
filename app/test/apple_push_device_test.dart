import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/apple_push_device.dart';

class Bridge implements ApplePushBridge {
  int initializations = 0, apnsReads = 0, fcmReads = 0, deletes = 0;
  bool allowed = true, failInitialization = false;
  String? apns = 'synthetic-apns';
  Completer<String?>? pendingApns, pendingFcm;
  final events = <String>[];
  @override
  Future<void> initialize() async {
    initializations++;
    if (failInitialization) throw StateError('synthetic setup failure');
  }

  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<String?> apnsToken() async {
    apnsReads++;
    return pendingApns?.future ?? apns;
  }

  @override
  Future<String?> fcmToken() async {
    events.add('fcm');
    fcmReads++;
    return pendingFcm?.future ?? 'synthetic-fcm';
  }

  @override
  Stream<String> get refreshes => const Stream<String>.empty();
  @override
  Future<void> deleteToken() async {
    events.add('delete');
    deletes++;
  }
}

void main() {
  test(
    'Apple initialization is shared and permission denial is preserved',
    () async {
      final bridge = Bridge()..allowed = false;
      final device = ApplePushDevice(bridge);
      expect(await device.permission(), isFalse);
      expect(await device.permission(), isFalse);
      expect(bridge.initializations, 1);
      expect(bridge.fcmReads, 0);
    },
  );
  test('APNs readiness is required before FCM registration', () async {
    final bridge = Bridge();
    final device = ApplePushDevice(bridge);
    expect(await device.token(), 'synthetic-fcm');
    expect(bridge.apnsReads, 1);
    expect(bridge.fcmReads, 1);
  });
  test('missing APNs is bounded and never calls FCM', () async {
    final bridge = Bridge()..apns = null;
    var waits = 0;
    final device = ApplePushDevice(
      bridge,
      apnsAttempts: 3,
      wait: () async {
        waits++;
      },
    );
    expect(await device.token(), isNull);
    expect(bridge.apnsReads, 3);
    expect(waits, 2);
    expect(bridge.fcmReads, 0);
  });
  test('logout during APNs wait cannot create a late FCM token', () async {
    final bridge = Bridge()..pendingApns = Completer<String?>();
    final device = ApplePushDevice(bridge);
    final token = device.token();
    await Future<void>.delayed(Duration.zero);
    await device.invalidate();
    bridge.pendingApns!.complete('late-synthetic-apns');
    expect(await token, isNull);
    expect(bridge.fcmReads, 0);
    expect(bridge.deletes, 1);
  });
  test(
    'logout during FCM serializes deletion before a later owner token',
    () async {
      final bridge = Bridge()..pendingFcm = Completer<String?>();
      final device = ApplePushDevice(bridge);
      final old = device.token();
      await Future<void>.delayed(Duration.zero);
      final removing = device.invalidate();
      final next = device.token();
      bridge.pendingFcm!.complete('synthetic-fcm');
      expect(await old, isNull);
      await removing;
      expect(await next, 'synthetic-fcm');
      expect(bridge.events, ['fcm', 'delete', 'fcm']);
    },
  );
  test('failed initialization can retry rather than caching failure', () async {
    final bridge = Bridge()..failInitialization = true;
    final device = ApplePushDevice(bridge);
    await expectLater(device.permission(), throwsStateError);
    bridge.failInitialization = false;
    expect(await device.permission(), isTrue);
    expect(bridge.initializations, 2);
  });
  test('invalid APNs polling budgets fail before provider effects', () {
    final bridge = Bridge();
    expect(() => ApplePushDevice(bridge, apnsAttempts: 0), throwsArgumentError);
    expect(
      () => ApplePushDevice(bridge, apnsAttempts: 21),
      throwsArgumentError,
    );
    expect(bridge.initializations, 0);
  });
}
