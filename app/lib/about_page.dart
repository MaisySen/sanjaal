import 'package:material_ui/material_ui.dart';
import 'ui.dart' show t_, Logo;
import 'app_update_tile.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Actual platform package metadata, not a stale display-only version.
Future<String> installedVersion() async {
  try { final info = await PackageInfo.fromPlatform(); return '${info.version} (${info.buildNumber})'; } catch (_) { return 'Unavailable'; }
}

/// About, privacy and terms. Plain text, no network needed.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget h(String s) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 6), child: Text(s, style: t.titleMedium));
    return Scaffold(
      appBar: AppBar(title: Text(t_('About Sanjaal'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Align(alignment: Alignment.centerLeft, child: Logo(size: 64)),
        FutureBuilder<String>(future: installedVersion(), builder: (_, value) => Text('Version ${value.data ?? '...'}')),
        const SizedBox(height: 8),
        const Text('A community app for Nepalis: a feed, short videos, chat, calls and a coin wallet.'),
        h('App updates'),
        const AppUpdateTile(),
        h('Publisher'),
        const Text('Fintex Australia Pty Ltd\nABN 60 688 406 108\ncontact@fintex.au'),
        h('Privacy'),
        const Text(
          'We store your email, username, display name, what you post and your messages so the app can work. '
          'We do not run ads, we do not sell your data and we do not track you across other apps. '
          'Adding coins is not switched on yet. '
          'To delete your account and data, write to contact@fintex.au.',
        ),
        h('Terms'),
        const Text(
          'Be kind. Do not post illegal content, spam or other people\'s private details. '
          'We may remove content or accounts that break these rules. '
          'Coins are an in app balance. Adding coins is not switched on yet. Coins move between members and cannot be cashed out.',
        ),
        h('Open source licences'),
        OutlinedButton(onPressed: () => showLicensePage(context: context, applicationName: 'Sanjaal', applicationVersion: null), child: const Text('View licences')),
      ]),
    );
  }
}
