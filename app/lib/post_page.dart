import 'glass/glass_app_bar.dart';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'session_bound_state.dart';
import 'feed_page.dart' show PostCard;
import 'ph.dart';
import 'ui.dart';

/// A notification or shared post resolves against current visibility, never a stale preview.
class PostPage extends StatefulWidget {
  const PostPage({
    super.key,
    required this.session,
    required this.postId,
    this.onVisibilityChanged,
  });
  final Session session;
  final String postId;
  final VoidCallback? onVisibilityChanged;
  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> with SessionBoundState<PostPage> {
  late final String _openingPost = widget.postId;
  @override
  Session get viewSession => widget.session;
  @override
  bool get sessionActive =>
      super.sessionActive && widget.postId == _openingPost;
  @override
  void sessionRetired() {
    post = null;
    error = null;
    unavailable = false;
    loading = false;
  }

  Map<String, dynamic>? post;
  String? error;
  bool unavailable = false;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (loading || !sessionActive) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await widget.session.call(
        'GET',
        '/posts/${widget.postId}',
      ) as Map<String, dynamic>;
      final next = (j['post'] as Map).cast<String, dynamic>();
      if (next['public_id'] != _openingPost ||
          next['author'] is! Map ||
          next['media'] is! List ||
          (next['media'] as List).any((m) => m is! Map<String, dynamic>) ||
          (next['hashtags'] != null && next['hashtags'] is! List) ||
          (next['comments_count'] != null && next['comments_count'] is! num) ||
          (next['likes_count'] != null && next['likes_count'] is! num) ||
          (next['my_reaction'] != null && next['my_reaction'] is! String)) {
        throw const FormatException('Invalid post detail');
      }
      if (mounted && sessionActive) setState(() => post = next);
    } on ApiError catch (e) {
      if (!mounted || !sessionActive) return;
      setState(() {
        unavailable = e.status == 404 || e.status == 410;
        error = unavailable ? null : t_(e.message);
      });
    } catch (_) {
      if (mounted && sessionActive) {
        setState(() => error = t_('Post could not be loaded.'));
      }
    } finally {
      if (mounted && sessionActive) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => !sessionActive
      ? retiredSessionView()
      : Scaffold(
          appBar: ReviewedAppBar(title: Text(t_('Post'))),
          body: unavailable
              ? EmptyState(
                  icon: Ph.info_outline,
                  title: t_('Post unavailable'),
                  hint: t_('This post was removed or is no longer available to you.'),
                )
              : error != null
              ? EmptyState(
                  icon: widget.session.offline
                      ? Ph.cloud_off
                      : Ph.error_outline,
                  title: error!,
                  action: OutlinedButton(
                    onPressed: _load,
                    child: Text(t_('Try again')),
                  ),
                )
              : post == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: PostCard(
                      session: widget.session,
                      post: post!,
                      onRemoved: () {
                        if (mounted && sessionActive) {
                          setState(() {
                            post = null;
                            unavailable = true;
                          });
                          widget.onVisibilityChanged?.call();
                        }
                      },
                    ),
                  ),
                ),
        );
}
