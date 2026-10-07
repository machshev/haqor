import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/app_settings.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/syntax_sheet.dart';

import '../syntax_tree_test.dart' show node;

/// Answers the panel's requests the way the Rust side would.
class _FakeRust {
  final List<GetSyntaxTrees> requests = [];
  final List<GetVerseTexts> verseRequests = [];

  /// Genesis 1:1, `[cl [pp:pp 0] 1:v 2:s [np:o 3 [np 4]]]`.
  void deliverTree() {
    final request = requests.last;
    assignRustSignal['SyntaxTrees']!(
      SyntaxTrees(
        requestId: request.requestId,
        book: request.book,
        chapter: request.chapter,
        verses: [
          VerseSyntaxEntry(
            verse: request.firstVerse,
            nodes: [
              node(-1, kind: 'cl'),
              node(0, kind: 'pp', role: 'pp'),
              node(1, position: 0),
              node(0, role: 'v', position: 1),
              node(0, role: 's', position: 2),
              node(0, kind: 'np', role: 'o'),
              node(5, position: 3),
              node(5, kind: 'np'),
              node(7, position: 4),
            ],
          ),
        ],
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

  void deliverNoTree() {
    final request = requests.last;
    assignRustSignal['SyntaxTrees']!(
      SyntaxTrees(
        requestId: request.requestId,
        book: request.book,
        chapter: request.chapter,
        verses: const [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

  void deliverWords() {
    final pending = List<GetVerseTexts>.of(verseRequests);
    verseRequests.clear();
    for (final request in pending) {
      assignRustSignal['VerseTexts']!(
        VerseTexts(
          requestId: request.requestId,
          englishOnly: request.englishOnly,
          verses: [
            for (final ref in request.refs)
              VerseTextEntry(
                book: ref.book,
                chapter: ref.chapter,
                verse: ref.verse,
                text: 'in-beginning created God the heavens',
                glossWords: const [
                  'in-beginning',
                  'created',
                  'God',
                  '',
                  'the heavens',
                ],
                sourceWords: const [
                  'בְּרֵאשִׁית',
                  'בָּרָא',
                  'אֱלֹהִים',
                  'אֵת',
                  'הַשָּׁמַיִם',
                ],
              ),
          ],
        ).bincodeSerialize(),
        Uint8List(0),
      );
    }
  }
}

Future<_FakeRust> _pump(
  WidgetTester tester, {
  SyntaxView view = SyntaxView.outline,
  ValueChanged<SyntaxView>? onViewChanged,
  void Function(String, int, String)? onWordTap,
}) async {
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SyntaxPanel(
          book: 1,
          chapter: 1,
          verse: 1,
          title: 'Genesis 1:1',
          initialView: view,
          onViewChanged: onViewChanged,
          onWordTap: onWordTap,
          sendRequest: rust.requests.add,
          sendVerseTextsRequest: rust.verseRequests.add,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return rust;
}

void main() {
  testWidgets('asks for one verse and outlines its constituents', (
    tester,
  ) async {
    final rust = await _pump(tester);
    final request = rust.requests.single;
    expect(
      (request.book, request.chapter, request.firstVerse, request.lastVerse),
      (1, 1, 1, 1),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    rust.deliverTree();
    rust.deliverWords();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('syntax-outline')), findsOneWidget);
    expect(find.text('Clause'), findsOneWidget);
    expect(find.text('Object · Noun phrase'), findsOneWidget);
    expect(find.text('Prepositional · Prep. phrase'), findsOneWidget);
    // A word standing alone as a constituent carries its role beneath it.
    expect(find.text('בָּרָא'), findsOneWidget);
    expect(find.text('created'), findsOneWidget);
    // Verb and Subject appear on their words as well as in the legend.
    expect(find.text('Subject'), findsNWidgets(2));
  });

  testWidgets('switches to the drawn tree and reports the choice', (
    tester,
  ) async {
    SyntaxView? chosen;
    final rust = await _pump(tester, onViewChanged: (v) => chosen = v);
    rust.deliverTree();
    rust.deliverWords();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    expect(chosen, SyntaxView.tree);
    expect(find.byKey(const ValueKey('syntax-tree')), findsOneWidget);
    expect(find.byKey(const ValueKey('syntax-outline')), findsNothing);
    expect(find.text('אֱלֹהִים'), findsOneWidget);
  });

  testWidgets('a tapped word reports the whole word and its position', (
    tester,
  ) async {
    final taps = <(String, int, String)>[];
    final rust = await _pump(
      tester,
      onWordTap: (word, position, gloss) => taps.add((word, position, gloss)),
    );
    rust.deliverTree();
    rust.deliverWords();
    await tester.pumpAndSettle();

    await tester.tap(find.text('אֱלֹהִים'));
    expect(taps, [('אֱלֹהִים', 2, 'God')]);
  });

  testWidgets('says so when a verse has no tree', (tester) async {
    final rust = await _pump(tester);
    rust.deliverNoTree();
    rust.deliverWords();
    await tester.pumpAndSettle();
    expect(find.text('No syntax tree for this verse.'), findsOneWidget);
  });
}
