import 'glass/glass_sheet.dart';
import 'feed_page.dart' show feedImageProvider;
import 'ph.dart';
import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'session_bound_state.dart';
import 'ui.dart';

/// Pick a chat and send a post into it. Nothing is sent until a chat is tapped.
Future<void> shareToChat(BuildContext context, Session session, String postId) async {
  await showReviewedGlassSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: false,
    builder: (_) => _ShareSheet(session: session, postId: postId),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.session, required this.postId});
  final Session session;
  final String postId;
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> with SessionBoundState<_ShareSheet> {
  @override
  Session get viewSession=>widget.session;
  @override
  void sessionRetired(){
    chats=null;error=null;sending=null;loading=false;_pendingChat=null;_clientId=null;sendError=null;
    final dialog = _closeDialog;
    if (dialog != null && dialog.mounted && ModalRoute.of(dialog)?.isCurrent == true) {
      Navigator.of(dialog).pop(false);
    }
  }

  BuildContext? _closeDialog;
  Map<String, dynamic>? _pendingChat;
  String? _clientId;
  String? sendError;
  bool _closing = false;
  bool _allowClose = false;

  Future<void> _close() async {
    if (!mounted || _closing) return;
    if (sending != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('Sharing is still in progress.'))));
      return;
    }
    if (_pendingChat != null) {
      _closing = true;
      final leave = await showDialog<bool>(context: context, builder: (c) { _closeDialog = c; return AlertDialog(
        scrollable: true,
        title: Text(t_('Close without confirming delivery?')),
        content: Text(t_('Check the original chat before sharing this post again. This screen will not keep the retry.')),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(t_('Keep checking'))),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: Text(t_('Close'))),
        ],
      ); });
      _closeDialog = null;
      _closing = false;
      if (!mounted || !sessionActive || leave != true) return;
    }
    if (!mounted) return;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  List<Map<String, dynamic>>? chats;
  String? error;
  String? sending;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || loading || !sessionActive || _pendingChat != null) return;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/conversations') as Map<String, dynamic>;
      final rows = (j['data'] as List).map((v) => (v as Map).cast<String, dynamic>()).toList();
      final ids = <String>{};
      if (rows.any((c) => c['public_id'] is! String || (c['public_id'] as String).trim().isEmpty ||
          c['title'] is! String || (c['title'] as String).trim().isEmpty || !ids.add(c['public_id'] as String))) {
        throw const FormatException('Invalid share recipients');
      }
      if (mounted && sessionActive) setState(() => chats = rows);
    } catch (e) {
      if (mounted && sessionActive) setState(() => error = e is ApiError ? t_(e.message) : t_('Chats could not be loaded.'));
    } finally {
      if (mounted && sessionActive) setState(() => loading = false);
    }
  }

  Future<void> _send(Map<String, dynamic> c) async {
    if (!mounted || !sessionActive || sending != null || loading || _closing || _allowClose ||
        ModalRoute.of(context)?.isCurrent != true ||
        !(chats?.any((row) => identical(row, c)) ?? false) ||
        (_pendingChat != null && _pendingChat!['public_id'] != c['public_id'])) {
      return;
    }
    final recipient = c['public_id'] as String;
    final owner = widget.session.user?['public_id'];
    _clientId ??= 'share-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    final client = _clientId!;
    setState(() {
      _pendingChat ??= Map.unmodifiable(c);
      sending = recipient;
      sendError = null;
    });
    try {
      final result = await widget.session.call('POST', '/conversations/$recipient/messages', body: {
        'shared_post': widget.postId,
        'client_id': client,
      });
      if (!mounted || !sessionActive) return;
      final message = result is Map ? result['message'] : null;
      final preview = message is Map ? message['shared_post'] : null;
      if (message is! Map || message['public_id'] is! String || (message['public_id'] as String).trim().isEmpty ||
          message['conversation_id'] != recipient || message['client_id'] != client || message['kind'] != 'post' ||
          message['sender'] is! Map || (message['sender'] as Map)['public_id'] != owner ||
          (preview != null && (preview is! Map || preview['public_id'] != widget.postId))) {
        throw const FormatException('Unconfirmed share receipt');
      }
      final messenger = ScaffoldMessenger.of(context);
      final title = _pendingChat!['title'] as String;
      setState(() { sending = null; _pendingChat = null; _clientId = null; _allowClose = true; });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !sessionActive || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('${t_('Sent to')} $title')));
    } catch (e) {
      if (!mounted || !sessionActive) return;
      setState(() {
        sending = null;
        sendError = e is ApiError ? t_(e.message) : t_('Could not confirm the result. Check before trying again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Text(t_('This screen belongs to another signed-in session. Close it and sign in again to continue.'))));
    final list = chats;
    return PopScope(
      canPop: _allowClose || (_pendingChat == null && sending == null),
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
      child: SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 8, 8), child: Row(children: [
            Expanded(child: Text(t_('Share to chat'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(tooltip: t_('Close'), onPressed: _close, icon: const PhIcon('x')),
          ])),
          if (sendError != null) Flexible(child: SingleChildScrollView(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(children: [
              Text(t_('Delivery unconfirmed. Tap to retry.'), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(sendError!, textAlign: TextAlign.center),
            ]),
          ))),
          if (error != null) Flexible(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(t_('Try again'))),
          ]))))
          else if (list == null) const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
          else if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t_('You have no chats yet. Start one from Chats.')))
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in list)
                  ListTile(
                    enabled: sending == null && (_pendingChat == null || _pendingChat!['public_id'] == c['public_id']),
                    leading: CircleAvatar(child: Text(((c['title'] ?? '?').toString().isEmpty ? '?' : (c['title'] as String).characters.first.toUpperCase()))),
                    title: Text((c['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: sending == null && _pendingChat?['public_id'] == c['public_id'] ? Text(t_('Try again')) : null,
                    trailing: sending == c['public_id'] ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                    onTap: sending == null && (_pendingChat == null || _pendingChat!['public_id'] == c['public_id']) ? () => _send(c) : null,
                  ),
              ]),
            ),
        ]),
      ),
      ),
    );
  }
}

/// The card shown in a chat bubble for a shared post. A missing preview (deleted, or the author is blocked) says so.
class SharedPostCard extends StatelessWidget {
  const SharedPostCard({super.key, required this.post, this.onOpenAuthor, this.onOpenPost});
  final Map<String, dynamic>? post;
  final void Function(String username)? onOpenAuthor;
  final void Function(String postId)? onOpenPost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = post;
    if (p == null) {
      return Container(
        width: 230,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          PhIcon('info', size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(t_('A post was shared here. It is no longer available.'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
        ]),
      );
    }
    final author = (p['author'] as Map).cast<String, dynamic>();
    final name = (author['name'] ?? '').toString().isEmpty ? '@${author['username']}' : author['name'].toString();
    final img = p['image_url'] as String?;
    return GestureDetector(
      onTap: onOpenPost != null ? () => onOpenPost!(p['public_id'].toString()) : onOpenAuthor == null ? null : () => onOpenAuthor!(author['username'].toString()),
      child: Container(
        width: 230,
        margin: const EdgeInsets.only(bottom: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (img != null) Image(image: (feedImageProvider ?? NetworkImage.new)(img), height: 130, width: 230, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 60)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
              if ((p['excerpt'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p['excerpt'].toString(), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface))),
            ]),
          ),
        ]),
      ),
    );
  }
}
