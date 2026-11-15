import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ui.dart';

/// Asks for a reason and files a report. [type] is post, user or comment.
Future<void> reportFlow(BuildContext context, Session s, String type, String target) async {
  const reasons = {
    'spam': 'Spam',
    'abuse': 'Abuse or harassment',
    'nudity': 'Nudity',
    'violence': 'Violence',
    'scam': 'Scam or fraud',
    'other': 'Something else',
  };
  final r = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(t_('Report')),
      children: [
        for (final e in reasons.entries) SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value)),
      ],
    ),
  );
  if (r == null) return;
  try {
    await s.call('POST', '/reports', body: {'type': type, 'target': target, 'reason': r});
    if (context.mounted) showInfo(context, 'Thanks. We review every report.');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Confirms and blocks a member. Returns true when blocked.
Future<bool> blockFlow(BuildContext context, Session s, String username) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Block @$username?'),
      content: const Text('You will not see each other\'s posts and they cannot follow you.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Block'))),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await s.call('POST', '/users/$username/block');
    if (context.mounted) showInfo(context, '@$username is blocked.');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}
