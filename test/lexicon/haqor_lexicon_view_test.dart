import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/lexicon/haqor_lexicon_store.dart';
import 'package:haqor/src/lexicon/haqor_lexicon_view.dart';

const _entry = '''
{
  "id": "amar",
  "root": "אמר",
  "status": "draft",
  "updated": "2026-11-06",
  "tags": ["speech"],
  "gloss": "say, speak",
  "summary": "The ordinary verb of saying.",
  "words": [
    {
      "lemma": "אָמַר",
      "pos": "verb",
      "gloss": "say",
      "stems": [
        {
          "stem": "qal",
          "gloss": "say, speak",
          "senses": [
            {
              "gloss": "say",
              "definition": "Utter words to someone.",
              "evidence": [
                { "ref": "Gen.1.3", "role": "defining", "note": "God said." },
                { "ref": "Est.1.10", "to": "Est.1.11" }
              ]
            }
          ]
        }
      ]
    }
  ],
  "cognates": [
    {
      "lang": "ar",
      "form": "أَمَرَ",
      "translit": "ʾamara",
      "gloss": "command",
      "relation": "cognate",
      "evidence": [{ "source": "lane", "locator": "p. 95" }]
    }
  ],
  "doctrine": [
    {
      "topic": "word-of-god",
      "statement": "His word is refined.",
      "evidence": [{ "ref": "Gen.1.3" }]
    },
    {
      "topic": "creation-by-word",
      "statement": "God said, and it was.",
      "evidence": [{ "ref": "Gen.1.3" }]
    }
  ]
}
''';

LexiconEntryDraft _draft() => LexiconEntryDraft(
  id: 'amar',
  data: jsonDecode(_entry) as Map<String, dynamic>,
  verses: const {
    'Gen.1.3': LexiconVerse(
      reference: 'Gen.1.3',
      book: 1,
      chapter: 1,
      verse: 3,
      original: 'וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר',
      english: 'Then God said, “Let there be light.”',
    ),
    'Est.1.10': LexiconVerse(
      reference: 'Est.1.10',
      book: 34,
      chapter: 1,
      verse: 10,
      original: 'אָמַר',
      english: 'he said',
    ),
    'Est.1.11': LexiconVerse(
      reference: 'Est.1.11',
      book: 34,
      chapter: 1,
      verse: 11,
      original: 'לְהָבִיא',
      english: 'to bring',
    ),
  },
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the distilled entry first, then its evidence', (
    tester,
  ) async {
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: _draft())));
    expect(find.text('say, speak'), findsWidgets);
    expect(find.text('The ordinary verb of saying.'), findsOneWidget);
    expect(find.text('Qal'), findsOneWidget);
    expect(find.text('Genesis 1:3'), findsWidgets);
    expect(find.text('Esther 1:10–11'), findsOneWidget);
    expect(find.text('Arabic'), findsOneWidget);
    expect(find.text('Creation by word'), findsOneWidget);
    expect(find.text('Word of God'), findsOneWidget);
    // Readers never see the editor's note or the edit controls.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('a verse chip opens the verse', (tester) async {
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: _draft())));
    await tester.tap(find.text('Genesis 1:3').first);
    await tester.pumpAndSettle();
    expect(find.text('Then God said, “Let there be light.”'), findsOneWidget);
    expect(find.text('Defines the sense'), findsOneWidget);
  });

  testWidgets('editing mode hands a tapped field to the editor', (
    tester,
  ) async {
    final edits = <String>[];
    await tester.pumpWidget(
      _host(
        HaqorLexiconEntryView(
          entry: _draft(),
          editing: true,
          onEdit: (node, key, {required label, multiline = false}) =>
              edits.add('$label:${node[key]}'),
        ),
      ),
    );
    await tester.tap(find.text('The ordinary verb of saying.'));
    expect(edits, ['summary:The ordinary verb of saying.']);
  });

  test('saves in the layout jq writes', () {
    final draft = _draft();
    expect(draft.encode(), startsWith('{\n  "id": "amar",\n  "root": "אמר",'));
  });

  test('reads scripts in their own direction', () {
    expect(directionOf('אָמַר'), TextDirection.rtl);
    expect(directionOf('أَمَرَ'), TextDirection.rtl);
    expect(directionOf('ܐܡܪ'), TextDirection.rtl);
    expect(directionOf('𐤀𐤌𐤓'), TextDirection.rtl);
    expect(directionOf('𐎀𐎎𐎗'), TextDirection.ltr);
    expect(directionOf('amāru'), TextDirection.ltr);
  });
}
