import 'reports_page.dart';
import 'language_settings_page.dart';
import 'appearance_settings_page.dart';
import 'glass/glass_app_bar.dart';
import 'session_bound_state.dart';
import 'session_recovery.dart';
import 'creator_drafts_page.dart';
import 'member_controls_page.dart';
import 'story_audience_page.dart';
import 'feed_page.dart' show SavedPage;
import 'profile_pages.dart' show EditProfilePage;
import 'notifications_page.dart';
import 'ph.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'about_page.dart';
import 'api.dart';

import 'push.dart';
import 'ui.dart';
import 'wallet_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.session});
  final Session session;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> with SessionBoundState<SettingsPage> {
  @override
  Session get viewSession => widget.session;
  String query = '';
  final _search = TextEditingController();
  bool _opening = false;
  bool _openingMail = false;

  Future<void> _openMail({bool deletion = false}) async {
    if (!mounted || !sessionActive || _openingMail) return;
    final route = ModalRoute.of(context);
    bool ownsRoute() => mounted && sessionActive && (route == null || route.isCurrent);
    if (!ownsRoute()) return;
    _openingMail = true;
    final username = (widget.session.user?['username'] ?? '').toString();
    final uri = deletion
        ? Uri.parse('mailto:contact@fintex.au?subject=${Uri.encodeComponent('Delete my Sanjaal account')}&body=${Uri.encodeComponent('Please delete my Sanjaal account and data. Username: $username')}')
        : Uri.parse('mailto:contact@fintex.au?subject=Sanjaal');
    final fallback = deletion
        ? 'Email contact@fintex.au to request account deletion.'
        : 'Email contact@fintex.au for help.';
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      // Native failures use the same recovery as a missing email handler.
    } finally {
      _openingMail = false;
    }
    if (!opened && mounted && ownsRoute()) showInfo(context, t_(fallback));
  }
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
  Future<void> open(Widget page) async {
    if (!mounted || !sessionActive || _opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    } finally {
      _opening = false;
    }
  }
  void _clearSearch() {
    if (!mounted || !sessionActive) return;
    _search.clear();
    setState(() => query = '');
  }
  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return _retiredSettingsView(context, widget.session);
    final session = widget.session;
    Widget option(String title, String icon, VoidCallback action, {String? subtitle, bool destructive = false}) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      leading: PhIcon(icon, size: 26, color: destructive ? Theme.of(context).colorScheme.error : null),
      title: Text(t_(title)), subtitle: subtitle == null ? null : Text(t_(subtitle)),
      trailing: const PhIcon('caret-right', size: 18), onTap: action,
    );
    final groups = <String, List<(String, Widget)>>{
      'Your account': [
        ('Profile personal details', option('Edit profile', 'user-circle', () => open(EditProfilePage(session: session)))),
      ],
      'How you use Sanjaal': [
        ('Saved drafts local text poll', option('Saved drafts', 'bookmark-simple', () => open(CreatorDraftsPage(session: session)))),
        ('Saved bookmarks', option('Saved', 'bookmark-simple', () => open(SavedPage(session: session)))),
        ('Notifications push', option('Notifications', 'bell', () => open(_NotificationSettings(session: session)))),
      ],
      'Who can interact with you': [
        if (session.protectedStoriesEnabled) ('Story close friends hide audience', option('Story audience', 'users', () => open(StoryAudiencePage(session:session)))),
        if (session.interactionControlsEnabled) ('Comments sharing audience', option('Comments and sharing', 'chat-teardrop', () => open(MemberControlsPage(session: session)))),
        ('Blocked people privacy', option('Blocked people', 'prohibit', () => open(BlockedPage(session: session)))),
      ],
      'Your app and media': [
        ('Appearance theme light dark', option('Appearance', 'moon', () => open(const AppearanceSettingsPage()))),
        ('Language translations English Nepali', option('Language', 'translate', () => open(const LanguageSettingsPage()))),
      ],
      'Your balance and activity': [
        ('Coin wallet payments activity', option('Coin wallet', 'wallet', () => open(WalletPage(session: session)))),
      ],
      'More info and support': [
        if (session.reportHistoryEnabled) ('Your reports safety support history', option('Your reports', 'warning-circle', () => open(ReportsPage(session: session)))),
        ('About privacy terms licences', option('About, privacy and terms', 'info', () => open(const AboutPage()))),
        ('Help contact support', option('Contact us', 'envelope-simple', () => _openMail(), subtitle: 'contact@fintex.au')),
        ('Delete my account data', option('Delete my account', 'trash', () => _openMail(deletion: true), subtitle: 'Opens a draft in your email app')),
      ],
      'Login': [
        ('Sign out logout', option('Sign out', 'sign-out', () {
          if(!mounted || !sessionActive)return;
          Navigator.of(context).popUntil((r) => r.isFirst); session.logout();
        }, destructive: true)),
      ],
    };
    final visible = <String, List<Widget>>{};
    for (final entry in groups.entries) {
      final rows = entry.value.where((row) => query.isEmpty || ('${t_(entry.key)} ${row.$1} ${(row.$2 as ListTile).title is Text ? ((row.$2 as ListTile).title as Text).data : ''}').toLowerCase().contains(query)).map((row) => row.$2).toList();
      if (rows.isNotEmpty) visible[entry.key] = rows;
    }
    return Scaffold(
      appBar: ReviewedAppBar(centerTitle: true, title: Text(t_('Settings and activity'))),
      body: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(controller: _search, onChanged: (value) => setState(() => query = value.trim().toLowerCase()), decoration: InputDecoration(hintText: t_('Search settings'), suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: t_('Clear search'), onPressed: _clearSearch, icon: const PhIcon('x')), prefixIcon: const Center(widthFactor: 1, heightFactor: 1, child: PhIcon('magnifying-glass', size: 22)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none)))),
        if (visible.isEmpty) EmptyState(icon: Ph.search_off, title: t_('No matching settings')),
        for (final entry in visible.entries) ...[
          Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 10), child: Text(t_(entry.key), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
          ...entry.value,
          const Divider(height: 20, thickness: 6),
        ],
        if (query.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('Sanjaal\nFintex Australia Pty Ltd (ABN 60 688 406 108)', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
class _NotificationSettings extends StatefulWidget {
  const _NotificationSettings({required this.session});
  final Session session;
  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}
class _NotificationSettingsState extends State<_NotificationSettings> with SessionBoundState<_NotificationSettings> {
  @override
  Session get viewSession => widget.session;
  bool _openingActivity = false;
  Future<void> _openActivity() async {
    if (!mounted || !sessionActive || _openingActivity) return;
    _openingActivity = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsPage(session: widget.session)));
    } finally {
      _openingActivity = false;
    }
  }
  @override
  Widget build(BuildContext context) => !sessionActive ? _retiredSettingsView(context, widget.session) : Scaffold(appBar: ReviewedAppBar(title: Text(t_('Notifications'))), body: ListView(children: [
    ValueListenableBuilder<String>(valueListenable: Push.status, builder: (context, value, _) => ListTile(leading: const PhIcon('bell'), title: Text(t_('Push notifications')), subtitle: Text(t_(value)))),
    ListTile(title: Text(t_('Activity')), trailing: const PhIcon('caret-right'), onTap: _openActivity),
  ]));
}

class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key, required this.session});
  final Session session;
  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> with SessionBoundState<BlockedPage> {
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() {
    list = null;
    error = null;
    loading = false;
    changing = false;
  }
  List<Map<String, dynamic>>? list;
  String? error;
  bool loading = false;
  bool changing = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load({bool afterChange = false}) async {
    if (!mounted || !sessionActive || loading || (changing && !afterChange)) return;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/users/blocked') as Map<String, dynamic>;
      final rows = (j['data'] as List).map((v) => (v as Map).cast<String,dynamic>()).toList();
      if (rows.any((u) => u['username'] is! String)) throw const FormatException('Invalid blocked member');
      if (mounted && sessionActive) setState(() => list = rows);
    } catch (e) {
      if (mounted && sessionActive) setState(() => error = e is ApiError ? t_(e.message) : t_('Blocked people could not be loaded.'));
    } finally { if (mounted && sessionActive) setState(() => loading = false); }
  }

  Future<void> _unblock(Map<String, dynamic> user) async {
    if (!mounted || !sessionActive || loading || changing ||
        list?.any((current) => identical(current, user)) != true) {
      return;
    }
    setState(() => changing = true);
    try {
      await widget.session.call('DELETE', '/users/${user['username']}/block');
      await _load(afterChange: true);
    } catch (e) {
      if (mounted && sessionActive) showError(context, e);
    } finally {
      if (mounted && sessionActive) setState(() => changing = false);
    }
  }

  @override
  Widget build(BuildContext context) => !sessionActive ? _retiredSettingsView(context, widget.session) : Scaffold(
    appBar: ReviewedAppBar(toolbarHeight: MediaQuery.textScalerOf(context).scale(40).clamp(56, 96), title: Text(t_('Blocked people'), maxLines: 2, style: const TextStyle(fontSize: 18)), actions: [IconButton(tooltip: t_('Refresh'), onPressed: loading || changing ? null : _load, icon: const PhIcon('arrow-clockwise'))]),
    body: list == null && loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: _load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Text(error!, textAlign: TextAlign.center),
          TextButton(onPressed: loading || changing ? null : _load, child: Text(t_('Try again'))),
        ])),
        if (list != null && list!.isEmpty) EmptyState(icon: Ph.block, title: t_('You have not blocked anyone')),
        for (final u in list ?? <Map<String,dynamic>>[]) ListTile(
          leading: Avatar(user: u), title: Text('@${u['username']}'),
          trailing: TextButton(onPressed: loading || changing ? null : () => _unblock(u), child: Text(t_('Unblock'))),
        ),
      ])),
  );
}


// Settings and Reels share the same live-session recovery behavior.
Widget _retiredSettingsView(BuildContext context, Session session) => SessionRecoveryView(session: session);
