import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/event_sequence.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/bible_prophecy.dart';
import 'package:haqor/src/widgets/bible_timeline_page.dart';
import 'package:haqor/src/widgets/event_sequence_page.dart';
import 'package:haqor/src/widgets/timeline_wheel.dart';

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
  test(
    'creation week places events and the kingdom across seven millennia',
    () {
      final marks = timelineWheelMarks(
        bibleTimeline,
        [...bibleTimelineEntries(_events), bibleKingdomOfChrist],
        0,
        cycle: bibleCreationWeek,
      );
      expect(bibleCreationWeek.segments, hasLength(7));
      expect(marks.firstWhere((m) => m.entry.id == '1').from, 0);
      final kingdom = marks.firstWhere(
        (m) => m.entry.id == bibleKingdomOfChrist.id,
      );
      expect(kingdom.from, closeTo(6 / 7, 0.000001));
      expect(kingdom.to, 1);
      expect(
        bibleTimeline.positionOf(bibleKingdomOfChrist.last) -
            bibleTimeline.positionOf(bibleKingdomOfChrist.start),
        1000,
      );
    },
  );

  testWidgets('Bible wheel opens with events and the seventh-day kingdom', (
    tester,
  ) async {
    final requests = <GetBibleEvents>[];
    await tester.pumpWidget(
      MaterialApp(home: BibleTimelinePage(sendRequest: requests.add)),
    );
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: _events,
        sequences: const [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show time span wheel'));
    await tester.pumpAndSettle();
    final wheel = tester.widget<TimelineWheel>(find.byType(TimelineWheel));
    expect(wheel.cycle, bibleCreationWeek);
    expect(wheel.entries.any((e) => e.id == bibleKingdomOfChrist.id), isTrue);
    expect(find.textContaining('Day 7: Kingdom of Christ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Show timeline'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineWheel), findsNothing);
  });

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
        sequences: const [],
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

  testWidgets('opens a timeline that comes with the app, its verses in the '
      'reader', (tester) async {
    final requests = <GetBibleEvents>[];
    final readAt = <(int, int, int)>[];
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
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: _events,
        sequences: const [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bible-timeline-standards')));
    await tester.pumpAndSettle();
    final moadim = standardTimelineById('moadim')!;
    await tester.tap(find.text(moadim.template.title));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, moadim.template.title), findsOneWidget);
    // Read as it is: nothing to add to it or edit.
    expect(find.byTooltip('Add to timeline'), findsNothing);
    expect(find.byTooltip('Edit timeline'), findsNothing);
    final pesach = find.byKey(const ValueKey('timeline-row-moadim:pesach'));
    await tester.scrollUntilVisible(
      pesach,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('timeline-page-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(pesach);
    await tester.pumpAndSettle();
    // Its top, the list below the chart and readings short of room.
    await tester.tapAt(tester.getTopLeft(pesach) + const Offset(40, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Leviticus 23:5'));
    await tester.pumpAndSettle();
    // Both timelines close for the reader.
    expect(find.byType(BibleTimelinePage, skipOffstage: false), findsNothing);
    expect(readAt, [(2, 23, 5)]);
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
        sequences: const [],
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
  _overviewTests();
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
  test('events are sorted into kinds, births and deaths a life shows left '
      'off, and other deaths pinned', () {
    final covered = <String, String>{};
    final entries = {
      for (final e in bibleTimelineEntries(_lives, coveredBy: covered)) e.id: e,
    };
    expect(entries['4']!.category, 'Lifetimes');
    expect(entries['60']!.category, 'Births');
    expect(entries['71']!.category, 'Deaths');
    expect(entries['70']!.category, 'Reigns');
    expect(entries['80']!.category, 'Prophets');
    expect(bibleEventCategory('Deliverance by Gideon', span: true), 'Judges');
    expect(bibleEventCategory('The Great Flood', span: true), 'Periods');
    expect(bibleEventCategory('Tower of Babel', span: false), 'Events');

    // Seth's birth starts his life and Adam's death ends his: each drawn
    // already by the life, and left off.
    expect(entries.containsKey('7'), isFalse);
    expect(entries.containsKey('23'), isFalse);
    expect(covered, {'7': '8', '23': '4'});
    // A king known by two names, his death pinned to his reign; Reuben has
    // no life to belong to.
    expect(entries['71']!.pin!.anchorId, '70');
    expect(entries['60']!.pin, isNull);
    expect(entries['4']!.pin, isNull);
  });

  testWidgets('deaths fold under reigns, and kinds hide', (tester) async {
    final requests = <GetBibleEvents>[];
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: BibleTimelinePage(sendRequest: requests.add)),
    );
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: _lives,
        sequences: const [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    Finder row(String id) =>
        find.byKey(ValueKey('timeline-row-$id'), skipOffstage: false);
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    // The births and deaths the lives show are not drawn or listed.
    expect(row('4'), findsOneWidget);
    expect(row('8'), findsOneWidget);
    expect(row('7'), findsNothing);
    expect(row('23'), findsNothing);
    expect(find.byKey(const ValueKey('timeline-mark-7')), findsNothing);
    expect(find.byKey(const ValueKey('timeline-mark-23')), findsNothing);
    expect(row('60'), findsOneWidget);

    // A death folded under the reign at first, a count on its row.
    expect(row('70'), findsOneWidget);
    expect(row('71'), findsNothing);
    final toggle = find.byKey(
      const ValueKey('timeline-group-row-70'),
      skipOffstage: false,
    );
    expect(toggle, findsOneWidget);

    // Opened, the death shows beneath it, set in.
    await tap(toggle);
    expect(row('71'), findsOneWidget);
    expect(
      tester.getTopLeft(row('71')).dy,
      greaterThan(tester.getTopLeft(row('70')).dy),
    );
    Finder title(String id, String text) =>
        find.descendant(of: row(id), matching: find.text(text));
    expect(
      tester.getTopLeft(title('71', 'Death of Jehoahaz')).dx,
      greaterThan(
        tester.getTopLeft(title('70', 'Reign of Ahaziah (Jehoahaz)')).dx,
      ),
    );
    await tap(toggle);
    expect(row('71'), findsNothing);

    // All opened, then all closed.
    await tap(find.byKey(const ValueKey('timeline-expand-all')));
    expect(row('71'), findsOneWidget);
    await tap(find.byKey(const ValueKey('timeline-collapse-all')));
    expect(row('71'), findsNothing);

    // With reigns hidden, the death stands alone; with deaths hidden, it
    // goes. Lives hidden, what they showed stays off.
    await tap(find.byKey(const ValueKey('timeline-category-Reigns')));
    expect(row('70'), findsNothing);
    expect(row('71'), findsOneWidget);
    await tap(find.byKey(const ValueKey('timeline-category-Deaths')));
    expect(row('71'), findsNothing);
    await tap(find.byKey(const ValueKey('timeline-category-Lifetimes')));
    expect(row('4'), findsNothing);
    expect(row('7'), findsNothing);
    expect(row('23'), findsNothing);
  });

  testWidgets('opened on a death a life shows, the life is opened on; on '
      'one folded away, its reign opens', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> openOn(String id) async {
      final requests = <GetBibleEvents>[];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: BibleTimelinePage(
            sendRequest: requests.add,
            initialEventId: id,
          ),
        ),
      );
      assignRustSignal['BibleEvents']!(
        BibleEvents(
          requestId: requests.single.requestId,
          events: _lives,
          sequences: const [],
        ).bincodeSerialize(),
        Uint8List(0),
      );
      await tester.pumpAndSettle();
    }

    ListTile tile(String id) => tester.widget(
      find.byKey(ValueKey('timeline-row-$id'), skipOffstage: false),
    );

    await openOn('23');
    expect(tile('4').selected, isTrue);
    expect(
      find.byKey(const ValueKey('timeline-row-23'), skipOffstage: false),
      findsNothing,
    );

    await openOn('71');
    expect(tile('71').selected, isTrue);
  });

  testWidgets('more than five events stacked at a time are drawn as one', (
    tester,
  ) async {
    final requests = <GetBibleEvents>[];
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: BibleTimelinePage(sendRequest: requests.add)),
    );
    final sons = [
      for (final (i, son) in [
        'Reuben',
        'Simeon',
        'Levi',
        'Judah',
        'Dan',
        'Naphtali',
        'Gad',
      ].indexed)
        _event(60 + i, 'Birth of $son', -1758 + i ~/ 4),
    ];
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: [
          _event(1, 'Creation of all things', -4004),
          ...sons,
          _event(400, 'Paul arrives at Rome', 60),
        ],
        sequences: const [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    await _zoomIn(tester);

    // Drawn as one mark, though each is still listed.
    final mark = find.byKey(const ValueKey('timeline-mark-cluster-60'));
    expect(mark, findsOneWidget);
    await tester.ensureVisible(mark);
    await tester.pumpAndSettle();
    expect(find.text('Births ×7'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-mark-61')), findsNothing);
    expect(find.byKey(const ValueKey('timeline-mark-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-row-61')), findsOneWidget);

    // Opened, it lists them, each opening its details.
    await tester.tap(mark);
    await tester.pumpAndSettle();
    expect(find.text('7 events'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timeline-cluster-row-63')));
    await tester.pumpAndSettle();
    expect(find.text('Birth of Judah'), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Zoomed in to them, they stand apart.
    await tester.tap(mark);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-cluster-zoom')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('timeline-mark-cluster-60')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('timeline-mark-61')), findsOneWidget);
  });

  group('sequences', () {
    ThematicTarget mark(int chapter, int verse) => ThematicTarget(
      book: 41,
      chapter: chapter,
      verse: verse,
      lastChapter: chapter,
      lastVerse: verse,
    );
    final events = [
      _event(1, 'Creation of all things', -4004),
      _event(266, 'John the Baptist Begins Ministry', 26),
      _event(267, 'John Baptizes Jesus', 26),
      _event(443, 'Holy Week', 30, passages: [mark(11, 1)]),
      _event(452, 'The Last Supper', 30, passages: [mark(14, 12)]),
      _event(460, 'Resurrection and Ascension', 30),
      _event(400, 'Paul arrives at Rome', 60),
    ];
    final sequences = [
      EventSequenceEntry(
        setAside: const [],
        key: 'ministry',
        title: 'Ministry of Jesus',
        note: 'Ordered, not dated.',
        expands: null,
        events: [266, 267, 443],
        edges: [
          SequenceEdgeEntry(before: 266, after: 267, bases: ["Mark's order"]),
          SequenceEdgeEntry(before: 267, after: 443, bases: ["Mark's order"]),
        ],
        groupings: const [],
        milestones: const [],
        details: const [],
      ),
      EventSequenceEntry(
        setAside: const [],
        key: 'week',
        title: 'Holy Week',
        note: '',
        expands: 443,
        events: [452, 460],
        edges: [
          SequenceEdgeEntry(
            before: 452,
            after: 460,
            bases: ["John's order", "Mark's order"],
          ),
        ],
        groupings: const [],
        milestones: const [],
        details: const [],
      ),
    ];

    /// The timeline opened from a page beneath it, so that closing it can
    /// be seen.
    Future<List<GetBibleEvents>> open(
      WidgetTester tester, {
      String? initialEventId,
      List<(int, int, int)>? readAt,
    }) async {
      final requests = <GetBibleEvents>[];
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => BibleTimelinePage.open(
                context,
                sendRequest: requests.add,
                initialEventId: initialEventId,
                useEnglishBookNames: true,
                onNavigateToPassage: (book, chapter, verse) =>
                    readAt?.add((book, chapter, verse)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      // Not settled: it waits for the events with a spinner.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      assignRustSignal['BibleEvents']!(
        BibleEvents(
          requestId: requests.single.requestId,
          events: events,
          sequences: sequences,
        ).bincodeSerialize(),
        Uint8List(0),
      );
      await tester.pumpAndSettle();
      return requests;
    }

    test('their events stand on the timeline as one span', () {
      final entries = bibleTimelineEntries(
        events,
        sequences: BibleSequences(sequences),
      );
      expect(entries.map((e) => e.id), ['1', 'sequence:ministry', '400']);
      final ministry = entries[1];
      expect(ministry.isSpan, isTrue);
      expect(bibleTimeline.formatTime(ministry.start), 'AD 26');
      expect(bibleTimeline.formatTime(ministry.end!), 'AD 31');
      // Without them, every event, as links to them need.
      expect(bibleTimelineEntries(events), hasLength(events.length));
    });

    testWidgets('open from the timeline and inside one another', (
      tester,
    ) async {
      final readAt = <(int, int, int)>[];
      await open(tester, readAt: readAt);
      Finder row(String id) => find.byKey(ValueKey('timeline-row-$id'));
      expect(row('266'), findsNothing);
      expect(row('452'), findsNothing);
      await _scrollTo(tester, row('sequence:ministry'));
      await tester.pumpAndSettle();
      await tester.tap(row('sequence:ministry'));
      await tester.pumpAndSettle();

      expect(find.byType(EventSequencePage), findsOneWidget);
      expect(find.text('3 events in order'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sequence-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sequence-about')));
      await tester.pumpAndSettle();
      expect(find.text('Ordered, not dated.'), findsOneWidget);
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sequence-event-267')));
      await tester.pumpAndSettle();
      expect(find.text('Before: 1'), findsOneWidget);
      expect(find.text('After: 1'), findsOneWidget);
      expect(find.text('Comes after'), findsOneWidget);
      expect(find.textContaining("— Mark's order"), findsNWidgets(2));

      // Holy Week opens its own sequence.
      await tester.tap(find.byKey(const ValueKey('sequence-related-443')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sequence-open-inner')));
      await tester.pumpAndSettle();
      expect(find.text('2 events in order'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sequence-event-452')));
      await tester.pumpAndSettle();
      expect(find.textContaining("John's order; Mark's order"), findsOneWidget);

      // A passage opens in the reader, every page above it closed.
      await tester.tap(find.widgetWithText(ActionChip, 'Mark 14:12'));
      await tester.pumpAndSettle();
      expect(readAt, [(40, 14, 12)]);
      expect(find.byType(EventSequencePage), findsNothing);
      expect(find.byType(BibleTimelinePage), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('a touch just beside a narrow span opens it', (tester) async {
      await open(tester);
      await _zoomIn(tester);
      final mark = find.byKey(
        const ValueKey('timeline-mark-sequence:ministry'),
      );
      await tester.ensureVisible(mark);
      await tester.pumpAndSettle();
      // Clear of the left edge, nothing drawn just before it.
      await tester.dragFrom(
        tester.getCenter(mark) + const Offset(0, 200),
        const Offset(200, 0),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(mark);
      // Too narrow to be sure of under a fingertip.
      expect(rect.width, lessThan(16));
      final beside = rect.centerLeft - const Offset(10, 0);

      // Clicked beside it with a mouse, nothing.
      await tester.tapAt(beside, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(EventSequencePage), findsNothing);

      // Touched beside it, it opens.
      await tester.tapAt(beside);
      await tester.pumpAndSettle();
      expect(find.byType(EventSequencePage), findsOneWidget);
    });

    testWidgets('turn between top to bottom and left to right, kept', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('timeline-row-sequence:ministry')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('timeline-row-sequence:ministry')),
      );
      await tester.pumpAndSettle();
      Offset at(int event) =>
          tester.getTopLeft(find.byKey(ValueKey('sequence-event-$event')));

      // Top to bottom at first, each event below the one it follows.
      expect(at(267).dy, greaterThan(at(266).dy));
      expect(at(267).dx, moreOrLessEquals(at(266).dx, epsilon: 1));

      await tester.tap(find.byKey(const ValueKey('sequence-orientation')));
      await tester.pumpAndSettle();
      expect(at(267).dx, greaterThan(at(266).dx));
      expect(at(267).dy, moreOrLessEquals(at(266).dy, epsilon: 1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(eventSequenceHorizontalKey), isTrue);

      // A sequence opened inside it is drawn the same way.
      await tester.tap(find.byKey(const ValueKey('sequence-event-443')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sequence-open-inner')));
      await tester.pumpAndSettle();
      expect(at(460).dx, greaterThan(at(452).dx));

      // Turned back for the next test.
      await tester.tap(find.byKey(const ValueKey('sequence-orientation')));
      await tester.pumpAndSettle();
      expect(prefs.getBool(eventSequenceHorizontalKey), isFalse);
    });

    testWidgets('opened on an event inside them, they open to it', (
      tester,
    ) async {
      await open(tester, initialEventId: '452');
      expect(
        find.byType(EventSequencePage, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(find.text('2 events in order'), findsOneWidget);
      expect(find.text('Comes before'), findsOneWidget);
      expect(find.textContaining('Resurrection and Ascension'), findsWidgets);
    });
  });
}

/// Zooms the chart in until it is drawn as usual, past its overview (see
/// [TimelinePage.overviewZoom]).
Future<void> _zoomIn(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
  }
}

void _overviewTests() {
  test("Daniel's kingdoms follow one another, a day for a year", () {
    final entries = bibleDaniel;
    final ids = entries.map((e) => e.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    TimelineTime? endOf(String id) =>
        entries.firstWhere((e) => e.id == 'daniel:$id').end;
    TimelineTime startOf(String id) =>
        entries.firstWhere((e) => e.id == 'daniel:$id').start;
    // The image's metals, and the beasts, end to end.
    for (final (a, b) in [
      ('image:gold', 'image:silver'),
      ('image:silver', 'image:brass'),
      ('image:brass', 'image:iron'),
      ('image:iron', 'image:feet'),
      ('beast:lion', 'beast:bear'),
      ('beast:bear', 'beast:leopard'),
    ]) {
      expect(endOf(a), startOf(b), reason: '$a to $b');
    }
    for (final e in entries) {
      expect(e.category, bibleDanielCategory);
      expect(e.verses.every((v) => v.bookIndex == 34), isTrue);
      expect(e.note, isNotEmpty);
      if (e.end case final end?) {
        expect(
          bibleTimeline.positionOf(end),
          greaterThan(bibleTimeline.positionOf(e.start)),
          reason: e.title,
        );
      }
    }
    // Sixty-nine weeks of years, from 457 BC, there being no year 0.
    final weeks = entries.firstWhere((e) => e.id == 'daniel:weeks:69');
    expect(
      bibleTimeline.positionOf(weeks.last) -
          bibleTimeline.positionOf(weeks.start),
      483,
    );
    expect(bibleTimeline.colorOf(entries.first), isNotNull);
  });
  test('the Apocalypse runs from Patmos through the seals, trumpets and '
      'vials', () {
    final entries = bibleApocalypse;
    final ids = entries.map((e) => e.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final prefix in ['seal', 'trumpet', 'vial']) {
      final count = prefix == 'seal'
          ? 6
          : prefix == 'trumpet'
          ? 7
          : 6;
      for (var n = 1; n <= count; n++) {
        expect(ids, contains('apocalypse:$prefix:$n'));
      }
    }
    for (final e in entries) {
      expect(e.category, bibleApocalypseCategory);
      expect(e.timelineId, bibleTimeline.id);
      expect(e.verses, isNotEmpty);
      expect(e.verses.every((v) => v.bookIndex == 65), isTrue);
      expect(e.note, isNotEmpty);
      if (e.end case final end?) {
        expect(
          bibleTimeline.positionOf(end),
          greaterThan(bibleTimeline.positionOf(e.start)),
          reason: e.title,
        );
      }
    }
    // The sixth trumpet's hour, day, month and year: 391 years and 30 days.
    final turks = entries.firstWhere((e) => e.id == 'apocalypse:trumpet:6');
    expect(
      bibleTimeline.positionOf(turks.last) -
          bibleTimeline.positionOf(turks.start),
      closeTo(391 + 30 / 365, 0.01),
    );
    expect(bibleTimeline.colorOf(entries.first), isNotNull);
  });
  test('the eras run end to end from the creation to now', () {
    expect(bibleEras.first.start.value, -4004);
    expect(bibleEras.last.end!.value, DateTime.now().year);
    for (final (before, after) in [
      for (var i = 1; i < bibleEras.length; i++)
        (bibleEras[i - 1], bibleEras[i]),
    ]) {
      expect(before.end, after.start);
    }
    // Each with a short title for a narrow screen.
    expect(bibleEras.every((e) => e.shortTitle.length <= 10), isTrue);
    expect(bibleEras.map((e) => e.category).toSet(), {bibleEraCategory});
  });

  testWidgets('zoomed out, the eras are titled over the rest drawn thin', (
    tester,
  ) async {
    final requests = <GetBibleEvents>[];
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: BibleTimelinePage(sendRequest: requests.add)),
    );
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: requests.single.requestId,
        events: _lives,
        sequences: const [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    Finder mark(String id) => find.byKey(ValueKey('timeline-mark-$id'));
    Finder titleOf(String id) =>
        find.descendant(of: mark(id), matching: find.byType(Text));

    // The eras in one lane above the rest, the first titled.
    final eras = [for (final e in bibleEras) tester.getTopLeft(mark(e.id))];
    expect(eras.map((at) => at.dy).toSet(), hasLength(1));
    expect(titleOf('era:0'), findsOneWidget);
    expect(tester.getTopLeft(mark('4')).dy, greaterThan(eras.first.dy));
    // Adam's life thin, untitled.
    expect(titleOf('4'), findsNothing);
    expect(tester.getSize(mark('4')).height, lessThan(10));

    // Zoomed in, drawn as usual.
    await _zoomIn(tester);
    expect(titleOf('4'), findsWidgets);
    expect(tester.getSize(mark('4')).height, greaterThan(20));
  });
}

/// Scrolls the list beneath the chart until [row] is built and shown.
Future<void> _scrollTo(WidgetTester tester, Finder row) async {
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('timeline-page-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(row);
}
