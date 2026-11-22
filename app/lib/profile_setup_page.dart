import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'glass/glass_app_bar.dart';
import 'profile_pages.dart' show EditProfilePage;
import 'session_bound_state.dart';
import 'session_recovery.dart';
import 'ui.dart';

/// Optional next step for a newly created, successfully signed-in account.
/// Skipping/continuing never saves profile data or requests media permission.
class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, required this.session});
  final Session session;
  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage>
    with SessionBoundState<ProfileSetupPage> {
  @override
  Session get viewSession => widget.session;
  late final String _owner = widget.session.user!['public_id'] as String;
  late final int _generation = widget.session.generation;
  bool _editing = false;
  void _finish() {
    if (!mounted || !sessionActive || _editing) return;
    widget.session.finishProfileSetup(
      owner: _owner,
      openedGeneration: _generation,
    );
  }

  Future<void> _edit() async {
    if (!mounted || !sessionActive || _editing) return;
    setState(() => _editing = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditProfilePage(session: widget.session),
        ),
      );
    } finally {
      if (mounted && sessionActive) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return SessionRecoveryView(session: widget.session);
    return Scaffold(
      appBar: ReviewedAppBar(
        title: Text(
          t_('Your profile'),
          maxLines: 2,
          style: const TextStyle(fontSize: 18),
        ),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(40).clamp(56, 96),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: FilledButton(
            onPressed: _editing ? null : _finish,
            child: Text(t_('Continue to Sanjaal'), textAlign: TextAlign.center),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: ListenableBuilder(
                      listenable: widget.session,
                      builder: (_, child) =>
                          Avatar(user: widget.session.user, radius: 28),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t_('Make your profile yours'),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t_(
                      'Add a name or photo so people can recognize you. This is optional.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListenableBuilder(
                    listenable: widget.session,
                    builder: (_, child) =>
                        Text('@${widget.session.user?['username'] ?? ''}'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _editing ? null : _edit,
                    child: Text(
                      t_('Add a name or photo'),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    t_('You can change your profile later from Edit profile.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
