// Review-only proposed service designs. Not exported by the production app.
// No network calls, files, account changes or real data.
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/glass/glass_app_bar.dart';
import 'package:sanjaal/glass/glass_action.dart';
import 'package:sanjaal/glass/glass_surface.dart';
import 'package:sanjaal/ph.dart';

class ProposedServiceScreen extends StatelessWidget {
  const ProposedServiceScreen(this.screen, {super.key});
  final String screen;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, String body) => Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.textTheme.titleMedium), const SizedBox(height: 6), Text(body),
    ]));
    Widget row(String title, String subtitle, {bool selected = false, bool arrow = false}) => ListTile(
      contentPadding: EdgeInsets.zero, title: Text(title), subtitle: Text(subtitle),
      trailing: PhIcon(arrow ? 'caret-right' : selected ? 'check-circle-fill' : 'circle', color: selected ? theme.colorScheme.primary : null),
      onTap: () {},
    );
    late String title, action;
    late List<Widget> children;
    switch (screen) {
      case 'report-review':
        title = 'Review report'; action = 'Submit report';
        children = [section('Post', '@member · Community concert'), const Divider(), row('Reason', 'Spam', arrow: true), section('Your privacy', 'Your name is not shown to the reported member.'), const SizedBox(height: 16), Text('You can block this member separately. Reporting does not block them.')];
      case 'report-status':
        title = 'Your report'; action = 'Back to reports';
        children = [section('Reference R-0241', 'Submitted'), const Divider(), section('Report details', 'Spam · Community concert'), section('Updates', 'No update yet. You can return here to check this report.'), TextButton.icon(onPressed: () {}, icon: const PhIcon('chat-circle'), label: const Text('Contact support'))];
      case 'report-result':
        title = 'Your report'; action = 'Back to reports';
        children = [section('Reference R-0241', 'Update available'), const Divider(), section('Update from support', 'Your report has been closed.'), section('Need more help?', 'Contact support with your report reference.'), TextButton.icon(onPressed: () {}, icon: const PhIcon('chat-circle'), label: const Text('Contact support'))];
      case 'privacy-audience':
        title = 'Post audience'; action = 'Save audience';
        children = [section('Who can see this post?', 'Choose who can view this post.'), row('Everyone', 'People who can view your profile'), const Divider(), row('Followers', 'Your approved followers', selected: true), const Divider(), row('Only me', 'Keep this post private'), section('Before you save', 'This changes access to this post. Copies already saved or shared outside Sanjaal cannot be taken back.')];
      case 'privacy-saved':
        title = 'Post audience'; action = 'Done';
        children = [const SizedBox(height: 20), Align(alignment: Alignment.centerLeft, child: PhIcon('check-circle-fill', size: 40, color: theme.colorScheme.primary)), section('Audience updated', 'Followers can view this post.'), const Divider(), row('Current audience', 'Followers', arrow: true)];
      case 'delete-review':
        title = 'Delete account'; action = 'Continue';
        children = [section('Before you continue', 'You are deleting @yourname.'), const Divider(), row('What happens to your account', 'Read deletion and retention details', arrow: true), section('Keep a copy first', 'You can request your data before deleting your account.'), TextButton(onPressed: () {}, child: const Text('Request your data')), section('Your next step', 'Verify your account, then review the final confirmation.')];
      case 'delete-confirm':
        title = 'Delete account'; action = 'Delete account';
        children = [section('Confirm deletion', '@yourname'), const Divider(), section('Check before you delete', 'Read what is removed and what must be retained before confirming.'), row('Deletion and retention details', 'Details unavailable. Try again.', arrow: true), const SizedBox(height: 16), const Text('This is separate from signing out. Only confirm if you want to delete this account.')];
      case 'delete-status':
        title = 'Account deletion'; action = 'Contact support';
        children = [section('Request D-0124', 'Deletion requested'), const Divider(), section('Keep your reference', 'Use D-0124 if you contact support.'), section('Request status', 'Your request has been received. Check the request details for the next update.'), row('Request details', 'View status and account details', arrow: true)];
      case 'export-request':
        title = 'Your data'; action = 'Request download';
        children = [section('Download your information', 'Request a copy for this account.'), const Divider(), row('Account', '@yourname', selected: true), section('What is included', 'Review the available data before requesting your file.'), TextButton(onPressed: () {}, child: const Text('View included information')), section('Private delivery', 'Verify your account to request and download your file.')];
      case 'export-ready':
        title = 'Your data'; action = 'Download data';
        children = [section('Request E-0142', 'Ready to download'), const Divider(), section('Your private download', 'Verify your account to download this file.'), row('File details', 'View contents, size and expiry', arrow: true), section('Keep it safe', 'Your download may include private information. Only save it somewhere you trust.')];
      default: throw ArgumentError(screen);
    }
    return Scaffold(
      appBar: ReviewedAppBar(leading: IconButton(onPressed: () {}, tooltip: 'Back', icon: Transform.rotate(angle: 3.141592653589793, child: const PhIcon('caret-right'))), title: Text(title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: children),
      bottomNavigationBar: SafeArea(top: false, child: GlassSurface(radius: 0, blur: 20, child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GlassAction(label: action, onPressed: screen == 'delete-confirm' ? null : () {}),
        if (screen.startsWith('delete')) TextButton(onPressed: () {}, child: Text(screen == 'delete-status' ? 'Request details' : 'Keep account')),
      ])))),
    );
  }
}
