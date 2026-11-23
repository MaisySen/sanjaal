import 'dart:async';
import 'api.dart';

abstract class NativeCallDevice {
  /// No permission/provider activation here. Returns only an already registered
  /// native token after the platform confirms the complete implementation.
  Future<Map<String,String>?> binding();
}

/// Unselected enrollment owner. Unlike ordinary chat push this needs a verified
/// native login lease AND explicit platform readiness. No timer, prompt or send.
class NativeCallRegistration {
  NativeCallRegistration({required this.session, required this.device});
  final Session session;
  final NativeCallDevice device;
  bool _disposed=false;
  Future<void>? _running;
  String? _registered;
  final _uuid=RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
  bool _matches(String owner,String lease,int generation) => !_disposed &&
      session.user?['public_id']==owner && session.nativeCallLease==lease && session.generation==generation;
  Future<void> register() {
    if (_running!=null) return _running!;
    final operation=_register();
    _running=operation;
    return operation.whenComplete(() { if(identical(_running,operation)) _running=null; });
  }
  Future<void> _register() async {
    final owner=session.user?['public_id'] as String?;
    final lease=session.nativeCallLease;
    final generation=session.generation;
    if(_disposed || owner==null || lease==null || !_uuid.hasMatch(owner) || !_uuid.hasMatch(lease)) return;
    final token=await device.binding();
    if(!_matches(owner,lease,generation) || token==null) return;
    final transport=token['transport'], value=token['token'], environment=token['environment'];
    if(value==null || value.length<16 || value.length>4096 || !const ['fcm','apns_voip'].contains(transport)) return;
    if(transport=='apns_voip' && (!const ['sandbox','production'].contains(environment) ||
      !RegExp(r'^[a-fA-F0-9]{64,512}$').hasMatch(value))) { return; }
    final fingerprint='$owner:$lease:$transport:$environment:$value';
    if(_registered==fingerprint) return;
    await session.call('POST','/call-devices',body:{'transport':transport,'token':value,
      'login_lease':lease, if(transport=='apns_voip') 'environment':environment});
    if(_matches(owner,lease,generation)) _registered=fingerprint;
  }
  void dispose() { _disposed=true; _registered=null; }
}
