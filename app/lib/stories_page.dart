import 'session_bound_state.dart';
import 'media_library_page.dart';
import 'creator_media_draft_store.dart';
import 'dart:convert' show jsonEncode;
import 'upload_center.dart';
import 'ph.dart';
import 'draft_exit_guard.dart';
import 'upload_notice.dart';
import 'dart:io';
import 'dart:typed_data';
import 'media_visibility.dart';
import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'ui.dart';

/// Row of story rings above the feed. First tile adds your own story.
class StoriesBar extends StatefulWidget {
  const StoriesBar({super.key, required this.session, this.contentRevision = 0});
  final Session session;
  final int contentRevision;
  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> with AutomaticKeepAliveClientMixin, SessionBoundState<StoriesBar> {
  @override Session get viewSession=>widget.session;
  @override void sessionRetired(){++_loadVersion;groups=[];loaded=false;}
  @override
  bool get wantKeepAlive => true;
  List<Map<String, dynamic>> groups = [];
  bool loaded = false;
  int _loadVersion = 0;
  late final uploads = UploadCenter.of(widget.session);
  int _uploadRevision = -1;
  void _mergeLocal() {
    final local = uploads.confirmedStories.where((p) => DateTime.tryParse((p['expires_at'] ?? '').toString())?.isBefore(DateTime.now()) != true).toList();
    if (local.isEmpty) return;
    final username = widget.session.user?['username'];
    final mine = groups.where((g) => (g['author'] as Map)['username'] == username).firstOrNull;
    final items = <Map<String, dynamic>>[...local, ...((mine?['items'] as List?) ?? []).cast<Map<String, dynamic>>()];
    final ids = <Object?>{};
    groups.removeWhere((g) => (g['author'] as Map)['username'] == username);
    groups.insert(0, {'author': widget.session.user, 'all_viewed': false, 'items': items.where((p) => ids.add(p['public_id'])).toList()});
  }
  void _published() {
    if (!mounted || !sessionActive || uploads.revision == _uploadRevision) return;
    _uploadRevision = uploads.revision;
    setState(_mergeLocal);
  }
  @override
  void dispose() { uploads.removeListener(_published); super.dispose(); }

  @override
  void initState() {
    super.initState();
    uploads.addListener(_published);
    _load();
  }

  @override
  void didUpdateWidget(StoriesBar old) {
    super.didUpdateWidget(old);
    if (old.contentRevision != widget.contentRevision) _load();
  }

  Future<void> _load() async {
    if(!sessionActive)return;
    final version = ++_loadVersion;
    try {
      final bundled = version == 1 ? await widget.session.takeHome('stories') : null;
      if(!mounted || !sessionActive || version!=_loadVersion)return;
      final j = (bundled is Map ? bundled.cast<String, dynamic>() : null) ?? await widget.session.call('GET', '/stories') as Map<String, dynamic>;
      if (mounted && sessionActive && version == _loadVersion) {
        setState(() {
          groups = (j['data'] as List).cast<Map<String, dynamic>>();
          _mergeLocal();
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted && sessionActive && version == _loadVersion) setState(() => loaded = true);
    }
  }

  Future<void> _add() async {
    if (!sessionActive)return;
    if (await addStory(context, widget.session) && mounted && sessionActive) await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if(!sessionActive)return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final me = widget.session.user?['username'];
    final mine = groups.where((g) => (g['author'] as Map)['username'] == me).toList();
    final others = groups.where((g) => (g['author'] as Map)['username'] != me).toList();
    Widget ring(Map<String, dynamic>? user, String label, VoidCallback onTap, {bool seen = false, bool plus = false}) => InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 84,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(alignment: Alignment.bottomRight, children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: seen ? scheme.outlineVariant : scheme.primary, width: 2.5)),
                  child: Avatar(user: user, radius: 32),
                ),
                if (plus)
                  CircleAvatar(radius: 10, backgroundColor: scheme.primary, child: PhIcon('plus', size: 14, color: scheme.onPrimary)),
              ]),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        );
    final tiles = <Widget>[
      if (mine.isEmpty)
        ring(widget.session.user, t_('Your story'), _add, seen: true, plus: true)
      else
        ring(widget.session.user, t_('Your story'), () => _open(mine.first), seen: mine.first['all_viewed'] == true),
      for (final g in others) ring((g['author'] as Map).cast<String, dynamic>(), '${(g['author'] as Map)['username']}', () => _open(g), seen: g['all_viewed'] == true),
    ];

    return SizedBox(
      height: 90 + 24 * (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        itemCount: tiles.length + (mine.isNotEmpty ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (mine.isNotEmpty && i == 1) {
            return InkWell(onTap: _add, child: SizedBox(width: 56, child: Center(child: PhIcon('plus-circle', color: scheme.primary, size: 32))));
          }
          final k = mine.isNotEmpty && i > 1 ? i - 1 : i;
          return tiles[k];
        },
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> group) async {
    if(!sessionActive)return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryViewer(session: widget.session, group: group)));
    if(mounted && sessionActive)_load();
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

class _StoryViewerState extends State<StoryViewer> with MediaVisibility<StoryViewer>, SessionBoundState<StoryViewer> {
  @override Session get viewSession=>widget.session;
  BuildContext? _overlay;
  void _clearMedia(){
    ++_startVersion;timer?.cancel();timer=null;
    final bytes=storyBytes;storyBytes=null;storyHeaders=const {};
    if(bytes!=null)unawaited(MemoryImage(bytes).evict());
    final ctl=video;video=null;
    if(ctl!=null){unawaited(ctl.pause().catchError((_){}));unawaited(ctl.dispose());}
  }
  @override void sessionRetired(){
    _clearMedia();
    final overlay=_overlay;_overlay=null;
    if(overlay!=null && overlay.mounted && ModalRoute.of(overlay)?.isCurrent==true)Navigator.of(overlay).pop();
  }
  late final List<Map<String, dynamic>> items = (widget.group['items'] as List).cast<Map<String, dynamic>>();
  int index = 0;
  Timer? timer;
  VideoPlayerController? video;
  double progress = 0;
  bool paused = false;
  int _startVersion = 0;
  bool mediaLoading = true;
  String? mediaError;
  Uint8List? storyBytes;
  Map<String,String> storyHeaders = const {};

  Map<String, dynamic> get author => (widget.group['author'] as Map).cast<String, dynamic>();
  bool get isMine => author['username'] == widget.session.user?['username'];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() { _clearMedia(); super.dispose(); }

  Future<void> _start() async {
    if(!sessionActive)return;
    final version = ++_startVersion;
    timer?.cancel();
    final previous=video;video=null;
    await previous?.dispose();
    if (!mounted || !sessionActive || version != _startVersion) return;
    video = null;
    progress = 0;
    final previousBytes = storyBytes;
    if (previousBytes != null) unawaited(MemoryImage(previousBytes).evict());
    storyBytes = null;
    mediaError = null;
    mediaLoading = true;
    storyHeaders = const {};
    setState(() {});
    final item = items[index];
    if (item['protected_media'] == true) {
      try {
        final url = item['url'] as String;
        final headers = await widget.session.privateMediaHeaders(url);
        if(!mounted || !sessionActive || version!=_startVersion)return;
        final bytes = item['type'] == 'video' ? null : await widget.session.fetchProtectedBytes(url);
        if (!mounted || !sessionActive || version != _startVersion) return;
        storyHeaders = headers;
        storyBytes = bytes;
      } catch (_) {
        if (mounted && sessionActive && version == _startVersion) setState(() { mediaLoading = false; mediaError = t_('This story is unavailable. It may have expired or its audience changed.'); });
        return;
      }
    }
    if(!mounted || !sessionActive || version!=_startVersion)return;
    widget.session.call('POST', '/stories/${item['public_id']}/view').catchError((_) => null);
    var total = const Duration(seconds: 6);
    if (item['type'] == 'video') {
      final c = VideoPlayerController.networkUrl(Uri.parse(item['url'] as String), httpHeaders: storyHeaders);
      video = c;
      try {
        await c.initialize();
        if (!mounted || !sessionActive || version != _startVersion) return;
        if (mediaVisible && !paused) await c.play();
        total = c.value.duration > Duration.zero ? c.value.duration : total;
      } catch (_) {
        if (mounted && sessionActive && version == _startVersion) setState(() { mediaLoading = false; mediaError = t_('This story is unavailable. It may have expired or its audience changed.'); });
        return;
      }
    }
    if (!mounted || !sessionActive || version != _startVersion) return;
    setState(() => mediaLoading = false);
    const tick = Duration(milliseconds: 50);
    timer = Timer.periodic(tick, (t) {
      if (!sessionActive || paused || !mediaVisible) return;
      progress += tick.inMilliseconds / total.inMilliseconds;
      if (progress >= 1) {
        t.cancel();
        _next();
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void mediaVisibilityChanged(bool visible) {
    final ctl = video;
    if (!sessionActive || ctl == null || !ctl.value.isInitialized) return;
    visible && !paused ? ctl.play() : ctl.pause();
  }

  void _pause(bool value) {
    if (!mounted || !sessionActive) return;
    paused = value;
    final ctl = video;
    if (!sessionActive || ctl == null || !ctl.value.isInitialized) return;
    !value && mediaVisible ? ctl.play() : ctl.pause();
  }

  void _next() {
    if(!sessionActive)return;
    if (index < items.length - 1) {
      index += 1;
      _start();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if(!sessionActive)return;
    if (index > 0) index -= 1;
    _start();
  }

  Future<void> _delete() async {
    if(!sessionActive)return;
    final version=_startVersion;
    final storyId=items[index]['public_id'];
    _pause(true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) { _overlay=ctx; return AlertDialog(
        title: Text(t_('Delete this story?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t_('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t_('Delete'))),
        ],
      ); },
    );
    _overlay=null;
    if (!mounted || !sessionActive || version!=_startVersion) return;
    if (ok != true) {
      _pause(false);
      return;
    }
    try {
      await widget.session.call('DELETE', '/stories/$storyId');
      if (mounted && sessionActive && version==_startVersion) Navigator.of(context).pop();
    } catch (e) {
      _pause(false);
      if (mounted && sessionActive && version==_startVersion) showError(context, e);
    }
  }

  Future<void> _viewers() async {
    if(!sessionActive)return;
    final version=_startVersion;
    final storyId=items[index]['public_id'];
    _pause(true);
    try {
      final j = await widget.session.call('GET', '/stories/$storyId/viewers') as Map<String, dynamic>;
      if(!mounted || !sessionActive || version!=_startVersion)return;
      final list = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) { _overlay=ctx; return SafeArea(
          child: list.isEmpty
              ? Padding(padding: const EdgeInsets.all(32), child: Text(t_('No views yet')))
              : ListView(shrinkWrap: true, children: [
                  for (final u in list) ListTile(leading: Avatar(user: u), title: Text('${u['name'] ?? u['username']}'), subtitle: Text('@${u['username']}')),
                ]),
        ); },
      );
      _overlay=null;
    } catch (e) {
      if (mounted && sessionActive && version==_startVersion) showError(context, e);
    }
    _pause(false);
  }

  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return retiredSessionView();
    final item = items[index];
    final caption = (item['caption'] as String?) ?? '';
    Widget media;
    if (mediaError != null) {
      media = Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(mediaError!,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white)),const SizedBox(height:12),TextButton(onPressed:_start,child:Text(t_('Try again')))])));
    } else if (mediaLoading) {
      media = const Center(child:CircularProgressIndicator());
    } else if (item['type'] == 'video') {
      final c = video;
      media = (c != null && c.value.isInitialized)
          ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
          : const Center(child: CircularProgressIndicator());
    } else if (storyBytes != null) {
      media = Center(child:Image.memory(storyBytes!,width:double.infinity,height:double.infinity,fit:BoxFit.contain,errorBuilder:(_,e,s)=>Text(t_('Photo preview unavailable'),style:const TextStyle(color:Colors.white))));
    } else {
      media = Center(
        child: Image.network(
          item['url'] as String,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, p) => p == null ? child : const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, __, ___) => const PhIcon('image-broken', color: Colors.white54, size: 48),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onLongPressStart: (_) => _pause(true),
          onLongPressEnd: (_) => _pause(false),
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
            const Positioned(top:0,left:0,right:0,height:160,child:IgnorePointer(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,stops:[0,.6,1],colors:[Colors.black87,Colors.black87,Colors.transparent]))))),
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
                Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[Text('${author['username']}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600)),Text(ago(item['created_at'] as String),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white70,fontSize:12))])),
                if (isMine) IconButton(tooltip:t_('Story viewers'),onPressed: _viewers, icon: const PhIcon('eye', color: Colors.white)),
                if (isMine) IconButton(tooltip:t_('Delete story'),onPressed: _delete, icon: const PhIcon('trash', color: Colors.white)),
                IconButton(tooltip:t_('Close'),onPressed: () => Navigator.of(context).pop(), icon: const PhIcon('x', color: Colors.white)),
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

/// Picks a photo or video, opens review, and returns true only after explicit sharing.
Future<bool> addStory(BuildContext context, Session session) async {
    final owner=session.user?['public_id'];final generation=session.generation;
    bool active()=>owner!=null && session.user?['public_id']==owner && session.generation==generation;
    if(!active())return false;
    UploadCenter.of(session);
    final chosen = await chooseCreatorMedia(context, CreatorKind.story);
    if (chosen == null || chosen.isEmpty || !context.mounted || !active()) return false;
    final x = chosen.first.file;
    final isVideo = chosen.first.isVideo;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => StoryComposePage(session: session, file: x, isVideo: isVideo, backgroundUpload: true)));
    return result == true;
}

/// Picking is not publication. Keep the selected file and caption until the
/// member explicitly shares or discards, including after an upload error.
class StoryComposePage extends StatefulWidget {
  const StoryComposePage({super.key, required this.session, required this.file, required this.isVideo, this.backgroundUpload = false,this.initialMediaDraft});
  final CreatorMediaDraft? initialMediaDraft;
  final Session session;
  final XFile file;
  final bool isVideo;
  final bool backgroundUpload;
  @override
  State<StoryComposePage> createState() => _StoryComposePageState();
}

class _StoryComposePageState extends State<StoryComposePage> {
  final caption = TextEditingController();
  late Future<Uint8List> bytes = widget.file.readAsBytes();
  bool busy = false;
  bool handedOff = false;
  String? error;
  String intent = newUploadIntent();
  String audience = 'followers';
  bool audienceLocked = false;
  UploadError? uploadError;
  CreatorMediaDraft? _saved;
  bool _saving=false;
  late final String? _owner;
  late final Session _boundSession;
  late final int _generation;
  String? _savedFingerprint;
  bool get _active=>identical(widget.session,_boundSession) && _owner!=null && widget.session.user?['public_id']==_owner && widget.session.generation==_generation;
  String get _fingerprint=>jsonEncode([caption.text,audience,widget.isVideo]);
  void _changed(){if(mounted)setState((){});}
  @override void initState(){
    super.initState();
    _boundSession=widget.session;_owner=widget.session.user?['public_id'] as String?;_generation=widget.session.generation;
    widget.session.addListener(_changed);caption.addListener(_changed);
    _saved=widget.initialMediaDraft;
    if(_saved!=null){
      if(!_saved!.story || _saved!.video!=widget.isVideo || _saved!.audience==null)throw StateError('This is not a matching story draft');
      caption.text=_saved!.text;audience=_saved!.audience!;audienceLocked=_saved!.attempted;
      _savedFingerprint=_fingerprint;
    }
    if(widget.backgroundUpload || _saved!=null)UploadCenter.of(widget.session);
  }
  Future<void> _save()async{
    if(!_active || busy || _saving || handedOff)return;
    final snapshot=_fingerprint;final text=caption.text;final selectedAudience=audience;
    setState(()=>_saving=true);
    try{
      final data=await bytes;
      if(!_active)return;
      final draft=await const CreatorMediaDraftStore().save(_owner!,text:text,video:widget.isVideo,files:[XFile.fromData(data,path:widget.file.path,name:widget.file.name)],story:true,audience:selectedAudience,id:_saved?.id,expectedRevision:_saved?.revision,expectedStamp:_saved?.stamp);
      if(mounted && _active){setState((){_saved=draft;_savedFingerprint=snapshot;});showInfo(context,t_('Media draft saved on this device. Nothing was posted.'));}
    }catch(e){if(mounted && _active)showError(context,e);}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  Future<void> _separate()async{
    final draft=_saved;
    if(draft==null || !_active || busy || _saving)return;
    if(!await confirmNewUpload(context) || !mounted || !_active || _saved!=draft)return;
    setState(()=>_saving=true);
    try{
      final next=await const CreatorMediaDraftStore().attempted(_owner!,draft,value:false);
      if(mounted && _active)setState((){_saved=next;intent=newUploadIntent();audienceLocked=false;error=null;uploadError=null;});
    }catch(e){if(mounted && _active)showError(context,e);}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  @override
  void dispose() { _boundSession.removeListener(_changed);caption.removeListener(_changed);caption.dispose(); super.dispose(); }

  Future<void> share() async {
    if (!_active || busy || _saving || uploadError?.terminal == true) return;
    if (!widget.session.protectedStoriesEnabled) { showInfo(context, t_('Story sharing needs the protected-story server update. Your draft is still here.')); return; }
    final saved=_saved;
    if(saved!=null){
      if(saved.attempted){showInfo(context,t_('This saved draft may already be posted. Check your profile before preparing a separate upload.'));return;}
      if(_savedFingerprint!=_fingerprint){showInfo(context,t_('Save media changes before posting this draft.'));return;}
      if(UploadCenter.of(widget.session).occupied){showInfo(context,t_('Check the current upload before starting another.'));return;}
      setState(()=>_saving=true);
      try{
        final marked=await const CreatorMediaDraftStore().attempted(_owner!,saved,value:true);
        if(!mounted || !_active)return;
        setState(()=>_saved=marked);
        final recovered=await const CreatorMediaDraftStore().open(_owner,marked);
        if(!mounted || !_active)return;
        bytes=recovered.single.readAsBytes();
      }catch(e){if(mounted && _active)showError(context,e);return;}
      finally{if(mounted)setState(()=>_saving=false);}
    }
    setState(() => audienceLocked = true);
    if (widget.backgroundUpload) {
      final session = widget.session;
      final center = UploadCenter.of(session);
      final originalCaption = caption.text.trim();
      final originalAudience = audience;
      final originalIntent = intent;
      final generation = center.generation;
      final originalOwner = session.user?['public_id'];
      final originalBytes = bytes;
      final fileName = widget.file.name;
      final isVideo = widget.isVideo;
      final started = center.start('story', () async {
        final data = await originalBytes;
        if (data.length > 25 * 1024 * 1024) throw ApiError(t_('That file is over 25 MB. Choose a smaller one.'));
        if (center.generation != generation || session.user?['public_id'] != originalOwner) throw ApiError('Please sign in again.', 401);
        center.sending();
        final value = await session.upload('/stories', fields: {'caption': originalCaption, 'protected_media':'1', 'audience':originalAudience}, file: UploadFile(data, mimeFor(fileName, video: isVideo), fileName), intent: originalIntent);
        return (value['story'] as Map).cast<String, dynamic>();
      });
      if (!started) { showInfo(context, 'Check the current upload before starting another.'); return; }
      setState(() => handedOff = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _active) Navigator.of(context).pop(false);
      return;
    }
    setState(() { busy = true; error = null; uploadError = null; });
    try {
      final data = await bytes;
      if (data.length > 25 * 1024 * 1024) throw ApiError(t_('That file is over 25 MB. Choose a smaller one.'));
      if(!mounted || !_active)return;
      await widget.session.upload('/stories', fields: {'caption': caption.text.trim(), 'protected_media':'1', 'audience':audience}, file: UploadFile(data, mimeFor(widget.file.name, video: widget.isVideo), widget.file.name), intent: intent);
      if (mounted && _active) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { busy = false; error = e.toString(); uploadError = e is UploadError ? e : null; });
    }
  }

  Future<void> chooseAudience() async {
    if(!_active || busy || _saving || audienceLocked)return;
    final choice=await showModalBottomSheet<String>(context:context,isScrollControlled:true,builder:(c)=>SafeArea(child:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(t_('Who can see this story'),style:Theme.of(c).textTheme.titleMedium),
      for(final option in [('followers','Followers'),('close_friends','Close friends'),('only_me','Only me')])ListTile(title:Text(t_(option.$2)),trailing:PhIcon(audience==option.$1?'check-circle-fill':'circle',size:24),onTap:()=>Navigator.of(c).pop(option.$1)),
      Text(t_('Close friends can view it even if they do not follow you. Hide my stories and blocking take priority.')),
    ])))));
    if(choice!=null && mounted && _active && !_saving)setState(()=>audience=choice);
  }

  Future<void> openOriginal() async {
    if(!_active)return;
    final id = uploadError?.resourceId;
    if (id == null) return;
    try {
      final result = await widget.session.call('GET', '/stories') as Map;
      for (final value in result['data'] as List) {
        final group = (value as Map).cast<String, dynamic>();
        final original = (group['items'] as List).where((item) => item['public_id'] == id).toList();
        if (original.isNotEmpty && mounted && _active) {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryViewer(session: widget.session, group: {'author': group['author'], 'items': original})));
          return;
        }
      }
      if (mounted && _active) showInfo(context, t_('The original story was removed or expired.'));
    } catch (e) { if (mounted) showError(context, e); }
  }

  @override
  Widget build(BuildContext context) {
   if(!_active)return Scaffold(appBar:AppBar(title:Text(t_('Local draft'))),body:Padding(padding:const EdgeInsets.all(20),child:Text(t_('This editor belongs to another signed-in session. Close it and sign in again to continue.'))));
   return DraftExitGuard(hasChanges: !handedOff && _savedFingerprint!=_fingerprint, busy: busy || _saving, child: Scaffold(
    appBar: AppBar(title: Text(t_('Your story')),actions:[IconButton(tooltip:t_('Save media draft'),onPressed:busy || _saving || handedOff || _saved?.attempted==true?null:_save,icon:const PhIcon('bookmark-simple'))]),
    body: SafeArea(top: false, child: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
      if(_saved?.attempted==true)Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t_('This saved draft may already be posted. Check your profile before preparing a separate upload.')),TextButton(onPressed:busy || _saving?null:_separate,child:Text(t_('Prepare a separate upload')))]),
        if(_saved!=null && !_saved!.attempted)Text(t_('Local draft. Posting is manual. The saved copy stays in Drafts until you delete it.')),
        Text(t_('Preview'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(t_('Disappears after 24 hours'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        ClipRRect(borderRadius: BorderRadius.circular(16), child: ColoredBox(color: Colors.black, child: SizedBox(height: 280, child: widget.isVideo
          ? widget.file.path.contains('://')?Center(child:Text(t_('Video preview unavailable. Your video is still selected.'),textAlign:TextAlign.center,style:const TextStyle(color:Colors.white))):_StoryVideoPreview(file: widget.file)
          : FutureBuilder<Uint8List>(future: bytes, builder: (_, value) => value.hasData
            ? Image.memory(value.data!, fit: BoxFit.contain, errorBuilder: (_, error, stack) => Center(child: Text(t_('Photo preview unavailable'), style: const TextStyle(color: Colors.white))))
            : value.hasError ? Center(child: Text(t_('File could not be read'), style: const TextStyle(color: Colors.white))) : const Center(child: CircularProgressIndicator()))))),
        const SizedBox(height: 16),
        TextField(controller: caption, enabled: !busy && !_saving, maxLength: 200, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: t_('Caption (optional)'))),
        if (widget.session.protectedStoriesEnabled) ...[
          Text(t_('Hidden people and blocked people cannot view it. People can save what they see.')),
          const SizedBox(height:16),
        ] else Padding(padding:const EdgeInsets.only(bottom:16),child:Text(t_('Story sharing needs the protected-story server update. Your draft is still here.'))),
      ])),
      if (widget.session.protectedStoriesEnabled) Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Tooltip(message:t_('Who can see this story'),child:TextButton.icon(onPressed:busy || _saving || audienceLocked?null:chooseAudience,icon:const PhIcon('users',size:20),label:Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(t_(audience=='close_friends'?'Close friends':audience=='only_me'?'Only me':'Followers'),maxLines:2)),const SizedBox(width:8),const PhIcon('caret-down',size:16)])))),
      if (error != null) UploadNotice(
        message: error!,
        openOriginal: uploadError?.resourceId == null ? null : openOriginal,
        prepareNew: uploadError?.terminal == true ? () async {
          if (await confirmNewUpload(context) && mounted && _active) setState(() { intent = newUploadIntent(); audienceLocked = false; error = null; uploadError = null; });
        } : null,
        newLabel: 'Prepare a new story',
      ),
      Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: !widget.session.protectedStoriesEnabled || busy || _saving || _saved?.attempted==true || handedOff || uploadError?.terminal == true ? null : share,
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const PhIcon('paper-plane-tilt', size: 20),
        label: Text(t_(busy ? 'Sharing...' : error != null && uploadError?.terminal != true ? 'Try again' : 'Share story'))))),
    ])),
  ));
  }
}

class _StoryVideoPreview extends StatefulWidget {
  const _StoryVideoPreview({required this.file});
  final XFile file;
  @override
  State<_StoryVideoPreview> createState() => _StoryVideoPreviewState();
}
class _StoryVideoPreviewState extends State<_StoryVideoPreview> with MediaVisibility<_StoryVideoPreview> {
  late final controller = VideoPlayerController.file(File(widget.file.path));
  bool ready = false;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    controller.initialize().then((_) { if (mounted) setState(() => ready = true); }).catchError((Object e) { if (mounted) setState(() => failed = true); });
    controller.addListener(changed);
  }
  void changed() { if (mounted) setState(() {}); }
  @override
  void mediaVisibilityChanged(bool visible) { if (!visible && ready) controller.pause(); }
  @override
  void dispose() { controller.removeListener(changed); controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => failed ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t_('Video preview unavailable. Your video is still selected.'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))))
    : !ready ? const Center(child: CircularProgressIndicator())
    : Center(child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: Stack(alignment: Alignment.center, children: [
      VideoPlayer(controller),
      IconButton(tooltip: t_(controller.value.isPlaying ? 'Pause' : 'Play'), onPressed: () { if (mediaVisible) controller.value.isPlaying ? controller.pause() : controller.play(); }, icon: PhIcon(controller.value.isPlaying ? 'pause-circle' : 'play-circle', color: Colors.white, size: 44)),
    ])));
}
