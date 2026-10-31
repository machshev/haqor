import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/event_sequence.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/event_sequence_page.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/sequence_map_page.dart';

final _basemap = Basemap.parse('{"land":[[30,28,40,28,40,36,30,36]]}');

ThematicTarget _at(int book, int chapter, int verse) => ThematicTarget(
  book: book,
  chapter: chapter,
  verse: verse,
  lastChapter: chapter,
  lastVerse: verse,
);

NameSummaryEntry _name(int id, String name, String kind) => NameSummaryEntry(
  id: id,
  name: name,
  kind: kind,
  description: '',
  origin: '',
  occurrences: 0,
);

final _peter = _name(900, 'Peter', 'person');

BibleEventEntry _event(
  int id,
  String title,
  ThematicTarget passage, {
  List<NameSummaryEntry> people = const [],
}) => BibleEventEntry(
  id: id,
  title: title,
  year: 27,
  duration: 0,
  unit: '',
  passages: [passage],
  people: people,
  places: const [],
  note: '',
);

final _events = {
  for (final e in [
    _event(1, 'Baptism', _at(41, 1, 9)),
    _event(2, 'Water to Wine', _at(43, 2, 1)),
    _event(3, 'Temple Cleansing', _at(43, 2, 13)),
    _event(4, 'Fishers of Men', _at(41, 1, 16), people: [_peter]),
    _event(5, "Peter's Mother-in-law", _at(41, 1, 29), people: [_peter]),
  ])
    e.id: e,
};

SequencePlaceEntry _place(int id, String name, double lat, double lon) =>
    SequencePlaceEntry(
      place: _name(id, name, 'place'),
      label: name,
      location: PlaceLocationEntry(
        latitude: lat,
        longitude: lon,
        confidence: -1,
        kind: 'settlement',
        label: '',
        area: const [],
        line: const [],
        estimated: false,
      ),
    );

SequenceEventDetailsEntry _details(
  int event,
  List<String> kinds,
  String region, [
  List<SequencePlaceEntry> places = const [],
]) => SequenceEventDetailsEntry(
  event: event,
  kinds: kinds,
  region: region,
  places: places,
);

final _cana = _place(800, 'Cana', 32.75, 35.34);
final _jerusalem = _place(801, 'Jerusalem', 31.78, 35.23);
final _capernaum = _place(802, 'Capernaum', 32.88, 35.57);

SequenceEdgeEntry _edge(int before, int after) =>
    SequenceEdgeEntry(before: before, after: after, bases: ["Mark's order"]);

final _sequence = EventSequenceEntry(
  key: 'test-ministry',
  title: 'Ministry',
  note: 'Ordered, not dated.',
  expands: null,
  events: [1, 2, 3, 4, 5],
  edges: [_edge(1, 2), _edge(2, 3), _edge(3, 4), _edge(4, 5)],
  groupings: [
    SequenceGroupingEntry(
      key: 'parts',
      title: 'Parts',
      note: 'By parts.',
      groups: [
        SequenceGroupEntry(
          title: 'Beginnings',
          note: '§§1–2',
          parent: null,
          events: [1, 2],
        ),
        SequenceGroupEntry(
          title: 'In Galilee',
          note: '',
          parent: null,
          events: [],
        ),
        SequenceGroupEntry(
          title: 'The Passover',
          note: '',
          parent: 1,
          events: [3, 4],
        ),
        SequenceGroupEntry(
          title: 'Capernaum',
          note: '',
          parent: 1,
          events: [5],
        ),
      ],
    ),
  ],
  milestones: [
    SequenceMilestoneEntry(
      event: 3,
      feast: 'pesach',
      label: 'Passover',
      book: 43,
      chapter: 2,
      verse: 13,
    ),
  ],
  details: [
    _details(1, ['revelation'], 'judea'),
    _details(2, ['sign'], 'galilee', [_cana]),
    _details(3, ['feast', 'conflict'], 'judea', [_jerusalem]),
    _details(4, ['calling'], 'galilee', [_capernaum]),
    _details(5, ['healing'], 'galilee', [_capernaum]),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The page opened from a page beneath it, so that a passage it opens
  /// closes it; the passages opened.
  Future<List<StudyPassage>> open(
    WidgetTester tester, {
    Size size = const Size(900, 1400),
    EventSequenceEntry? sequence,
  }) async {
    final shown = sequence ?? _sequence;
    final opened = <StudyPassage>[];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => EventSequencePage.open(
              context,
              sequence: shown,
              sequences: BibleSequences([shown]),
              events: _events,
              useEnglishBookNames: true,
              onOpenPassage: opened.add,
              basemap: _basemap,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return opened;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  double opacity(WidgetTester tester, String k) => tester
      .widget<Opacity>(
        find.ancestor(of: key(k), matching: find.byType(Opacity)).first,
      )
      .opacity;

  Future<void> menu(WidgetTester tester, String item) async {
    await tester.tap(key('sequence-menu'));
    await tester.pumpAndSettle();
    await tester.tap(key(item));
    await tester.pumpAndSettle();
  }

  testWidgets('folds into its groups, each unfolded on its own', (
    tester,
  ) async {
    await open(tester);
    expect(key('sequence-group-0'), findsOneWidget);
    expect(key('sequence-group-1'), findsOneWidget);
    expect(key('sequence-event-1'), findsNothing);
    expect(find.text('5 events in order'), findsOneWidget);

    await tester.tap(key('sequence-unfold-1'));
    await tester.pumpAndSettle();
    expect(key('sequence-group-1'), findsNothing);
    expect(key('sequence-group-2'), findsOneWidget);
    expect(key('sequence-group-3'), findsOneWidget);

    await tester.tap(key('sequence-unfold-2'));
    await tester.pumpAndSettle();
    expect(key('sequence-event-3'), findsOneWidget);
    expect(key('sequence-event-4'), findsOneWidget);
    // The Passover is marked across the graph before its event.
    expect(key('sequence-milestone-3'), findsOneWidget);
    expect(
      tester.getTopLeft(key('sequence-event-3')).dy,
      greaterThan(tester.getBottomLeft(key('sequence-milestone-3')).dy),
    );
    // Below the group before it, and above the one after.
    expect(
      tester.getTopLeft(key('sequence-event-3')).dy,
      greaterThan(tester.getBottomLeft(key('sequence-group-0')).dy),
    );
    expect(
      tester.getTopLeft(key('sequence-group-3')).dy,
      greaterThan(tester.getBottomLeft(key('sequence-event-4')).dy),
    );

    // Picking an event shows what it is, and what is known around it.
    await tester.tap(key('sequence-event-3'));
    await tester.pumpAndSettle();
    expect(find.text('Before: 2'), findsOneWidget);
    expect(
      find.descendant(
        of: key('sequence-panel'),
        matching: find.text('Conflict'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Judea · Jerusalem'), findsOneWidget);

    // Folded again, the group stands for it.
    await tester.tap(key('sequence-fold-1'));
    await tester.pumpAndSettle();
    expect(key('sequence-group-1'), findsOneWidget);
    expect(key('sequence-event-3'), findsNothing);
    expect(find.textContaining('Unfold: 3 events'), findsOneWidget);
  });

  testWidgets('a related event folded away is unfolded to', (tester) async {
    await open(tester);
    await tester.tap(key('sequence-unfold-0'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-event-2'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-related-3'));
    await tester.pumpAndSettle();
    expect(key('sequence-event-3'), findsOneWidget);
    expect(find.text('Before: 2'), findsOneWidget);
  });

  testWidgets('lights the events of a kind, or of a person', (tester) async {
    await open(tester);
    await tester.tap(key('sequence-fold-toggle'));
    await tester.pumpAndSettle();
    expect(opacity(tester, 'sequence-event-2'), 1);

    await tester.tap(key('sequence-kind-miracles'));
    await tester.pumpAndSettle();
    expect(opacity(tester, 'sequence-event-2'), 1);
    expect(opacity(tester, 'sequence-event-5'), 1);
    expect(opacity(tester, 'sequence-event-4'), lessThan(1));
    await tester.tap(key('sequence-kind-miracles'));
    await tester.pumpAndSettle();

    await tester.tap(key('sequence-person'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-person-900'));
    await tester.pumpAndSettle();
    expect(opacity(tester, 'sequence-event-4'), 1);
    expect(opacity(tester, 'sequence-event-5'), 1);
    expect(opacity(tester, 'sequence-event-2'), lessThan(1));

    // Folded, a group says how many of its events are lit.
    await tester.tap(key('sequence-fold-toggle'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 events'), findsOneWidget);
    expect(opacity(tester, 'sequence-group-0'), lessThan(1));
  });

  testWidgets('lays its events in lanes by region, kept', (tester) async {
    await open(tester);
    await tester.tap(key('sequence-fold-toggle'));
    await tester.pumpAndSettle();
    await menu(tester, 'sequence-lanes');
    expect(find.text('Galilee'), findsOneWidget);
    expect(find.text('Judea'), findsOneWidget);
    // Galilee's lane before Judea's.
    final galilee = tester.getTopLeft(key('sequence-event-2')).dx;
    expect(tester.getTopLeft(key('sequence-event-1')).dx, greaterThan(galilee));
    expect(tester.getTopLeft(key('sequence-event-4')).dx, galilee);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(eventSequenceLanesKey), isTrue);

    await menu(tester, 'sequence-lanes');
    expect(find.text('Galilee'), findsNothing);
  });

  testWidgets('reads as an outline, its feasts between its events', (
    tester,
  ) async {
    final opened = await open(tester);
    await tester.tap(key('sequence-outline'));
    await tester.pumpAndSettle();
    expect(key('sequence-graph'), findsNothing);
    expect(key('sequence-outline-group-0'), findsOneWidget);
    expect(key('sequence-outline-event-1'), findsNothing);

    await tester.tap(key('sequence-outline-group-1'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-outline-group-2'));
    await tester.pumpAndSettle();
    expect(key('sequence-outline-event-3'), findsOneWidget);
    expect(
      tester.getTopLeft(key('sequence-outline-event-3')).dy,
      greaterThan(tester.getTopLeft(key('sequence-outline-milestone-3')).dy),
    );

    // The feast tells what the moʿadim say of it, and opens its verse.
    await tester.tap(key('sequence-outline-milestone-3'));
    await tester.pumpAndSettle();
    expect(find.text('Pesach (the passing over)'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'John 2:13'));
    await tester.pumpAndSettle();
    expect(opened.single.reference, '2:13');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(eventSequenceOutlineKey), isTrue);
    // Drawn as a graph again for the next test.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-outline'));
    await tester.pumpAndSettle();
    expect(key('sequence-graph'), findsOneWidget);
  });

  testWidgets('shows a group on the map, joined where the order is known', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(key('sequence-group-1'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-panel-map'));
    await tester.pumpAndSettle();
    final map = tester.widget<SequenceMapPage>(find.byType(SequenceMapPage));
    expect(map.stops.map((s) => s.event), [3, 4, 5]);
    expect(find.text('3 of 3 events placed'), findsOneWidget);
    final placeMap = tester.widget<PlaceMap>(key('sequence-map'));
    // Capernaum twice, one pin; one way, Jerusalem to Capernaum.
    expect(placeMap.pins.map((p) => p.label), [
      'Jerusalem (1)',
      'Capernaum (2, 3)',
    ]);
    expect(placeMap.legs, hasLength(1));

    // An event of it picks it out on the sequence.
    await tester.tap(key('sequence-map-stop-4'));
    await tester.pumpAndSettle();
    expect(key('sequence-event-4'), findsOneWidget);
    expect(find.text('Before: 3'), findsOneWidget);
  });

  testWidgets('groups by another grouping, or none', (tester) async {
    await open(tester);
    await tester.tap(key('sequence-grouping'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-grouping-none').last);
    await tester.pumpAndSettle();
    for (final e in _sequence.events) {
      expect(key('sequence-event-$e'), findsOneWidget);
    }
    expect(key('sequence-group-0'), findsNothing);

    // Kept for the sequence; back to its parts for the other tests.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(key('sequence-group-0'), findsNothing);
    await tester.tap(key('sequence-grouping'));
    await tester.pumpAndSettle();
    await tester.tap(key('sequence-grouping-parts').last);
    await tester.pumpAndSettle();
    expect(key('sequence-group-0'), findsOneWidget);
  });

  testWidgets('on a narrow screen every chip can be reached', (tester) async {
    await open(tester, size: const Size(360, 800));
    // Compact, it takes no more than two lines of the screen.
    expect(tester.getSize(key('sequence-filters')).height, lessThan(80));
    for (final family in ['miracles', 'callings', 'conflict', 'feasts']) {
      await tester.tap(key('sequence-kind-$family'));
      await tester.pumpAndSettle();
    }
    expect(
      tester.widget<FilterChip>(key('sequence-kind-feasts')).selected,
      isTrue,
    );
    await tester.tap(key('sequence-clear-filters'));
    await tester.pumpAndSettle();
    expect(key('sequence-clear-filters'), findsNothing);
    expect(
      tester.widget<FilterChip>(key('sequence-kind-feasts')).selected,
      isFalse,
    );
  });

  testWidgets('one button unfolds every group, and folds them again', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(key('sequence-fold-toggle'));
    await tester.pumpAndSettle();
    for (final e in _sequence.events) {
      expect(key('sequence-event-$e'), findsOneWidget);
    }
    // The Passover's group ends where Capernaum's begins, one event leading
    // straight to the next: the boxes are stacked, with no arrow's room
    // between, only the one's foot and the other's title.
    expect(
      tester.getTopLeft(key('sequence-event-5')).dy -
          tester.getBottomLeft(key('sequence-event-4')).dy,
      lessThan(50),
    );
    await tester.tap(key('sequence-fold-toggle'));
    await tester.pumpAndSettle();
    expect(key('sequence-group-0'), findsOneWidget);
    expect(key('sequence-group-1'), findsOneWidget);
    expect(key('sequence-event-1'), findsNothing);
  });

  testWidgets('stacks a one-to-one chain, with arrows only where it branches', (
    tester,
  ) async {
    // Baptism leads to two: Water to Wine one to one to Fishers of Men, and
    // Temple Cleansing beside them; both then lead to Peter's Mother-in-law.
    await open(
      tester,
      sequence: EventSequenceEntry(
        key: 'test-branching',
        title: 'Branching',
        note: '',
        expands: null,
        events: [1, 2, 3, 4, 5],
        edges: [
          _edge(1, 2),
          _edge(1, 3),
          _edge(2, 4),
          _edge(4, 5),
          _edge(3, 5),
        ],
        groupings: const [],
        milestones: const [],
        details: const [],
      ),
    );
    double gap(int above, int below) =>
        tester.getTopLeft(key('sequence-event-$below')).dy -
        tester.getBottomLeft(key('sequence-event-$above')).dy;
    // Each card fitted to its one line of title.
    expect(tester.getSize(key('sequence-event-1')).height, lessThan(56));
    // Where Baptism branches, and where the two meet, room for the arrows.
    expect(gap(1, 2), greaterThan(20));
    expect(gap(4, 5), greaterThan(20));
    // One to one, stacked straight beneath, the longer edge passing beside.
    expect(gap(2, 4), lessThan(8));
    expect(
      tester.getTopLeft(key('sequence-event-4')).dx,
      tester.getTopLeft(key('sequence-event-2')).dx,
    );
  });
}
