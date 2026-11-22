import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'glass/glass_app_bar.dart';
import 'session_bound_state.dart';
import 'ui.dart';

const deviceAccessStates = {
  'allowed': 'Allowed',
  'not_allowed': 'Not allowed',
  'not_requested': 'Not requested',
  'restricted': 'Restricted by device',
  'limited': 'Selected items only',
  'unknown': 'Status unavailable',
};

class DeviceAccessSnapshot {
  DeviceAccessSnapshot(dynamic value) {
    if (value is! Map || !['android', 'ios'].contains(value['platform'])) {
      throw const FormatException('Unsupported permission response');
    }
    platform = value['platform'];
    final states = value['states'];
    if (states is! Map ||
        [
          'camera',
          'microphone',
          'photos',
          'videos',
        ].any((key) => !deviceAccessStates.containsKey(states[key]))) {
      throw const FormatException('Invalid permission response');
    }
    if (['camera', 'microphone'].any((key) => states[key] == 'limited')) {
      throw const FormatException('Invalid limited permission');
    }
    values = Map<String, String>.unmodifiable(states.cast<String, String>());
  }
  late final String platform;
  late final Map<String, String> values;
}

class DeviceAccessGateway {
  const DeviceAccessGateway();
  static const channel = MethodChannel('au.fintex.sanjaal/device-access');
  Future<DeviceAccessSnapshot> read() async =>
      DeviceAccessSnapshot(await channel.invokeMethod('status'));
  Future<bool> openSettings() async =>
      await channel.invokeMethod<bool>('settings') == true;
}

class DeviceAccessPage extends StatefulWidget {
  const DeviceAccessPage({
    super.key,
    required this.session,
    this.gateway = const DeviceAccessGateway(),
  });
  final Session session;
  final DeviceAccessGateway gateway;
  @override
  State<DeviceAccessPage> createState() => _DeviceAccessPageState();
}

class _DeviceAccessPageState extends State<DeviceAccessPage>
    with SessionBoundState<DeviceAccessPage>, WidgetsBindingObserver {
  @override
  Session get viewSession => widget.session;
  DeviceAccessSnapshot? snapshot;
  String? error;
  bool loading = false, opening = false;
  int request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void sessionRetired() {
    request++;
    snapshot = null;
    error = null;
    loading = opening = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    if (!mounted || !sessionActive) return;
    final ticket = ++request;
    setState(() {
      loading = true;
      error = null;
      snapshot = null;
    });
    try {
      final value = await widget.gateway.read();
      if (mounted && sessionActive && ticket == request) {
        setState(() => snapshot = value);
      }
    } catch (_) {
      if (mounted && sessionActive && ticket == request) {
        setState(
          () => error = t_('Device access could not be checked. Try again.'),
        );
      }
    } finally {
      if (mounted && sessionActive && ticket == request) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> openSettings() async {
    if (!mounted ||
        !sessionActive ||
        opening ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() => opening = true);
    var opened = false;
    try {
      opened = await widget.gateway.openSettings();
    } catch (_) {
      // The screen remains available if the OS cannot open its settings page.
    }
    if (!mounted || !sessionActive) return;
    setState(() {
      opening = false;
      if (!opened) {
        error = t_('Device settings could not be opened. Try again.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    final value = snapshot;
    return Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Device access'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t_(
              'Change access in your device settings. Sanjaal checks again when you return.',
            ),
          ),
          const SizedBox(height: 16),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(
              onPressed: loading ? null : load,
              child: Text(t_('Check again')),
            ),
          ],
          if (value != null)
            for (final entry in {
              'camera': 'Camera',
              'microphone': 'Microphone',
              'photos': value.platform == 'ios'
                  ? 'Photos and videos'
                  : 'Photos',
              if (value.platform == 'android') 'videos': 'Videos',
            }.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t_(entry.value)),
                subtitle: Text(
                  t_(deviceAccessStates[value.values[entry.key]]!),
                ),
              ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: opening ? null : openSettings,
            child: Text(
              t_(opening ? 'Opening settings...' : 'Open device settings'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t_(
              'Permission settings do not confirm that camera, microphone or playback works.',
            ),
          ),
          Text(
            t_(
              'Selected access applies only to the photos and videos you chose.',
            ),
          ),
        ],
      ),
    );
  }
}
