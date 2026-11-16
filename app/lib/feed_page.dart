import 'ph.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';
import 'actions.dart';
import 'gifts.dart';
import 'api.dart';
import 'notifications_page.dart';
import 'profile_pages.dart';
import 'search_page.dart';
import 'reactions.dart';
import 'share_post.dart';
import 'stories_page.dart';
import 'ui.dart';

/// Test seam: lets widget tests supply a local image instead of a network fetch.
ImageProvider Function(String url)? feedImageProvider;

/// Home tab: For you and Following, with search and notifications on top.
class FeedPage extends StatelessWidget {
  const FeedPage({super.key, required this.session, required this.onCompose, this.forYouKey});
  final Session session;
  final Future<void> Function() onCompose;
  final GlobalKey<FeedListState>? forYouKey;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Logo(size: 56),
          actions: [
            IconButton(tooltip: t_('Post'), icon: const PhIcon('plus-square'), onPressed: onCompose),
            IconButton(tooltip: t_('Search'), icon: const PhIcon('magnifying-glass'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(session: session)))),
            IconButton(tooltip: t_('Notifications'), icon: const PhIcon('bell'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsPage(session: session)))),
          ],
          bottom: TabBar(tabs: [Tab(text: t_('For you')), Tab(text: t_('Following'))]),
        ),
        body: TabBarView(children: [
          FeedList(
            key: forYouKey ?? const PageStorageKey('forYou'),
            session: session,
            query: const {'kind': 'post'},
            immersive: true,
            header: StoriesBar(session: session),
            emptyIcon: Ph.dynamic_feed_outlined,
            emptyTitle: 'Nothing here yet',
            emptyHint: t_('Share something that matters to you.'),
            emptyAction: FilledButton.icon(onPressed: onCompose, icon: const PhIcon('plus', size: 18), label: Text(t_('Create a post'))),
          ),
          FeedList(
            key: const PageStorageKey('following'),
            session: session,
            query: const {'scope': 'following', 'kind': 'post'},
            immersive: true,
            emptyIcon: Ph.group_add_outlined,
            emptyTitle: 'Follow people to fill this tab',
            emptyHint: t_('Posts from the people you follow will appear here.'),
            emptyAction: FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(session: session))), icon: const PhIcon('magnifying-glass', size: 18), label: Text(t_('Find people'))),
          ),
        ]),
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
    this.emptyIcon = Ph.dynamic_feed_outlined,
    this.emptyTitle = 'No posts yet',
    this.emptyHint,
    this.emptyAction,
    this.immersive = false,
    this.path = '/posts',
  });
  final bool immersive;
  final String path;
  final Session session;
  final Map<String, String> query;
  final Widget? header;
  final PhData emptyIcon;
  final String emptyTitle;
  final String? emptyHint;
  final Widget? emptyAction;
  @override
  State<FeedList> createState() => FeedListState();
}

class FeedListState extends State<FeedList> {
  final posts = <Map<String, dynamic>>[];
  final scroll = ScrollController();
  String? cursor;
  bool loading = false;
  bool done = false;
  bool _refreshQueued = false;
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
    pager.dispose();
    super.dispose();
  }

  void insertFirst(Map<String, dynamic> p) => setState(() => posts.insert(0, p));

  Future<void> load({bool refresh = false}) async {
    if (loading) {
      if (refresh) _refreshQueued = true;
      return;
    }
    if (done && !refresh) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final q = {...widget.query, if (!refresh && cursor != null) 'cursor': cursor!};
      final j = await widget.session.call('GET', widget.path, query: q) as Map<String, dynamic>;
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        if (refresh) posts.clear();
        posts.addAll(items);
        cursor = j['next_cursor'] as String?;
        done = cursor == null;
      });
      if (refresh) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (pager.hasClients) pager.jumpToPage(0);
          if (scroll.hasClients) scroll.jumpTo(0);
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      // A reply the app could not read must not look like an empty list.
      if (mounted) setState(() => error = 'Could not load posts. Try again.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (_refreshQueued) {
          _refreshQueued = false;
          load(refresh: true);
        }
      }
    }
  }

  final pager = PageController();

  Widget _pager() {
    return Column(children: [
      if (widget.header != null) widget.header!,
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => load(refresh: true),
          child: PageView.builder(
            controller: pager,
            scrollDirection: Axis.vertical,
            physics: const AlwaysScrollableScrollPhysics(parent: PageScrollPhysics()),
            itemCount: posts.length,
            onPageChanged: (i) {
              if (i >= posts.length - 3) load();
            },
            itemBuilder: (context, i) {
              final p = posts[i];
              final hasPhoto = (p['media'] as List).any((m) => (m as Map)['type'] == 'image') && !(p['media'] as List).any((m) => (m as Map)['type'] != 'image');
              final card = PostCard(
                key: ValueKey(p['public_id']),
                session: widget.session,
                post: p,
                immersive: true,
                fill: true,
                onRemoved: () => setState(() => posts.removeWhere((x) => x['public_id'] == p['public_id'])),
              );
              // Room under the page for the floating nav bar.
              return Padding(
                padding: const EdgeInsets.only(bottom: 84),
                child: hasPhoto ? card : _PageHandoff(pager: pager, child: SingleChildScrollView(physics: const ClampingScrollPhysics(), child: card)),
              );
            },
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final hasHeader = widget.header != null;
    if (widget.immersive && posts.isNotEmpty) return _pager();
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
                icon: widget.session.offline ? Ph.cloud_off : Ph.error_outline,
                title: error!,
                action: OutlinedButton(onPressed: () => load(refresh: true), child: Text(t_('Try again'))),
              );
            }
            return Padding(padding: const EdgeInsets.only(top: 40), child: EmptyState(icon: widget.emptyIcon, title: widget.emptyTitle, hint: widget.emptyHint, action: widget.emptyAction));
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
            immersive: widget.immersive,
            onRemoved: () => setState(() => posts.removeWhere((x) => x['public_id'] == p['public_id'])),
          );
        },
      ),
    );
  }
}

/// A page whose own content scrolls. The content scrolls first; once it reaches its end (or start) the same drag
/// carries on into the pager, and letting go snaps to a page. Without this a tall post would trap the swipe.
class _PageHandoff extends StatefulWidget {
  const _PageHandoff({required this.pager, required this.child});
  final PageController pager;
  final Widget child;
  @override
  State<_PageHandoff> createState() => _PageHandoffState();
}

class _PageHandoffState extends State<_PageHandoff> {
  bool carrying = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical || !widget.pager.hasClients) return false;
        final pos = widget.pager.position;
        if (n is OverscrollNotification && n.dragDetails != null) {
          carrying = true;
          pos.jumpTo((pos.pixels + n.overscroll).clamp(pos.minScrollExtent, pos.maxScrollExtent));
          return true;
        }
        if (n is ScrollEndNotification && carrying) {
          carrying = false;
          if (pos is ScrollPositionWithSingleContext) pos.goBallistic(-(n.dragDetails?.primaryVelocity ?? 0));
          return true;
        }
        return false;
      },
      child: widget.child,
    );
  }
}

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.session, required this.post, required this.onRemoved, this.immersive = false, this.fill = false});
  final bool immersive;
  /// In the pager the photo card fills the page instead of using its own shape.
  final bool fill;
  final Session session;
  final Map<String, dynamic> post;
  final VoidCallback onRemoved;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late int comments = (widget.post['comments_count'] as num?)?.toInt() ?? 0;

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

  PopupMenuItem<String> shareItem() => PopupMenuItem(value: 'share', child: Text(t_('Share to chat')));

  PopupMenuItem<String> saveItem() => PopupMenuItem(value: 'save', child: Text(widget.post['saved'] == true ? t_('Remove from saved') : t_('Save')));

  Future<void> _toggleSave() async {
    final was = widget.post['saved'] == true;
    setState(() => widget.post['saved'] = !was);
    try {
      await widget.session.call(was ? 'DELETE' : 'POST', '/posts/$id/save');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(was ? t_('Removed from saved') : t_('Saved'))));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => widget.post['saved'] = was);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _menu(String v) async {
    if (v == 'save') return _toggleSave();
    if (v == 'share') return shareToChat(context, widget.session, id);
    if (v == 'delete') return _delete();
    if (v == 'report') return reportFlow(context, widget.session, 'post', id);
    if (v == 'block') {
      if (await blockFlow(context, widget.session, author['username'].toString())) widget.onRemoved();
    }
  }

  void _comments() async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
    final bodyLower = body.toLowerCase();
    final tags = ((p['hashtags'] as List?)?.map((e) => e.toString()).toList() ?? <String>[]).where((tg) => !bodyLower.contains('#${tg.toLowerCase()}')).toList();
    final scheme = Theme.of(context).colorScheme;
    final name = (author['name'] ?? '').toString().isEmpty ? '@${author['username']}' : author['name'].toString();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final single = images.length == 1;
    if (widget.immersive && images.isNotEmpty && videos.isEmpty) {
      return _immersive(images, name, body, mine, scheme);
    }
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)))),
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: Row(children: [
              GestureDetector(onTap: _openAuthor, child: Avatar(user: author, radius: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _openAuthor,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.2)),
                    Text(name != '@${author['username']}' ? '@${author['username']} \u00b7 ${ago((p['created_at'] ?? '').toString())}' : ago((p['created_at'] ?? '').toString()), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ]),
                ),
              ),
              SizedBox(width: 40, height: 40, child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: PhIcon('dots-three', color: scheme.onSurfaceVariant),
                onSelected: _menu,
                itemBuilder: (_) => mine
                    ? [saveItem(), shareItem(), PopupMenuItem(value: 'delete', child: Text(t_('Delete')))]
                    : [saveItem(), shareItem(), PopupMenuItem(value: 'report', child: Text(t_('Report'))), PopupMenuItem(value: 'block', child: Text(t_('Block')))],
              )),
            ]),
          ),
          if (body.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(body, style: Theme.of(context).textTheme.bodyLarge)),
          if (tags.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Wrap(spacing: 10, children: [for (final tg in tags.take(4)) _tag(tg)])),
          if (single) Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), child: ClipRRect(borderRadius: BorderRadius.circular(18), child: _image(images.first['url'] as String, 320))),
          if (images.length > 1) Padding(padding: const EdgeInsets.only(top: 10), child: SizedBox(height: 320, child: PageView(children: [for (final m in images) SizedBox(height: 320, width: double.infinity, child: Image.network(m['url'] as String, fit: BoxFit.cover, errorBuilder: (c, e, st) => const SizedBox()))]))),
          if (images.length > 1) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Text('1 of ${images.length}, swipe', style: muted)),
          for (final v in videos) Padding(padding: const EdgeInsets.only(top: 10), child: VideoTile(url: v['url'] as String)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
            child: Row(
              children: [
                ReactionButton(session: widget.session, post: widget.post),
                TextButton.icon(onPressed: _comments, icon: const PhIcon('chat-teardrop', size: 20), label: Text('$comments')),
                if (!mine)
                  TextButton.icon(
                    onPressed: () => showGiftSheet(context, widget.session, widget.post['public_id'] as String, author['username'].toString()),
                    icon: const PhIcon('gift', size: 20),
                    label: Text(t_('Gift')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _immersive(List<Map<String, dynamic>> images, String name, String body, bool mine, ColorScheme scheme) {
    final p = widget.post;
    const shadow = [Shadow(blurRadius: 6, color: Colors.black54)];
    Widget railItem(String icon, String label, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                PhIcon(icon, size: 28, color: Colors.white),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
    final url = images.first['url'] as String;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _shape(
          Stack(fit: StackFit.expand, children: [
            GestureDetector(onTap: () => openImage(context, url), child: _photo(url)),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.0, 0.4, 0.7, 1.0], colors: [Color(0x00000000), Color(0x00000000), Color(0x99000000), Color(0xE6000000)])),
              ),
            ),
            const Positioned(
              right: 0, top: 0, bottom: 0, width: 84,
              child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.transparent, Color(0x77000000)]),
              ))),
            ),
            if (images.length > 1) Positioned(top: 12, right: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: Text('+${images.length - 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
            Positioned(
              right: 8,
              bottom: 16,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ReactionButton(session: widget.session, post: p, dark: true),
                const SizedBox(height: 8),
                railItem('chat-teardrop', '$comments', _comments),
                if (!mine) ...[
                  const SizedBox(height: 8),
                  railItem('gift', t_('Gift'), () => showGiftSheet(context, widget.session, p['public_id'] as String, author['username'].toString())),
                ],
              ]),
            ),
            Positioned(
              left: 14,
              right: 76,
              bottom: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  GestureDetector(onTap: _openAuthor, child: Avatar(user: author, radius: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _openAuthor,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, shadows: shadow)),
                        Text(ago((p['created_at'] ?? '').toString()), style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: shadow)),
                      ]),
                    ),
                  ),
                  SizedBox(width: 36, height: 36, child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: const PhIcon('dots-three', color: Colors.white),
                    onSelected: _menu,
                    itemBuilder: (_) => mine
                        ? [saveItem(), shareItem(), PopupMenuItem(value: 'delete', child: Text(t_('Delete')))]
                        : [saveItem(), shareItem(), PopupMenuItem(value: 'report', child: Text(t_('Report'))), PopupMenuItem(value: 'block', child: Text(t_('Block')))],
                  )),
                ]),
                if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3, shadows: shadow))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _shape(Widget child) {
    if (widget.fill) return SizedBox.expand(child: child);
    final k = MediaQuery.textScalerOf(context).scale(14) / 14;
    return AspectRatio(aspectRatio: 0.8 / (k > 1.15 ? k * 0.9 : 1.0), child: child);
  }

  Widget _photo(String url) {
    final override = feedImageProvider;
    if (override != null) return Image(image: override(url), fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (c, child, prog) => prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (c, e, s) => const ColoredBox(color: Color(0xFF16181D), child: Center(child: Text('Image could not load', style: TextStyle(color: Colors.white70)))),
    );
  }

  // Height follows the photo's own shape, capped so a tall photo does not take the whole screen.
  Widget _image(String url, double h) => GestureDetector(
        onTap: () => openImage(context, url),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440, minHeight: 160),
          child: Image.network(
            url,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, prog) => prog == null ? child : SizedBox(height: 240, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.outline))),
            errorBuilder: (c, e, s) => SizedBox(height: 80, child: Center(child: Text('Image could not load', style: TextStyle(color: Theme.of(context).colorScheme.outline)))),
          ),
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
        padding: EdgeInsets.only(left: reply ? 40 : 0),
        child: ListTile(
          dense: true,
          leading: Avatar(user: a, radius: reply ? 12 : 16),
          title: Text('@${a['username']}  ·  ${ago(c['created_at'].toString())}', style: const TextStyle(fontSize: 12)),
          subtitle: Text(c['body'].toString(), style: Theme.of(context).textTheme.bodyMedium),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!reply) IconButton(tooltip: t_('Reply'), icon: const PhIcon('arrow-bend-up-left', size: 18), onPressed: () => setState(() => replyTo = c)),
            if (canDelete) IconButton(tooltip: t_('Delete'), icon: const PhIcon('trash', size: 18), onPressed: () => _delete(c)),
          ]),
        ),
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
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              Text(t_('Comments'), style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? EmptyState(icon: Ph.mode_comment_outlined, title: error ?? 'No comments yet', hint: error == null ? 'Say something kind.' : null)
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
                  trailing: IconButton(icon: const PhIcon('x'), onPressed: () => setState(() => replyTo = null)),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: input, maxLength: 1000, decoration: const InputDecoration(hintText: 'Add a comment', counterText: '', border: OutlineInputBorder()), onSubmitted: (_) => _send())),
                    IconButton(onPressed: sending ? null : _send, icon: const PhIcon('paper-plane-tilt-fill')),
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
        body: FeedList(session: session, query: {'hashtag': tag}, emptyIcon: Ph.tag, emptyTitle: 'No posts with #$tag yet'),
      );
}

class ComposePage extends StatefulWidget {
  const ComposePage({super.key, required this.session, this.startWithVideo = false});
  final Session session;
  final bool startWithVideo;
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final text = TextEditingController();
  List<XFile> images = [];
  XFile? video;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.startWithVideo) WidgetsBinding.instance.addPostFrameCallback((_) => _pickVideo());
  }

  Future<void> _pick() async {
    final fs = await guardPick(context, () => ImagePicker().pickMultiImage(maxWidth: 1280, imageQuality: 78, limit: 4)) ?? <XFile>[];
    if (fs.isEmpty) return;
    setState(() {
      images = fs.take(4).toList();
      video = null;
    });
  }

  Future<void> _pickVideo() async {
    final from = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const PhIcon('video-camera'), title: Text(t_('Record a video')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const PhIcon('film-strip'), title: Text(t_('Choose a video')), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (from == null) return;
    final f = await guardPick(context, () => ImagePicker().pickVideo(source: from, maxDuration: const Duration(seconds: 60)));
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
          child: FilledButton(onPressed: busy ? null : _post, child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t_('Post'))),
        ),
      ]),
      body: Column(children: [
        Expanded(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(user: widget.session.user),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: text, autofocus: true, minLines: 4, maxLines: 10, maxLength: 2000, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => currentLength > 1800 ? Text('$currentLength / $maxLength') : null, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18), decoration: const InputDecoration(hintText: 'What is happening? Use #hashtags', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false))),
          ]),
          if (video != null)
            Card(child: ListTile(leading: const PhIcon('video-camera'), title: Text(video!.name, overflow: TextOverflow.ellipsis), subtitle: const Text('Posts as a reel'))),
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
        ],
      )),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(onPressed: busy ? null : _pick, icon: const PhIcon('image', size: 20), label: Text(images.isEmpty ? 'Photos' : 'Change photos')),
              TextButton.icon(onPressed: busy ? null : _pickVideo, icon: const PhIcon('video-camera', size: 20), label: Text(video == null ? 'Reel' : 'Change video')),
              if (images.isNotEmpty || video != null) TextButton(onPressed: busy ? null : () => setState(() { images = []; video = null; }), child: const Text('Remove media')),
            ]),
          ),
        ),
      ]),
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
        if (!c.value.isPlaying) const PhIcon('play-circle-fill', size: 64, color: Colors.white70),
      ]),
    );
  }
}


/// Create sheet: pick what to make, then Continue.
class CreateSheet extends StatefulWidget {
  const CreateSheet({super.key});
  @override
  State<CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<CreateSheet> {
  String? picked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(String id, String icon, String title, String sub) {
      final on = picked == id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? scheme.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => picked = id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)), child: Center(child: PhIcon(icon, size: 24))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(sub, style: TextStyle(color: scheme.onSurfaceVariant)),
                ])),
                PhIcon(on ? 'check-circle-fill' : 'circle', color: on ? scheme.primary : scheme.outline),
              ]),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 4, 0, 12), child: Text(t_('Create'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          option('post', 'image', t_('Post'), t_('Photos or a text update')),
          option('reel', 'video-camera', t_('Reel'), t_('Short video')),
          option('story', 'camera', t_('Story'), t_('Disappears after 24 hours')),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: picked == null ? null : () => Navigator.pop(context, picked), child: Text(t_('Continue')))),
        ]),
      )),
    );
  }
}

/// The caller's saved posts, newest save first. Private to the caller.
class SavedPage extends StatelessWidget {
  const SavedPage({super.key, required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t_('Saved'))),
        body: FeedList(session: session, query: const {}, path: '/saved', emptyIcon: Ph.bookmark_outline, emptyTitle: 'Nothing saved yet', emptyHint: 'Open the menu on a post and choose Save. Only you can see this list.'),
      );
}
