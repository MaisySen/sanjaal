import 'ph.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'profile_pages.dart';
import 'post_page.dart';
import 'ui.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.session});
  final Session session;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>>? items;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (loading) return;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/notifications') as Map<String, dynamic>;
      if (mounted) setState(() { items = (j['data'] as List).cast<Map<String, dynamic>>(); error = null; });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (items == null && error == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items == null) {
      body = EmptyState(icon: widget.session.offline ? Ph.cloud_off : Ph.error_outline, title: error!, action: OutlinedButton(onPressed: _load, child: Text(t_('Try again'))));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: items!.isEmpty ? CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Ph.notifications_none, title: t_('Nothing yet'), hint: t_('Likes, comments and new followers show up here.')))],
        ) : ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items!.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final n = items![i];
            final type = n['type'];
            final who = '@${n['actor']}';
            final (icon, color, text) = switch (type) {
              'like' => (Ph.favorite, brandRed, '$who liked your post'),
              'comment' => (Ph.mode_comment, const Color(0xFF24405F), '$who commented: ${n['text']}'),
              _ => (Ph.person_add, const Color(0xFF3F5B45), '$who started following you'),
            };
            return ListTile(
              leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: PhIcon(icon, color: color, size: 20)),
              title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(type == 'like' && (n['text'] ?? '').toString().isNotEmpty ? '${n['text']}  ·  ${ago(n['created_at'].toString())}' : ago(n['created_at'].toString())),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => n['post_id'] is String
                  ? PostPage(session: widget.session, postId: n['post_id'] as String)
                  : UserProfilePage(session: widget.session, username: n['actor'].toString()))),
            );
          },
        ),
      );
    }
    if (items != null && error != null) {
      body = Column(children: [
        Material(color: Theme.of(context).colorScheme.surfaceContainerHigh, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(child: Text(t_('Could not refresh.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
            TextButton(onPressed: loading ? null : _load, child: Text(t_('Try again'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          ]),
        )),
        Expanded(child: body),
      ]);
    }
    return Scaffold(appBar: AppBar(title: Text(t_('Notifications'))), body: body);
  }
}
