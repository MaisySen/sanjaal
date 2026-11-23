import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  final app=File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final native=File('ios/Runner/NativeIncomingCalls.swift').readAsStringSync();
  final project=File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  final engine=File('ios/Runner/NativeCallEngine.swift').readAsStringSync();
  final scene=File('ios/Runner/SceneDelegate.swift').readAsStringSync();
  final plist=File('ios/Runner/Info.plist').readAsStringSync();
  test('CallKit source is linked and process owned without provider activation', () {
    expect(project,contains('NativeIncomingCalls.swift in Sources'));
    expect(project,contains('CallWakeEnvelope.swift in Sources'));
    expect(app,contains('private lazy var incomingCalls'));
    expect(app,contains('incomingCalls.attach(registrar.messenger())'));
    expect(app,isNot(contains('incomingCalls.activate()')));
    expect(plist,isNot(contains('<string>voip</string>')));
  });
  test('private cold and scene path shares one gated engine without storyboard engine duplication', () {
    expect(engine,contains('static let enabled = false'));
    expect(engine,contains('allowHeadlessExecution: true'));
    expect(engine,contains('if let engine = engine { return engine }'));
    expect(engine,contains('if let existing = engine.viewController { return existing }'));
    expect(app,contains('config.storyboard = nil'));
    expect(scene,contains('app.callEngine.controller()'));
    expect(app,contains('owner.wakeEngine'));
  });
  test('CallKit audio activation checks the pinned native gate', () {
    expect(app,contains('import livekit_client'));
    expect(app,contains('LiveKitPlugin.setEngineAvailability'));
    expect(native,contains('audioAvailability?(true) == true'));
    expect(native,contains('let accepted = leaseMatches'));
    expect(native,contains('payload.dictionaryPayload["login_lease"]'));
    expect(native,contains('self.owner == openedOwner, self.generation == openedGeneration'));
    expect(native,isNot(contains('self.seen = [id]')));
  });
}
