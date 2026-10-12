import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/word_search_page.dart';

WordSearchEntry _entry(
  String language,
  String headword, {
  String matched = 'headword',
  String root = '',
  String gloss = '',
  int occurrences = 1,
}) => WordSearchEntry(
  language: language,
  matched: matched,
  headword: headword,
  root: root,
  gloss: gloss,
  partOfSpeech: '',
  word: headword,
  forms: const [],
  lexeme: '',
  occurrences: occurrences,
);

void _answer(SearchWords request, List<WordSearchEntry> matches) {
  assignRustSignal['WordSearchResults']!(
    WordSearchResults(
      requestId: request.requestId,
      matches: matches,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

/// Pumps the page under a launcher that records what it closes with.
Future<(List<SearchWords>, List<WordSearchEntry?>)> _pump(
  WidgetTester tester,
) async {
  final requests = <SearchWords>[];
  final chosen = <WordSearchEntry?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            chosen.add(
              await Navigator.of(context).push(
                MaterialPageRoute<WordSearchEntry>(
                  builder: (_) => WordSearchPage(sendRequest: requests.add),
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (requests, chosen);
}

void main() {
  testWidgets('a query is asked for once typing pauses', (tester) async {
    final (requests, _) = await _pump(tester);
    final field = find.byKey(const ValueKey('word-search-field'));

    await tester.enterText(field, 'lo');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'love');
    expect(requests, isEmpty);
    await tester.pump(wordSearchDebounce);

    expect(requests.map((r) => r.query), ['love']);
  });

  testWidgets('matches are listed under their language, and one is chosen', (
    tester,
  ) async {
    final (requests, chosen) = await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('word-search-field')),
      'love',
    );
    await tester.pump(wordSearchDebounce);
    final agapao = _entry(
      'greek',
      'ἀγαπάω',
      matched: 'gloss',
      gloss: 'to love',
      occurrences: 143,
    );
    _answer(requests.single, [
      _entry(
        'hebrew',
        'אָהֵב',
        matched: 'gloss',
        root: 'אהב',
        gloss: 'love',
        occurrences: 214,
      ),
      agapao,
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Hebrew & Aramaic · Old Testament'), findsOneWidget);
    expect(find.text('Greek · New Testament'), findsOneWidget);
    expect(find.text('Aramaic · Peshitta'), findsNothing);
    expect(find.text('root אהב'), findsOneWidget);
    expect(find.text('214×'), findsOneWidget);

    await tester.tap(find.text('ἀγαπάω'));
    await tester.pumpAndSettle();
    expect(chosen.single?.headword, agapao.headword);
  });

  testWidgets('a reply to an earlier keystroke is not shown', (tester) async {
    final (requests, _) = await _pump(tester);
    final field = find.byKey(const ValueKey('word-search-field'));
    await tester.enterText(field, 'lov');
    await tester.pump(wordSearchDebounce);
    await tester.enterText(field, 'love');
    await tester.pump(wordSearchDebounce);
    expect(requests, hasLength(2));

    _answer(requests.first, [_entry('hebrew', 'לוֹא')]);
    // Still waiting for the newer reply, whose progress bar keeps running.
    await tester.pump();
    expect(find.text('לוֹא'), findsNothing);

    _answer(requests.last, const []);
    await tester.pumpAndSettle();
    expect(find.textContaining('No word of the text matches'), findsOneWidget);
  });

  testWidgets('an example fills the search', (tester) async {
    final (requests, _) = await _pump(tester);
    await tester.tap(find.text('shepherd'));
    await tester.pump(wordSearchDebounce);
    expect(requests.single.query, 'shepherd');
  });
}
