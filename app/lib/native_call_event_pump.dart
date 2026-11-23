import 'dart:async';
import 'package:flutter/services.dart';
import 'api.dart';
import 'native_call_coordinator.dart';

/// One engine-side owner. Not selected by the app root until native lifecycle,
/// media ownership and activation review are complete. No timer or auto-answer.
class NativeCallEventPump {
  NativeCallEventPump({required this.session, required this.actions,
    this.onTokenChanged, MethodChannel? channel}) : _channel = channel ?? const MethodChannel('au.fintex.sanjaal/incoming-calls') {
    session.addListener(_changed);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _changed();
      if (call.method == 'tokenChanged') onTokenChanged?.call();
    });
    _changed();
  }
  final Session session;
  final NativeCallActions actions;
  final void Function()? onTokenChanged;
  final MethodChannel _channel;
  NativeCallCoordinator? _coordinator;
  String? _owner, _lease;
  bool _disposed = false, _running = false, _again = false;
  bool registered = false;
  final _dispatching = <String>{};
  bool get _ready => !_disposed && session.nativeCallLease != null &&
      session.user?['public_id'] == _owner && session.nativeCallLease == _lease;
  Map<String, Object?> get _binding => {'owner': _owner, 'generation': _lease};

  void _changed() {
    if (_disposed) return;
    _again = true;
    // Retire synchronously, not after a pending platform/network operation.
    if (!_ready) { _coordinator?.dispose(); _coordinator = null; registered = false; }
    if (!_running) unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    try {
      while (_again && !_disposed) {
        _again = false;
        final owner = session.user?['public_id'] as String?;
        final lease = session.nativeCallLease;
        if (owner == null || lease == null) {
          _coordinator?.dispose(); _coordinator = null;
          // Preserve the cold-start journal while restoration is pending/offline.
          // Once a known engine binding is retired, clear native metadata before
          // a replacement bind. Also clear a settled genuinely signed-out root.
          final retired = _owner != null || _lease != null;
          final signedOut = !session.loading && !session.authenticating &&
              session.user == null && session.restoreError == null;
          if (retired || signedOut) {
            await _channel.invokeMethod<Object?>('clear', _binding);
          }
          _owner = null; _lease = null; registered = false;
          continue;
        }
        if (_coordinator == null || owner != _owner || lease != _lease) {
          _coordinator?.dispose();
          _owner = owner; _lease = lease;
          final result = await _channel.invokeMethod<Object?>('bind', _binding);
          if (!_ready) { _again = true; continue; }
          registered = result is Map && result['registered'] == true;
          _coordinator = NativeCallCoordinator(session: session, lease: lease, actions: actions);
        }
        final coordinator = _coordinator!;
        final binding = Map<String, Object?>.from(_binding);
        final events = await _channel.invokeMethod<Object?>('drain', binding);
        if (!_ready || !identical(coordinator, _coordinator)) continue;
        if (events is! List || events.length > 8) continue;
        // Do not block subsequent native callbacks on an Answer's network/media
        // wait. A later End must be drained and cancel it immediately too.
        for (final event in events) {
          if (event is! Map || event['event_id'] is! String) continue;
          final key = '$lease:${event['event_id']}';
          if (!_dispatching.add(key)) continue;
          unawaited(_handle(event, coordinator, binding).catchError((Object _) {
            registered = false;
          }).whenComplete(() => _dispatching.remove(key)));
        }
      }
    } catch (_) {
      // Platform absence/storage failure fails closed. Retry on the next real
      // native/session event, not a loop which can spam platform operations.
      registered = false;
    } finally {
      _running = false;
      if (_again && !_disposed) _changed();
    }
  }

  Future<void> _handle(Object? event, NativeCallCoordinator coordinator, Map<String, Object?> binding) async {
    if (event is! Map || event['event_id'] is! String || event['recipient'] != binding['owner'] ||
        event['generation'] != binding['generation']) { return; }
    final id = event['event_id'] as String;
    if (id.length > 80 || id != '${event['call']}:${event['action']}') { return; }
    final args = {...binding, 'event_id': id};
    if (!_ready || !identical(coordinator, _coordinator)) return;
    // Native persistence must complete before any authenticated read/effect.
    final claimed = await _channel.invokeMethod<bool>('claim', args);
    if (!_ready || !identical(coordinator, _coordinator)) return;
    if (claimed == true) { await coordinator.handle(event); }
    // A prior-process claim has an unknown outcome. Never replay it, only retire
    // the retained event. Both methods are generation-guarded by native code.
    if (_ready && identical(coordinator, _coordinator)) {
      await _channel.invokeMethod<bool>('acknowledge', args);
    }
  }

  void dispose() {
    _disposed = true;
    session.removeListener(_changed);
    _coordinator?.dispose(); _coordinator = null;
    _channel.setMethodCallHandler(null);
  }
}
