import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/native_call_coordinator.dart';
import 'call_continuity_fakes.dart';

const owner = '12345678-1234-1234-1234-123456789abc';
const id = 'abcdefab-1234-1234-1234-123456789abc';
const conversation = 'abcdefab-5678-1234-1234-123456789abc';
final now = DateTime.utc(2026, 11, 23, 2);
Map<String, dynamic> event(String action) => {'action': action, 'recipient': owner, 'generation': 'lease-a',
  'call': id, 'conversation': conversation, 'kind': 'video', 'expires_at': now.millisecondsSinceEpoch ~/ 1000 + 40};
Map<String, dynamic> state(String status) => {'call': {'public_id': id, 'conversation_id': conversation,
  'kind': 'video', 'status': status, 'ring_expires_at': now.add(const Duration(seconds: 40)).toIso8601String()}};
class Actions implements NativeCallActions {
  int presents = 0, connects = 0, stops = 0;
  final completions = <bool>[];
  Completer<bool>? pending;
  bool failConnect=false, failConnectedCompletion=false, failStop=false;
  @override Future<void> present(NativeCallEvent event, Map<String,dynamic> call) async { presents++; }
  @override Future<bool> connect(NativeCallEvent event, {required bool cameraEnabled}) async {
    expect(cameraEnabled, isFalse); connects++; return pending?.future ?? !failConnect;
  }
  @override Future<void> complete(NativeCallEvent event, {required bool connected}) async { completions.add(connected); if(connected && failConnectedCompletion) throw StateError('Synthetic handoff failure'); }
  @override Future<void> stop(NativeCallEvent event) async { stops++; if(failStop) throw StateError('Synthetic stop failure'); }
}
void main() {
  late CallFixtureSession session; late Actions actions; late NativeCallCoordinator coordinator; late DateTime clock;
  setUp(() {
    session = CallFixtureSession()..user = {'public_id': owner}..loading = false;
    clock = now; actions = Actions(); coordinator = NativeCallCoordinator(session: session, lease: 'lease-a', actions: actions, now: () => clock);
    session.respond = (method,path,body) async => state(method == 'POST' ? 'answered' : 'ringing');
  });
  tearDown(() => coordinator.dispose());
  test('failed prepared media ends only this confirmed answer once', () async {
    actions.failConnect=true;
    await coordinator.handle(event('answer'));
    expect(session.requests.where((r)=>r.method=='POST').length,2);
    expect(actions.completions,[false]);
  });
  test('failed system connected handoff stops media and ends confirmed answer', () async {
    actions.failConnectedCompletion=true;
    await coordinator.handle(event('answer'));
    expect(actions.stops,greaterThanOrEqualTo(1));
    expect(session.requests.where((r)=>r.method=='POST').length,2);
  });
  test('native stop failure cannot prevent exact authenticated End attempt', () async {
    await coordinator.handle(event('answer')); actions.failStop=true;
    session.respond=(m,p,b) async=>state(m=='GET'?'answered':'ended');
    await coordinator.handle(event('end'));
    expect(session.requests.where((r)=>r.method=='POST').length,2);
    actions.failStop=false;
  });
  test('failed media after replacement login never sends captured cleanup through new account', () async {
    actions.pending=Completer<bool>();
    final work=coordinator.handle(event('answer')); await Future<void>.delayed(Duration.zero);
    session.replace(owner:owner); actions.pending!.complete(false); await work;
    expect(session.requests.where((r)=>r.method=='POST').length,1);
  });
  test('failed answer then native End never repeats uncertain server end', () async {
    actions.failConnect=true; await coordinator.handle(event('answer'));
    session.respond=(m,p,b) async=>state('answered');
    await coordinator.handle(event('end'));
    expect(session.requests.where((r)=>r.method=='POST').length,2);
  });
  test('remote End after ring deadline retires owned media without sending End', () async {
    await coordinator.handle(event('answer')); clock=now.add(const Duration(minutes:2));
    session.respond=(m,p,b) async=>state('ended');
    await coordinator.reconcile();
    expect(actions.stops,1); expect(actions.completions,[true,false]);
    expect(session.requests.where((r)=>r.method=='POST').length,1);
    expect(coordinator.needsReconciliation,false);
  });
  test('remote cancellation retires presented ring without answering or posting', () async {
    await coordinator.handle(event('incoming'));
    session.respond=(m,p,b) async=>state('ended');
    await coordinator.reconcile();
    expect(actions.stops,1); expect(actions.connects,0);
    expect(session.requests.where((r)=>r.method=='POST'),isEmpty);
  });
  test('late reconciliation from retired login cannot stop new account', () async {
    await coordinator.handle(event('answer'));
    final pending=Completer<dynamic>();session.respond=(m,p,b)=>pending.future;
    final work=coordinator.reconcile(); await Future<void>.delayed(Duration.zero);
    session.replace(owner:owner);final stops=actions.stops;
    pending.complete(state('ended'));await work;
    expect(actions.stops,stops);
  });
  test('expired observed ring retires locally without endless state polling', () async {
    await coordinator.handle(event('incoming')); clock=now.add(const Duration(minutes:1));
    final reads=session.requests.length; await coordinator.reconcile();
    expect(session.requests.length,reads);expect(actions.stops,1);
    expect(coordinator.needsReconciliation,false);
  });
  test('native incoming reads exact state and never acts or connects', () async {
    await coordinator.handle(event('incoming'));
    expect(actions.presents,1); expect(actions.connects,0);
    expect(session.requests.map((r)=>r.method), ['GET']);
  });
  test('native answer verifies then acts once, connects without camera and completes', () async {
    await coordinator.handle(event('answer')); await coordinator.handle(event('answer'));
    expect(session.requests.map((r)=>r.method), ['GET','POST']);
    expect(actions.connects,1); expect(actions.completions,[true]);
  });
  for (final wrong in ['recipient','generation','call','expires_at']) {
    test('native event rejects mismatched $wrong before reads', () async {
      final value=event('answer')..[wrong] = wrong=='expires_at'?0:'wrong';
      await coordinator.handle(value); expect(session.requests,isEmpty); expect(actions.connects,0);
    });
  }
  test('answer elsewhere never authorizes local media', () async {
    session.respond=(m,p,b) async=>state('answered');
    await coordinator.handle(event('answer')); expect(session.requests.length,1);
    expect(actions.connects,0); expect(actions.completions,[false]);
  });
  test('lost answer receipt reads once but never repeats action or joins', () async {
    session.respond=(m,p,b) async { if(m=='POST') throw StateError('Synthetic lost receipt'); return state('ringing'); };
    await coordinator.handle(event('answer')); await coordinator.handle(event('answer'));
    expect(session.requests.map((r)=>r.method), ['GET','POST','GET']);
    expect(actions.connects,0); expect(actions.completions,[false]);
  });
  test('replacement same-account login retires delayed authenticated read', () async {
    final pending=Completer<dynamic>(); session.respond=(m,p,b)=>pending.future;
    final work=coordinator.handle(event('answer')); await Future<void>.delayed(Duration.zero);
    session.replace(owner:owner); pending.complete(state('ringing')); await work;
    expect(session.requests.length,1); expect(actions.connects,0); expect(actions.completions,isEmpty);
  });
  test('end cancels pending connection and never confirms it as connected', () async {
    actions.pending=Completer<bool>();
    final work=coordinator.handle(event('answer')); await Future<void>.delayed(Duration.zero);
    expect(actions.connects,1);
    session.respond=(m,p,b) async=>state(m=='GET'?'answered':'ended');
    await coordinator.handle(event('end')); actions.pending!.complete(true); await work;
    expect(actions.stops,greaterThanOrEqualTo(1)); expect(actions.completions,[false]);
    expect(session.requests.where((r)=>r.method=='POST').length,2);
  });
  test('mismatched state cannot produce an action or presentation', () async {
    session.respond=(m,p,b) async=>{'call': {...(state('ringing')['call'] as Map), 'public_id': conversation}};
    await coordinator.handle(event('answer')); expect(session.requests.length,1);
    expect(actions.connects,0); expect(actions.completions,[false]);
  });
  test('retiring a connected lease stops its own media without replacement API calls', () async {
    await coordinator.handle(event('answer'));
    expect(actions.completions,[true]);
    final count=session.requests.length; session.replace(owner:owner);
    await Future<void>.delayed(Duration.zero);
    expect(actions.stops,1); expect(session.requests.length,count);
  });

  test('native end of this connected call remains valid after original ring expiry', () async {
    await coordinator.handle(event('answer')); clock=now.add(const Duration(minutes: 10));
    session.respond=(m,p,b) async=>state(m=='GET'?'answered':'ended');
    await coordinator.handle(event('end'));
    expect(actions.stops,1); expect(actions.completions,[true,false]);
    expect(session.requests.map((r)=>r.method), ['GET','POST','GET','POST']);
  });
  test('expired unowned native end cannot touch a different active server call', () async {
    clock=now.add(const Duration(minutes:10));
    await coordinator.handle(event('end'));
    expect(session.requests,isEmpty); expect(actions.stops,0);
  });

}
