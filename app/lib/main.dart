import 'package:material_ui/material_ui.dart';
import 'dart:async';
import 'about_page.dart';
import 'api.dart';
import 'auth_page.dart';
import 'chat_pages.dart';
import 'feed_page.dart';
import 'wallet_page.dart';

void main() => runApp(const SanjaalApp());

class SanjaalApp extends StatefulWidget {
  const SanjaalApp({super.key});
  @override
  State<SanjaalApp> createState() => _SanjaalAppState();
}

class _SanjaalAppState extends State<SanjaalApp> {
  final session = Session();

  @override
  void initState() {
    super.initState();
    session.restore();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sanjaal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC8102E)),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.loading) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (session.user == null) return AuthPage(session: session);
          return HomeShell(session: session);
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session});
  final Session session;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  int unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refreshUnread();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshUnread());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    try {
      final j = await widget.session.call('GET', '/notifications/summary') as Map<String, dynamic>;
      final n = (j['unread_messages'] as num?)?.toInt() ?? 0;
      if (mounted && n != unread) setState(() => unread = n);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FeedPage(session: widget.session),
      ChatsPage(session: widget.session),
      ProfilePage(session: widget.session),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() => tab = i);
          _refreshUnread();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dynamic_feed_outlined), selectedIcon: Icon(Icons.dynamic_feed), label: 'Feed'),
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_outline)),
            selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble)),
            label: 'Chats',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final u = session.user!;
    final name = (u['name'] ?? '').toString();
    final username = (u['username'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text((username.isEmpty ? name : username).characters.firstOrNull?.toUpperCase() ?? '?',
                  style: const TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text(username.isEmpty ? name : '@$username', style: Theme.of(context).textTheme.titleLarge)),
          if (name.isNotEmpty && name != username) Center(child: Text(name)),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Coin wallet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WalletPage(session: session))),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About, privacy and terms'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () => session.logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 32),
          const Text('Sanjaal 0.1.1\nPublished by Fintex Australia Pty Ltd (ABN 60 688 406 108)\ncontact@fintex.au',
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
