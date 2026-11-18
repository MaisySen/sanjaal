import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Every plain string passed to t_() must have a Nepali entry, so Nepali mode never silently
/// shows English for a fixed label. Brand name is exempt.
void main() {
  test('every literal t_ string has a Nepali translation', () {
    final ui = File('lib/ui.dart').readAsStringSync();
    final keys = RegExp("^\\s*(?:'((?:[^'\\\\]|\\\\.)*)'|\"((?:[^\"\\\\]|\\\\.)*)\")\\s*:", multiLine: true).allMatches(ui).map((m) => (m.group(1) ?? m.group(2))!.replaceAll(r"\'", "'")).toSet();
    final missing = <String>{};
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r"\bt_\(\s*'((?:[^'\\]|\\.)*)'\s*\)").allMatches(f.readAsStringSync())) {
        final k = m.group(1)!.replaceAll(r"\'", "'");
        if (k != 'Sanjaal' && !keys.contains(k)) missing.add('$k (${f.path})');
      }
    }
    // Sentences with data slots go through tf_() and need an entry for the whole template.
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r"\btf_\(\s*'((?:[^'\\]|\\.)*)'").allMatches(f.readAsStringSync())) {
        final k = m.group(1)!.replaceAll(r"\'", "'");
        if (!keys.contains(k)) missing.add('$k (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });

  /// A literal shown as Text('Capitalised words') without t_() stays English in Nepali mode and no test notices.
  /// Brand and legal text are allowed; anything else must go through t_().
  test('no fixed English label is shown without t_()', () {
    const allowed = {'Sanjaal', 'DEMO DATA: test fixture, not live'};
    final bad = <String>{};
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.endsWith('ui.dart'))) {
      for (final m in RegExp(r"\bText\(\s*'([A-Z][a-z][^']*)'\s*[,)]").allMatches(f.readAsStringSync())) {
        final k = m.group(1)!;
        if (!allowed.contains(k) && !k.contains('Fintex')) bad.add('$k (${f.path})');
      }
    }
    expect(bad, isEmpty);
  });
}
