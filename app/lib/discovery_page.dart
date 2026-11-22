import 'package:material_ui/material_ui.dart';

import 'discovery_contract.dart';
import 'discovery_paging.dart';
import 'discovery_network_image.dart';
import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'ui.dart' show t_;

/// Discovery surface. The coordinated compatibility entry is capability-gated.
/// The caller supplies a session-owned pager backed by an eligible-content
/// provider. This widget does not fabricate content, moderation or topic chips.
class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
    super.key,
    required this.pager,
    required this.onOpen,
    required this.onSearch,
    this.imageProvider,
    this.allowReelsFilter = false,
  });
  final DiscoveryPaging<DiscoveryTile> pager;
  final ValueChanged<DiscoveryTile> onOpen;
  final VoidCallback onSearch;
  final ImageProvider Function(Uri)? imageProvider;
  final bool allowReelsFilter;
  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final scroll = ScrollController();
  DiscoveryImageScope _scope = DiscoveryImageScope();
  final _images = <Uri, ImageProvider>{};
  late int _cacheRevision;
  void _syncImages() {
    if (_cacheRevision == widget.pager.cacheRevision) return;
    _cacheRevision = widget.pager.cacheRevision;
    _clearImages();
  }

  void _clearImages() {
    _scope.retire();
    _scope = DiscoveryImageScope();
    for (final image in _images.values) {
      image.evict();
    }
    _images.clear();
  }

  ImageProvider _image(Uri url) => _images.putIfAbsent(
    url,
    () => ResizeImage(
      widget.imageProvider?.call(url) ?? DiscoveryNetworkImage(url, _scope),
      width: 480,
      height: 640,
      policy: ResizeImagePolicy.fit,
    ),
  );
  @override
  void initState() {
    super.initState();
    scroll.addListener(_nearEnd);
    _cacheRevision = widget.pager.cacheRevision;
    widget.pager.addListener(_syncImages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.pager.load();
    });
  }

  @override
  void didUpdateWidget(covariant DiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pager, widget.pager)) {
      oldWidget.pager.removeListener(_syncImages);
      _clearImages();
      _cacheRevision = widget.pager.cacheRevision;
      widget.pager.addListener(_syncImages);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.pager.load();
      });
    } else if (oldWidget.imageProvider != widget.imageProvider) {
      _clearImages();
    }
  }

  void _nearEnd() {
    if (scroll.hasClients && scroll.position.extentAfter < 400) {
      widget.pager.load();
    }
  }

  @override
  void dispose() {
    widget.pager.removeListener(_syncImages);
    _clearImages();
    _scope.retire();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _filter(String? kind) async {
    final future = widget.pager.reset(
      kind == null ? <String, String>{} : {'kind': kind},
    );
    if (scroll.hasClients) scroll.jumpTo(0);
    await future;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.pager,
    builder: (context, _) {
      final p = widget.pager;
      final items = p.items;
      if (p.retired) {
        return Scaffold(
          appBar: ReviewedAppBar(),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              t_(
                p.sourceUnavailable
                    ? 'Discovery is unavailable. Close this view and open Search again.'
                    : 'This screen belongs to another signed-in session. Close it and sign in again to continue.',
              ),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: ReviewedAppBar(
          title: Text(t_('Explore')),
          actions: [
            IconButton(
              tooltip: t_('Search'),
              onPressed: widget.onSearch,
              icon: const PhIcon('magnifying-glass'),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => p.reset(p.query, retain: true),
          child: CustomScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.allowReelsFilter)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          shape: const StadiumBorder(),
                          labelStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          selectedColor: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: .10),
                          showCheckmark: false,
                          label: Text(t_('All')),
                          selected: p.query['kind'] == null,
                          onSelected: (_) => _filter(null),
                        ),
                        ChoiceChip(
                          shape: const StadiumBorder(),
                          labelStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          selectedColor: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: .10),
                          showCheckmark: false,
                          label: Text(t_('Reels')),
                          selected: p.query['kind'] == 'reel',
                          onSelected: (_) => _filter('reel'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (items.isNotEmpty)
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    childAspectRatio: .75,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final item = items[i];
                    return Semantics(
                      button: true,
                      label: item.caption.isEmpty
                          ? t_(item.preview.video ? 'Video' : 'Post')
                          : item.caption,
                      child: InkWell(
                        onTap: () => widget.onOpen(item),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image(
                              image: _image(item.preview.url),
                              fit: BoxFit.cover,
                              errorBuilder: (_, e, s) => ColoredBox(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                                child: Center(
                                  child: PhIcon(
                                    item.preview.video
                                        ? 'play-circle'
                                        : 'image',
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                            if (item.preview.video)
                              const Positioned(
                                top: 8,
                                right: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: PhIcon(
                                      'play-circle',
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: items.length),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    children: [
                      if (p.loading) const CircularProgressIndicator(),
                      if (!p.loading && p.error != null) ...[
                        Text(t_('Could not load this.')),
                        TextButton(
                          onPressed: p.load,
                          child: Text(t_('Try again')),
                        ),
                      ],
                      if (!p.loading && p.error == null && items.isEmpty)
                        Text(t_('No posts yet')),
                      if (!p.loading &&
                          p.error == null &&
                          !p.exhausted &&
                          !p.atLimit)
                        TextButton(
                          onPressed: p.load,
                          child: Text(t_('Load more')),
                        ),
                      if (p.atLimit)
                        TextButton(
                          onPressed: () => p.reset(p.query, retain: true),
                          child: Text(t_('Refresh')),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
