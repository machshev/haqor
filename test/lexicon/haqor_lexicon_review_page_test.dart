import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/lexicon/haqor_lexicon_review_page.dart';
import 'package:haqor/src/lexicon/haqor_lexicon_store.dart';

String _json(String id, String root, String gloss, String status) =>
    '''
{
  "id": "$id",
  "root": "$root",
  "status": "$status",
  ${status == 'reviewed' ? '"reviewed": "2026-11-01",' : ''}
  "created": "${id == 'amar'
        ? '2026-11-01'
        : id == 'changed'
        ? '2026-11-02'
        : '2026-11-03'}",
  "updated": "${id == 'changed' ? '2026-11-05' : '2026-11-01'}",
  "gloss": "$gloss",
  "summary": "A summary.",
  "words": []
}
''';

/// Serves three entries (one draft, one signed off, one changed since its
/// sign-off) and records what is saved.
class _FakeStore extends HaqorLexiconStore {
  _FakeStore({
    this.accept = true,
    this.includeName = false,
    this.includeSharedName = false,
  });

  final bool accept;
  final bool includeName;

  /// Adds a name entry with the same id as the `amar` root entry.
  final bool includeSharedName;
  final saved = <String, Map<String, dynamic>>{};
  final loaded = <String>[];

  @override
  Future<LexiconReview> load() async => LexiconReview(
    entries: [
      for (final (id, root, gloss, status) in [
        ('amar', 'אמר', 'say, speak', 'draft'),
        ('ashar', 'אשׁר', 'right path', 'reviewed'),
        ('changed', 'דבר', 'word', 'reviewed'),
      ])
        LexiconEntryDraft(
          id: id,
          data:
              jsonDecode(
                    saved[id] == null
                        ? _json(id, root, gloss, status)
                        : jsonEncode(saved[id]),
                  )
                  as Map<String, dynamic>,
          verses: const {},
        ),
      if (includeName)
        LexiconEntryDraft(
          id: 'shifrah',
          data: {
            'id': 'shifrah',
            'name': 'שִׁפְרָה',
            'people': <String>[],
            'status': 'draft',
            'created': '2026-11-04',
            'updated': '2026-11-02',
            'gloss': 'midwife',
            'summary': 'A summary.',
          },
          verses: const {},
        ),
      if (includeSharedName)
        LexiconEntryDraft(
          id: 'amar',
          data: {
            'id': 'amar',
            'name': 'אִמֵּר',
            'people': <String>[],
            'status': 'draft',
            'created': '2026-11-04',
            'updated': '2026-11-02',
            'gloss': 'Immer',
            'summary': 'A summary.',
          },
          verses: const {},
        ),
    ],
    editable: true,
    dir: '/lexicon',
    error: '',
  );

  @override
  Future<LexiconEntryDraft> loadEntry(LexiconEntryDraft entry) async {
    loaded.add(entry.id);
    return entry;
  }

  @override
  Future<HaqorLexiconSaveStatus> save(LexiconEntryDraft entry) async {
    if (accept) saved[entry.id] = jsonDecode(entry.encode());
    return HaqorLexiconSaveStatus(
      id: entry.id,
      success: accept,
      message: accept ? 'Saved' : 'Refused: bad entry',
    );
  }
}

class _MobileStore extends HaqorLexiconStore {
  final decisions = <(String, String, String, bool)>[];

  LexiconEntryDraft entry() => LexiconEntryDraft(
    id: 'anan',
    data: {
      'id': 'anan',
      'root': 'עננ',
      'status': 'draft',
      'updated': '2026-11-01',
      'gloss': 'cloud',
      'summary': 'A cloud.',
      'words': [
        {
          'lemma': 'עָנָן',
          'pos': 'noun',
          'gloss': 'cloud',
          'senses': [
            {
              'gloss': 'cloud',
              'definition': 'A cloud in the sky.',
              'evidence': [],
            },
          ],
        },
      ],
      'doctrine': [],
    },
    verses: const {},
    mobileSourceHash: 'a' * 64,
  );

  @override
  Future<LexiconReview> load() async => LexiconReview(
    entries: [entry()],
    editable: false,
    dir: 'bundled database',
    error: '',
  );

  @override
  Future<LexiconEntryDraft> loadEntry(LexiconEntryDraft entry) async => entry;

  @override
  Future<HaqorLexiconSaveStatus> saveMobileReview(
    LexiconEntryDraft entry, {
    required String targetKind,
    String targetKey = '',
    String note = '',
    bool approved = false,
  }) async {
    decisions.add((targetKind, targetKey, note, approved));
    return HaqorLexiconSaveStatus(
      id: 'mobile-review:${entry.id}',
      success: true,
      message: 'Saved',
    );
  }
}

Future<void> _pump(WidgetTester tester, HaqorLexiconStore store) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: HaqorLexiconReviewPage(store: store, today: () => '2026-11-08'),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _listed(String id, {bool name = false}) =>
    find.byKey(ValueKey('lexicon-entry-${name ? 'name' : 'root'}:$id'));

void main() {
  testWidgets('phone approval records a decision without editing entry JSON', (
    tester,
  ) async {
    final store = _MobileStore();
    await _pump(tester, store);
    expect(
      find.byKey(const ValueKey('lexicon-mobile-approve')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('lexicon-mobile-approve')));
    await tester.pumpAndSettle();
    expect(store.decisions, [('entry', '', '', true)]);
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('phone note on an unnamed sense is attached to that sense', (
    tester,
  ) async {
    final store = _MobileStore();
    await _pump(tester, store);
    await tester.tap(find.text('Words (1)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Note on sense'));
    await tester.tap(find.text('Note on sense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Check the verse');
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(store.decisions, [
      ('sense', '/words/0/senses/0', 'Check the verse', false),
    ]);
    expect(find.text('Review notes (1)'), findsOneWidget);
  });

  testWidgets('loads details for the selected entry once', (tester) async {
    final store = _FakeStore();
    await _pump(tester, store);
    expect(store.loaded, ['amar']);

    await tester.tap(_listed('changed'));
    await tester.pumpAndSettle();
    await tester.tap(_listed('amar'));
    await tester.pumpAndSettle();
    expect(store.loaded, ['amar', 'changed']);
  });

  testWidgets('opens on the entries still to review, and filters', (
    tester,
  ) async {
    await _pump(tester, _FakeStore());

    expect(find.text('To review 2'), findsOneWidget);
    expect(find.text('Signed off 1'), findsOneWidget);
    expect(find.text('All 3'), findsOneWidget);
    expect(_listed('amar'), findsOneWidget);
    expect(_listed('changed'), findsOneWidget);
    expect(_listed('ashar'), findsNothing);
    expect(find.text('Changed since sign-off'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lexicon-filter-signedOff')));
    await tester.pumpAndSettle();
    expect(_listed('ashar'), findsOneWidget);
    expect(_listed('amar'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lexicon-filter-all')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lexicon-review-search')),
      'path',
    );
    await tester.pumpAndSettle();
    expect(_listed('ashar'), findsOneWidget);
    expect(_listed('amar'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lexicon-review-clear-search')));
    await tester.pumpAndSettle();
    expect(_listed('ashar'), findsOneWidget);
    expect(_listed('amar'), findsOneWidget);
    expect(_listed('changed'), findsOneWidget);
  });

  testWidgets('filters by entry type and sorts by creation and update date', (
    tester,
  ) async {
    await _pump(tester, _FakeStore(includeName: true));
    await tester.tap(find.byKey(const ValueKey('lexicon-filter-all')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lexicon-entry-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Names').last);
    await tester.pumpAndSettle();
    expect(_listed('shifrah', name: true), findsOneWidget);
    expect(_listed('amar'), findsNothing);
    expect(find.text('Lexicon: shifrah'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lexicon-entry-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All types').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lexicon-sort-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date created').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_listed('shifrah', name: true)).dy,
      lessThan(tester.getTopLeft(_listed('ashar')).dy),
    );
    expect(
      tester.getTopLeft(_listed('ashar')).dy,
      lessThan(tester.getTopLeft(_listed('changed')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('lexicon-sort-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last updated').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_listed('changed')).dy,
      lessThan(tester.getTopLeft(_listed('shifrah', name: true)).dy),
    );
  });

  testWidgets('a name and a root entry may share an id', (tester) async {
    await _pump(tester, _FakeStore(includeSharedName: true));
    await tester.tap(find.byKey(const ValueKey('lexicon-filter-all')));
    await tester.pumpAndSettle();
    expect(_listed('amar'), findsOneWidget);
    expect(_listed('amar', name: true), findsOneWidget);

    await tester.tap(_listed('amar', name: true));
    await tester.pumpAndSettle();
    await tester.tap(_listed('amar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lexicon-sort-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last updated').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed entry is marked as changed since sign-off', (
    tester,
  ) async {
    await _pump(tester, _FakeStore());
    await tester.tap(_listed('changed'));
    await tester.pumpAndSettle();
    expect(find.text('Changed since sign-off'), findsOneWidget);
    expect(find.byKey(const ValueKey('lexicon-sign-off')), findsOneWidget);
  });

  testWidgets('signs an entry off and saves it, dated, in place', (
    tester,
  ) async {
    final store = _FakeStore();
    await _pump(tester, store);

    expect(find.text('Draft'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lexicon-sign-off')));
    await tester.pumpAndSettle();

    final saved = store.saved['amar']!;
    expect(saved['status'], 'reviewed');
    expect(saved['reviewed'], '2026-11-08');
    expect(saved['updated'], '2026-11-01', reason: 'no edit, no new date');
    expect(saved.keys.take(6).toList(), [
      'id',
      'root',
      'status',
      'reviewed',
      'created',
      'updated',
    ]);
    expect(find.text('Signed off 2026-11-08'), findsOneWidget);
    expect(find.text('To review 1'), findsOneWidget);
    expect(find.text('Next: changed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lexicon-withdraw-sign-off')));
    await tester.pumpAndSettle();
    expect(store.saved['amar']!['status'], 'draft');
    expect(store.saved['amar']!.containsKey('reviewed'), isFalse);
    expect(find.text('To review 2'), findsOneWidget);
  });

  testWidgets('a refused sign-off leaves the entry as it was', (tester) async {
    await _pump(tester, _FakeStore(accept: false));
    await tester.tap(find.byKey(const ValueKey('lexicon-sign-off')));
    await tester.pumpAndSettle();
    expect(find.text('Refused: bad entry'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('To review 2'), findsOneWidget);
  });
}
