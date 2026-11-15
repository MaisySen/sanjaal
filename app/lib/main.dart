import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'auth_page.dart';
import 'calls_page.dart';
import 'chat_pages.dart';
import 'feed_page.dart';
import 'onboarding_page.dart';
import 'profile_pages.dart';
import 'reels_page.dart';
import 'ui.dart';
import 'wallet_page.dart';

void main() => runApp(const SanjaalApp());

ThemeData _theme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: brandRed, secondary: brandBlue, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: scheme.surface, scrolledUnderElevation: 1),
    cardTheme: CardThemeData(elevation: 0, color: scheme.surfaceContainerLow, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    navigationBarTheme: NavigationBarThemeData(indicatorColor: scheme.primaryContainer, labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(64, 46))),
    inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
  );
}

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
    prefs.load();
    session.restore();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => MaterialApp(
        title: 'Sanjaal',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: prefs.mode,
        home: KeyedSubtree(
          key: ValueKey(prefs.lang),
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              if (session.loading || !prefs.ready) {
                return const Scaffold(body: Center(child: Logo(size: 96)));
              }
              if (session.user == null) {
                return prefs.seenOnboarding ? AuthPage(session: session) : const OnboardingPage();
              }
              return HomeShell(session: session);
            },
          ),
        ),
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
  Timer? _ring;
  bool _ringing = false;
  String? _lastCall;
  final feedKey = GlobalKey<FeedListState>();

  @override
  void initState() {
    super.initState();
    _refreshUnread();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshUnread());
    _ring = Timer.periodic(const Duration(seconds: 5), (_) => _checkIncoming());
  }

  Future<void> _checkIncoming() async {
    if (_ringing || !mounted) return;
    try {
      final j = await widget.session.call('GET', '/calls/incoming') as Map<String, dynamic>;
      final list = (j['data'] as List).cast<Map<String, dynamic>>();
      if (list.isEmpty || !mounted) return;
      if (list.first['public_id'] == _lastCall) return;
      _lastCall = list.first['public_id'] as String;
      _ringing = true;
      HapticFeedback.heavyImpact();
      await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => IncomingCallPage(session: widget.session, call: list.first)));
    } catch (_) {
    } finally {
      _ringing = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ring?.cancel();
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    try {
      final j = await widget.session.call('GET', '/notifications/summary') as Map<String, dynamic>;
      final n = (j['unread_messages'] as num?)?.toInt() ?? 0;
      if (mounted && n != unread) setState(() => unread = n);
    } catch (_) {}
  }

  Future<void> _compose() async {
    final p = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ComposePage(session: widget.session)));
    if (p != null && mounted) {
      showInfo(context, p['kind'] == 'reel' ? 'Your reel is live in the Reels tab.' : 'Posted. Pull down on Home to refresh.');
      setState(() => tab = p['kind'] == 'reel' ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = [
      FeedPage(session: s, onCompose: _compose),
      ReelsPage(session: s, active: tab == 1),
      ChatsPage(session: s),
      WalletPage(session: s),
      MePage(session: s),
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
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t_('Home')),
          NavigationDestination(icon: const Icon(Icons.play_circle_outline), selectedIcon: const Icon(Icons.play_circle), label: t_('Reels')),
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_outline)),
            selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble)),
            label: t_('Chats'),
          ),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: t_('Wallet')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t_('Me')),
        ],
      ),
    );
  }
}
