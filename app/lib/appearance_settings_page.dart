import 'package:material_ui/material_ui.dart';

import 'glass/glass_settings.dart';
import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'ui.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});
  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  bool saving = false;
  bool failed = false;
  Future<void> choose(ThemeMode mode) async {
    if (saving) return;
    setState(() {
      saving = true;
      failed = false;
    });
    try {
      await prefs.setMode(mode);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: prefs,
    builder: (context, _) => Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Appearance'))),
      body: ListView(
        children: [
          if (saving) const LinearProgressIndicator(),
          if (failed)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  t_(
                    'Appearance changed for now, but could not be saved. Choose it again to retry.',
                  ),
                ),
              ),
            ),
          for (final item in [
            (ThemeMode.system, 'System'),
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
          ])
            ListTile(
              title: Text(t_(item.$2)),
              trailing: prefs.mode == item.$1 ? const PhIcon('check') : null,
              onTap: saving ? null : () => choose(item.$1),
            ),
          ListenableBuilder(
            listenable: glassSettings,
            builder: (context, _) => Column(
              children: [
                const Divider(height: 24),
                ListTile(
                  title: Text(t_('Transparency')),
                  subtitle: Slider(
                    value: glassSettings.transparency,
                    onChanged: glassSettings.setTransparency,
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t_('Ultra clear')),
                      Text(t_('Fully tinted')),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: Text(t_('Reduce glass')),
                  subtitle: Text(t_('Solid surfaces instead of glass')),
                  value: glassSettings.reduced,
                  onChanged: glassSettings.setReduced,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
