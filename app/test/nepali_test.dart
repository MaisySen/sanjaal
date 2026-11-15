import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/ui.dart' show t_, prefs;

void main() {
  test('Nepali strings resolve, English is the fallback', () {
    prefs.lang = 'ne';
    expect(t_('Live rooms'), 'लाइभ कोठा');
    expect(t_('Move to listeners'), 'श्रोतामा सार्नुहोस्');
    expect(t_('A string with no translation'), 'A string with no translation');
    prefs.lang = 'en';
    expect(t_('Live rooms'), 'Live rooms');
  });
}
