import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/tutor/progress_sync.dart';

// `FilledButton.icon` is a subclass, which `byType` would not match.
Finder button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

void main() {
  testWidgets('turning sync off with "Save & sync now" frees the buttons', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProgressSyncSettings(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save & sync now'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic study and progress sync is off.'), findsOne);
    expect(
      tester.widget<ButtonStyleButton>(button('Save & sync now')).onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNotNull,
    );
  });
}
