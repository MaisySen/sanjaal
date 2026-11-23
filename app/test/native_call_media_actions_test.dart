import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/call_controller.dart';
import 'package:sanjaal/native_call_coordinator.dart';
import 'package:sanjaal/native_call_media_actions.dart';
import 'call_continuity_fakes.dart';
import 'native_call_coordinator_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final event = NativeCallEvent.parse(fixture.event('answer'), owner:fixture.owner, lease:'lease-a', now:fixture.now)!;
  test('native video answer uses shared controller with camera off; later explicit camera remains possible', () async {
    final session = CallFixtureSession()..user={'public_id':fixture.owner};
    final media = FakeCallConnection();
    late CallController call;
    final actions = NativeCallMediaActions(reserve:(e) => call=CallController(session:session,
      conversationId:e.conversation,title:'Member',video:e.video,callId:e.call,startCamera:false,connection:media),
      release:(c) async { await c.close(endRemote:false); c.dispose(); }, show:(e,r) async {});
    expect(await actions.connect(event,cameraEnabled:false),true);
    expect(media.events, ['connect','microphone:true']);
    expect(call.camOn,false);
    await call.changeMedia(camera:true);
    expect(media.events.last,'camera:true');
    await actions.stop(event);
    expect(await actions.connect(event,cameraEnabled:false),false);
  });
  test('busy host cannot start another media owner', () async {
    final actions=NativeCallMediaActions(reserve:(_)=>null,release:(_) async {},show:(e,r) async {});
    expect(await actions.connect(event,cameraEnabled:false),false);
    expect(await actions.connect(event,cameraEnabled:true),false);
  });
  test('unconfirmed native handoff releases connected capture', () async {
    const channel=MethodChannel('synthetic-media');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(_) async=>false);
    final session=CallFixtureSession()..user={'public_id':fixture.owner}; final media=FakeCallConnection();
    var releases=0;
    final actions=NativeCallMediaActions(channel:channel,reserve:(e)=>CallController(session:session,
      conversationId:e.conversation,title:'Member',video:true,callId:e.call,startCamera:false,connection:media),
      release:(c) async { releases++; await c.close(endRemote:false); c.dispose(); },show:(e,r) async {});
    expect(await actions.connect(event,cameraEnabled:false),true);
    await expectLater(actions.complete(event,connected:true),throwsStateError);
    expect(releases,1); expect(media.events,contains('stopCapture'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
  });
}
