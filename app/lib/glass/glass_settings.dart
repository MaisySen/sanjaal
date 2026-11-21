import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local visual preferences only, never account/privacy capability switches.
class GlassSettings extends ChangeNotifier {
  double transparency = .5;
  bool reduced = false;
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final nextTransparency = (p.getDouble('glass_transparency') ?? .5)
        .clamp(0, 1)
        .toDouble();
    final nextReduced = p.getBool('glass_reduced') ?? false;
    transparency = nextTransparency;
    reduced = nextReduced;
    notifyListeners();
  }

  Future<void>? _writes;
  int _saveRevision = 0;
  int _pendingWrites = 0;
  bool saveFailed = false;
  bool get saving => _pendingWrites > 0;

  /// Live slider preview is cheap and does not write on every movement.
  void previewTransparency(double value) {
    transparency = value.clamp(0, 1);
    notifyListeners();
  }

  Future<void> setTransparency(double value) {
    previewTransparency(value);
    return save();
  }

  Future<void> setReduced(bool value) {
    reduced = value;
    notifyListeners();
    return save();
  }

  /// Serialize captured snapshots so late platform completion cannot restore
  /// an older gesture. A failed write never poisons subsequent explicit saves.
  Future<void> save() {
    final nextTransparency = transparency;
    final nextReduced = reduced;
    final revision = ++_saveRevision;
    _pendingWrites++;
    saveFailed = false;
    notifyListeners();
    final previous = _writes;
    Future<void> write() async {
      if (previous != null) await previous;
      try {
        final p = await SharedPreferences.getInstance();
        final tintSaved = await p.setDouble(
          'glass_transparency',
          nextTransparency,
        );
        final reducedSaved = await p.setBool('glass_reduced', nextReduced);
        if (!tintSaved || !reducedSaved) {
          throw StateError('Glass preferences were not saved');
        }
      } catch (_) {
        if (revision == _saveRevision) saveFailed = true;
        rethrow;
      } finally {
        _pendingWrites--;
        if (_pendingWrites == 0) _writes = null;
        notifyListeners();
      }
    }

    final result = write();
    _writes = result.catchError((Object _) {});
    return result;
  }
}

final glassSettings = GlassSettings();
