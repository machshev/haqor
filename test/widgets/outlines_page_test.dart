import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/outlines.dart';
import 'package:haqor/src/widgets/outlines_page.dart';

const _psalms = 27;

OutlineSectionEntry _section(
  String title, {
  int? parent,
  required int chapter,
  int? lastChapter,
  int lastVerse = 20,
  String subtitle = '',
  String superscription = '',
  Map<String, List<String>> facts = const {},
}) => OutlineSectionEntry(
  parent: parent,
  book: _psalms,
  chapter: chapter,
  verse: 1,
  lastBook: _psalms,
  lastChapter: lastChapter ?? chapter,
  lastVerse: lastVerse,
  title: title,
  subtitle: subtitle,
  superscription: superscription,
  note: '',
  facts: [
    for (final MapEntry(:key, :value) in facts.entries)
      OutlineFactEntry(facet: key, values: value),
  ],
);

/// Two books of the Psalms, the second with two collections.
OutlineEntry _outline() => OutlineEntry(
  key: 'psalms',
  title: 'The Psalms',
  note: 'Five books.',
  facets: [
    OutlineFacetEntry(key: 'author', title: 'Author'),
    OutlineFacetEntry(key: 'kind', title: 'Kind'),
  ],
  sections: [
    _section('Book One', chapter: 1, lastChapter: 2),
    _section(
      'Psalm 1',
      parent: 0,
      chapter: 1,
      subtitle: 'The two ways',
      facts: {
        'author': ['Unnamed'],
      },
    ),
    _section(
      'Psalm 2',
      parent: 0,
      chapter: 2,
      facts: {
        'author': ['David'],
      },
    ),
    _section('Book Two', chapter: 50, lastChapter: 52),
    _section('Of Asaph', parent: 3, chapter: 50),
    _section(
      'Psalm 50',
      parent: 4,
      chapter: 50,
      superscription: 'A psalm of Asaph.',
      facts: {
        'author': ['Asaph'],
        'kind': ['Psalm'],
      },
    ),
    _section('Of David', parent: 3, chapter: 51, lastChapter: 52),
    _section(
      'Psalm 51',
      parent: 6,
      chapter: 51,
      subtitle: 'Create in me a clean heart',
      superscription: 'A psalm of David, when Nathan the prophet came to him.',
      facts: {
        'author': ['David'],
        'kind': ['Psalm'],
      },
    ),
    _section(
      'Psalm 52',
      parent: 6,
      chapter: 52,
      facts: {
        'author': ['David'],
        'kind': ['Maskil'],
      },
    ),
  ],
);

OutlinesStore _store() => OutlinesStore()..set([_outline()]);

void main() {
  group('OutlineTree', () {
    final tree = OutlineTree(_outline());

    test('knows its leaves and the path to each', () {
      expect(tree.top, [0, 3]);
      expect(tree.leaves, [1, 2, 5, 7, 8]);
      expect(tree.pathTo(7), [3, 6, 7]);
    });

    test('finds what surrounds a chapter', () {
      expect(tree.pathAround(_psalms, 51, 51), [3, 6, 7]);
      // Two collections: only the book holds both.
      expect(tree.pathAround(_psalms, 50, 51), [3]);
      expect(tree.leavesTouching(_psalms, 50, 51), [5, 7]);
      expect(tree.touches(_psalms, 30, 40), isFalse);
      expect(tree.touches(1, 1, 1), isFalse);
    });

    test('counts each value of a facet, most first', () {
      expect(tree.valuesOf('author'), [
        ('David', 3),
        ('Unnamed', 1),
        ('Asaph', 1),
      ]);
    });
  });

  test('names passages', () {
    final s = _section('Psalm 51', chapter: 51);
    expect(outlinePassageLabel(s, useEnglish: true), 'Psalms 51:1–20');
    expect(
      outlinePassageLabel(s, useEnglish: true, wholeChapters: true),
      'Psalms 51',
    );
    final across = OutlineSectionEntry(
      parent: null,
      book: 2,
      chapter: 20,
      verse: 1,
      lastBook: 4,
      lastChapter: 10,
      lastVerse: 10,
      title: 'The law',
      subtitle: '',
      superscription: '',
      note: '',
      facts: const [],
    );
    expect(
      outlinePassageLabel(across, useEnglish: true),
      'Exodus 20:1–Numbers 10:10',
    );
  });

  testWidgets('the index filters by facet and opens a psalm', (tester) async {
    final opened = <(int, int, int)>[];
    final tree = _store().trees.single;
    await tester.pumpWidget(
      MaterialApp(
        home: OutlinePage(
          tree: tree,
          initialView: OutlineView.list,
          useEnglishBookNames: true,
          onNavigateToPassage: (b, c, v) => opened.add((b, c, v)),
        ),
      ),
    );
    expect(find.text('5 of 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('outline-facet-author-David')));
    await tester.pumpAndSettle();
    expect(find.text('3 of 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('outline-facet-kind-Psalm')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 5'), findsOneWidget);
    expect(
      find.text('A psalm of David, when Nathan the prophet came to him.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('outline-section-psalms-7')));
    expect(opened, [(_psalms - 1, 51, 1)]);

    await tester.tap(find.byKey(const ValueKey('outline-facet-kind-Psalm')));
    await tester.enterText(
      find.byKey(const ValueKey('outline-search')),
      'two ways',
    );
    await tester.pumpAndSettle();
    expect(find.text('0 of 5'), findsOneWidget);
  });

  testWidgets('the structure unfolds, and opens on a section', (tester) async {
    final tree = _store().trees.single;
    await tester.pumpWidget(MaterialApp(home: OutlinePage(tree: tree)));
    expect(
      find.byKey(const ValueKey('outline-section-psalms-1')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('outline-group-psalms-0')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('outline-section-psalms-1')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OutlinePage(
          key: const ValueKey('at'),
          tree: tree,
          initialSection: 7,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('outline-section-psalms-7')).first,
    );
    expect(tile.selected, isTrue);
  });

  testWidgets('a chapter shows where it stands', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterOutlinesSheet(
            store: _store(),
            bookIndex: _psalms - 1,
            chapter: 51,
            lastChapter: 51,
            useEnglishBookNames: true,
          ),
        ),
      ),
    );
    expect(find.text('The Psalms'), findsOneWidget);
    expect(find.text('Book Two › Of David'), findsOneWidget);
    expect(
      find.text('A psalm of David, when Nathan the prophet came to him.'),
      findsOneWidget,
    );
    expect(find.text('David'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterOutlinesSheet(
            key: const ValueKey('genesis'),
            store: _store(),
            bookIndex: 0,
            chapter: 1,
            lastChapter: 1,
          ),
        ),
      ),
    );
    expect(find.text('No book outline covers these chapters.'), findsOneWidget);
  });
}
