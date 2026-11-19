import 'dart:async';
import 'upload_pending_store.dart';
import 'post_page.dart';
import 'stories_page.dart' show StoryViewer;
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ph.dart';
import 'ui.dart';

/// App-lifetime work, not an OS background-upload service. Never retries on its
/// own. A job owns an immutable draft and intent, independent of its composer.
class UploadCenter extends ChangeNotifier {
  UploadCenter._(this.session, this.store) {
    _owner = owner;
    _sessionGeneration = session.generation;
    session.addListener(_accountChanged);
    session.uploadProgress.addListener(_progressChanged);
    unawaited(_recover());
  }
  static final _centers = Expando<UploadCenter>();
  static UploadCenter of(Session session, {UploadPendingStore store = const UploadPendingStore()}) => _centers[session] ??= UploadCenter._(session, store);
  final Session session;
  final UploadPendingStore store;
  String? get owner => session.user?['public_id']?.toString();
  String? _owner;
  late int _sessionGeneration;
  int _epoch = 0;
  int get generation => _epoch + session.generation;
  int revision = 0;
  final confirmedPosts = <Map<String, dynamic>>[];
  final confirmedStories = <Map<String, dynamic>>[];
  String? kind;
  bool restoring = true;
  String? _localId;
  bool busy = false;
  bool preparing = false;
  bool openingOriginal = false;
  Object? error;
  Map<String, dynamic>? result;
  Future<Map<String, dynamic>> Function()? _original;
  double? get progress => preparing ? null : session.uploadProgress.value;
  bool get canRetry => !restoring && !busy && error != null && _original != null && !(error is UploadError && (error as UploadError).terminal);
  bool get occupied => restoring || busy || error != null;
  void _progressChanged() { if (busy) notifyListeners(); }
  void _accountChanged() {
    if (_owner == owner && _sessionGeneration == session.generation) return;
    _owner = owner;
    _sessionGeneration = session.generation;
    _epoch++;
    busy = false; preparing = false; openingOriginal = false; error = null; result = null;
    _original = null; kind = null; _localId = null;
    confirmedPosts.clear(); confirmedStories.clear(); revision++;
    restoring = true;
    notifyListeners();
    unawaited(_recover());
  }
  Future<void> _recover() async {
    final account = owner; final epoch = generation;
    _localId = null;
    try {
      final saved = account == null ? null : await store.read(account);
      if (epoch != generation) return;
      if (saved != null) {
        _localId = saved['id'] as String; kind = saved['kind'] as String;
        error = UploadError('An earlier upload may already be posted. Check your profile before starting another.', uncertain: true);
      }
    } catch (_) {
      if (epoch == generation) error = UploadError('Earlier upload safety info could not be read. Uploading is paused.', uncertain: true);
    } finally { if (epoch == generation) { restoring = false; notifyListeners(); } }
  }
  bool start(String type, Future<Map<String, dynamic>> Function() original) {
    if (occupied || owner == null || !['post','reel','story'].contains(type)) return false;
    kind = type; result = null; _original = original; _localId = newUploadIntent();
    unawaited(_run());
    return true;
  }
  Future<void> _run() async {
    if (busy || restoring || _original == null) return;
    final epoch = generation;
    final original = _original!;
    final markerId = _localId!;
    final markerKind = kind!;
    final account = owner;
    if (account == null) return;
    busy = true; preparing = true; error = null;
    session.uploadProgress.value = null;
    notifyListeners();
    try {
      // Persist before even file preparation can hand work to the network.
      try { await store.write(account, markerId, markerKind); }
      catch (_) { throw ApiError('Upload safety info could not be saved. Nothing was sent.'); }
      if (epoch != generation) return;
      final value = await original();
      if (epoch != generation) return;
      bool text(Object? v) => v is String && v.trim().isNotEmpty;
      final author = value['author'];
      final valid = text(value['public_id']) && (kind == 'story'
          ? text(value['url']) && ['image','video'].contains(value['type'])
          : author is Map && text(author['public_id']) && text(author['username']) && value['media'] is List && value['kind'] == kind);
      if (!valid) throw UploadError('The upload result is unknown. Check your posts or stories before sharing again.', uncertain: true);
      result = Map<String, dynamic>.from(value);
      final list = kind == 'story' ? confirmedStories : confirmedPosts;
      list.removeWhere((p) => p['public_id'] == value['public_id']);
      list.insert(0, result!);
      if (list.length > 32) list.removeLast();
      revision++;
      _original = null;
      try { await store.clear(account, expectedId: markerId); }
      catch (_) { throw UploadError('Your upload was confirmed, but its safety info could not be cleared. Open the original before starting another.', resourceId: value['public_id'] as String, uncertain: true); }
    } catch (e) {
      if (epoch == generation) error = e;
    } finally {
      if (epoch == generation) { busy = false; preparing = false; notifyListeners(); }
    }
  }
  void sending() { preparing = false; notifyListeners(); }
  void retry() { if (canRetry) unawaited(_run()); }
  /// Explicit dismissal discards the in-memory failed draft, never resends it.
  Future<void> dismiss() async {
    if (busy || restoring) return;
    final account = owner; final epoch = generation;
    final markerId = _localId;
    restoring = true; notifyListeners();
    try { if (account != null) await store.clear(account, expectedId: markerId); }
    catch (_) {
      if (epoch == generation) { restoring = false; error = UploadError('Upload safety info could not be cleared. Uploading is paused.', uncertain: true); notifyListeners(); }
      return;
    }
    if (epoch != generation) return;
    restoring = false; error = null; result = null; _original = null; kind = null; _localId = null;
    notifyListeners();
  }
  Future<void> openOriginal(BuildContext context) async {
    final id = (error is UploadError ? (error as UploadError).resourceId : null) ?? result?['public_id'];
    if (id == null || openingOriginal) return;
    final epoch = generation;
    openingOriginal = true; notifyListeners();
    try {
      if (kind != 'story') { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostPage(session: session, postId: id))); return; }
      final value = await session.call('GET', '/stories');
      if (epoch != generation || !context.mounted) return;
      if (value is! Map || value['data'] is! List) throw ApiError('Could not read stories. Try again.');
      Map<String,dynamic>? matching;
      for (final item in value['data'] as List) {
        if (item is! Map || item['author'] is! Map || item['items'] is! List) throw ApiError('Could not read stories. Try again.');
        final author = item['author'] as Map;
        if (author['public_id'] is! String || (author['public_id'] as String).trim().isEmpty || author['username'] is! String || (author['username'] as String).trim().isEmpty) throw ApiError('Could not read stories. Try again.');
        for (final story in item['items'] as List) {
          if (story is! Map || story['public_id'] is! String || (story['public_id'] as String).trim().isEmpty || story['url'] is! String || (story['url'] as String).trim().isEmpty || !['image','video'].contains(story['type']) || story['created_at'] is! String || DateTime.tryParse(story['created_at'] as String) == null) throw ApiError('Could not read stories. Try again.');
          if (story['public_id'] == id) matching = {'author': Map<String,dynamic>.from(author), 'items': [Map<String,dynamic>.from(story)]};
        }
      }
      if (matching != null) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryViewer(session: session, group: matching!)));
        return;
      }
      if (context.mounted) showInfo(context, t_('The original story was removed or expired.'));
    } catch (e) { if (epoch == generation && context.mounted) showError(context, e); }
    finally { if (epoch == generation) { openingOriginal = false; notifyListeners(); } }
  }
}

class UploadStrip extends StatelessWidget {
  const UploadStrip({super.key, required this.center});
  final UploadCenter center;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: center, builder: (context, _) {
    if (!center.busy && center.error == null && center.result == null && !center.restoring) return const SizedBox.shrink();
    final error = center.error;
    final label = center.restoring ? t_('Checking earlier uploads...') : error != null ? t_(error.toString()) : center.busy
        ? center.preparing ? t_('Preparing upload...') : center.progress == 1 ? t_('Finishing upload...') : t_('Uploading... Keep the app open.')
        : t_(center.kind == 'story' ? 'Your story is up.' : center.kind == 'reel' ? 'Your reel is live in the Reels tab.' : 'Your post is up.');
    return Material(color: Theme.of(context).colorScheme.surfaceContainerHigh, child: SafeArea(bottom: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 6), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PhIcon(error != null ? 'warning-circle' : center.busy ? 'upload-simple' : 'check-circle', size: 20),
        const SizedBox(width: 10), Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis)),
        ]),
        if (!center.busy && !center.restoring) Wrap(alignment: WrapAlignment.end, spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (!center.busy && ((error is UploadError && error.resourceId != null) || center.result != null)) TextButton(onPressed: center.openingOriginal ? null : () => center.openOriginal(context), child: Text(t_('Open original'))),
        if (center.canRetry) TextButton(onPressed: center.retry, child: Text(t_('Try again'))),
        if (error != null) TextButton(onPressed:()=>showDialog<void>(context:context,builder:(c)=>ListenableBuilder(listenable:center,builder:(c,_)=>AlertDialog(
          scrollable:true,title:Text(t_('Upload details')),content:Text(center.error == null ? t_('No upload details to show.') : t_(center.error.toString())),
          actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(t_('Close')))],
        ))),child:Text(t_('Details'))),
        if (!center.busy && !center.restoring) IconButton(tooltip: t_('Dismiss'), onPressed: () async {
          if (error == null) { await center.dismiss(); return; }
          final epoch = center.generation;
          final markerId = center._localId;
          final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(scrollable: true,
            title: Text(t_('Discard this draft?')), content: Text(t_('This removes the local retry copy. It does not remove anything already posted. Check your profile before starting a new upload.')),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Discard')))],
          ));
          // The confirmation belongs to the marker shown when it opened.
          if (yes == true && epoch == center.generation && markerId == center._localId) await center.dismiss();
        }, icon: const PhIcon('x', size: 18)),
        ]),
      ])),
      if (center.busy) LinearProgressIndicator(value: center.progress),
    ])));
  });
}
