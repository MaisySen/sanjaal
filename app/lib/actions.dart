import 'reports_page.dart';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'ui.dart';

/// Reason, persisted receipt, then owner-only review history on capable servers.
Future<void> reportFlow(
  BuildContext context,
  Session s,
  String type,
  String target, {
  bool Function()? isActive,
}) async {
  final openingRoute = ModalRoute.of(context);
  final owner = _ActionOwner(s, isActive);
  if (!owner.active || openingRoute?.isCurrent == false) {
    owner.dispose();
    return;
  }
  try {
    final reason = await owner.dialog<String>(
      context: context,
      builder: (c, complete) => SimpleDialog(
        title: Text(t_('Report')),
        children: [
          for (final entry in reportReasons.entries)
            SimpleDialogOption(
              onPressed: () => complete(entry.key),
              child: Text(t_(entry.value)),
            ),
        ],
      ),
    );
    if (reason == null ||
        !owner.active ||
        !context.mounted ||
        openingRoute?.isCurrent == false) {
      return;
    }
    try {
      final result = await s.call(
        'POST',
        '/reports',
        body: {'type': type, 'target': target, 'reason': reason},
      );
      if (!context.mounted ||
          !owner.active ||
          openingRoute?.isCurrent == false) {
        return;
      }
      if (!s.reportHistoryEnabled) {
        showInfo(context, t_('Report submitted.'));
        return;
      }
      final receipt = ReportReceipt((result as Map)['report']);
      if (receipt.data['type'] != type ||
          receipt.data['target'] != target ||
          receipt.data['reason'] != reason ||
          receipt.data['status'] != 'received') {
        throw const FormatException();
      }
      final view = await owner.dialog<bool>(
        context: context,
        builder: (c, complete) => AlertDialog(
          title: Text(t_('Report received')),
          content: Text(
            t_(
              'Your report has a receipt. You can check its review status in Your reports.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => complete(false),
              child: Text(t_('Done')),
            ),
            FilledButton(
              onPressed: () => complete(true),
              child: Text(t_('View report')),
            ),
          ],
        ),
      );
      if (view == true &&
          context.mounted &&
          owner.active &&
          openingRoute?.isCurrent != false) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReportDetailPage(session: s, receiptId: receipt.id),
          ),
        );
      }
    } catch (error) {
      if (context.mounted && owner.active && openingRoute?.isCurrent != false) {
        if (s.reportHistoryEnabled &&
            (error is! ApiError ||
                error.status == null ||
                error.status! >= 500)) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  t_(
                    'Report result unconfirmed. Check Your reports before submitting again.',
                  ),
                ),
                action: SnackBarAction(
                  label: t_('Your reports'),
                  onPressed: () async {
                    if (!context.mounted ||
                        !owner.active ||
                        openingRoute?.isCurrent == false) {
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportsPage(session: s),
                      ),
                    );
                  },
                ),
              ),
            );
        } else {
          showError(context, error);
        }
      }
    }
  } finally {
    owner.dispose();
  }
}

/// Confirms and blocks a member. No report status implies a block or removal.
Future<bool> blockFlow(
  BuildContext context,
  Session s,
  String username, {
  bool Function()? isActive,
  VoidCallback? onSubmitted,
}) async {
  final owner = _ActionOwner(s, isActive);
  if (!owner.active) {
    owner.dispose();
    return false;
  }
  try {
    final ok = await owner.dialog<bool>(
      context: context,
      builder: (c, complete) => AlertDialog(
        title: Text(tf_('Block @{u}?', {'u': username})),
        content: Text(
          t_(
            'You will not see each other\'s posts and they cannot follow you.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => complete(false),
            child: Text(t_('Cancel')),
          ),
          FilledButton(
            onPressed: () => complete(true),
            child: Text(t_('Block')),
          ),
        ],
      ),
    );
    if (ok != true || !owner.active || !context.mounted) return false;
    try {
      onSubmitted?.call();
      await s.call('POST', '/users/$username/block');
      if (context.mounted && owner.active) {
        showInfo(context, '@$username is blocked.');
      }
      return owner.active;
    } catch (error) {
      if (context.mounted && owner.active) showError(context, error);
      return false;
    }
  } finally {
    owner.dispose();
  }
}

class _ActionOwner {
  _ActionOwner(this.session, this.routeActive)
    : member = session.user?['public_id'],
      generation = session.generation {
    session.addListener(_changed);
  }
  final Session session;
  final bool Function()? routeActive;
  final Object? member;
  final int generation;
  bool retired = false;
  Route<dynamic>? _dialog;
  bool get active =>
      !retired &&
      member != null &&
      session.user?['public_id'] == member &&
      session.generation == generation &&
      (routeActive?.call() ?? true);
  void _changed() {
    if (active) return;
    retired = true;
    final route = _dialog;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<T?> dialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext, ValueChanged<T>) builder,
  }) async {
    if (!active || _dialog != null) return null;
    late final DialogRoute<T> route;
    var completed = false;
    void complete(T result) {
      if (completed ||
          !active ||
          !identical(_dialog, route) ||
          !route.isCurrent) {
        return;
      }
      completed = true;
      route.navigator?.pop<T>(result);
    }

    route = DialogRoute<T>(
      context: context,
      builder: (c) => builder(c, complete),
    );
    _dialog = route;
    try {
      return await Navigator.of(context, rootNavigator: true).push<T>(route);
    } finally {
      if (identical(_dialog, route)) _dialog = null;
    }
  }

  void dispose() {
    session.removeListener(_changed);
  }
}
