import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'apple_push_device.dart';

/// Not selected by Push yet. Native GoogleService-Info.plist, APNs credentials,
/// capabilities and signed-device acceptance are separate integration gates.
class FirebaseApplePushBridge implements ApplePushBridge {
  @override
  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError('Apple push requires native iOS');
    }
    // The iOS app's own native configuration is required. Never fall back to
    // Android identifiers when that configuration has not been installed.
    await Firebase.initializeApp();
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> apnsToken() => FirebaseMessaging.instance.getAPNSToken();

  @override
  Future<String?> fcmToken() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get refreshes => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();
}
