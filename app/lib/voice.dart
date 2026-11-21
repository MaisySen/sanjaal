import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'glass/glass_material.dart';
import 'glass/glass_tokens.dart';

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

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final AudioRecorder _rec = AudioRecorder();
  Timer? _tick;
  Duration _elapsed = Duration.zero;
  String? _path;
  bool _ready = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        widget.onError('Microphone permission is needed to record. Allow it in Settings.');
        widget.onCancel();
        return;
      }
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 22050, numChannels: 1), path: _path!);
      if (!mounted) return;
      setState(() => _ready = true);
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(milliseconds: 250));
        if (_elapsed.inSeconds >= maxVoiceSeconds) _send();
      });
    } catch (e) {
      widget.onError('Could not start recording.');
      widget.onCancel();
    }
  }

  Future<void> _send() async {
    if (_finished) return;
    _finished = true;
    _tick?.cancel();
    try {
      final p = await _rec.stop();
      final path = p ?? _path;
      if (path == null || _elapsed.inMilliseconds < 800) {
        if (path != null) File(path).delete().catchError((_) => File(path));
        widget.onError('Hold on a little longer. That was too short.');
        widget.onCancel();
        return;
      }
      final bytes = await File(path).readAsBytes();
      File(path).delete().catchError((_) => File(path));
      widget.onDone(bytes);
    } catch (e) {
      widget.onError('Could not save the recording.');
      widget.onCancel();
    }
  }

  Future<void> _discard() async {
    if (_finished) return;
    _finished = true;
    _tick?.cancel();
    try {
      final p = await _rec.stop();
      if (p != null) File(p).delete().catchError((_) => File(p));
    } catch (_) {}
    widget.onCancel();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassMaterial(
      radius: GlassTokens.radiusPill,
      blur: GlassTokens.blurLight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          IconButton(onPressed: _discard, icon: Icon(Icons.delete_outline, color: scheme.error), tooltip: 'Discard'),
          Icon(Icons.fiber_manual_record, size: 14, color: _ready ? scheme.error : scheme.outline),
          const SizedBox(width: 8),
          Text(_ready ? _clock(_elapsed) : 'Starting', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text('Recording', style: TextStyle(color: scheme.onSurfaceVariant))),
          IconButton.filled(onPressed: _ready ? _send : null, icon: const Icon(Icons.send), tooltip: 'Send voice message'),
        ]),
      ),
    );
  }
}

/// Play and pause a received or sent voice message. [dark] is true inside an
/// own message bubble, where the icon and progress are white on crimson.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.url, this.dark = false});
  final String url;
  final bool dark;
  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
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

  Future<void> _toggle() async {
    final p = _ensure();
    try {
      if (_playing) {
        await p.pause();
        setState(() => _playing = false);
      } else {
        await p.play(UrlSource(widget.url));
        setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this voice message.')));
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final accent = widget.dark ? Colors.white : scheme.primary;
    return SizedBox(
      width: 210,
      child: Row(children: [
        IconButton(onPressed: _toggle, icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36, color: accent)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: progress, minHeight: 4, borderRadius: BorderRadius.circular(2), backgroundColor: accent.withValues(alpha: 0.28), color: accent),
            const SizedBox(height: 4),
            Text(_total == Duration.zero ? 'Voice message' : '${_clock(_playing || _pos > Duration.zero ? _pos : _total)} / ${_clock(_total)}', style: TextStyle(fontSize: 11, color: widget.dark ? Colors.white70 : null)),
          ]),
        ),
      ]),
    );
  }
}
