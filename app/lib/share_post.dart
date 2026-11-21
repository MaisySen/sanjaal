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
    showDragHandle: true,
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
  void sessionRetired(){chats=null;error=null;sending=null;loading=false;}

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
    if (loading || !sessionActive) return;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/conversations') as Map<String, dynamic>;
      if (mounted && sessionActive) setState(() => chats = (j['data'] as List).cast<Map<String, dynamic>>());
    } on ApiError catch (e) {
      if (mounted && sessionActive) setState(() => error = t_(e.message));
    } finally {
      if (mounted && sessionActive) setState(() => loading = false);
    }
  }

  Future<void> _send(Map<String, dynamic> c) async {
    if (sending != null || !sessionActive) return;
    setState(() => sending = c['public_id'].toString());
    try {
      await widget.session.call('POST', '/conversations/${c['public_id']}/messages', body: {
        'shared_post': widget.postId,
        'client_id': 'share-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}',
      });
      if (!mounted || !sessionActive) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t_('Sent to')} ${c['title'] ?? ''}')));
    } on ApiError catch (e) {
      if (!mounted || !sessionActive) return;
      setState(() => sending = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_(e.message))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Text(t_('This screen belongs to another signed-in session. Close it and sign in again to continue.'))));
    final list = chats;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text(t_('Share to chat'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)))),
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
                    leading: CircleAvatar(child: Text(((c['title'] ?? '?').toString().isEmpty ? '?' : (c['title'] as String).characters.first.toUpperCase()))),
                    title: Text((c['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: sending == c['public_id'] ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                    onTap: sending == null ? () => _send(c) : null,
                  ),
              ]),
            ),
        ]),
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
