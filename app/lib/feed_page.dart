import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';

String ago(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
}

class FeedPage extends StatefulWidget {
  const FeedPage({super.key, required this.session});
  final Session session;
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final posts = <Map<String, dynamic>>[];
  final scroll = ScrollController();
  String? cursor;
  bool loading = false;
  bool done = false;
  String? error;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.pixels > scroll.position.maxScrollExtent - 400) _load();
    });
    _load(refresh: true);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (loading || (done && !refresh)) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await widget.session.call('GET', '/posts', query: {if (!refresh && cursor != null) 'cursor': cursor!}) as Map<String, dynamic>;
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      setState(() {
        if (refresh) posts.clear();
        posts.addAll(items);
        cursor = j['next_cursor'] as String?;
        done = cursor == null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _compose() async {
    final p = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => ComposePage(session: widget.session)),
    );
    if (p != null) setState(() => posts.insert(0, p));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _compose, icon: const Icon(Icons.edit), label: const Text('Post')),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: posts.isEmpty
            ? ListView(children: [
                SizedBox(
                  height: 400,
                  child: Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(error ?? 'No posts yet. Tap Post to share the first one.', textAlign: TextAlign.center),
                          ),
                  ),
                ),
              ])
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: posts.length + 1,
                itemBuilder: (context, i) {
                  if (i == posts.length) {
                    if (error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(error!, textAlign: TextAlign.center));
                    return loading ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())) : const SizedBox(height: 8);
                  }
                  final p = posts[i];
                  return PostCard(
                    key: ValueKey(p['public_id']),
                    session: widget.session,
                    post: p,
                    onDeleted: () => setState(() => posts.removeAt(i)),
                  );
                },
              ),
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.session, required this.post, required this.onDeleted});
  final Session session;
  final Map<String, dynamic> post;
  final VoidCallback onDeleted;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool liked = widget.post['liked'] == true;
  late int likes = (widget.post['likes_count'] as num?)?.toInt() ?? 0;
  late int comments = (widget.post['comments_count'] as num?)?.toInt() ?? 0;
  bool busy = false;

  String get id => widget.post['public_id'] as String;

  Future<void> _like() async {
    if (busy) return;
    busy = true;
    final was = liked;
    setState(() {
      liked = !was;
      likes += was ? -1 : 1;
    });
    try {
      final j = await widget.session.call(was ? 'DELETE' : 'POST', '/posts/$id/like') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          liked = j['liked'] == true;
          likes = (j['likes_count'] as num?)?.toInt() ?? likes;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          liked = was;
          likes += was ? 1 : -1;
        });
        showError(context, e);
      }
    } finally {
      busy = false;
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete post?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.session.call('DELETE', '/posts/$id');
      widget.onDeleted();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _comments() async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CommentsSheet(session: widget.session, postId: id),
    );
    if (added != null && added > 0 && mounted) setState(() => comments += added);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final author = (p['author'] as Map).cast<String, dynamic>();
    final mine = author['public_id'] == widget.session.user?['public_id'];
    final media = (p['media'] as List).cast<Map<String, dynamic>>();
    final body = (p['body'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(child: Text((author['username'] ?? '?').toString().characters.first.toUpperCase())),
            title: Text('@${author['username']}'),
            subtitle: Text(ago((p['created_at'] ?? '').toString())),
            trailing: mine
                ? PopupMenuButton<String>(
                    onSelected: (_) => _delete(),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
                  )
                : null,
          ),
          if (body.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(body)),
          for (final m in media)
            if (m['type'] == 'image')
              Image.network(
                m['url'] as String,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (c, child, prog) => prog == null ? child : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                errorBuilder: (c, e, s) => const SizedBox(height: 80, child: Center(child: Text('Image could not load'))),
              )
            else
              VideoTile(url: m['url'] as String),
          Row(
            children: [
              TextButton.icon(
                onPressed: _like,
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Theme.of(context).colorScheme.primary : null),
                label: Text('$likes'),
              ),
              TextButton.icon(onPressed: _comments, icon: const Icon(Icons.mode_comment_outlined), label: Text('$comments')),
            ],
          ),
        ],
      ),
    );
  }
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.session, required this.postId});
  final Session session;
  final String postId;
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final items = <Map<String, dynamic>>[];
  final input = TextEditingController();
  bool loading = true;
  bool sending = false;
  String? error;
  int added = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/posts/${widget.postId}/comments') as Map<String, dynamic>;
      items.addAll((j['data'] as List).cast<Map<String, dynamic>>());
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _send() async {
    final t = input.text.trim();
    if (t.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final j = await widget.session.call('POST', '/posts/${widget.postId}/comments', body: {'body': t}) as Map<String, dynamic>;
      items.add((j['comment'] as Map).cast<String, dynamic>());
      input.clear();
      added++;
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(added);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.all(12), child: Text('Comments', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? Center(child: Text(error ?? 'No comments yet.'))
                        : ListView(
                            children: [
                              for (final c in items)
                                ListTile(
                                  title: Text('@${(c['author'] as Map)['username']}'),
                                  subtitle: Text(c['body'].toString()),
                                  trailing: Text(ago(c['created_at'].toString())),
                                ),
                            ],
                          ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: input, maxLength: 1000, decoration: const InputDecoration(hintText: 'Add a comment', counterText: '', border: OutlineInputBorder()), onSubmitted: (_) => _send())),
                    IconButton(onPressed: sending ? null : _send, icon: const Icon(Icons.send)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComposePage extends StatefulWidget {
  const ComposePage({super.key, required this.session});
  final Session session;
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final text = TextEditingController();
  XFile? picked;
  bool pickedVideo = false;
  bool busy = false;

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (f != null) {
      setState(() {
        picked = f;
        pickedVideo = false;
      });
    }
  }

  Future<void> _pickVideo() async {
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
    if (f == null) return;
    if (await f.length() > 25 * 1024 * 1024) {
      if (mounted) showError(context, 'That video is over 25 MB. Pick a shorter one.');
      return;
    }
    setState(() {
      picked = f;
      pickedVideo = true;
    });
  }

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    return pickedVideo ? 'video/mp4' : 'image/jpeg';
  }

  Future<void> _post() async {
    final body = text.text.trim();
    if (body.isEmpty && picked == null) {
      showError(context, 'Write something or add a photo or video.');
      return;
    }
    setState(() => busy = true);
    try {
      final bytes = picked == null ? null : await picked!.readAsBytes();
      final name = picked?.name ?? 'photo.jpg';
      final post = await widget.session.createPost(body, image: bytes, mime: _mime(name), filename: name, reel: pickedVideo);
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New post'), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton(onPressed: busy ? null : _post, child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Post')),
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: text, maxLines: 6, maxLength: 2000, decoration: const InputDecoration(hintText: 'What is happening? Use #hashtags', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          if (picked != null && pickedVideo)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [const Icon(Icons.videocam), const SizedBox(width: 8), Expanded(child: Text(picked!.name, overflow: TextOverflow.ellipsis))])),
          if (picked != null && !pickedVideo)
            FutureBuilder(
              future: picked!.readAsBytes(),
              builder: (c, s) => s.hasData ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(s.data!, height: 220, fit: BoxFit.cover)) : const SizedBox(height: 220),
            ),
          Row(children: [
            TextButton.icon(onPressed: busy ? null : _pick, icon: const Icon(Icons.photo_outlined), label: Text(picked == null || pickedVideo ? 'Add photo' : 'Change photo')),
            TextButton.icon(onPressed: busy ? null : _pickVideo, icon: const Icon(Icons.videocam_outlined), label: Text(pickedVideo ? 'Change video' : 'Add video')),
            if (picked != null) TextButton(onPressed: busy ? null : () => setState(() => picked = null), child: const Text('Remove')),
          ]),
        ],
      ),
    );
  }
}

/// Streams a video from the media endpoint. Tap to play or pause.
class VideoTile extends StatefulWidget {
  const VideoTile({super.key, required this.url});
  final String url;
  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late final VideoPlayerController c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool ready = false;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    c.initialize().then((_) {
      if (mounted) setState(() => ready = true);
    }).catchError((_) {
      if (mounted) setState(() => failed = true);
    });
    c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) return const SizedBox(height: 80, child: Center(child: Text('Video could not load')));
    if (!ready) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    return GestureDetector(
      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        if (!c.value.isPlaying) const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
      ]),
    );
  }
}
