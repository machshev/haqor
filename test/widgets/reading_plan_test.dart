import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/reader_page.dart';

/// Answers [GetChapter] requests the way the Rust side would, so the reader
/// finishes its initial load and the app bar (with the reader menu) appears.
class _FakeRust {
  final List<GetChapter> pending = [];

  void onRequest(GetChapter request) => pending.add(request);

  void deliverAll() {
    final requests = List<GetChapter>.of(pending);
    pending.clear();
    for (final request in requests) {
      final response = ChapterText(
        book: request.book,
        chapter: request.chapter,
        syriac: request.syriac,
        includeGlosses: request.includeGlosses,
        includeNames: request.includeNames,
        verses: [
          for (var v = 1; v <= 5; v++)
            VerseEntry(
              verse: v,
              text: 'ספר${request.book} פרק${request.chapter} פסוק$v',
              glosses: const [],
              names: const [],
            ),
        ],
      );
      assignRustSignal['ChapterText']!(
        response.bincodeSerialize(),
        Uint8List(0),
      );
    }
  }
}

/// Pumps the reader with saved reading plans and opens the plan sheet.
Future<void> _openPlanSheet(
  WidgetTester tester, {
  required List<String> plans,
}) async {
  SharedPreferences.setMockInitialValues({
    'book': 0,
    'chapter': 1,
    'reading_plans': plans,
  });
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(home: BibleReaderPage(sendChapterRequest: rust.onRequest)),
  );
  await tester.pump();
  rust.deliverAll();
  await tester.pump();

  await tester.tap(find.byTooltip('More reader options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Reading plan'));
  await tester.pumpAndSettle();
}

Future<List<String>?> _savedPlans() async =>
    (await SharedPreferences.getInstance()).getStringList('reading_plans');

void main() {
  testWidgets('plan row shows progress stats', (tester) async {
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .millisecondsSinceEpoch;
    await _openPlanSheet(tester, plans: ['0|1,2,3@$yesterday']);
    expect(find.text('3/50 chapters'), findsOneWidget);
    expect(find.text('Next: chapter 4 · read yesterday'), findsOneWidget);
  });

  testWidgets('deleting a plan asks for confirmation first', (tester) async {
    await _openPlanSheet(tester, plans: ['0|1,2,3']);
    await tester.tap(find.byTooltip('Remove plan'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Bereshit?'), findsOneWidget);

    // Cancel keeps the plan, both on screen and on disk.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('3/50 chapters'), findsOneWidget);
    expect(await _savedPlans(), ['0|1,2,3']);

    // Confirming removes it.
    await tester.tap(find.byTooltip('Remove plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('3/50 chapters'), findsNothing);
    expect(find.text('Add a book to start a reading plan.'), findsOneWidget);
    expect(await _savedPlans(), isEmpty);
  });

  testWidgets('editing the position rewrites progress', (tester) async {
    await _openPlanSheet(tester, plans: ['0|1,2,3']);
    await tester.tap(find.byTooltip('Edit position'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Tap the chapter you want to read next'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('11')),
    );
    await tester.pumpAndSettle();
    expect(find.text('10/50 chapters'), findsOneWidget);
    expect(find.textContaining('Next: chapter 11'), findsOneWidget);
    expect(await _savedPlans(), ['0|1,2,3,4,5,6,7,8,9,10']);
  });

  testWidgets('mark all read completes the plan', (tester) async {
    await _openPlanSheet(tester, plans: ['0|1,2,3']);
    await tester.tap(find.byTooltip('Edit position'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(find.text('50/50 chapters'), findsOneWidget);
    expect(find.textContaining('Complete'), findsOneWidget);
    expect(find.byTooltip('Plan complete'), findsOneWidget);
  });

  testWidgets('timestamped storage round-trips', (tester) async {
    await _openPlanSheet(tester, plans: ['0|1@1700000000000,2']);
    expect(find.text('2/50 chapters'), findsOneWidget);
    // Editing back to chapter 2 keeps chapter 1's timestamp.
    await tester.tap(find.byTooltip('Edit position'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('2')),
    );
    await tester.pumpAndSettle();
    expect(await _savedPlans(), ['0|1@1700000000000']);
  });
}
