import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'about_page.dart';
import 'api.dart';

import 'push.dart';
import 'ui.dart';
import 'wallet_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(t_('Settings'))),
        body: ListView(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(t_('Theme'), style: Theme.of(context).textTheme.titleSmall)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(t_('System'))),
                ButtonSegment(value: ThemeMode.light, label: Text(t_('Light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(t_('Dark'))),
              ],
              selected: {prefs.mode},
              onSelectionChanged: (s) => prefs.setMode(s.first),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(t_('Language'), style: Theme.of(context).textTheme.titleSmall)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ne', label: Text('नेपाली'))],
              selected: {prefs.lang},
              onSelectionChanged: (s) => prefs.setLang(s.first),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          ValueListenableBuilder<String>(
            valueListenable: Push.status,
            builder: (context, v, child) => ListTile(leading: const Icon(Icons.notifications_outlined), title: Text(t_('Push notifications')), subtitle: Text(v)),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(t_('Coin wallet')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WalletPage(session: session))),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(t_('Blocked people')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlockedPage(session: session))),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(t_('About, privacy and terms')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(t_('Contact us')),
            subtitle: const Text('contact@fintex.au'),
            onTap: () => launchUrl(Uri.parse('mailto:contact@fintex.au?subject=Sanjaal')),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Delete my account'),
            subtitle: const Text('Sends a request by email'),
            onTap: () async {
              final u = (session.user?['username'] ?? '').toString();
              await launchUrl(Uri.parse('mailto:contact@fintex.au?subject=${Uri.encodeComponent('Delete my Sanjaal account')}&body=${Uri.encodeComponent('Please delete my Sanjaal account and data. Username: $u')}'));
            },
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(t_('Sign out')),
            onTap: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              session.logout();
            },
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Sanjaal $appVersion\nFintex Australia Pty Ltd (ABN 60 688 406 108)', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/users/blocked') as Map<String, dynamic>;
      if (mounted) setState(() => list = (j['data'] as List).cast<Map<String, dynamic>>());
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t_('Blocked people'))),
      body: list == null
          ? (error != null ? EmptyState(icon: Icons.cloud_off, title: error!) : const Center(child: CircularProgressIndicator()))
          : list!.isEmpty
              ? const EmptyState(icon: Icons.block, title: 'You have not blocked anyone')
              : ListView(children: [
                  for (final u in list!)
                    ListTile(
                      leading: Avatar(user: u),
                      title: Text('@${u['username']}'),
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            await widget.session.call('DELETE', '/users/${u['username']}/block');
                            await _load();
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        },
                        child: Text(t_('Unblock')),
                      ),
                    ),
                ]),
    );
  }
}
