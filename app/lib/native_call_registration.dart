import 'dart:async';
import 'api.dart';
import 'package:flutter/services.dart';

abstract class NativeCallDevice {
  /// No permission/provider activation here. Returns only an already registered
  /// native token after the platform confirms the complete implementation.
  Future<Map<String,String>?> binding();
}

/// Reads readiness only; never initializes Firebase, registers PushKit or asks
/// permission. Native implementation stays false until its full flow is ready.
class ChannelNativeCallDevice implements NativeCallDevice {
  ChannelNativeCallDevice({MethodChannel? channel}) : _channel=channel ?? const MethodChannel('au.fintex.sanjaal/incoming-calls');
  final MethodChannel _channel;
  @override Future<Map<String,String>?> binding() async {
    final value=await _channel.invokeMethod<Object?>('registration');
    if(value is! Map || value['registered']!=true || value['token'] is! String || value['transport'] is! String) return null;
    return {'transport':value['transport'] as String, 'token':value['token'] as String,
      if(value['environment'] is String) 'environment':value['environment'] as String};
  }
}

/// Unselected enrollment owner. Unlike ordinary chat push this needs a verified
/// native login lease AND explicit platform readiness. No timer, prompt or send.
class NativeCallRegistration {
  NativeCallRegistration({required this.session, required this.device});
  final Session session;
  final NativeCallDevice device;
  bool _disposed=false;
  Future<void>? _running;
  bool _again=false;
  String? _registered;
  Map<String,dynamic>? _registeredBinding;
  Future<void> Function(Map<String,dynamic>)? _remove;
  final _uuid=RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
  bool _matches(String owner,String lease,int generation) => !_disposed &&
      session.user?['public_id']==owner && session.nativeCallLease==lease && session.generation==generation;
  Future<void> register() {
    if (_disposed) return Future<void>.value();
    if (_running!=null) { _again=true; return _running!; }
    final operation=_drain();
    _running=operation;
    return operation.whenComplete(() { if(identical(_running,operation)) _running=null; });
  }
  Future<void> _drain() async {
    do { _again=false; await _register(); } while(_again && !_disposed);
  }
  Future<void> _retireBinding() async {
    final binding=_registeredBinding, remove=_remove;
    if(binding!=null && remove!=null) await remove(binding);
    _registeredBinding=null; _remove=null; _registered=null;
  }
  Future<void> _register() async {
    final owner=session.user?['public_id'] as String?;
    final lease=session.nativeCallLease;
    final generation=session.generation;
    if(_disposed || owner==null || lease==null || !_uuid.hasMatch(owner) || !_uuid.hasMatch(lease)) return;
    final token=await device.binding();
    if(!_matches(owner,lease,generation)) return;
    if(token==null) { await _retireBinding(); return; }
    final transport=token['transport'], value=token['token'], environment=token['environment'];
    if(value==null || value.length<16 || value.length>4096 || !const ['fcm','apns_voip'].contains(transport)) { await _retireBinding(); return; }
    if(transport=='apns_voip' && (!const ['sandbox','production'].contains(environment) ||
      !RegExp(r'^[a-fA-F0-9]{64,512}$').hasMatch(value))) { await _retireBinding(); return; }
    final fingerprint='$owner:$lease:$transport:$environment:$value';
    if(_registered==fingerprint) return;
    final binding=<String,dynamic>{'transport':transport,'token':value,
      'login_lease':lease, if(transport=='apns_voip') 'environment':environment};
    // Retire any older token/lease before replacing our only cleanup handle.
    // Failure keeps the old handle and blocks new enrollment, never orphaning it.
    final previous=_registeredBinding, previousRemove=_remove;
    if(previous!=null && previousRemove!=null) {
      await previousRemove(previous);
      _registeredBinding=null; _remove=null; _registered=null;
      if(!_matches(owner,lease,generation)) return;
    }
    final remove=session.captureCallDeviceRemoval();
    // Retain the exact attempt before POST. A transport error is unknown, not
    // proof that enrollment did not land. Unregister must still retire it.
    _registeredBinding=binding; _remove=remove;
    try {
      await session.call('POST','/call-devices',body:binding);
    } catch (_) {
      if(!_matches(owner,lease,generation)) await remove(binding);
      rethrow;
    }
    if(_matches(owner,lease,generation)) {
      _registered=fingerprint; _registeredBinding=binding; _remove=remove;
    } else {
      // Enrollment may have landed after account retirement. Cleanup uses only
      // its captured access and exact lease, never current Session.call.
      await remove(binding);
      _registeredBinding=null; _remove=null;
    }
  }
  Future<void> unregister() async {
    _disposed=true;
    final pending=_running;
    try { await pending; } catch (_) { /* Still try any confirmed enrollment. */ }
    final binding=_registeredBinding, remove=_remove;
    if(binding!=null && remove!=null) await remove(binding);
    _registered=null; _registeredBinding=null; _remove=null;
  }
  void dispose() { _disposed=true; _registered=null; }
}
