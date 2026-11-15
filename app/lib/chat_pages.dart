import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'call_page.dart';
import 'feed_page.dart' show ago, showError;

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
      final j = await widget.session.call('GET', '/conversations') as Map<String, dynamic>;
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

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(session: widget.session, convo: c)));
    _load(quiet: true);
  }

  Future<void> _new() async {
    final c = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => NewChatDialog(session: widget.session));
    if (c != null) {
      await _load(quiet: true);
      if (mounted) _open(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add_comment), label: const Text('New chat')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : convos.isEmpty
                ? ListView(children: [SizedBox(height: 300, child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error ?? 'No chats yet. Tap New chat and enter a username.', textAlign: TextAlign.center))))])
                : ListView.separated(
                    itemCount: convos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = convos[i];
                      final last = c['last_message'] as Map<String, dynamic>?;
                      final unread = (c['unread'] as num?)?.toInt() ?? 0;
                      final title = (c['title'] ?? 'Chat').toString();
                      return ListTile(
                        leading: CircleAvatar(child: Icon(c['type'] == 'group' ? Icons.groups : Icons.person)),
                        title: Text(title, style: TextStyle(fontWeight: unread > 0 ? FontWeight.bold : null)),
                        subtitle: Text(last == null ? 'No messages yet' : last['body'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (last != null) Text(ago(last['created_at'].toString()), style: const TextStyle(fontSize: 12)),
                          if (unread > 0) Badge(label: Text('$unread')),
                        ]),
                        onTap: () => _open(c),
                      );
                    },
                  ),
      ),
    );
  }
}

class NewChatDialog extends StatefulWidget {
  const NewChatDialog({super.key, required this.session});
  final Session session;
  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  final user = TextEditingController();
  final title = TextEditingController();
  bool group = false;
  bool busy = false;
  String? error;

  Future<void> _go() async {
    final names = user.text.split(RegExp(r'[,\s]+')).map((s) => s.replaceFirst('@', '').trim()).where((s) => s.isNotEmpty).toList();
    if (names.isEmpty) {
      setState(() => error = 'Enter a username.');
      return;
    }
    if (group && title.text.trim().isEmpty) {
      setState(() => error = 'Enter a group name.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final j = await widget.session.call('POST', '/conversations',
          body: group ? {'type': 'group', 'title': title.text.trim(), 'usernames': names} : {'type': 'direct', 'username': names.first}) as Map<String, dynamic>;
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New chat'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Group chat'), value: group, onChanged: busy ? null : (v) => setState(() => group = v)),
        if (group) TextField(controller: title, decoration: const InputDecoration(labelText: 'Group name')),
        TextField(controller: user, autofocus: true, decoration: InputDecoration(labelText: group ? 'Usernames, separated by commas' : 'Username')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _go, child: Text(busy ? 'Starting' : 'Start')),
      ],
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
      final j = await widget.session.call('GET', '/conversations/$id/messages', query: first ? null : {'after_seq': '$lastSeq', if (wait) 'wait': '20'}) as Map<String, dynamic>;
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
    };
    setState(() => msgs.add(local));
    _toEnd();
    try {
      final j = await widget.session.call('POST', '/conversations/$id/messages', body: {'body': t, 'client_id': cid}) as Map<String, dynamic>;
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
        title: Text((widget.convo['title'] ?? 'Chat').toString()),
        actions: [
          IconButton(tooltip: 'Voice call', icon: const Icon(Icons.call), onPressed: () => _call(false)),
          IconButton(tooltip: 'Video call', icon: const Icon(Icons.videocam), onPressed: () => _call(true)),
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
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (group && !mine) Text('@${(m['sender'] as Map)['username']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                Text(m['body'].toString()),
                                Text(failed ? 'Not sent. Tap to retry.' : (m['pending'] == true ? 'Sending' : ago(m['created_at'].toString())), style: TextStyle(fontSize: 10, color: failed ? scheme.error : null)),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, maxLength: 4000, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Message', counterText: '', border: OutlineInputBorder()))),
              IconButton(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
