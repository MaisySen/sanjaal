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
class _SettingsPageState extends State<SettingsPage> {
  String query = '';
  void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
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
        ('Appearance theme light dark', option('Appearance', 'moon', () => open(const _AppearanceSettings()))),
        ('Language translations English Nepali', option('Language', 'translate', () => open(const _LanguageSettings()))),
      ],
      'Your balance and activity': [
        ('Coin wallet payments activity', option('Coin wallet', 'wallet', () => open(WalletPage(session: session)))),
      ],
      'More info and support': [
        ('About privacy terms licences', option('About, privacy and terms', 'info', () => open(const AboutPage()))),
        ('Help contact support', option('Contact us', 'envelope-simple', () async {
          final ok = await launchUrl(Uri.parse('mailto:contact@fintex.au?subject=Sanjaal'));
          if (!ok && context.mounted) showInfo(context, 'Email contact@fintex.au for help.');
        }, subtitle: 'contact@fintex.au')),
        ('Delete my account data', option('Delete my account', 'trash', () async {
          final u = (session.user?['username'] ?? '').toString();
          final ok = await launchUrl(Uri.parse('mailto:contact@fintex.au?subject=${Uri.encodeComponent('Delete my Sanjaal account')}&body=${Uri.encodeComponent('Please delete my Sanjaal account and data. Username: $u')}'));
          if (!ok && context.mounted) showInfo(context, 'Email contact@fintex.au to request account deletion.');
        }, subtitle: 'Sends a request by email')),
      ],
      'Login': [
        ('Sign out logout', option('Sign out', 'sign-out', () {
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
      appBar: AppBar(centerTitle: true, title: Text(t_('Settings and activity'))),
      body: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(onChanged: (value) => setState(() => query = value.trim().toLowerCase()), decoration: InputDecoration(hintText: t_('Search settings'), prefixIcon: const PhIcon('magnifying-glass'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none)))),
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
class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings();
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => Scaffold(
    appBar: AppBar(title: Text(t_('Appearance'))), body: ListView(children: [
      for (final item in [(ThemeMode.system, 'System'), (ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')])
        ListTile(title: Text(t_(item.$2)), trailing: prefs.mode == item.$1 ? const PhIcon('check') : null, onTap: () => prefs.setMode(item.$1)),
    ]),
  ));
}
class _LanguageSettings extends StatelessWidget {
  const _LanguageSettings();
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => Scaffold(
    appBar: AppBar(title: Text(t_('Language'))), body: ListView(children: [
      for (final item in [('en', 'English'), ('ne', 'नेपाली')]) ListTile(title: Text(item.$2), trailing: prefs.lang == item.$1 ? const PhIcon('check') : null, onTap: () => prefs.setLang(item.$1)),
    ]),
  ));
}
class _NotificationSettings extends StatelessWidget {
  const _NotificationSettings({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(t_('Notifications'))), body: ListView(children: [
    ValueListenableBuilder<String>(valueListenable: Push.status, builder: (context, value, _) => ListTile(leading: const PhIcon('bell'), title: Text(t_('Push notifications')), subtitle: Text(t_(value)))),
    ListTile(title: Text(t_('Activity')), trailing: const PhIcon('caret-right'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsPage(session: session)))),
  ]));
}

class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key, required this.session});
  final Session session;
  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  List<Map<String, dynamic>>? list;
  String? error;
  bool loading = false;
  bool changing = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (loading) return;
    setState(() { loading = true; error = null; });
    try {
      final j = await widget.session.call('GET', '/users/blocked') as Map<String, dynamic>;
      final rows = (j['data'] as List).map((v) => (v as Map).cast<String,dynamic>()).toList();
      if (rows.any((u) => u['username'] is! String)) throw const FormatException('Invalid blocked member');
      if (mounted) setState(() => list = rows);
    } catch (e) {
      if (mounted) setState(() => error = e is ApiError ? t_(e.message) : t_('Blocked people could not be loaded.'));
    } finally { if (mounted) setState(() => loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(toolbarHeight: MediaQuery.textScalerOf(context).scale(40).clamp(56, 96), title: Text(t_('Blocked people'), maxLines: 2, style: const TextStyle(fontSize: 18)), actions: [IconButton(tooltip: t_('Refresh'), onPressed: loading ? null : _load, icon: const PhIcon('arrow-clockwise'))]),
    body: list == null && loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: _load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Text(error!, textAlign: TextAlign.center),
          TextButton(onPressed: loading ? null : _load, child: Text(t_('Try again'))),
        ])),
        if (list != null && list!.isEmpty) EmptyState(icon: Ph.block, title: t_('You have not blocked anyone')),
        for (final u in list ?? <Map<String,dynamic>>[]) ListTile(
          leading: Avatar(user: u), title: Text('@${u['username']}'),
          trailing: TextButton(onPressed: loading || changing ? null : () async {
            setState(() => changing = true);
            try {
              await widget.session.call('DELETE', '/users/${u['username']}/block');
              await _load();
            } catch (e) { if (context.mounted) showError(context, e); }
            finally { if (mounted) setState(() => changing = false); }
          }, child: Text(t_('Unblock'))),
        ),
      ])),
  );
}
