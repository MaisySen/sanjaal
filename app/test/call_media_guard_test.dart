// Adapter ordering only. No native device, microphone or camera is opened.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/call_media_guard.dart';

void main() {
  test('successful change applies once without cleanup', () async {
    final guard = CallMediaGuard();
    final events = <String>[];
    expect(await guard.change(isActive: () => true,
      apply: () async => events.add('apply'), onFailure: () => events.add('failed'),
      stopMicrophone: () async => events.add('mic-off'),
      stopCamera: () async => events.add('camera-off'),
      disconnect: () async => events.add('disconnect')), isTrue);
    expect(events, ['apply']);expect(guard.busy, isFalse);expect(guard.failed, isFalse);
  });

  for (final failedStops in [<String>{}, {'mic-off'}, {'camera-off'}, {'disconnect'}, {'mic-off','camera-off','disconnect'}]) {
    test('failed native change stops both capabilities and latches $failedStops', () async {
      final guard = CallMediaGuard();
      final events = <String>[];
      final error = StateError('synthetic native acknowledgment failure');
      Future<void> step(String name) async { events.add(name);if(failedStops.contains(name))throw StateError('synthetic stop failure'); }
      await expectLater(guard.change(isActive: () => true,
        apply: () async {events.add('apply');throw error;},
        onFailure: () {expect(guard.failed,isTrue);expect(guard.busy,isTrue);events.add('failed');},
        stopMicrophone: () => step('mic-off'),stopCamera: () => step('camera-off'),disconnect: () => step('disconnect')),throwsA(same(error)));
      expect(events,['apply','failed','mic-off','camera-off','disconnect']);
      expect(guard.failed,isTrue);expect(guard.busy,isFalse);
      expect(await guard.change(isActive:()=>true,apply:()=>step('retry'),onFailure:(){},stopMicrophone:()=>step('mic-off'),stopCamera:()=>step('camera-off'),disconnect:()=>step('disconnect')),isFalse);
      expect(events, isNot(contains('retry')));
    });
  }

  test('busy remains through cleanup and blocks another change', () async {
    final guard=CallMediaGuard();final stopping=Completer<void>();final started=Completer<void>();final events=<String>[];
    final result=guard.change(isActive:()=>true,apply:()async{throw StateError('synthetic');},onFailure:(){},
      stopMicrophone:()async{events.add('mic-off');started.complete();await stopping.future;},
      stopCamera:()async{events.add('camera-off');},disconnect:()async{events.add('disconnect');});
    final expectation=expectLater(result,throwsStateError);await started.future;
    expect(guard.busy,isTrue);expect(guard.failed,isTrue);
    expect(await guard.change(isActive:()=>true,apply:()async{events.add('retry');},onFailure:(){},stopMicrophone:()async{},stopCamera:()async{},disconnect:()async{}),isFalse);
    stopping.complete();await expectation;expect(events,['mic-off','camera-off','disconnect']);expect(guard.busy,isFalse);
  });

  test('owner retired during apply cannot publish success', () async {
    var active=true;final guard=CallMediaGuard();
    expect(await guard.change(isActive:()=>active,apply:()async{active=false;},onFailure:(){},stopMicrophone:()async{},stopCamera:()async{},disconnect:()async{}),isFalse);
  });

  test('owner retired during failed apply still completes all cleanup', () async {
    var active=true;final events=<String>[];final guard=CallMediaGuard();
    await expectLater(guard.change(isActive:()=>active,apply:()async{active=false;throw StateError('synthetic');},onFailure:(){events.add('failed');},stopMicrophone:()async{events.add('mic-off');},stopCamera:()async{events.add('camera-off');},disconnect:()async{events.add('disconnect');}),throwsStateError);
    expect(events,['failed','mic-off','camera-off','disconnect']);
  });

  test('inactive call never invokes a native change', () async {
    final guard=CallMediaGuard();
    expect(await guard.change(isActive:()=>false,apply:()async{fail('inactive native change');},onFailure:(){fail('inactive failure');},stopMicrophone:()async{},stopCamera:()async{},disconnect:()async{}),isFalse);
  });
}
