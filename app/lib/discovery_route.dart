import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'discovery_contract.dart';
import 'discovery_page.dart';
import 'discovery_paging.dart';
import 'post_page.dart';
import 'media_visibility.dart';
import 'search_page.dart';

/// Session-owned route host with actual Search/Post navigation. It requires a
/// supplied eligible-content provider. The compatibility entry registers it only
/// for an explicit server v1 capability, not for older or disabled servers.
class DiscoveryRoute extends StatefulWidget {
  const DiscoveryRoute({
    super.key,
    required this.session,
    required this.read,
    this.allowReelsFilter = false,
    this.imageProvider,
    this.sourceAvailable,
    this.freshness = const Duration(minutes: 1),
  });
  final Session session;

  /// Provisional local freshness ceiling, not remote push invalidation.
  final Duration freshness;
  final bool Function()? sourceAvailable;
  final DiscoveryPageReader<DiscoveryTile> read;
  final bool allowReelsFilter;
  final ImageProvider Function(Uri)? imageProvider;
  @override
  State<DiscoveryRoute> createState() => _DiscoveryRouteState();
}

class _DiscoveryRouteState extends State<DiscoveryRoute>
    with MediaVisibility<DiscoveryRoute> {
  Timer? _expiry;
  int _readVersion = 0, _visibilityVersion = 0, _freshnessVersion = 0;
  bool _visible = true, _expired = true, _backgroundCleared = false;
  late final AppLifecycleListener _backgroundGuard;
  @override
  void initState() {
    super.initState();
    _visible = mediaVisible;
    _backgroundGuard = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          _backgroundCleared = false;
          return;
        }
        if (_backgroundCleared) return;
        _backgroundCleared = true;
        ++_readVersion;
        _expired = true;
        _expiry?.cancel();
        Future.microtask(() {
          if (mounted && !pager.retired) pager.invalidate();
        });
      },
    );
  }

  Future<DiscoveryPageData<DiscoveryTile>> _read(
    Map<String, String> query,
    String? cursor,
  ) async {
    if (!_visible) throw StateError('Discovery is not visible.');
    if (widget.freshness < const Duration(seconds: 5) ||
        widget.freshness > const Duration(minutes: 5)) {
      throw StateError('Invalid Discovery freshness bounds.');
    }
    final version = cursor == null ? ++_readVersion : _readVersion;
    final clock = Stopwatch()..start();
    final result = await widget.read(query, cursor);
    if (clock.elapsed >= widget.freshness) {
      throw StateError('Discovery response expired before display.');
    }
    if (mounted &&
        _visible &&
        version == _readVersion &&
        !pager.retired &&
        cursor == null) {
      final remaining = widget.freshness - clock.elapsed;
      _expiry?.cancel();
      final freshness = ++_freshnessVersion;
      _expired = false;
      _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
        if (!mounted || freshness != _freshnessVersion || pager.retired) {
          return;
        }
        // Clear before revalidation. Never retain a remotely withdrawn item
        // through a failed refresh, and never poll covered/background views.
        _expired = true;
        if (_visible) {
          pager.reset(pager.query);
        } else {
          pager.invalidate();
        }
      });
    }
    return result;
  }

  @override
  void mediaVisibilityChanged(bool visible) => _visibility(visible);
  void _visibility(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    ++_readVersion;
    final background =
        WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    if (background) {
      _expiry?.cancel();
      _expired = true;
    }
    final change = ++_visibilityVersion;
    // Route/TickerMode notifications can happen during a build.
    Future.microtask(() {
      if (!mounted || change != _visibilityVersion || pager.retired) return;
      if (visible) {
        if (_expired || pager.items.isEmpty) pager.reset(pager.query);
      } else if (background) {
        pager.invalidate();
      } else {
        pager.pausePending();
      }
    });
  }

  Future<void> _open(WidgetBuilder builder) async {
    _visibility(false);
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
    if (mounted && mediaVisible) _visibility(true);
  }

  late final pager = DiscoveryPaging<DiscoveryTile>.forSession(
    currentSession: () => widget.session,
    sourceAvailable: () => widget.sourceAvailable?.call() ?? true,
    read: _read,
    keyOf: (tile) => tile.id,
    maxItems: 90,
    maxPageSize: 15,
  );
  @override
  void didUpdateWidget(covariant DiscoveryRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    pager.checkOwner();
  }

  @override
  void dispose() {
    ++_readVersion;
    ++_visibilityVersion;
    _backgroundGuard.dispose();
    _expiry?.cancel();
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DiscoveryPage(
    pager: pager,
    imageProvider: widget.imageProvider,
    allowReelsFilter: widget.allowReelsFilter,
    onSearch: () {
      pager.checkOwner();
      if (!pager.retired) {
        _open((_) => SearchPage(session: widget.session));
      }
    },
    onOpen: (tile) {
      pager.checkOwner();
      if (!pager.retired) {
        _open(
          (_) => PostPage(
            session: widget.session,
            postId: tile.id,
            onVisibilityChanged: () {
              pager.checkOwner();
              if (!pager.retired) {
                if (_visible) {
                  pager.reset(pager.query);
                } else {
                  pager.invalidate();
                }
              }
            },
          ),
        );
      }
    },
  );
}
