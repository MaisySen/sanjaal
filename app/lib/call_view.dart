import 'ph.dart';

import 'package:material_ui/material_ui.dart';

import 'ui.dart' show t_;

class CallTile extends StatelessWidget {
  const CallTile({super.key, required this.name, this.video});
  final String name;
  final Widget? video;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.grey.shade900,
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        if (video != null)
          Positioned.fill(child: video!)
        else
          const Center(
            child: PhIcon('user-fill', size: 64, color: Colors.white54),
          ),
        Positioned(
          left: 10,
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(name, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
    ),
  );
}

/// The call screen without any LiveKit dependency, so it can be rendered offline.
class CallView extends StatelessWidget {
  const CallView({
    super.key,
    required this.title,
    required this.status,
    required this.failed,
    required this.video,
    required this.muted,
    required this.camOn,
    required this.tiles,
    required this.onMute,
    required this.onCamera,
    required this.onEnd,
    this.selfPreview,
    this.controlsBusy = false,
    this.onMinimize,
  });
  final String title;
  final String status;
  final bool failed;
  final bool video;
  final bool muted;
  final bool camOn;
  final List<Widget> tiles;
  final Widget? selfPreview;
  final bool controlsBusy;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onEnd;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: onMinimize != null
            ? IconButton(
                tooltip: t_('Minimize call'),
                onPressed: onMinimize,
                icon: const PhIcon('caret-down', color: Colors.white),
              )
            : (Navigator.maybeOf(context)?.canPop() == true
                  ? BackButton(
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onEnd,
                    )
                  : null),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            // A service/permission error may be long, especially with large text.
            // Keep it fully scrollable without pushing End call off the screen.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxHeight * 0.3),
              child: SingleChildScrollView(
                key: const ValueKey('call-status-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    t_(status),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (tiles.isEmpty)
                    const Center(
                      child: PhIcon(
                        'user-fill',
                        size: 80,
                        color: Colors.white54,
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, box) {
                        final cols = tiles.length > 1 ? 2 : 1;
                        final rows = (tiles.length / cols).ceil();
                        return GridView.count(
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: cols,
                          childAspectRatio:
                              (box.maxWidth / cols) / (box.maxHeight / rows),
                          children: tiles,
                        );
                      },
                    ),
                  if (selfPreview != null)
                    Positioned(
                      right: 14,
                      top: 14,
                      child: Semantics(
                        label: t_('Your camera preview'),
                        child: SizedBox(
                          height: 120,
                          width: 90,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: selfPreview,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white54,
                        ),
                        tooltip: t_(
                          muted ? 'Unmute microphone' : 'Mute microphone',
                        ),
                        onPressed: failed || controlsBusy ? null : onMute,
                        icon: PhIcon(muted ? Ph.mic_off : Ph.mic),
                      ),
                      if (video)
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.18,
                            ),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white54,
                          ),
                          tooltip: t_(
                            camOn ? 'Turn camera off' : 'Turn camera on',
                          ),
                          onPressed: failed || controlsBusy ? null : onCamera,
                          icon: PhIcon(camOn ? Ph.videocam : Ph.videocam_off),
                        ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        tooltip: t_('End call'),
                        onPressed: onEnd,
                        icon: const PhIcon('phone-x-fill', color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
