import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';
import 'actions.dart';
import 'gifts.dart';
import 'api.dart';
import 'glass/glass.dart';
import 'notifications_page.dart';
import 'profile_pages.dart';
import 'search_page.dart';
import 'reactions.dart';
import 'stories_page.dart';
import 'ui.dart';

/// Home tab: For you and Following, with search and notifications on top.
///
/// The feed is the Instagram post layout: a header row with a 32px avatar,
/// name and time, the caption, full bleed media, then the action row. Double
/// tap on the media likes with a spring heart, the TikTok rule. Comments open
/// in a glass sheet at 60 percent of the viewport, the TikTok comments height.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key, required this.session, required this.onCompose});
  final Session session;
  final Future<void> Function() onCompose;
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  bool _scrolledUnder = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis != Axis.vertical) return false;
              final under = n.metrics.pixels > 8;
              if (under != _scrolledUnder) setState(() => _scrolledUnder = under);
              return false;
            },
            child: Scaffold(
              appBar: GlassAppBar(
                title: Row(children: [const Logo(size: 26), const SizedBox(width: 8), Text('Sanjaal', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 17, color: Theme.of(context).colorScheme.onSurface))]),
                largeTitle: Row(children: [const Logo(size: 32), const SizedBox(width: 10), Text('Sanjaal', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 28, color: Theme.of(context).colorScheme.onSurface))]),
                actions: [
                  IconButton(tooltip: t_('Post'), icon: const Icon(Icons.add_box_outlined), onPressed: widget.onCompose),
                  IconButton(tooltip: t_('Search'), icon: const Icon(Icons.search), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(session: session)))),
                  IconButton(tooltip: t_('Notifications'), icon: const Icon(Icons.notifications_none), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsPage(session: session)))),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: AnimatedBuilder(
                    animation: tabController,
                    builder: (context, _) => GlassSegmentedControl(
                      labels: [t_('For you'), t_('Following')],
                      selectedIndex: tabController.index,
                      onSelected: (i) => tabController.animateTo(i),
                    ),
                  ),
                ),
                collapsed: _scrolledUnder,
              ),
              body: TabBarView(children: [
                FeedList(
                  key: const PageStorageKey('forYou'),
                  session: session,
                  query: const {'kind': 'post'},
                  header: StoriesBar(session: session),
                  emptyIcon: Icons.dynamic_feed_outlined,
                  emptyTitle: 'Nothing here yet',
                  emptyHint: 'Be the first. Tap + to share a photo or a thought.',
                ),
                FeedList(
                  key: const PageStorageKey('following'),
                  session: session,
                  query: const {'scope': 'following', 'kind': 'post'},
                  emptyIcon: Icons.group_add_outlined,
                  emptyTitle: 'Follow people to fill this tab',
                  emptyHint: 'Use search to find members and tap Follow.',
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// A paged list of posts. Reused for the feed, hashtags and profiles.
class FeedList extends StatefulWidget {
  const FeedList({
    super.key,
    required this.session,
    required this.query,
    this.header,
    this.emptyIcon = Icons.dynamic_feed_outlined,
    this.emptyTitle = 'No posts yet',
    this.emptyHint,
  });
  final Session session;
  final Map<String, String> query;
  final Widget? header;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyHint;
  @override
  State<FeedList> createState() => FeedListState();
}

class FeedListState extends State<FeedList> {
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
      if (scroll.position.pixels > scroll.position.maxScrollExtent - 500) load();
    });
    load(refresh: true);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void insertFirst(Map<String, dynamic> p) => setState(() => posts.insert(0, p));

  Future<void> load({bool refresh = false}) async {
    if (loading || (done && !refresh)) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final q = {...widget.query, if (!refresh && cursor != null) 'cursor': cursor!};
      final j = await widget.session.call('GET', '/posts', query: q) as Map<String, dynamic>;
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final hasHeader = widget.header != null;
    return RefreshIndicator(
      onRefresh: () => load(refresh: true),
      child: ListView.builder(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: (hasHeader ? 1 : 0) + (posts.isEmpty ? 1 : posts.length + 1),
        itemBuilder: (context, i) {
          if (hasHeader && i == 0) return widget.header!;
          final k = hasHeader ? i - 1 : i;
          if (posts.isEmpty) {
            if (loading) return const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()));
            if (error != null) {
              return EmptyState(
                icon: Icons.cloud_off,
                title: error!,
                action: OutlinedButton(onPressed: () => load(refresh: true), child: Text(t_('Try again'))),
              );
            }
            return Padding(padding: const EdgeInsets.only(top: 40), child: EmptyState(icon: widget.emptyIcon, title: widget.emptyTitle, hint: widget.emptyHint));
          }
          if (k == posts.length) {
            if (error != null) {
              return Padding(padding: const EdgeInsets.all(16), child: Center(child: TextButton(onPressed: load, child: Text('$error  Tap to retry'))));
            }
            return loading ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())) : const SizedBox(height: 8);
          }
          final p = posts[k];
          return PostCard(
            key: ValueKey(p['public_id']),
            session: widget.session,
            post: p,
            onRemoved: () => setState(() => posts.removeWhere((x) => x['public_id'] == p['public_id'])),
          );
        },
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.session, required this.post, required this.onRemoved});
  final Session session;
  final Map<String, dynamic> post;
  final VoidCallback onRemoved;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late int comments = (widget.post['comments_count'] as num?)?.toInt() ?? 0;
  final reactionKey = GlobalKey<ReactionButtonState>();
  bool _heartVisible = false;

  /// Double tap on the media likes, the TikTok and Instagram rule. The heart
  /// pops at the centre of the media and fades after 700ms.
  void _doubleTap() {
    HapticFeedback.mediumImpact();
    setState(() => _heartVisible = true);
    reactionKey.currentState?.like();
    Future.delayed(const Duration(milliseconds: 700), () => mounted ? setState(() => _heartVisible = false) : null);
  }

  String get id => widget.post['public_id'] as String;
  Map<String, dynamic> get author => (widget.post['author'] as Map).cast<String, dynamic>();

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete post?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.session.call('DELETE', '/posts/$id');
      widget.onRemoved();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _menu(String v) async {
    if (v == 'delete') return _delete();
    if (v == 'report') return reportFlow(context, widget.session, 'post', id);
    if (v == 'block') {
      if (await blockFlow(context, widget.session, author['username'].toString())) widget.onRemoved();
    }
  }

  void _comments() async {
    final added = await showGlassSheet<int>(
      context,
      builder: (_) => CommentsSheet(session: widget.session, postId: id, postAuthorId: author['public_id'].toString()),
    );
    if (added != null && added != 0 && mounted) setState(() => comments += added);
  }

  void _openAuthor() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: author['username'].toString())));

  Widget _tag(String tag) => InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HashtagPage(session: widget.session, tag: tag))),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('#$tag', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final mine = author['public_id'] == widget.session.user?['public_id'];
    final media = (p['media'] as List).cast<Map<String, dynamic>>();
    final images = media.where((m) => m['type'] == 'image').toList();
    final videos = media.where((m) => m['type'] != 'image').toList();
    final body = (p['body'] ?? '').toString();
    final tags = (p['hashtags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final scheme = Theme.of(context).colorScheme;
    final name = (author['name'] ?? '').toString().isEmpty ? '@${author['username']}' : author['name'].toString();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final mediaWidgets = <Widget>[
      if (images.length == 1) _image(images.first['url'] as String, 300),
      if (images.length > 1) SizedBox(height: 300, child: PageView(children: [for (final m in images) _image(m['url'] as String, 300)])),
      for (final v in videos) VideoTile(url: v['url'] as String),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            GestureDetector(onTap: _openAuthor, child: Avatar(user: author, radius: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _openAuthor,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text('@${author['username']}  ${ago((p['created_at'] ?? '').toString())}', style: muted),
                ]),
              ),
            ),
            SizedBox(
              width: 32,
              height: 28,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
                onSelected: _menu,
                itemBuilder: (_) => mine
                    ? [PopupMenuItem(value: 'delete', child: Text(t_('Delete')))]
                    : [PopupMenuItem(value: 'report', child: Text(t_('Report'))), PopupMenuItem(value: 'block', child: Text(t_('Block')))],
              ),
            ),
          ]),
        ),
        if (body.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Text(body, style: Theme.of(context).textTheme.bodyLarge)),
        if (tags.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Wrap(spacing: 10, children: [for (final tg in tags.take(4)) _tag(tg)])),
        if (mediaWidgets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Stack(children: [
              GestureDetector(
                onDoubleTap: _doubleTap,
                child: Column(mainAxisSize: MainAxisSize.min, children: mediaWidgets),
              ),
              if (_heartVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: AnimatedScale(
                        scale: _heartVisible ? 1.0 : 0.6,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: const Icon(Icons.favorite, size: 88, color: Colors.white, shadows: [Shadow(blurRadius: 12, color: Colors.black45)]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        if (images.length > 1) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Text('1 of ${images.length}, swipe', style: muted)),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
          child: Row(children: [
            ReactionButton(key: reactionKey, session: widget.session, post: widget.post),
            TextButton.icon(onPressed: _comments, icon: const Icon(Icons.mode_comment_outlined, size: 22), label: Text('$comments')),
            if (!mine)
              TextButton.icon(
                onPressed: () => showGiftSheet(context, widget.session, widget.post['public_id'] as String, author['username'].toString()),
                icon: const Icon(Icons.card_giftcard, size: 22),
                label: Text(t_('Gift')),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ],
    );
  }

  Widget _image(String url, double h) => GestureDetector(
        onTap: () => openImage(context, url),
        child: Image.network(
          url,
          width: double.infinity,
          height: h,
          fit: BoxFit.cover,
          loadingBuilder: (c, child, prog) => prog == null ? child : SizedBox(height: h, child: const Center(child: CircularProgressIndicator())),
          errorBuilder: (c, e, s) => SizedBox(height: 80, child: Center(child: Text('Image could not load', style: TextStyle(color: Theme.of(context).colorScheme.outline)))),
        ),
      );
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.session, required this.postId, required this.postAuthorId});
  final Session session;
  final String postId;
  final String postAuthorId;
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final items = <Map<String, dynamic>>[];
  final input = TextEditingController();
  bool loading = true;
  bool sending = false;
  String? error;
  int delta = 0;
  Map<String, dynamic>? replyTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      String? cur;
      do {
        // ignore: use_null_aware_elements - the ? entry form is a type error here, the map value type is String not String?
        final j = await widget.session.call('GET', '/posts/${widget.postId}/comments', query: {if (cur != null) 'cursor': cur}) as Map<String, dynamic>;
        items.addAll((j['data'] as List).cast<Map<String, dynamic>>());
        cur = j['next_cursor'] as String?;
      } while (cur != null && items.length < 300);
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _send() async {
    final tx = input.text.trim();
    if (tx.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final j = await widget.session.call('POST', '/posts/${widget.postId}/comments', body: {'body': tx, if (replyTo != null) 'parent_id': replyTo!['public_id']}) as Map<String, dynamic>;
      items.add((j['comment'] as Map).cast<String, dynamic>());
      input.clear();
      delta++;
      replyTo = null;
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    try {
      await widget.session.call('DELETE', '/comments/${c['public_id']}');
      final id = c['public_id'];
      final before = items.length;
      items.removeWhere((x) => x['public_id'] == id || x['parent_id'] == id);
      delta -= before - items.length;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.session.user?['public_id'];
    final top = items.where((c) => c['parent_id'] == null).toList();
    Widget tile(Map<String, dynamic> c, {bool reply = false}) {
      final a = (c['author'] as Map).cast<String, dynamic>();
      final canDelete = a['public_id'] == me || widget.postAuthorId == me;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 8, 8).copyWith(left: reply ? 56 : 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(user: a, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '@${a['username']}  ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                TextSpan(text: ago(c['created_at'].toString()), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
              const SizedBox(height: 2),
              Text(c['body'].toString(), style: Theme.of(context).textTheme.bodyMedium),
            ]),
          ),
          if (!reply) IconButton(tooltip: t_('Reply'), icon: const Icon(Icons.reply, size: 18), onPressed: () => setState(() => replyTo = c)),
          if (canDelete) IconButton(tooltip: t_('Delete'), icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _delete(c)),
        ]),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(delta);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Text(t_('Comments'), style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? EmptyState(icon: Icons.mode_comment_outlined, title: error ?? 'No comments yet', hint: error == null ? 'Say something kind.' : null)
                        : ListView(children: [
                            for (final c in top) ...[
                              tile(c),
                              for (final r in items.where((x) => x['parent_id'] == c['public_id'])) tile(r, reply: true),
                            ],
                          ]),
              ),
              if (replyTo != null)
                ListTile(
                  dense: true,
                  title: Text('Replying to @${(replyTo!['author'] as Map)['username']}'),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => replyTo = null)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: input, maxLength: 1000, decoration: InputDecoration(hintText: 'Add a comment', counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(999))), onSubmitted: (_) => _send())),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: sending ? null : _send, icon: const Icon(Icons.send)),
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

class HashtagPage extends StatelessWidget {
  const HashtagPage({super.key, required this.session, required this.tag});
  final Session session;
  final String tag;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('#$tag')),
        body: FeedList(session: session, query: {'hashtag': tag}, emptyIcon: Icons.tag, emptyTitle: 'No posts with #$tag yet'),
      );
}

class ComposePage extends StatefulWidget {
  const ComposePage({super.key, required this.session});
  final Session session;
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final text = TextEditingController();
  List<XFile> images = [];
  XFile? video;
  bool busy = false;

  Future<void> _pick() async {
    final fs = await ImagePicker().pickMultiImage(maxWidth: 1280, imageQuality: 78, limit: 4);
    if (fs.isEmpty) return;
    setState(() {
      images = fs.take(4).toList();
      video = null;
    });
  }

  Future<void> _pickVideo() async {
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
    if (f == null) return;
    if (await f.length() > 25 * 1024 * 1024) {
      if (mounted) showError(context, 'That video is over 25 MB. Pick a shorter one.');
      return;
    }
    setState(() {
      video = f;
      images = [];
    });
  }

  Future<void> _post() async {
    final body = text.text.trim();
    if (body.isEmpty && images.isEmpty && video == null) {
      showError(context, 'Write something or add a photo or video.');
      return;
    }
    setState(() => busy = true);
    try {
      final files = <UploadFile>[];
      for (final f in images) {
        files.add(UploadFile(await f.readAsBytes(), mimeFor(f.name), f.name));
      }
      if (video != null) files.add(UploadFile(await video!.readAsBytes(), mimeFor(video!.name, video: true), video!.name));
      final post = await widget.session.createPost(body, files: files, reel: video != null);
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
      appBar: AppBar(title: Text(t_('New post')), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(child: GlassButton(label: busy ? 'Posting' : t_('Post'), onPressed: busy ? null : _post)),
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(user: widget.session.user),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: text, maxLines: 6, maxLength: 2000, decoration: const InputDecoration(hintText: 'What is happening? Use #hashtags', border: InputBorder.none))),
          ]),
          if (video != null)
            GlassCard(child: ListTile(leading: const Icon(Icons.videocam), title: Text(video!.name, overflow: TextOverflow.ellipsis), subtitle: const Text('Posts as a reel'))),
          if (images.isNotEmpty)
            SizedBox(
              height: 140,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final f in images)
                  FutureBuilder(
                    future: f.readAsBytes(),
                    builder: (c, s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: s.hasData ? Image.memory(s.data!, height: 140, width: 140, fit: BoxFit.cover) : const SizedBox(height: 140, width: 140)),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ActionChip(avatar: const Icon(Icons.photo_outlined, size: 18), label: Text(images.isEmpty ? 'Add photos (up to 4)' : 'Change photos'), onPressed: busy ? null : _pick),
            ActionChip(avatar: const Icon(Icons.videocam_outlined, size: 18), label: Text(video == null ? 'Add video as reel' : 'Change video'), onPressed: busy ? null : _pickVideo),
            if (images.isNotEmpty || video != null) ActionChip(label: const Text('Remove media'), onPressed: busy ? null : () => setState(() { images = []; video = null; })),
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
