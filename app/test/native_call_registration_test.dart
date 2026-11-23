import 'dart:async';
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
void main() {
  test('unready native and unverified login cannot enroll',() async {
    final session=PumpSession()..user={'public_id':fixture.owner}; final device=Device()..value=null;
    final registration=NativeCallRegistration(session:session,device:device);
    await registration.register(); expect(session.requests,isEmpty);
    session.lease=null; device.value={'transport':'fcm','token':'synthetic-fcm-token'};
    await registration.register(); expect(session.requests,isEmpty); expect(device.reads,1);
  });
  test('enrollment deduplicates same token but rotates with login lease',() async {
    final session=PumpSession()..user={'public_id':fixture.owner}; final device=Device();
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
