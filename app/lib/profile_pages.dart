import 'follow_list_page.dart';
import 'glass/glass_app_bar.dart';
import 'glass/glass_action.dart';
import 'ph.dart';
import 'upload_center.dart';
import 'draft_exit_guard.dart';
import 'session_bound_state.dart';
import 'session_recovery.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'actions.dart';
import 'api.dart';
import 'chat_pages.dart';
import 'conversation_receipt.dart';
import 'feed_page.dart' show FeedList, SavedPage;
import 'settings_page.dart';
import 'ui.dart';

/// Validate identity and counts before replacing a readable profile snapshot.
/// The signed-in owner's counts must match that public ID. Another profile stays
/// bound to its route username and the public ID from its first valid response.
/// Missing counts retain the existing partial-profile contract.
Map<String, dynamic> _profileRead(dynamic value, {String? owner, String? username}) {
  if (value is! Map<String, dynamic> ||
      value['public_id'] is! String || (value['public_id'] as String).trim().isEmpty ||
      value['username'] is! String || (value['username'] as String).trim().isEmpty ||
      (owner != null && value['public_id'] != owner) ||
      (username != null && value['username'] != username)) {
    throw const FormatException('Invalid profile');
  }
  for (final key in ['posts_count', 'followers_count', 'following_count']) {
    final count = value[key];
    if (count != null && (count is! num || !count.isFinite || count < 0)) {
      throw const FormatException('Invalid profile count');
    }
  }
  return value;
}

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

Widget _stat(BuildContext context, String n, String label, {bool available = true}) => Column(mainAxisSize: MainAxisSize.min, children: [
      Text(n, semanticsLabel: available ? null : t_('Unavailable'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
  const ProfileHeader({super.key, required this.user, required this.actions, this.onFollowers, this.onFollowing, this.countsAvailable = true});
  final bool countsAvailable;
  final Map<String, dynamic> user;
  final Widget actions;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? '').toString();
    final bio = (user['bio'] ?? '').toString();
    String n(String k) => countsAvailable ? shortCount((user[k] as num?)?.toInt() ?? 0) : '-';
    final large = MediaQuery.textScalerOf(context).scale(14) > 19;
    Widget countCell((String, String) stat) {
      final tap = stat.$1 == 'followers_count' ? onFollowers : stat.$1 == 'following_count' ? onFollowing : null;
      final cell = Padding(padding: EdgeInsets.symmetric(vertical: onFollowers != null || onFollowing != null ? 8 : 0), child: _stat(context, n(stat.$1), t_(stat.$2), available: countsAvailable));
      return tap == null ? cell : InkWell(onTap: tap, child: cell);
    }
    const items = [('posts_count', 'Posts'), ('followers_count', 'Followers'), ('following_count', 'Following')];
    final stats = large
        ? SizedBox(width: double.infinity, child: Wrap(alignment: WrapAlignment.spaceAround, spacing: 16, runSpacing: 8, children: [for (final item in items) countCell(item)]))
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final item in items) Expanded(child: countCell(item))]);
    return Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        GestureDetector(onTap: user['avatar_url'] == null ? null : () => openImage(context, user['avatar_url'].toString()), child: Avatar(user: user, radius: 44)),
        if (!large) ...[const SizedBox(width: 20), Expanded(child: stats)],
      ]),
      if (large) Padding(padding: const EdgeInsets.only(top: 12), child: stats),
      const SizedBox(height: 12),
      if (name.isNotEmpty) Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      Text('@${user['username']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(bio)),
      const SizedBox(height: 16),
      actions,
      const Divider(height: 16),
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
  void sessionRetired() { u=null;error=null;busy=false;loading=false;_profileVerified=false;read++; }
  Map<String, dynamic>? u;
  String? error;
  bool busy = false;
  bool loading = false;
  int read = 0;
  bool _openingMembers = false;
  bool _profileVerified = false;

  Future<void> _openMembers(Map<String, dynamic> user, FollowListKind kind) async {
    final owner = user['public_id'];
    if (!mounted || !sessionActive || !_profileVerified || _openingMembers || busy || loading ||
        !widget.session.followListsEnabled || !identical(u, user) ||
        user['blocked'] == true || user['username'] != widget.username ||
        owner is! String || owner.trim().isEmpty) {
      return;
    }
    _openingMembers = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        FollowListPage(session: widget.session, username: widget.username, ownerId: owner, kind: kind)));
    } finally {
      _openingMembers = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !sessionActive) return;
    final request = ++read;
    setState(() { loading = true; error = null; _profileVerified = false; });
    try {
      final j = await widget.session.call('GET', '/users/${widget.username}') as Map<String, dynamic>;
      final profile = _profileRead(j['user'], owner: u?['public_id'] as String?, username: widget.username);
      if (mounted && sessionActive && request == read) setState(() { u = profile; _profileVerified = true; });
    } catch (e) {
      if (mounted && sessionActive && request == read) setState(() => error = e is ApiError ? (e.status == 404 ? t_('That member does not exist.') : t_(e.message)) : t_('Profile could not be loaded.'));
    } finally { if (mounted && sessionActive && request == read) setState(() => loading = false); }
  }

  Future<void> _follow() async {
    if (!mounted || !sessionActive || !_profileVerified || busy || loading || u == null) return;
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
    if (!mounted || !sessionActive || !_profileVerified || busy || loading || u == null || u!['blocked'] == true) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final recipient = u!;
    final owner = widget.session.user!['public_id'] as String;
    final profileRead = read;
    bool stillSelected() => mounted && sessionActive && _profileVerified && read == profileRead && identical(u, recipient);
    setState(() => busy = true);
    try {
      final response = await widget.session.call('POST', '/conversations', body: {'type': 'direct', 'username': recipient['username']});
      if (!mounted || !stillSelected()) return;
      final conversation = checkedDirectConversation(response, owner, recipient);
      if (!route.isCurrent) {
        setState(() {
          _profileVerified = false;
          error = t_('The chat may already exist. Check Chats before starting it again.');
        });
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(session: widget.session, convo: conversation)));
    } catch (e) {
      if (mounted && stillSelected()) {
        setState(() {
          _profileVerified = false;
          error = t_('Could not verify this chat. Refresh the profile and try again.');
        });
        if (e is ApiError) showError(context, e);
      }
    } finally {
      if (mounted && sessionActive) setState(() => busy = false);
    }
  }

  Future<void> _menu(String v) async {
    if (!mounted || !sessionActive || !_profileVerified || busy || loading || u == null ||
        !const {'report', 'block', 'unblock'}.contains(v)) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final selected = u!;
    if ((v == 'block' && selected['blocked'] == true) ||
        (v == 'unblock' && selected['blocked'] != true)) {
      return;
    }
    final profileRead = read;
    bool stillSelected() => mounted && sessionActive && _profileVerified &&
        read == profileRead && identical(u, selected);
    setState(() => busy = true);
    try {
      if (v == 'report') {
        await reportFlow(context, widget.session, 'user', widget.username, isActive: stillSelected);
      } else if (v == 'block') {
        var submitted = false;
        final blocked = await blockFlow(context, widget.session, widget.username,
            isActive: stillSelected, onSubmitted: () => submitted = true);
        if (!stillSelected()) return;
        if (blocked && route.isCurrent) {
          route.navigator?.pop();
        } else if (submitted) {
          await _load();
        }
      } else {
        try {
          await widget.session.call('DELETE', '/users/${widget.username}/block');
        } catch (e) {
          if (mounted && stillSelected()) showError(context, e);
        }
        if (stillSelected()) await _load();
      }
    } finally {
      if (mounted && sessionActive) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    final user = u;
    if (user == null) {
      return Scaffold(
        appBar: ReviewedAppBar(title: Text('@${widget.username}')),
        body: error != null ? EmptyState(icon: Ph.person_off_outlined, title: error!, action: OutlinedButton(onPressed: loading ? null : _load, child: Text(t_('Try again')))) : const Center(child: CircularProgressIndicator()),
      );
    }
    final isMe = user['is_me'] == true;
    final following = user['following'] == true;
    final blocked = user['blocked'] == true;
    return Scaffold(
      appBar: ReviewedAppBar(
        title: Text('@${user['username']}'),
        actions: [
          IconButton(tooltip: t_('Refresh profile'), onPressed: loading || busy ? null : _load, icon: const PhIcon('arrow-clockwise')),
          if (!isMe)
            PopupMenuButton<String>(
              enabled: !busy && !loading && _profileVerified,
              onSelected: _menu,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'report', child: Text(t_('Report'))),
                PopupMenuItem(value: blocked ? 'unblock' : 'block', child: Text(blocked ? t_('Unblock') : t_('Block'))),
              ],
            ),
        ],
      ),
      body: ProfilePosts(
        session: widget.session,
        query: {'username': widget.username},
        hideContent: blocked,
        emptyIcon: Ph.image_outlined,
        emptyTitle: t_('No photo or text posts yet'),
        header: Column(children: [
          if (error != null) _ProfileReadNotice(message: error!, retry: loading || busy ? null : _load),
          if (loading || busy) const LinearProgressIndicator(),
          ProfileHeader(
          user: user,
          onFollowers: !_profileVerified || !widget.session.followListsEnabled || blocked ? null : () => _openMembers(user, FollowListKind.followers),
          onFollowing: !_profileVerified || !widget.session.followListsEnabled || blocked ? null : () => _openMembers(user, FollowListKind.following),
          actions: isMe
              ? const SizedBox.shrink()
              : ProfileActions(children: [
                  following
                        ? OutlinedButton(onPressed: busy || loading || !_profileVerified ? null : _follow, child: Text(t_('Unfollow')))
                        : FilledButton(onPressed: busy || loading || !_profileVerified || blocked ? null : _follow, child: Text(t_('Follow'))),
                  OutlinedButton.icon(onPressed: busy || loading || !_profileVerified || blocked ? null : _message, icon: const PhIcon('chat-circle'), label: Text(t_('Message'))),
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

class _MePageState extends State<MePage> with SessionBoundState<MePage> {
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() {
    counts = null;
    error = null;
    loading = false;
    read++;
  }
  bool _opening = false;
  Future<void> _open(Widget page, {bool refreshProfile = false}) async {
    if (!mounted || !sessionActive || _opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    } finally {
      _opening = false;
    }
    if (mounted && sessionActive && refreshProfile) {
      setState(() => _refresh++);
      await _load();
    }
  }
  Future<void> _compose() async {
    if (!mounted || !sessionActive || _opening || widget.onCompose == null) return;
    _opening = true;
    try { await widget.onCompose!(); } finally { _opening = false; }
  }

  Map<String, dynamic>? counts;
  int _refresh = 0;
  late final uploads = UploadCenter.of(widget.session);
  int _publishedRevision = -1;
  void _published() {
    if (!mounted || !sessionActive || _publishedRevision == uploads.revision) return;
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
    if (!mounted || !sessionActive) return;
    final name = widget.session.user?['username'];
    if (name == null) return;
    final request = ++read;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/users/$name') as Map<String, dynamic>;
      final profile = _profileRead(j['user'], owner: widget.session.user?['public_id'] as String?);
      if (mounted && sessionActive && request == read) setState(() => counts = profile);
    } catch (e) {
      if (mounted && sessionActive && request == read) setState(() => error = e is ApiError ? t_(e.message) : t_('Profile could not be loaded.'));
    } finally { if (mounted && sessionActive && request == read) setState(() => loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return SessionRecoveryView(session: widget.session);
    final s = widget.session;
    final generation = s.generation;
    final listUsername = s.user?['username'] as String?;
    final listOwnerId = s.user?['public_id'] as String?;
    void openMembers(FollowListKind kind) {
      if (!mounted || !sessionActive || !identical(s, widget.session) || s.generation != generation || listUsername == null || listOwnerId == null || s.user?['public_id'] != listOwnerId || s.user?['username'] != listUsername || !s.followListsEnabled) return;
      _open(FollowListPage(session: s, username: listUsername, ownerId: listOwnerId, kind: kind));
    }
    final me = {...?counts, ...?s.user, for (final key in ['posts_count', 'followers_count', 'following_count']) if (counts?[key] != null) key: counts![key]};
    return Scaffold(
      appBar: ReviewedAppBar(
        title: Text('@${s.user?['username'] ?? t_('Me')}'),
        leading: IconButton(tooltip: t_('Settings'), icon: const PhIcon('list'), onPressed: () => _open(SettingsPage(session: s))),
        actions: [
          IconButton(tooltip: t_('Refresh profile'), onPressed: loading ? null : _load, icon: const PhIcon('arrow-clockwise')),
          if (widget.onCompose != null) IconButton(tooltip: t_('Post'), onPressed: _compose, icon: const PhIcon('plus')),
        ],
      ),
      body: ProfilePosts(
        key: ValueKey(_refresh),
        session: s,
        query: {'username': (s.user?['username'] ?? '').toString()},
        emptyIcon: Ph.image_outlined,
        emptyTitle: t_('No photo or text posts yet'),
        emptyHint: t_('A photo, a thought, a little of your day.'),
        emptyAction: widget.onCompose == null ? null : GlassAction(onPressed: _compose, icon: const PhIcon('plus', size: 18), label: t_('Create a post')),
        header: Column(children: [
          if (error != null) _ProfileReadNotice(message: error!, retry: loading ? null : _load),
          if (loading) const LinearProgressIndicator(),
          ProfileHeader(
          user: me,
          countsAvailable: counts != null,
          onFollowers: s.followListsEnabled ? () => openMembers(FollowListKind.followers) : null,
          onFollowing: s.followListsEnabled ? () => openMembers(FollowListKind.following) : null,
          actions: ProfileActions(children: [
            OutlinedButton.icon(
              icon: const PhIcon('pencil-simple', size: 18),
              label: Text(t_('Edit profile')),
              onPressed: () => _open(EditProfilePage(session: s), refreshProfile: true),
            ),
            OutlinedButton.icon(
              icon: const PhIcon('bookmark-simple', size: 18),
              label: Text(t_('Saved')),
              onPressed: () => _open(SavedPage(session: s)),
            ),
          ]),
        )]),
      ),
    );
  }
}

/// Only content types backed by Sanjaal are shown. Reposts/tags are not fake tabs.
class ProfilePosts extends StatefulWidget {
  const ProfilePosts({super.key, required this.session, required this.query, required this.header, required this.emptyIcon, required this.emptyTitle, this.emptyHint, this.emptyAction, this.hideContent = false});
  final bool hideContent;
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
  Widget build(BuildContext context) {
    if (widget.hideContent) {
      return ListView(children: [widget.header,
        EmptyState(icon: Ph.person_off_outlined, title: t_('This member is blocked.')),
      ]);
    }
    return IndexedStack(index: tab, children: [for (var i = 0; i < 2; i++)
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
    _finishing = false;
  }
  late final name = TextEditingController(text: (widget.session.user?['name'] ?? '').toString());
  late final username = TextEditingController(text: (widget.session.user?['username'] ?? '').toString());
  late final bio = TextEditingController(text: (widget.session.user?['bio'] ?? '').toString());
  final _form = GlobalKey<FormState>();
  bool busy = false;
  bool _finishing = false;
  bool get _locked => busy || _finishing;
  bool get _canEdit => mounted && sessionActive && ModalRoute.of(context)?.isCurrent == true;
  (String, String, String) get _values => (name.text, username.text, bio.text);
  late (String, String, String) initial;

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
    if (_locked || !_canEdit) return;
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
    if (_locked || !_canEdit || !_form.currentState!.validate()) return;
    final route = ModalRoute.of(context)!;
    final submitted = _values;
    setState(() => busy = true);
    try {
      await widget.session.updateProfile({'name': submitted.$1.trim(), 'username': submitted.$2.trim(), 'bio': submitted.$3.trim()});
      if (!mounted || !sessionActive) return;
      setState(() { initial = submitted; busy = false; _finishing = true; });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && sessionActive && route.isCurrent && _values == submitted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted && sessionActive) {
        setState(() => busy = false);
        showError(context, e);
      }
    } finally {
      if (mounted && sessionActive && _finishing) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    return DraftExitGuard(hasChanges: _values != initial, busy: busy, busyMessage: 'Your profile is still updating.', child: Scaffold(
      appBar: ReviewedAppBar(toolbarHeight: MediaQuery.textScalerOf(context).scale(40).clamp(56, 96), title: Text(t_('Edit profile'), maxLines: 2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), actions: [
        Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: _locked ? null : _save, child: Text(t_('Save')))),
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
                child: CircleAvatar(radius: 18, backgroundColor: Colors.white, child: IconButton(tooltip: t_('Change photo'), padding: EdgeInsets.zero, icon: const PhIcon('camera', size: 18, color: Colors.black), onPressed: _locked ? null : _avatar)),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          TextFormField(key: const ValueKey('profile-name'), controller: name, enabled: !_locked, maxLength: 80, decoration: InputDecoration(labelText: t_('Name'), border: const OutlineInputBorder()), validator: (v) => (v ?? '').trim().isEmpty ? t_('Required') : null),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('profile-username'),
            controller: username,
            enabled: !_locked,
            decoration: InputDecoration(labelText: t_('Username'), border: const OutlineInputBorder()),
            validator: (v) => RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch((v ?? '').trim()) ? null : t_('Use 3 to 30 letters, numbers, dots or underscores'),
          ),
          const SizedBox(height: 12),
          TextFormField(key: const ValueKey('profile-bio'), controller: bio, enabled: !_locked, maxLength: 160, maxLines: 3, decoration: InputDecoration(labelText: t_('Bio'), border: const OutlineInputBorder())),
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
