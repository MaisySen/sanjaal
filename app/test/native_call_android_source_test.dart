import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = 'android/app/src/main/kotlin/au/fintex/sanjaal';
  final owner = File('$root/NativeIncomingCalls.kt').readAsStringSync();
  final telecom = File('$root/NativeCallTelecom.kt').readAsStringSync();
  final activity = File('$root/MainActivity.kt').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  test('activity delegates initial and replacement intents to process singleton', () {
    expect(owner, contains('private constructor'));
    expect(owner, contains('context.applicationContext'));
    expect(owner, contains('@Volatile private var instance'));
    expect(activity, contains('override fun onNewIntent'));
    expect(activity, contains('override fun cleanUpFlutterEngine'));
    expect(activity.split('consume(intent)').length - 1, 2);
    expect(owner, contains('attachedMessenger !== messenger'));
  });
  test('telecom source defers active until explicit connected completion', () {
    expect(telecom, contains('if (connected) value.setActive()'));
    expect(telecom, contains('override fun onAnswer() { answer() }'));
    expect(telecom, contains('override fun onAnswer(videoState: Int) { answer() }'));
    expect(telecom, contains('action("answer", envelope)'));
    expect(telecom.split('setActive()').length-1,1);
    expect(telecom, contains('PROPERTY_SELF_MANAGED'));
    expect(telecom, contains('setAudioModeIsVoip(true)'));
    expect(telecom, contains('override fun onCreateIncomingConnectionFailed'));
  });
  test('source wiring does not silently register provider or telecom permission', () {
    expect(manifest, isNot(contains('NativeCallConnectionService')));
    expect(manifest, isNot(contains('MANAGE_OWN_CALLS')));
    expect(activity, isNot(contains('.activate()')));
    expect(owner, contains('"registered" to false'));
    expect(owner, contains('show = { false }'));
  });
}
