import 'package:material_ui/material_ui.dart';
import 'ui.dart' show t_;

const appVersion = '0.3.0';

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
        Text('Sanjaal', style: t.headlineSmall),
        const Text('Version $appVersion'),
        const SizedBox(height: 8),
        const Text('A community app for Nepalis: a feed, short videos, chat, calls and a coin wallet.'),
        h('Publisher'),
        const Text('Fintex Australia Pty Ltd\nABN 60 688 406 108\ncontact@fintex.au'),
        h('Privacy'),
        const Text(
          'We store your email, username, display name, what you post and your messages so the app can work. '
          'We do not run ads, we do not sell your data and we do not track you across other apps. '
          'Wallet top ups are paid on eSewa. We see the payment reference and amount, never your eSewa login. '
          'To delete your account and data, write to contact@fintex.au.',
        ),
        h('Terms'),
        const Text(
          'Be kind. Do not post illegal content, spam or other people\'s private details. '
          'We may remove content or accounts that break these rules. '
          'Coins are an in app balance. They are bought with a verified top up, move between members and cannot be cashed out.',
        ),
        h('Open source licences'),
        OutlinedButton(onPressed: () => showLicensePage(context: context, applicationName: 'Sanjaal', applicationVersion: appVersion), child: const Text('View licences')),
      ]),
    );
  }
}
