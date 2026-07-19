import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/reader_page.dart';
import 'package:haqor/src/widgets/verse_row.dart';

/// Answers [GetChapter] requests the way the Rust side would, but only when
/// the test asks for it, so tests can observe the exact frame where a chapter
/// lands in the sliver tree.
class _FakeRust {
  final List<GetChapter> pending = [];

  void onRequest(GetChapter request) => pending.add(request);

  /// Serialize-and-deliver every pending chapter through the same
  /// [assignRustSignal] entry point rinf uses for real signals.
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
          for (var v = 1; v <= 20; v++)
            VerseEntry(
              verse: v,
              text: 'ספר${request.book} פרק${request.chapter} פסוק$v '
                  'מלה מלה מלה מלה מלה מלה מלה מלה',
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

Finder _verse(int book, int chapter, int verse) => find.byWidgetPredicate(
  (w) =>
      w is VerseRow && w.entry.text.startsWith('ספר$book פרק$chapter פסוק$verse '),
);

Finder _anyVisibleVerse(WidgetTester tester) => find.byType(VerseRow).first;

Future<_FakeRust> _pumpReader(
  WidgetTester tester, {
  required int chapter,
}) async {
  SharedPreferences.setMockInitialValues({'book': 0, 'chapter': chapter});
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(home: BibleReaderPage(sendChapterRequest: rust.onRequest)),
  );
  await tester.pump();
  rust.deliverAll();
  await tester.pump();
  return rust;
}

/// Delivers all pending chapters and asserts that the first visible verse did
/// not move on screen — the core no-jump guarantee of the reader.
Future<void> _deliverExpectingNoShift(
  WidgetTester tester,
  _FakeRust rust,
) async {
  final anchor = _anyVisibleVerse(tester);
  final entryBefore = tester.widget<VerseRow>(anchor).entry;
  final topBefore = tester.getTopLeft(anchor);
  rust.deliverAll();
  await tester.pump();
  final after = find.byWidgetPredicate(
    (w) => w is VerseRow && identical(w.entry, entryBefore),
  );
  expect(after, findsOneWidget);
  expect(tester.getTopLeft(after), topBefore);
}

void main() {
  testWidgets('initial load shows the requested chapter with its divider', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 5);
    expect(_verse(1, 5, 1), findsOneWidget);
    expect(find.text('Bereshit 5'), findsOneWidget);
    rust.deliverAll(); // prefetched neighbours
    await tester.pump();
  });

  testWidgets('prepending the previous chapter does not shift content', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 5);
    // Neighbour prefetches (4 and 6) are pending. A first scroll tick asks
    // for the previous chapter; hold the response, then deliver it and
    // require the visible verse to stay exactly where it was.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
    await tester.pump();
    await _deliverExpectingNoShift(tester, rust);

    // The prepended chapter is really there: scrolling up reveals chapter 4.
    for (var i = 0; i < 30 && _verse(1, 4, 20).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pump();
      rust.deliverAll();
      await tester.pump();
    }
    expect(_verse(1, 4, 20), findsOneWidget);
  });

  testWidgets('scrolling forward across many chapters never shifts content', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 1);
    // Read forward through enough chapters to exceed the retained window.
    for (var i = 0; i < 120 && _verse(1, 10, 1).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();
      await _deliverExpectingNoShift(tester, rust);
    }
    expect(_verse(1, 10, 1), findsOneWidget);
  });

  testWidgets('scrolling backward across many chapters never shifts content', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 15);
    for (var i = 0; i < 120 && _verse(1, 8, 1).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pump();
      await _deliverExpectingNoShift(tester, rust);
    }
    expect(_verse(1, 8, 1), findsOneWidget);
  });
}
