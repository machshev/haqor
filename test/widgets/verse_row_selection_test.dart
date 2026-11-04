import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/app_settings.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/verse_row.dart';

void main() {
  const entry = VerseEntry(
    verse: 1,
    text: 'בְּרֵאשִׁית בָּרָא אֱלֹהִים',
    glosses: ['in beginning', 'created', 'God'],
    morphologies: [],
    names: [],
    roots: [],
    ketivs: [],
    crossReferenceScores: [],
  );
  TranslationWordEntry at(int position) =>
      TranslationWordEntry(chapter: 1, verse: 1, position: position);
  final english = [
    TranslationSpanEntry(
      text: 'In the beginning',
      supplied: false,
      words: [at(0)],
    ),
    const TranslationSpanEntry(text: ' ', supplied: false, words: []),
    TranslationSpanEntry(text: 'God', supplied: false, words: [at(2)]),
    const TranslationSpanEntry(text: ' ', supplied: false, words: []),
    TranslationSpanEntry(text: 'created', supplied: false, words: [at(1)]),
  ];

  Future<
    ({List<(int, int)> source, List<List<TranslationWordEntry>> translation})
  >
  pump(WidgetTester tester, ReaderText readerText) async {
    final source = <(int, int)>[];
    final translation = <List<TranslationWordEntry>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseRow(
            entry: entry,
            isSelected: false,
            hebrewNumerals: false,
            onTap: () {},
            onWordTap: (_, _, _, _) {},
            readerText: readerText,
            translation: english,
            onTranslationWordTap: (_) {},
            onSourceWordsSelected: (first, last) => source.add((first, last)),
            onTranslationWordsSelected: translation.add,
          ),
        ),
      ),
    );
    return (source: source, translation: translation);
  }

  /// Drags the mouse over [direction]'s text, between the characters at
  /// [from] and [to] of its plain text.
  Future<void> drag(
    WidgetTester tester,
    TextDirection direction,
    int Function(String text) from,
    int Function(String text) to,
  ) async {
    final selectable = find.byWidgetPredicate(
      (w) => w is SelectableText && w.textDirection == direction,
    );
    final text = tester
        .widget<SelectableText>(selectable)
        .textSpan!
        .toPlainText(includeSemanticsLabels: false);
    final render = tester
        .state<EditableTextState>(
          find.descendant(of: selectable, matching: find.byType(EditableText)),
        )
        .renderEditable;
    Offset point(int offset) => render.localToGlobal(
      render.getLocalRectForCaret(TextPosition(offset: offset)).center,
    );
    final gesture = await tester.startGesture(
      point(from(text)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(point(to(text)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a highlight in the original snaps to the words it touches', (
    tester,
  ) async {
    final selected = await pump(tester, ReaderText.source);
    // From within בָּרָא to within אֱלֹהִים, cutting both short.
    await drag(
      tester,
      TextDirection.rtl,
      (text) => text.indexOf('בָּרָא') + 3,
      (text) => text.indexOf('אֱלֹהִים') + 2,
    );
    expect(selected.source, [(1, 2)]);

    // A click selects nothing.
    await tester.tap(find.byType(SelectableText));
    await tester.pumpAndSettle();
    expect(selected.source, [(1, 2)]);
  });

  testWidgets('a highlight in the English selects the words it renders', (
    tester,
  ) async {
    final selected = await pump(tester, ReaderText.english);
    // From within "beginning" to within "God".
    await drag(
      tester,
      TextDirection.ltr,
      (text) => text.indexOf('beginning') + 3,
      (text) => text.indexOf('God') + 1,
    );
    expect(selected.translation, [
      [at(0), at(2)],
    ]);
  });
}
