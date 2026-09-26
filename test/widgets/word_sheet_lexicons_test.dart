import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/lexicon_source.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';

/// The Lexicon tab lists every lexicon's entries for the word's root family —
/// BDB, Klein and Jastrow, on OT and NT words alike — and badges each with the
/// lexicon it comes from, so the reader can weigh them against each other.

const _klein = BdbSummary(
  headword: 'שָׁלוֹם',
  gloss: 'well-being, welfare',
  contentJson:
      '{"senses":[{"num":"1","definition":[{"t":"well-being."}]},'
      '{"num":"2","lang":"NH","definition":[{"t":"hello."}]}],'
      '"etymology":[{"t":"[From "},{"t":"שׁלם","rtl":true,"dref":"U01167"},'
      '{"t":". cp. Akka. "},{"t":"shalāmu","i":true},{"t":".]"}],'
      '"derivatives":[{"t":" "},{"t":"שְׁלוֹמִים","rtl":true}]}',
  posCategory: 'noun',
  source: 'klein',
  lang: '',
);

const _jastrow = BdbSummary(
  headword: 'שְׁלָם',
  gloss: 'perfection, soundness, health, peace',
  contentJson: '{"senses":[{"definition":[{"t":"peace."}]}]}',
  posCategory: 'noun',
  source: 'jastrow',
  lang: 'ch.',
);

const _bdb = BdbSummary(
  headword: 'שָׁלוֹם',
  gloss: 'completeness; soundness; welfare; peace',
  contentJson: '{"senses":[{"definition":[{"t":"peace."}]}]}',
  posCategory: 'noun',
  source: 'bdb',
  lang: '',
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required bool syriac,
  List<SedraSummary> sedraEntries = const [],
  void Function(GetDictionaryEntry)? onDictionaryRequest,
}) async {
  SharedPreferences.setMockInitialValues({
    'occurrence_verse_english_only': false,
  });
  final requests = <GetWordInfo>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 900,
          child: WordInfoSheet(
            word: syriac ? 'שְׁלָמָא' : 'שָׁלוֹם',
            syriac: syriac,
            useEnglishBookNames: true,
            sendInfoRequest: requests.add,
            sendOccurrencesRequest: (_) {},
            sendVerseTextsRequest: (_) {},
            sendDictionaryRequest: onDictionaryRequest,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  assignRustSignal['WordInfo']!(
    WordInfo(
      requestId: requests.last.requestId,
      found: true,
      word: syriac ? 'שְׁלָמָא' : 'שָׁלוֹם',
      root: 'שלם',
      gloss: 'peace',
      partOfSpeech: 'noun',
      gender: null,
      number: null,
      prefix: null,
      suffix: null,
      prepositions: null,
      article: false,
      vavCon: false,
      bdbEntries: const [_bdb, _klein, _jastrow],
      sedraEntries: sedraEntries,
      person: null,
      state: null,
      tense: null,
      form: null,
      roots: const [],
    ).bincodeSerialize(),
    Uint8List(0),
  );
  await tester.pumpAndSettle();
}

/// Tap the linked span reading [text]. Entry bodies are [SelectableText], whose
/// spans the text-range finders cannot reach, so the span's own recognizer is
/// fired — the last match, being the topmost preview's.
void tapLink(WidgetTester tester, String text) {
  TapGestureRecognizer? found;
  for (final widget in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    widget.textSpan?.visitChildren((span) {
      if (span is TextSpan && span.text == text && span.recognizer != null) {
        found = span.recognizer! as TapGestureRecognizer;
      }
      return true;
    });
  }
  expect(found, isNotNull, reason: 'no link reading $text');
  found!.onTap!();
}

void main() {
  testWidgets('each entry is badged with the lexicon it comes from', (
    tester,
  ) async {
    await _pumpSheet(tester, syriac: false);
    expect(find.byTooltip(LexiconSource.bdb.title), findsOneWidget);
    expect(find.byTooltip(LexiconSource.klein.title), findsOneWidget);
    expect(find.byTooltip(LexiconSource.jastrow.title), findsOneWidget);
    // Jastrow's Aramaic marker, spelled out for a reader who does not know
    // his abbreviations.
    expect(find.text('Aram.'), findsOneWidget);
    expect(find.byTooltip('Aramaic (Jastrow: ch.)'), findsOneWidget);
  });

  testWidgets("a Klein entry opens on its senses, periods and etymology", (
    tester,
  ) async {
    await _pumpSheet(tester, syriac: false);
    await tester.tap(find.text('well-being, welfare'));
    await tester.pumpAndSettle();
    expect(find.textContaining('well-being.'), findsOneWidget);
    // Klein dates the greeting sense as modern Hebrew.
    expect(find.text('NH'), findsOneWidget);
    expect(find.textContaining('Etymology'), findsOneWidget);
    expect(find.textContaining('shalāmu'), findsOneWidget);
    expect(find.textContaining('Derivatives'), findsOneWidget);
  });

  testWidgets('a Klein link opens the entry it names, and so on from there', (
    tester,
  ) async {
    final asked = <GetDictionaryEntry>[];
    await _pumpSheet(tester, syriac: false, onDictionaryRequest: asked.add);
    await tester.tap(find.text('well-being, welfare'));
    await tester.pumpAndSettle();

    tapLink(tester, 'שׁלם');
    await tester.pump();
    expect(asked, hasLength(1));
    expect(asked.single.source, 'klein');
    expect(asked.single.key, 'U01167');
    // The link's own text heads the preview while the entry is on its way.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    assignRustSignal['DictionaryEntry']!(
      DictionaryEntry(
        requestId: asked.single.requestId,
        found: true,
        entry: const BdbSummary(
          headword: 'שׁלם',
          gloss: 'to be complete',
          contentJson:
              '{"senses":[{"form":"Qal","senses":[{"definition":'
              '[{"t":"was whole."}]}]}],"derivatives":[{"t":" "},'
              '{"t":"שָׁלֵם","rtl":true,"dref":"U01168"}]}',
          posCategory: 'verb',
          source: 'klein',
          lang: '',
        ),
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(AlertDialog);
    expect(
      find.descendant(of: preview, matching: find.text('to be complete')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.textContaining('was whole.')),
      findsOneWidget,
    );

    // The preview's own links open a further preview over it.
    tapLink(tester, 'שָׁלֵם');
    await tester.pump();
    expect(asked.last.key, 'U01168');
    expect(asked.last.requestId, isNot(asked.first.requestId));
    assignRustSignal['DictionaryEntry']!(
      DictionaryEntry(
        requestId: asked.last.requestId,
        found: false,
        entry: null,
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNWidgets(2));
    expect(
      find.text('This entry is not in the installed dictionary.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('an NT word shows the other lexicons above its SEDRA tree', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      syriac: true,
      sedraEntries: const [
        SedraSummary(lexeme: 'שלמא', meaning: 'peace', isCurrent: true),
      ],
    );
    expect(find.byTooltip(LexiconSource.bdb.title), findsOneWidget);
    expect(find.byTooltip(LexiconSource.jastrow.title), findsOneWidget);
    expect(find.text('Root tree'), findsOneWidget);
  });

  test('an unknown or missing source reads as BDB', () {
    expect(LexiconSource.of(''), LexiconSource.bdb);
    expect(LexiconSource.of('klein'), LexiconSource.klein);
    expect(LexiconSource.of('jastrow'), LexiconSource.jastrow);
  });

  test('period markers are spelled out', () {
    expect(LexiconPeriodLabel.describe('PBH').$2, 'Post-biblical Hebrew');
    expect(LexiconPeriodLabel.describe('b. h.').$1, 'BH');
    expect(LexiconPeriodLabel.describe('ch. = h.').$1, 'Aram.');
    expect(LexiconPeriodLabel.of(''), isNull);
  });
}
