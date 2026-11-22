import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'session_bound_state.dart';
import 'ui.dart';

const reportStatuses = {
  'received': 'Received',
  'in_review': 'In review',
  'closed': 'Review closed',
};
const reportReasons = {
  'spam': 'Spam',
  'abuse': 'Abuse or harassment',
  'nudity': 'Nudity',
  'violence': 'Violence',
  'scam': 'Scam or fraud',
  'other': 'Something else',
};
const reportTypes = {'post': 'Post', 'user': 'Member', 'comment': 'Comment'};
final _receiptPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class ReportReceipt {
  ReportReceipt(dynamic value) {
    if (value is! Map ||
        value['public_id'] is! String ||
        !_receiptPattern.hasMatch(value['public_id']) ||
        !reportTypes.containsKey(value['type']) ||
        !reportReasons.containsKey(value['reason']) ||
        !reportStatuses.containsKey(value['status']) ||
        value['target'] is! String ||
        (value['target'] as String).trim().isEmpty ||
        (value['target'] as String).runes.length > 40 ||
        (value['note'] != null &&
            (value['note'] is! String ||
                (value['note'] as String).runes.length > 300)) ||
        !_validReportTime(value['created_at']) ||
        !_validReportTime(value['updated_at'])) {
      throw const FormatException('Invalid report receipt');
    }
    data = Map<String, dynamic>.unmodifiable(value.cast<String, dynamic>());
  }
  late final Map<String, dynamic> data;
  String get id => data['public_id'];
  String get status => t_(reportStatuses[data['status']]!);
}

bool _validReportTime(dynamic value) =>
    value == null || (value is String && DateTime.tryParse(value) != null);
String _reportTime(String? value) => value == null
    ? t_('Time unavailable')
    : DateTime.parse(value)
          .toLocal()
          .toIso8601String()
          .replaceFirst('T', ' ')
          .substring(0, 16);

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.session});
  final Session session;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SessionBoundState<ReportsPage> {
  @override
  Session get viewSession => widget.session;
  List<ReportReceipt>? rows;
  String? cursor, error;
  bool loading = false, opening = false, retryMore = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void sessionRetired() {
    rows = null;
    cursor = error = null;
    loading = false;
  }

  Future<void> load({bool more = false}) async {
    if (!mounted ||
        !sessionActive ||
        !widget.session.reportHistoryEnabled ||
        loading ||
        (more && cursor == null)) {
      return;
    }
    final requested = more ? cursor : null;
    setState(() {
      loading = true;
      error = null;
      retryMore = more;
    });
    try {
      final value = await widget.session.call(
        'GET',
        '/reports${requested == null ? '' : '?cursor=${Uri.encodeQueryComponent(requested)}'}',
      );
      if (value is! Map ||
          value['data'] is! List ||
          (value['data'] as List).length > 20 ||
          (value['next_cursor'] != null &&
              (value['next_cursor'] is! String ||
                  !_receiptPattern.hasMatch(value['next_cursor'])))) {
        throw const FormatException();
      }
      final parsed = (value['data'] as List).map(ReportReceipt.new).toList();
      final next = value['next_cursor'] as String?;
      final ids = parsed.map((r) => r.id).toSet();
      if (ids.length != parsed.length ||
          (next != null &&
              (parsed.isEmpty ||
                  next != parsed.last.id ||
                  next == requested))) {
        throw const FormatException();
      }
      if (!mounted || !sessionActive) return;
      if (more && parsed.any((r) => rows!.any((old) => old.id == r.id))) {
        throw const FormatException();
      }
      setState(() {
        rows = more ? [...rows!, ...parsed] : parsed;
        cursor = next;
      });
    } catch (_) {
      if (mounted && sessionActive) {
        setState(() => error = t_('Reports could not be loaded. Try again.'));
      }
    } finally {
      if (mounted && sessionActive) setState(() => loading = false);
    }
  }

  Future<void> open(ReportReceipt receipt) async {
    if (!mounted ||
        !sessionActive ||
        opening ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    opening = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReportDetailPage(
            session: widget.session,
            receiptId: receipt.id,
            onReceipt: (updated) {
              if (!mounted ||
                  !sessionActive ||
                  updated.id != receipt.id ||
                  rows == null) {
                return;
              }
              setState(
                () => rows = rows!
                    .map((r) => r.id == updated.id ? updated : r)
                    .toList(),
              );
            },
          ),
        ),
      );
    } finally {
      opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    final supported = widget.session.reportHistoryEnabled;
    return Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Your reports'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              t_(
                'Only reports submitted by this account appear here. Review status does not confirm content removal.',
              ),
            ),
            if (!supported)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  t_('Report history is not available on this server yet.'),
                ),
              ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error!),
                    TextButton(
                      onPressed: loading ? null : () => load(more: retryMore),
                      child: Text(t_('Try again')),
                    ),
                  ],
                ),
              ),
            if (supported && rows?.isEmpty == true)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  t_(
                    'No reports yet. Reports you submit from a post or profile will appear here.',
                  ),
                ),
              ),
            for (final row in rows ?? <ReportReceipt>[])
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const PhIcon('warning-circle'),
                  title: Text(
                    '${t_(reportTypes[row.data['type']]!)} · ${row.status}',
                  ),
                  subtitle: Text(
                    '${t_(reportReasons[row.data['reason']]!)}\n${_reportTime(row.data['created_at'])}',
                  ),
                  trailing: const PhIcon('caret-right'),
                  onTap: () => open(row),
                ),
              ),
            if (cursor != null)
              OutlinedButton(
                onPressed: loading ? null : () => load(more: true),
                child: Text(t_('Load more')),
              ),
          ],
        ),
      ),
    );
  }
}

class ReportDetailPage extends StatefulWidget {
  const ReportDetailPage({
    super.key,
    required this.session,
    required this.receiptId,
    this.onReceipt,
  });
  final Session session;
  final String receiptId;
  final ValueChanged<ReportReceipt>? onReceipt;
  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage>
    with SessionBoundState<ReportDetailPage> {
  @override
  Session get viewSession => widget.session;
  ReportReceipt? receipt;
  List<Map<String, dynamic>> events = [];
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant ReportDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receiptId != widget.receiptId) {
      receipt = null;
      events = [];
      load(force: true);
    }
  }

  @override
  void sessionRetired() {
    receipt = null;
    events = [];
    error = null;
    loading = false;
  }

  int request = 0;
  Future<void> load({bool force = false}) async {
    if (!mounted ||
        !sessionActive ||
        (loading && !force) ||
        !widget.session.reportHistoryEnabled ||
        !_receiptPattern.hasMatch(widget.receiptId)) {
      return;
    }
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.session.call(
        'GET',
        '/reports/${widget.receiptId}',
      );
      if (value is! Map ||
          value['events'] is! List ||
          (value['events'] as List).isEmpty ||
          (value['events'] as List).length > 3) {
        throw const FormatException();
      }
      final parsed = ReportReceipt(value['report']);
      final history = (value['events'] as List).map((e) {
        if (e is! Map ||
            !reportStatuses.containsKey(e['status']) ||
            !_validReportTime(e['created_at'])) {
          throw const FormatException();
        }
        return Map<String, dynamic>.from(e);
      }).toList();
      if (parsed.id != widget.receiptId ||
          history.first['status'] != 'received' ||
          history.last['status'] != parsed.data['status'] ||
          history.map((e) => e['status']).toSet().length != history.length) {
        throw const FormatException();
      }
      if (mounted && sessionActive && token == request) {
        setState(() {
          receipt = parsed;
          events = history;
        });
        widget.onReceipt?.call(parsed);
      }
    } catch (_) {
      if (mounted && sessionActive && token == request) {
        setState(
          () => error = t_('Report details could not be loaded. Try again.'),
        );
      }
    } finally {
      if (mounted && sessionActive && token == request) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    final row = receipt;
    return Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Report details'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (!widget.session.reportHistoryEnabled)
              Text(t_('Report history is not available on this server yet.')),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: loading ? null : load,
                child: Text(t_('Try again')),
              ),
            ],
            if (row != null) ...[
              Text(row.status, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                t_('Review status does not confirm that content was removed.'),
              ),
              const SizedBox(height: 24),
              Text(t_('Receipt')),
              SelectableText(row.id),
              const SizedBox(height: 16),
              Text(t_('Original report')),
              Text(
                '${t_(reportTypes[row.data['type']]!)} · ${t_(reportReasons[row.data['reason']]!)}',
              ),
              Text(t_('Original reference')),
              Text(row.data['target']),
              if (row.data['note'] != null) Text(row.data['note']),
              const SizedBox(height: 24),
              Text(
                t_('Status history'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final event in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t_(reportStatuses[event['status']]!)),
                  subtitle: Text(_reportTime(event['created_at'])),
                ),
              Text(t_('Times are shown in your device time zone.')),
            ],
          ],
        ),
      ),
    );
  }
}
