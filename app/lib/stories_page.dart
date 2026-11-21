import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'glass/glass_sheet.dart';
import 'ui.dart';

/// Row of story rings above the feed. First tile adds your own story.
class StoriesBar extends StatefulWidget {
  const StoriesBar({super.key, required this.session});
  final Session session;
  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  List<Map<String, dynamic>> groups = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/stories') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          groups = (j['data'] as List).cast<Map<String, dynamic>>();
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  Future<void> _add() async {
    final picker = ImagePicker();
    final source = await showGlassSheet<String>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_outlined), title: Text(t_('Photo')), onTap: () => Navigator.pop(ctx, 'photo')),
        ListTile(leading: const Icon(Icons.videocam_outlined), title: Text(t_('Video')), onTap: () => Navigator.pop(ctx, 'video')),
      ]),
    );
    if (source == null) return;
    final x = source == 'photo'
        ? await picker.pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 78)
        : await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 20));
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    try {
      showInfo(context, t_('Posting your story...'));
      await widget.session.upload('/stories', file: UploadFile(bytes, mimeFor(x.name, video: source == 'video'), x.name));
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = widget.session.user?['username'];
    final mine = groups.where((g) => (g['author'] as Map)['username'] == me).toList();
    final others = groups.where((g) => (g['author'] as Map)['username'] != me).toList();
    // Instagram rings: unseen is a 2px gradient ring, seen is a 1px grey ring.
    // Avatar is 60px, name is 12px.
    Widget ring(Map<String, dynamic>? user, String label, VoidCallback onTap, {bool seen = false, bool plus = false}) {
      final inner = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface),
        child: Avatar(user: user, radius: 30),
      );
      final circled = seen
          ? Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant, width: 1)),
              child: inner,
            )
          : Container(
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF515BD4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: inner,
            );
      return InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(alignment: Alignment.bottomRight, children: [
              circled,
              if (plus)
                CircleAvatar(radius: 10, backgroundColor: brandRed, child: Icon(Icons.add, size: 14, color: scheme.onPrimary)),
            ]),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
    }
    final tiles = <Widget>[
      if (mine.isEmpty)
        ring(widget.session.user, t_('Your story'), _add, seen: true, plus: true)
      else
        ring(widget.session.user, t_('Your story'), () => _open(mine.first), seen: mine.first['all_viewed'] == true),
      for (final g in others) ring((g['author'] as Map).cast<String, dynamic>(), '${(g['author'] as Map)['username']}', () => _open(g), seen: g['all_viewed'] == true),
    ];
    if (!loaded && groups.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        itemCount: tiles.length + (mine.isNotEmpty ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (mine.isNotEmpty && i == 1) {
            return InkWell(onTap: _add, child: SizedBox(width: 56, child: Center(child: Icon(Icons.add_circle_outline, color: scheme.primary, size: 32))));
          }
          final k = mine.isNotEmpty && i > 1 ? i - 1 : i;
          return tiles[k];
        },
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> group) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryViewer(session: widget.session, group: group)));
    _load();
  }
}

/// Full screen viewer. Tap right or left to move, tap and hold to pause.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.session, required this.group});
  final Session session;
  final Map<String, dynamic> group;
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late final List<Map<String, dynamic>> items = (widget.group['items'] as List).cast<Map<String, dynamic>>();
  int index = 0;
  Timer? timer;
  VideoPlayerController? video;
  double progress = 0;
  bool paused = false;

  Map<String, dynamic> get author => (widget.group['author'] as Map).cast<String, dynamic>();
  bool get isMine => author['username'] == widget.session.user?['username'];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    timer?.cancel();
    video?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    timer?.cancel();
    await video?.dispose();
    video = null;
    progress = 0;
    final item = items[index];
    widget.session.call('POST', '/stories/${item['public_id']}/view').catchError((_) => null);
    var total = const Duration(seconds: 6);
    if (item['type'] == 'video') {
      final c = VideoPlayerController.networkUrl(Uri.parse(item['url'] as String));
      video = c;
      try {
        await c.initialize();
        await c.play();
        total = c.value.duration > Duration.zero ? c.value.duration : total;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {});
    const tick = Duration(milliseconds: 50);
    timer = Timer.periodic(tick, (t) {
      if (paused) return;
      progress += tick.inMilliseconds / total.inMilliseconds;
      if (progress >= 1) {
        t.cancel();
        _next();
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  void _next() {
    if (index < items.length - 1) {
      index += 1;
      _start();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (index > 0) index -= 1;
    _start();
  }

  Future<void> _delete() async {
    paused = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t_('Delete this story?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t_('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t_('Delete'))),
        ],
      ),
    );
    if (ok != true) {
      paused = false;
      return;
    }
    try {
      await widget.session.call('DELETE', '/stories/${items[index]['public_id']}');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      paused = false;
      if (mounted) showError(context, e);
    }
  }

  Future<void> _viewers() async {
    paused = true;
    try {
      final j = await widget.session.call('GET', '/stories/${items[index]['public_id']}/viewers') as Map<String, dynamic>;
      final list = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showGlassSheet<void>(
        context,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: list.isEmpty
              ? Padding(padding: const EdgeInsets.all(32), child: Text(t_('No views yet')))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final u in list) ListTile(leading: Avatar(user: u), title: Text('${u['name'] ?? u['username']}'), subtitle: Text('@${u['username']}')),
                ]),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
    paused = false;
  }

  @override
  Widget build(BuildContext context) {
    final item = items[index];
    final caption = (item['caption'] as String?) ?? '';
    Widget media;
    if (item['type'] == 'video') {
      final c = video;
      media = (c != null && c.value.isInitialized)
          ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
          : const Center(child: CircularProgressIndicator());
    } else {
      media = Center(
        child: Image.network(
          item['url'] as String,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, p) => p == null ? child : const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onLongPressStart: (_) => paused = true,
          onLongPressEnd: (_) => paused = false,
          onTapUp: (d) {
            final w = MediaQuery.of(context).size.width;
            if (d.localPosition.dx < w / 3) {
              _prev();
            } else {
              _next();
            }
          },
          child: Stack(children: [
            Positioned.fill(child: media),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: LinearProgressIndicator(
                        value: i < index ? 1 : (i == index ? progress.clamp(0, 1).toDouble() : 0),
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ]),
            ),
            Positioned(
              top: 20,
              left: 12,
              right: 4,
              child: Row(children: [
                Avatar(user: author, radius: 16),
                const SizedBox(width: 8),
                Expanded(child: Text('${author['username']}  ${ago(item['created_at'] as String)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                if (isMine) IconButton(onPressed: _viewers, icon: const Icon(Icons.visibility_outlined, color: Colors.white)),
                if (isMine) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: Colors.white)),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            if (caption.isNotEmpty)
              Positioned(left: 16, right: 16, bottom: 28, child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 6)]))),
          ]),
        ),
      ),
    );
  }
}
