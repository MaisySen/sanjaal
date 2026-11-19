import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ui.dart' show t_;

/// A routed account view cannot borrow a later login, including the same member.
/// Retiring a view never performs authenticated cleanup as the replacement user.
mixin SessionBoundState<T extends StatefulWidget> on State<T> {
  Session get viewSession;
  late final Session _sourceSession;
  late final String? _sourceOwner;
  late final int _sourceGeneration;
  bool _retired = false;
  bool get sessionActive => !_retired && identical(viewSession, _sourceSession) &&
      _sourceOwner != null && viewSession.user?['public_id'] == _sourceOwner &&
      viewSession.generation == _sourceGeneration;
  @override
  void initState() {
    super.initState();
    _sourceSession = viewSession;
    _sourceOwner = viewSession.user?['public_id'] as String?;
    _sourceGeneration = viewSession.generation;
    _sourceSession.addListener(_checkSession);
  }
  void _checkSession() {
    if (_retired || sessionActive || !mounted) return;
    _retired = true;
    sessionRetired();
    if (mounted) setState(() {});
  }
  /// Cancel private local work and native capture. Never send with viewSession.
  void sessionRetired() {}
  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkSession();
  }
  @override
  void dispose() {
    _sourceSession.removeListener(_checkSession);
    super.dispose();
  }
  Widget retiredSessionView() => Scaffold(
    appBar: AppBar(),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Text(t_(
      'This screen belongs to another signed-in session. Close it and sign in again to continue.'))),
  );
}
