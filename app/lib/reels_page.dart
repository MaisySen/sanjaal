import 'ph.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';
import 'feed_page.dart' show CommentsSheet;
import 'gifts.dart';
import 'profile_pages.dart';
import 'reactions.dart';
import 'ui.dart';

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

class _ReelsPageState extends State<ReelsPage> {
  final reels = <Map<String, dynamic>>[];
  final pager = PageController();
  int index = 0;
  String? cursor;
  bool loading = false;
  bool _refreshQueued = false;
  bool done = false;
  String? error;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  @override
  void didUpdateWidget(ReelsPage old) {
    super.didUpdateWidget(old);
    if (old.contentRevision != widget.contentRevision) _load(refresh: true);
  }

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (loading) { if (refresh) _refreshQueued = true; return; }
    if (done && !refresh) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await widget.session.call('GET', '/posts', query: {'kind': 'reel', if (!refresh && cursor != null) 'cursor': cursor!}) as Map<String, dynamic>;
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        if (refresh) { reels.clear(); index = 0; }
        reels.addAll(items);
        cursor = j['next_cursor'] as String?;
        done = cursor == null;
      });
      if (refresh) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && pager.hasClients) pager.jumpToPage(0); });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load reels. Try again.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (_refreshQueued) { _refreshQueued = false; _load(refresh: true); }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (reels.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t_('Reels'))),
        body: Padding(padding: const EdgeInsets.only(bottom: 88), child: loading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: Ph.movie_outlined,
                title: error ?? t_('No reels yet'),
                hint: error == null ? t_('Share a short video with your community.') : null,
                action: error == null && widget.onCreate != null
                    ? FilledButton.icon(onPressed: widget.onCreate, icon: const PhIcon('video-camera', size: 18), label: Text(t_('Create a reel')))
                    : OutlinedButton(onPressed: () => _load(refresh: true), child: Text(t_('Try again'))),
              )),
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
            setState(() => index = i);
            if (i >= reels.length - 2) _load();
          },
          itemBuilder: (context, i) => ReelItem(
            key: ValueKey(reels[i]['public_id']),
            session: widget.session,
            reel: reels[i],
            bottomInset: widget.bottomInset,
            playing: widget.active && i == index,
            muted: muted,
            onToggleMute: () => setState(() => muted = !muted),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Text(t_('Reels'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(color: Colors.white, tooltip: 'Refresh', icon: const PhIcon('arrow-clockwise'), onPressed: () => _load(refresh: true)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class ReelItem extends StatefulWidget {
  const ReelItem({super.key, required this.session, required this.reel, required this.playing, required this.muted, required this.onToggleMute, this.bottomInset = 0});
  final Session session;
  final Map<String, dynamic> reel;
  final bool playing;
  final bool muted;
  final VoidCallback onToggleMute;
  final double bottomInset;
  @override
  State<ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<ReelItem> {
  VideoPlayerController? c;
  bool ready = false;
  bool failed = false;
  late int comments = (widget.reel['comments_count'] as num?)?.toInt() ?? 0;
  late bool following = (widget.reel['author'] as Map)['following'] == true;
  bool followBusy = false;

  Map<String, dynamic> get author => (widget.reel['author'] as Map).cast<String, dynamic>();
  String get id => widget.reel['public_id'] as String;

  @override
  void initState() {
    super.initState();
    final media = (widget.reel['media'] as List).cast<Map<String, dynamic>>();
    final v = media.where((m) => m['type'] != 'image').toList();
    if (v.isEmpty) {
      failed = true;
      return;
    }
    final ctl = VideoPlayerController.networkUrl(Uri.parse(v.first['url'] as String));
    c = ctl;
    ctl.setLooping(true);
    ctl.initialize().then((_) {
      if (!mounted) return;
      ctl.setVolume(widget.muted ? 0 : 1);
      setState(() => ready = true);
      if (widget.playing) ctl.play();
    }).catchError((_) {
      if (mounted) setState(() => failed = true);
    });
  }

  @override
  void didUpdateWidget(ReelItem old) {
    super.didUpdateWidget(old);
    final ctl = c;
    if (ctl == null || !ready) return;
    if (widget.muted != old.muted) ctl.setVolume(widget.muted ? 0 : 1);
    if (widget.playing != old.playing) {
      widget.playing ? ctl.play() : ctl.pause();
    }
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
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

  Future<void> _follow() async {
    if (followBusy) return;
    final was = following;
    setState(() {
      followBusy = true;
      following = !was;
    });
    try {
      await widget.session.call(was ? 'DELETE' : 'POST', '/users/${author['username']}/follow');
    } catch (e) {
      if (mounted) {
        setState(() => following = was);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  bool get _mine => widget.session.user?['username'] == author['username'];

  Widget _side(PhData icon, String label, VoidCallback onTap, {Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(children: [
          IconButton(tooltip: label, iconSize: 30, style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.55), fixedSize: const Size(52, 52)), color: color, icon: PhIcon(icon), onPressed: onTap),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ctl = c;
    final body = (widget.reel['body'] ?? '').toString();
    return Stack(fit: StackFit.expand, children: [
      if (failed)
        const Positioned(top: 104, left: 24, right: 84, child: Text('Video could not load', style: TextStyle(color: Colors.white70)))
      else if (!ready || ctl == null)
        const Center(child: CircularProgressIndicator())
      else
        GestureDetector(
          onTap: () => ctl.value.isPlaying ? ctl.pause() : ctl.play(),
          child: ColoredBox(
            color: Colors.black,
            child: Center(child: AspectRatio(aspectRatio: ctl.value.aspectRatio, child: VideoPlayer(ctl))),
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
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: author['username'].toString()))),
            child: Row(children: [
              Avatar(user: author, radius: 18),
              const SizedBox(width: 10),
              Flexible(child: Text('@${author['username']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
            ]),
          ),
          if (!_mine)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 48,
                child: following
                    ? OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)), onPressed: _follow, child: const Text('Following'))
                    : FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: Colors.white, foregroundColor: Colors.black), onPressed: _follow, child: const Text('Follow')),
              ),
            ),
          if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
        ]),
      ),
      Positioned(
        right: 4,
        bottom: 24 + widget.bottomInset,
        child: Column(children: [
          ReactionButton(session: widget.session, post: widget.reel, dark: true),
          _side(Ph.mode_comment_outlined, '$comments', _comments),
          _side(Ph.card_giftcard, 'Gift', () => showGiftSheet(context, widget.session, id, author['username'].toString())),
          _side(widget.muted ? Ph.volume_off : Ph.volume_up, widget.muted ? 'Muted' : 'Sound', widget.onToggleMute),
        ]),
      ),
    ]);
  }
}
