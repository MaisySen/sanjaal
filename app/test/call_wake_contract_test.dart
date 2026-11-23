import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/call_wake_contract.dart';

void main() {
  const owner = '12345678-1234-1234-1234-123456789abc';
  const call = 'abcdefab-1234-1234-1234-123456789abc';
  const conversation = 'abcdefab-5678-1234-1234-123456789abc';
  final now = DateTime.utc(2026, 11, 23, 2);
  final epoch = now.millisecondsSinceEpoch ~/ 1000;
  Map<String, dynamic> fixture() => {'type': 'incoming_call', 'call_version': '1',
    'recipient': owner, 'call': call, 'conversation': conversation, 'kind': 'voice',
    'issued_at': '$epoch', 'expires_at': '${epoch + 40}'};
  test('valid recipient-bound forty-second wake matches only exact authenticated state', () {
    final wake = CallWakeEnvelope.parse(fixture(), owner: owner, now: now)!;
    expect(wake.call, call); expect(wake.video, isFalse);
    expect(wake.matchesState({'call': {'public_id': call, 'conversation_id': conversation,
      'kind': 'voice', 'status': 'ringing'}}), isTrue);
    expect(wake.matchesState({'call': {'public_id': conversation, 'conversation_id': conversation,
      'kind': 'voice', 'status': 'ringing'}}), isFalse);
    expect(wake.matchesState(null), isFalse);
  });
  final bad = <String, Object?>{'type': 'message', 'call_version': '2', 'recipient': call,
    'call': 'bad', 'conversation': null, 'kind': 'audio', 'issued_at': '${epoch + 10}',
    'expires_at': '${epoch + 400}'};
  for (final entry in bad.entries) {
    test('rejects invalid ${entry.key}', () {
      expect(CallWakeEnvelope.parse(fixture()..[entry.key] = entry.value, owner: owner, now: now), isNull);
    });
  }
  test('expired exact boundary and stale envelope never ring', () {
    expect(CallWakeEnvelope.parse(fixture(), owner: owner, now: now.add(const Duration(seconds: 40))), isNull);
    expect(CallWakeEnvelope.parse(fixture(), owner: owner, now: now.add(const Duration(hours: 1))), isNull);
  });
}
