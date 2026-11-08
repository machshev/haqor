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
  "updated": "${id == 'changed' ? '2026-11-05' : '2026-11-01'}",
  "gloss": "$gloss",
  "summary": "A summary.",
  "words": []
}
''';

/// Serves three entries (one draft, one signed off, one changed since its
/// sign-off) and records what is saved.
class _FakeStore extends HaqorLexiconStore {
  _FakeStore({this.accept = true});

  final bool accept;
  final saved = <String, Map<String, dynamic>>{};

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
    ],
    editable: true,
    dir: '/lexicon',
    error: '',
  );

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

Future<void> _pump(WidgetTester tester, _FakeStore store) async {
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

Finder _listed(String id) => find.byKey(ValueKey('lexicon-entry-$id'));

void main() {
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
    expect(saved.keys.take(5).toList(), [
      'id',
      'root',
      'status',
      'reviewed',
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
