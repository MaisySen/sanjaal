import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/native_call_audio_policy.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>debugDefaultTargetPlatformOverride=TargetPlatform.android);
  tearDown(()=>debugDefaultTargetPlatformOverride=null);
  test('Android Telecom ownership is acknowledged before manual SDK mode, release does not restart SDK',() async {
    final calls=<MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('livekit_client'),(call) async { calls.add(call); return true; });
    await NativeCallAudioPolicy.prepare();
    // ignore: experimental_member_use
    expect(lk.AudioManager.instance.managementMode,lk.AudioSessionManagementMode.manual);
    await NativeCallAudioPolicy.release();
    expect(calls.map((c)=>c.method),['sanjaalExternalTelecomAudio','sanjaalExternalTelecomAudio']);
    expect((calls.first.arguments as Map)['owned'],true);
    expect((calls.last.arguments as Map)['owned'],false);
  });
  test('native ownership failure propagates instead of opening media',() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('livekit_client'),(_) async { throw PlatformException(code:'native-stop'); });
    await expectLater(NativeCallAudioPolicy.prepare(),throwsA(isA<PlatformException>()));
  });
}
