import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/request_failure.dart';
import 'package:haqor/src/tutor/study_settings.dart';

void _fail(String request, String message) =>
    assignRustSignal['RequestFailed']!(
      RequestFailed(
        request: request,
        key: '',
        message: message,
      ).bincodeSerialize(),
      Uint8List(0),
    );

void main() {
  Future<List<Object>> open(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showStudySettings(context, sendRequest: sent.add),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    return sent;
  }

  testWidgets('settings that cannot be loaded show the error and retry', (
    tester,
  ) async {
    final sent = await open(tester);
    expect(sent.single, isA<GetTutorSettings>());

    _fail(requestTutorSettings, 'database is locked');
    await tester.pump();
    expect(find.textContaining('database is locked'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<GetTutorSettings>(), hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings that never arrive stop spinning', (tester) async {
    await open(tester);
    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a change that was not saved is reported', (tester) async {
    await open(tester);
    assignRustSignal['TutorSettings']!(
      const TutorSettings(
        lettersPerBatch: 3,
        wordsPerBatch: 8,
        grammarGating: true,
        vocabPriority: 75,
        grammarPriority: 25,
        versePriority: 25,
        lettersRatio: 30,
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);

    _fail(requestSetTutorSettings, 'database is locked');
    await tester.pump();
    expect(find.textContaining('not saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resetting progress asks Rust to reset and then to sync', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final sent = await open(tester);
    assignRustSignal['TutorSettings']!(
      const TutorSettings(
        lettersPerBatch: 3,
        wordsPerBatch: 8,
        grammarGating: true,
        vocabPriority: 75,
        grammarPriority: 25,
        versePriority: 25,
        lettersRatio: 30,
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reset progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pump();
    expect(sent.whereType<ResetTutor>(), hasLength(1));
    // The sync it schedules runs after a short quiet period.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the fresh reply replaces the settings the sheet opened with', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    TutorSettings settings(int letters) => TutorSettings(
      lettersPerBatch: letters,
      wordsPerBatch: 8,
      grammarGating: true,
      vocabPriority: 75,
      grammarPriority: 25,
      versePriority: 25,
      lettersRatio: 30,
    );
    // What an earlier visit left behind, now out of date.
    assignRustSignal['TutorSettings']!(
      settings(3).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    final sent = await open(tester);
    expect(sent.single, isA<GetTutorSettings>());

    assignRustSignal['TutorSettings']!(
      settings(5).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(sent.whereType<SetTutorSettings>().single.lettersPerBatch, 5);

    // The deferred progress sync runs after a short quiet period.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
}
