import 'dart:async';
import 'api.dart';

/// Native UI actions are hints until bound to this restored account lease and an
/// exact authenticated call read. Not selected by the root application yet.
class NativeCallEvent {
  NativeCallEvent._(this.action, this.owner, this.lease, this.call,
      this.conversation, this.video, this.expires);
  final String action, owner, lease, call, conversation;
  final bool video;
  final DateTime expires;
  static final _uuid = RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
  static NativeCallEvent? parse(Object? value, {required String owner, required String lease, required DateTime now, Set<String> activeCalls = const {}}) {
    if (value is! Map || value['recipient'] != owner || value['generation'] != lease ||
        !const ['incoming', 'answer', 'decline', 'end', 'open'].contains(value['action']) ||
        !const ['voice', 'video'].contains(value['kind'])) {
      return null;
    }
    for (final key in ['call', 'conversation']) {
      if (value[key] is! String || !_uuid.hasMatch(value[key] as String)) return null;
    }
    final seconds = value['expires_at'];
    if (seconds is! int) return null;
    final current = now.millisecondsSinceEpoch ~/ 1000;
    final activeEnd = value['action'] == 'end' && activeCalls.contains(value['call']);
    if ((!activeEnd && seconds <= current) || seconds > current + 45) return null;
    return NativeCallEvent._(value['action'] as String, owner, lease, value['call'] as String,
        value['conversation'] as String, value['kind'] == 'video',
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true));
  }
}

/// Native completion is deferred until an existing exact call has been connected
/// or explicitly failed. Implementations must not enable background camera.
abstract class NativeCallActions {
  Future<void> present(NativeCallEvent event, Map<String, dynamic> call);
  Future<bool> connect(NativeCallEvent event, {required bool cameraEnabled});
  Future<void> complete(NativeCallEvent event, {required bool connected});
  Future<void> stop(NativeCallEvent event);
}

class NativeCallCoordinator {
  NativeCallCoordinator({required this.session, required this.lease, required this.actions,
    DateTime Function()? now}) : _owner = session.user?['public_id'] as String?,
      _generation = session.generation, _now = now ?? DateTime.now {
    session.addListener(_accountChanged);
  }
  final Session session;
  final String lease;
  final NativeCallActions actions;
  final String? _owner;
  final int _generation;
  final DateTime Function() _now;
  bool _retired = false;
  final _handled = <String>{};
  final _inFlight = <String>{};
  final _connecting = <String, NativeCallEvent>{};
  final _observed = <String, NativeCallEvent>{};
  bool _reconciling = false;
  final _cancelled = <String>{};
  final _connected = <String, NativeCallEvent>{};
  final _answeredHere = <String>{};
  final _remoteEndAttempted = <String>{};
  Future<void> _stopSafely(NativeCallEvent event) async {
    try { await actions.stop(event); } catch (_) {
      // The media owner quarantines unconfirmed release. Still attempt exact
      // authenticated server termination, never let platform failure skip it.
    }
  }
  Future<void> _endConfirmedAnswer(NativeCallEvent event) async {
    if (!active || !_answeredHere.contains(event.call) || !_remoteEndAttempted.add(event.call)) return;
    try { await session.call('POST', '/calls/${event.call}/action', body: {'action':'end'}); } catch (_) {
      // Unknown result is not replayed with this or a replacement login.
    }
  }
  Future<void> _failedAnswer(NativeCallEvent event) async {
    _connected.remove(event.call); _observed.remove(event.call);
    await _stopSafely(event);
    await _endConfirmedAnswer(event);
  }
  bool get active => !_retired && _owner != null && session.user?['public_id'] == _owner &&
      session.generation == _generation && !session.loading && !session.authenticating &&
      !session.recoveringAccount && !session.accountViewNeedsRefresh;
  bool _valid(NativeCallEvent event) => active && !_cancelled.contains(event.call) && event.expires.isAfter(_now());

  void _accountChanged() {
    if (_owner == session.user?['public_id'] && _generation == session.generation) return;
    _retired = true;
    for (final event in {..._observed, ..._connected, ..._connecting}.values.toList()) {
      unawaited(_stopSafely(event));
    }
  }
  Map<String, dynamic> _state(Object? value, NativeCallEvent event) {
    if (value is! Map || value['call'] is! Map) throw const FormatException('Missing native call state');
    final row = Map<String, dynamic>.from(value['call'] as Map);
    if (row['public_id'] != event.call || row['conversation_id'] != event.conversation ||
        row['kind'] != (event.video ? 'video' : 'voice') ||
        !const ['ringing', 'answered', 'declined', 'missed', 'ended'].contains(row['status'])) {
      throw const FormatException('Mismatched native call state');
    }
    if (row['status'] == 'ringing') {
      final end = row['ring_expires_at'] is String ? DateTime.tryParse(row['ring_expires_at'] as String) : null;
      if (end == null || !end.isAfter(_now()) || end.isAfter(event.expires.add(const Duration(seconds: 1)))) {
        throw const FormatException('Stale native call state');
      }
    }
    return row;
  }

  /// Exact-state reconciliation while this Dart engine is already alive. This
  /// cannot wake an OS-suspended or terminated app and is not a push substitute.
  Future<void> reconcile() async {
    if (!active || _reconciling) return;
    _reconciling = true;
    try {
      for (final event in {..._observed, ..._connecting, ..._connected}.values.toList()) {
        if (!active) return;
        try {
          if (!event.expires.isAfter(_now()) && !_answeredHere.contains(event.call) && !_inFlight.contains('${event.call}:answer')) {
            _cancelled.add(event.call); _observed.remove(event.call);
            await _stopSafely(event);
            if (active) await actions.complete(event, connected:false);
            continue;
          }
          final row = _state(await session.call('GET', '/calls/${event.call}'), event);
          if (!active) return;
          final terminal = const ['ended','declined','missed'].contains(row['status']);
          final answeredElsewhere = row['status']=='answered' && !_answeredHere.contains(event.call) && !_inFlight.contains('${event.call}:answer');
          if (terminal || answeredElsewhere) {
            _cancelled.add(event.call);
            _observed.remove(event.call); _connected.remove(event.call);
            await _stopSafely(event);
            if (active) await actions.complete(event, connected:false);
          }
        } catch (_) {
          // Unavailable or malformed state never authorizes an action or join.
          // Known local ownership remains until explicit stop or later evidence.
        }
      }
    } finally { _reconciling=false; }
  }
  bool get needsReconciliation => active && (_observed.isNotEmpty || _connecting.isNotEmpty || _connected.isNotEmpty);

  Future<void> handle(Object? data) async {
    if (!active) return;
    final event = NativeCallEvent.parse(data, owner: _owner!, lease: lease, now: _now(), activeCalls: {..._connected.keys, ..._connecting.keys});
    if (event == null) return;
    final key = '${event.call}:${event.action}';
    if (_handled.contains(key) || _inFlight.contains(key)) return;
    // End/decline must cancel a simultaneous pending answer locally immediately.
    if (event.action == 'end' || event.action == 'decline') {
      _cancelled.add(event.call);
      _observed.remove(event.call);
      await _stopSafely(event);
      _connected.remove(event.call);
    }
    _inFlight.add(key);
    // At most64 calls per coordinator lease, fail closed rather than evict replay guards.
    if (_handled.length >= 320) { _inFlight.remove(key); return; }
    _handled.add(key);
    if (!active) { _inFlight.remove(key); return; }
    try {
      final row = _state(await session.call('GET', '/calls/${event.call}'), event);
      if (!active) return;
      if (event.action == 'end' || event.action == 'decline') {
        if (const ['ringing', 'answered'].contains(row['status']) && _remoteEndAttempted.add(event.call)) {
          await session.call('POST', '/calls/${event.call}/action', body: {
            'action': row['status'] == 'ringing' && event.action == 'decline' ? 'decline' : 'end',
          });
        }
        await actions.complete(event, connected: false);
        return;
      }
      if (!_valid(event)) return;
      if (event.action == 'incoming' || event.action == 'open') {
        if (row['status'] == 'ringing') _observed[event.call] = event;
        await actions.present(event, row);
        return;
      }
      // Answered elsewhere is not proof this native action answered the call.
      if (row['status'] != 'ringing') {
        await actions.complete(event, connected: false);
        return;
      }
      Map<String, dynamic> receipt;
      try {
        receipt = _state(await session.call('POST', '/calls/${event.call}/action',
            body: {'action': 'answer'}), event);
      } catch (_) {
        // Lost response never repeats an action or silently joins an ambiguous answer.
        if (active) {
          try { await session.call('GET', '/calls/${event.call}'); } catch (_) {}
          await actions.complete(event, connected: false);
        }
        return;
      }
      if (receipt['status'] == 'answered') _answeredHere.add(event.call);
      if (!_valid(event) || receipt['status'] != 'answered') {
        if (active) await actions.complete(event, connected: false);
        await _endConfirmedAnswer(event);
        return;
      }
      _connecting[event.call] = event;
      final connected = await actions.connect(event, cameraEnabled: false);
      if (!_valid(event)) {
        await _failedAnswer(event);
        return;
      }
      if (connected) _connected[event.call] = event;
      await actions.complete(event, connected: connected);
      if (!connected) await _failedAnswer(event);
    } catch (_) {
      if (event.action == 'answer') await _failedAnswer(event);
      if (active) {
        try { await actions.complete(event, connected: false); } catch (_) {}
      }
    } finally {
      _inFlight.remove(key);
      _connecting.remove(event.call);
    }
  }

  void dispose() {
    if (_retired) { session.removeListener(_accountChanged); return; }
    _retired = true;
    session.removeListener(_accountChanged);
    for (final event in {..._observed, ..._connected, ..._connecting}.values.toList()) {
      unawaited(_stopSafely(event));
    }
  }
}
