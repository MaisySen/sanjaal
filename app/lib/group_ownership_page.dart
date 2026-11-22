import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'session_bound_state.dart';
import 'ui.dart';

final _groupUuid = RegExp(
  r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
);

/// A complete current group snapshot, never a username-only handoff target.
class GroupOwnershipSnapshot {
  GroupOwnershipSnapshot(dynamic value, String groupId, String actorId) {
    if (value is! Map ||
        value['public_id'] != groupId ||
        !_groupUuid.hasMatch(groupId) ||
        value['type'] != 'group' ||
        value['title'] is! String ||
        (value['title'] as String).trim().isEmpty ||
        (value['title'] as String).runes.length > 80 ||
        value['ownership_revision'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['ownership_revision']) ||
        !['owner', 'member'].contains(value['my_role']) ||
        value['members'] is! List ||
        (value['members'] as List).isEmpty ||
        (value['members'] as List).length > 50) {
      throw const FormatException('Invalid group ownership snapshot');
    }
    final parsed = <Map<String, dynamic>>[];
    for (final member in value['members'] as List) {
      if (member is! Map ||
          member['public_id'] is! String ||
          !_groupUuid.hasMatch(member['public_id']) ||
          member['username'] is! String ||
          (member['username'] as String).trim().isEmpty ||
          (member['username'] as String).runes.length > 80 ||
          (member['name'] != null &&
              (member['name'] is! String ||
                  (member['name'] as String).runes.length > 80)) ||
          (member['avatar_url'] != null &&
              (member['avatar_url'] is! String ||
                  (member['avatar_url'] as String).length > 2048)) ||
          !['owner', 'member'].contains(member['group_role'])) {
        throw const FormatException('Invalid group member');
      }
      parsed.add(
        Map<String, dynamic>.unmodifiable({
          'public_id': member['public_id'],
          'username': member['username'],
          'name': member['name'],
          'group_role': member['group_role'],
          'avatar_url': member['avatar_url'],
        }),
      );
    }
    if (parsed.map((m) => m['public_id']).toSet().length != parsed.length ||
        parsed.map((m) => m['username']).toSet().length != parsed.length ||
        parsed.where((m) => m['group_role'] == 'owner').length != 1) {
      throw const FormatException('Ambiguous group owner');
    }
    final actor = parsed.where((m) => m['public_id'] == actorId).toList();
    if (actor.length != 1 || actor.single['group_role'] != value['my_role']) {
      throw const FormatException('Group does not belong to this member');
    }
    id = groupId;
    title = value['title'];
    revision = value['ownership_revision'];
    isOwner = value['my_role'] == 'owner';
    members = List.unmodifiable(parsed);
  }
  late final String id, title, revision;
  late final bool isOwner;
  late final List<Map<String, dynamic>> members;
  Map<String, dynamic> get owner =>
      members.singleWhere((m) => m['group_role'] == 'owner');
}

String _memberName(Map<String, dynamic> member) =>
    (member['name'] as String?)?.trim().isNotEmpty == true
    ? member['name']
    : '@${member['username']}';

class GroupOwnershipPage extends StatefulWidget {
  const GroupOwnershipPage({
    super.key,
    required this.session,
    required this.groupId,
  });
  final Session session;
  final String groupId;
  @override
  State<GroupOwnershipPage> createState() => _GroupOwnershipPageState();
}

class _GroupOwnershipPageState extends State<GroupOwnershipPage>
    with SessionBoundState<GroupOwnershipPage> {
  @override
  Session get viewSession => widget.session;
  late final String _groupId;
  bool _retiredGroup = false;
  GroupOwnershipSnapshot? snapshot;
  bool loading = false, sending = false, needsRead = false;
  String? error, info;
  int epoch = 0;
  BuildContext? dialog;
  bool get active =>
      mounted && sessionActive && !_retiredGroup && widget.groupId == _groupId;
  bool get canAct =>
      active &&
      widget.session.groupOwnershipEnabled &&
      !loading &&
      !sending &&
      !needsRead &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _groupId = widget.groupId;
    load();
  }

  void retire() {
    ++epoch;
    snapshot = null;
    error = info = null;
    loading = sending = false;
    final owned = dialog;
    if (owned != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (owned.mounted && ModalRoute.of(owned)?.isCurrent == true) {
          Navigator.of(owned).pop(false);
        }
      });
    }
  }

  @override
  void sessionRetired() => retire();

  @override
  void didUpdateWidget(GroupOwnershipPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groupId != _groupId && !_retiredGroup) {
      _retiredGroup = true;
      retire();
    }
  }

  Future<void> load() async {
    if (!active ||
        loading ||
        sending ||
        !widget.session.groupOwnershipEnabled) {
      return;
    }
    final version = ++epoch;
    setState(() {
      loading = true;
      snapshot = null;
      error = info = null;
    });
    try {
      if (!_groupUuid.hasMatch(_groupId)) throw const FormatException();
      final value = await widget.session.call(
        'GET',
        '/conversations/$_groupId',
      );
      final parsed = GroupOwnershipSnapshot(
        value is Map ? value['conversation'] : null,
        _groupId,
        widget.session.user?['public_id'] ?? '',
      );
      if (!active || version != epoch) return;
      setState(() {
        snapshot = parsed;
        needsRead = false;
      });
    } catch (_) {
      if (active && version == epoch) {
        setState(() {
          error = 'Could not load group ownership. Try again.';
        });
      }
    } finally {
      if (active && version == epoch) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> choose(
    GroupOwnershipSnapshot source,
    Map<String, dynamic> member,
  ) async {
    if (!canAct ||
        !identical(snapshot, source) ||
        !source.isOwner ||
        member['public_id'] == widget.session.user?['public_id'] ||
        !source.members.contains(member)) {
      return;
    }
    final version = epoch;
    bool valid() =>
        active &&
        widget.session.groupOwnershipEnabled &&
        version == epoch &&
        identical(snapshot, source) &&
        !loading &&
        !sending &&
        !needsRead;
    var decided = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) {
        dialog = c;
        void finish(bool yes) {
          if (decided || !c.mounted || ModalRoute.of(c)?.isCurrent != true) {
            return;
          }
          decided = true;
          Navigator.of(c).pop(yes && valid());
        }

        return AlertDialog(
          insetPadding: const EdgeInsets.all(16),
          title: Text(
            t_('Make owner?'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          contentTextStyle: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontSize: 14, height: 1.35),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text('${_memberName(member)}\n@${member['username']}'),
                const SizedBox(height: 12),
                Text(
                  t_(
                    'They will be able to rename this group and choose its next owner. You will stay in the group as a member.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => finish(false),
              child: Text(t_('Cancel')),
            ),
            FilledButton(
              onPressed: () => finish(true),
              child: Text(t_('Make owner')),
            ),
          ],
        );
      },
    );
    dialog = null;
    if (approved != true || !canAct || !valid()) return;
    setState(() {
      sending = true;
      error = info = null;
    });
    try {
      final value = await widget.session.call(
        'POST',
        '/conversations/$_groupId/ownership',
        body: {
          'member_id': member['public_id'],
          'ownership_revision': source.revision,
        },
      );
      final parsed = GroupOwnershipSnapshot(
        value is Map ? value['conversation'] : null,
        _groupId,
        widget.session.user?['public_id'] ?? '',
      );
      final before = source.members.map((m) => m['public_id']).toSet();
      final after = parsed.members.map((m) => m['public_id']).toSet();
      if (parsed.isOwner ||
          parsed.owner['public_id'] != member['public_id'] ||
          parsed.revision == source.revision ||
          parsed.title != source.title ||
          before.length != after.length ||
          !before.containsAll(after)) {
        throw const FormatException();
      }
      if (!active || version != epoch) return;
      setState(() {
        snapshot = parsed;
        info = 'Ownership transferred. You are still a group member.';
      });
    } catch (_) {
      if (active && version == epoch) {
        setState(() {
          snapshot = null;
          needsRead = true;
          error = 'The result could not be confirmed. Reload the group before choosing again.';
        });
      }
    } finally {
      if (active && version == epoch) {
        setState(() {
          sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    if (_retiredGroup) {
      return Scaffold(
        appBar: ReviewedAppBar(title: Text(t_('Group ownership'))),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            t_(
              'This group view has changed. Close it and open the group again.',
            ),
          ),
        ),
      );
    }
    final current = snapshot;
    return PopScope(
      canPop: !sending,
      child: Scaffold(
        appBar: ReviewedAppBar(
          title: Text(
            t_('Group ownership'),
            maxLines: 2,
            style: const TextStyle(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 26
              ? MediaQuery.textScalerOf(context).scale(20) * 2.4 + 16
              : null,
          actions: [
            if (widget.session.groupOwnershipEnabled)
              IconButton(
                tooltip: t_('Reload group'),
                onPressed: loading || sending ? null : load,
                icon: const PhIcon('arrow-clockwise'),
              ),
          ],
        ),
        body: !widget.session.groupOwnershipEnabled
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  t_(
                    'Group ownership changes are not available on this server.',
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  if (loading || sending) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 12),
                    Text(
                      t_(
                        sending
                            ? 'Changing group owner...'
                            : 'Loading group ownership...',
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    Text(t_(error!)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: loading || sending ? null : load,
                      child: Text(t_('Reload group')),
                    ),
                  ],
                  if (info != null) ...[
                    Text(t_(info!)),
                    const SizedBox(height: 16),
                  ],
                  if (current != null) ...[
                    Text(
                      current.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(t_('Current owner')),
                    Text(
                      '${_memberName(current.owner)} (@${current.owner['username']})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t_(
                        current.isOwner
                            ? 'Choose another current member to become the owner. This does not remove anyone from the group.'
                            : 'Only the current owner can choose the next owner.',
                      ),
                    ),
                    if (current.isOwner && current.members.length == 1) ...[
                      const SizedBox(height: 12),
                      Text(
                        t_('Add another person before choosing a new owner.'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    for (final member in current.members)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_memberName(member)),
                        subtitle: Text(
                          '@${member['username']}${member['group_role'] == 'owner' ? ' · ${t_('Owner')}' : ''}',
                        ),
                        trailing:
                            current.isOwner &&
                                member['public_id'] !=
                                    widget.session.user?['public_id']
                            ? IconButton(
                                tooltip:
                                    '${t_('Make owner')}: @${member['username']}',
                                onPressed: sending || loading
                                    ? null
                                    : () => choose(current, member),
                                icon: const PhIcon('crown'),
                              )
                            : null,
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
