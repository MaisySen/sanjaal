import 'reports_page.dart';
import 'report_submission_store.dart';

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
  String? targetLabel,
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
    final replaySafe = s.reportHistoryEnabled && s.reportReplayEnabled;
    const submissions = ReportSubmissionStore();
    String? previous;
    if (replaySafe) {
      try {
        previous = await submissions.find(
          owner.member as String,
          type,
          target,
          reason,
        );
      } catch (_) {
        if (context.mounted &&
            owner.active &&
            openingRoute?.isCurrent != false) {
          showError(
            context,
            ApiError(t_('Report retry could not be saved. Nothing was sent.')),
          );
        }
        return;
      }
      if (!context.mounted ||
          !owner.active ||
          openingRoute?.isCurrent == false) {
        return;
      }
    }
    final confirmed = await owner.dialog<bool>(
      context: context,
      builder: (c, complete) => AlertDialog(
        scrollable: true,
        title: Text(t_('Review report'), style: const TextStyle(fontSize: 18)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t_(reportTypes[type] ?? 'Report')),
            const SizedBox(height: 6),
            if (targetLabel != null && targetLabel.trim().isNotEmpty) ...[
              Text(targetLabel, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
            ],
            if (targetLabel != null &&
                targetLabel.trim().isNotEmpty &&
                type != 'user')
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  t_('Reference'),
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                children: [
                  SelectableText(
                    target,
                    key: const ValueKey('report-review-target'),
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                ],
              )
            else
              SelectableText(
                type == 'user' ? '@$target' : target,
                key: const ValueKey('report-review-target'),
                style: Theme.of(c).textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            Text(t_(reportReasons[reason]!)),
            const SizedBox(height: 12),
            Text(
              t_(
                previous == null
                    ? 'Send this report?'
                    : 'Retry the same report?',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => complete(false),
            child: Text(t_('Cancel')),
          ),
          FilledButton(
            onPressed: () => complete(true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            child: Text(
              t_('Send report'),
              style: const TextStyle(height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !owner.active ||
        !context.mounted ||
        openingRoute?.isCurrent == false) {
      return;
    }
    String? submission;
    if (replaySafe) {
      try {
        submission = await submissions.prepare(
          owner.member as String,
          type,
          target,
          reason,
        );
      } catch (_) {
        if (context.mounted &&
            owner.active &&
            openingRoute?.isCurrent != false) {
          showError(
            context,
            ApiError(t_('Report retry could not be saved. Nothing was sent.')),
          );
        }
        return;
      }
      if (!context.mounted ||
          !owner.active ||
          openingRoute?.isCurrent == false) {
        return;
      }
    }
    try {
      final result = await s.call(
        'POST',
        '/reports',
        body: {
          'type': type,
          'target': target,
          'reason': reason,
          'submission_id': ?submission,
        },
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
          (receipt.data['status'] != 'received' &&
              !(replaySafe && result['replayed'] == true))) {
        throw const FormatException();
      }
      if (submission != null) {
        try {
          await submissions.complete(
            owner.member as String,
            type,
            target,
            reason,
            submission,
          );
        } catch (_) {
          // Keep the same key on storage failure. A later explicit send is still replay-safe.
        }
        if (!context.mounted ||
            !owner.active ||
            openingRoute?.isCurrent == false) {
          return;
        }
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
      if (completed || !identical(_dialog, route)) return;
      // A newer profile read can retire this choice without a session event.
      // Remove only this owner's dialog, never a route that now covers it.
      _changed();
      if (!active || !route.isCurrent) return;
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
