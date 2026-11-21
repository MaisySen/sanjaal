import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'session_bound_state.dart';
import 'feed_page.dart' show PostCard;
import 'ph.dart';
import 'ui.dart';

/// A notification or shared post resolves against current visibility, never a stale preview.
class PostPage extends StatefulWidget {
  const PostPage({super.key, required this.session, required this.postId});
  final Session session;
  final String postId;
  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> with SessionBoundState<PostPage> {
  late final String _openingPost=widget.postId;
  @override
  Session get viewSession=>widget.session;
  @override
  bool get sessionActive=>super.sessionActive && widget.postId==_openingPost;
  @override
  void sessionRetired(){post=null;error=null;unavailable=false;loading=false;}

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
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/posts/${widget.postId}') as Map<String, dynamic>;
      if (mounted && sessionActive) setState(() => post = (j['post'] as Map).cast<String, dynamic>());
    } on ApiError catch (e) {
      if (!mounted || !sessionActive) return;
      setState(() {
        unavailable = e.status == 404 || e.status == 410;
        error = unavailable ? null : t_(e.message);
      });
    } finally {
      if (mounted && sessionActive) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => !sessionActive?retiredSessionView():Scaffold(
    appBar: AppBar(title: Text(t_('Post'))),
    body: unavailable
      ? const EmptyState(icon: Ph.info_outline, title: 'Post unavailable', hint: 'This post was removed or is no longer available to you.')
      : error != null
        ? EmptyState(icon: widget.session.offline ? Ph.cloud_off : Ph.error_outline, title: error!, action: OutlinedButton(onPressed: _load, child: Text(t_('Try again'))))
        : post == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(top: false, child: SingleChildScrollView(child: PostCard(session: widget.session, post: post!, onRemoved: () {if(mounted && sessionActive)setState(() { post = null; unavailable = true; });}))),
  );
}
