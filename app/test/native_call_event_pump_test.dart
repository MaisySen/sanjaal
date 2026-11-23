import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/native_call_event_pump.dart';
import 'call_continuity_fakes.dart';
import 'native_call_coordinator_test.dart' as fixture;

class PumpSession extends CallFixtureSession {
  String? lease = '12345678-1234-1234-1234-123456789aaa';
  @override String? get nativeCallLease => lease;
  void change(String? value) { lease = value; epoch++; notifyListeners(); }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic-native-calls');
  late PumpSession session;
  late fixture.Actions actions;
  late List<MethodCall> calls;
  late List<Map<String,dynamic>> events;
  late NativeCallEventPump pump;
  late bool claim;
  Completer<bool>? pending;
  Map<String,dynamic> event(String action) => fixture.event(action)
    ..['generation'] = session.lease
    ..['expires_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 40
    ..['event_id'] = '${fixture.id}:$action';
  Future<void> settle() async { for(var i=0;i<12;i++) { await Future<void>.delayed(Duration.zero); } }
  setUp(() {
    session=PumpSession()..user={'public_id':fixture.owner}..loading=false;
    actions=fixture.Actions(); calls=[]; events=[]; claim=true; pending=null;
    session.respond=(m,p,b) async => {'call': {'public_id':fixture.id,'conversation_id':fixture.conversation,
      'kind':'video','status':m=='POST'?'answered':'ringing',
      'ring_expires_at':DateTime.now().add(const Duration(seconds:39)).toIso8601String()}};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
      calls.add(call);
      switch(call.method) {
        case 'clear': return true;
        case 'bind': return {'registered':false};
        case 'drain': return List.of(events);
        case 'claim': return pending?.future ?? claim;
        case 'acknowledge': return true;
        default: throw MissingPluginException();
      }
    });
  });
  tearDown(() {
    pump.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
  });
  test('claim precedes exact read/action; ack follows completion; registered stays honest', () async {
    events=[event('answer')];
    session.respond=(m,p,b) async {
      expect(calls.any((c)=>c.method=='claim'),true);
      expect(calls.any((c)=>c.method=='acknowledge'),false);
      return {'call':{'public_id':fixture.id,'conversation_id':fixture.conversation,'kind':'video',
        'status':m=='POST'?'answered':'ringing','ring_expires_at':DateTime.now().add(const Duration(seconds:39)).toIso8601String()}};
    };
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle();
    expect(session.requests.map((r)=>r.method),['GET','POST']);
    expect(actions.connects,1); expect(pump.registered,false);
    expect(calls.map((c)=>c.method),['bind','drain','claim','acknowledge']);
    expect((calls.last.arguments as Map)['generation'],session.lease);
  });
  test('already claimed event is acknowledged without authenticated replay', () async {
    events=[event('answer')]; claim=false;
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle(); expect(session.requests,isEmpty);
    expect(calls.last.method,'acknowledge');
  });
  test('account replacement while claim pending prevents effect and stale acknowledgement', () async {
    events=[event('answer')]; pending=Completer<bool>();
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle(); session.change(null); pending!.complete(true);
    await settle(); expect(session.requests,isEmpty);
    expect(calls.where((c)=>c.method=='acknowledge'),isEmpty);
  });
  test('cold restore without ready lease does not erase persisted native journal', () async {
    session.lease=null; session.loading=true;
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle(); expect(calls,isEmpty);
  });
  test('wrong owner and forged event id never claim or read', () async {
    events=[event('answer')..['recipient']='wrong', event('answer')..['event_id']='forged'];
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle(); expect(calls.map((c)=>c.method),['bind','drain']); expect(session.requests,isEmpty);
  });
  test('queued end cancels answer while exact read is pending', () async {
    final read = Completer<dynamic>();
    events=[event('answer'), event('end')];
    session.respond=(m,p,b) async {
      if(session.requests.length==1) return read.future;
      return {'call':{'public_id':fixture.id,'conversation_id':fixture.conversation,'kind':'video',
        'status':'ended'}};
    };
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle();
    expect(actions.stops,1);
    read.complete({'call':{'public_id':fixture.id,'conversation_id':fixture.conversation,'kind':'video',
      'status':'ringing','ring_expires_at':DateTime.now().add(const Duration(seconds:39)).toIso8601String()}});
    await settle();
    expect(actions.connects,0);
    expect(session.requests.where((r)=>r.method=='POST'),isEmpty);
    expect(calls.where((c)=>c.method=='acknowledge').length,2);
  });
  test('settled signed-out root clears obsolete native binding', () async {
    session.lease=null; session.user=null; session.loading=false;
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle(); expect(calls.map((c)=>c.method),['clear']);
  });
  test('restoration error preserves native journal without borrowed identity', () async {
    session.lease=null; session.user=null; session.restoreError='offline';
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle(); expect(calls,isEmpty); expect(session.requests,isEmpty);
  });
  test('platform failure stays closed without retry loop', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
      calls.add(call); throw PlatformException(code:'storage');
    });
    pump=NativeCallEventPump(session:session,actions:actions,channel:channel);
    await settle(); expect(calls.length,1); expect(session.requests,isEmpty);
  });
}
