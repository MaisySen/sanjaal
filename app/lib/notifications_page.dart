import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'profile_pages.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/notifications') as Map<String, dynamic>;
      if (mounted) setState(() => items = (j['data'] as List).cast<Map<String, dynamic>>());
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (items == null && error == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items == null) {
      body = EmptyState(icon: Icons.cloud_off, title: error!, action: OutlinedButton(onPressed: () { setState(() => error = null); _load(); }, child: Text(t_('Try again'))));
    } else if (items!.isEmpty) {
      body = const EmptyState(icon: Icons.notifications_none, title: 'Nothing yet', hint: 'Likes, comments and new followers show up here.');
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: items!.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final n = items![i];
            final type = n['type'];
            final who = '@${n['actor']}';
            final (icon, color, text) = switch (type) {
              'like' => (Icons.favorite, brandRed, '$who liked your post'),
              'comment' => (Icons.mode_comment, brandBlue, '$who commented: ${n['text']}'),
              _ => (Icons.person_add, Colors.green, '$who started following you'),
            };
            return ListTile(
              leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
              title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(type == 'like' && (n['text'] ?? '').toString().isNotEmpty ? '${n['text']}  ·  ${ago(n['created_at'].toString())}' : ago(n['created_at'].toString())),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: n['actor'].toString()))),
            );
          },
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(t_('Notifications'))), body: body);
  }
}
