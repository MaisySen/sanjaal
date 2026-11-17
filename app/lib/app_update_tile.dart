import 'package:material_ui/material_ui.dart';

import 'app_updates.dart';

/// Manual check, Play consent, then separate explicit restart. No startup nag.
class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({super.key, this.controller});
  final AppUpdateController? controller;
  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile>
    with WidgetsBindingObserver {
  late final AppUpdateController controller;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? AppUpdateController(PlayUpdateGateway());
    controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        controller.phase != UpdatePhase.idle) {
      controller.check(resume: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  String get message => switch (controller.phase) {
    UpdatePhase.idle => 'Check Google Play for a newer full app build.',
    UpdatePhase.checking => 'Checking Google Play...',
    UpdatePhase.current =>
      'Google Play reports no newer build for this account.',
    UpdatePhase.available =>
      'A newer build is available. Download it with Google Play.',
    UpdatePhase.consent =>
      'Choose whether to download in the Google Play dialog.',
    UpdatePhase.downloading =>
      'Downloading with Google Play. You can keep using Sanjaal.',
    UpdatePhase.ready => 'Update downloaded. Save your work before restarting.',
    UpdatePhase.installing =>
      'Google Play is installing the update and may restart Sanjaal.',
    UpdatePhase.unavailable => 'Could not offer an update. Check your connection and use the Google Play account that installed Sanjaal.',
    UpdatePhase.canceled => 'Update canceled. Your current app is unchanged.',
    UpdatePhase.failed =>
      'The update did not finish. Check Google Play and try again.',
    UpdatePhase.unsupported => 'Install full app updates through your app store. In-app updates are available only on Android with Google Play.',
  };
  @override
  Widget build(BuildContext context) {
    final ready = controller.phase == UpdatePhase.ready;
    final available = controller.phase == UpdatePhase.available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 8),
        if (controller.phase == UpdatePhase.downloading) ...[
          LinearProgressIndicator(value: controller.progress),
          const SizedBox(height: 8),
        ],
        if (controller.phase != UpdatePhase.unsupported)
          OutlinedButton(
            onPressed: controller.busy
                ? null
                : () {
                    if (ready) {
                      controller.install();
                    } else if (available) {
                      controller.download();
                    } else {
                      controller.check();
                    }
                  },
            child: Text(
              ready
                  ? 'Restart and install'
                  : available
                  ? 'Download update'
                  : 'Check for updates',
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'These are full app updates, not background code patches.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
