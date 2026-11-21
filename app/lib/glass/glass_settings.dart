import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local visual preferences only, never account/privacy capability switches.
class GlassSettings extends ChangeNotifier {
  double transparency = .5;
  bool reduced = false;
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    transparency = (p.getDouble('glass_transparency') ?? .5).clamp(0, 1);
    reduced = p.getBool('glass_reduced') ?? false;
    notifyListeners();
  }
  Future<void> setTransparency(double value) async {
    transparency = value.clamp(0, 1);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('glass_transparency', transparency);
  }
  Future<void> setReduced(bool value) async {
    reduced = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('glass_reduced', reduced);
  }
}
final glassSettings = GlassSettings();
