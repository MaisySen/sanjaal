import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/call_connection.dart';
import 'package:sanjaal/call_presentation.dart';

class CallFixtureSession extends Session {
  CallFixtureSession() {
    user = {'public_id': 'me', 'username': 'synthetic'};
  }
  int epoch = 1;
  @override
  int get generation => epoch;
  final requests = <({String method, String path, int epoch})>[];
  Future<dynamic>? tokenReply;
  Future<dynamic> Function(
    String method,
    String path,
    Map<String, dynamic>? body,
  )?
  respond;
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    requests.add((method: method, path: path, epoch: epoch));
    if (path.contains('/call-token')) {
      return tokenReply ??
          {
            'call_id':
                Uri.parse(path).queryParameters['call'] ?? 'synthetic-call',
            'url': 'wss://fixture.invalid',
            'token': 'not-a-real-token',
          };
    }
    final handler = respond;
    if (handler != null) return handler(method, path, body);
    return <String, dynamic>{
      'data': [],
      'next_cursor': null,
      'unread_messages': 0,
      'balance': 0,
      'entries': [],
    };
  }

  void replace({String owner = 'me'}) {
    epoch++;
    user = {'public_id': owner};
    notifyListeners();
  }
}

class FakeCallConnection implements CallConnection {
  final events = <String>[];
  final _listeners = <VoidCallback>{};
  Future<void>? connectWait, microphoneWait, cameraWait, disconnectWait;
  bool failDispose = false, failMicrophone = false, failStopCapture = false;
  @override
  Future<void> stopCapture() async {
    events.add('stopCapture');
    if (failStopCapture) throw StateError('Synthetic capture stop failed');
    microphoneEnabled = false;
    cameraEnabled = false;
  }

  @override
  CallTransport transport = CallTransport.connecting;
  @override
  int remoteCount = 0;
  @override
  bool? microphoneEnabled;
  @override
  bool? cameraEnabled;
  @override
  bool localAvailable = false;
  @override
  List<Widget> get tiles => const [];
  @override
  Widget? get selfPreview => null;
  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void emit() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  Future<void> connect(String url, String token) async {
    events.add('connect');
    await connectWait;
    transport = CallTransport.connected;
    localAvailable = true;
    emit();
  }

  @override
  Future<void> microphone(bool enabled) async {
    events.add('microphone:$enabled');
    await microphoneWait;
    if (failMicrophone) throw StateError('Synthetic native microphone failure');
    microphoneEnabled = enabled;
  }

  @override
  Future<void> camera(bool enabled) async {
    events.add('camera:$enabled');
    await cameraWait;
    cameraEnabled = enabled;
  }

  @override
  Future<void> disconnect() async {
    events.add('disconnect');
    await disconnectWait;
    transport = CallTransport.disconnected;
    localAvailable = false;
    emit();
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
    if (failDispose) throw StateError('Synthetic native cleanup failure');
  }
}

Future<void> settleCall() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
