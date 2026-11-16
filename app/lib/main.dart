import 'glass_nav.dart';
import 'ph.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'auth_page.dart';
import 'calls_page.dart';
import 'chat_pages.dart';
import 'feed_page.dart';
import 'stories_page.dart' show addStory;
import 'onboarding_page.dart';
import 'profile_pages.dart';
import 'reels_page.dart';
import 'ui.dart';
import 'wallet_page.dart';

void main() {
  registerPhosphorLicense();
  runApp(const SanjaalApp());
}

ThemeData buildTheme(Brightness b, {String? fontFamily, List<String>? fontFamilyFallback}) {
  final light = b == Brightness.light;
  // Near-black surface, white primary actions, quiet greys (reviewed direction, Nov 16 2026).
  final scheme = ColorScheme(
    brightness: b,
    primary: light ? const Color(0xFF0B0D11) : Colors.white,
    onPrimary: light ? Colors.white : const Color(0xFF0B0D11),
    primaryContainer: light ? const Color(0xFFE9EBEF) : const Color(0xFF232833),
    onPrimaryContainer: light ? const Color(0xFF0B0D11) : Colors.white,
    secondary: light ? const Color(0xFF3A4150) : const Color(0xFFC9CED8),
    onSecondary: light ? Colors.white : const Color(0xFF0B0D11),
    error: light ? const Color(0xFFC62840) : const Color(0xFFFF6B7C),
    onError: light ? Colors.white : const Color(0xFF2A0006),
    surface: light ? Colors.white : const Color(0xFF0B0D11),
    onSurface: light ? const Color(0xFF0B0D11) : Colors.white,
    surfaceContainerLowest: light ? Colors.white : const Color(0xFF090B0E),
    surfaceContainerLow: light ? const Color(0xFFF6F7F9) : const Color(0xFF12151B),
    surfaceContainer: light ? const Color(0xFFF0F2F5) : const Color(0xFF181C23),
    surfaceContainerHigh: light ? const Color(0xFFE9EBEF) : const Color(0xFF1F242D),
    surfaceContainerHighest: light ? const Color(0xFFE1E4E9) : const Color(0xFF272C36),
    onSurfaceVariant: light ? const Color(0xFF4A505C) : const Color(0xFFA6A9AF),
    outline: light ? const Color(0xFF6B7280) : const Color(0xFF8A8E96),
    outlineVariant: light ? const Color(0xFFDDE0E5) : const Color(0xFF2A2F39),
  );
  const r = BorderRadius.all(Radius.circular(14));
  const shape = RoundedRectangleBorder(borderRadius: r);
  final labelStyle = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.1);
  final base = ThemeData(brightness: b, fontFamily: fontFamily, useMaterial3: true).textTheme.apply(fontFamilyFallback: fontFamilyFallback);
  final text = base.copyWith(
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 15.5, height: 1.4),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.35),
    labelSmall: base.labelSmall?.copyWith(letterSpacing: 0.4, fontWeight: FontWeight.w600),
  );
  return ThemeData(
    fontFamily: fontFamily,
    colorScheme: scheme,
    textTheme: text,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, color: scheme.onSurface, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: scheme.outlineVariant)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 60,
      elevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 11, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500, color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? scheme.primaryContainer : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: shape, minimumSize: const Size(64, 44), textStyle: labelStyle)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: shape, minimumSize: const Size(64, 44), side: BorderSide(color: scheme.outlineVariant), textStyle: labelStyle)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape, foregroundColor: scheme.onSurfaceVariant, textStyle: labelStyle)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: scheme.onSurface)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    chipTheme: ChipThemeData(shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))), side: BorderSide(color: scheme.outlineVariant), backgroundColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape, backgroundColor: scheme.onSurface, contentTextStyle: TextStyle(color: scheme.surface)),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
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
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
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
    final what = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => const CreateSheet());
    if (what == null || !mounted) return;
    if (what == 'story') {
      if (await addStory(context, widget.session) && mounted) showInfo(context, 'Your story is up. It shows in the row at the top of Home.');
      return;
    }
    final p = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ComposePage(session: widget.session, startWithVideo: what == 'reel')));
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
      body: Column(children: [
        ListenableBuilder(
          listenable: s,
          builder: (context, _) => s.offline ? _OfflineBanner(onRetry: _refreshUnread) : const SizedBox.shrink(),
        ),
        Expanded(child: IndexedStack(index: tab, children: pages)),
      ]),
      extendBody: true,
      bottomNavigationBar: GlassNavBar(
        index: tab,
        onSelected: (i) {
          setState(() => tab = i);
          _refreshUnread();
        },
        items: [
          NavItem(t_('Home'), 'house', 'house-fill'),
          NavItem(t_('Reels'), 'play-circle', 'play-circle-fill'),
          NavItem(t_('Chats'), 'chat-circle', 'chat-circle-fill', badge: unread),
          NavItem(t_('Wallet'), 'wallet', 'wallet-fill'),
          NavItem(t_('Me'), 'user-circle', 'user-circle-fill'),
        ],
      ),
    );
  }
}

/// Shown above the tabs after a request failed for lack of a connection. Retry makes one
/// request; the banner clears when any request gets a response.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(children: [
            const PhIcon('wifi-slash', size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(t_('No connection. Some things may be out of date.'), style: Theme.of(context).textTheme.bodyMedium)),
            TextButton(onPressed: onRetry, child: Text(t_('Retry'))),
          ]),
        ),
      ),
    );
  }
}
