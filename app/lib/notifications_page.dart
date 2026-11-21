import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'session_bound_state.dart';
import 'profile_pages.dart';
import 'post_page.dart';
import 'ui.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.session});
  final Session session;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> with SessionBoundState<NotificationsPage> {
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() {
    items = null;
    error = null;
    loading = false;
  }
  List<Map<String, dynamic>>? items;
  String? error;
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
      final j = await widget.session.call('GET', '/notifications') as Map<String, dynamic>;
      final rows=(j['data'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      if(rows.any((v)=>!['like','comment','follow'].contains(v['type']) || v['actor'] is! String || (v['actor'] as String).trim().isEmpty)) throw const FormatException('Invalid notification');
      if (mounted && sessionActive) setState(() { items = rows; error = null; });
    } catch (e) {
      if (mounted && sessionActive) setState(() => error = e is ApiError ? t_(e.message) : t_('Notifications could not be loaded.'));
    } finally {
      if (mounted && sessionActive) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
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
              'like' => (Ph.favorite, brandRed, '$who ${t_('liked your post')}'),
              'comment' => (Ph.mode_comment, Theme.of(context).colorScheme.onSurface, '$who ${t_('commented:')} ${n['text'] ?? ''}'),
              _ => (Ph.person_add, Theme.of(context).colorScheme.onSurface, '$who ${t_('started following you')}'),
            };
            return ListTile(
              leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: PhIcon(icon, color: color, size: 20)),
              title: Text(text, maxLines: MediaQuery.textScalerOf(context).scale(14)>19 ? 4 : 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(type == 'like' && (n['text'] ?? '').toString().isNotEmpty ? '${n['text']}  ·  ${t_(ago(n['created_at'].toString()))}' : t_(ago(n['created_at'].toString()))),
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
    return Scaffold(appBar: ReviewedAppBar(toolbarHeight: MediaQuery.textScalerOf(context).scale(40).clamp(56,96), title: Text(t_('Notifications'),maxLines:2,style:const TextStyle(fontSize:18)), actions:[IconButton(tooltip:t_('Refresh'),onPressed:loading?null:_load,icon:const PhIcon('arrow-clockwise'))]), body: body);
  }
}
