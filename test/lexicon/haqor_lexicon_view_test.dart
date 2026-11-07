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

Future<void> _openTab(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find.byType(Tab),
      matching: find.textContaining(RegExp('^$name')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the distilled entry first, then its evidence', (
    tester,
  ) async {
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: _draft())));
    // The overview: gloss, summary, and an outline of what the entry holds.
    expect(find.text('say, speak'), findsOneWidget);
    expect(find.text('The ordinary verb of saying.'), findsOneWidget);
    expect(find.text('Creation by word'), findsOneWidget);
    expect(find.text('Word of God'), findsOneWidget);
    expect(find.text('Words (1)'), findsOneWidget);
    expect(find.text('Cognates (1)'), findsOneWidget);
    expect(find.text('Doctrine (2)'), findsOneWidget);
    // A lone word opens without a click.
    await _openTab(tester, 'Words');
    expect(find.text('Qal'), findsOneWidget);
    expect(find.text('Genesis 1:3'), findsWidgets);
    expect(find.text('Esther 1:10–11'), findsOneWidget);
    await _openTab(tester, 'Cognates');
    expect(find.text('Arabic'), findsOneWidget);
    // Readers never see the editor's note or the edit controls.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('a verse chip opens the verse', (tester) async {
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: _draft())));
    await _openTab(tester, 'Words');
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

  testWidgets('shows Aramaic words and the sound a sense goes with', (
    tester,
  ) async {
    final data = jsonDecode(_entry) as Map<String, dynamic>;
    final cognate = (data['cognates'] as List).first as Map<String, dynamic>;
    cognate['id'] = 'ar-amara';
    cognate['sounds'] = {'ע': 'ġ'};
    (data['words'] as List).add({
      'lemma': 'אֶמַר',
      'lang': 'syc',
      'root': 'אמר',
      'pos': 'verb',
      'gloss': 'say',
      'cognate_ids': ['ar-amara'],
      'stems': [
        {
          'stem': 'peal',
          'gloss': 'say',
          'senses': [
            {
              'gloss': 'say',
              'definition': 'Speak.',
              'evidence': [
                {'ref': 'Rom.10.6'},
              ],
            },
          ],
        },
      ],
    });
    final entry = LexiconEntryDraft(
      id: 'amar',
      data: data,
      verses: const {
        'Rom.10.6': LexiconVerse(
          reference: 'Rom.10.6',
          book: 45,
          chapter: 10,
          verse: 6,
          original: 'μὴ εἴπῃς ἐν τῇ καρδίᾳ σου',
          english: 'Do not say in your heart',
          peshitta: 'דלא תאמר בלבך',
        ),
      },
    );
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: entry)));
    await _openTab(tester, 'Words');
    expect(find.text('Peshitta Syriac · root אמר'), findsOneWidget);
    await tester.tap(find.text('אֶמַר'));
    await tester.pumpAndSettle();
    expect(find.text('Peal'), findsOneWidget);
    expect(find.text('ע ġ · Arabic أَمَرَ'), findsOneWidget);
    await tester.tap(find.text('Romans 10:6'));
    await tester.pumpAndSettle();
    expect(find.text('דלא תאמר בלבך'), findsOneWidget);
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Cognates');
    expect(find.text('ע = ġ'), findsOneWidget);
  });

  testWidgets('marks a Greek loan', (tester) async {
    final data = jsonDecode(_entry) as Map<String, dynamic>;
    ((data['words'] as List).first as Map<String, dynamic>)['greek'] = [
      {
        'lemma': 'ἀρραβών',
        'gloss': 'pledge',
        'relation': 'loan',
        'evidence': [
          {'ref': 'Gen.1.3'},
        ],
      },
    ];
    final entry = LexiconEntryDraft(id: 'amar', data: data, verses: const {});
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: entry)));
    await _openTab(tester, 'Words');
    expect(find.text('ἀρραβών'), findsOneWidget);
    expect(find.text('loan'), findsOneWidget);
  });
  testWidgets('shows a word'
      's evidence counted', (tester) async {
    final entry = LexiconEntryDraft(
      id: 'amar',
      data: jsonDecode(_entry) as Map<String, dynamic>,
      verses: const {},
      support: const [
        {
          'lemma': 'אָמַר',
          'uses': 45,
          'cited': 20,
          'defining': 8,
          'cognates': {
            'sharing': <String>[],
            'sharing_languages': 0,
            'differing': ['Arabic أَثَرٌ (footstep)'],
            'differing_languages': 1,
            'possible': <String>[],
            'balance': -2,
          },
          'kin': [
            {
              'sense': 'אָשַׁר piel: call happy',
              'uses': 15,
              'cited': 7,
              'defining': 2,
              'cognates': 0,
            },
          ],
          'senses': <Object>[],
        },
      ],
    );
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: entry)));
    await _openTab(tester, 'Words');
    expect(
      find.textContaining(
        '45 uses · 20 verses (8 defining) · cognates: 0 for, 1 against',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('balance -2 · 1 kin sense', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Arabic أَثَرٌ (footstep)', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'אָשַׁר piel: call happy — 15 uses, 7 verses (2 defining), 0 cognates',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
  testWidgets('words open on a click, or from the overview', (tester) async {
    final data = jsonDecode(_entry) as Map<String, dynamic>;
    (data['words'] as List).add({
      'lemma': 'אֵמֶר',
      'pos': 'noun',
      'gender': 'm',
      'gloss': 'utterance',
      'senses': [
        {'gloss': 'speech', 'definition': 'What is said.'},
      ],
    });
    final entry = LexiconEntryDraft(id: 'amar', data: data, verses: const {});
    await tester.pumpWidget(_host(HaqorLexiconEntryView(entry: entry)));
    // The overview lists both words; a tap opens that one in Words.
    expect(find.text('utterance'), findsOneWidget);
    await tester.tap(find.text('utterance'));
    await tester.pumpAndSettle();
    expect(find.text('What is said.'), findsOneWidget);
    // The other word stays closed, its outline showing what it holds.
    expect(find.text('Qal · 1 sense'), findsOneWidget);
    expect(find.text('Utter words to someone.'), findsNothing);
    await tester.tap(find.text('Qal · 1 sense'));
    await tester.pumpAndSettle();
    expect(find.text('Utter words to someone.'), findsOneWidget);
    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.text('Utter words to someone.'), findsNothing);
    expect(find.text('What is said.'), findsNothing);
  });
}
