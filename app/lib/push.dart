import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';
import 'push_registration.dart';
import 'message_open_host.dart';

/// Public client identifiers. Project authorization, not hidden identifiers,
/// controls delivery. No provider key or sending credential ships in the app.
const _options = FirebaseOptions(
  apiKey: 'AIzaSyCZ4J0krSDecfTrA9cOjPuoHFTcIK9RlwY',
  appId: '1:746380796806:android:ae6a7c0d755a71e90c8207',
  messagingSenderId: '746380796806',
  projectId: 'sanjaal-app-3ede9',
);

class _FirebaseDevice implements PushDevice {
  Future<FirebaseApp>? _initializing;
  Future<void> _ready() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Native Android push only');
    }
    _initializing ??= Firebase.initializeApp(options: _options);
    try {
      await _initializing;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  @override
  Future<bool> permission() async {
    await _ready();
    final value = await FirebaseMessaging.instance.requestPermission();
    return value.authorizationStatus == AuthorizationStatus.authorized ||
        value.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    await _ready();
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Stream<String> get refreshes => FirebaseMessaging.instance.onTokenRefresh;
  @override
  Future<void> invalidate() async {
    await _ready();
    await FirebaseMessaging.instance.deleteToken();
  }
}

class _SessionPushAccount implements PushAccount {
  _SessionPushAccount(this.session);
  final Session session;
  @override
  String? get owner => session.user?['public_id']?.toString();
  @override
  Future<void> registerToken(String token) async {
    await session.call(
      'POST',
      '/devices',
      body: {'token': token, 'platform': 'android'},
    );
  }

  @override
  Future<void> removeToken(String token) async {
    await session.call('POST', '/devices/remove', body: {'token': token});
  }
}

class FirebaseMessageOpenSource implements MessageOpenSource {
  const FirebaseMessageOpenSource();
  @override bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override Stream<MessageOpenIntent> get opens => FirebaseMessaging.onMessageOpenedApp.map((message)=>MessageOpenIntent.fromData(message.data)).where((intent)=>intent!=null).cast<MessageOpenIntent>();
  @override Future<MessageOpenIntent?> initialOpen() async {
    if(!supported)return null;
    await Push._device._ready();
    final message=await FirebaseMessaging.instance.getInitialMessage();
    return message==null?null:MessageOpenIntent.fromData(message.data);
  }
}

class Push {
  static final _device = _FirebaseDevice();
  static final _registration = PushRegistration(_device);
  static final _accounts = Expando<_SessionPushAccount>();
  static _SessionPushAccount _account(Session session) =>
      _accounts[session] ??= _SessionPushAccount(session);
  static ValueNotifier<String> get status => _registration.status;
  static const iosUnavailable = 'Push notifications are not set up for iOS yet. Reopening the app will not enable them. Use Activity while Sanjaal is open.';
  static bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static Future<void> register(Session session) async {
    // No Android Firebase initialization, token registration, permission prompt
    // or suggestion that reopening can configure an absent APNs integration.
    if (_ios) {status.value=iosUnavailable;return;}
    await _registration.register(_account(session));
  }
  static Future<void> unregister(Session session) async {
    if (_ios) {status.value=iosUnavailable;return;}
    await _registration.unregister(_account(session), removeForSignedOutAccount: session.capturePushRemoval());
  }
}
