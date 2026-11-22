import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart' as camera;
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' as photos;
import 'package:material_ui/material_ui.dart';

import 'ph.dart';
import 'media_visibility.dart' show mediaRoutes;
import 'ui.dart';

class CreatorMedia {
  const CreatorMedia(this.file, {required this.isVideo});
  final XFile file;
  final bool isVideo;
}

/// A small boundary for native capture. Fixture devices never stand in for
/// hardware proof; production always uses the real camera plugin below.
abstract class CaptureDevice {
  bool get canSwitch;
  Future<void> initialize();
  Widget preview();
  Future<XFile> photo();
  Future<void> start();
  Future<XFile> stop();
  Future<void> flash(bool enabled);
  Future<double> zoom(double value);
  Future<void> dispose();
}

class NativeCaptureDevice implements CaptureDevice {
  NativeCaptureDevice({required this.video, required this.front});
  final bool video, front;
  camera.CameraController? controller;
  bool closed = false;
  bool switchable = false;
  @override
  bool get canSwitch => switchable;
  @override
  Future<void> initialize() async {
    final devices = await camera.availableCameras();
    if (closed) return;
    switchable =
        devices.any(
          (d) => d.lensDirection == camera.CameraLensDirection.front,
        ) &&
        devices.any((d) => d.lensDirection == camera.CameraLensDirection.back);
    if (devices.isEmpty) throw StateError('No camera available');
    final preferred = devices.where(
      (d) =>
          d.lensDirection ==
          (front
              ? camera.CameraLensDirection.front
              : camera.CameraLensDirection.back),
    );
    final c = controller = camera.CameraController(
      preferred.isEmpty ? devices.first : preferred.first,
      camera.ResolutionPreset.high,
      enableAudio: video,
    );
    await c.initialize();
    if (closed) {
      await c.dispose();
      return;
    }
    try {
      await c.setFlashMode(camera.FlashMode.off);
    } catch (_) {}
  }

  @override
  Widget preview() {
    final c = controller!;
    return LayoutBuilder(
      builder: (_, bounds) => ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.previewSize!.height,
              height: c.value.previewSize!.width,
              child: camera.CameraPreview(c),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<XFile> photo() => controller!.takePicture();
  @override
  Future<void> start() => controller!.startVideoRecording();
  @override
  Future<XFile> stop() => controller!.stopVideoRecording();
  @override
  Future<void> flash(bool enabled) => controller!.setFlashMode(
    enabled
        ? (video ? camera.FlashMode.torch : camera.FlashMode.always)
        : camera.FlashMode.off,
  );
  @override
  Future<double> zoom(double value) async {
    final c = controller!;
    final min = await c.getMinZoomLevel();
    final max = await c.getMaxZoomLevel();
    final actual = value.clamp(min, max).toDouble();
    await c.setZoomLevel(actual);
    return actual;
  }

  @override
  Future<void> dispose() async {
    if (!closed) {
      closed = true;
      await controller?.dispose();
    }
  }
}

/// Nothing captured here is uploaded. Closing, failed permission, interruption
/// and mode changes never publish content. Explicit review is a separate route.
class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    this.startVideo = false,
    this.allowPhoto = true,
    this.allowVideo = true,
    this.maxSeconds = 60,
    this.deviceFactory,
    this.openSettings,
  });
  final bool startVideo;
  final bool allowPhoto, allowVideo;
  final int maxSeconds;
  final CaptureDevice Function(bool video, bool front)? deviceFactory;
  final Future<void> Function()? openSettings;
  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage>
    with WidgetsBindingObserver, RouteAware {
  CaptureDevice? device;
  late bool video = widget.startVideo;
  bool front = false,
      ready = false,
      busy = false,
      recording = false,
      torch = false,
      foreground = true,
      leaving = false;
  int epoch = 0, seconds = 0;
  double zoom = 1;
  String? error;
  bool permissionDenied = false,
      permissionRestricted = false,
      settingsBusy = false;
  XFile? recovered;
  Timer? timer;
  Timer? countdownTimer;
  int captureDelay = 0, countdown = 0, countdownVersion = 0;
  ModalRoute<dynamic>? observedRoute;
  bool get routeAvailable =>
      mounted &&
      foreground &&
      !leaving &&
      ModalRoute.of(context)?.isCurrent != false;
  bool get canConfigure =>
      routeAvailable &&
      ready &&
      !busy &&
      !recording &&
      countdown == 0 &&
      recovered == null;
  Future<void>? operation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != observedRoute) {
      mediaRoutes.unsubscribe(this);
      observedRoute = route;
      if (route != null) mediaRoutes.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => cancelCountdown();
  @override
  void didPopNext() {}
  @override
  void didPush() {}
  @override
  void didPop() => cancelCountdown();

  void cancelCountdown({bool notify = true}) {
    countdownVersion++;
    countdownTimer?.cancel();
    countdownTimer = null;
    if (countdown != 0) {
      if (mounted && notify) {
        setState(() => countdown = 0);
      } else {
        countdown = 0;
      }
    }
  }

  void cycleCaptureDelay() {
    if (!canConfigure) return;
    setState(
      () => captureDelay = switch (captureDelay) {
        0 => 3,
        3 => 10,
        _ => 0,
      },
    );
  }

  void changeMode(bool mode) {
    if (!routeAvailable ||
        busy ||
        recording ||
        countdown > 0 ||
        recovered != null ||
        mode == video) {
      return;
    }
    setState(() => video = mode);
    boot();
  }

  void switchCamera() {
    if (!canConfigure || device?.canSwitch != true) return;
    front = !front;
    boot();
  }

  Future<void> boot() async {
    cancelCountdown();
    if (!foreground || recovered != null) return;
    final request = ++epoch;
    final old = device;
    device = null;
    setState(() {
      ready = false;
      error = null;
      permissionDenied = false;
      permissionRestricted = false;
      torch = false;
      zoom = 1;
    });
    await old?.dispose();
    if (!mounted || request != epoch || !foreground) return;
    final current =
        widget.deviceFactory?.call(video, front) ??
        NativeCaptureDevice(video: video, front: front);
    device = current;
    try {
      await current.initialize();
      if (!mounted || request != epoch || !foreground) {
        await current.dispose();
        return;
      }
      setState(() => ready = true);
    } catch (e) {
      if (mounted && request == epoch) setState(() => error = captureError(e));
      await current.dispose();
    }
  }

  Future<void> settings() async {
    if (settingsBusy || busy) return;
    setState(() => settingsBusy = true);
    try {
      await (widget.openSettings?.call() ?? photos.PhotoManager.openSetting());
    } catch (_) {
      if (mounted) {
        showInfo(
          context,
          t_(
            'Device settings could not be opened. Open Settings manually, then return to Sanjaal.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => settingsBusy = false);
    }
  }

  String captureError(Object e) {
    permissionRestricted =
        e is camera.CameraException && e.code.contains('Restricted');
    permissionDenied = e is camera.CameraException && e.code.contains('Denied');
    if (permissionRestricted) {
      return t_(
        'Camera or microphone access is restricted on this device. You may need help from the person who manages it. You can still choose media from your library.',
      );
    }
    if (e is camera.CameraException &&
        (e.code.contains('Denied') || e.code.contains('Restricted'))) {
      return t_(
        'Camera or microphone access is unavailable. Allow it in your device settings, or choose media from your library.',
      );
    }
    return t_(
      'The camera is unavailable. Try again or choose media from your library.',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      foreground = false;
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        suspend();
      }
    } else {
      foreground = true;
      if (!busy && recovered == null) boot();
      if (mounted) setState(() {});
    }
  }

  Future<void> suspend() async {
    cancelCountdown();
    if (device == null) return;
    final current = device!;
    device = null;
    epoch++;
    timer?.cancel();
    if (mounted) {
      setState(() {
        ready = false;
        busy = true;
      });
    }
    try {
      await operation;
      if (recording) recovered = await current.stop();
      recording = false;
    } catch (_) {
      if (mounted) {
        error = t_(
          'The interrupted recording could not be recovered. Nothing was posted.',
        );
      }
    } finally {
      await current.dispose();
      if (mounted) {
        setState(() => busy = false);
        if (foreground && recovered == null) boot();
      }
    }
  }

  Future<void> shutter() async {
    if (countdown > 0) {
      cancelCountdown();
      return;
    }
    if (!ready || busy || !routeAvailable || device == null) return;
    final current = device!, request = epoch;
    if (!recording && captureDelay > 0) {
      final version = ++countdownVersion;
      final delay = captureDelay;
      setState(() => countdown = delay);
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (tick) {
        if (!mounted ||
            !routeAvailable ||
            !ready ||
            busy ||
            request != epoch ||
            version != countdownVersion ||
            !identical(device, current)) {
          cancelCountdown();
          return;
        }
        final remaining = (delay - tick.tick).clamp(0, delay);
        if (remaining > 0) {
          setState(() => countdown = remaining);
        } else {
          cancelCountdown();
          unawaited(captureNow(current, request));
        }
      });
      return;
    }
    await captureNow(current, request);
  }

  Future<void> captureNow(CaptureDevice current, int request) async {
    if (!ready ||
        busy ||
        !routeAvailable ||
        request != epoch ||
        !identical(current, device)) {
      return;
    }
    final pending = capture(current, request);
    operation = pending;
    try {
      await pending;
    } finally {
      if (identical(operation, pending)) operation = null;
    }
  }

  Future<void> capture(CaptureDevice current, int request) async {
    setState(() => busy = true);
    try {
      if (!video) {
        final file = await current.photo();
        if (mounted && request == epoch && foreground) {
          await finish(file, isVideo: false);
        } else {
          recovered = file;
        }
      } else if (!recording) {
        await current.start();
        recording = true;
        if (!mounted || request != epoch || !foreground) return;
        setState(() {
          seconds = 0;
        });
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || !recording) return;
          setState(() => seconds++);
          if (seconds >= widget.maxSeconds && !busy) shutter();
        });
      } else {
        timer?.cancel();
        final file = await current.stop();
        recording = false;
        if (mounted && request == epoch && foreground) {
          await finish(file, isVideo: true);
        } else {
          recovered = file;
        }
      }
    } catch (e) {
      if (mounted && request == epoch) {
        timer?.cancel();
        device = null;
        epoch++;
        setState(() {
          ready = false;
          recording = false;
          busy = false;
          error = captureError(e);
        });
        await current.dispose();
      }
    } finally {
      if (mounted && request == epoch) setState(() => busy = false);
    }
  }

  Future<void> finish(XFile file, {required bool isVideo}) async {
    recovered = file;
    final current = device;
    device = null;
    epoch++;
    if (mounted) {
      setState(() {
        ready = false;
        recording = false;
      });
    }
    await current?.dispose();
    if (!mounted) return;
    setState(() => busy = false);
    if (foreground) {
      leaving = true;
      Navigator.pop(context, CreatorMedia(file, isVideo: isVideo));
    }
  }

  Future<void> setting(Future<void> Function() action) async {
    if (!canConfigure) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        showInfo(
          context,
          t_('That camera setting is not supported on this device.'),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> close() async {
    cancelCountdown();
    if (busy || leaving) return;
    if (recording || recovered != null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t_('Discard this recording?')),
          content: Text(
            t_(
              'Nothing has been posted. Discarding removes this local capture.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t_('Keep editing')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t_('Discard')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      if (recording) {
        timer?.cancel();
        setState(() => busy = true);
        try {
          recovered = await device?.stop();
        } catch (_) {}
        recording = false;
      }
      final file = recovered;
      if (file != null) {
        try {
          await File(file.path).delete();
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() {
        busy = false;
        leaving = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    cancelCountdown(notify: false);
    mediaRoutes.unsubscribe(this);
    epoch++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    device?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!recording && recovered == null && !busy),
    onPopInvokedWithResult: (p, _) {
      if (!p) close();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ready && device != null && recovered == null)
                      device!.preview()
                    else
                      const ColoredBox(color: Color(0xFF101214)),
                    if (!ready && error == null && recovered == null)
                      const Center(child: CircularProgressIndicator()),
                    if (error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 76, 28, 24),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 12),
                                if (permissionDenied)
                                  FilledButton(
                                    onPressed: busy || settingsBusy
                                        ? null
                                        : settings,
                                    child: Text(t_('Open device settings')),
                                  ),
                                if (!permissionRestricted)
                                  TextButton(
                                    onPressed: busy ? null : boot,
                                    child: Text(t_('Try again')),
                                  ),
                                TextButton(
                                  onPressed: busy ? null : close,
                                  child: Text(t_('Close camera')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (recovered != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t_(
                                  'Your interrupted capture is ready to review. Nothing has been posted.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        leaving = true;
                                        Navigator.pop(
                                          context,
                                          CreatorMedia(
                                            recovered!,
                                            isVideo: video,
                                          ),
                                        );
                                      },
                                child: Text(t_('Review capture')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 116,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          key: ValueKey('camera-header-contrast'),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xD9000000),
                                Color(0x99000000),
                                Color(0x00000000),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: t_('Close camera'),
                            onPressed: busy ? null : close,
                            icon: const PhIcon('x', color: Colors.white),
                          ),
                          const Spacer(),
                          if (recovered == null) ...[
                            IconButton(
                              tooltip: t_(torch ? 'Flash on' : 'Flash off'),
                              onPressed: canConfigure
                                  ? () => setting(() async {
                                      await device!.flash(!torch);
                                      if (mounted) {
                                        setState(() => torch = !torch);
                                      }
                                    })
                                  : null,
                              icon: PhIcon(
                                torch ? 'lightning-fill' : 'lightning-slash',
                                color: Colors.white,
                              ),
                            ),
                            TextButton(
                              onPressed: canConfigure
                                  ? () => setting(() async {
                                      final next = zoom == 1 ? 2.0 : 1.0;
                                      final actual = await device!.zoom(next);
                                      if (mounted) {
                                        setState(() => zoom = actual);
                                      }
                                    })
                                  : null,
                              child: Text(
                                '${zoom == zoom.roundToDouble() ? zoom.toStringAsFixed(0) : zoom.toStringAsFixed(1)}x',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (countdown > 0)
                      Center(
                        child: Semantics(
                          liveRegion: true,
                          label:
                              '${t_(video ? 'Recording starts in' : 'Photo in')} $countdown ${t_('seconds')}',
                          child: ExcludeSemantics(
                            child: Container(
                              key: const ValueKey('capture-countdown-circle'),
                              width: MediaQuery.textScalerOf(context)
                                  .scale(132)
                                  .clamp(132.0, 200.0)
                                  .toDouble(),
                              height: MediaQuery.textScalerOf(context)
                                  .scale(132)
                                  .clamp(132.0, 200.0)
                                  .toDouble(),
                              padding: const EdgeInsets.all(16),
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xBB000000),
                                shape: BoxShape.circle,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$countdown',
                                  key: const ValueKey(
                                    'capture-countdown-number',
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 72,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (recording)
                      Positioned(
                        top: 74,
                        left: 16,
                        right: 16,
                        child: Text(
                          '${seconds.toString().padLeft(2, '0')} / ${widget.maxSeconds}s',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ),
                    if (recovered == null && error == null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 28,
                        child: Center(
                          child: Semantics(
                            label: t_(
                              countdown > 0
                                  ? 'Cancel countdown'
                                  : recording
                                  ? 'Stop recording'
                                  : video
                                  ? 'Start recording'
                                  : 'Take a photo',
                            ),
                            button: true,
                            child: InkResponse(
                              onTap: ready && !busy ? shutter : null,
                              child: Container(
                                width: 86,
                                height: 86,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0x88000000),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x99000000),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: recording
                                        ? BoxShape.rectangle
                                        : BoxShape.circle,
                                    borderRadius: recording
                                        ? BorderRadius.circular(16)
                                        : null,
                                    color: ready && !busy
                                        ? (recording
                                              ? Colors.red
                                              : Colors.white)
                                        : Colors.grey,
                                  ),
                                  child: countdown > 0
                                      ? const Center(
                                          child: PhIcon(
                                            'x',
                                            color: Colors.black,
                                            size: 34,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: Row(
                children: [
                  Semantics(
                    value: captureDelay == 0
                        ? t_('Off')
                        : '$captureDelay ${t_('seconds')}',
                    child: IconButton(
                      key: const ValueKey('capture-delay'),
                      tooltip: t_('Capture timer'),
                      onPressed: canConfigure ? cycleCaptureDelay : null,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      padding: const EdgeInsets.all(4),
                      icon: captureDelay == 0
                          ? const PhIcon('timer', color: Colors.white)
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$captureDelay',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final mode in [
                          if (widget.allowPhoto) false,
                          if (widget.allowVideo) true,
                        ])
                          TextButton(
                            onPressed:
                                busy ||
                                    recording ||
                                    countdown > 0 ||
                                    recovered != null
                                ? null
                                : () => changeMode(mode),
                            child: Text(
                              t_(mode ? 'Video' : 'Photo'),
                              style: TextStyle(
                                color: video == mode
                                    ? Colors.white
                                    : Colors.grey,
                                fontWeight: video == mode
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t_('Switch camera'),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      maximumSize: const Size(48, 48),
                    ),
                    onPressed: canConfigure && device?.canSwitch == true
                        ? switchCamera
                        : null,
                    icon: const PhIcon('arrows-clockwise', color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
