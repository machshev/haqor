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
}
