import 'dart:async';
import 'package:flutter/widgets.dart';
import 'api.dart';
import 'active_call_host.dart';
import 'native_call_event_pump.dart';
import 'native_call_media_actions.dart';
import 'native_call_registration.dart';

/// Private source gate. Never enable from an unreviewed runtime preference.
const nativeCallRootEnabled = false;

class NativeCallRoot extends StatefulWidget {
  const NativeCallRoot({super.key,required this.session,required this.hostKey,required this.child});
  final Session session;
  final GlobalKey<ActiveCallHostState> hostKey;
  final Widget child;
  @override State<NativeCallRoot> createState()=>_NativeCallRootState();
}
class _NativeCallRootState extends State<NativeCallRoot> {
  NativeCallEventPump? _pump;
  NativeCallRegistration? _registration;
  String? _lease;
  @override void initState() {
    super.initState();
    if (!nativeCallRootEnabled) return;
    widget.session.addListener(_account);
    WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) _start(); });
  }
  void _start() {
    _pump=NativeCallEventPump(session:widget.session,actions:NativeCallMediaActions(
      reserve:(event)=>widget.hostKey.currentState?.reserveNative(event),
      release:(call) async { await widget.hostKey.currentState?.releaseNative(call); },
      // Incoming/open metadata never navigates from a background callback.
      // Foreground incoming reconciliation retains its exact-read UI path.
      show:(event,row) async {},
    ));
    _account();
  }
  void _account() {
    if(!mounted || _pump==null) return;
    final next=widget.session.nativeCallLease;
    if(next==_lease) return;
    final previous=_registration;
    _registration=null; _lease=next;
    if(previous!=null) unawaited(previous.unregister().catchError((Object _) {}));
    if(next==null) return;
    final value=NativeCallRegistration(session:widget.session,device:ChannelNativeCallDevice());
    _registration=value;
    unawaited(value.register().catchError((Object _) {}));
  }
  @override void didUpdateWidget(covariant NativeCallRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Root Session object is currently persistent. A future replacement must
    // recreate this scope, not let callbacks borrow its new account object.
    if(!identical(oldWidget.session,widget.session)) {
      oldWidget.session.removeListener(_account);
      _pump?.dispose(); _pump=null;
      final previous=_registration; _registration=null;
      if(previous!=null) unawaited(previous.unregister().catchError((Object _) {}));
    }
  }
  @override void dispose() {
    widget.session.removeListener(_account);
    _pump?.dispose();
    final previous=_registration;
    if(previous!=null) unawaited(previous.unregister().catchError((Object _) {}));
    super.dispose();
  }
  @override Widget build(BuildContext context)=>widget.child;
}
