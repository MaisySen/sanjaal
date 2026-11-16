import 'package:material_ui/material_ui.dart';

/// Shared by media surfaces and the app navigator. A covered route, inactive tab
/// or backgrounded app must not keep playing audio behind the visible screen.
final mediaRoutes = RouteObserver<ModalRoute<dynamic>>();

mixin MediaVisibility<T extends StatefulWidget> on State<T> implements RouteAware {
  late final AppLifecycleListener _lifecycle;
  ModalRoute<dynamic>? _route;
  bool _foreground = true;
  bool _routeVisible = true;
  bool _tickerVisible = true;
  bool get mediaVisible => mounted && _foreground && _routeVisible && _tickerVisible;

  void mediaVisibilityChanged(bool visible);

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      final was = mediaVisible;
      _foreground = state == AppLifecycleState.resumed;
      if (was != mediaVisible) mediaVisibilityChanged(mediaVisible);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final was = mediaVisible;
    _tickerVisible = TickerMode.of(context);
    final route = ModalRoute.of(context);
    if (route != _route) {
      mediaRoutes.unsubscribe(this);
      _route = route;
      if (route != null) mediaRoutes.subscribe(this, route);
    }
    if (was != mediaVisible) mediaVisibilityChanged(mediaVisible);
  }

  void _covered(bool covered) {
    final was = mediaVisible;
    _routeVisible = !covered;
    if (was != mediaVisible) mediaVisibilityChanged(mediaVisible);
  }

  @override
  void didPushNext() => _covered(true);
  @override
  void didPopNext() => _covered(false);
  @override
  void didPush() => _covered(false);
  @override
  void didPop() => _covered(true);

  @override
  void dispose() {
    mediaRoutes.unsubscribe(this);
    _lifecycle.dispose();
    super.dispose();
  }
}
