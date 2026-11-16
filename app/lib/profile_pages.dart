import 'ph.dart';
import 'draft_exit_guard.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'actions.dart';
import 'api.dart';
import 'chat_pages.dart';
import 'feed_page.dart' show FeedList, SavedPage;
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

Widget _stat(BuildContext context, String n, String label) => Column(mainAxisSize: MainAxisSize.min, children: [
      Text(n, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          GestureDetector(
            onTap: user['avatar_url'] == null ? null : () => openImage(context, user['avatar_url'].toString()),
            child: Avatar(user: user, radius: 36),
          ),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (name.isNotEmpty) Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('@${user['username']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        ]),
        if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerLeft, child: Text(bio))),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 20, runSpacing: 12, children: [
          _stat(context, n('posts_count'), t_('Posts')),
          _stat(context, n('followers_count'), t_('Followers')),
          _stat(context, n('following_count'), t_('Following')),
        ]),
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
  bool loading = false;
  int read = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++read;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/users/${widget.username}') as Map<String, dynamic>;
      if (mounted && request == read) setState(() => u = (j['user'] as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted && request == read) setState(() => error = e is ApiError ? (e.status == 404 ? t_('That member does not exist.') : e.message) : t_('Profile could not be loaded.'));
    } finally { if (mounted && request == read) setState(() => loading = false); }
  }

  Future<void> _follow() async {
    if (busy || loading || u == null) return;
    final me = u!;
    final was = me['following'] == true;
    setState(() => busy = true);
    try {
      await widget.session.call(was ? 'DELETE' : 'POST', '/users/${widget.username}/follow');
      if (!mounted) return;
      setState(() {
        u = {...u!, 'following': !was, 'followers_count': (((u!['followers_count'] as num?)?.toInt() ?? 0) + (was ? -1 : 1)).clamp(0, 1 << 31)};
      });
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _message() async {
    if (busy || loading) return;
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
    if (busy || loading) return;
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
        body: error != null ? EmptyState(icon: Ph.person_off_outlined, title: error!, action: OutlinedButton(onPressed: loading ? null : _load, child: Text(t_('Try again')))) : const Center(child: CircularProgressIndicator()),
      );
    }
    final isMe = user['is_me'] == true;
    final following = user['following'] == true;
    final blocked = user['blocked'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${user['username']}'),
        actions: [
          IconButton(tooltip: t_('Refresh profile'), onPressed: loading || busy ? null : _load, icon: const PhIcon('arrow-clockwise')),
          if (!isMe)
            PopupMenuButton<String>(
              enabled: !busy && !loading,
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
        emptyIcon: Ph.image_outlined,
        emptyTitle: isMe ? 'You have not posted yet' : 'No posts yet',
        header: Column(children: [
          if (error != null) _ProfileReadNotice(message: error!, retry: loading || busy ? null : _load),
          if (loading) const LinearProgressIndicator(),
          ProfileHeader(
          user: user,
          actions: isMe
              ? const SizedBox.shrink()
              : Row(children: [
                  Expanded(
                    child: following
                        ? OutlinedButton(onPressed: busy || loading ? null : _follow, child: Text(t_('Unfollow')))
                        : FilledButton(onPressed: busy || loading || blocked ? null : _follow, child: Text(t_('Follow'))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: busy || loading || blocked ? null : _message, icon: const PhIcon('chat-circle'), label: Text(t_('Message')))),
                ]),
        )]),
      ),
    );
  }
}

/// The Me tab: own profile with edit and settings.
class MePage extends StatefulWidget {
  const MePage({super.key, required this.session, this.onCompose, this.contentRevision = 0});
  final Session session;
  final Future<void> Function()? onCompose;
  final int contentRevision;
  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  Map<String, dynamic>? counts;
  int _refresh = 0;
  int read = 0;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentRevision != widget.contentRevision) {
      _refresh++;
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final name = widget.session.user?['username'];
    if (name == null) return;
    final request = ++read;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/users/$name') as Map<String, dynamic>;
      if (mounted && request == read) setState(() => counts = (j['user'] as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted && request == read) setState(() => error = e is ApiError ? e.message : t_('Profile could not be loaded.'));
    } finally { if (mounted && request == read) setState(() => loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final me = {...?counts, ...?s.user};
    return Scaffold(
      appBar: AppBar(
        title: Text(t_('Me')),
        actions: [
          IconButton(tooltip: t_('Refresh profile'), onPressed: loading ? null : _load, icon: const PhIcon('arrow-clockwise')),
          IconButton(
            tooltip: t_('Settings'),
            icon: const PhIcon('gear'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(session: s))),
          ),
        ],
      ),
      body: FeedList(
        key: ValueKey(_refresh),
        session: s,
        query: {'username': (s.user?['username'] ?? '').toString()},
        emptyIcon: Ph.image_outlined,
        emptyTitle: 'You have not posted yet',
        emptyHint: t_('A photo, a thought, a little of your day.'),
        emptyAction: widget.onCompose == null ? null : FilledButton.icon(onPressed: widget.onCompose, icon: const PhIcon('plus', size: 18), label: Text(t_('Create a post'))),
        header: Column(children: [
          if (error != null) _ProfileReadNotice(message: error!, retry: loading ? null : _load),
          if (loading) const LinearProgressIndicator(),
          ProfileHeader(
          user: me,
          actions: Wrap(spacing: 10, runSpacing: 8, children: [
            OutlinedButton.icon(
              icon: const PhIcon('pencil-simple', size: 18),
              label: Text(t_('Edit profile')),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfilePage(session: s)));
                if (mounted) {
                  setState(() => _refresh++);
                  _load();
                }
              },
            ),
            OutlinedButton.icon(
              icon: const PhIcon('bookmark-simple', size: 18),
              label: Text(t_('Saved')),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SavedPage(session: s))),
            ),
          ]),
        )]),
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
  bool saved = false;
  late final (String, String, String) initial;

  @override
  void initState() {
    super.initState();
    initial = (name.text, username.text, bio.text);
    for (final field in [name, username, bio]) { field.addListener(_changed); }
  }
  void _changed() { if (mounted) setState(() {}); }
  @override
  void dispose() { for (final field in [name, username, bio]) { field.dispose(); } super.dispose(); }


  Future<void> _avatar() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final f = await guardPick(context, () => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, imageQuality: 78));
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      await widget.session.uploadAvatar(UploadFile(bytes, mimeFor(f.name), f.name));
      if (mounted) showInfo(context, t_('Photo saved. Text changes still need Save.'));
    } catch (e) { if (mounted) showError(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _save() async {
    if (busy || !_form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.session.updateProfile({'name': name.text.trim(), 'username': username.text.trim(), 'bio': bio.text.trim()});
      if (!mounted) return;
      setState(() { saved = true; busy = false; });
      await WidgetsBinding.instance.endOfFrame;
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
    return DraftExitGuard(hasChanges: !saved && (name.text, username.text, bio.text) != initial, busy: busy, busyMessage: 'Your profile is still updating.', child: Scaffold(
      appBar: AppBar(toolbarHeight: MediaQuery.textScalerOf(context).scale(40).clamp(56, 96), title: Text(t_('Edit profile'), maxLines: 2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), actions: [
        Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: busy ? null : _save, child: Text(t_('Save')))),
      ]),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: Stack(children: [
              ListenableBuilder(listenable: widget.session, builder: (_, __) => Avatar(user: widget.session.user, radius: 52)),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(radius: 18, backgroundColor: Colors.white, child: IconButton(tooltip: t_('Change photo'), padding: EdgeInsets.zero, icon: const PhIcon('camera', size: 18, color: Colors.black), onPressed: busy ? null : _avatar)),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          TextFormField(key: const ValueKey('profile-name'), controller: name, enabled: !busy, maxLength: 80, decoration: InputDecoration(labelText: t_('Name'), border: const OutlineInputBorder()), validator: (v) => (v ?? '').trim().isEmpty ? t_('Required') : null),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('profile-username'),
            controller: username,
            enabled: !busy,
            decoration: InputDecoration(labelText: t_('Username'), border: const OutlineInputBorder()),
            validator: (v) => RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch((v ?? '').trim()) ? null : t_('Use 3 to 30 letters, numbers, dots or underscores'),
          ),
          const SizedBox(height: 12),
          TextFormField(key: const ValueKey('profile-bio'), controller: bio, enabled: !busy, maxLength: 160, maxLines: 3, decoration: InputDecoration(labelText: t_('Bio'), border: const OutlineInputBorder())),
          if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ]),
      ),
    ));
  }
}

class _ProfileReadNotice extends StatelessWidget {
  const _ProfileReadNotice({required this.message, required this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(12), child: Column(children: [Text(message), TextButton(onPressed: retry, child: Text(t_('Try again')))]));
}
