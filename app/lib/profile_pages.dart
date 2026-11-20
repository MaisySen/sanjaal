import 'ph.dart';
import 'upload_center.dart';
import 'draft_exit_guard.dart';
import 'session_bound_state.dart';
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
      Text(n, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ]);

class ProfileActions extends StatelessWidget {
  const ProfileActions({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(14) > 19) return Wrap(spacing: 8, runSpacing: 8, children: children);
    return Row(children: [for (var i = 0; i < children.length; i++) ...[
      if (i > 0) const SizedBox(width: 8), Expanded(child: children[i]),
    ]]);
  }
}

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.user, required this.actions});
  final Map<String, dynamic> user;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? '').toString();
    final bio = (user['bio'] ?? '').toString();
    String n(String k) => shortCount((user[k] as num?)?.toInt() ?? 0);
    final large = MediaQuery.textScalerOf(context).scale(14) > 19;
    final stats = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final stat in [('posts_count', 'Posts'), ('followers_count', 'Followers'), ('following_count', 'Following')])
        Expanded(child: _stat(context, n(stat.$1), t_(stat.$2))),
    ]);
    return Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        GestureDetector(onTap: user['avatar_url'] == null ? null : () => openImage(context, user['avatar_url'].toString()), child: Avatar(user: user, radius: 40)),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (name.isNotEmpty) Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (!large) stats,
        ])),
      ]),
      if (large) Padding(padding: const EdgeInsets.only(top: 12), child: stats),
      if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(bio)),
      const SizedBox(height: 14),
      actions,
    ]));
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.session, required this.username});
  final Session session;
  final String username;
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> with SessionBoundState<UserProfilePage> {
  late final String _openingUsername=widget.username;
  @override
  bool get sessionActive=>super.sessionActive && widget.username==_openingUsername;
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() { u=null;error=null;busy=false;loading=false;read++; }
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
    if (!mounted || !sessionActive) return;
    final request = ++read;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/users/${widget.username}') as Map<String, dynamic>;
      if (mounted && sessionActive && request == read) setState(() => u = (j['user'] as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted && sessionActive && request == read) setState(() => error = e is ApiError ? (e.status == 404 ? t_('That member does not exist.') : e.message) : t_('Profile could not be loaded.'));
    } finally { if (mounted && sessionActive && request == read) setState(() => loading = false); }
  }

  Future<void> _follow() async {
    if (!sessionActive || busy || loading || u == null) return;
    final me = u!;
    final was = me['following'] == true;
    setState(() => busy = true);
    try {
      await widget.session.call(was ? 'DELETE' : 'POST', '/users/${widget.username}/follow');
      if (!mounted || !sessionActive) return;
      setState(() {
        u = {...u!, 'following': !was, 'followers_count': (((u!['followers_count'] as num?)?.toInt() ?? 0) + (was ? -1 : 1)).clamp(0, 1 << 31)};
      });
      await _load();
    } catch (e) {
      if (mounted && sessionActive) showError(context, e);
    }
    if (mounted && sessionActive) setState(() => busy = false);
  }

  Future<void> _message() async {
    if (!sessionActive || busy || loading) return;
    setState(() => busy = true);
    try {
      final j = await widget.session.call('POST', '/conversations', body: {'type': 'direct', 'username': widget.username}) as Map<String, dynamic>;
      if (!mounted || !sessionActive) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(session: widget.session, convo: (j['conversation'] as Map).cast<String, dynamic>())));
    } catch (e) {
      if (mounted && sessionActive) showError(context, e);
    }
    if (mounted && sessionActive) setState(() => busy = false);
  }

  Future<void> _menu(String v) async {
    if (!sessionActive || busy || loading) return;
    if (v == 'report') return reportFlow(context, widget.session, 'user', widget.username, isActive:()=>sessionActive);
    if (v == 'block') {
      if (await blockFlow(context, widget.session, widget.username, isActive:()=>sessionActive) && mounted && sessionActive) Navigator.of(context).pop();
    }
    if (v == 'unblock') {
      try {
        await widget.session.call('DELETE', '/users/${widget.username}/block');
        await _load();
      } catch (e) {
        if (mounted && sessionActive) showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
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
      body: ProfilePosts(
        session: widget.session,
        query: {'username': widget.username},
        emptyIcon: Ph.image_outlined,
        emptyTitle: t_('No photo or text posts yet'),
        header: Column(children: [
          if (error != null) _ProfileReadNotice(message: error!, retry: loading || busy ? null : _load),
          if (loading) const LinearProgressIndicator(),
          ProfileHeader(
          user: user,
          actions: isMe
              ? const SizedBox.shrink()
              : ProfileActions(children: [
                  following
                        ? OutlinedButton(onPressed: busy || loading ? null : _follow, child: Text(t_('Unfollow')))
                        : FilledButton(onPressed: busy || loading || blocked ? null : _follow, child: Text(t_('Follow'))),
                  OutlinedButton.icon(onPressed: busy || loading || blocked ? null : _message, icon: const PhIcon('chat-circle'), label: Text(t_('Message'))),
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
  late final uploads = UploadCenter.of(widget.session);
  int _publishedRevision = -1;
  void _published() {
    if (!mounted || _publishedRevision == uploads.revision) return;
    _publishedRevision = uploads.revision;
    if (uploads.confirmedPosts.isNotEmpty) _load();
  }
  @override
  void dispose() { uploads.removeListener(_published); super.dispose(); }
  int read = 0;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    uploads.addListener(_published);
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
    final me = {...?counts, ...?s.user, for (final key in ['posts_count', 'followers_count', 'following_count']) if (counts?[key] != null) key: counts![key]};
    return Scaffold(
      appBar: AppBar(
        title: Text('@${s.user?['username'] ?? t_('Me')}'),
        leading: IconButton(tooltip: t_('Settings'), icon: const PhIcon('list'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(session: s)))),
        actions: [
          IconButton(tooltip: t_('Refresh profile'), onPressed: loading ? null : _load, icon: const PhIcon('arrow-clockwise')),
          if (widget.onCompose != null) IconButton(tooltip: t_('Post'), onPressed: widget.onCompose, icon: const PhIcon('plus')),
        ],
      ),
      body: ProfilePosts(
        key: ValueKey(_refresh),
        session: s,
        query: {'username': (s.user?['username'] ?? '').toString()},
        emptyIcon: Ph.image_outlined,
        emptyTitle: t_('No photo or text posts yet'),
        emptyHint: t_('A photo, a thought, a little of your day.'),
        emptyAction: widget.onCompose == null ? null : FilledButton.icon(onPressed: widget.onCompose, icon: const PhIcon('plus', size: 18), label: Text(t_('Create a post'))),
        header: Column(children: [
          if (error != null) _ProfileReadNotice(message: error!, retry: loading ? null : _load),
          if (loading) const LinearProgressIndicator(),
          ProfileHeader(
          user: me,
          actions: ProfileActions(children: [
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

/// Only content types backed by Sanjaal are shown. Reposts/tags are not fake tabs.
class ProfilePosts extends StatefulWidget {
  const ProfilePosts({super.key, required this.session, required this.query, required this.header, required this.emptyIcon, required this.emptyTitle, this.emptyHint, this.emptyAction});
  final Session session;
  final Map<String, String> query;
  final Widget header;
  final PhData emptyIcon;
  final String emptyTitle;
  final String? emptyHint;
  final Widget? emptyAction;
  @override
  State<ProfilePosts> createState() => _ProfilePostsState();
}
class _ProfilePostsState extends State<ProfilePosts> {
  int tab = 0;
  final visited = <int>{0};
  @override
  Widget build(BuildContext context) => IndexedStack(index: tab, children: [for (var i = 0; i < 2; i++)
    if (!visited.contains(i)) const SizedBox.shrink() else FeedList(
      key: ValueKey(i), session: widget.session, query: {...widget.query, 'kind': i == 0 ? 'post' : 'reel'}, grid: true,
      emptyIcon: i == 0 ? widget.emptyIcon : Ph.movie_outlined,
      emptyTitle: i == 0 ? widget.emptyTitle : t_('No reels yet'),
      emptyHint: i == 0 ? widget.emptyHint : t_('Share a short video with your community.'),
      emptyAction: widget.emptyAction,
      header: Column(children: [widget.header, Row(children: [for (var j = 0; j < 2; j++) Expanded(child: InkWell(
        onTap: () => setState(() { tab = j; visited.add(j); }),
        child: Semantics(selected: tab == j, button: true, label: t_(j == 0 ? 'Posts' : 'Reels'), child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 2, color: tab == j ? Theme.of(context).colorScheme.onSurface : Colors.transparent))),
          child: PhIcon(j == 0 ? 'grid-nine' : 'play-circle', size: 25, color: tab == j ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant),
        )),
      ))])]),
    ),
  ]);
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.session});
  final Session session;
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> with SessionBoundState<EditProfilePage> {
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() {
    for (final field in [name, username, bio]) { field.clear(); }
    busy = false;
  }
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
    if (busy || !sessionActive) return;
    setState(() => busy = true);
    try {
      final f = await guardPick(context, () => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, imageQuality: 78));
      if (f == null || !mounted || !sessionActive) return;
      final bytes = await f.readAsBytes();
      if (!mounted || !sessionActive) return;
      await widget.session.uploadAvatar(UploadFile(bytes, mimeFor(f.name), f.name));
      if (mounted && sessionActive) showInfo(context, t_('Photo saved. Text changes still need Save.'));
    } catch (e) { if (mounted && sessionActive) showError(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _save() async {
    if (busy || !sessionActive || !_form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.session.updateProfile({'name': name.text.trim(), 'username': username.text.trim(), 'bio': bio.text.trim()});
      if (!mounted || !sessionActive) return;
      setState(() { saved = true; busy = false; });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && sessionActive) Navigator.of(context).pop();
    } catch (e) {
      if (mounted && sessionActive) {
        setState(() => busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
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
