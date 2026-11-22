import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart' as camera;
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' as photos;
import 'package:material_ui/material_ui.dart';

import 'ph.dart';
import 'capture_recording_time.dart';
import 'capture_release_guard.dart';
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

abstract class PausableCaptureDevice {
  Future<void> pauseRecording();
  Future<void> resumeRecording();
}

final _nativeCaptureReleaseGuard = CaptureReleaseGuard();

class NativeCaptureDevice implements CaptureDevice, PausableCaptureDevice {
  NativeCaptureDevice({
    required this.video,
    required this.front,
    CaptureReleaseGuard? releaseGuard,
  }) : releaseGuard = releaseGuard ?? _nativeCaptureReleaseGuard;
  final CaptureReleaseGuard releaseGuard;
  void quarantine() => releaseGuard.markUncertain();
  final bool video, front;
  camera.CameraController? controller;
  bool closed = false;
  bool switchable = false;
  @override
  bool get canSwitch => switchable;
  @override
  Future<void> initialize() async {
    releaseGuard.ensureAvailable();
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
  Future<void> pauseRecording() => controller!.pauseVideoRecording();
  @override
  Future<void> resumeRecording() => controller!.resumeVideoRecording();
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
      try {
        await controller?.dispose().timeout(const Duration(seconds: 8));
      } catch (_) {
        quarantine();
        rethrow;
      }
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
    this.recordingClock,
  });
  final bool startVideo;
  final bool allowPhoto, allowVideo;
  final int maxSeconds;
  final CaptureDevice Function(bool video, bool front)? deviceFactory;
  final Future<void> Function()? openSettings;
  // Controlled fixture clock only. Production uses a monotonic stopwatch.
  final Duration Function()? recordingClock;
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
      paused = false,
      restartRequired = false,
      torch = false,
      foreground = true,
      leaving = false;
  int epoch = 0, seconds = 0;
  double zoom = 1;
  String? error, recoveryMessage;
  bool permissionDenied = false,
      permissionRestricted = false,
      settingsBusy = false;
  XFile? recovered;
  Timer? timer;
  final Stopwatch monotonic = Stopwatch()..start();
  late final recordingTime = CaptureRecordingTime(
    () => widget.recordingClock?.call() ?? monotonic.elapsed,
  );
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
    if (!mounted || !foreground || recovered != null || restartRequired) return;
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
    if (!await releaseDevice(old)) {
      if (mounted) setState(() => error = restartMessage);
      return;
    }
    if (!mounted || request != epoch || !foreground) return;
    final current =
        widget.deviceFactory?.call(video, front) ??
        NativeCaptureDevice(video: video, front: front);
    device = current;
    try {
      await current.initialize();
      if (!mounted || request != epoch || !foreground) {
        await releaseDevice(current);
        return;
      }
      setState(() => ready = true);
    } catch (e) {
      if (mounted && request == epoch) setState(() => error = captureError(e));
      await releaseDevice(current);
      if (mounted && restartRequired) setState(() => error = restartMessage);
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

  String get restartMessage => t_(
    'Camera cleanup could not be confirmed. Force close Sanjaal, then reopen it before using the camera again. Nothing was posted.',
  );

  Future<bool> releaseDevice(CaptureDevice? current) async {
    if (current == null) return true;
    try {
      await current.dispose().timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      restartRequired = true;
      if (current is NativeCaptureDevice) current.quarantine();
      return false;
    }
  }

  String captureError(Object e) {
    if (e is CaptureRestartRequired) {
      restartRequired = true;
      return restartMessage;
    }
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
      if (!busy && recovered == null && !restartRequired) boot();
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
    recordingTime.pause();
    if (mounted) {
      setState(() {
        ready = false;
        busy = true;
      });
    }
    try {
      await operation;
      if (recording) {
        recovered = await current.stop().timeout(const Duration(seconds: 8));
      }
      recording = false;
      paused = false;
    } catch (_) {
      if (mounted) {
        error = t_(
          'The interrupted recording could not be recovered. Nothing was posted.',
        );
      }
    } finally {
      final released = await releaseDevice(current);
      if (mounted) {
        setState(() {
          busy = false;
          recording = false;
          paused = false;
          if (!released || restartRequired) {
            error = restartMessage;
            recoveryMessage = restartMessage;
          }
        });
        if (foreground && recovered == null && !restartRequired) boot();
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
        recordingTime.begin();
        await current.start();
        recording = true;
        if (!mounted || request != epoch || !foreground) return;
        setState(() {
          seconds = 0;
        });
        paused = false;
        armRecordingTimer();
      } else {
        timer?.cancel();
        recordingTime.pause();
        final file = await current.stop().timeout(const Duration(seconds: 8));
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
        recordingTime.pause();
        device = null;
        epoch++;
        setState(() {
          ready = false;
          recording = false;
          busy = false;
          error = captureError(e);
        });
        final released = await releaseDevice(current);
        if (!released && mounted) setState(() => error = restartMessage);
      }
    } finally {
      if (mounted && request == epoch) setState(() => busy = false);
    }
  }

  void armRecordingTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !recording || paused) return;
      final elapsed = recordingTime.elapsed;
      final shown = elapsed.inSeconds.clamp(0, widget.maxSeconds);
      if (shown != seconds) setState(() => seconds = shown);
      if (elapsed >= Duration(seconds: widget.maxSeconds) && !busy) {
        unawaited(shutter());
      }
    });
  }

  Future<void> toggleRecordingPause() async {
    final current = device;
    if (!routeAvailable ||
        busy ||
        !ready ||
        !recording ||
        current is! PausableCaptureDevice ||
        restartRequired) {
      return;
    }
    final request = epoch;
    final pending = changeRecordingPause(current as CaptureDevice, request);
    operation = pending;
    try {
      await pending;
    } finally {
      if (identical(operation, pending)) operation = null;
    }
    if (mounted &&
        request == epoch &&
        recording &&
        !busy &&
        recordingTime.elapsed >= Duration(seconds: widget.maxSeconds)) {
      await shutter();
    }
  }

  Future<void> changeRecordingPause(CaptureDevice current, int request) async {
    final controls = current as PausableCaptureDevice;
    final wasPaused = paused;
    setState(() => busy = true);
    try {
      // Count all time in which recording may already have resumed. Do not
      // tell the user it is paused until the native operation confirms it.
      if (wasPaused) recordingTime.resume();
      await (wasPaused ? controls.resumeRecording() : controls.pauseRecording())
          .timeout(const Duration(seconds: 8));
      if (!mounted ||
          request != epoch ||
          !identical(current, device) ||
          !foreground) {
        return;
      }
      if (!wasPaused) {
        recordingTime.pause();
        timer?.cancel();
      } else {
        armRecordingTimer();
      }
      setState(() {
        paused = !wasPaused;
        seconds = recordingTime.elapsed.inSeconds.clamp(0, widget.maxSeconds);
      });
    } catch (e) {
      if (e is TimeoutException) {
        restartRequired = true;
        if (current is NativeCaptureDevice) current.quarantine();
      }
      if (mounted && request == epoch && identical(current, device)) {
        await recoverRecordingControlFailure(current);
      }
    } finally {
      if (mounted && request == epoch) setState(() => busy = false);
    }
  }

  Future<void> recoverRecordingControlFailure(CaptureDevice current) async {
    timer?.cancel();
    recordingTime.pause();
    device = null;
    epoch++;
    setState(() {
      ready = false;
      recording = false;
      paused = false;
    });
    XFile? file;
    try {
      file = await current.stop().timeout(const Duration(seconds: 8));
    } catch (_) {
      /* No claim that a clip exists without the native stop result. */
    }
    final released = await releaseDevice(current);
    recovered = file;
    if (mounted) {
      setState(() {
        busy = false;
        if (!released || restartRequired) {
          error = restartMessage;
          recoveryMessage = restartMessage;
        } else if (file != null) {
          error = null;
          recoveryMessage = t_(
            'Recording controls failed. Your saved clip is ready to review. Nothing was posted.',
          );
        } else {
          error = t_(
            'Recording controls failed and no clip could be recovered. Nothing was posted.',
          );
        }
      });
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
    final released = await releaseDevice(current);
    if (!mounted) return;
    if (!released || restartRequired) {
      setState(() {
        busy = false;
        recoveryMessage = restartMessage;
      });
      return;
    }
    setState(() => busy = false);
    if (foreground) {
      await exitCapture(CreatorMedia(file, isVideo: isVideo));
    }
  }

  Future<void> exitCapture([CreatorMedia? value]) async {
    if (!routeAvailable) return;
    setState(() => leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      setState(() => leaving = false);
      return;
    }
    Navigator.pop(context, value);
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
    if (busy || !routeAvailable) return;
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
        recordingTime.pause();
        setState(() => busy = true);
        try {
          recovered = await device?.stop().timeout(const Duration(seconds: 8));
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
    final current = device;
    device = null;
    epoch++;
    if (mounted) {
      setState(() {
        ready = false;
        busy = true;
      });
    }
    final released = await releaseDevice(current);
    if (!released && mounted) {
      setState(() {
        busy = false;
        error = restartMessage;
      });
      return;
    }
    if (mounted) {
      setState(() => busy = false);
      await exitCapture();
    }
  }

  @override
  void dispose() {
    cancelCountdown(notify: false);
    mediaRoutes.unsubscribe(this);
    epoch++;
    timer?.cancel();
    monotonic.stop();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(releaseDevice(device));
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
                    if (error != null && recovered == null)
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
                                if (!permissionRestricted && !restartRequired)
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
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                recoveryMessage ??
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
                                    : () => unawaited(
                                        exitCapture(
                                          CreatorMedia(
                                            recovered!,
                                            isVideo: video,
                                          ),
                                        ),
                                      ),
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${paused && !busy ? '${t_('Paused')} · ' : ''}${seconds.toString().padLeft(2, '0')} / ${widget.maxSeconds}s',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                backgroundColor: paused
                                    ? const Color(0xCC000000)
                                    : Colors.red,
                              ),
                            ),
                            if (device is PausableCaptureDevice) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                key: const ValueKey('recording-pause'),
                                onPressed: busy ? null : toggleRecordingPause,
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xCC000000),
                                  foregroundColor: Colors.white,
                                ),
                                icon: PhIcon(
                                  paused
                                      ? 'play-circle-fill'
                                      : 'pause-circle-fill',
                                  color: Colors.white,
                                ),
                                label: Text(
                                  t_(
                                    busy
                                        ? (paused
                                              ? 'Resuming recording...'
                                              : 'Pausing recording...')
                                        : (paused
                                              ? 'Resume recording'
                                              : 'Pause recording'),
                                  ),
                                ),
                              ),
                            ],
                          ],
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
