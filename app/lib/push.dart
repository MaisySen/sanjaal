import 'dart:async';
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
      await m.requestPermission();
      final t = await m.getToken();
      if (t == null) return;
      _token = t;
      await s.call('POST', '/devices', body: {'token': t, 'platform': 'android'});
      _refreshSub ??= m.onTokenRefresh.listen((n) {
        _token = n;
        unawaited(s.call('POST', '/devices', body: {'token': n, 'platform': 'android'}).then((_) {}, onError: (_) {}));
      });
    } catch (_) {}
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
