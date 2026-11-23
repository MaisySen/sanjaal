import 'active_call_host.dart';
import 'native_call_root.dart';
import 'message_open_host.dart';
import 'push.dart';
import 'profile_setup_page.dart';
import 'glass/glass_sheet.dart';
import 'glass/glass_settings.dart';
import 'discovery_entry.dart';
import 'upload_center.dart';
import 'glass_nav.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'media_visibility.dart';
import 'ph.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry, LicenseEntryWithLineBreaks;
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
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL-NotoSansDevanagari.txt');
    yield LicenseEntryWithLineBreaks(['Noto Sans Devanagari'], text);
  });
  runApp(const SanjaalApp());
}

ThemeData buildTheme(Brightness b, {String? fontFamily, List<String>? fontFamilyFallback = const ['NotoDev']}) {
  final light = b == Brightness.light;
  // PR1 identity; white light-mode surfaces follow owner-provided references.
  final scheme = ColorScheme(
    brightness: b,
    primary: light ? const Color(0xFFB3122B) : const Color(0xFFFF7A87),
    onPrimary: light ? Colors.white : const Color(0xFF3A0008),
    primaryContainer: light ? const Color(0xFFF3E4DF) : const Color(0xFF3A2220),
    onPrimaryContainer: light ? const Color(0xFF5B0A17) : const Color(0xFFFFD9DC),
    secondary: light ? const Color(0xFF24405F) : const Color(0xFF9DB8DC),
    onSecondary: light ? Colors.white : const Color(0xFF0B2038),
    error: light ? const Color(0xFFB3261E) : const Color(0xFFFFB4AB),
    onError: light ? Colors.white : const Color(0xFF601410),
    surface: light ? const Color(0xFFFFFFFF) : const Color(0xFF141311),
    onSurface: light ? const Color(0xFF161719) : const Color(0xFFECE8E1),
    surfaceContainerLowest: light ? Colors.white : const Color(0xFF0F0E0C),
    surfaceContainerLow: light ? const Color(0xFFF5F5F5) : const Color(0xFF1B1A17),
    surfaceContainer: light ? const Color(0xFFF0F1F2) : const Color(0xFF211F1C),
    surfaceContainerHigh: light ? const Color(0xFFEBEDEF) : const Color(0xFF292723),
    surfaceContainerHighest: light ? const Color(0xFFE5E7EB) : const Color(0xFF312F2A),
    onSurfaceVariant: light ? const Color(0xFF60646B) : const Color(0xFFA9A398),
    outline: light ? const Color(0xFF7A7469) : const Color(0xFF8B857A),
    outlineVariant: light ? const Color(0xFFDDDFE2) : const Color(0xFF3A372F),
  );
  const cardR = BorderRadius.all(Radius.circular(20));
  const buttonR = BorderRadius.all(Radius.circular(8));
  const inputR = BorderRadius.all(Radius.circular(12));
  const shape = RoundedRectangleBorder(borderRadius: buttonR);
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
      shape: RoundedRectangleBorder(borderRadius: cardR, side: BorderSide(color: scheme.outlineVariant)),
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
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: shape, minimumSize: const Size(64, 48), textStyle: labelStyle)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: shape, minimumSize: const Size(64, 48), side: BorderSide(color: scheme.outlineVariant), textStyle: labelStyle)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape, foregroundColor: scheme.onSurfaceVariant, textStyle: labelStyle)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: scheme.onSurface)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: inputR, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: inputR, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: inputR, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    chipTheme: ChipThemeData(shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))), side: BorderSide(color: scheme.outlineVariant), backgroundColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape, backgroundColor: scheme.onSurface, contentTextStyle: base.bodyMedium?.copyWith(color: scheme.surface)),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

class SanjaalApp extends StatefulWidget {
  const SanjaalApp({super.key, this.fontFamily});
  // Optional host-review font. Normal launches retain platform typography.
  final String? fontFamily;
  @override
  State<SanjaalApp> createState() => _SanjaalAppState();
}

class _SanjaalAppState extends State<SanjaalApp> {
  final session = Session();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _activeCallKey = GlobalKey<ActiveCallHostState>();
  final _messageOpens = const FirebaseMessageOpenSource();
  bool _createAccount = false;
  bool _preferencesLoading = true;
  bool _preferencesFailed = false;
  bool _preferencesReading = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    session.restore();
  }

  Future<void> _loadPreferences() async {
    if (_preferencesReading) return;
    _preferencesReading = true;
    final reload = _preferencesFailed;
    if (!_preferencesLoading) {
      setState(() { _preferencesLoading = true; _preferencesFailed = false; });
    }
    try {
      // Wait for both reads before presenting any account. Neither failure
      // clears storage or authorizes silently replacing a saved preference.
      if (reload) await (await SharedPreferences.getInstance()).reload();
      await Future.wait([prefs.load(), glassSettings.load()]);
      if (mounted) setState(() { _preferencesLoading = false; _preferencesFailed = false; });
    } catch (_) {
      if (mounted) setState(() { _preferencesLoading = false; _preferencesFailed = true; });
    } finally {
      _preferencesReading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => MaterialApp(
        title: 'Sanjaal',
        navigatorObservers: [mediaRoutes],
        navigatorKey: _navigatorKey,
        builder: (context, child) => ActiveCallHost(key: _activeCallKey, session: session,
            navigatorKey: _navigatorKey, child: NativeCallRoot(session: session, hostKey: _activeCallKey,
              child: MessageOpenHost(session: session, navigatorKey: _navigatorKey, source: _messageOpens, child: child ?? const SizedBox.shrink()))),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, fontFamily: widget.fontFamily),
        darkTheme: buildTheme(Brightness.dark, fontFamily: widget.fontFamily),
        themeMode: prefs.mode,
        home: KeyedSubtree(
          // Locale changes must not discard a signed-out member's form.
          // Signed-in routes retain their existing full locale rebuild.
          key: ValueKey(session.user == null ? 'signed-out' : prefs.lang),
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              if (_preferencesFailed) {
                return Scaffold(body: SafeArea(child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal:24, vertical:56),
                  child: EmptyState(icon:Ph.error_outline,
                    title:t_('Device preferences could not be loaded.'),
                    hint:t_('Your saved settings were not reset. Try again. If this continues, close and reopen Sanjaal.'),
                    action:OutlinedButton(onPressed:_preferencesLoading ? null : _loadPreferences, child:Text(t_('Try again')))),
                )));
              }
              if (_preferencesLoading || session.loading || !prefs.ready || session.recoveringAccount || (session.authenticating && session.user!=null)) {
                return const Scaffold(body: Center(child: Logo(size: 96)));
              }
              if (session.restoreError != null) {
                return RestoreSessionPage(session: session);
              }
              if (session.user == null) {
                return prefs.seenOnboarding
                    ? AuthPage(session: session, initialRegister: _createAccount)
                    : OnboardingPage(onContinue: (create) {
                        setState(() => _createAccount = create);
                        prefs.finishOnboarding();
                      });
              }
              if (session.profileSetupPending) {
                return ProfileSetupPage(
                  key: ValueKey('profile-setup-${session.accountViewGeneration}'),
                  session: session,
                );
              }
              return HomeShell(key: ValueKey(session.accountViewGeneration), session: session);
            },
          ),
        ),
      ),
    );
  }
}

/// A recoverable cold start must not look like a deliberate sign-out.
class RestoreSessionPage extends StatelessWidget {
  const RestoreSessionPage({super.key, required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t_('Sanjaal'))),
    body: SafeArea(child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
      child: EmptyState(
        icon: Ph.cloud_off,
        title: t_('Could not restore your sign-in. Try again.'),
        hint: t_('Your account has not been opened. Check your connection and try again.'),
        action: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:16,vertical:12)),
          onPressed: session.loading || session.recoveringAccount ? null : session.accountViewNeedsRefresh ? session.recoverAccountView : session.restore,
          icon: const PhIcon('arrow-clockwise'),
          label: Text(t_('Try again')),
        ),
      ),
    ))),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session});
  final Session session;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;
  int unread = 0;
  bool _navCompact = false;
  Timer? _navIdle;
  void _touchNav() {
    _navIdle?.cancel();
    if (_navCompact) setState(() => _navCompact = false);
    _navIdle = Timer(const Duration(seconds: 3), () { if (mounted && tab == 1) setState(() => _navCompact = true); });
  }
  int _contentRevision = 0;
  int _reelRevision = 0;
  int _storyRevision = 0;
  bool _foreground = true;
  int _foregroundRevision = 0;
  final _visited = <int>{0};
  Timer? _poll;
  Timer? _ring;
  bool _ringing = false;
  String? _lastCall;
  final feedKey = GlobalKey<FeedListState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.session.prefetchHome();
    _initialUnread();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshUnread());
    _ring = Timer.periodic(const Duration(seconds: 5), (_) => _checkIncoming());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground || !mounted) return;
    _foregroundRevision++;
    setState(() => _foreground = foreground);
    if (foreground) {
      _refreshUnread();
      _checkIncoming();
    }
  }

  void _showTab(int index) {
    setState(() { tab = index; _visited.add(index); });
    _touchNav();
    // Only a tab tap is throttled. Foreground return, the 30s poll and Retry still refresh at once.
    if (DateTime.now().difference(_unreadAt) > const Duration(seconds: 20)) _refreshUnread();
  }

  Future<void> _checkIncoming() async {
    if (_ringing || !mounted || !_foreground || ActiveCallHost.busy(context)) return;
    final session = widget.session;
    final owner = session.user?['public_id'];
    if (owner == null) return;
    final generation = session.generation;
    final foregroundRevision = _foregroundRevision;
    _ringing = true;
    try {
      final value = await session.call('GET', '/calls/incoming');
      // A response from before backgrounding or a replacement login cannot
      // start ringing on the current screen, even after foreground return.
      if (!mounted || !_foreground || foregroundRevision != _foregroundRevision ||
          !identical(widget.session, session) || session.generation != generation ||
          session.user?['public_id'] != owner || ActiveCallHost.busy(context)) {
        return;
      }
      if (value is! Map || value['data'] is! List) return;
      final list = value['data'] as List;
      if (list.isEmpty || list.first is! Map) return;
      final call = Map<String, dynamic>.from(list.first as Map);
      final id = call['public_id'];
      final conversation = call['conversation_id'];
      final deadline = call['ring_expires_at'] is String
          ? DateTime.tryParse(call['ring_expires_at'] as String) : null;
      if (id is! String || id.isEmpty || conversation is! String || conversation.isEmpty ||
          !const ['voice', 'video'].contains(call['kind']) || call['status'] != 'ringing' ||
          deadline == null || !deadline.isAfter(DateTime.now()) || id == _lastCall) {
        return;
      }
      _lastCall = id;
      HapticFeedback.heavyImpact();
      await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true,
          builder: (_) => IncomingCallPage(session: session, call: call)));
    } catch (_) {
      // The next foreground poll reconciles transient or malformed responses.
    } finally {
      _ringing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navIdle?.cancel();
    _poll?.cancel();
    _ring?.cancel();
    super.dispose();
  }

  Future<void> _initialUnread() async {
    if (!widget.session.homePending) return _refreshUnread();
    final n = (await widget.session.takeHome('unread_messages') as num?)?.toInt();
    if (n == null) return _refreshUnread();
    _unreadAt = DateTime.now();
    if (mounted && n != unread) setState(() => unread = n);
  }

  bool _unreadInFlight = false;
  DateTime _unreadAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _refreshUnread() async {
    if (!_foreground || _unreadInFlight) return;
    _unreadInFlight = true;
    _unreadAt = DateTime.now();
    try {
      final j = await widget.session.call('GET', '/notifications/summary') as Map<String, dynamic>;
      final n = (j['unread_messages'] as num?)?.toInt() ?? 0;
      if (mounted && n != unread) setState(() => unread = n);
    } catch (_) {
    } finally {
      _unreadInFlight = false;
    }
  }

  Future<void> _compose() async {
    final what = await showReviewedGlassSheet<String>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => const CreateSheet());
    if (what == null || !mounted) return;
    await _create(what);
  }

  Future<void> _create(String what) async {
    if (what == 'story') {
      if (await addStory(context, widget.session) && mounted) {
        setState(() { _storyRevision++; tab = 0; _visited.add(0); });
        showInfo(context, 'Your story is up. It shows in the row at the top of Home.');
      }
      return;
    }
    final p = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ComposePage(session: widget.session, startWithVideo: what == 'reel', backgroundUpload: true)));
    if (p != null && mounted) {
      showInfo(context, p['kind'] == 'reel' ? 'Your reel is live in the Reels tab.' : 'Your post is up.');
      if (p['kind'] != 'reel') {
        feedKey.currentState?.insertFirst(p);
      }
      setState(() {
        _contentRevision++;
        if (p['kind'] == 'reel') _reelRevision++;
        tab = p['kind'] == 'reel' ? 1 : 0;
        _visited.add(tab);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = [
      FeedPage(session: s, onCompose: _compose, forYouKey: feedKey, storyRevision: _storyRevision),
      ReelsPage(session: s, active: tab == 1 && _foreground, contentRevision: _reelRevision, onCreate: () => _create('reel'), bottomInset: GlassNavBar.contentInset(context)),
      ChatsPage(session: s, active: tab == 2 && _foreground),
      WalletPage(session: s),
      MePage(session: s, onCompose: _compose, contentRevision: _contentRevision),
    ];
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([s, UploadCenter.of(s)]),
        builder: (context, child) {
          final uploads = UploadCenter.of(s);
          final headerVisible = s.offline || uploads.busy || uploads.restoring || uploads.error != null || uploads.result != null;
          // A visible status strip owns the top inset for the whole stack.
          // Without a strip, destinations retain their existing inset policy,
          // including full-bleed Reels. Keep one subtree across transitions.
          return SafeArea(top: headerVisible, bottom: false, left: false, right: false, child: child!);
        },
        child: Column(children: [
        UploadStrip(center: UploadCenter.of(s), destination: tab),
        ListenableBuilder(
          listenable: s,
          builder: (context, _) => s.offline ? _OfflineBanner(onRetry: _refreshUnread) : const SizedBox.shrink(),
        ),
        Expanded(child: NotificationListener<UserScrollNotification>(
          onNotification: (event) {
            if (event.direction != ScrollDirection.idle && !_navCompact) {
              _navIdle?.cancel(); setState(() => _navCompact = true);
            }
            return false;
          }, child: IndexedStack(index: tab, children: [
          for (var i = 0; i < pages.length; i++)
            _visited.contains(i) ? TickerMode(enabled: i == tab && _foreground, child: pages[i]) : const SizedBox.shrink(),
        ]))),
      ])),
      extendBody: true,
      bottomNavigationBar: GlassNavBar(
        immersive: tab == 1,
        index: tab,
        onSearch: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => discoveryEntry(s))),
        compact: _navCompact,
        onTouch: _touchNav,
        onSelected: _showTab,
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
