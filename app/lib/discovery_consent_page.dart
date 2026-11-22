import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'draft_exit_guard.dart';
import 'glass/glass_app_bar.dart';
import 'session_bound_state.dart';
import 'ui.dart' show t_;

/// Local candidate, opened only by an explicit capability-gated post-owner
/// menu after coordinated service activation. No local switch stands in for the
/// server's consent, audience or moderation state.
class DiscoveryConsentPage extends StatefulWidget {
  const DiscoveryConsentPage({
    super.key,
    required this.session,
    required this.postId,
    this.sourceAvailable,
  });
  final Session session;
  final String postId;
  final bool Function()? sourceAvailable;
  @override
  State<DiscoveryConsentPage> createState() => _DiscoveryConsentPageState();
}

class _DiscoveryConsentPageState extends State<DiscoveryConsentPage>
    with SessionBoundState<DiscoveryConsentPage> {
  @override
  Session get viewSession => widget.session;
  late final String openingPost = widget.postId;
  @override
  bool get sessionActive =>
      super.sessionActive &&
      openingPost == widget.postId &&
      (widget.sourceAvailable?.call() ?? true);
  Map<String, dynamic>? current;
  bool selected = false,
      loading = false,
      saving = false,
      reloadRequired = false,
      saved = false;
  bool sourceUnavailable = false;
  String? error;
  int read = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void sessionRetired() {
    sourceUnavailable = widget.sourceAvailable?.call() == false;
    saved = false;
    current = null;
    selected = false;
    loading = false;
    saving = false;
    error = null;
    read++;
  }

  Map<String, dynamic> _parse(Object? value) {
    if (value is! Map || value['discovery'] is! Map) {
      throw const FormatException();
    }
    final row = Map<String, dynamic>.from(value['discovery']);
    if (row['author_opted_in'] is! bool ||
        row['public_post'] is! bool ||
        row['revision'] is! int ||
        row['revision'] < 0 ||
        !['pending', 'approved', 'rejected'].contains(row['moderation'])) {
      throw const FormatException();
    }
    return row;
  }

  Future<void> _load() async {
    if (!sessionActive || loading || saving) return;
    final request = ++read;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = _parse(
        await widget.session.call('GET', '/posts/${widget.postId}/discovery'),
      );
      if (!mounted || !sessionActive || request != read) return;
      setState(() {
        current = data;
        selected = data['author_opted_in'];
        reloadRequired = false;
        saved = false;
      });
    } catch (_) {
      if (mounted && sessionActive && request == read) {
        setState(() => error = 'Discovery settings could not be loaded.');
      }
    } finally {
      if (mounted && sessionActive && request == read) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!sessionActive ||
        saving ||
        loading ||
        reloadRequired ||
        current == null ||
        selected == current!['author_opted_in']) {
      return;
    }
    final choice = selected, revision = current!['revision'] as int;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final next = _parse(
        await widget.session.call(
          'PUT',
          '/posts/${widget.postId}/discovery',
          body: {'author_opted_in': choice, 'revision': revision},
        ),
      );
      if (!mounted || !sessionActive) return;
      if (next['author_opted_in'] != choice ||
          next['revision'] != revision + 1) {
        throw const FormatException();
      }
      setState(() {
        current = next;
        selected = choice;
        saved = true;
      });
    } catch (_) {
      if (mounted && sessionActive) {
        setState(() {
          reloadRequired = true;
          error = 'Reload these settings before making another change.';
        });
      }
    } finally {
      if (mounted && sessionActive) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) {
      if (sourceUnavailable || widget.sourceAvailable?.call() == false) {
        return Scaffold(
          appBar: ReviewedAppBar(title: Text(t_('Discovery'))),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              t_(
                'Discovery is unavailable. Close this view and open Search again.',
              ),
            ),
          ),
        );
      }
      return retiredSessionView();
    }
    final data = current,
        changed = data != null && selected != data['author_opted_in'];
    return DraftExitGuard(
      hasChanges: changed,
      busy: saving,
      busyMessage: 'Your settings are still updating.',
      title: 'Discard these changes?',
      message: 'Your unsaved Discovery choice will be lost.',
      child: Scaffold(
        appBar: ReviewedAppBar(title: Text(t_('Discovery'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(t_(error!)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: loading || saving ? null : _load,
                child: Text(t_('Reload')),
              ),
              const SizedBox(height: 16),
            ],
            if (data != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t_('Allow this post in Explore')),
                value: selected,
                onChanged: loading || saving || reloadRequired
                    ? null
                    : (v) => setState(() {
                        selected = v;
                        saved = false;
                      }),
              ),
              Text(
                t_(
                  'Your post can be recommended only after public visibility and review are confirmed. Turning this off removes it from new Explore results, not from your profile or existing public links.',
                ),
              ),
              const SizedBox(height: 24),
              Text(
                t_(
                  data['public_post']
                      ? 'Public visibility confirmed'
                      : 'Public visibility not confirmed',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t_(switch (data['moderation']) {
                  'approved' => 'Review approved',
                  'rejected' => 'Not eligible for recommendations',
                  _ => 'Awaiting review',
                }),
              ),
              const SizedBox(height: 24),
              if (saved)
                Semantics(
                  liveRegion: true,
                  child: Text(t_('Your choice is saved.')),
                ),
              FilledButton(
                onPressed: changed && !saving && !loading && !reloadRequired
                    ? _save
                    : null,
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t_('Save')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
