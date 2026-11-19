// Does not enable APNs or prove delivery. Unsupported iOS must be explicit,
// perform no Android Firebase/device registration, and not advise futile retries.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/push.dart';
import 'package:sanjaal/ui.dart';

class NoDeviceCalls extends Session {
 int calls=0;
 @override
 Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query}) async {
  calls++;throw StateError('iOS without APNs must not register a device');
 }
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('iOS push is explicitly unavailable without Android registration or retry advice',() async {
  debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
  addTearDown((){debugDefaultTargetPlatformOverride=null;Push.status.value='Not set up yet';});
  final session=NoDeviceCalls()..user={'public_id':'synthetic-ios-owner'};
  await Push.register(session);
  expect(Push.status.value,Push.iosUnavailable);
  expect(Push.status.value,contains('Reopening the app will not enable'));
  await Push.unregister(session);
  expect(Push.status.value,Push.iosUnavailable);
  expect(session.calls,0);
 });
 test('iOS limitation has a Nepali explanation',(){
  prefs.lang='ne';addTearDown(()=>prefs.lang='en');
  expect(t_(Push.iosUnavailable),isNot(Push.iosUnavailable));
 });
}
