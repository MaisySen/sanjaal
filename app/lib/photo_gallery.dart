import 'package:material_ui/material_ui.dart';
import 'ph.dart';
import 'ui.dart' show t_;

typedef PhotoProvider = ImageProvider Function(String url);

/// One media treatment for feed, post detail and the full-screen viewer.
/// HTTP headers stay on every full-screen request, including retries.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery({super.key, required this.urls, this.headers, this.provider, this.initialIndex = 0, this.fullscreen = false});
  final List<String> urls;
  final Map<String, String>? headers;
  final PhotoProvider? provider;
  final int initialIndex;
  final bool fullscreen;
  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late final PageController pages;
  late int index;

  @override
  void initState() {
    super.initState();
    index = widget.urls.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.urls.length - 1);
    pages = PageController(initialPage: index);
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void open() => Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PhotoViewer(urls: widget.urls, headers: widget.headers, provider: widget.provider, initialIndex: index),
  ));

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox();
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        controller: pages,
        itemCount: widget.urls.length,
        onPageChanged: (value) => setState(() => index = value),
        itemBuilder: (_, i) {
          final photo = _Photo(url: widget.urls[i], headers: widget.headers, provider: widget.provider, contain: widget.fullscreen);
          return Semantics(
            label: '${t_('Photo')} ${i + 1} / ${widget.urls.length}',
            button: !widget.fullscreen,
            hint: widget.fullscreen ? null : t_('Open full screen'),
            child: widget.fullscreen
              ? InteractiveViewer(minScale: 1, maxScale: 4, child: Center(child: photo))
              : GestureDetector(onTap: open, child: photo),
          );
        },
      ),
      if (widget.urls.length > 1) Positioned(
        top: 12, right: 12,
        child: IgnorePointer(child: Semantics(liveRegion: true, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
          child: Text('${index + 1} / ${widget.urls.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ))),
      ),
    ]);
  }
}

class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.urls, this.headers, this.provider, this.initialIndex = 0});
  final List<String> urls;
  final Map<String, String>? headers;
  final PhotoProvider? provider;
  final int initialIndex;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, leading: IconButton(tooltip: MaterialLocalizations.of(context).closeButtonTooltip, onPressed: () => Navigator.of(context).maybePop(), icon: const PhIcon('x', color: Colors.white)), title: Text(t_('Photos'), style: const TextStyle(color: Colors.white))),
    body: SafeArea(top: false, child: PhotoGallery(urls: urls, headers: headers, provider: provider, initialIndex: initialIndex, fullscreen: true)),
  );
}

class _Photo extends StatefulWidget {
  const _Photo({required this.url, this.headers, this.provider, required this.contain});
  final String url;
  final Map<String, String>? headers;
  final PhotoProvider? provider;
  final bool contain;
  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  int attempt = 0;
  ImageProvider get image => widget.provider?.call(widget.url) ?? NetworkImage(widget.url, headers: widget.headers);
  Future<void> retry() async {
    await image.evict();
    if (mounted) setState(() => attempt++);
  }
  @override
  Widget build(BuildContext context) => Image(
    key: ValueKey(attempt), image: image,
    width: double.infinity, height: widget.contain ? null : double.infinity,
    fit: widget.contain ? BoxFit.contain : BoxFit.cover,
    loadingBuilder: (_, child, progress) => progress == null ? child : const ColoredBox(color: Color(0xFF171A20), child: Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2))),
    errorBuilder: (_, error, stack) => ColoredBox(color: const Color(0xFF171A20), child: Center(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const PhIcon('image', color: Colors.white70, size: 28),
        const SizedBox(height: 10),
        Text(t_('Photo could not load'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 8),
        TextButton(onPressed: retry, child: Text(t_('Try again'), style: const TextStyle(color: Colors.white, decoration: TextDecoration.underline))),
      ]),
    ))),
  );
}
