import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/verse_text_cache.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';

TranslationSpanEntry _span(String text, {List<int> words = const []}) =>
    TranslationSpanEntry(
      text: text,
      supplied: false,
      words: [
        for (final position in words)
          TranslationWordEntry(chapter: 1, verse: 1, position: position),
      ],
    );

void main() {
  testWidgets('English-only rows read the translation, highlighting the word '
      'that renders the looked-up one', (tester) async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(send: sent.add);
    addTearDown(cache.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OccurrenceVerseRow(
            cache: cache,
            displayRef: 'Gen 1:1',
            bookIndex: 0,
            chapter: 1,
            verse: 1,
            highlightWords: const [],
            positions: const [1],
            englishOnly: true,
            useEnglishBookNames: true,
          ),
        ),
      ),
    );
    await tester.pump();

    assignRustSignal['VerseTexts']!(
      VerseTexts(
        requestId: sent.single.requestId,
        englishOnly: true,
        verses: [
          VerseTextEntry(
            book: 1,
            chapter: 1,
            verse: 1,
            text: 'in-beginning created God',
            glossWords: const ['in-beginning', 'created', 'God'],
            sourceWords: const ['בְּרֵאשִׁית', 'בָּרָא', 'אֱלֹהִים'],
            translation: [
              _span('In the beginning', words: [0]),
              _span(', '),
              _span('God', words: [2]),
              _span(' '),
              _span('created', words: [1]),
              _span('.'),
            ],
          ),
        ],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    // One pump for the reply stream to deliver, one for the row to rebuild.
    await tester.pump();
    await tester.pump();

    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    final root = text.textSpan!;
    expect(root.toPlainText(), 'Genesis 1:1  In the beginning, God created.');
    final highlighted = [
      for (final span in root.children!.cast<TextSpan>())
        if (span.style?.backgroundColor != null) span.text,
    ];
    expect(highlighted, ['created']);
  });
}
