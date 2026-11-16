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
  int _epoch = 0;
  int get generation => _epoch;
  int revision = 0;
  final confirmedPosts = <Map<String, dynamic>>[];
  final confirmedStories = <Map<String, dynamic>>[];
  String? kind;
  bool restoring = true;
  String? _localId;
  bool busy = false;
  bool preparing = false;
  Object? error;
  Map<String, dynamic>? result;
  Future<Map<String, dynamic>> Function()? _original;
  double? get progress => preparing ? null : session.uploadProgress.value;
  bool get canRetry => !restoring && !busy && error != null && _original != null && !(error is UploadError && (error as UploadError).terminal);
  bool get occupied => restoring || busy || error != null;
  void _progressChanged() { if (busy) notifyListeners(); }
  void _accountChanged() {
    if (_owner == owner) return;
    _owner = owner;
    _epoch++;
    busy = false; preparing = false; error = null; result = null;
    _original = null; kind = null;
    confirmedPosts.clear(); confirmedStories.clear(); revision++;
    restoring = true;
    notifyListeners();
    unawaited(_recover());
  }
  Future<void> _recover() async {
    final account = owner; final epoch = _epoch;
    try {
      final saved = account == null ? null : await store.read(account);
      if (epoch != _epoch) return;
      if (saved != null) {
        _localId = saved['id'] as String; kind = saved['kind'] as String;
        error = UploadError('An earlier upload may already be posted. Check your profile before starting another.', uncertain: true);
      }
    } catch (_) {
      if (epoch == _epoch) error = UploadError('Earlier upload safety info could not be read. Uploading is paused.', uncertain: true);
    } finally { if (epoch == _epoch) { restoring = false; notifyListeners(); } }
  }
  bool start(String type, Future<Map<String, dynamic>> Function() original) {
    if (occupied || owner == null || !['post','reel','story'].contains(type)) return false;
    kind = type; result = null; _original = original; _localId = newUploadIntent();
    unawaited(_run());
    return true;
  }
  Future<void> _run() async {
    if (busy || restoring || _original == null) return;
    final epoch = _epoch;
    final original = _original!;
    final account = owner;
    if (account == null) return;
    busy = true; preparing = true; error = null;
    session.uploadProgress.value = null;
    notifyListeners();
    try {
      // Persist before even file preparation can hand work to the network.
      try { await store.write(account, _localId!, kind!); }
      catch (_) { throw ApiError('Upload safety info could not be saved. Nothing was sent.'); }
      if (epoch != _epoch) return;
      final value = await original();
      if (epoch != _epoch) return;
      if (value['public_id'] is! String || (kind == 'story' ? value['url'] is! String || value['type'] is! String : value['author'] is! Map || value['media'] is! List || value['kind'] != kind)) throw UploadError('The upload result is unknown. Check your posts or stories before sharing again.', uncertain: true);
      result = Map<String, dynamic>.from(value);
      final list = kind == 'story' ? confirmedStories : confirmedPosts;
      list.removeWhere((p) => p['public_id'] == value['public_id']);
      list.insert(0, result!);
      if (list.length > 32) list.removeLast();
      revision++;
      _original = null;
      try { await store.clear(account); }
      catch (_) { throw UploadError('Your upload was confirmed, but its safety info could not be cleared. Open the original before starting another.', resourceId: value['public_id'] as String, uncertain: true); }
    } catch (e) {
      if (epoch == _epoch) error = e;
    } finally {
      if (epoch == _epoch) { busy = false; preparing = false; notifyListeners(); }
    }
  }
  void sending() { preparing = false; notifyListeners(); }
  void retry() { if (canRetry) unawaited(_run()); }
  /// Explicit dismissal discards the in-memory failed draft, never resends it.
  Future<void> dismiss() async {
    if (busy || restoring) return;
    final account = owner; final epoch = _epoch;
    restoring = true; notifyListeners();
    try { if (account != null) await store.clear(account); }
    catch (_) {
      if (epoch == _epoch) { restoring = false; error = UploadError('Upload safety info could not be cleared. Uploading is paused.', uncertain: true); notifyListeners(); }
      return;
    }
    if (epoch != _epoch) return;
    restoring = false; error = null; result = null; _original = null; kind = null; _localId = null;
    notifyListeners();
  }
  Future<void> openOriginal(BuildContext context) async {
    final id = (error is UploadError ? (error as UploadError).resourceId : null) ?? result?['public_id'];
    if (id == null) return;
    if (kind != 'story') { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostPage(session: session, postId: id))); return; }
    try {
      final value = await session.call('GET', '/stories') as Map;
      for (final item in value['data'] as List) {
        final group = (item as Map).cast<String, dynamic>();
        final originals = (group['items'] as List).where((s) => s['public_id'] == id).toList();
        if (originals.isNotEmpty && context.mounted) { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryViewer(session: session, group: {'author': group['author'], 'items': originals}))); return; }
      }
      if (context.mounted) showInfo(context, t_('The original story was removed or expired.'));
    } catch (e) { if (context.mounted) showError(context, e); }
  }
}

class UploadStrip extends StatelessWidget {
  const UploadStrip({super.key, required this.center});
  final UploadCenter center;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: center, builder: (context, _) {
    if (!center.busy && center.error == null && center.result == null && !center.restoring) return const SizedBox.shrink();
    final error = center.error;
    final label = center.restoring ? t_('Checking earlier uploads...') : error != null ? error.toString() : center.busy
        ? center.preparing ? t_('Preparing upload...') : center.progress == 1 ? t_('Finishing upload...') : t_('Uploading... Keep the app open.')
        : t_(center.kind == 'story' ? 'Your story is up.' : center.kind == 'reel' ? 'Your reel is live in the Reels tab.' : 'Your post is up.');
    return Material(color: Theme.of(context).colorScheme.surfaceContainerHigh, child: SafeArea(bottom: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 6), child: Row(children: [
        PhIcon(error != null ? 'warning-circle' : center.busy ? 'upload-simple' : 'check-circle', size: 20),
        const SizedBox(width: 10), Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis)),
        if (!center.busy && ((error is UploadError && error.resourceId != null) || center.result != null)) TextButton(onPressed: () => center.openOriginal(context), child: Text(t_('Open original'))),
        if (center.canRetry) TextButton(onPressed: center.retry, child: Text(t_('Try again'))),
        if (!center.busy && !center.restoring) IconButton(tooltip: t_('Dismiss'), onPressed: () async {
          if (error == null) { await center.dismiss(); return; }
          final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(scrollable: true,
            title: Text(t_('Discard this draft?')), content: Text(t_('This removes the local retry copy. It does not remove anything already posted. Check your profile before starting a new upload.')),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Discard')))],
          ));
          if (yes == true) await center.dismiss();
        }, icon: const PhIcon('x', size: 18)),
      ])),
      if (center.busy) LinearProgressIndicator(value: center.progress),
    ])));
  });
}
