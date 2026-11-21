import 'upload_center.dart';
import 'ph.dart';
import 'media_visibility.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';
import 'session_bound_state.dart';
import 'session_recovery.dart';
import 'feed_page.dart' show CommentsSheet;
import 'gifts.dart';
import 'profile_pages.dart';
import 'reactions.dart';
import 'ui.dart';

/// Three players only: current, previous and next. Prepared players never
/// autoplay. Ownership is the Reels destination, not disposable PageView cells.
class ReelPlayback {
  ReelPlayback(String url) : controller = VideoPlayerController.networkUrl(Uri.parse(url)) {
    initialized = controller.initialize().then((_) async {
      if (disposed) return;
      await controller.setLooping(true);
    });
    initialized.catchError((Object _) { failed = true; });
  }
  final VideoPlayerController controller;
  late final Future<void> initialized;
  bool disposed = false;
  bool failed = false;
  void dispose() { if (!disposed) { disposed = true; controller.dispose(); } }
}
class ReelPlayerPool {
  final _players = <String, ReelPlayback>{};
  int get length => _players.length;
  static String? url(Map<String, dynamic> reel) {
    final media = (reel['media'] as List?) ?? [];
    final videos = media.where((m) => m['type'] != 'image');
    return videos.isEmpty ? null : videos.first['url'] as String?;
  }
  ReelPlayback? forReel(Map<String, dynamic> reel) => _players[url(reel)];
  void warm(List<Map<String, dynamic>> reels, int index) {
    final keep = <String>{};
    for (var i = index - 1; i <= index + 1; i++) {
      if (i < 0 || i >= reels.length) continue;
      final value = url(reels[i]);
      if (value != null) keep.add(value);
    }
    for (final value in _players.keys.toList()) { if (!keep.contains(value)) _players.remove(value)!.dispose(); }
    for (final value in keep) { _players.putIfAbsent(value, () => ReelPlayback(value)); }
  }
  bool discardFailedFor(Map<String, dynamic> reel) {
    final value = url(reel);
    final player = _players[value];
    if (player == null || (!player.failed && !player.controller.value.hasError)) return false;
    _players.remove(value)!.dispose();
    return true;
  }
  void discardFailed() {
    for (final url in _players.keys.toList()) {
      final player = _players[url]!;
      if (player.failed || player.controller.value.hasError) _players.remove(url)!.dispose();
    }
  }
  void dispose() { for (final value in _players.values) { value.dispose(); } _players.clear(); }
}

/// Full screen vertical reels. Swipe up for the next one.
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key, required this.session, required this.active, this.contentRevision = 0, this.onCreate, this.bottomInset = 0});
  final Session session;
  final int contentRevision;
  final double bottomInset;
  final Future<void> Function()? onCreate;
  final bool active; // false while another tab is showing, so audio stops
  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> with SessionBoundState<ReelsPage> {
  @override Session get viewSession=>widget.session;
  @override void sessionRetired(){
    _refreshQueued=false;reels.clear();cursor=null;error=null;
    players.dispose();
  }
  final reels = <Map<String, dynamic>>[];
  final pager = PageController();
  int index = 0;
  String? cursor;
  bool loading = false;
  bool _refreshQueued = false;
  bool done = false;
  String? error;
  bool muted = false;
  final players = ReelPlayerPool();
  late final uploads = UploadCenter.of(widget.session);
  int _uploadRevision = -1;
  void _published() {
    if (!mounted || !sessionActive || uploads.revision == _uploadRevision) return;
    _uploadRevision = uploads.revision;
    final items = uploads.confirmedPosts.where((p) => p['kind'] == 'reel').toList();
    if (items.isEmpty) return;
    // Keep the viewed reel stable; reveal the new result on deliberate refresh.
    final current = reels.isEmpty ? null : reels[index]['public_id'];
    setState(() {
      for (final p in items.reversed) {
        reels.removeWhere((x) => x['public_id'] == p['public_id']); reels.insert(0, p);
      }
      if (current != null) index = reels.indexWhere((p) => p['public_id'] == current);
      players.warm(reels, index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && sessionActive && pager.hasClients) pager.jumpToPage(index); });
  }

  @override
  void initState() {
    super.initState();
    uploads.addListener(_published);
    _load(refresh: true);
  }

  @override
  void didUpdateWidget(ReelsPage old) {
    super.didUpdateWidget(old);
    if (sessionActive && old.contentRevision != widget.contentRevision) _load(refresh: true);
  }

  @override
  void dispose() {
    uploads.removeListener(_published);
    players.dispose();
    pager.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if(!mounted || !sessionActive)return;
    if (loading) { if (refresh) _refreshQueued = true; return; }
    if (done && !refresh) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await widget.session.call('GET', '/posts', query: {'kind': 'reel', if (!refresh && cursor != null) 'cursor': cursor!}) as Map<String, dynamic>;
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted || !sessionActive) return;
      setState(() {
        if (refresh) { reels.clear(); reels.addAll(uploads.confirmedPosts.where((p) => p['kind'] == 'reel')); index = 0; }
        final ids = reels.map((p) => p['public_id']).toSet();
        reels.addAll(items.where((p) => ids.add(p['public_id'])));
        if (refresh) players.discardFailed();
        players.warm(reels, index);
        cursor = j['next_cursor'] as String?;
        done = cursor == null;
      });
      if (refresh) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && sessionActive && pager.hasClients) pager.jumpToPage(0); });
    } on ApiError catch (e) {
      if (mounted && sessionActive) setState(() => error = t_(e.message));
    } catch (_) {
      if (mounted && sessionActive) setState(() => error = 'Could not load reels. Try again.');
    } finally {
      if (mounted && sessionActive) {
        setState(() => loading = false);
        if (_refreshQueued) { _refreshQueued = false; _load(refresh: true); }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return SessionRecoveryView(session:widget.session);
    if (reels.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t_('Reels'))),
        body: Padding(padding: const EdgeInsets.only(bottom: 88), child: loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight), child: EmptyState(
                icon: Ph.movie_outlined,
                title: error ?? t_('No reels yet'),
                hint: error == null ? t_('Share a short video with your community.') : null,
                action: error == null && widget.onCreate != null
                    ? FilledButton.icon(onPressed: widget.onCreate, icon: const PhIcon('video-camera', size: 18), label: Text(t_('Create a reel')))
                    : OutlinedButton(onPressed: () => _load(refresh: true), child: Text(t_('Try again'))),
              ))))),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: pager,
          scrollDirection: Axis.vertical,
          allowImplicitScrolling: true,
          itemCount: reels.length,
          onPageChanged: (i) {
            setState(() { index = i; players.warm(reels, index); });
            if (i >= reels.length - 2) _load();
          },
          itemBuilder: (context, i) => ReelItem(
            key: ValueKey(reels[i]['public_id']),
            session: widget.session,
            reel: reels[i],
            playback: players.forReel(reels[i]),
            bottomInset: widget.bottomInset,
            playing: widget.active && i == index,
            muted: muted,
            onToggleMute: () => setState(() => muted = !muted),
            onRetry: () {
              if (!mounted || !sessionActive || !widget.active || i != index) return;
              if (!players.discardFailedFor(reels[i])) return;
              setState(() => players.warm(reels, index));
            },
          ),
        ),
        const Positioned(top: 0, left: 0, right: 0, height: 160,
          child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xB3000000), Color(0x00000000)],
          ))))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (widget.onCreate != null) IconButton(color: Colors.white, tooltip: t_('Create a reel'), onPressed: widget.onCreate, icon: const PhIcon('plus')),
              const Spacer(),
              Text(t_('Reels'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(color: Colors.white, tooltip: t_('Refresh'), icon: const PhIcon('arrow-clockwise'), onPressed: () => _load(refresh: true)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class ReelItem extends StatefulWidget {
  const ReelItem({super.key, required this.session, required this.reel, required this.playing, required this.muted, required this.onToggleMute, this.bottomInset = 0, this.playback, this.onRetry});
  final ReelPlayback? playback;
  final VoidCallback? onRetry;
  final Session session;
  final Map<String, dynamic> reel;
  final bool playing;
  final bool muted;
  final VoidCallback onToggleMute;
  final double bottomInset;
  @override
  State<ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<ReelItem> with SessionBoundState<ReelItem>, MediaVisibility<ReelItem> {
  @override Session get viewSession=>widget.session;
  @override void sessionRetired(){
    ++_playerEpoch;
    c?.removeListener(_playerChanged);
    if(widget.playback==null){c?.dispose();}else if(!widget.playback!.disposed){c?.pause();}
    c=null;ready=false;
  }
  VideoPlayerController? c;
  bool ready = false;
  bool failed = false;
  late int comments = (widget.reel['comments_count'] as num?)?.toInt() ?? 0;
  late bool following = (widget.reel['author'] as Map)['following'] == true;
  bool followBusy = false;
  int _playerEpoch = 0;

  Map<String, dynamic> get author => (widget.reel['author'] as Map).cast<String, dynamic>();
  String get id => widget.reel['public_id'] as String;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _playerChanged() {
    if (!mounted || !sessionActive || c?.value.hasError != true || failed) return;
    setState(() { failed = true; ready = false; });
  }

  void _retry() {
    if (!mounted || !sessionActive || !failed || !mediaVisible || !widget.playing) return;
    if (widget.playback != null) {
      widget.onRetry?.call();
      return;
    }
    c?.removeListener(_playerChanged); c?.dispose(); c = null;
    setState(_attach);
  }

  void _attach() {
    if(!sessionActive)return;
    final epoch = ++_playerEpoch;
    ready = false; failed = false;
    final media = (widget.reel['media'] as List).cast<Map<String, dynamic>>();
    final v = media.where((m) => m['type'] != 'image').toList();
    if (v.isEmpty) {
      failed = true;
      return;
    }
    final ctl = widget.playback?.controller ?? VideoPlayerController.networkUrl(Uri.parse(v.first['url'] as String));
    c = ctl;
    ctl.addListener(_playerChanged);
    if (widget.playback == null) ctl.setLooping(true);
    (widget.playback?.initialized ?? ctl.initialize()).then((_) {
      if (!mounted || !sessionActive || epoch != _playerEpoch || widget.playback?.disposed == true) return;
      if (ctl.value.hasError) { _playerChanged(); return; }
      ctl.setVolume(widget.muted ? 0 : 1);
      setState(() => ready = true);
      if (widget.playing && mediaVisible) ctl.play();
    }).catchError((_) {
      if (mounted && sessionActive && epoch == _playerEpoch) setState(() => failed = true);
    });
  }

  @override
  void didUpdateWidget(ReelItem old) {
    super.didUpdateWidget(old);
    if(!sessionActive)return;
    if(old.reel['public_id']!=id){comments=(widget.reel['comments_count'] as num?)?.toInt()??0;following=author['following']==true;followBusy=false;}
    if (!identical(old.playback, widget.playback)) {
      c?.removeListener(_playerChanged);
      if (old.playback == null) { c?.dispose(); } else if (!old.playback!.disposed) { c?.pause(); }
      c = null; _attach(); return;
    }
    final ctl = c;
    if (ctl == null || !ready || widget.playback?.disposed == true) return;
    if (widget.muted != old.muted) ctl.setVolume(widget.muted ? 0 : 1);
    if (widget.playing != old.playing) {
      widget.playing && mediaVisible ? ctl.play() : ctl.pause();
    }
  }

  @override
  void mediaVisibilityChanged(bool visible) {
    final ctl = c;
    if (!sessionActive || ctl == null || !ready || widget.playback?.disposed==true) return;
    visible && widget.playing ? ctl.play() : ctl.pause();
  }

  @override
  void dispose() {
    _playerEpoch++;
    c?.removeListener(_playerChanged);
    if (widget.playback == null) { c?.dispose(); } else if (!widget.playback!.disposed) { c?.pause(); }
    super.dispose();
  }

  void _comments() async {
    if(!mounted || !sessionActive)return;
    final target=id;
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => CommentsSheet(session: widget.session, postId: id, postAuthorId: author['public_id'].toString()),
    );
    if (!mounted || !sessionActive || id!=target) return;
    if (added != null && added != 0) setState(() => comments = (comments + added).clamp(0, 1 << 31));
    try {
      final result = await widget.session.call('GET', '/posts/$id') as Map;
      final count = (result['post'] as Map)['comments_count'] as int;
      if (mounted && sessionActive && id==target) setState(() => comments = count);
    } catch (_) { /* Keep the last known count until the next feed refresh. */ }
  }

  Future<void> _follow() async {
    if (!mounted || !sessionActive || followBusy) return;
    final target=id;
    final was = following;
    setState(() {
      followBusy = true;
      following = !was;
    });
    try {
      await widget.session.call(was ? 'DELETE' : 'POST', '/users/${author['username']}/follow');
    } catch (e) {
      if (mounted && sessionActive && id==target) {
        setState(() => following = was);
        showError(context, e);
      }
    } finally {
      if (mounted && sessionActive && id==target) setState(() => followBusy = false);
    }
  }

  bool get _mine => widget.session.user?['username'] == author['username'];

  Widget _followControl() => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
    onPressed: followBusy ? null : _follow,
    child: Text(t_(following ? 'Following' : 'Follow')),
  );

  Widget _side(PhData icon, String label, VoidCallback onTap, {Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(children: [
          IconButton(tooltip: label, iconSize: 30, style: IconButton.styleFrom(backgroundColor: Colors.transparent, minimumSize: const Size(44, 44), tapTargetSize: MaterialTapTargetSize.shrinkWrap), color: color, icon: PhIcon(icon), onPressed: (){if(mounted && sessionActive)onTap();}),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return const SizedBox.shrink();
    final ctl = c;
    final body = (widget.reel['body'] ?? '').toString();
    return Stack(fit: StackFit.expand, children: [
      if (failed)
        Positioned(top: 104, left: 24, right: 84, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t_('Video could not load'), style: const TextStyle(color: Colors.white70)),
          if (ReelPlayerPool.url(widget.reel) != null && (widget.playback == null || widget.onRetry != null))
            TextButton(style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(44, 44)), onPressed: widget.playing ? _retry : null, child: Text(t_('Try again'))),
        ]))
      else if (!ready || ctl == null)
        const Center(child: CircularProgressIndicator())
      else
        GestureDetector(
          onTap: () { if (sessionActive && mediaVisible && widget.playing) ctl.value.isPlaying ? ctl.pause() : ctl.play(); },
          child: ColoredBox(
            color: Colors.black,
            child: ClipRect(child: SizedBox.expand(child: FittedBox(
              // Portrait clips fill the viewing surface. Landscape stays fully
              // visible instead of losing its sides to a portrait crop.
              fit: ctl.value.aspectRatio <= 1 ? BoxFit.cover : BoxFit.contain,
              child: SizedBox(width: ctl.value.size.width, height: ctl.value.size.height, child: VideoPlayer(ctl)),
            ))),
          ),
        ),
      if (ready && ctl != null && !ctl.value.isPlaying) const Center(child: IgnorePointer(child: PhIcon('play-fill', size: 88, color: Colors.white54))),
      if (ready && ctl != null)
        Positioned(left: 0, right: 0, bottom: widget.bottomInset, child: VideoProgressIndicator(ctl, allowScrubbing: true, padding: EdgeInsets.zero, colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white24, backgroundColor: Colors.white12))),
      const Positioned(left: 0, right: 0, bottom: 0, height: 220, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Color(0x00000000)]))))),
      Positioned(
        left: 16,
        right: 84,
        bottom: 24 + widget.bottomInset,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () {if(mounted && sessionActive)Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: author['username'].toString())));},
            child: Row(children: [
              Avatar(user: author, radius: 18),
              const SizedBox(width: 10),
              Flexible(child: Text('@${author['username']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
              if (!_mine && MediaQuery.textScalerOf(context).scale(14) <= 20) ...[
                const SizedBox(width: 8),
                _followControl(),
              ],
            ]),
          ),
          if (!_mine && MediaQuery.textScalerOf(context).scale(14) > 20)
            Padding(padding: const EdgeInsets.only(top: 4), child: _followControl()),
          if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
        ]),
      ),
      Positioned(
        right: 4,
        bottom: 24 + widget.bottomInset,
        child: Column(children: [
          ReactionButton(session: widget.session, post: widget.reel, dark: true),
          _side(Ph.mode_comment_outlined, '$comments', _comments),
          if (!_mine) _side(Ph.card_giftcard, 'Gift', () => showGiftSheet(context, widget.session, id, author['username'].toString())),
          _side(widget.muted ? Ph.volume_off : Ph.volume_up, widget.muted ? 'Muted' : 'Sound', widget.onToggleMute),
        ]),
      ),
    ]);
  }
}
