import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/app_settings.dart';
import 'package:haqor/src/reading_presets.dart';

void main() {
  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WelcomeGate(child: Text('reader'))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a fresh install is asked about its Hebrew', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpGate(tester);
    expect(find.text('How familiar are you with Hebrew?'), findsOneWidget);
    expect(find.text('reader'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('welcome-newcomer')));
    await tester.pumpAndSettle();
    expect(find.text('reader'), findsOneWidget);

    // The preset's settings are saved as ordinary settings; which preset it
    // was is not, so nothing later overrides them.
    final prefs = await SharedPreferences.getInstance();
    final settings = readReadingSettings(prefs);
    expect(settings.readerText, ReaderText.english);
    expect(settings.englishBookNames, isTrue);
    expect(settings.hebrewNumerals, isFalse);
    expect(settings.glossInterlinear, isTrue);
    expect(await occurrenceVerseEnglishOnlyEnabled(), isTrue);
    expect(prefs.getKeys().where((key) => key.contains('preset')), isEmpty);
  });

  testWidgets('an existing install goes straight to the reader', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'book': 3});
    await pumpGate(tester);
    expect(find.text('reader'), findsOneWidget);
    expect(find.byType(WelcomePage), findsNothing);
  });

  test('settings with nothing saved are the Reading Hebrew preset', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = readReadingSettings(await SharedPreferences.getInstance());
    expect(settings.readerText, ReaderText.source);
    expect(settings.showCantillation, isTrue);
    expect(settings.glossInterlinear, isFalse);
  });

  test('a preset keeps the display settings', () {
    final large = kDefaultReadingSettings.copyWith(
      fontSize: 28,
      fontFamily: 'David Libre',
      readerLayoutMode: ReaderLayoutMode.focus,
    );
    final applied = ReadingPreset.learner.applyTo(large);
    expect(applied.fontSize, 28);
    expect(applied.fontFamily, 'David Libre');
    expect(applied.readerLayoutMode, ReaderLayoutMode.focus);
    expect(applied.glossInterlinear, isTrue);
    expect(applied.showCantillation, isFalse);
  });

  testWidgets('settings apply a preset once, on confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final applied = <AppReadingSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSettings(
              context,
              readingSettings: kDefaultReadingSettings.copyWith(fontSize: 24),
              onReadingSettingsChanged: applied.add,
              sendRequest: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-text-setting')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-tab-presets')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-preset-newcomer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(applied, isEmpty);

    await tester.tap(find.byKey(const ValueKey('settings-preset-newcomer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied.single.readerText, ReaderText.english);
    expect(applied.single.fontSize, 24);

    // The settings stay free to refine afterwards.
    await tester.tap(find.byKey(const ValueKey('settings-tab-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hebrew').first);
    await tester.pumpAndSettle();
    expect(applied.last.readerText, ReaderText.source);
    expect(applied.last.englishBookNames, isTrue);
  });
}
