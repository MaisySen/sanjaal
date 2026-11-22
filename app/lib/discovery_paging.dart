import 'package:flutter/foundation.dart';

import 'api.dart';

/// Client paging primitive for the capability-gated Discovery candidate. Its
/// provider must enforce the separately unresolved content eligibility policy;
/// accepting a page here is not moderation approval.
class DiscoveryPageData<T> {
  DiscoveryPageData({
    required Iterable<T> items,
    required this.nextCursor,
    required this.version,
  }) : items = List.unmodifiable(items);
  final List<T> items;
  final String? nextCursor;
  final String version;
}

typedef DiscoveryPageReader<T> = Future<DiscoveryPageData<T>> Function(
  Map<String, String> query,
  String? cursor,
);

class DiscoveryPaging<T> extends ChangeNotifier {
  DiscoveryPaging({
    required this.read,
    required this.keyOf,
    required this.ownerActive,
    required this.maxItems,
    required this.maxPageSize,
    this.sourceAvailable,
  }) {
    if (maxItems < 1 || maxPageSize < 1 || maxPageSize > maxItems) {
      throw ArgumentError('Invalid Discovery bounds');
    }
  }
  factory DiscoveryPaging.forSession({
    required Session Function() currentSession,
    required DiscoveryPageReader<T> read,
    required String Function(T) keyOf,
    required int maxItems,
    required int maxPageSize,
    bool Function()? sourceAvailable,
  }) {
    final source = currentSession();
    final owner = source.user?['public_id'];
    final generation = source.generation;
    final pager = DiscoveryPaging<T>(
      read: read,
      keyOf: keyOf,
      ownerActive: () =>
          identical(currentSession(), source) &&
          owner != null &&
          source.user?['public_id'] == owner &&
          source.generation == generation,
      sourceAvailable: sourceAvailable,
      maxItems: maxItems,
      maxPageSize: maxPageSize,
    );
    source.addListener(pager.checkOwner);
    pager._detachOwner = () => source.removeListener(pager.checkOwner);
    return pager;
  }
  VoidCallback? _detachOwner;
  final DiscoveryPageReader<T> read;
  final String Function(T) keyOf;
  final bool Function() ownerActive;
  final bool Function()? sourceAvailable;
  final int maxItems, maxPageSize;
  List<T> _items = [];
  Map<String, String> _query = const {};
  final Set<String> _cursors = {};
  String? _cursor, _version;
  Future<void>? _flight;
  int _epoch = 0;
  int _cacheRevision = 0;
  int get cacheRevision => _cacheRevision;
  bool _retired = false, _disposed = false, _exhausted = false, _refresh = true;
  bool _sourceUnavailable = false;
  bool get sourceUnavailable => _sourceUnavailable;
  Object? error;
  List<T> get items => List.unmodifiable(_items);
  Map<String, String> get query => Map.unmodifiable(_query);
  bool get loading => _flight != null;
  bool get exhausted => _exhausted;
  bool get atLimit => _items.length >= maxItems && !_exhausted;
  bool get retired => _retired;

  bool _active() {
    if (_disposed || _retired) return false;
    final owner = ownerActive();
    final available = sourceAvailable?.call() ?? true;
    if (owner && available) return true;
    _sourceUnavailable = owner && !available;
    _retired = true;
    ++_cacheRevision;
    ++_epoch;
    _items = [];
    _query = const {};
    _cursor = null;
    _version = null;
    _cursors.clear();
    error = null;
    return false;
  }

  /// Call synchronously when identity changes, not only on the next response.
  void checkOwner() {
    final wasRetired = _retired;
    _active();
    if (!_disposed && !wasRetired && _retired) notifyListeners();
  }

  /// A covered, still-fresh view may keep its scroll/cache, but an in-flight
  /// metadata response must not publish into that covered result generation.
  void pausePending() {
    if (!_active()) return;
    ++_epoch;
    error = null;
    notifyListeners();
  }

  /// Withdraw cached metadata immediately without starting IO. Epoch retirement
  /// prevents an already-running response from restoring withdrawn previews.
  void invalidate() {
    if (!_active()) return;
    ++_cacheRevision;
    ++_epoch;
    _items = [];
    _refresh = true;
    _exhausted = false;
    _cursor = null;
    _version = null;
    _cursors.clear();
    error = null;
    notifyListeners();
  }

  /// A filter change clears the prior filter's content. A refresh preserves its
  /// usable content until a complete replacement succeeds. Neither overlaps IO.
  Future<void> reset(
    Map<String, String> nextQuery, {
    bool retain = false,
  }) async {
    if (!_active()) return;
    if (retain && !mapEquals(nextQuery, _query)) {
      throw ArgumentError('A different filter cannot retain old content');
    }
    final epoch = ++_epoch;
    _query = Map.unmodifiable(nextQuery);
    if (!retain) {
      ++_cacheRevision;
      _items = [];
    }
    _refresh = true;
    _exhausted = false;
    _cursor = null;
    _version = null;
    _cursors.clear();
    error = null;
    notifyListeners();
    final pending = _flight;
    if (pending != null) await pending;
    if (_active() && epoch == _epoch) await load();
  }

  Future<void> load() async {
    if (!_active() || loading || _exhausted || (atLimit && !_refresh)) return;
    final epoch = _epoch;
    final cursor = _refresh ? null : _cursor;
    final query = Map<String, String>.unmodifiable(_query);
    final flight = _load(epoch, query, cursor);
    _flight = flight;
    notifyListeners();
    await flight;
  }

  Future<void> _load(
    int epoch,
    Map<String, String> query,
    String? cursor,
  ) async {
    try {
      final page = await Future<DiscoveryPageData<T>>.sync(
        () => read(query, cursor),
      );
      if (!_active() || epoch != _epoch) return;
      if (page.version.trim().isEmpty ||
          page.items.length > maxPageSize ||
          (cursor != null && _version != page.version) ||
          (page.nextCursor != null &&
              (page.nextCursor!.isEmpty ||
                  page.nextCursor == cursor ||
                  _cursors.contains(page.nextCursor)))) {
        throw const FormatException('Invalid or inconsistent Discovery page');
      }
      final next = _refresh ? <T>[] : List<T>.of(_items);
      final ids = next.map(keyOf).toSet();
      for (final item in page.items) {
        final id = keyOf(item);
        if (id.trim().isEmpty) {
          throw const FormatException('Missing Discovery identity');
        }
        if (ids.add(id) && next.length < maxItems) next.add(item);
      }
      if (_refresh) ++_cacheRevision;
      _items = next;
      _cursor = page.nextCursor;
      _version = page.version;
      if (cursor != null) _cursors.add(cursor);
      _exhausted = _cursor == null;
      _refresh = false;
      error = null;
    } catch (e) {
      if (_active() && epoch == _epoch) error = e;
    } finally {
      _flight = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _detachOwner?.call();
    ++_epoch;
    _items = [];
    _query = const {};
    super.dispose();
  }
}
