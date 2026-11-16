import 'ph.dart';
import 'dart:async';
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

String kindLabel(Object? kind, Object? body) {
  if (kind == 'image') return 'Photo';
  if (kind == 'voice') return 'Voice message';
  if (kind == 'post') return 'Shared a post';
  return '${body ?? ''}';
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, required this.session});
  final Session session;
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  List<Map<String, dynamic>> convos = [];
  bool loading = true;
  String? error;
  Timer? timer;
  bool showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 12), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final j = await widget.session.call('GET', '/conversations', query: showArchived ? {'archived': '1'} : null) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        convos = (j['data'] as List).cast<Map<String, dynamic>>();
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted && !quiet) setState(() => error = e.message);
    }
    if (mounted && loading) setState(() => loading = false);
  }

  String _preview(Map<String, dynamic>? last) {
    if (last == null) return 'No messages yet';
    switch (last['kind']) {
      case 'image':
        return 'Photo';
      case 'voice':
        return 'Voice message';
    }
    return last['body'].toString();
  }

  Future<void> _menu(Map<String, dynamic> c) async {
    final id = c['public_id'];
    Future<void> set(Map<String, dynamic> body) async {
      Navigator.pop(context);
      try {
        await widget.session.call('PATCH', '/conversations/$id/settings', body: body);
        await _load(quiet: true);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: PhIcon(c['pinned'] == true ? Ph.push_pin : Ph.push_pin_outlined), title: Text(c['pinned'] == true ? 'Unpin' : 'Pin to top'), onTap: () => set({'pinned': c['pinned'] != true})),
          ListTile(leading: PhIcon(c['muted'] == true ? Ph.notifications_off : Ph.notifications_off_outlined), title: Text(c['muted'] == true ? 'Unmute' : 'Mute'), onTap: () => set({'muted': c['muted'] != true})),
          ListTile(leading: PhIcon(c['archived'] == true ? Ph.unarchive_outlined : Ph.archive_outlined), title: Text(c['archived'] == true ? 'Unarchive' : 'Archive'), onTap: () => set({'archived': c['archived'] != true})),
        ]),
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(session: widget.session, convo: c)));
    _load(quiet: true);
  }

  Future<void> _new() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => NewChatPage(session: widget.session)));
    if (c != null) {
      await _load(quiet: true);
      if (mounted) _open(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(showArchived ? 'Archived' : t_('Chats')),
        actions: [
          IconButton(tooltip: t_('New chat'), icon: const PhIcon('note-pencil'), onPressed: _new),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'rooms') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomsPage(session: widget.session)));
              } else if (v == 'calls') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallsPage(session: widget.session)));
              } else {
                setState(() {
                  showArchived = !showArchived;
                  loading = true;
                });
                _load();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rooms', child: Text(t_('Live rooms'))),
              const PopupMenuItem(value: 'calls', child: Text('Call history')),
              PopupMenuItem(value: 'archive', child: Text(showArchived ? 'Back to chats' : 'Archived chats')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : convos.isEmpty
                ? ListView(children: [SizedBox(height: 300, child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error ?? 'No chats yet. Tap New chat to find someone.', textAlign: TextAlign.center))))])
                : ListView.separated(
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
      ),
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
  bool group = false;
  bool busy = false;
  bool searched = false;
  String? error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        results = [];
        searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final seq = ++_seq;
      try {
        final j = await widget.session.call('GET', '/users/search', query: {'q': v.trim()}) as Map<String, dynamic>;
        if (mounted && seq == _seq) {
          setState(() {
            results = (j['users'] as List).cast<Map<String, dynamic>>();
            searched = true;
            error = null;
          });
        }
      } on ApiError catch (e) {
        if (mounted && seq == _seq) setState(() => error = e.message);
      }
    });
  }

  Future<void> _start(Map<String, dynamic> body) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final j = await widget.session.call('POST', '/conversations', body: body) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop((j['conversation'] as Map).cast<String, dynamic>());
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
        });
      }
    }
  }

  void _tap(Map<String, dynamic> u) {
    final name = u['username'].toString();
    if (!group) {
      _start({'type': 'direct', 'username': name});
      return;
    }
    setState(() => picked.containsKey(name) ? picked.remove(name) : picked[name] = u);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group ? 'New group' : t_('New chat')),
        actions: [
          TextButton.icon(
            onPressed: busy ? null : () => setState(() { group = !group; picked.clear(); }),
            icon: PhIcon(group ? Ph.person : Ph.groups),
            label: Text(group ? 'One to one' : 'New group'),
          ),
        ],
      ),
      body: Column(children: [
        if (group)
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: TextField(controller: title, maxLength: 80, decoration: const InputDecoration(labelText: 'Group name', border: OutlineInputBorder()))),
        if (group && picked.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final e in picked.entries)
                Padding(padding: const EdgeInsets.only(right: 6), child: InputChip(label: Text('@${e.key}'), onDeleted: () => setState(() => picked.remove(e.key)))),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(controller: q, autofocus: true, onChanged: _changed, decoration: const InputDecoration(prefixIcon: PhIcon('magnifying-glass'), hintText: 'Search by name or username', border: OutlineInputBorder())),
        ),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(
          child: !searched
              ? const EmptyState(icon: Ph.person_search, title: 'Find someone to chat with', hint: 'Search for a member, then tap them.')
              : results.isEmpty
                  ? const EmptyState(icon: Ph.search_off, title: 'No matches')
                  : ListView(children: [
                      for (final u in results)
                        ListTile(
                          leading: Avatar(user: u),
                          title: Text((u['name'] ?? '').toString().isEmpty ? '@${u['username']}' : u['name'].toString()),
                          subtitle: Text('@${u['username']}'),
                          trailing: group ? Checkbox(value: picked.containsKey(u['username'].toString()), onChanged: (_) => _tap(u)) : null,
                          onTap: busy ? null : () => _tap(u),
                        ),
                    ]),
        ),
      ]),
      floatingActionButton: group && picked.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: busy
                  ? null
                  : () {
                      if (title.text.trim().isEmpty) {
                        setState(() => error = 'Enter a group name.');
                        return;
                      }
                      _start({'type': 'group', 'title': title.text.trim(), 'usernames': picked.keys.toList()});
                    },
              icon: const PhIcon('check'),
              label: Text('Create group (${picked.length})'),
            )
          : null,
    );
  }
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
  String? error;
  int _n = 0;
  Map<String, dynamic>? replyTo;
  bool recording = false;
  List<String> typing = [];
  DateTime _lastTypingPing = DateTime.fromMillisecondsSinceEpoch(0);

  String get id => widget.convo['public_id'] as String;
  int get lastSeq => msgs.where((m) => m['seq'] != null).fold(0, (a, m) => (m['seq'] as num).toInt() > a ? (m['seq'] as num).toInt() : a);

  @override
  void initState() {
    super.initState();
    _loop();
  }

  bool _closed = false;

  // Realtime by long poll: the server holds each request until a new message
  // arrives, so delivery is near instant without a separate socket server.
  Future<void> _loop() async {
    await _fetch();
    while (mounted && !_closed) {
      final before = DateTime.now();
      await _fetch(wait: true);
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
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
    });
  }

  Future<void> _fetch({bool wait = false}) async {
    if (fetching) return;
    fetching = true;
    try {
      final first = msgs.isEmpty;
      final j = await widget.session.call('GET', '/conversations/$id/messages', query: first ? null : {'after_seq': '$lastSeq', if (wait) 'wait': '20', 'typing': typing.join(',')}) as Map<String, dynamic>;
      final nowTyping = ((j['typing'] as List?) ?? const []).map((e) => e.toString()).toList();
      if (mounted && nowTyping.join(',') != typing.join(',')) setState(() => typing = nowTyping);
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      final known = msgs.map((m) => m['public_id']).toSet();
      final fresh = items.where((m) => !known.contains(m['public_id'])).toList();
      // A server copy replaces the local pending copy that has the same client id.
      msgs.removeWhere((m) => m['pending'] == true && items.any((s) => s['client_id'] == m['client_id']));
      if (fresh.isNotEmpty || first) {
        setState(() {
          msgs.addAll(fresh);
          error = null;
        });
        _toEnd();
        widget.session.call('POST', '/conversations/$id/read').catchError((_) => null);
      }
    } on ApiError catch (e) {
      if (mounted && msgs.isEmpty) setState(() => error = e.message);
    } finally {
      fetching = false;
      if (mounted && loading) setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    final cid = '${DateTime.now().microsecondsSinceEpoch}-${_n++}';
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
    final replyId = replyTo?['public_id'];
    replyTo = null;
    setState(() => msgs.add(local));
    _toEnd();
    try {
      final j = await widget.session.call('POST', '/conversations/$id/messages', body: {'body': t, 'client_id': cid, if (replyId != null) 'reply_to': replyId}) as Map<String, dynamic>;
      final server = (j['message'] as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        msgs.removeWhere((m) => m['client_id'] == cid);
        if (!msgs.any((m) => m['public_id'] == server['public_id'])) msgs.add(server);
      });
      _toEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        local['pending'] = false;
        local['failed'] = true;
      });
      showError(context, e);
    }
  }

  Future<void> _attach() async {
    final x = await guardPick(context, () => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 78));
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    await _sendFile(UploadFile(bytes, mimeFor(x.name), x.name));
  }

  Future<void> _sendVoice(List<int> bytes) async {
    setState(() => recording = false);
    await _sendFile(UploadFile(bytes, 'audio/mp4', 'voice.m4a'));
  }

  Future<void> _sendFile(UploadFile file) async {
    final cid = '${DateTime.now().microsecondsSinceEpoch}-${_n++}';
    final replyId = replyTo?['public_id'];
    setState(() => replyTo = null);
    try {
      final j = await widget.session.upload('/conversations/$id/messages', fields: {'client_id': cid, if (replyId != null) 'reply_to': '$replyId'}, file: file);
      final server = (j['message'] as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        if (!msgs.any((m) => m['public_id'] == server['public_id'])) msgs.add(server);
      });
      _toEnd();
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
    setState(() => msgs.remove(m));
    input.text = m['body'].toString();
    await _send();
  }

  void _call(bool video) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallPage(session: widget.session, conversationId: id, title: (widget.convo['title'] ?? 'Call').toString(), video: video),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final myId = widget.session.user?['public_id'];
    final group = widget.convo['type'] == 'group';
    return Scaffold(
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
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : msgs.isEmpty
                  ? Center(child: Text(error ?? 'Say hello.'))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        final mine = (m['sender'] as Map)['public_id'] == myId;
                        final failed = m['failed'] == true;
                        final scheme = Theme.of(context).colorScheme;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: failed ? () => _retry(m) : null,
                            onLongPress: () => _messageMenu(m),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: mine ? scheme.primary : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(mine ? 20 : 6), bottomRight: Radius.circular(mine ? 6 : 20)),
                              ),
                              child: DefaultTextStyle.merge(style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                                if (m['kind'] == 'image' && m['media_url'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: GestureDetector(
                                      onTap: () => openImage(context, m['media_url'] as String, headers: widget.session.mediaHeaders),
                                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(m['media_url'] as String, headers: widget.session.mediaHeaders, width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const PhIcon('image-broken'))),
                                    ),
                                  ),
                                if (m['kind'] == 'post') SharedPostCard(post: (m['shared_post'] as Map?)?.cast<String, dynamic>(), onOpenAuthor: (u) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: u)))),
                                if (m['kind'] == 'voice' && m['media_url'] != null) VoiceBubble(url: m['media_url'] as String, session: widget.session),
                                if ((m['body'] ?? '').toString().isNotEmpty) Text(m['body'].toString()),
                                Text(failed ? 'Not sent. Tap to retry.' : (m['pending'] == true ? 'Sending' : ago(m['created_at'].toString())), style: TextStyle(fontSize: 11, color: failed ? (mine ? const Color(0xFFB3261E) : scheme.error) : (mine ? scheme.onPrimary.withValues(alpha: 0.78) : scheme.onSurfaceVariant))),
                              ])),
                            ),
                          ),
                        );
                      },
                    ),
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
                IconButton(onPressed: _attach, icon: const PhIcon('image')),
                Expanded(child: TextField(controller: input, onChanged: (_) => _typingPing(), minLines: 1, maxLines: 4, maxLength: 4000, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: 'Message', counterText: '', filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerHigh, contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
                IconButton(onPressed: () => setState(() => recording = true), icon: const PhIcon('microphone'), tooltip: 'Voice message'),
                IconButton.filled(tooltip: 'Send message', onPressed: _send, icon: PhIcon('paper-plane-tilt-fill', color: Theme.of(context).colorScheme.onPrimary)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Group info: the group name and who is in it. Adding people and leaving are not available yet, so they are not offered.
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
    final convo = widget.convo;
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
