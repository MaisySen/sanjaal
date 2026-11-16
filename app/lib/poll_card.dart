import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ui.dart';

/// Single-choice poll. Counts and the current member's choice only. The API
/// never returns other voters. A failed vote keeps the last confirmed result.
class PollCard extends StatefulWidget {
  const PollCard({super.key, required this.session, required this.post});
  final Session session;
  final Map<String, dynamic> post;
  @override
  State<PollCard> createState() => _PollCardState();
}
class _PollCardState extends State<PollCard> {
  late Map<String, dynamic> poll = Map<String, dynamic>.from(widget.post['poll'] as Map);
  bool busy = false;
  String? error;

  @override
  void didUpdateWidget(covariant PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Feed refreshes can replace the same post object after another member votes.
    if (!busy && !identical(oldWidget.post, widget.post)) {
      poll = Map<String, dynamic>.from(widget.post['poll'] as Map);
      error = null;
    }
  }

  Future<void> _vote(int? choice) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final result = await widget.session.call(choice == null ? 'DELETE' : 'POST', '/posts/${widget.post['public_id']}/poll/vote', body: choice == null ? null : {'choice': choice}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        poll = Map<String, dynamic>.from(result['poll'] as Map);
        widget.post['poll'] = poll;
      });
    } catch (e) {
      if (mounted) setState(() => error = e is ApiError ? e.message : t_('Could not save your vote. Try again.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (poll['total_votes'] as num?)?.toInt() ?? 0;
    final mine = poll['my_choice'];
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final raw in poll['options'] as List) Builder(builder: (_) {
        final option = raw as Map;
        final count = (option['votes'] as num).toInt();
        final chosen = option['choice'] == mine;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(backgroundColor: chosen ? scheme.primaryContainer : null, padding: const EdgeInsets.all(12)),
            onPressed: busy ? null : () => _vote((option['choice'] as num).toInt()),
            child: Row(children: [
              Icon(chosen ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('${option['text']}', textAlign: TextAlign.start)),
              const SizedBox(width: 10),
              Text(total == 0 ? '0' : '${(count * 100 / total).round()}%'),
            ]),
          ),
        );
      }),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('$total ${t_(total == 1 ? 'vote' : 'votes')}'),
        if (mine != null) TextButton(onPressed: busy ? null : () => _vote(null), child: Text(t_('Remove vote'))),
        if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (error != null) Semantics(liveRegion: true, child: Text(error!, style: TextStyle(color: scheme.error))),
    ]);
  }
}
