import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';

/// Firebase client identifiers. These are public by design (they ship in every app). Access is
/// controlled by the project, not by hiding them.
const _options = FirebaseOptions(
  apiKey: 'AIzaSyCZ4J0krSDecfTrA9cOjPuoHFTcIK9RlwY',
  appId: '1:746380796806:android:ae6a7c0d755a71e90c8207',
  messagingSenderId: '746380796806',
  projectId: 'sanjaal-app-3ede9',
);

/// Registers this device for push. Every failure is swallowed: push is an extra, the app works without it.
class Push {
  /// Shown in Settings so people know whether push is really on. Never holds tokens.
  static final status = ValueNotifier<String>('Not set up yet');
  static bool _ready = false;
  static String? _token;
  static StreamSubscription<String>? _refreshSub;

  static Future<void> register(Session s) async {
    try {
      if (!_ready) {
        await Firebase.initializeApp(options: _options);
        _ready = true;
      }
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        status.value = 'Off: allow notifications in system settings';
        return;
      }
      final t = await m.getToken();
      if (t == null) {
        status.value = 'Off: no device token. Will retry next time you open the app';
        return;
      }
      _token = t;
      await s.call('POST', '/devices', body: {'token': t, 'platform': 'android'});
      status.value = 'Registered. Delivery starts once the server side is switched on';
      _refreshSub ??= m.onTokenRefresh.listen((n) {
        _token = n;
        unawaited(s.call('POST', '/devices', body: {'token': n, 'platform': 'android'}).then((_) {}, onError: (_) {}));
      });
    } catch (e) {
      status.value = 'Off: could not register (${e.runtimeType}). Will retry next time you open the app';
    }
  }

  static Future<void> unregister(Session s) async {
    final t = _token;
    if (t == null) return;
    try {
      await s.call('POST', '/devices/remove', body: {'token': t});
    } catch (_) {}
    _token = null;
  }
}
