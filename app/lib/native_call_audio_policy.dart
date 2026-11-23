import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Pinned LiveKit2.13.2 CallKit mode. Do not apply to ordinary foreground calls
/// until a native system-call owner exists; no automatic audio activation here.
class NativeCallAudioPolicy {
  static Future<void> prepare() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final stopped = await const MethodChannel('livekit_client').invokeMethod<bool>(
        'sanjaalExternalTelecomAudio', {'owned':true});
      if (stopped != true) throw StateError('Native audio release was not confirmed');
      // ignore: experimental_member_use
      await lk.AudioManager.instance.setAudioSessionManagementMode(lk.AudioSessionManagementMode.manual);
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    // Native gate is applied by CallKit callbacks. Do not close an already active
    // didActivate window here: registration can happen before Dart starts.
    // ignore: experimental_member_use
    await lk.AudioManager.instance.setAudioSessionManagementMode(lk.AudioSessionManagementMode.externalCallSystem);
  }
  static Future<void> release() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final released = await const MethodChannel('livekit_client').invokeMethod<bool>(
      'sanjaalExternalTelecomAudio', {'owned':false});
    if (released != true) throw StateError('Native audio ownership release failed');
    // Do not re-activate SDK audio here. The next ordinary connect owns that.
    // ignore: experimental_member_use
    await lk.AudioManager.instance.setAudioSessionManagementMode(lk.AudioSessionManagementMode.externalCallSystem);
  }
}
