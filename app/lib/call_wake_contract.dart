/// Versioned native call wake contract. Presentation is not authentication and
/// never authorizes media, a call action, or fetching a replacement call token.
class CallWakeEnvelope {
  const CallWakeEnvelope._({required this.recipient, required this.call,
    required this.conversation, required this.video, required this.expiresAt});
  final String recipient, call, conversation;
  final bool video;
  final DateTime expiresAt;
  static final _uuid = RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
  static CallWakeEnvelope? parse(Object? value, {required String owner, required DateTime now}) {
    if (value is! Map || value['type'] != 'incoming_call' || value['call_version'] != '1') return null;
    for (final key in ['recipient', 'call', 'conversation']) {
      if (value[key] is! String || !_uuid.hasMatch(value[key] as String)) return null;
    }
    if ((value['recipient'] as String).toLowerCase() != owner.toLowerCase() ||
        !const ['voice', 'video'].contains(value['kind'])) {
      return null;
    }
    final issued = int.tryParse('${value['issued_at']}');
    final expires = int.tryParse('${value['expires_at']}');
    if (issued == null || expires == null || expires - issued != 40) return null;
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    // An unverified or old wake cannot extend the server's ring deadline.
    if (issued > seconds + 5 || expires <= seconds || expires > seconds + 45) return null;
    return CallWakeEnvelope._(recipient: (value['recipient'] as String).toLowerCase(),
      call: (value['call'] as String).toLowerCase(), conversation: (value['conversation'] as String).toLowerCase(),
      video: value['kind'] == 'video', expiresAt: DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true));
  }
  bool matchesState(Object? value) {
    if (value is! Map || value['call'] is! Map) return false;
    final row = value['call'] as Map;
    return row['public_id'] == call && row['conversation_id'] == conversation &&
        row['kind'] == (video ? 'video' : 'voice') &&
        const ['ringing', 'answered', 'declined', 'missed', 'ended'].contains(row['status']);
  }
}
