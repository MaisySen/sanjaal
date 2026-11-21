import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui.dart' show brandRed;

/// Liquid Glass settings. Follows the AppPrefs pattern in ui.dart: a
/// ChangeNotifier held in a global, loaded once at startup, saved to
/// SharedPreferences on every change.
///
/// How Reduce Transparency works here, stated plainly: Flutter exposes
/// Increase Contrast through MediaQuery.highContrast, but it exposes no
/// Reduce Transparency media query at all. There is no platform value to
/// read for it. So the mechanism is this setting: `reduceGlass` is the
/// in-app Reduce Transparency switch, persisted under `glass_reduced`.
/// When it is on, every glass surface degrades to a solid surface. When
/// the user turns it on, GlassMaterial also stops blurring, so nothing
/// behind the surface shows through. The slider is the iOS 27 continuous
/// transparency control: 0.0 ultra clear, 1.0 fully tinted, default 0.5,
/// which is the middle of the system slider. The slider never drops below
/// the contrast floor in GlassTokens, so the clear end is still legible.
class GlassSettings extends ChangeNotifier {
  double transparency = 0.5;
  bool reduceGlass = false;
  bool ready = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    transparency = (p.getDouble('glass_transparency') ?? 0.5).clamp(0.0, 1.0);
    reduceGlass = p.getBool('glass_reduced') ?? false;
    ready = true;
    notifyListeners();
  }

  Future<void> setTransparency(double value) async {
    transparency = value.clamp(0.0, 1.0);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('glass_transparency', transparency);
  }

  Future<void> setReduceGlass(bool value) async {
    reduceGlass = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('glass_reduced', reduceGlass);
  }
}

final glassSettings = GlassSettings();

/// A settings row for the Liquid Glass section of Settings. Shows the
/// transparency slider with Ultra clear and Fully tinted ends, and the
/// Reduce glass switch. Drop it into SettingsPage as one widget.
class GlassSettingsRow extends StatelessWidget {
  const GlassSettingsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context);
    return ListenableBuilder(
      listenable: glassSettings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Liquid Glass', style: s.textTheme.titleSmall),
          ),
          ListTile(
            leading: const Icon(Icons.blur_on_outlined),
            title: const Text('Transparency'),
            subtitle: Slider(
              value: glassSettings.transparency,
              onChanged: glassSettings.setTransparency,
              min: 0.0,
              max: 1.0,
              activeColor: brandRed,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Ultra clear'), Text('Fully tinted')],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.contrast_outlined),
            title: const Text('Reduce glass'),
            subtitle: const Text('Solid surfaces instead of glass'),
            value: glassSettings.reduceGlass,
            activeThumbColor: brandRed,
            onChanged: glassSettings.setReduceGlass,
          ),
        ],
      ),
    );
  }
}
