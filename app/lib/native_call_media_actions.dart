import 'package:flutter/services.dart';
import 'call_controller.dart';
import 'native_call_coordinator.dart';

/// Shares the app's one active-call host; never creates an independent hidden
/// Room owner. reserve must atomically refuse busy/quarantined/replacement work.
/// Unselected until the native lifecycle and platform audio handoff are ready.
class NativeCallMediaActions implements NativeCallActions {
  NativeCallMediaActions({required this.reserve, required this.release,
    required this.show, MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('au.fintex.sanjaal/incoming-calls');
  final CallController? Function(NativeCallEvent event) reserve;
  final Future<void> Function(CallController controller) release;
  final Future<void> Function(NativeCallEvent event, Map<String,dynamic> row) show;
  final MethodChannel _channel;
  final _owned = <String, CallController>{};
  final _cancelled = <String>{};
  @override
  Future<void> present(NativeCallEvent event, Map<String,dynamic> call) => show(event, call);
  @override
  Future<bool> connect(NativeCallEvent event, {required bool cameraEnabled}) async {
    if (cameraEnabled || _cancelled.contains(event.call) || _owned.isNotEmpty) return false;
    final prepared = await _channel.invokeMethod<bool>('prepare', {
      'call':event.call, 'generation':event.lease,
    });
    if (prepared != true || _cancelled.contains(event.call) || _owned.isNotEmpty) return false;
    final controller = reserve(event);
    if (controller == null) return false;
    // Fail closed even if an incorrectly supplied host enables camera or returns
    // a call belonging to another account/conversation.
    if (controller.startCamera || !controller.ownerMatches ||
        controller.conversationId != event.conversation) {
      await release(controller);
      return false;
    }
    _owned[event.call] = controller;
    final connected = await controller.connected;
    if (!identical(_owned[event.call], controller) || _cancelled.contains(event.call)) return false;
    if (!connected) { await stop(event); return false; }
    return true;
  }
  @override
  Future<void> complete(NativeCallEvent event, {required bool connected}) async {
    try {
      final acknowledged = await _channel.invokeMethod<bool>('complete', {
        'call':event.call, 'generation':event.lease, 'connected':connected,
      });
      // Failure to hand off system call ownership must release capture too.
      if (connected && acknowledged != true) {
        throw StateError('Native call media handoff was not confirmed');
      }
    } catch (_) {
      await stop(event);
      rethrow;
    }
  }

  @override
  Future<void> stop(NativeCallEvent event) async {
    _cancelled.add(event.call);
    final controller = _owned.remove(event.call);
    try {
      // End native system ownership before returning audio to ordinary calls.
      // This also stops a prepared service when End wins before reservation.
      await _channel.invokeMethod<bool>('complete', {
        'call':event.call, 'generation':event.lease, 'connected':false,
      });
    } finally {
      if (controller != null) await release(controller);
    }
  }
}
