import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_manager/photo_manager.dart' as photos;

import 'capture_page.dart';
import 'ph.dart';
import 'ui.dart';

enum CreatorKind { post, story, reel }

class LibraryAlbum {
  const LibraryAlbum(this.id, this.name, {this.recent = false});
  final bool recent;
  final String id, name;
}

class LibraryAsset {
  const LibraryAsset(this.id, {required this.video, this.seconds = 0});
  final String id;
  final bool video;
  final int seconds;
}

enum LibraryAccess { full, limited, denied }

abstract class MediaLibrary {
  Future<LibraryAccess> request();
  Future<LibraryAccess> status();
  Future<List<LibraryAlbum>> albums({
    required bool videos,
    required bool images,
  });
  Future<List<LibraryAsset>> page(String album, int index);
  Future<Uint8List?> thumbnail(LibraryAsset asset);
  Future<XFile?> file(LibraryAsset asset);
  Future<void> manage();
  Future<void> settings();
}

class NativeMediaLibrary implements MediaLibrary {
  NativeMediaLibrary(this.kind);
  final CreatorKind kind;
  final paths = <String, photos.AssetPathEntity>{};
  final assets = <String, photos.AssetEntity>{};
  photos.RequestType get type => kind == CreatorKind.post
      ? photos.RequestType.image
      : kind == CreatorKind.reel
      ? photos.RequestType.video
      : photos.RequestType.common;
  @override
  Future<LibraryAccess> request() async {
    final status = await photos.PhotoManager.requestPermissionExtend(
      requestOption: photos.PermissionRequestOption(
        androidPermission: photos.AndroidPermission(
          type: type,
          mediaLocation: false,
        ),
      ),
    );
    return status == photos.PermissionState.limited
        ? LibraryAccess.limited
        : status.hasAccess
        ? LibraryAccess.full
        : LibraryAccess.denied;
  }

  @override
  Future<LibraryAccess> status() async {
    final value = await photos.PhotoManager.getPermissionState(
      requestOption: photos.PermissionRequestOption(
        androidPermission: photos.AndroidPermission(
          type: type,
          mediaLocation: false,
        ),
      ),
    );
    return value == photos.PermissionState.limited
        ? LibraryAccess.limited
        : value.hasAccess
        ? LibraryAccess.full
        : LibraryAccess.denied;
  }

  @override
  Future<List<LibraryAlbum>> albums({
    required bool videos,
    required bool images,
  }) async {
    final result = await photos.PhotoManager.getAssetPathList(
      type: videos && images
          ? photos.RequestType.common
          : videos
          ? photos.RequestType.video
          : photos.RequestType.image,
      filterOption: photos.FilterOptionGroup(
        includeHiddenAssets: false,
        orders: [
          const photos.OrderOption(
            type: photos.OrderOptionType.createDate,
            asc: false,
          ),
        ],
      ),
    );
    for (final item in result) {
      paths[item.id] = item;
    }
    return result
        .map(
          (p) => LibraryAlbum(
            p.id,
            p.isAll ? t_('Recents') : p.name,
            recent: p.isAll,
          ),
        )
        .toList();
  }

  @override
  Future<List<LibraryAsset>> page(String album, int index) async {
    final rows = await paths[album]!.getAssetListPaged(page: index, size: 24);
    for (final item in rows) {
      assets[item.id] = item;
    }
    return rows
        .map(
          (p) => LibraryAsset(
            p.id,
            video: p.type == photos.AssetType.video,
            seconds: p.duration,
          ),
        )
        .toList();
  }

  @override
  Future<Uint8List?> thumbnail(LibraryAsset asset) =>
      assets[asset.id]!.thumbnailDataWithSize(
        const photos.ThumbnailSize.square(320),
        quality: 75,
      );
  @override
  Future<XFile?> file(LibraryAsset asset) async {
    // Never request original EXIF/location or hidden albums. Only the selected
    // asset is materialized. Browsing never starts a server request or upload.
    final source = await assets[asset.id]!.file;
    if (source == null) return null;
    if (await source.length() > 25 * 1024 * 1024)
      throw StateError(t_('That file is over 25 MB. Choose a smaller one.'));
    if (asset.video) return XFile(source.path);
    // A bounded render removes metadata and normalizes HEIC/other supported
    // system image formats to the PNG format accepted by our upload API.
    final bytes = await source.readAsBytes();
    return normalizeLibraryPhoto(bytes);
  }

  @override
  Future<void> manage() => photos.PhotoManager.presentLimited(type: type);
  @override
  Future<void> settings() => photos.PhotoManager.openSetting();
}

/// Normalize a selected photo with the same codec and multipart identity on IO/web.
Future<XFile?> normalizeLibraryPhoto(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 1280,
    allowUpscaling: false,
  );
  final frame = await codec.getNextFrame();
  final encoded = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  if (encoded == null) return null;
  return XFile.fromData(
    encoded.buffer.asUint8List(),
    // On Android/iOS cross_file derives name from path and ignores name.
    // Bytes stay in memory; this is a logical filename, not a disk write.
    path: 'selected-photo.png',
    name: 'selected-photo.png',
    mimeType: 'image/png',
  );
}

Future<List<CreatorMedia>?> chooseCreatorMedia(
  BuildContext context,
  CreatorKind kind,
) => Navigator.of(context).push<List<CreatorMedia>>(
  MaterialPageRoute(builder: (_) => MediaLibraryPage(kind: kind)),
);

/// The screenshot-led Recents grid uses device media only after permission.
/// Native picker fallback stays available when broad library access is denied.
class MediaLibraryPage extends StatefulWidget {
  const MediaLibraryPage({
    super.key,
    required this.kind,
    this.library,
    this.captureBuilder,
  });
  final CreatorKind kind;
  final MediaLibrary? library;
  final Widget Function(bool startVideo, int maxSeconds)? captureBuilder;
  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage>
    with WidgetsBindingObserver {
  late final library = widget.library ?? NativeMediaLibrary(widget.kind);
  final scroll = ScrollController();
  final items = <LibraryAsset>[];
  final selected = <LibraryAsset>[];
  List<LibraryAlbum> albums = [];
  LibraryAlbum? album;
  LibraryAccess? access;
  bool needsAuthorize = true;
  bool launchingPicker = false;
  bool get selectionBusy=>resolving || launchingPicker;
  bool loading = false,
      resolving = false,
      more = true,
      multiple = false,
      waitingSettings = false;
  String? error;
  List<LibraryAsset>? retrySelection;
  int page = 0, epoch = 0;
  late bool videos = widget.kind != CreatorKind.post;
  late bool images = widget.kind != CreatorKind.reel;
  int get maxSeconds => widget.kind == CreatorKind.story ? 20 : 60;
  int get maxFiles => widget.kind == CreatorKind.post ? 4 : 1;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(() {
      if (scroll.hasClients && scroll.position.extentAfter < 500) load();
    });
    authorize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (waitingSettings) {
      waitingSettings = false;
      authorize(ask: false);
    } else if (access != null &&
        !loading &&
        !selectionBusy &&
        ModalRoute.of(context)?.isCurrent == true) {
      authorize(ask: false);
    }
  }

  Future<void> authorize({bool ask = true}) async {
    final request = ++epoch;
    setState(() {
      loading = true;
      error = null;
      retrySelection = null;
    });
    try {
      final permission = await (ask ? library.request() : library.status());
      if (!mounted || request != epoch) return;
      access = permission;
      needsAuthorize = false;
      if (permission == LibraryAccess.denied) {
        selected.clear();
        setState(() {
          loading = false;
          items.clear();
          albums = [];
          album = null;
        });
        return;
      }
      final result = await library.albums(videos: videos, images: images);
      if (!mounted || request != epoch) return;
      setState(() {
        albums = result;
        album = result.isEmpty ? null : result.first;
        loading = false;
        items.clear();
        page = 0;
        more = true;
      });
      if (album != null) load();
    } catch (_) {
      if (mounted && request == epoch)
        setState(() {
          error = t_('Your media could not be loaded.');
          needsAuthorize = true;
          loading = false;
        });
    }
  }

  Future<void> load({bool reset = false}) async {
    if (album == null || selectionBusy || (!reset && (loading || !more))) return;
    final request = reset ? ++epoch : epoch;
    final current = album!;
    if (reset) {
      items.clear();
      page = 0;
      more = true;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await library.page(current.id, page);
      if (!mounted || request != epoch) return;
      final known = items.map((a) => a.id).toSet();
      setState(() {
        items.addAll(result.where((a) => known.add(a.id)));
        page++;
        more = result.length == 24;
      });
    } catch (_) {
      if (mounted && request == epoch)
        setState(() => error = t_('Your media could not be loaded.'));
    } finally {
      if (mounted && request == epoch) setState(() => loading = false);
    }
  }

  Future<void> choose(LibraryAsset asset) async {
    if (selectionBusy) return;
    if (asset.video && asset.seconds > maxSeconds) {
      showInfo(
        context,
        '${t_('Choose a video up to')} $maxSeconds ${t_('seconds')}.',
      );
      return;
    }
    if (!multiple) {
      await resolve([asset]);
      return;
    }
    setState(() {
      final existing = selected.indexWhere((a) => a.id == asset.id);
      if (existing >= 0) {
        selected.removeAt(existing);
      } else if (selected.length < maxFiles) {
        selected.add(asset);
      }
    });
  }

  Future<void> resolve(List<LibraryAsset> chosen) async {
    if (selectionBusy || chosen.isEmpty) return;
    setState(() {
      resolving = true;
      error = null;
      retrySelection = null;
    });
    try {
      final result = <CreatorMedia>[];
      for (final asset in chosen) {
        final file = await library.file(asset);
        if (!mounted) return;
        if (file == null)
          throw StateError(
            t_(
              'That item is unavailable. Check your connection or choose another.',
            ),
          );
        if (await file.length() > 25 * 1024 * 1024)
          throw StateError(
            t_('That file is over 25 MB. Choose a smaller one.'),
          );
        result.add(CreatorMedia(file, isVideo: asset.video));
      }
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted)
        setState(() {
          retrySelection = List.of(chosen);
          error = e is StateError
              ? e.message.toString()
              : t_(
                  'That item is unavailable. Check your connection or choose another.',
                );
        });
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  Future<void> launch(Future<void> Function() action) async {
    if(selectionBusy) return;
    setState(()=>launchingPicker=true);
    try { await action(); }
    catch (_) { if(mounted) showInfo(context,t_('Camera or media picker could not be opened. Try again.')); }
    finally { if(mounted) setState(()=>launchingPicker=false); }
  }

  Future<void> capture()=>launch(_capture);
  Future<void> fallback()=>launch(_fallback);

  Future<void> _capture() async {
    if (resolving) return;
    final builder = widget.captureBuilder;
    final value = await Navigator.of(context).push<CreatorMedia>(
      MaterialPageRoute(
        builder: (_) =>
            builder?.call(widget.kind == CreatorKind.reel, maxSeconds) ??
            CapturePage(
              startVideo: widget.kind == CreatorKind.reel,
              maxSeconds: maxSeconds,
              allowPhoto: widget.kind != CreatorKind.reel,
              allowVideo: widget.kind != CreatorKind.post,
            ),
      ),
    );
    if (value != null && mounted) Navigator.pop(context, [value]);
  }

  Future<void> _fallback() async {
    if (resolving) return;
    bool video = widget.kind == CreatorKind.reel;
    if (widget.kind == CreatorKind.story) {
      final picked = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(t_('Choose a photo')),
                onTap: () => Navigator.pop(c, false),
              ),
              ListTile(
                title: Text(t_('Choose a video')),
                onTap: () => Navigator.pop(c, true),
              ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      video = picked;
    }
    final picker = ImagePicker();
    if (widget.kind == CreatorKind.post) {
      final files = await guardPick(
        context,
        () => picker.pickMultiImage(
          maxWidth: 1280,
          imageQuality: 78,
          limit: maxFiles,
        ),
      );
      if (files != null && files.isNotEmpty && mounted)
        Navigator.pop(
          context,
          files
              .take(maxFiles)
              .map((f) => CreatorMedia(f, isVideo: false))
              .toList(),
        );
    } else {
      final file = await guardPick(
        context,
        () => video
            ? picker.pickVideo(
                source: ImageSource.gallery,
                maxDuration: Duration(seconds: maxSeconds),
              )
            : picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 1280,
                imageQuality: 78,
              ),
      );
      if (file != null && mounted)
        Navigator.pop(context, [CreatorMedia(file, isVideo: video)]);
    }
  }

  Future<void> manage() async {
    if (selectionBusy || loading) return;
    try {
      await library.manage();
      if (mounted) authorize();
    } catch (_) {
      if (mounted)
        showInfo(context, t_('Choose more photos in your device settings.'));
    }
  }

  @override
  void dispose() {
    epoch++;
    WidgetsBinding.instance.removeObserver(this);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.kind == CreatorKind.story
        ? 'Add to story'
        : widget.kind == CreatorKind.reel
        ? 'Create a reel'
        : 'New post';
    return PopScope(
      canPop: true,
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          textButtonTheme: TextButtonThemeData(style:TextButton.styleFrom(foregroundColor:Colors.white,disabledForegroundColor:Colors.white38)),
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            secondary: Colors.white,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? 100
                : 56,
            leading: IconButton(
              tooltip: t_('Close'),
              onPressed: () => Navigator.pop(context),
              icon: const PhIcon('x'),
            ),
            title: Text(
              t_(title),
              maxLines: 3,
              style: const TextStyle(fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: t_('Photo permissions'),
                onPressed: selectionBusy
                    ? null
                    : () async {
                        waitingSettings = true;
                        try { await library.settings(); }
                        catch (_) {
                          waitingSettings=false;
                          if(context.mounted) showInfo(context,t_('Photo permissions could not be opened. Try again.'));
                        }
                      },
                icon: const PhIcon('gear'),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (loading || resolving) const LinearProgressIndicator(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: selectionBusy ? null : capture,
                              icon: const PhIcon('camera'),
                              label: Text(t_('Camera')),
                            ),
                            OutlinedButton.icon(
                              onPressed: selectionBusy ? null : fallback,
                              icon: const PhIcon('images'),
                              label: Text(t_('Device picker')),
                            ),
                            if (widget.kind == CreatorKind.story) ...[
                              FilterChip(
                                label: Text(t_('Photos')),
                                selected: images && !videos,
                                onSelected: selectionBusy
                                    ? null
                                    : (_) {
                                        images = true;
                                        videos = false;
                                        authorize();
                                      },
                              ),
                              FilterChip(
                                label: Text(t_('Videos')),
                                selected: videos && !images,
                                onSelected: selectionBusy
                                    ? null
                                    : (_) {
                                        images = false;
                                        videos = true;
                                        authorize();
                                      },
                              ),
                              if (!(images && videos))
                                ActionChip(
                                  label: Text(t_('All media')),
                                  onPressed: selectionBusy
                                      ? null
                                      : () {
                                          images = true;
                                          videos = true;
                                          authorize();
                                        },
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (access == LibraryAccess.limited)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                t_(
                                  'Only the photos and videos you allow are shown.',
                                ),
                              ),
                              TextButton(
                                onPressed: selectionBusy || loading ? null : manage,
                                child: Text(t_('Choose more')),
                              ),
                            ],
                          ),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text(
                                error!,
                                style: const TextStyle(color: Colors.white),
                              ),
                              TextButton(
                                onPressed: loading || selectionBusy
                                    ? null
                                    : () {
                                        if (retrySelection != null) {
                                          resolve(List.of(retrySelection!));
                                        } else if (needsAuthorize ||
                                            access == null) {
                                          authorize();
                                        } else {
                                          load();
                                        }
                                      },
                                child: Text(t_('Try again')),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: LayoutBuilder(
                          builder: (_, bounds) => Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: multiple
                                    ? MediaQuery.textScalerOf(context).scale(1)>1.3 ? bounds.maxWidth : 100
                                    : (bounds.maxWidth -
                                              (maxFiles > 1 ? 80 : 0))
                                          .clamp(80, bounds.maxWidth),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF202226),
                                    value: album?.id,
                                    hint: Text(
                                      t_('Recents'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontSize: 18,
                                        ),
                                    items: albums
                                        .map(
                                          (a) => DropdownMenuItem(
                                            value: a.id,
                                            child: Text(
                                              a.recent ? t_('Recents') : a.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: selectionBusy || loading
                                        ? null
                                        : (id) {
                                            album = albums.firstWhere(
                                              (a) => a.id == id,
                                            );
                                            load(reset: true);
                                          },
                                  ),
                                ),
                              ),
                              if (maxFiles > 1)
                                TextButton(
                                  onPressed: selectionBusy
                                      ? null
                                      : () => setState(() {
                                          multiple = !multiple;
                                          selected.clear();
                                        }),
                                  child: Text(
                                    t_(multiple ? 'Cancel' : 'Select'),
                                  ),
                                ),
                              if (multiple)
                                TextButton(
                                  onPressed: selectionBusy || selected.isEmpty
                                      ? null
                                      : () => resolve(List.of(selected)),
                                  child: Text(
                                    '${t_('Next')} (${selected.length}/$maxFiles)',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (access == LibraryAccess.denied)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t_(
                              'Choose photos with the device picker, or allow library access to see your Recents here.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: selectionBusy?null:fallback,
                            child: Text(t_('Device picker')),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                      childAspectRatio: widget.kind == CreatorKind.post
                          ? 1
                          : 9 / 16,
                    ),
                    delegate: SliverChildBuilderDelegate((_, i) {
                      if (i == 0)
                        return Material(
                          color: const Color(0xFF202124),
                          child: InkWell(
                            onTap: selectionBusy ? null : capture,
                            child: Center(
                              child: Semantics(
                                label: t_('Camera'),
                                child: const PhIcon(
                                  'camera-fill',
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                        );
                      final asset = items[i - 1];
                      final index = selected.indexWhere(
                        (a) => a.id == asset.id,
                      );
                      return _LibraryTile(
                        key: ValueKey(asset.id),
                        asset: asset,
                        library: library,
                        selected: index >= 0 ? index + 1 : null,
                        multiple: multiple,
                        onTap: selectionBusy ? null : () => choose(asset),
                      );
                    }, childCount: items.length + 1),
                  ),
                  if (items.isEmpty &&
                      !loading &&
                      error == null &&
                      access != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          t_(
                            'No media to show. Choose another album or allow more photos.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  if (more && !loading && items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: TextButton(
                        onPressed: selectionBusy ? null : load,
                        child: Text(t_('Load more')),
                      ),
                    ),
                  if (loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryTile extends StatefulWidget {
  const _LibraryTile({
    super.key,
    required this.asset,
    required this.library,
    required this.selected,
    required this.multiple,
    this.onTap,
  });
  final LibraryAsset asset;
  final MediaLibrary library;
  final int? selected;
  final bool multiple;
  final VoidCallback? onTap;
  @override
  State<_LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends State<_LibraryTile> {
  late final thumbnail = widget.library.thumbnail(widget.asset);
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${t_(widget.asset.video ? 'Video' : 'Photo')}${widget.asset.video ? ', ${widget.asset.seconds} ${t_('seconds')}' : ''}',
    selected: widget.selected != null,
    excludeSemantics: true,
    button: true,
    child: Material(
      color: const Color(0xFF202124),
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: thumbnail,
              builder: (_, value) => value.hasData
                  ? Image.memory(
                      value.data!,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    )
                  : const Center(child: PhIcon('image', color: Colors.white54)),
            ),
            if (widget.asset.video)
              Positioned(
                right: 6,
                bottom: 6,
                child: Text(
                  '${widget.asset.seconds ~/ 60}:${(widget.asset.seconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            if (widget.multiple)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected == null
                        ? Colors.black38
                        : Theme.of(context).colorScheme.primary,
                    border: Border.all(color: Colors.white),
                  ),
                  child: widget.selected == null
                      ? null
                      : Text(
                          '${widget.selected}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                        ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
