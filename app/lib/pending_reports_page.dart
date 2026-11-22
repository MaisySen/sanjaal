import 'package:material_ui/material_ui.dart';

import 'actions.dart';
import 'api.dart';
import 'reports_page.dart';
import 'report_submission_store.dart';
import 'session_bound_state.dart';
import 'glass/glass_app_bar.dart';
import 'ui.dart';

/// Device-local unresolved sends only. Opening this page never contacts reports.
class PendingReportsPage extends StatefulWidget {
  const PendingReportsPage({super.key, required this.session});
  final Session session;
  @override
  State<PendingReportsPage> createState() => _PendingReportsPageState();
}

class _PendingReportsPageState extends State<PendingReportsPage>
    with SessionBoundState<PendingReportsPage> {
  @override
  Session get viewSession => widget.session;
  List<Map<String, String>>? rows;
  bool loading = false, opening = false;
  String? error;
  bool get supported =>
      widget.session.reportHistoryEnabled && widget.session.reportReplayEnabled;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void sessionRetired() {
    rows = null;
    error = null;
    loading = false;
  }

  Future<void> load() async {
    if (!mounted || !sessionActive || !supported || loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await const ReportSubmissionStore().pending(
        widget.session.user!['public_id'] as String,
      );
      if (mounted && sessionActive) setState(() => rows = result);
    } catch (_) {
      if (mounted && sessionActive) {
        setState(() {
          rows = null;
          error = t_(
            'Unconfirmed reports could not be read. Nothing was changed.',
          );
        });
      }
    } finally {
      if (mounted && sessionActive) setState(() => loading = false);
    }
  }

  Future<void> open(Map<String, String> row) async {
    if (opening ||
        !mounted ||
        !sessionActive ||
        !supported ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() => opening = true);
    try {
      await reportFlow(
        context,
        widget.session,
        row['type']!,
        row['target']!,
        initialReason: row['reason'],
        memberRef: row['target_public_id'],
        isActive: () => mounted && sessionActive && supported,
      );
    } finally {
      if (mounted && sessionActive) {
        setState(() => opening = false);
        await load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    return Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Unconfirmed reports'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              t_(
                'Nothing is sent automatically. Open an attempt to review it before retrying.',
              ),
            ),
            if (!supported)
              Text(t_('Report history is not available on this server yet.')),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: loading ? null : load,
                child: Text(t_('Try again')),
              ),
            ],
            if (supported && rows?.isEmpty == true)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(t_('No unconfirmed reports on this device.')),
              ),
            for (final row in rows ?? <Map<String, String>>[])
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    '${t_(reportTypes[row['type']]!)} · ${t_(reportReasons[row['reason']]!)}',
                  ),
                  subtitle: Text(
                    row['type'] == 'user'
                        ? '@${row['target']}'
                        : row['target']!,
                  ),
                  onTap: opening ? null : () => open(row),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
