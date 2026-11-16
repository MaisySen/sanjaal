import 'ph.dart';
import 'media_visibility.dart';
import 'ui.dart' show t_;
import 'api.dart' show Session, newUploadIntent;
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const int maxVoiceSeconds = 120;

String _clock(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Records a voice message. Calls [onDone] with the AAC bytes, or [onCancel] when discarded.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({super.key, required this.onDone, required this.onCancel, required this.onError});
  final void Function(List<int> bytes) onDone;
  final VoidCallback onCancel;
  final void Function(String message) onError;
  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> with MediaVisibility<VoiceRecorderBar> {
  final AudioRecorder _rec = AudioRecorder();
  late final Future<void> _starting;
  Future<void>? _ending, _closing;
  Timer? _tick;
  Duration _elapsed = Duration.zero;
  String? _path, _stoppedPath;
  bool _ready = false, _finished = false, _cancelled = false;
  bool _startRequested = false, _nativeEnded = false, _notified = false;
  bool get _active => mounted && !_cancelled && mediaVisible;

  @override
  void initState() {
    super.initState();
    _starting = Future<void>.microtask(_start);
  }

  Future<void> _deleteFiles() async {
    for (final path in {_path, _stoppedPath}.whereType<String>()) {
      try { final file = File(path); if (await file.exists()) await file.delete(); } catch (_) {}
    }
  }

  Future<void> _cancelNative() async {
    if (_startRequested && !_nativeEnded) {
      try { await _rec.cancel(); _nativeEnded = true; } catch (_) {}
    }
    await _deleteFiles();
  }

  void _notifyCancel() {
    if (mounted && !_notified) { _notified = true; widget.onCancel(); }
  }

  void _error(String message) {
    if (!_active) return;
    widget.onError(t_(message));
    if (_active) _notifyCancel();
  }

  Future<void> _start() async {
    if (!_active) {
      _cancelled = true;
      _finished = true;
      _notifyCancel();
      return;
    }
    if (_finished) return;
    try {
      final allowed = await _rec.hasPermission();
      if (!_active || _finished) return;
      if (!allowed) {
        _finished = true;
        _error('Microphone permission is needed to record. Allow it in Settings.');
        return;
      }
      final dir = await getTemporaryDirectory();
      if (!_active || _finished) return;
      _path = '${dir.path}/voice-${newUploadIntent()}.m4a';
      _startRequested = true;
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 22050, numChannels: 1), path: _path!);
      if (!_active || _finished) return;
      setState(() => _ready = true);
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!_active || _finished) return;
        setState(() => _elapsed += const Duration(milliseconds: 250));
        if (_elapsed.inSeconds >= maxVoiceSeconds) _send();
      });
    } catch (_) {
      await _cancelNative();
      if (_active && !_finished) {
        _finished = true;
        _error('Could not start recording.');
      }
    }
  }

  Future<void> _send() async {
    if (_finished || !_ready || !_active) return;
    setState(() => _finished = true);
    _tick?.cancel();
    _ending = _sendAndFinish();
    await _ending;
  }

  Future<void> _sendAndFinish() async {
    try {
      await _starting;
      _stoppedPath = await _rec.stop();
      _nativeEnded = true;
      final path = _stoppedPath ?? _path;
      if (!_active) return;
      if (path == null || _elapsed.inMilliseconds < 800) {
        _error('Hold on a little longer. That was too short.');
        return;
      }
      final bytes = await File(path).readAsBytes();
      // Finish private-file cleanup before handing bytes to a callback that
      // can remove this widget or start an upload. Recheck visibility afterward.
      await _cancelNative();
      if (_active && !_notified) { _notified = true; widget.onDone(bytes); }
    } catch (_) {
      _error('Could not save the recording.');
    } finally {
      await _cancelNative();
      if (_cancelled) _notifyCancel();
    }
  }

  Future<void> _discard() async {
    if (_finished) return;
    _cancelled = true;
    setState(() => _finished = true);
    _tick?.cancel();
    _ending = _discardAndFinish();
    await _ending;
  }

  Future<void> _discardAndFinish() async {
    await _starting;
    await _cancelNative();
    _notifyCancel();
  }

  @override
  void mediaVisibilityChanged(bool visible) {
    if (visible) return;
    _cancelled = true;
    if (!_finished) _discard();
  }

  Future<void> _shutdown() => _closing ??= () async {
    await _starting;
    await _ending;
    await _cancelNative();
    try { await _rec.dispose(); } catch (_) {}
  }();

  @override
  void dispose() {
    _cancelled = true;
    _tick?.cancel();
    // A start/stop in flight owns the recorder until it returns. Shutdown waits
    // for both, then cancels remaining capture and deletes only our temp files.
    _shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      IconButton(onPressed: _finished ? null : _discard, icon: PhIcon('trash', color: scheme.error), tooltip: t_('Discard')),
      PhIcon('circle-fill', size: 14, color: _ready && !_finished ? scheme.error : scheme.outline),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(_finished ? t_('Finishing') : _ready ? _clock(_elapsed) : t_('Starting'), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (!_finished) Text(t_('Recording'), style: TextStyle(color: scheme.onSurfaceVariant)),
      ])),
      IconButton.filled(onPressed: _ready && !_finished ? _send : null, icon: PhIcon('paper-plane-tilt-fill', color: scheme.onPrimary), tooltip: t_('Send voice message')),
    ]);
  }
}

/// Play and pause a received or sent voice message.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.url, this.session});
  final String url;

  /// When set, the file is fetched with the person's sign-in (chat voice messages need it).
  final Session? session;
  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> with MediaVisibility<VoiceBubble> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
  bool _busy = false;
  bool _sourceReady = false;
  int _generation = 0;
  Duration _pos = Duration.zero;
  Duration _total = Duration.zero;

  AudioPlayer _ensure() {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _subs.add(p.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    }));
    _subs.add(p.onPositionChanged.listen((d) {
      if (mounted) setState(() => _pos = d);
    }));
    _subs.add(p.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _pos = Duration.zero;
        });
      }
    }));
    _player = p;
    return p;
  }

  @override
  void mediaVisibilityChanged(bool visible) {
    if (visible) return;
    _generation++;
    _player?.pause().catchError((_) {});
    if (mounted) setState(() => _playing = false);
  }

  @override
  void didUpdateWidget(covariant VoiceBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.session != widget.session) {
      _generation++;
      for (final s in _subs) { s.cancel(); }
      _subs.clear();
      _player?.dispose().catchError((_) {});
      _player = null;
      _sourceReady = false;
      _playing = false;
      _pos = Duration.zero;
      _total = Duration.zero;
    }
  }

  Future<void> _toggle() async {
    if (_busy || !mediaVisible) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final p = _ensure();
      if (_playing) {
        await p.pause();
        if (mounted && generation == _generation) setState(() => _playing = false);
      } else {
        if (!_sourceReady) {
          final s = widget.session;
          final source = s == null ? UrlSource(widget.url) : BytesSource(await s.fetchBytes(widget.url));
          // A download or native decoder can finish after navigation/background.
          if (!mediaVisible || generation != _generation) return;
          await p.setSource(source);
          if (!mediaVisible || generation != _generation) return;
          _sourceReady = true;
        }
        await p.resume();
        if (!mediaVisible || generation != _generation) {
          await p.pause();
          return;
        }
        setState(() => _playing = true);
      }
    } catch (_) {
      if (mediaVisible && generation == _generation) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('Could not play this voice message.'))));
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  void dispose() {
    _generation++;
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = DefaultTextStyle.of(context).style.color ?? Theme.of(context).colorScheme.onSurface;
    final progress = _total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 210,
      child: Row(children: [
        IconButton(tooltip: t_(_busy ? 'Loading voice message' : _playing ? 'Pause voice message' : 'Play voice message'), onPressed: _busy ? null : _toggle, icon: _busy ? SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: ink)) : PhIcon(_playing ? Ph.pause_circle_filled : Ph.play_circle_fill, size: 36, color: ink)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: progress, minHeight: 4, borderRadius: BorderRadius.circular(2), backgroundColor: ink.withValues(alpha: 0.28), color: ink),
            const SizedBox(height: 4),
            Text(_total == Duration.zero ? t_('Voice message') : '${_clock(_playing || _pos > Duration.zero ? _pos : _total)} / ${_clock(_total)}', style: const TextStyle(fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}
