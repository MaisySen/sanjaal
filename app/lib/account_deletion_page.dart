import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ui.dart' show t_;
import 'session_bound_state.dart';
import 'glass/glass_app_bar.dart';

/// Request/status UI only. Disabled unless the server has a verified completion
/// process and reviewed notices. Submitting a request never claims deletion.
class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key, required this.session});
  final Session session;
  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}
class _AccountDeletionPageState extends State<AccountDeletionPage> with SessionBoundState<AccountDeletionPage> {
  @override
  Session get viewSession => widget.session;
  Map<String, dynamic>? _state;
  String? _error;
  bool _loading = true, _sending = false, _confirmed = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (!sessionActive || _sending) return;
    setState(() { _loading = true; _error = null; _confirmed = false; });
    try {
      final value = await widget.session.call('GET', '/auth/me/deletion');
      if (!mounted || !sessionActive) return;
      setState(() { _state = value; _loading = false; });
    } catch (_) {
      if (!mounted || !sessionActive) return;
      setState(() { _loading = false; _error = 'Could not load account deletion. No new request has been sent.'; });
    }
  }
  Future<void> _submit() async {
    if (_sending || _loading || !_confirmed || !sessionActive) return;
    final policy = _state?['policy'];
    if (policy is! Map || policy['policy_version'] is! String || _state?['available'] != true) return;
    setState(() { _sending = true; _error = null; });
    try {
      final value = await widget.session.call('POST', '/auth/me/deletion', body: {'confirmed': true, 'policy_version': policy['policy_version']});
      if (!mounted || !sessionActive) return;
      if (value['request'] is! Map || value['request']['status'] != 'requested') throw StateError('Unverified request response');
      setState(() { _state = {...?_state, 'request': value['request']}; _sending = false; _confirmed = false; });
    } catch (_) {
      if (!mounted || !sessionActive) return;
      setState(() { _sending = false; _confirmed = false; _error = 'Could not confirm your request. Check its status before trying again.'; _state = null; });
    }
  }
  bool _text(dynamic value) => value is String && value.trim().isNotEmpty;
  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return Scaffold(body: SafeArea(child: Center(child: Text('This account session has ended.'))));
    final request = _state?['request'];
    final knownRequest = request is Map && request['status'] == 'requested' && _text(request['public_id']) && _text(request['completion_notice']) && _text(request['retention_notice']);
    final policy = _state?['policy'];
    final ready = _state?['available'] == true && policy is Map && _text(policy['policy_version']) && _text(policy['completion_notice']) && _text(policy['retention_notice']);
    return Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Delete my account'))),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        if (_loading) const Center(child: CircularProgressIndicator()) else ...[
          if (knownRequest) ...[
            Text(t_('Deletion requested'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(t_('Your request has been recorded. Your account and data have not been deleted yet.')),
            const SizedBox(height: 16),
            Text(request['completion_notice']?.toString() ?? ''),
            const SizedBox(height: 12),
            Text(request['retention_notice']?.toString() ?? ''),
          ] else if (request != null) ...[
            Text(t_('Request status could not be verified. Check its status again.')),
          ] else if (ready) ...[
            Text(t_('Request account deletion'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(t_('Request deletion of your Sanjaal account and associated personal data, including content you shared. This is different from signing out.')),
            const SizedBox(height: 16),
            Text(policy['completion_notice'] as String),
            const SizedBox(height: 12),
            Text(policy['retention_notice'] as String),
            const SizedBox(height: 16),
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(t_('I want to request deletion of my account and data.')), value: _confirmed, onChanged: _sending ? null : (value) => setState(() => _confirmed = value == true)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _confirmed && !_sending ? _submit : null, child: Text(t_(_sending ? 'Sending request...' : 'Request deletion'))),
          ] else if (_error == null) ...[
            Text(t_('Account deletion is not available yet'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(t_('No request has been sent. Account deletion is not set up for this version.')),
          ],
          if (_error != null) ...[const SizedBox(height: 16), Text(t_(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error))],
          const SizedBox(height: 20),
          OutlinedButton(onPressed: _sending ? null : _load, child: Text(t_('Check status'))),
        ],
      ])),
    );
  }
}
