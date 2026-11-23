import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/native_call_registration.dart';
import 'native_call_event_pump_test.dart' show PumpSession;
import 'native_call_coordinator_test.dart' as fixture;
class Device implements NativeCallDevice {
  Map<String,String>? value={'transport':'fcm','token':'synthetic-fcm-token'};
  Completer<Map<String,String>?>? wait;
  int reads=0;
  @override Future<Map<String,String>?> binding() async { reads++; return wait?.future ?? value; }
}
class RemovalSession extends PumpSession {
  final removals=<Map<String,dynamic>>[];
  @override Future<void> Function(Map<String,dynamic>) captureCallDeviceRemoval() => (binding) async { removals.add(binding); };
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('platform readiness false never enrolls token possession alone',() async {
    const channel=MethodChannel('synthetic-registration');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(_) async =>
      {'registered':false,'transport':'apns_voip','token':'synthetic-token'});
    expect(await ChannelNativeCallDevice(channel:channel).binding(),isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
  });
  test('unregister uses captured enrollment binding once and blocks future registration',() async {
    final session=RemovalSession()..user={'public_id':fixture.owner};
    final registration=NativeCallRegistration(session:session,device:Device());
    await registration.register(); await registration.unregister(); await registration.register();
    expect(session.requests.length,1); expect(session.removals.length,1);
    expect(session.removals.single['login_lease'],'12345678-1234-1234-1234-123456789aaa');
  });
  test('retirement during server enrollment cleans late result using old binding',() async {
    final session=RemovalSession()..user={'public_id':fixture.owner}; final server=Completer<dynamic>();
    session.respond=(m,p,b)=>server.future;
    final registration=NativeCallRegistration(session:session,device:Device());
    final operation=registration.register();
    await Future<void>.delayed(Duration.zero);
    final retiring=registration.unregister(); session.change(null);
    server.complete({'registered':true}); await operation; await retiring;
    expect(session.requests.length,1); expect(session.removals.length,1);
  });
  test('lost enrollment response remains removable without repeating enrollment',() async {
    final session=RemovalSession()..user={'public_id':fixture.owner};
    session.respond=(m,p,b) async { throw StateError('Synthetic receipt lost'); };
    final registration=NativeCallRegistration(session:session,device:Device());
    await expectLater(registration.register(),throwsStateError);
    await registration.unregister();
    expect(session.requests.length,1); expect(session.removals.length,1);
  });
  test('token rotation removes old captured enrollment before losing its handle',() async {
    final session=RemovalSession()..user={'public_id':fixture.owner}; final device=Device();
    final registration=NativeCallRegistration(session:session,device:device);
    await registration.register(); device.value={'transport':'fcm','token':'replacement-synthetic-token'};
    await registration.register();
    expect(session.removals.single['token'],'synthetic-fcm-token');
    expect(session.requests.length,2);
    await registration.unregister(); expect(session.removals.last['token'],'replacement-synthetic-token');
  });
  test('unready native and unverified login cannot enroll',() async {
    final session=PumpSession()..user={'public_id':fixture.owner}; final device=Device()..value=null;
    final registration=NativeCallRegistration(session:session,device:device);
    await registration.register(); expect(session.requests,isEmpty);
    session.lease=null; device.value={'transport':'fcm','token':'synthetic-fcm-token'};
    await registration.register(); expect(session.requests,isEmpty); expect(device.reads,1);
  });
  test('enrollment deduplicates same token but rotates with login lease',() async {
    final session=RemovalSession()..user={'public_id':fixture.owner}; final device=Device();
    final registration=NativeCallRegistration(session:session,device:device);
    await registration.register(); await registration.register(); expect(session.requests.length,1);
    session.change('abcdefab-1234-4234-8234-123456789abc');
    await registration.register(); expect(session.requests.length,2);
  });
  test('account replacement during native token wait cannot borrow new credentials',() async {
    final session=PumpSession()..user={'public_id':fixture.owner}; final device=Device()..wait=Completer();
    final registration=NativeCallRegistration(session:session,device:device);
    final work=registration.register(); session.change(null);
    device.wait!.complete({'transport':'fcm','token':'synthetic-fcm-token'}); await work;
    expect(session.requests,isEmpty);
  });
  test('APNs requires explicit environment and valid token',() async {
    final session=PumpSession()..user={'public_id':fixture.owner}; final device=Device()
      ..value={'transport':'apns_voip','token':List.filled(64,'a').join()};
    final registration=NativeCallRegistration(session:session,device:device);
    await registration.register(); expect(session.requests,isEmpty);
    device.value!['environment']='sandbox'; await registration.register(); expect(session.requests.length,1);
  });
}
