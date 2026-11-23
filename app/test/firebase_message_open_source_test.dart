// Pinned FlutterFire channel contract only. No FCM/native delivery claim.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/push.dart';
import 'package:sanjaal/message_open_host.dart';

const recipient = '12345678-1234-1234-1234-123456789abc';
const conversation = 'abcdefab-1234-1234-1234-123456789abc';
class _CoreHost extends MockFirebaseApp {
  @override Future<List<CoreInitializeResponse>> initializeCore() async => [];
  @override Future<CoreInitializeResponse> initializeApp(String appName, CoreFirebaseOptions options) async =>
      CoreInitializeResponse(name: appName, options: options, pluginConstants: {});
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/firebase_messaging');
  final methods = <String>[];
  Object? initial;
  setUpAll(() => TestFirebaseCoreHostApi.setUp(_CoreHost()));
  setUp(() {
    methods.clear(); initial = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'Messaging#getInitialMessage') {
        if (initial is PlatformException) throw initial! as PlatformException;
        return initial;
      }
      throw StateError('Unexpected provider method: ${call.method}');
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test('cold tap traverses actual pinned messaging channel without requesting token or permission', () async {
    initial = {'messageId': 'synthetic-cold', 'data': {'type': 'message', 'open_version': '1', 'recipient': recipient, 'conversation': conversation}};
    const source = FirebaseMessageOpenSource();
    final intent = await source.initialOpen();
    expect(intent!.recipient, recipient); expect(intent.conversation, conversation);
    expect(methods, ['Messaging#getInitialMessage']);
  });
  test('actual opened-app channel maps message data and ignores unrelated notifications', () async {
    const source = FirebaseMessageOpenSource();
    await source.initialOpen(); // Installs the pinned SDK platform channel handler.
    methods.clear();
    final events = <MessageOpenIntent>[];
    final sub = source.opens.listen(events.add);
    Future<void> emit(Map<String, dynamic> data) async {
      final done = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall('Messaging#onMessageOpenedApp', {'data': data})), (_) => done.complete());
      await done.future;
      await Future<void>.delayed(Duration.zero);
    }
    await emit({'type': 'call'});
    await emit({'type': 'message', 'conversation': conversation});
    await emit({'type': 'message', 'open_version': '1', 'recipient': recipient, 'conversation': conversation});
    expect(events.length, 2);
    expect(events.first.conversation, isNull); expect(events.last.conversation, conversation);
    expect(methods, isEmpty);
    await sub.cancel();
  });
  test('initial provider failure remains observable to safe host fallback', () async {
    initial = PlatformException(code: 'synthetic-unavailable');
    await expectLater(const FirebaseMessageOpenSource().initialOpen(), throwsA(isA<Exception>()));
    expect(methods, ['Messaging#getInitialMessage']);
  });
  test('unsupported iOS initial source does not initialize messaging', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const source = FirebaseMessageOpenSource();
    expect(source.supported, isFalse); expect(await source.initialOpen(), isNull); expect(methods, isEmpty);
  });
}
