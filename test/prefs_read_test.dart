import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/app_settings.dart';
import 'package:haqor/src/prefs_read.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('an int saved where a double is read comes back as a double', () async {
    SharedPreferences.setMockInitialValues({'a': 0, 'b': 2.5});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.readDouble('a'), 0.0);
    expect(prefs.readDouble('b'), 2.5);
    expect(prefs.readDouble('missing'), isNull);
  });

  test('a value of the wrong type reads as unset', () async {
    SharedPreferences.setMockInitialValues({
      's': 'text',
      'n': 3,
      'l': ['x'],
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.readBool('s'), isNull);
    expect(prefs.readInt('s'), isNull);
    expect(prefs.readString('n'), isNull);
    expect(prefs.readStringList('s'), isNull);
    expect(prefs.readString('l'), isNull);
    expect(prefs.readStringList('l'), ['x']);
  });

  test('a font size snaps to the nearest menu choice', () {
    expect(snapFontSize(18), 16.0);
    expect(snapFontSize(18.5), 20.0);
    expect(snapFontSize(2), 13.0);
    expect(snapFontSize(99), 28.0);
    expect(snapFontSize(24), 24.0);
    expect(snapFontSize(null), 20.0);
    expect(snapFontSize(double.nan), 20.0);
  });
}
