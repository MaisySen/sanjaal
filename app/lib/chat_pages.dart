import 'ph.dart';
import 'dart:async';
import 'draft_exit_guard.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'call_page.dart';
import 'profile_pages.dart' show UserProfilePage;
import 'calls_page.dart';
import 'rooms_page.dart';
import 'ui.dart';
import 'voice.dart';
import 'share_post.dart';
import 'post_page.dart';
import 'private_media_image.dart';
import 'photo_gallery.dart';

String kindLabel(Object? kind, Object? body) {
  if (kind == 'image') return 'Photo';
  if (kind == 'voice') return 'Voice message';
  if (kind == 'post') return 'Shared a post';
  return '${body ?? ''}';
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, required this.session, this.active = true});
  final Session session;
  final bool active;
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  List<Map<String, dynamic>> convos = [];
  bool loading = true;
  String? error;
  Timer? timer;
  bool showArchived = false;
  int _loadVersion = 0;
  bool? _readingArchive;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 12), (_) { if (widget.active) _load(quiet: true); });
  }

  @override
  void didUpdateWidget(ChatsPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load(quiet: true);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false, bool force = false}) async {
    if(!mounted || (!force && _readingArchive==showArchived)) return;
    final archived=showArchived;
    _readingArchive=archived;
    final version = ++_loadVersion;
    try {
      final j = await widget.session.call('GET', '/conversations', query: showArchived ? {'archived': '1'} : null) as Map<String, dynamic>;
      if (!mounted || version != _loadVersion) return;
      final rows=(j['data'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      if(rows.any((c)=>c['public_id'] is! String || (c['public_id'] as String).trim().isEmpty || (c['last_message']!=null && c['last_message'] is! Map) || (c['unread']!=null && c['unread'] is! num))) throw const FormatException('Invalid inbox');
      setState(() { convos=rows; error=null; });
    } catch (e) {
      if (mounted && version == _loadVersion && !quiet) setState(() => error=e is ApiError?t_(e.message):t_('Chats could not be loaded.'));
    } finally {
      if(version==_loadVersion) _readingArchive=null;
      if (mounted && version == _loadVersion && loading) setState(() => loading = false);
    }
  }

  String _preview(Map<String, dynamic>? last) {
    if (last == null) return t_('No messages yet');
    if(['image','voice','post'].contains(last['kind'])) return t_(kindLabel(last['kind'],last['body']));
    return (last['body']??'').toString();
  }

  Future<void> _menu(Map<String, dynamic> c) async {
    final id = c['public_id'];
    Future<void> set(Map<String, dynamic> body) async {
      Navigator.pop(context);
      try {
        await widget.session.call('PATCH', '/conversations/$id/settings', body: body);
        await _load(quiet: true,force:true);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: PhIcon(c['pinned'] == true ? Ph.push_pin : Ph.push_pin_outlined), title: Text(t_(c['pinned'] == true ? 'Unpin' : 'Pin to top')), onTap: () => set({'pinned': c['pinned'] != true})),
          ListTile(leading: PhIcon(c['muted'] == true ? Ph.notifications_off : Ph.notifications_off_outlined), title: Text(t_(c['muted'] == true ? 'Unmute' : 'Mute')), onTap: () => set({'muted': c['muted'] != true})),
          ListTile(leading: PhIcon(c['archived'] == true ? Ph.unarchive_outlined : Ph.archive_outlined), title: Text(t_(c['archived'] == true ? 'Unarchive' : 'Archive')), onTap: () => set({'archived': c['archived'] != true})),
        ]),
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(session: widget.session, convo: c)));
    _load(quiet: true,force:true);
  }

  Future<void> _new() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => NewChatPage(session: widget.session)));
    if (c != null) {
      await _load(quiet: true,force:true);
      if (mounted) _open(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t_(showArchived ? 'Archived' : 'Chats')),
        actions: [
          IconButton(tooltip: t_('New chat'), icon: const PhIcon('note-pencil'), onPressed: _new),
          PopupMenuButton<String>(
            tooltip: t_('More'),
            onSelected: (_) {
              setState(() {
                showArchived = !showArchived;
                convos = [];
                error = null;
                loading = true;
              });
              _load();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archive', child: Text(t_(showArchived ? 'Back to chats' : 'Archived chats'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if(error!=null && convos.isNotEmpty) RefreshReadNotice(onRetry:()=>_load()),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 4, children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallsPage(session: widget.session))),
              icon: const PhIcon('phone', size: 20), label: Text(t_('Calls')),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomsPage(session: widget.session))),
              icon: const PhIcon('waveform', size: 20), label: Text(t_('Live rooms')),
            ),
          ])),
        ),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(physics:const AlwaysScrollableScrollPhysics(),children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : convos.isEmpty
                ? ListView(physics:const AlwaysScrollableScrollPhysics(),padding: const EdgeInsets.only(bottom: 100), children: [EmptyState(
                    icon: error != null ? Ph.error_outline : Ph.forum,
                    title: error ?? t_(showArchived ? 'No archived chats' : 'Start a conversation'),
                    hint: error != null || showArchived ? null : t_('Find someone by name or username.'),
                    action: error != null
                        ? OutlinedButton(onPressed: _load, child: Text(t_('Try again')))
                        : showArchived ? null : FilledButton.icon(onPressed: _new, icon: const PhIcon('note-pencil', size: 18), label: Text(t_('New chat'))),
                  )])
                : ListView.separated(
                    physics:const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: convos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = convos[i];
                      final last = c['last_message'] as Map<String, dynamic>?;
                      final unread = (c['unread'] as num?)?.toInt() ?? 0;
                      final title = (c['title'] ?? 'Chat').toString();
                      final scheme = Theme.of(context).colorScheme;
                      return InkWell(
                        onTap: () => _open(c),
                        onLongPress: () => _menu(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(children: [
                            c['type'] == 'group'
                                ? CircleAvatar(radius: 24, backgroundColor: scheme.surfaceContainerHigh, child: PhIcon('users-three', color: scheme.onSurfaceVariant))
                                : Avatar(user: {'name': title, 'username': title, 'avatar_url': c['avatar_url']}, radius: 24),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600))),
                                  if (c['pinned'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: PhIcon('push-pin-fill', size: 13, color: scheme.onSurfaceVariant)),
                                  if (c['muted'] == true) Padding(padding: const EdgeInsets.only(left: 4), child: PhIcon('bell-slash', size: 13, color: scheme.onSurfaceVariant)),
                                ]),
                                const SizedBox(height: 2),
                                Text(_preview(last), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? scheme.onSurface : scheme.onSurfaceVariant, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              if (last != null) Text(ago(last['created_at'].toString()), style: TextStyle(fontSize: 12, color: unread > 0 ? scheme.primary : scheme.onSurfaceVariant)),
                              if (unread > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Badge(label: Text('$unread'), backgroundColor: c['muted'] == true ? scheme.outline : scheme.primary, textColor: scheme.onPrimary)),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key, required this.session});
  final Session session;
  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final q = TextEditingController();
  final title = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> results = [];
  final picked = <String, Map<String, dynamic>>{};
  bool group = false, busy = false, searched = false, searching = false;
  bool _completed = false, _uncertain = false;
  String? searchError, startError;
  int _seq = 0;
  bool get _locked => busy || _uncertain;

  @override
  void dispose() {
    ++_seq;
    _debounce?.cancel();
    q.dispose();
    title.dispose();
    super.dispose();
  }

  void _changed(String value) {
    final seq = ++_seq; // Invalidate immediately, not when the debounce fires.
    _debounce?.cancel();
    final query = value.trim();
    setState(() {
      results = [];
      searchError = null;
      searched = false;
      searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query, seq));
  }

  Future<void> _search(String query, int seq) async {
    try {
      final response = await widget.session.call('GET', '/users/search', query: {'q': query});
      final users = ((response as Map)['users'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      if(users.any((u)=>u['username'] is! String || (u['username'] as String).trim().isEmpty)) throw const FormatException('Invalid member identity');
      if (!mounted || seq != _seq) return;
      setState(() { results = users; searched = true; searching = false; searchError = null; });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        searching = false;
        searchError = e is ApiError ? e.message : t_('Could not load members. Try again.');
      });
    }
  }

  Future<void> _leave([Map<String, dynamic>? conversation]) async {
    if (!mounted) return;
    setState(() { _completed = true; busy = false; });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(conversation);
  }

  Future<void> _start(Map<String, dynamic> body) async {
    if (_locked) return;
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    ++_seq;
    setState(() { busy = true; searching = false; startError = null; });
    try {
      final response = await widget.session.call('POST', '/conversations', body: body);
      final conversation = ((response as Map)['conversation'] as Map).cast<String, dynamic>();
      if (conversation['public_id'] is! String || (conversation['public_id'] as String).isEmpty) throw const FormatException();
      if (mounted) await _leave(conversation);
    } catch (e) {
      if (!mounted) return;
      // Groups have no server replay key. A lost/malformed success is not a
      // rejected creation, so do not offer another POST as ordinary retry.
      final rejected = e is ApiError && e.status != null && e.status! >= 400 && e.status! < 500;
      setState(() {
        busy = false;
        _uncertain = !rejected;
        startError = rejected ? e.message : t_('The chat may already exist. Check Chats before starting it again.');
      });
    }
  }

  void _tap(Map<String, dynamic> user) {
    if (_locked) return;
    final name = user['username'].toString();
    if (!group) { _start({'type': 'direct', 'username': name}); return; }
    if (!picked.containsKey(name) && picked.length >= 49) {
      showInfo(context, t_('Choose up to 49 people.'));
      return;
    }
    setState(() => picked.containsKey(name) ? picked.remove(name) : picked[name] = user);
  }

  Future<void> _switchMode() async {
    if (_locked) return;
    if (group && (picked.isNotEmpty || title.text.trim().isNotEmpty)) {
      final discard = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(t_('Discard this group?')),
        content: Text(t_('The name and selected people will be cleared.')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Keep editing'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Discard')))],
      ));
      if (discard != true || !mounted) return;
    }
    setState(() { group = !group; picked.clear(); title.clear(); startError = null; });
  }

  @override
  Widget build(BuildContext context) => DraftExitGuard(
    hasChanges: !_completed && (picked.isNotEmpty || title.text.trim().isNotEmpty),
    busy: busy && !_completed,
    busyMessage: 'Starting the conversation. Please wait.',
    child: Scaffold(
      appBar: AppBar(title: Text(t_(group ? 'New group' : 'New chat')), actions: [
        IconButton(onPressed: _locked ? null : _switchMode, icon: PhIcon(group ? Ph.person : Ph.groups), tooltip: t_(group ? 'One to one' : 'New group')),
      ]),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (group) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: TextField(controller: title, enabled: !_locked, onChanged: (_) => setState(() {}), maxLength: 80, decoration: InputDecoration(labelText: t_('Group name'), border: const OutlineInputBorder()))),
          if (group && picked.isNotEmpty) SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [for (final entry in picked.entries) Padding(padding: const EdgeInsets.only(right: 6), child: InputChip(label: Text('@${entry.key}'), onDeleted: _locked ? null : () => setState(() => picked.remove(entry.key))))])),
          Padding(padding: const EdgeInsets.all(16), child: TextField(controller: q, enabled: !_locked, autofocus: true, onChanged: _changed, decoration: InputDecoration(prefixIcon: const PhIcon('magnifying-glass'), hintText: t_('Search by name or username'), border: const OutlineInputBorder()))),
          if (busy) Padding(padding: const EdgeInsets.all(16), child: Text(t_('Starting the conversation. Please wait.'))),
          if (startError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(startError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_uncertain) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OutlinedButton(onPressed: _leave, child: Text(t_('Back to Chats')))),
          if (searchError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [Text(searchError!, style: TextStyle(color: Theme.of(context).colorScheme.error)), OutlinedButton(onPressed: _locked ? null : () => _changed(q.text), child: Text(t_('Try again')))])),
        ])),
        if (searching) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
        if (!searching && searchError == null && !searched) SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Ph.person_search, title: t_('Find someone to chat with'), hint: t_('Search for a member, then tap them.'))),
        if (!searching && searchError == null && searched && results.isEmpty) SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Ph.search_off, title: t_('No matches'))),
        if (!searching && results.isNotEmpty) SliverList(delegate: SliverChildBuilderDelegate((c, index) {
          final user = results[index];
          return ListTile(leading: Avatar(user: user), title: Text((user['name'] ?? '').toString().isEmpty ? '@${user['username']}' : user['name'].toString()), subtitle: Text('@${user['username']}'), trailing: group ? Checkbox(value: picked.containsKey(user['username'].toString()), onChanged: _locked ? null : (_) => _tap(user)) : null, onTap: _locked ? null : () => _tap(user));
        }, childCount: results.length)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
      bottomNavigationBar: group && picked.isNotEmpty ? Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(
        onPressed: _locked ? null : () {
          if (title.text.trim().isEmpty) { setState(() => startError = t_('Enter a group name.')); return; }
          _start({'type': 'group', 'title': title.text.trim(), 'usernames': picked.keys.toList()});
        }, icon: const PhIcon('check'), label: Text('${t_('Create group')} (${picked.length})'),
      )))) : null,
    ),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.session, required this.convo});
  final Session session;
  final Map<String, dynamic> convo;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final msgs = <Map<String, dynamic>>[];
  final input = TextEditingController();
  final scroll = ScrollController();
  Timer? timer;
  bool loading = true;
  bool fetching = false;
  bool loadingOlder = false;
  bool hasOlder = false;
  int? historyBoundary;
  String? olderError;
  int unseen = 0;
  final historyCenter = const ValueKey('chat-recent-center');
  bool get nearEnd => !scroll.hasClients || scroll.position.extentAfter < 80;
  int get firstSeq => msgs.where((m) => m['seq'] != null).fold(1 << 62, (a, m) => (m['seq'] as num).toInt() < a ? (m['seq'] as num).toInt() : a);

  String? error;
  Map<String, dynamic>? replyTo;
  bool recording = false;
  bool pickingMedia = false;
  List<String> typing = [];
  DateTime _lastTypingPing = DateTime.fromMillisecondsSinceEpoch(0);

  String get id => widget.convo['public_id'] as String;
  int get lastSeq => msgs.where((m) => m['seq'] != null).fold(0, (a, m) => (m['seq'] as num).toInt() > a ? (m['seq'] as num).toInt() : a);

  @override
  void initState() {
    super.initState();
    scroll.addListener(() { if (unseen > 0 && nearEnd && mounted) setState(() => unseen = 0); });
    _loop();
  }

  bool _closed = false;

  // Realtime by long poll: the server holds each request until a new message
  // arrives, so delivery is near instant without a separate socket server.
  Future<void> _loop() async {
    await _fetch();
    if (!mounted || _closed) return;
    // Do not immediately hide a first-load error behind a second read.
    if (error != null) await Future<void>.delayed(const Duration(seconds: 2));
    while (mounted && !_closed) {
      final before = DateTime.now();
      await _fetch(wait: true);
      if (!mounted || _closed) break;
      if (DateTime.now().difference(before) < const Duration(seconds: 2)) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    timer?.cancel();
    scroll.dispose();
    input.dispose();
    super.dispose();
  }

  void _sortMessages() {
    msgs.sort((a, b) {
      final sa = (a['seq'] as num?)?.toInt();
      final sb = (b['seq'] as num?)?.toInt();
      if (sa != null && sb != null) return sa.compareTo(sb);
      if (sa != null) return -1;
      if (sb != null) return 1;
      return a['created_at'].toString().compareTo(b['created_at'].toString());
    });
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        if (unseen != 0) setState(() => unseen = 0);
      }
    });
  }

  Future<void> _older() async {
    if (loadingOlder || !hasOlder || historyBoundary == null) return;
    final before = firstSeq;
    setState(() { loadingOlder = true; olderError = null; });
    try {
      final j = await widget.session.call('GET', '/conversations/$id/messages', query: {'before_seq': '$before'}) as Map<String, dynamic>;
      final page = (j['data'] as List).cast<Map<String, dynamic>>();
      if (page.any((m) => m['seq'] is! num || (m['seq'] as num) >= before)) throw const FormatException('Invalid history cursor');
      if (!mounted) return;
      setState(() {
        final known = msgs.map((m) => m['public_id']).toSet();
        msgs.addAll(page.where((m) => known.add(m['public_id'])));
        _sortMessages();
        hasOlder = page.length >= 50;
      });
      // Older rows grow in the sliver before the center. Its offset stays fixed
      // without guessing text/image heights or moving a user reading history.
    } catch (e) {
      if (mounted) setState(() => olderError = e is ApiError ? e.message : t_('Earlier messages could not be loaded.'));
    } finally { if (mounted) setState(() => loadingOlder = false); }
  }

  Future<void> _fetch({bool wait = false}) async {
    if (fetching) return;
    fetching = true;
    try {
      final first = historyBoundary == null;
      final j = await widget.session.call('GET', '/conversations/$id/messages', query: first ? null : {'after_seq': '$lastSeq', if (wait) 'wait': '20', 'typing': typing.join(',')}) as Map<String, dynamic>;
      final nowTyping = ((j['typing'] as List?) ?? const []).map((e) => e.toString()).toList();
      if (mounted && nowTyping.join(',') != typing.join(',')) setState(() => typing = nowTyping);
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      final follow = nearEnd;
      if (first) {
        final seqs = items.map((m) => (m['seq'] as num?)?.toInt()).whereType<int>();
        historyBoundary = seqs.isEmpty ? 0 : seqs.reduce((a, b) => a < b ? a : b);
        hasOlder = items.length >= 50;
      }
      if (error != null) setState(() => error = null);
      final known = msgs.map((m) => m['public_id']).toSet();
      final fresh = items.where((m) => known.add(m['public_id'])).toList();
      // A server copy replaces the local pending copy that has the same client id.
      final before = msgs.length;
      msgs.removeWhere((m) => (m['pending'] == true || m['failed'] == true) && items.any((s) => s['client_id'] == m['client_id'] && (s['sender'] as Map?)?['public_id'] == (m['sender'] as Map?)?['public_id']));
      if (fresh.isNotEmpty || first || before != msgs.length) {
        setState(() {
          msgs.addAll(fresh);
          _sortMessages();
          error = null;
        });
        if (first || follow) {
          _toEnd();
        } else if (fresh.isNotEmpty) {
          setState(() => unseen += fresh.length);
        }
        widget.session.call('POST', '/conversations/$id/read').catchError((_) => null);
      }
    } catch (e) {
      if (mounted) setState(() => error = e is ApiError ? e.message : t_('Messages could not be loaded.'));
    } finally {
      fetching = false;
      if (mounted && loading) setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    final cid = newUploadIntent();
    final me = widget.session.user!;
    final local = <String, dynamic>{
      'public_id': 'local-$cid',
      'body': t,
      'client_id': cid,
      'pending': true,
      'sender': {'public_id': me['public_id'], 'username': me['username']},
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'kind': 'text',
      if (replyTo != null) 'reply_to': {'public_id': replyTo!['public_id'], 'sender': ((replyTo!['sender'] as Map)['username']).toString(), 'kind': replyTo!['kind'] ?? 'text', 'body': replyTo!['body']},
    };
    replyTo = null;
    setState(() => msgs.add(local));
    _toEnd();
    await _deliver(local);
  }

  Future<void> _deliver(Map<String, dynamic> local) async {
    if (local['pending'] != true) return;
    final cid = local['client_id'];
    final replyId = (local['reply_to'] as Map?)?['public_id'];
    try {
      final file = local['_file'] as UploadFile?;
      final j = file == null
          ? await widget.session.call('POST', '/conversations/$id/messages', body: {'body': local['body'], 'client_id': cid, if (replyId != null) 'reply_to': replyId}) as Map<String, dynamic>
          : await widget.session.upload('/conversations/$id/messages', fields: {'client_id': '$cid', if (replyId != null) 'reply_to': '$replyId'}, file: file);
      final server = (j['message'] as Map).cast<String, dynamic>();
      if (server['public_id'] is! String || server['sender'] is! Map || server['body'] is! String) throw const FormatException('Incomplete message response');
      if (!mounted) return;
      final follow = nearEnd;
      setState(() {
        msgs.removeWhere((m) => m['client_id'] == cid && (m['sender'] as Map?)?['public_id'] == widget.session.user?['public_id']);
        if (!msgs.any((m) => m['public_id'] == server['public_id'])) msgs.add(server);
        _sortMessages();
      });
      if (follow) _toEnd();
    } catch (e) {
      if (!mounted || !msgs.contains(local)) return;
      setState(() {
        local['pending'] = false;
        local['failed'] = true;
        local['unavailable'] = e is ApiError && e.status == 410;
      });
      showError(context, e is ApiError ? e : ApiError(t_('Delivery could not be confirmed.')));
    }
  }

  Future<void> _attach() async {
    if (hasLocalMedia || pickingMedia) return;
    setState(() => pickingMedia = true);
    try {
      final x = await guardPick(context, () => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 78));
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (mounted) {
        setState(() => pickingMedia = false);
        await _sendFile(UploadFile(bytes, mimeFor(x.name), x.name));
      }
    } catch (e) { if (mounted) showError(context, e); }
    finally { if (mounted) setState(() => pickingMedia = false); }
  }

  Future<void> _sendVoice(List<int> bytes) async {
    if (!mounted) return;
    setState(() => recording = false);
    await _sendFile(UploadFile(bytes, 'audio/mp4', 'voice.m4a'));
  }

  bool get hasLocalMedia => msgs.any((m) => m['_file'] is UploadFile);

  Future<void> _sendFile(UploadFile file) async {
    if (!mounted || hasLocalMedia) return;
    final cid = newUploadIntent();
    final me = widget.session.user!;
    final local = <String, dynamic>{
      'public_id': 'local-$cid', 'body': '', 'client_id': cid, 'pending': true,
      'sender': {'public_id': me['public_id'], 'username': me['username']},
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'kind': file.mime.startsWith('audio/') ? 'voice' : 'image',
      // Never persist private attachment bytes or put them into a public URL.
      '_file': UploadFile(Uint8List.fromList(file.bytes).asUnmodifiableView(), file.mime, file.name),
      if (replyTo != null) 'reply_to': {'public_id': replyTo!['public_id'], 'sender': ((replyTo!['sender'] as Map)['username']).toString(), 'kind': replyTo!['kind'] ?? 'text', 'body': replyTo!['body']},
    };
    setState(() { replyTo = null; msgs.add(local); });
    _toEnd();
    await _deliver(local);
  }

  Future<void> _removeMediaCopy(Map<String, dynamic> local) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      scrollable: true, title: Text(t_('Remove retry copy?')),
      content: Text(t_('This removes only the attachment kept on this screen. It does not delete a message that may already be delivered.')),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Remove retry copy')))],
    ));
    if (yes == true && mounted && local['failed'] == true) setState(() => msgs.remove(local));
  }

  void _typingPing() {
    final now = DateTime.now();
    if (now.difference(_lastTypingPing) < const Duration(seconds: 4)) return;
    _lastTypingPing = now;
    widget.session.call('POST', '/conversations/$id/typing').catchError((_) => null);
  }

  Future<void> _messageMenu(Map<String, dynamic> m) async {
    if (m['pending'] == true || m['failed'] == true) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const PhIcon('arrow-bend-up-left'),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => replyTo = m);
            },
          ),
          if ((m['body'] ?? '').toString().isNotEmpty)
            ListTile(
              leading: const PhIcon('copy'),
              title: Text(t_('Copy')),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: m['body'].toString()));
                showInfo(context, 'Copied');
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _retry(Map<String, dynamic> m) async {
    if (!mounted || !msgs.contains(m) || m['failed'] != true || m['pending'] == true || m['unavailable'] == true) return;
    // Retry the immutable original, never the newer composer or its reply.
    setState(() { m['failed'] = false; m['pending'] = true; });
    await _deliver(m);
  }

  void _call(bool video) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallPage(session: widget.session, conversationId: id, title: (widget.convo['title'] ?? 'Call').toString(), video: video),
    ));
  }

  Widget _messageTile(Map<String, dynamic> m, {required bool group, required String? myId}) {
    final mine = (m['sender'] as Map)['public_id'] == myId;
    final failed = m['failed'] == true;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      key: ValueKey(m['public_id']),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: failed && m['unavailable'] != true ? () => _retry(m) : null,
        onLongPress: () => _messageMenu(m),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: failed ? scheme.errorContainer : (mine ? scheme.primary : scheme.surfaceContainerHigh),
            borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(mine ? 20 : 6), bottomRight: Radius.circular(mine ? 6 : 20)),
          ),
          child: DefaultTextStyle.merge(style: TextStyle(color: failed ? scheme.onErrorContainer : (mine ? scheme.onPrimary : scheme.onSurface)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (group && !mine) Text('@${(m['sender'] as Map)['username']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            if (m['reply_to'] is Map)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.primary, width: 3)), color: Colors.black12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(m['reply_to'] as Map)['sender']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(kindLabel((m['reply_to'] as Map)['kind'], (m['reply_to'] as Map)['body']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
            if (m['_file'] is UploadFile) ...[
              if (m['kind'] == 'image') ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory((m['_file'] as UploadFile).bytes as Uint8List, width: 220, height: 160, fit: BoxFit.cover, errorBuilder: (context, error, stack) => const PhIcon('image-broken'))),
              Text(t_(m['kind'] == 'voice' ? 'Voice message' : 'Photo')),
              if (failed) TextButton(onPressed: () => _removeMediaCopy(m), style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer), child: Text(t_('Remove retry copy'))),
            ],
            if (m['kind'] == 'image' && m['media_url'] is String && widget.session.supportsPrivateMedia(m['media_url'] as String))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewer(urls: [m['media_url'] as String], provider: (url) => PrivateMediaImage(widget.session,url)))),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image(image: PrivateMediaImage(widget.session,m['media_url'] as String), width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const PhIcon('image-broken'))),
                ),
              ),
            if (m['kind'] == 'image' && m['media_url'] != null && (m['media_url'] is! String || !widget.session.supportsPrivateMedia(m['media_url'] as String))) Text(t_('This photo is unavailable.')),
            if (m['kind'] == 'post') SharedPostCard(post: (m['shared_post'] as Map?)?.cast<String, dynamic>(), onOpenPost: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostPage(session: widget.session, postId: id))), onOpenAuthor: (u) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: u)))),
            if (m['kind'] == 'voice' && m['media_url'] != null) VoiceBubble(url: m['media_url'] as String, session: widget.session),
            if ((m['body'] ?? '').toString().isNotEmpty) Text(m['body'].toString()),
            Text(failed ? (m['unavailable'] == true ? t_('Original message unavailable.') : t_('Delivery unconfirmed. Tap to retry.')) : (m['pending'] == true ? 'Sending' : ago(m['created_at'].toString())), style: TextStyle(fontSize: 11, color: failed ? scheme.onErrorContainer : (mine ? scheme.onPrimary.withValues(alpha: 0.78) : scheme.onSurfaceVariant))),
          ])),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = widget.session.user?['public_id'];
    final group = widget.convo['type'] == 'group';
    return DraftExitGuard(
      hasChanges: hasLocalMedia, busy: pickingMedia || msgs.any((m) => m['_file'] is UploadFile && m['pending'] == true),
      title: 'Leave chat?', message: 'Leaving removes local retry copies, not messages that may have arrived.',
      keepLabel: 'Stay here', discardLabel: 'Leave', busyMessage: 'Your attachment is still sending.',
      child: Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: group ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupInfoPage(session: widget.session, convo: widget.convo))) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((widget.convo['title'] ?? 'Chat').toString()),
            if (typing.isNotEmpty) Text(group ? '${typing.join(', ')} typing...' : 'typing...', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal))
            else if (group) Text('${(widget.convo['members'] as List?)?.length ?? 0} members', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        actions: [
          IconButton(tooltip: 'Voice call', icon: const PhIcon('phone-fill'), onPressed: () => _call(false)),
          IconButton(tooltip: 'Video call', icon: const PhIcon('video-camera'), onPressed: () => _call(true)),
        ],
      ),
      body: Column(children: [
        if (error != null && msgs.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
          Expanded(child: Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: fetching ? null : () => _fetch(), child: Text(t_('Try again'))),
        ])),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : msgs.isEmpty
                  ? error == null ? const Center(child: Text('Say hello.')) : EmptyState(icon: Ph.cloud_off, title: error!, action: OutlinedButton(onPressed: fetching ? null : () => _fetch(), child: Text(t_('Try again'))))
                  : Builder(builder: (context) {
                      final older = msgs.where((m) => m['seq'] is num && (m['seq'] as num) < (historyBoundary ?? 0)).toList().reversed.toList();
                      final recent = msgs.where((m) => m['seq'] is! num || (m['seq'] as num) >= (historyBoundary ?? 0)).toList();
                      SliverList rows(List<Map<String, dynamic>> data, {Key? key}) => SliverList(key: key, delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(key: ValueKey(data[i]['public_id']), padding: const EdgeInsets.symmetric(horizontal: 12), child: _messageTile(data[i], group: group, myId: myId)),
                        childCount: data.length,
                        findChildIndexCallback: (key) { final i = data.indexWhere((m) => ValueKey(m['public_id']) == key); return i < 0 ? null : i; },
                      ));
                      return Stack(children: [
                        CustomScrollView(key: const ValueKey('chat-history-scroll'), controller: scroll, center: historyCenter, slivers: [
                          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                            if (olderError != null) Text(olderError!),
                            if (loadingOlder) const Center(child: CircularProgressIndicator())
                            else if (hasOlder) TextButton(onPressed: _older, child: Text(t_(olderError == null ? 'Load earlier messages' : 'Try again')))
                            else Text(t_('Start of conversation'), style: Theme.of(context).textTheme.labelMedium),
                          ]))),
                          rows(older),
                          rows(recent, key: historyCenter),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        ]),
                        if (unseen > 0) Positioned(bottom: 8, left: 0, right: 0, child: Center(child: FilledButton.tonalIcon(
                          onPressed: _toEnd, icon: const PhIcon('arrow-down', size: 18), label: Text(t_('New messages')),
                        ))),
                      ]);
                    }),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (replyTo != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(child: Text('Replying to @${(replyTo!['sender'] as Map)['username']}: ${kindLabel(replyTo!['kind'], replyTo!['body'])}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => replyTo = null), icon: const PhIcon('x', size: 18)),
                  ]),
                ),
              if (recording)
                VoiceRecorderBar(
                  onDone: _sendVoice,
                  onCancel: () {
                    if (mounted) setState(() => recording = false);
                  },
                  onError: (msg) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  },
                )
              else
              Row(children: [
                IconButton(tooltip: t_('Attach photo'), onPressed: hasLocalMedia || pickingMedia ? null : _attach, icon: const PhIcon('image')),
                Expanded(child: TextField(controller: input, onChanged: (_) => _typingPing(), minLines: 1, maxLines: 4, maxLength: 4000, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: 'Message', hintMaxLines: 1, counterText: '', filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerHigh, contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
                IconButton(onPressed: hasLocalMedia || pickingMedia ? null : () => setState(() => recording = true), icon: const PhIcon('microphone'), tooltip: 'Voice message'),
                IconButton.filled(tooltip: 'Send message', onPressed: _send, icon: PhIcon('paper-plane-tilt-fill', color: Theme.of(context).colorScheme.onPrimary)),
              ]),
            ]),
          ),
        ),
      ]),
    ));
  }
}

/// Group membership, owner-only rename, invitations and leaving.
class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({super.key, required this.session, required this.convo});
  final Session session;
  final Map<String, dynamic> convo;
  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late List<Map<String, dynamic>> members = ((widget.convo['members'] as List?) ?? const []).cast<Map<String, dynamic>>();
  bool busy = false;
  late String title = (widget.convo['title'] ?? 'Group').toString();
  late final bool isOwner = widget.convo['my_role'] == 'owner';

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _add() async {
    final ctrl = TextEditingController();
    final names = await showDialog<List<String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t_('Add people')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: t_('Usernames, separated by commas'))),
          const SizedBox(height: 12),
          Text(t_('New members see messages from when they join, not earlier ones.'), style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t_('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, [for (final n in ctrl.text.split(RegExp(r'[,\s]+'))) if (n.trim().isNotEmpty) n.trim().replaceFirst('@', '')]),
            child: Text(t_('Add')),
          ),
        ],
      ),
    );
    if (names == null || names.isEmpty) return;
    setState(() => busy = true);
    try {
      final j = await widget.session.call('POST', '/conversations/${widget.convo['public_id']}/members', body: {'usernames': names}) as Map<String, dynamic>;
      final c = j['conversation'] as Map<String, dynamic>;
      if (mounted) setState(() => members = ((c['members'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } on ApiError catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: title);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t_('Rename group')),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 80, decoration: InputDecoration(hintText: t_('Group name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(t_('Save'))),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == title) return;
    setState(() => busy = true);
    try {
      final j = await widget.session.call('PATCH', '/conversations/${widget.convo['public_id']}', body: {'title': name}) as Map<String, dynamic>;
      final c = j['conversation'] as Map<String, dynamic>;
      if (mounted) setState(() => title = (c['title'] ?? name).toString());
    } on ApiError catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t_('Leave this group?')),
        content: Text(t_('You will stop getting its messages. Someone has to add you again to rejoin.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Leave'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await widget.session.call('POST', '/conversations/${widget.convo['public_id']}/leave');
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        _say(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(title: Text(t_('Group info'))),
      body: ListView(children: [
        const SizedBox(height: 16),
        Center(child: CircleAvatar(radius: 44, backgroundColor: scheme.surfaceContainerHigh, child: PhIcon('users-three', size: 40, color: scheme.onSurfaceVariant))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
        Text('${members.length} members', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (isOwner)
          ListTile(
            leading: CircleAvatar(radius: 22, backgroundColor: scheme.surfaceContainerHigh, child: const PhIcon('note-pencil', size: 20)),
            title: Text(t_('Rename group'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: busy ? null : _rename,
          ),
        ListTile(
          leading: CircleAvatar(radius: 22, backgroundColor: scheme.surfaceContainerHigh, child: const PhIcon('plus', size: 20)),
          title: Text(t_('Add people'), style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: busy ? null : _add,
        ),
        for (final m in members)
          ListTile(
            leading: Avatar(user: m, radius: 22),
            title: Text((m['name'] ?? '').toString().isEmpty ? '@${m['username']}' : m['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('@${m['username']}'),
            onTap: m['public_id'] == session.user?['public_id'] ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: session, username: m['username'].toString()))),
          ),
        const SizedBox(height: 8),
        ListTile(
          leading: PhIcon('sign-out', color: scheme.error),
          title: Text(t_('Leave group'), style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
          onTap: busy ? null : _leave,
        ),
        const SizedBox(height: 96),
      ]),
    );
  }
}
