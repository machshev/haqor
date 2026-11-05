import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/apologetics.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/apologetics_page.dart';

PassageSpan _span(
  int book,
  int chapter,
  int verse, [
  int? lastVerse,
  int? lastChapter,
]) => PassageSpan(
  book: book,
  chapter: chapter,
  verse: verse,
  lastChapter: lastChapter ?? chapter,
  lastVerse: lastVerse ?? verse,
);

ApologeticEntry _entry({
  required String key,
  required String subject,
  required String kind,
  required String title,
  required List<PassageSpan> passages,
  List<String> related = const [],
  List<String> topics = const [],
}) => ApologeticEntry(
  id: key.hashCode,
  key: key,
  subject: subject,
  kind: kind,
  title: title,
  summary: 'Why $title.',
  passages: passages,
  points: [
    ApologeticPointEntry(
      claim: 'A step of $title.',
      passages: [_span(43, 20, 17)],
      sources: [
        ApologeticSourceEntry(
          title: 'Annals',
          author: 'Tacitus',
          loc: '15.44',
          quote: '',
        ),
      ],
    ),
  ],
  objections: [
    ApologeticObjectionEntry(
      objection: 'An objection to $title.',
      answer: 'Its answer.',
      passages: const [],
    ),
  ],
  related: related,
  topics: topics,
);

/// The empty tomb (Matthew 28:1-15), and Luke 23:42-43; Luke 16:19-31 runs
/// on into chapter 17 here to test a passage carried into a chapter.
ApologeticsStore _store() => ApologeticsStore()
  ..set(
    [
      ApologeticSubjectEntry(
        key: 'resurrection',
        title: 'The resurrection of Jesus',
        note: 'The evidence.',
      ),
      ApologeticSubjectEntry(
        key: 'death',
        title: 'Death and the resurrection',
        note: 'Man is mortal.',
      ),
    ],
    [
      _entry(
        key: 'empty-tomb',
        subject: 'resurrection',
        kind: 'evidence',
        title: 'The tomb was empty',
        passages: [_span(40, 28, 1, 15)],
        related: ['luke-23-43'],
        topics: ['resurrection-evidence'],
      ),
      _entry(
        key: 'luke-23-43',
        subject: 'death',
        kind: 'passage',
        title: 'Luke 23:43, today in paradise',
        passages: [_span(42, 23, 42, 43)],
        topics: ['heaven-at-death'],
      ),
      _entry(
        key: 'luke-16-19',
        subject: 'death',
        kind: 'passage',
        title: 'The rich man and Lazarus',
        passages: [_span(42, 16, 19, 2, 17)],
        topics: ['heaven-at-death', 'hell'],
      ),
    ],
    topics: [
      ApologeticTopicEntry(key: 'resurrection-evidence', title: 'Evidence'),
      ApologeticTopicEntry(key: 'heaven-at-death', title: 'Heaven at death'),
      ApologeticTopicEntry(key: 'hell', title: 'Hell'),
    ],
    religions: [
      ApologeticReligionEntry(
        key: 'christianity',
        title: 'Christianity',
        note: 'Those who confess Jesus as Lord.',
      ),
      ApologeticReligionEntry(
        key: 'none',
        title: 'No religion',
        note: 'Begin from history.',
      ),
    ],
    audiences: [
      ApologeticAudienceEntry(
        key: 'catholic',
        religion: 'christianity',
        title: 'Catholics',
        note: 'Begin from the resurrection of the body.',
        agree: ['empty-tomb'],
        differ: ['luke-16-19', 'luke-23-43'],
      ),
      ApologeticAudienceEntry(
        key: 'orthodox',
        religion: 'christianity',
        title: 'Eastern Orthodox',
        note: 'Begin from the resurrection.',
        agree: [],
        differ: ['luke-23-43'],
      ),
      ApologeticAudienceEntry(
        key: 'sceptic',
        religion: 'none',
        title: 'Sceptics',
        note: 'Begin from the tomb.',
        agree: [],
        differ: ['empty-tomb'],
      ),
    ],
  );

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  test('verses are marked where a passage starts, or carries in', () {
    final store = _store();
    expect(store.markedAt(42, 23, 42).map((e) => e.key), ['luke-23-43']);
    expect(store.markedAt(42, 23, 43), isEmpty);
    expect(store.markedAt(42, 17, 1).map((e) => e.key), ['luke-16-19']);
    expect(store.touching(42, 17, 17).map((e) => e.key), ['luke-16-19']);
    expect(store.touching(40, 1, 27), isEmpty);
  });

  testWidgets('subjects expand to their entries; a kind or search opens all', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(ApologeticsPage(store: _store())));
    expect(find.text('The resurrection of Jesus'), findsOneWidget);
    expect(find.text('3 entries'), findsOneWidget);
    // Collapsed until tapped.
    final tomb = find.byKey(const ValueKey('apologetic-row-empty-tomb'));
    expect(tomb, findsNothing);
    final resurrection = find.byKey(
      const ValueKey('apologetics-group-subjects-resurrection'),
    );
    await tester.tap(resurrection);
    await tester.pump();
    expect(tomb, findsOneWidget);
    expect(
      find.byKey(const ValueKey('apologetic-row-luke-23-43')),
      findsNothing,
    );
    await tester.tap(resurrection);
    await tester.pump();
    expect(tomb, findsNothing);

    await tester.tap(find.byKey(const ValueKey('apologetics-kind-passage')));
    await tester.pump();
    expect(find.text('2 entries'), findsOneWidget);
    expect(tomb, findsNothing);
    expect(
      find.byKey(const ValueKey('apologetic-row-luke-23-43')),
      findsOneWidget,
    );
    // A subject with no match is not listed.
    expect(resurrection, findsNothing);

    await tester.tap(find.byKey(const ValueKey('apologetics-kind-all')));
    await tester.enterText(
      find.byKey(const ValueKey('apologetics-search')),
      'Luke 23',
    );
    await tester.pump();
    expect(find.text('1 entry'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('apologetic-row-luke-23-43')),
      findsOneWidget,
    );
  });

  testWidgets('topics list across subjects, an entry under each of its own', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(ApologeticsPage(store: _store())));
    await tester.tap(find.text('Topics'));
    await tester.pump();
    expect(find.text('Heaven at death'), findsOneWidget);
    expect(find.text('Hell'), findsOneWidget);
    expect(find.text('The rich man and Lazarus'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('apologetics-group-topics-hell')),
    );
    await tester.pump();
    expect(find.text('The rich man and Lazarus'), findsOneWidget);
    expect(find.text('Luke 23:43, today in paradise'), findsNothing);

    // Under two topics: listed under both, counted once.
    await tester.tap(
      find.byKey(const ValueKey('apologetics-group-topics-heaven-at-death')),
    );
    await tester.pump();
    expect(find.text('The rich man and Lazarus'), findsNWidgets(2));
    expect(find.text('3 entries'), findsOneWidget);
  });

  testWidgets(
    'talking with a religion\'s audience lists common ground, then differences',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(ApologeticsPage(store: _store())));
      await tester.tap(find.text('Talking with'));
      await tester.pump();
      expect(find.text('Choose whom you are talking with'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('apologetics-audience-row-catholic')),
        findsNothing,
      );

      // A religion lists its denominations under its note.
      await tester.tap(
        find.byKey(const ValueKey('apologetics-religion-row-christianity')),
      );
      await tester.pump();
      expect(find.text('Those who confess Jesus as Lord.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('apologetics-audience-row-orthodox')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('apologetics-audience-row-catholic')),
      );
      await tester.pump();
      expect(
        find.text('Begin from the resurrection of the body.'),
        findsOneWidget,
      );
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('Common ground'), lessThan(y('The tomb was empty')));
      expect(y('The tomb was empty'), lessThan(y('Where you differ')));
      // In the audience's own order, not the file's.
      expect(
        y('The rich man and Lazarus'),
        lessThan(y('Luke 23:43, today in paradise')),
      );

      await tester.tap(find.byKey(const ValueKey('apologetics-kind-passage')));
      await tester.pump();
      expect(find.text('Common ground'), findsNothing);
      expect(find.text('2 entries'), findsOneWidget);

      // Back to the religion's denominations, then to the religions.
      await tester.tap(find.byKey(const ValueKey('apologetics-audience-back')));
      await tester.pump();
      expect(find.text('Choose whom you are talking with'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('apologetics-audience-row-catholic')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('apologetics-religion-back')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('apologetics-religion-row-none')),
        findsOneWidget,
      );

      // A religion of one goes straight to it, and back to the religions.
      await tester.tap(
        find.byKey(const ValueKey('apologetics-religion-row-none')),
      );
      await tester.pump();
      expect(find.text('Begin from the tomb.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('apologetics-audience-back')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('apologetics-religion-row-christianity')),
        findsOneWidget,
      );
    },
  );

  testWidgets('an entry\'s topic opens that topic in the list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(ApologeticsPage(store: _store())));
    await tester.tap(
      find.byKey(const ValueKey('apologetics-group-subjects-death')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('apologetic-row-luke-16-19')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apologetic-topic-hell')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('apologetic-page-luke-16-19')),
      findsNothing,
    );
    // Topics, with Hell open and Heaven at death not.
    expect(
      find.byKey(const ValueKey('apologetics-group-topics-hell')),
      findsOneWidget,
    );
    expect(find.text('The rich man and Lazarus'), findsOneWidget);
    expect(find.text('Luke 23:43, today in paradise'), findsNothing);
  });

  testWidgets('an entry opens with its argument, and passages navigate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <(int, int, int)>[];
    final store = _store();
    // Pushed over a page, as the reader opens it, so closing it can pop.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ApologeticsPage(
                  store: store,
                  useEnglishBookNames: true,
                  onNavigateToPassage: (b, c, v) => opened.add((b, c, v)),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('apologetics-group-subjects-resurrection')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('apologetic-row-empty-tomb')));
    await tester.pumpAndSettle();
    expect(find.text('The argument'), findsOneWidget);
    expect(find.text('Tacitus, Annals 15.44'), findsOneWidget);
    expect(find.text('An objection to The tomb was empty.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('apologetic-related-luke-23-43')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Luke 23:43, today in paradise'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Luke 23:42–43'));
    await tester.pumpAndSettle();
    expect(opened, [(41, 23, 42)]);
    expect(find.byType(ApologeticsPage), findsNothing);
  });

  testWidgets('a chapter lists the entries marking it', (tester) async {
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: ChapterApologeticsSheet(
            bookIndex: 41,
            chapter: 23,
            store: _store(),
            useEnglishBookNames: true,
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('chapter-apologetic-luke-23-43')),
      findsOneWidget,
    );
    expect(find.text('Luke 23:42–43'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chapter-apologetic-empty-tomb')),
      findsNothing,
    );
  });
}
