import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'glass/glass_app_bar.dart';
import 'profile_pages.dart' show UserProfilePage;
import 'session_bound_state.dart';
import 'session_recovery.dart';
import 'ui.dart';

enum FollowListKind { followers, following }

/// Read-only, capability-gated list. Opening it never follows another member.
class FollowListPage extends StatefulWidget {
  const FollowListPage({
    super.key,
    required this.session,
    required this.username,
    required this.kind,
    this.ownerId,
  });
  final Session session;
  final String username;
  final FollowListKind kind;
  final String? ownerId;
  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage>
    with SessionBoundState<FollowListPage> {
  late final String _username = widget.username;
  late final FollowListKind _kind = widget.kind;
  late final String? _ownerId = widget.ownerId;
  @override
  Session get viewSession => widget.session;
  @override
  bool get sessionActive =>
      super.sessionActive &&
      widget.username == _username &&
      widget.kind == _kind &&
      widget.ownerId == _ownerId;
  List<Map<String, dynamic>>? _rows;
  String? _next;
  String? _error;
  bool _busy = false;
  bool _opening = false;
  bool _failedMore = false;
  int _revision = 0;
  @override
  void sessionRetired() {
    _rows = null;
    _next = null;
    _error = null;
    _busy = false;
    _opening = false;
    _revision++;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted ||
        !sessionActive ||
        _busy ||
        !widget.session.followListsEnabled ||
        (more && _next == null)) {
      return;
    }
    final revision = ++_revision;
    final cursor = more ? _next : null;
    setState(() {
      _busy = true;
      _error = null;
      _failedMore = more;
    });
    try {
      final response = await widget.session.call(
        'GET',
        '/users/${Uri.encodeComponent(_username)}/${_kind.name}',
        query: cursor == null ? null : {'cursor': cursor},
      );
      if (response is! Map ||
          response['owner'] is! Map ||
          (response['owner'] as Map)['username'] != _username ||
          (response['owner'] as Map)['public_id'] is! String ||
          ((_ownerId != null) &&
              (response['owner'] as Map)['public_id'] != _ownerId) ||
          response['direction'] != _kind.name ||
          response['data'] is! List ||
          (response['data'] as List).length > 30 ||
          (response['next_cursor'] != null &&
              (response['next_cursor'] is! String ||
                  (response['next_cursor'] as String).isEmpty ||
                  (response['next_cursor'] as String).length > 2048 ||
                  response['next_cursor'] == cursor))) {
        throw const FormatException('Invalid member list');
      }
      final page = <Map<String, dynamic>>[];
      for (final value in response['data'] as List) {
        if (value is! Map ||
            value['public_id'] is! String ||
            (value['public_id'] as String).isEmpty ||
            value['username'] is! String ||
            !RegExp(r'^[A-Za-z0-9_.]{3,30}$')
                .hasMatch(value['username'] as String) ||
            (value['name'] != null && value['name'] is! String) ||
            (value['avatar_url'] != null && value['avatar_url'] is! String)) {
          throw const FormatException('Invalid member');
        }
        page.add({
          for (final key in [
            'public_id',
            'username',
            'name',
            'bio',
            'avatar_url',
          ])
            key: value[key],
        });
      }
      if (!mounted || !sessionActive || revision != _revision) return;
      final seen = <String>{};
      final merged = [
        ...(more
            ? _rows ?? <Map<String, dynamic>>[]
            : <Map<String, dynamic>>[]),
        ...page,
      ].where((u) => seen.add(u['public_id'] as String)).toList();
      setState(() {
        _rows = merged;
        _next = response['next_cursor'] as String?;
      });
    } catch (error) {
      if (mounted && sessionActive && revision == _revision) {
        setState(
          () => _error = error is ApiError && error.status == 404
              ? t_('This member list is unavailable.')
              : t_('Member list could not be loaded.'),
        );
      }
    } finally {
      if (mounted && sessionActive && revision == _revision) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return SessionRecoveryView(session: widget.session);
    if (!widget.session.followListsEnabled) {
      return Scaffold(
        appBar: ReviewedAppBar(
          title: Text(
            t_(_kind == FollowListKind.followers ? 'Followers' : 'Following'),
          ),
        ),
        body: Center(child: Text(t_('This member list is unavailable.'))),
      );
    }
    return Scaffold(
      appBar: ReviewedAppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(40).clamp(56, 96),
        title: Text(
          t_(_kind == FollowListKind.followers ? 'Followers' : 'Following'),
          maxLines: 2,
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: t_('Refresh'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _rows == null && _busy
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: (_rows?.length ?? 0) + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('@$_username'),
                          ),
                        ),
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null && !_failedMore)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _load(more: _failedMore),
                                  child: Text(t_('Try again')),
                                ),
                              ],
                            ),
                          ),
                        if (_rows != null && _rows!.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              t_(
                                _kind == FollowListKind.followers
                                    ? 'No followers to show'
                                    : 'No followed members to show',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    );
                  }
                  if (index > (_rows?.length ?? 0)) {
                    if (_error != null && _failedMore) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                              onPressed: _busy ? null : () => _load(more: true),
                              child: Text(t_('Try again')),
                            ),
                          ],
                        ),
                      );
                    }
                    return _next != null && _error == null
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                if (_busy) const LinearProgressIndicator(),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _load(more: true),
                                  child: Text(t_('Load more')),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink();
                  }
                  final member = _rows![index - 1];
                  return ListTile(
                    key: ValueKey(member['public_id']),
                    leading: Avatar(user: member),
                    title: Text('@${member['username']}'),
                    subtitle: (member['name'] as String? ?? '').isEmpty
                        ? null
                        : Text(member['name'] as String),
                    onTap: () async {
                      if (!mounted || !sessionActive || _busy || _opening) {
                        return;
                      }
                      _opening = true;
                      try {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserProfilePage(
                              session: widget.session,
                              username: member['username'] as String,
                            ),
                          ),
                        );
                      } finally {
                        if (mounted && sessionActive) {
                          _opening = false;
                          await _load();
                        }
                      }
                    },
                  );
                },
              ),
            ),
    );
  }
}
