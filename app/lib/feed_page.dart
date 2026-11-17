import 'dart:convert' show jsonEncode;
import 'creator_draft_store.dart';
import 'media_library_page.dart';
import 'settings_page.dart';
import 'upload_center.dart';
import 'ph.dart';
import 'photo_gallery.dart';
import 'draft_exit_guard.dart';
import 'upload_notice.dart';
import 'post_page.dart';
import 'poll_card.dart';
import 'media_visibility.dart';
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
  const FeedPage({super.key, required this.session, required this.onCompose, this.forYouKey, this.storyRevision = 0});
  final Session session;
  final Future<void> Function() onCompose;
  final GlobalKey<FeedListState>? forYouKey;
  final int storyRevision;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: t_('Settings'), icon: const PhIcon('list'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(session: session)))),
          centerTitle: true,
          title: const Logo(size: 48),
          actions: [
            IconButton(tooltip: t_('Post'), icon: const PhIcon('plus'), onPressed: onCompose),
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
            header: StoriesBar(session: session, contentRevision: storyRevision),
            emptyIcon: Ph.dynamic_feed_outlined,
            emptyTitle: 'Nothing here yet',
            emptyHint: t_('Share something that matters to you.'),
            emptyAction: FilledButton.icon(onPressed: onCompose, icon: const PhIcon('plus', size: 18), label: Text(t_('Create a post'))),
          ),
          FeedList(
            key: const PageStorageKey('following'),
            session: session,
            query: const {'scope': 'following', 'kind': 'post'},
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
    this.grid = false,
    this.path = '/posts',
  });
  final bool immersive;
  final bool grid;
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

class FeedListState extends State<FeedList> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final posts = <Map<String, dynamic>>[];
  final scroll = ScrollController();
  String? cursor;
  bool loading = false;
  bool done = false;
  bool _refreshQueued = false;
  String? error;
  late final uploads = UploadCenter.of(widget.session);
  int _uploadRevision = -1;

  @override
  void initState() {
    super.initState();
    uploads.addListener(_published);
    scroll.addListener(() {
      if (scroll.position.pixels > scroll.position.maxScrollExtent - 500) load();
    });
    load(refresh: true);
  }

  @override
  void dispose() {
    uploads.removeListener(_published);
    scroll.dispose();
    pager.dispose();
    super.dispose();
  }

  void insertFirst(Map<String, dynamic> p) {
    if (!mounted) return;
    setState(() { posts.removeWhere((x) => x['public_id'] == p['public_id']); posts.insert(0, p); });
  }


  Iterable<Map<String, dynamic>> get _localPosts => uploads.confirmedPosts.where((p) =>
      widget.path == '/posts' && widget.query['scope'] != 'following' &&
      (widget.query['kind'] == null || widget.query['kind'] == p['kind']) &&
      (widget.query['username'] == null || widget.query['username'] == (p['author'] as Map?)?['username']));
  void _published() {
    if (!mounted || _uploadRevision == uploads.revision) return;
    _uploadRevision = uploads.revision;
    setState(() {
      for (final p in _localPosts.toList().reversed) {
        posts.removeWhere((x) => x['public_id'] == p['public_id']);
        posts.insert(0, p);
      }
    });
  }

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
        if (refresh) { posts.clear(); posts.addAll(_localPosts); }
        final ids = posts.map((p) => p['public_id']).toSet();
        posts.addAll(items.where((p) => ids.add(p['public_id'])));
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
    super.build(context);
    final hasHeader = widget.header != null;
    if (widget.grid && posts.isNotEmpty) return RefreshIndicator(
      onRefresh: () => load(refresh: true),
      child: CustomScrollView(controller: scroll, physics: const AlwaysScrollableScrollPhysics(), slivers: [
        if (hasHeader) SliverToBoxAdapter(child: widget.header),
        SliverGrid(delegate: SliverChildBuilderDelegate((context, i) {
          final p = posts[i];
          final media = (p['media'] as List?) ?? [];
          final photo = media.where((m) => m['type'] == 'image').firstOrNull;
          final url = photo?['url'] ?? (media.isNotEmpty ? media.first['thumbnail_url'] : null);
          return Semantics(button: true, label: (p['body'] ?? t_('Post')).toString(), child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostPage(session: widget.session, postId: p['public_id'].toString()))),
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh, child: url == null
                ? Center(child: Padding(padding: const EdgeInsets.all(10), child: Text((p['body'] ?? '').toString(), maxLines: 5, overflow: TextOverflow.ellipsis)))
                : Image(image: feedImageProvider?.call(url.toString()) ?? NetworkImage(url.toString()), fit: BoxFit.cover, errorBuilder: (_,e,st) => const Center(child: PhIcon('image')))),
              if (p['kind'] == 'reel') const Positioned(top: 8, right: 8, child: PhIcon('play-circle', color: Colors.white, size: 22)),
            ]),
          ));
        }, childCount: posts.length), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 0.75)),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(bottom: 104, top: 12), child: loading ? const LinearProgressIndicator() : error != null ? TextButton(onPressed: load, child: Text(error!)) : const SizedBox.shrink())),
      ]),
    );
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

  PopupMenuItem<String> shareItem() => PopupMenuItem(value: 'share', enabled: widget.post['can_share_to_chat'] != false, child: Text(t_('Share to chat')));

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
      isDismissible: false,
      enableDrag: false,
      builder: (_) => CommentsSheet(session: widget.session, postId: id, postAuthorId: author['public_id'].toString()),
    );
    if (!mounted) return;
    if (added != null && added != 0) setState(() => comments = (comments + added).clamp(0, 1 << 31));
    try {
      final result = await widget.session.call('GET', '/posts/$id') as Map;
      final count = (result['post'] as Map)['comments_count'] as int;
      if (mounted) setState(() => comments = count);
    } catch (_) { /* Keep the last known count until the next feed refresh. */ }
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
          if (p['poll'] is Map) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: PollCard(key: ValueKey(p['public_id']), session: widget.session, post: p)),
          if (tags.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Wrap(spacing: 10, children: [for (final tg in tags.take(4)) _tag(tg)])),
          if (images.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(borderRadius: BorderRadius.zero, child: SizedBox(
              height: 360,
              child: PhotoGallery(key: ValueKey('photos-$id'), urls: images.map((m) => m['url'] as String).toList(), provider: feedImageProvider),
            )),
          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _shape(
          Stack(fit: StackFit.expand, children: [
            PhotoGallery(key: ValueKey('photos-$id'), urls: images.map((m) => m['url'] as String).toList(), provider: feedImageProvider),
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
  final scroll = ScrollController();
  final deleting = <String>{};
  final local = <String>{};
  final removed = <String>{};
  bool canComment = true;
  bool loading = false;
  bool sending = false;
  bool closing = false;
  bool uncertain = false;
  bool replyGone = false;
  String? error;
  String? nextCursor;
  bool retryRefresh = false;
  int delta = 0;
  Map<String, dynamic>? replyTo;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { input.dispose(); scroll.dispose(); super.dispose(); }

  Future<void> _load({bool refresh = false}) async {
    if (loading) return;
    setState(() { loading = true; error = null; retryRefresh = refresh; });
    try {
      final j = await widget.session.call('GET', '/posts/${widget.postId}/comments', query: {if (!refresh && nextCursor != null) 'cursor': nextCursor!}) as Map<String, dynamic>;
      if (!mounted) return;
      canComment = j['can_comment'] != false;
      final incoming = (j['data'] as List).cast<Map<String, dynamic>>().where((c) => !removed.contains(c['public_id']) && !removed.contains(c['parent_id'])).toList();
      final cursor = j['next_cursor'] as String?;
      if (refresh) items.removeWhere((c) => !local.contains(c['public_id']));
      final known = items.map((c) => c['public_id']).toSet();
      final fresh = incoming.where((c) => known.add(c['public_id'])).toList();
      final firstLocal = items.indexWhere((c) => local.contains(c['public_id']));
      items.insertAll(firstLocal < 0 ? items.length : firstLocal, fresh);
      nextCursor = cursor;
    } catch (e) {
      if (mounted) error = e is ApiError ? e.message : t_('Comments could not be loaded.');
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _send() async {
    final tx = input.text.trim();
    if (!canComment || tx.isEmpty || sending || deleting.isNotEmpty || uncertain || replyGone) return;
    final parent = replyTo;
    setState(() => sending = true);
    try {
      final j = await widget.session.call('POST', '/posts/${widget.postId}/comments', body: {'body': tx, if (parent != null) 'parent_id': parent['public_id']}) as Map<String, dynamic>;
      if (!mounted) return;
      final c = (j['comment'] as Map).cast<String, dynamic>();
      if (c['public_id'] is! String || (c['public_id'] as String).isEmpty || c['body'] is! String || c['author'] is! Map) throw const FormatException('Incomplete comment response');
      if (!items.any((item) => item['public_id'] == c['public_id'])) items.add(c);
      local.add(c['public_id'].toString());
      input.clear(); delta++; replyTo = null;
      showInfo(context, t_('Comment posted.'));
    } catch (e) {
      if (!mounted) return;
      uncertain = e is! ApiError || e.status == null || e.status! >= 500;
      showError(context, e is ApiError ? e : ApiError(t_('The comment result is unknown.')));
      if (uncertain) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && scroll.hasClients) scroll.jumpTo(0); });
    } finally { if (mounted) setState(() => sending = false); }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final id = c['public_id'].toString();
    if (sending || deleting.isNotEmpty) return;
    setState(() => deleting.add(id));
    try {
      final result = await widget.session.call('DELETE', '/comments/$id');
      if (!mounted) return;
      removed.add(id);
      final before = items.length;
      items.removeWhere((x) => x['public_id'] == id || x['parent_id'] == id);
      final count = result is Map && result['deleted_count'] is int ? result['deleted_count'] as int : before - items.length;
      delta -= count;
      if (replyTo?['public_id'] == id) replyGone = true;
    } catch (e) { if (mounted) showError(context, e); }
    finally { if (mounted) setState(() => deleting.remove(id)); }
  }

  Future<void> _close() async {
    if (closing) return;
    if (sending || deleting.isNotEmpty) { showInfo(context, t_('Your comment is still updating.')); return; }
    if (input.text.trim().isNotEmpty) {
      closing = true;
      final discard = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(t_('Discard this draft?')),
        content: Text(t_('Leaving will remove this draft from this screen.')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Keep editing'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Discard')))],
      ));
      closing = false;
      if (discard != true) return;
    }
    if (mounted) Navigator.of(context).pop(delta);
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.session.user?['public_id'];
    final children = <String, List<Map<String, dynamic>>>{};
    final roots = <Map<String, dynamic>>[];
    for (final c in items) {
      if (c['parent_id'] == null) { roots.add(c); }
      else { children.putIfAbsent(c['parent_id'].toString(), () => []).add(c); }
    }
    final rows = <(Map<String, dynamic>, bool)>[];
    for (final c in roots) { rows.add((c, false)); for (final r in children[c['public_id']] ?? <Map<String, dynamic>>[]) { rows.add((r, true)); } }
    Widget tile(Map<String, dynamic> c, {bool reply = false}) {
      final a = (c['author'] as Map).cast<String, dynamic>();
      final canDelete = a['public_id'] == me || widget.postAuthorId == me;
      return Padding(padding: EdgeInsets.fromLTRB(reply ? 36 : 16, 12, 12, 0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 3, right: 10), child: Avatar(user: a, radius: reply ? 12 : 16)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('@${a['username']}  ·  ${ago(c['created_at'].toString())}', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(c['body'].toString(), style: Theme.of(context).textTheme.bodyMedium),
          Wrap(children: [
            if (!reply) TextButton(onPressed: !canComment || sending || deleting.isNotEmpty || uncertain ? null : () => setState(() { replyTo = c; replyGone = false; }), child: Text(t_('Reply'))),
            if (canDelete) IconButton(tooltip: t_('Delete'), icon: const PhIcon('trash', size: 18), onPressed: sending || deleting.isNotEmpty ? null : () => _delete(c)),
          ]),
        ])),
      ]));
    }

    final list = <Widget>[
      if (uncertain) Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t_('This comment may already be posted.')),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: loading ? null : () => _load(refresh: true), child: Text(t_('Check comments'))),
          TextButton(onPressed: () async {
            final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(scrollable: true,
              title: Text(t_('Write another comment?')),
              content: Text(t_('The earlier attempt may already be posted. Check it first to avoid a duplicate. Your current draft will be kept.')),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('New comment')))],
            ));
            if (yes == true && mounted) setState(() => uncertain = false);
          }, child: Text(t_('New comment'))),
        ]),
      ])),
      if (items.isEmpty && !loading && error == null) EmptyState(icon: Ph.mode_comment_outlined, title: t_('No comments yet'), hint: t_('Say something kind.')),
      for (final row in rows) tile(row.$1, reply: row.$2),
      if (loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
      if (!loading && (error != null || nextCursor != null)) Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        if (error != null) Text(error!),
        TextButton(onPressed: () => _load(refresh: error != null && retryRefresh), child: Text(t_(error != null ? 'Try again' : 'Load more comments'))),
      ])),
    ];
    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); }, child: SafeArea(top: false, child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.72, child: LayoutBuilder(builder: (context, bounds) => Column(children: [
        Row(children: [const SizedBox(width: 16), Expanded(child: Text(t_('Comments'), style: Theme.of(context).textTheme.titleMedium)), IconButton(tooltip: t_('Refresh comments'), onPressed: loading ? null : () => _load(refresh: true), icon: const PhIcon('arrow-clockwise')), IconButton(tooltip: t_('Close comments'), onPressed: _close, icon: const PhIcon('x'))]),
        Expanded(child: ListView.builder(controller: scroll, itemCount: list.length, itemBuilder: (_, i) => list[i])),
        ConstrainedBox(constraints: BoxConstraints(maxHeight: bounds.maxHeight * 0.6), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!canComment) Padding(padding: const EdgeInsets.all(12), child: Text(t_('Comments are limited by this member.'))),
          if (replyGone) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(t_('Original comment removed. Choose another reply or cancel.'))),
          if (replyTo != null) Padding(padding: const EdgeInsets.only(left: 16), child: Row(children: [Expanded(child: Text('${t_('Replying to')} @${(replyTo!['author'] as Map)['username']}', maxLines: 2, overflow: TextOverflow.ellipsis)), IconButton(tooltip: t_('Cancel reply'), icon: const PhIcon('x'), onPressed: sending || deleting.isNotEmpty || uncertain ? null : () => setState(() { replyTo = null; replyGone = false; }))])),
          Padding(key: const ValueKey('comment-composer'), padding: const EdgeInsets.all(8), child: Row(children: [
            Expanded(child: TextField(controller: input, enabled: canComment && !sending && deleting.isEmpty, maxLength: 1000, minLines: 1, maxLines: 3, decoration: InputDecoration(hintText: t_('Add a comment'), counterText: '', border: const OutlineInputBorder()), onSubmitted: (_) => _send())),
            IconButton(tooltip: t_('Send comment'), onPressed: !canComment || sending || deleting.isNotEmpty || uncertain || replyGone ? null : _send, icon: sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const PhIcon('paper-plane-tilt-fill')),
          ])),
        ]))),
      ]))),
    )));

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
  const ComposePage({super.key, required this.session, this.startWithVideo = false, this.backgroundUpload = false, this.initialLocalDraft});
  final Session session;
  final bool startWithVideo;
  final bool backgroundUpload;
  final CreatorDraft? initialLocalDraft;
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final text = TextEditingController();
  List<XFile> images = [];
  XFile? video;
  bool busy = false;
  bool handedOff = false;
  String intent = newUploadIntent();
  UploadError? uploadError;
  List<TextEditingController>? pollOptions;
  String? _draftOwner, _localDraftId, _localDraftRevision, _savedFingerprint;
  bool _savingDraft = false;
  bool get _draftAccountChanged => _draftOwner != null && widget.session.user?['public_id'] != _draftOwner;
  void _draftSessionChanged() { if (mounted) setState(() {}); }
  String get _fingerprint => jsonEncode([text.text, pollOptions?.map((c) => c.text).toList()]);
  bool get _unsaved => images.isNotEmpty || video != null || (_savedFingerprint != _fingerprint && (text.text.trim().isNotEmpty || pollOptions != null));
  Future<void> _saveDraft() async {
    if (_savingDraft || busy || handedOff) return;
    final owner = _draftOwner;
    if (owner == null || widget.session.user?['public_id'] != owner) { showError(context, t_('Sign in to save drafts on this device.')); return; }
    if (images.isNotEmpty || video != null) { showError(context, t_('Only text and poll options can be saved for now. Photos and videos are not saved.')); return; }
    final snapshot = _fingerprint;
    setState(() => _savingDraft = true);
    try {
      final saved = await const CreatorDraftStore().save(owner, id: _localDraftId, expectedRevision: _localDraftRevision, text: text.text, options: pollOptions?.map((c) => c.text).toList());
      if (!mounted || widget.session.user?['public_id'] != owner) return;
      setState(() { _localDraftId = saved.id; _localDraftRevision = saved.revision; _savedFingerprint = snapshot; });
      showInfo(context, t_('Draft saved on this device. Find it in Settings > Saved drafts. Nothing was posted.'));
    } catch (error) { if (mounted && widget.session.user?['public_id'] == owner) showError(context, error); }
    finally { if (mounted) setState(() => _savingDraft = false); }
  }

  @override
  void dispose() {
    widget.session.removeListener(_draftSessionChanged);
    text.dispose();
    for (final option in pollOptions ?? <TextEditingController>[]) { option.dispose(); }
    super.dispose();
  }

  void _poll() {
    if (images.isNotEmpty || video != null) { showError(context, 'Remove media before adding a poll.'); return; }
    setState(() => pollOptions = [TextEditingController(), TextEditingController()]);
  }

  void _removePoll() {
    final old = pollOptions;
    FocusScope.of(context).unfocus();
    setState(() => pollOptions = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old ?? <TextEditingController>[]) { c.dispose(); }
    });
  }

  @override
  void initState() {
    super.initState();
    _draftOwner = widget.session.user?['public_id'] as String?;
    widget.session.addListener(_draftSessionChanged);
    final draft = widget.initialLocalDraft;
    if (draft != null) {
      text.text = draft.text; _localDraftId = draft.id; _localDraftRevision = draft.revision;
      pollOptions = draft.options?.map((v) => TextEditingController(text: v)).toList();
      _savedFingerprint = _fingerprint;
    }
    if (widget.backgroundUpload) UploadCenter.of(widget.session);
    if (widget.startWithVideo) WidgetsBinding.instance.addPostFrameCallback((_) => _pickVideo());
  }

  Future<void> _pick() async {
    final chosen = await chooseCreatorMedia(context, CreatorKind.post);
    final fs = chosen?.map((m) => m.file).toList() ?? <XFile>[];
    if (fs.isEmpty || !mounted) return;
    setState(() {
      images = fs.take(4).toList();
      video = null;
    });
  }

  Future<void> _pickVideo() async {
    final chosen = await chooseCreatorMedia(context, CreatorKind.reel);
    final f = chosen == null || chosen.isEmpty ? null : chosen.first.file;
    if (f == null || !mounted) return;
    if (await f.length() > 25 * 1024 * 1024) {
      if (mounted) showError(context, 'That video is over 25 MB. Pick a shorter one.');
      return;
    }
    if (!mounted) return;
    setState(() {
      video = f;
      images = [];
    });
  }

  Future<void> _post() async {
    if (busy || _savingDraft || uploadError?.terminal == true) return;
    if (_draftAccountChanged) { showError(context, 'This draft belongs to another signed-in session. Close it and sign in again.'); return; }
    final body = text.text.trim();
    final options = pollOptions?.map((c) => c.text.trim()).toList();
    if (options != null && !widget.session.pollsEnabled) { showError(context, t_('Polls are not available for this session. Keep the draft or remove the poll to post text.')); return; }
    if (options != null && (body.isEmpty || options.any((v) => v.isEmpty) || options.map((v) => v.toLowerCase()).toSet().length != options.length)) {
      showError(context, t_('Add a question and different, non-empty options.')); return;
    }
    if (body.isEmpty && images.isEmpty && video == null) {
      showError(context, 'Write something or add a photo or video.');
      return;
    }
    if (widget.backgroundUpload) {
      final center = UploadCenter.of(widget.session);
      final picked = List<XFile>.unmodifiable(video == null ? images : [video!]);
      final isReel = video != null;
      final originalIntent = intent;
      final generation = center.generation;
      final owner = widget.session.user?['public_id'];
      final originalOptions = options == null ? null : List<String>.unmodifiable(options);
      // Files are read once; replay uses the same bytes, text, kind and intent.
      Future<List<UploadFile>>? snapshot;
      Future<List<UploadFile>> prepare() async {
        final result = <UploadFile>[];
        for (final file in picked) {
          final data = await file.readAsBytes();
          if (data.length > 25 * 1024 * 1024) throw ApiError('That file is over 25 MB. Choose a smaller one.');
          result.add(UploadFile(data, mimeFor(file.name, video: isReel), file.name));
        }
        return List.unmodifiable(result);
      }
      final session = widget.session;
      final started = center.start(isReel ? 'reel' : 'post', () async {
        snapshot ??= prepare();
        final files = await snapshot!;
        if (center.generation != generation || session.user?['public_id'] != owner) throw ApiError('Please sign in again.', 401);
        center.sending();
        return session.createPost(body, files: files, reel: isReel, pollOptions: originalOptions, intent: originalIntent);
      });
      if (!started) { showInfo(context, 'Check the current upload before starting another.'); return; }
      setState(() => handedOff = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() { busy = true; uploadError = null; });
    try {
      final files = <UploadFile>[];
      for (final f in images) {
        files.add(UploadFile(await f.readAsBytes(), mimeFor(f.name), f.name));
      }
      if (video != null) files.add(UploadFile(await video!.readAsBytes(), mimeFor(video!.name, video: true), video!.name));
      final post = await widget.session.createPost(body, files: files, reel: video != null, pollOptions: options, intent: intent);
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (mounted) {
        setState(() { busy = false; uploadError = e is UploadError ? e : null; });
        if (e is! UploadError) showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draftAccountChanged) return Scaffold(appBar: AppBar(title: const Text('Local draft')), body: const Padding(padding: EdgeInsets.all(20), child: Text('This editor belongs to another signed-in session. Close it and sign in again to continue.')));
    return DraftExitGuard(
      hasChanges: !handedOff && _unsaved,
      busy: busy || _savingDraft,
      child: Scaffold(
      appBar: AppBar(title: Text(t_('New post')), actions: [
        IconButton(tooltip: t_('Save text draft'), onPressed: busy || _savingDraft || handedOff ? null : _saveDraft, icon: const PhIcon('bookmark-simple')),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton(onPressed: busy || _savingDraft || handedOff || uploadError?.terminal == true || (text.text.trim().isEmpty && images.isEmpty && video == null) ? null : _post, child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t_('Post'))),
        ),
      ]),
      body: Column(children: [
        if (widget.initialLocalDraft != null) Padding(padding: const EdgeInsets.all(12), child: Text('Local draft. Posting is manual. The saved copy stays in Drafts until you delete it.')),
        if (uploadError != null) UploadNotice(
          message: uploadError!.message,
          openOriginal: uploadError!.resourceId == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostPage(session: widget.session, postId: uploadError!.resourceId!))),
          prepareNew: uploadError!.terminal ? () async {
            if (await confirmNewUpload(context) && mounted) setState(() { intent = newUploadIntent(); uploadError = null; });
          } : null,
          retry: !busy && !uploadError!.terminal ? _post : null,
        ),
        Expanded(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(user: widget.session.user),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: text, enabled: !busy, onChanged: (_) => setState(() {}), autofocus: true, minLines: 4, maxLines: 10, maxLength: 2000, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => currentLength > 1800 ? Text('$currentLength / $maxLength') : null, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18), decoration: const InputDecoration(hintText: 'What is happening? Use #hashtags', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false))),
          ]),
          if (pollOptions != null) ...[
            for (var i = 0; i < pollOptions!.length; i++) Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(controller: pollOptions![i], enabled: !busy, onChanged: (_) => setState(() {}), maxLength: 80, decoration: InputDecoration(labelText: '${t_('Option')} ${i + 1}')),
            ),
            Wrap(spacing: 8, children: [
              if (pollOptions!.length < 4) TextButton(onPressed: busy ? null : () => setState(() => pollOptions!.add(TextEditingController())), child: Text(t_('Add option'))),

            ]),
            Text(t_('One choice per person. Results show counts, not names.')),
          ],
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
              if (pollOptions != null) TextButton(onPressed: busy ? null : _removePoll, child: Text(t_('Remove poll'))),
              if (pollOptions == null) TextButton.icon(onPressed: busy ? null : _pick, icon: const PhIcon('image', size: 20), label: Text(images.isEmpty ? 'Photos' : 'Change photos')),
              if (pollOptions == null) TextButton.icon(onPressed: busy ? null : _pickVideo, icon: const PhIcon('video-camera', size: 20), label: Text(video == null ? 'Reel' : 'Change video')),
              if (widget.session.pollsEnabled && pollOptions == null) TextButton.icon(onPressed: busy ? null : _poll, icon: const PhIcon('check', size: 20), label: Text(t_('Poll'))),
              if (images.isNotEmpty || video != null) TextButton(onPressed: busy ? null : () => setState(() { images = []; video = null; }), child: const Text('Remove media')),
            ]),
          ),
        ),
      ]),
    ));
  }
}

/// Streams a video from the media endpoint. Tap to play or pause.
class VideoTile extends StatefulWidget {
  const VideoTile({super.key, required this.url});
  final String url;
  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> with MediaVisibility<VideoTile> {
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
  void mediaVisibilityChanged(bool visible) {
    if (!visible && ready) c.pause();
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
      onTap: () { if (mediaVisible) c.value.isPlaying ? c.pause() : c.play(); },
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
