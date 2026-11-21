import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'actions.dart';
import 'api.dart';
import 'chat_pages.dart';
import 'feed_page.dart' show FeedList;
import 'settings_page.dart';
import 'ui.dart';

/// 999 stays 999, 1240 becomes 1.2K, 2500000 becomes 2.5M.
String shortCount(int v) {
  String f(double x, String u) {
    final t = (x * 10).floor() / 10;
    return (t == t.roundToDouble() ? t.toInt().toString() : t.toStringAsFixed(1)) + u;
  }

  if (v >= 1000000) return f(v / 1000000, 'M');
  if (v >= 1000) return f(v / 1000, 'K');
  return v.toString();
}

Widget _stat(BuildContext context, String n, String label) => Column(children: [
      Text(n, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.user, required this.actions});
  final Map<String, dynamic> user;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? '').toString();
    final bio = (user['bio'] ?? '').toString();
    String n(String k) => shortCount((user[k] as num?)?.toInt() ?? 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: user['avatar_url'] == null ? null : () => openImage(context, user['avatar_url'].toString()),
            child: Avatar(user: user, radius: 55),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _stat(context, n('posts_count'), t_('Posts')),
              _stat(context, n('followers_count'), t_('Followers')),
              _stat(context, n('following_count'), t_('Following')),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (name.isNotEmpty) Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text('@${user['username']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(bio)),
        const SizedBox(height: 16),
        actions,
        const Divider(height: 28),
      ]),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.session, required this.username});
  final Session session;
  final String username;
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? u;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/users/${widget.username}') as Map<String, dynamic>;
      if (mounted) setState(() => u = (j['user'] as Map).cast<String, dynamic>());
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.status == 404 ? 'That member does not exist.' : e.message);
    }
  }

  Future<void> _follow() async {
    final me = u!;
    final was = me['following'] == true;
    setState(() => busy = true);
    try {
      await widget.session.call(was ? 'DELETE' : 'POST', '/users/${widget.username}/follow');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _message() async {
    setState(() => busy = true);
    try {
      final j = await widget.session.call('POST', '/conversations', body: {'type': 'direct', 'username': widget.username}) as Map<String, dynamic>;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(session: widget.session, convo: (j['conversation'] as Map).cast<String, dynamic>())));
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _menu(String v) async {
    if (v == 'report') return reportFlow(context, widget.session, 'user', widget.username);
    if (v == 'block') {
      if (await blockFlow(context, widget.session, widget.username) && mounted) Navigator.of(context).pop();
    }
    if (v == 'unblock') {
      try {
        await widget.session.call('DELETE', '/users/${widget.username}/block');
        await _load();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = u;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text('@${widget.username}')),
        body: error != null ? EmptyState(icon: Icons.person_off_outlined, title: error!) : const Center(child: CircularProgressIndicator()),
      );
    }
    final isMe = user['is_me'] == true;
    final following = user['following'] == true;
    final blocked = user['blocked'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${user['username']}'),
        actions: [
          if (!isMe)
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'report', child: Text(t_('Report'))),
                PopupMenuItem(value: blocked ? 'unblock' : 'block', child: Text(blocked ? 'Unblock' : t_('Block'))),
              ],
            ),
        ],
      ),
      body: FeedList(
        session: widget.session,
        query: {'username': widget.username},
        emptyIcon: Icons.image_outlined,
        emptyTitle: isMe ? 'You have not posted yet' : 'No posts yet',
        header: ProfileHeader(
          user: user,
          actions: isMe
              ? const SizedBox.shrink()
              : Row(children: [
                  Expanded(
                    child: following
                        ? OutlinedButton(onPressed: busy ? null : _follow, child: Text(t_('Unfollow')))
                        : FilledButton(onPressed: busy || blocked ? null : _follow, child: Text(t_('Follow'))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: busy || blocked ? null : _message, icon: const Icon(Icons.chat_bubble_outline), label: Text(t_('Message')))),
                ]),
        ),
      ),
    );
  }
}

/// The Me tab: own profile with edit and settings.
class MePage extends StatefulWidget {
  const MePage({super.key, required this.session});
  final Session session;
  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  Map<String, dynamic>? counts;
  int _refresh = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = widget.session.user?['username'];
    if (name == null) return;
    try {
      final j = await widget.session.call('GET', '/users/$name') as Map<String, dynamic>;
      if (mounted) setState(() => counts = (j['user'] as Map).cast<String, dynamic>());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final me = {...?counts, ...?s.user};
    return Scaffold(
      appBar: AppBar(
        title: Text(t_('Me')),
        actions: [
          IconButton(
            tooltip: t_('Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(session: s))),
          ),
        ],
      ),
      body: FeedList(
        key: ValueKey(_refresh),
        session: s,
        query: {'username': (s.user?['username'] ?? '').toString()},
        emptyIcon: Icons.image_outlined,
        emptyTitle: 'You have not posted yet',
        emptyHint: 'Your posts show up here. Tap + on Home to share one.',
        header: ProfileHeader(
          user: me,
          actions: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(t_('Edit profile')),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfilePage(session: s)));
                if (mounted) {
                  setState(() => _refresh++);
                  _load();
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.session});
  final Session session;
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final name = TextEditingController(text: (widget.session.user?['name'] ?? '').toString());
  late final username = TextEditingController(text: (widget.session.user?['username'] ?? '').toString());
  late final bio = TextEditingController(text: (widget.session.user?['bio'] ?? '').toString());
  final _form = GlobalKey<FormState>();
  bool busy = false;

  Future<void> _avatar() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, imageQuality: 78);
    if (f == null) return;
    setState(() => busy = true);
    try {
      await widget.session.uploadAvatar(UploadFile(await f.readAsBytes(), mimeFor(f.name), f.name));
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.session.updateProfile({'name': name.text.trim(), 'username': username.text.trim(), 'bio': bio.text.trim()});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t_('Edit profile')), actions: [
        Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: busy ? null : _save, child: Text(t_('Save')))),
      ]),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: Stack(children: [
              ListenableBuilder(listenable: widget.session, builder: (_, _) => Avatar(user: widget.session.user, radius: 52)),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(radius: 18, backgroundColor: brandRed, child: IconButton(padding: EdgeInsets.zero, icon: const Icon(Icons.camera_alt, size: 18, color: Colors.white), onPressed: busy ? null : _avatar)),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          TextFormField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(
            controller: username,
            decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
            validator: (v) => RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch((v ?? '').trim()) ? null : 'Use 3 to 30 letters, numbers, dots or underscores',
          ),
          const SizedBox(height: 12),
          TextFormField(controller: bio, maxLength: 160, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', border: OutlineInputBorder())),
          if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ]),
      ),
    );
  }
}
