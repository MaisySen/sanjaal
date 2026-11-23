import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Pinned LiveKit2.13.2 CallKit mode. Do not apply to ordinary foreground calls
/// until a native system-call owner exists; no automatic audio activation here.
class NativeCallAudioPolicy {
  static Future<void> prepare() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    // Native gate is applied by CallKit callbacks. Do not close an already active
    // didActivate window here: registration can happen before Dart starts.
    // ignore: experimental_member_use
    await lk.AudioManager.instance.setAudioSessionManagementMode(lk.AudioSessionManagementMode.externalCallSystem);
  }
}
