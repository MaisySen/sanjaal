import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'draft_exit_guard.dart';
import 'ph.dart';
import 'ui.dart';

/// Owner-only list. Saving is confirmed by the API, never by a local toggle.
class StoryAudiencePage extends StatefulWidget {
  const StoryAudiencePage({super.key, required this.session});
  final Session session;
  @override
  State<StoryAudiencePage> createState() => _StoryAudiencePageState();
}

class _StoryAudiencePageState extends State<StoryAudiencePage> {
  final username = TextEditingController();
  List<Map<String, dynamic>> members = [];
  String? cursor;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    username.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    final owner = widget.session.user?['public_id'];
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.session.call(
        'GET',
        '/auth/me/story-audience',
        query: more && cursor != null ? {'cursor': cursor!} : null,
      ) as Map;
      final values = (result['data'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (!mounted || owner != widget.session.user?['public_id']) return;
      setState(() {
        members = more ? [...members, ...values] : values;
        cursor = result['next_cursor'] as String?;
      });
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is ApiError
              ? e.message
              : t_('Story audience could not be loaded.'),
        );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit(String name) async {
    name = name.trim().replaceFirst(RegExp(r'^@'), '');
    if (name.isEmpty || loading) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _StoryPersonPage(session: widget.session, username: name),
      ),
    );
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t_('Story audience'))),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          t_(
            'Choose close friends or hide your protected stories from someone. This applies to active protected stories and future protected stories.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t_(
            'Earlier public stories and copies people saved cannot be made private. These settings do not change posts, reels or chats.',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: username,
          enabled: !loading,
          decoration: InputDecoration(
            labelText: t_('Exact username'),
            prefixText: '@',
          ),
          onSubmitted: edit,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: loading ? null : () => edit(username.text),
            child: Text(t_('Find person')),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(error!),
          TextButton(
            onPressed: loading ? null : load,
            child: Text(t_('Try again')),
          ),
        ],
        if (!loading && error == null && members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(t_('No story audience changes yet.')),
          ),
        for (final member in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('@${(member['user'] as Map)['username']}'),
            subtitle: Text(
              t_(
                member['hide_story'] == true
                    ? 'Hidden from stories'
                    : member['close_friend'] == true
                    ? 'Close friend'
                    : 'No extra restrictions',
              ),
            ),
            trailing: const PhIcon('caret-right', size: 18),
            onTap: loading
                ? null
                : () => edit((member['user'] as Map)['username'] as String),
          ),
        if (cursor != null)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: Text(t_('Load more')),
          ),
      ],
    ),
  );
}

class _StoryPersonPage extends StatefulWidget {
  const _StoryPersonPage({required this.session, required this.username});
  final Session session;
  final String username;
  @override
  State<_StoryPersonPage> createState() => _StoryPersonPageState();
}

class _StoryPersonPageState extends State<_StoryPersonPage> {
  Map<String, dynamic>? current;
  bool close = false,
      hide = false,
      loading = false,
      saving = false,
      needsReload = false,
      saved = false;
  String? error;
  bool get changed =>
      current != null &&
      (close != current!['close_friend'] || hide != current!['hide_story']);
  String get path =>
      '/auth/me/story-audience/${Uri.encodeComponent(widget.username)}';
  Map<String, dynamic> parse(dynamic response) {
    final m = (response as Map)['member'];
    if (m is! Map ||
        m['revision'] is! int ||
        m['close_friend'] is! bool ||
        m['hide_story'] is! bool ||
        (m['user'] as Map?)?['username'] != widget.username)
      throw const FormatException();
    return m.cast<String, dynamic>();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading || saving) return;
    final owner = widget.session.user?['public_id'];
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final m = parse(await widget.session.call('GET', path));
      if (!mounted || owner != widget.session.user?['public_id']) return;
      setState(() {
        current = m;
        close = m['close_friend'];
        hide = m['hide_story'];
        needsReload = false;
        saved = false;
      });
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is ApiError
              ? e.message
              : t_('Story audience could not be loaded.'),
        );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!changed || loading || saving || needsReload) return;
    final owner = widget.session.user?['public_id'];
    final body = {
      'revision': current!['revision'],
      'close_friend': close,
      'hide_story': hide,
    };
    setState(() {
      saving = true;
      error = null;
      saved = false;
    });
    try {
      final m = parse(await widget.session.call('PUT', path, body: body));
      if (!mounted || owner != widget.session.user?['public_id']) return;
      setState(() {
        current = m;
        close = m['close_friend'];
        hide = m['hide_story'];
        saved = true;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          needsReload = true;
          error = e is ApiError
              ? e.message
              : t_(
                  'Save result is unconfirmed. Reload before making another change.',
                );
        });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = current != null && !loading && !saving && !needsReload;
    return DraftExitGuard(
      hasChanges: changed,
      busy: saving,
      busyMessage: 'Your story audience is still being saved.',
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '@${widget.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: enabled && changed ? save : null,
              child: Text(t_('Save')),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (loading || saving) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: loading || saving ? null : load,
                child: Text(
                  t_(needsReload ? 'Reload current settings' : 'Try again'),
                ),
              ),
            ],
            if (saved) Text(t_('Story audience saved.')),
            if (current != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t_('Close friend')),
                subtitle: Text(
                  t_(
                    'Can see stories shared with Close friends, even without following you.',
                  ),
                ),
                value: close,
                onChanged: enabled
                    ? (v) => setState(() {
                        close = v;
                        saved = false;
                      })
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t_('Hide my stories')),
                subtitle: Text(
                  t_(
                    'Cannot view your protected stories, including Close friends stories.',
                  ),
                ),
                value: hide,
                onChanged: enabled
                    ? (v) => setState(() {
                        hide = v;
                        saved = false;
                      })
                    : null,
              ),
              Text(
                t_(
                  'Blocking still takes priority. Earlier public links and saved copies are not removed.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
