import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Every plain string passed to t_() must have a Nepali entry, so Nepali mode never silently
/// shows English for a fixed label. Brand name is exempt.
void main() {
  test('every literal t_ string has a Nepali translation', () {
    final ui = File('lib/ui.dart').readAsStringSync();
    final keys = RegExp(r"^\s*'((?:[^'\\]|\\.)*)'\s*:\s*'", multiLine: true).allMatches(ui).map((m) => m.group(1)!.replaceAll(r"\'", "'")).toSet();
    final missing = <String>{};
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r"\bt_\(\s*'((?:[^'\\]|\\.)*)'\s*\)").allMatches(f.readAsStringSync())) {
        final k = m.group(1)!.replaceAll(r"\'", "'");
        if (k != 'Sanjaal' && !keys.contains(k)) missing.add('$k (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });
}
