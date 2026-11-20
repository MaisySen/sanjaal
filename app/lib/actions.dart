import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ui.dart';

/// Asks for a reason and files a report. [type] is post, user or comment.
Future<void> reportFlow(BuildContext context, Session s, String type, String target, {bool Function()? isActive}) async {
  final owner=_ActionOwner(s,isActive);
  if(!owner.active){owner.dispose();return;}
  try {
  const reasons = {
    'spam': 'Spam',
    'abuse': 'Abuse or harassment',
    'nudity': 'Nudity',
    'violence': 'Violence',
    'scam': 'Scam or fraud',
    'other': 'Something else',
  };
  final r = await owner.dialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(t_('Report')),
      children: [
        for (final e in reasons.entries) SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value)),
      ],
    ),
  );
  if (r == null || !owner.active || !context.mounted) return;
  try {
    await s.call('POST', '/reports', body: {'type': type, 'target': target, 'reason': r});
    if (context.mounted && owner.active) showInfo(context, 'Thanks. We review every report.');
  } catch (e) {
    if (context.mounted && owner.active) showError(context, e);
  }
  } finally {owner.dispose();}
}

/// Confirms and blocks a member. Returns true when blocked.
Future<bool> blockFlow(BuildContext context, Session s, String username, {bool Function()? isActive}) async {
  final owner=_ActionOwner(s,isActive);
  if(!owner.active){owner.dispose();return false;}
  try {
  final ok = await owner.dialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tf_('Block @{u}?', {'u': username})),
      content: Text(t_('You will not see each other\'s posts and they cannot follow you.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Block'))),
      ],
    ),
  );
  if (ok != true || !owner.active || !context.mounted) return false;
  try {
    await s.call('POST', '/users/$username/block');
    if (context.mounted && owner.active) showInfo(context, '@$username is blocked.');
    return owner.active;
  } catch (e) {
    if (context.mounted && owner.active) showError(context, e);
    return false;
  }
  } finally {owner.dispose();}
}

// Dialogs and their result belong to their opening login, even if the same
// member signs back in before choosing a reason or confirming a block.
class _ActionOwner {
  _ActionOwner(this.session,this.routeActive)
    : member=session.user?['public_id'],generation=session.generation {
    session.addListener(_changed);
  }
  final Session session;
  final bool Function()? routeActive;
  final Object? member;
  final int generation;
  bool retired=false;
  Route<dynamic>? _dialog;
  bool get active=>!retired && member!=null && session.user?['public_id']==member &&
      session.generation==generation && (routeActive?.call()??true);
  void _changed() {
    if(active)return;
    retired=true;
    final route=_dialog;
    if(route!=null && route.isActive) route.navigator?.removeRoute(route);
  }
  Future<T?> dialog<T>({required BuildContext context,required WidgetBuilder builder}) async {
    if(!active)return null;
    final route=DialogRoute<T>(context:context,builder:builder);
    _dialog=route;
    try {return await Navigator.of(context,rootNavigator:true).push<T>(route);}
    finally {_dialog=null;}
  }
  void dispose(){session.removeListener(_changed);}
}
