import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sanjaal/active_call_host.dart';
import 'package:sanjaal/native_call_root.dart';
import 'call_continuity_fakes.dart';
void main() {
  testWidgets('default-off root does not bind platform, enroll or request permissions',(tester) async {
    var calls=0;
    const channel=MethodChannel('au.fintex.sanjaal/incoming-calls');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(_) async { calls++; return null; });
    final session=CallFixtureSession()..loading=false;
    await tester.pumpWidget(NativeCallRoot(session:session,hostKey:GlobalKey<ActiveCallHostState>(),
      child:const SizedBox()));
    await tester.pump(); expect(nativeCallRootEnabled,false); expect(calls,0); expect(session.requests,isEmpty);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
  });
}
