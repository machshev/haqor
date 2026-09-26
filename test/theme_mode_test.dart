import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/main.dart';
import 'package:haqor/src/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => themeMode.value = ThemeMode.system);

  test('an unset or unknown theme choice follows the system', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
    themeMode.value = ThemeMode.dark;
    await loadThemeMode();
    expect(themeMode.value, ThemeMode.system);
  });

  test('a chosen theme is saved and restored', () async {
    SharedPreferences.setMockInitialValues({});
    await setThemeMode(ThemeMode.dark);
    themeMode.value = ThemeMode.system;
    await loadThemeMode();
    expect(themeMode.value, ThemeMode.dark);
  });

  testWidgets('the app follows the chosen theme', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const Haqor(home: SizedBox()));
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(SizedBox))).brightness;

    expect(brightness(), Brightness.light);
    themeMode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
  });
}
