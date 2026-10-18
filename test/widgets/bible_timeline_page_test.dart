import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/bible_timeline_page.dart';

NameSummaryEntry _name(int id, String name, String kind) => NameSummaryEntry(
  id: id,
  name: name,
  kind: kind,
  description: '',
  origin: '',
  occurrences: 1,
);

BibleEventEntry _event(
  int id,
  String title,
  int year, {
  int duration = 0,
  String unit = '',
  List<ThematicTarget> passages = const [],
  List<NameSummaryEntry> people = const [],
  List<NameSummaryEntry> places = const [],
}) => BibleEventEntry(
  id: id,
  title: title,
  year: year,
  duration: duration,
  unit: unit,
  passages: passages,
  people: people,
  places: places,
  note: '',
);

final _events = [
  _event(
    1,
    'Creation of all things',
    -4004,
    duration: 7,
    unit: 'days',
    passages: [
      ThematicTarget(
        book: 1,
        chapter: 1,
        verse: 1,
        lastChapter: 2,
        lastVerse: 3,
      ),
    ],
    people: [_name(10, 'God', 'other')],
  ),
  _event(
    39,
    'The Great Flood',
    -2348,
    duration: 1,
    unit: 'years',
    places: [_name(20, 'Ararat', 'place')],
  ),
  _event(258, 'Birth of Jesus', -5),
  _event(400, 'Paul arrives at Rome', 60),
];

void main() {
  test('events lasting years are spans, the rest events', () {
    final entries = bibleTimelineEntries(_events);
    final creation = entries.first;
    expect(creation.isSpan, isFalse);
    expect(creation.note, 'Lasted 7 days.');
    expect(creation.verses.single.reference, '1:1–2:3');
    expect(creation.verses.single.bookIndex, 0);
    expect(bibleTimeline.formatTime(creation.start), '4004 BC');

    final flood = entries[1];
    expect(flood.isSpan, isTrue);
    expect(bibleTimeline.formatTime(flood.end!), '2347 BC');
    expect(flood.note, isEmpty);

    // From 5 BC to AD 60, with no year 0.
    expect(entries.map((e) => e.start.value), [-4004, -2348, -5, 60]);
  });

  testWidgets('lists the events and opens their verses and names', (
    tester,
  ) async {
    final requests = <GetBibleEvents>[];
    final readAt = <(int, int, int)>[];
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BibleTimelinePage(
          useEnglishBookNames: true,
          sendRequest: requests.add,
          onNavigateToPassage: (book, chapter, verse) =>
              readAt.add((book, chapter, verse)),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: _events,
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bible timeline'), findsOneWidget);
    final creationRow = find.byKey(const ValueKey('timeline-row-1'));
    expect(creationRow, findsOneWidget);
    expect(
      find.descendant(
        of: creationRow,
        matching: find.textContaining('4004 BC'),
      ),
      findsOneWidget,
    );
    final floodRow = find.byKey(const ValueKey('timeline-row-39'));
    expect(
      find.descendant(
        of: floodRow,
        matching: find.textContaining('2348 BC – 2347 BC (1 year)'),
      ),
      findsOneWidget,
    );

    await tester.tap(creationRow);
    await tester.pumpAndSettle();
    expect(find.text('Lasted 7 days.'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'God'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Genesis 1:1–2:3'));
    await tester.pumpAndSettle();
    expect(readAt, [(0, 1, 1)]);
  });

  testWidgets('says so when the database has no events', (tester) async {
    final requests = <GetBibleEvents>[];
    await tester.pumpWidget(
      MaterialApp(home: BibleTimelinePage(sendRequest: requests.add)),
    );
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: const [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    expect(find.textContaining('no events'), findsOneWidget);
  });

  test('a passage of one verse has no end', () {
    final entries = bibleTimelineEntries([
      _event(
        5,
        'Cain kills Abel',
        -3875,
        passages: [
          ThematicTarget(
            book: 1,
            chapter: 4,
            verse: 8,
            lastChapter: 4,
            lastVerse: 8,
          ),
        ],
      ),
    ]);
    final StudyPassage passage = entries.single.verses.single;
    expect((passage.endChapter, passage.endVerse), (null, null));
    expect(passage.reference, '4:8');
  });

  _groupingTests();
}

final _lives = [
  _event(4, 'Lifetime of Adam', -4004, duration: 930, unit: 'years'),
  _event(7, 'Birth of Seth', -3874),
  _event(8, 'Lifetime of Seth', -3874, duration: 912, unit: 'years'),
  _event(23, 'Death of Adam', -3075),
  _event(60, 'Birth of Reuben', -1758),
  _event(70, 'Reign of Ahaziah (Jehoahaz)', -886, duration: 1, unit: 'years'),
  _event(71, 'Death of Jehoahaz', -885),
  _event(80, 'Prophecies of Elijah', -910, duration: 13, unit: 'years'),
];

void _groupingTests() {
  test('events are sorted into kinds, births and deaths pinned to lives', () {
    final entries = {for (final e in bibleTimelineEntries(_lives)) e.id: e};
    expect(entries['4']!.category, 'Lifetimes');
    expect(entries['7']!.category, 'Births');
    expect(entries['23']!.category, 'Deaths');
    expect(entries['70']!.category, 'Reigns');
    expect(entries['80']!.category, 'Prophets');
    expect(bibleEventCategory('Deliverance by Gideon', span: true), 'Judges');
    expect(bibleEventCategory('The Great Flood', span: true), 'Periods');
    expect(bibleEventCategory('Tower of Babel', span: false), 'Events');

    // Seth's birth starts his life, Adam's death falls 929 years into his.
    expect(entries['7']!.pin!.anchorId, '8');
    expect(entries['7']!.pin!.offset.amount, 0);
    expect(entries['23']!.pin!.anchorId, '4');
    expect(entries['23']!.pin!.offset.amount, 929);
    // A king known by two names; Reuben has no life to belong to.
    expect(entries['71']!.pin!.anchorId, '70');
    expect(entries['60']!.pin, isNull);
    expect(entries['4']!.pin, isNull);
  });

  testWidgets('births and deaths fold under lives, and kinds hide', (
    tester,
  ) async {
    final requests = <GetBibleEvents>[];
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: BibleTimelinePage(sendRequest: requests.add)),
    );
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: _lives,
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    Finder row(String id) => find.byKey(ValueKey('timeline-row-$id'));

    // Folded away at first, a count on the span's bar and its row.
    expect(row('4'), findsOneWidget);
    expect(row('23'), findsNothing);
    expect(row('7'), findsNothing);
    expect(row('60'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-group-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-group-row-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-mark-23')), findsNothing);

    // Opened from the bar, its death shows beneath it, set in.
    await tester.tap(find.byKey(const ValueKey('timeline-group-4')));
    await tester.pumpAndSettle();
    expect(row('23'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-mark-23')), findsOneWidget);
    expect(
      tester.getTopLeft(row('23')).dy,
      greaterThan(tester.getTopLeft(row('4')).dy),
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: row('23'),
              matching: find.text('Death of Adam'),
            ),
          )
          .dx,
      greaterThan(
        tester
            .getTopLeft(
              find.descendant(
                of: row('4'),
                matching: find.text('Lifetime of Adam'),
              ),
            )
            .dx,
      ),
    );
    expect(row('7'), findsNothing);

    // All opened, then all closed.
    await tester.tap(find.byKey(const ValueKey('timeline-expand-all')));
    await tester.pumpAndSettle();
    expect(row('7'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timeline-collapse-all')));
    await tester.pumpAndSettle();
    expect(row('7'), findsNothing);
    expect(row('23'), findsNothing);

    // With lives hidden, births and deaths stand alone; with births hidden,
    // they go.
    await tester.tap(find.byKey(const ValueKey('timeline-category-Lifetimes')));
    await tester.pumpAndSettle();
    expect(row('4'), findsNothing);
    expect(row('7'), findsOneWidget);
    expect(row('23'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timeline-category-Births')));
    await tester.pumpAndSettle();
    expect(row('7'), findsNothing);
    expect(row('60'), findsNothing);
    expect(row('23'), findsOneWidget);
  });

  testWidgets('opened on an event folded away, its life opens', (tester) async {
    final requests = <GetBibleEvents>[];
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BibleTimelinePage(
          sendRequest: requests.add,
          initialEventId: '23',
        ),
      ),
    );
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: _lives,
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-row-23')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-row-7')), findsNothing);
  });
}
