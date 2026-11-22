import 'package:material_ui/material_ui.dart';

import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'ui.dart';

/// Existing local language choice, also reachable before account creation.
class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});
  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  bool saving = false;
  bool failed = false;
  Future<void> choose(String language) async {
    if (saving) return;
    setState(() {
      saving = true;
      failed = false;
    });
    try {
      await prefs.setLang(language);
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
      appBar: ReviewedAppBar(title: Text(t_('Language'))),
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
                    'Language changed for now, but could not be saved. Choose it again to retry.',
                  ),
                ),
              ),
            ),
          for (final item in [('en', 'English'), ('ne', 'नेपाली')])
            ListTile(
              title: Text(item.$2),
              trailing: prefs.lang == item.$1 ? const PhIcon('check') : null,
              onTap: saving ? null : () => choose(item.$1),
            ),
        ],
      ),
    ),
  );
}
