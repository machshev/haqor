import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/study_timeline_editor.dart';
import 'package:haqor/src/widgets/study_workspace_panel.dart';
import 'package:haqor/src/widgets/timeline_calendar.dart';
import 'package:haqor/src/widgets/timeline_chart.dart';
import 'package:haqor/src/widgets/timeline_wheel.dart';

const _timeline = StudyTimeline(
  id: 'kings',
  title: 'Kings',
  scale: TimelineScale.calendar,
);
const _reign = StudyTimelineEntry(
  id: 'reign',
  title: 'Solomon reigns',
  timelineId: 'kings',
  start: TimelineTime(-970),
  end: TimelineTime(-931),
  verses: [StudyPassage(bookIndex: 9, chapter: 1, verse: 39)],
);
const _temple = StudyTimelineEntry(
  id: 'temple',
  title: 'Temple begun',
  timelineId: 'kings',
  start: TimelineTime(-966, month: 2, day: 2),
  date: 'c.',
  note: 'In the fourth year',
  verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
);

Future<List<VerseEntry>> _chapter(int book, int chapter) async => [
  for (var v = 1; v <= 10; v++)
    VerseEntry(
      verse: v,
      text: 'אב גד',
      glosses: const [],
      morphologies: const [],
      roots: const [],
      names: const [],
      ketivs: const [],
      crossReferenceScores: const [],
    ),
];

void main() {
  test('entries pack into the fewest lanes, in time order', () {
    final slots = packTimelineLanes(
      _timeline,
      [_temple, _reign, _temple.copyWith(title: 'Later')],
      x: (p) => p,
      width: (_) => 2,
      gap: 1,
    );
    // The reign starts first and spans the temple, which takes a new lane.
    expect(slots.map((s) => (s.entry.title, s.lane)), [
      ('Solomon reigns', 0),
      ('Temple begun', 1),
      ('Later', 2),
    ]);
    // High Sabbaths share a lane of their own, however close together.
    StudyTimelineEntry sabbath(String title, double at) => StudyTimelineEntry(
      id: title,
      title: title,
      timelineId: 'kings',
      start: TimelineTime(at),
      sabbath: true,
    );
    expect(
      packTimelineLanes(
        _timeline,
        [_reign, sabbath('First', -969), sabbath('Second', -969)],
        x: (p) => p,
        width: (_) => 2,
        gap: 1,
      ).map((s) => (s.entry.title, s.lane)),
      [('Solomon reigns', 1), ('First', 0), ('Second', 0)],
    );
    const days = StudyTimeline(id: 'd', title: 'Days', unit: 'Day');
    expect(timelineTicks(days, 0, 100, 500).map((t) => t.label), [
      'Day 0',
      'Day 20',
      'Day 40',
      'Day 60',
      'Day 80',
      'Day 100',
    ]);
    // Counting by era there is no year zero; 1 BC is just before AD 1.
    final era = timelineTicks(_timeline, -2, 2, 400);
    expect(era.map((t) => t.label), ['3 BC', '2 BC', '1 BC', 'AD 1', 'AD 2']);
    expect(era.map((t) => t.position), [-2, -1, 0, 1, 2]);
    // Zoomed in within a year, its months are marked.
    final months = timelineTicks(_timeline, -965, -964, 1200);
    expect(months.first.label, 'Nisan 966 BC');
    expect(months.map((t) => t.label), contains('Tishri'));
    // Further in, days: each marked in its middle, every so many by number.
    final feasts = _timeline.copyWith(scale: TimelineScale.annual);
    const nisan15 = TimelineTime(0, month: 1, day: 15);
    final days15 = timelineTicks(
      feasts,
      feasts.positionOf(nisan15),
      feasts.positionOf(nisan15) + 10 / 354,
      1000,
    );
    expect(days15.map((t) => t.label), [for (var d = 15; d < 25; d++) '$d']);
    // A day is the gap between two marks, its label in the middle.
    expect(days15.first.position, feasts.positionOf(nisan15));
    expect(days15.first.labelAt, feasts.centreOf(nisan15));
    final daysAcross = timelineTicks(feasts, 25 / 354, 40 / 354, 300);
    expect(
      [
        for (final t in daysAcross)
          if (t.label.isNotEmpty) t.label,
      ],
      ['1 Iyyar', '5', '10'],
      reason: 'Nisan 30 is too near 1 Iyyar to be marked',
    );
    // A span runs to the end of its last day, past an event on that day.
    const unleavened = StudyTimelineEntry(
      id: 'u',
      title: 'Unleavened Bread',
      timelineId: 'kings',
      start: nisan15,
      end: TimelineTime(0, month: 1, day: 21),
    );
    final reach = timelineEntryReach(feasts, unleavened);
    expect(reach.end - reach.start, closeTo(7 / 354, 1e-9));
    expect(
      reach.end,
      greaterThan(feasts.centreOf(const TimelineTime(0, month: 1, day: 21))),
    );
    final extent = timelineExtent(_timeline, [_temple]);
    expect(_timeline.positionOf(_temple.start), closeTo(-965 + 31 / 354, 1e-9));
    // An event stands in the middle of its day.
    final temple = _timeline.centreOf(_temple.start);
    expect(temple, closeTo(-965 + 31.5 / 354, 1e-9));
    expect((extent.start, extent.end), (temple - 1, temple + 1));
  });

  testWidgets('the outline shows a timeline, its strip and entries, and '
      'offers its actions', (tester) async {
    final workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).putTimeline(_timeline).putTimelineEntry(_temple).putTimelineEntry(_reign);
    StudyTimeline? opened, edited, deleted;
    StudyTimelineEntry? editedEntry, removed;
    StudyPassage? openedPassage;
    final created = <(String, bool)>[];
    final createdTimelines = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 900,
            child: StudyWorkspacePanel(
              workspaces: [workspace],
              activeWorkspace: workspace,
              currentPassage: const StudyPassage(
                bookIndex: 0,
                chapter: 1,
                verse: 1,
              ),
              useEnglishBookNames: true,
              onCreate: () {},
              onSelect: (_) {},
              onRename: () {},
              onDelete: () {},
              onToggleHighlights: (_) {},
              onCreateGroup: (_) {},
              onEditGroup: (_) {},
              onDeleteGroup: (_) {},
              onBookmarkCurrent: (_) {},
              onOpenPassage: (p) => openedPassage = p,
              onEditPassage: (_) {},
              onUpdatePassage: (_) {},
              onRemovePassage: (_) {},
              onEditWord: (_) {},
              onUpdateWord: (_) {},
              onSwitchWordKind: (_) {},
              onRemoveWord: (_) {},
              onOpenWord: (_) {},
              onCreateNote: (_) {},
              onEditNote: (_) {},
              onUpdateNote: (_) {},
              onRemoveNote: (_) {},
              onMoveItem: (_, _, _) {},
              onCreateTimeline: createdTimelines.add,
              onOpenTimeline: (t) => opened = t,
              onEditTimeline: (t) => edited = t,
              onDeleteTimeline: (t) => deleted = t,
              onCreateTimelineEntry: (id, span) => created.add((id, span)),
              onEditTimelineEntry: (e) => editedEntry = e,
              onRemoveTimelineEntry: (e) => removed = e,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Kings'), findsOneWidget);
    // The strip's first and last times.
    expect(find.text('970 BC'), findsOneWidget);
    expect(find.text('931 BC'), findsOneWidget);
    // Entries in time order, with their times, verses and notes.
    expect(
      tester.getTopLeft(find.text('Solomon reigns')).dy,
      lessThan(tester.getTopLeft(find.text('Temple begun')).dy),
    );
    expect(find.text('970 BC – 931 BC'), findsOneWidget);
    expect(find.text('c. 2 Iyyar 966 BC'), findsOneWidget);
    expect(find.text('In the fourth year'), findsOneWidget);
    await tester.tap(find.text('1 Kings 6:1'));
    expect(openedPassage?.chapter, 6);

    await tester.tap(find.byKey(const ValueKey('timeline-strip-kings')));
    expect(opened?.id, 'kings');

    for (final (label, check) in [
      ('Add event', () => created.last == ('kings', false)),
      ('Add span', () => created.last == ('kings', true)),
      ('Edit timeline', () => edited?.id == 'kings'),
      ('Delete timeline', () => deleted?.id == 'kings'),
    ]) {
      await tester.tap(find.byTooltip('Timeline options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(check(), isTrue, reason: label);
    }

    await tester.tap(find.text('Temple begun'));
    expect(editedEntry?.id, 'temple');
    await tester.tap(find.byTooltip('Event options'));
    await tester.pumpAndSettle();
    // With one timeline there is nowhere to move an entry to.
    expect(find.text('Move to timeline'), findsNothing);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed?.id, 'temple');

    await tester.tap(find.byTooltip('Add study item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New timeline'));
    await tester.pumpAndSettle();
    expect(createdTimelines, [null]);
  });

  testWidgets('the entry editor saves a BC span and its linked verses', (
    tester,
  ) async {
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: const StudyTimelineEntry(
                    id: 'new',
                    title: '',
                    timelineId: 'kings',
                    start: TimelineTime(0),
                    end: TimelineTime(0),
                    verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
                  ),
                  creating: true,
                  timelines: const [_timeline],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    expect(find.text('New timeline span'), findsOneWidget);
    expect(find.text('1 Kings 6:1'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Give the span a title.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-title')),
      'Building the temple',
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-start')),
      '966',
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-end')),
      '970',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    // 970 BC is before 966 BC.
    expect(find.text('The end must be at or after the start.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-end')),
      '959',
    );

    final addVerses = find.byKey(const ValueKey('timeline-entry-add-verses'));
    // Off the end field, which would keep itself in view.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(addVerses);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-entry-add-verses')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    // The same verse is linked once only.
    expect(find.text('1 Kings 6:1'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(saved?.title, 'Building the temple');
    expect(saved?.start, const TimelineTime(-966));
    expect(saved?.end, const TimelineTime(-959));
    expect(saved?.duration, isNull);
    expect(saved?.verses.single.reference, '6:1');
  });

  testWidgets('a span may be given a start month and day and a duration', (
    tester,
  ) async {
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: const StudyTimelineEntry(
                    id: 'new',
                    title: '',
                    timelineId: 'kings',
                    start: TimelineTime(0),
                    end: TimelineTime(0),
                  ),
                  creating: true,
                  timelines: const [_timeline],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-title')),
      'Building the temple',
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-start')),
      '966',
    );
    await tester.tap(
      find.byKey(const ValueKey('timeline-entry-start-month-12')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 · Iyyar').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duration'));
    await tester.pumpAndSettle();
    // With a month but no day the length may be in years or months.
    expect(find.text('Give the start a day to count days.'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-entry-start-day-2-29')),
    );
    await tester.tap(
      find.byKey(const ValueKey('timeline-entry-start-day-2-29')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(find.text('Give the start a day to count days.'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-duration')),
      '7',
    );
    await tester.pump();
    expect(find.text('Ends 2 Iyyar 959 BC'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(saved?.start, const TimelineTime(-966, month: 2, day: 2));
    expect(saved?.end, const TimelineTime(-959, month: 2, day: 2));
    expect(
      saved?.duration,
      const TimelineDuration(7, TimelineDurationUnit.years),
    );
    expect(
      timelineEntryTime(_timeline, saved!),
      '2 Iyyar 966 BC – 2 Iyyar 959 BC (7 years)',
    );
  });

  testWidgets('the timeline editor counts in a unit of its own', (
    tester,
  ) async {
    StudyTimeline? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimeline>(
                context: context,
                builder: (_) => const StudyTimelineEditor(
                  initial: StudyTimeline(
                    id: 't',
                    title: '',
                    scale: TimelineScale.calendar,
                  ),
                  creating: true,
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
    expect(find.byKey(const ValueKey('timeline-unit')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('timeline-scale')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Another unit, such as days').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('timeline-title')),
      'Creation week',
    );
    await tester.enterText(find.byKey(const ValueKey('timeline-unit')), 'Day');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(saved?.title, 'Creation week');
    expect(saved?.scale, TimelineScale.units);
    expect(saved?.formatTime(const TimelineTime(3)), 'Day 3');
  });

  testWidgets("the timeline page fits to its entries, not a year's calendar, "
      'and zooms into a stretch dragged across', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    const trumpets = StudyTimelineEntry(
      id: 'trumpets',
      title: 'Trumpets',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 7, day: 1),
    );
    const booths = StudyTimelineEntry(
      id: 'booths',
      title: 'Booths',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 7, day: 15),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: const [trumpets, booths],
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    double x(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('timeline-mark-$id'))).dx;
    void expectFitted() {
      // Both in view, a fortnight apart spread across most of it.
      expect(x('trumpets'), inInclusiveRange(0, width));
      expect(x('booths'), inInclusiveRange(0, width));
      expect(x('booths') - x('trumpets'), greaterThan(width / 2));
    }

    expectFitted();
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(x('booths') - x('trumpets'), lessThan(width / 2));
    await tester.tap(find.byTooltip('Fit to entries'));
    await tester.pumpAndSettle();
    expectFitted();

    // A mouse drag over the first few days zooms into them.
    final chart = tester.getRect(
      find.byKey(const ValueKey('timeline-drag-zoom')),
    );
    final y = chart.bottom - 10;
    final gesture = await tester.startGesture(
      Offset(x('trumpets') - 4, y),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(Offset((x('booths') - x('trumpets')) / 3, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(x('trumpets'), inInclusiveRange(0, width));
    expect(x('booths'), greaterThan(width));

    // On touch, a drag scrolls, unless picking a stretch is turned on.
    await tester.tap(find.byTooltip('Fit to entries'));
    await tester.pumpAndSettle();
    final before = x('booths') - x('trumpets');
    await tester.dragFrom(Offset(x('trumpets'), y), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(x('booths') - x('trumpets'), closeTo(before, 1));
    await tester.tap(find.byTooltip('Fit to entries'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Drag across the timeline to zoom in'));
    await tester.pump();
    await tester.dragFrom(
      Offset(x('trumpets') - 4, y),
      Offset((x('booths') - x('trumpets')) / 3, 0),
    );
    await tester.pumpAndSettle();
    expect(x('booths'), greaterThan(width));
  });

  testWidgets('the timeline page draws entries and opens their verses', (
    tester,
  ) async {
    StudyPassage? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TimelinePage(
                  timeline: _timeline,
                  entries: const [_temple, _reign],
                  useEnglishBookNames: true,
                  onOpenPassage: (p) => opened = p,
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
    expect(find.byKey(const ValueKey('timeline-mark-reign')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-mark-temple')), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-row-temple')));
    await tester.pumpAndSettle();
    expect(find.text('In the fourth year'), findsOneWidget);
    await tester.tap(find.text('1 Kings 6:1'));
    await tester.pumpAndSettle();
    expect(opened?.chapter, 6);
    // The page closes back to the reader.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the timeline editor takes chosen leap years with their era', (
    tester,
  ) async {
    StudyTimeline? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimeline>(
                context: context,
                builder: (_) => const StudyTimelineEditor(
                  initial: StudyTimeline(
                    id: 't',
                    title: 'Exodus',
                    scale: TimelineScale.calendar,
                  ),
                  creating: false,
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
    await tester.tap(find.byKey(const ValueKey('timeline-leap-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Fixed 19-year cycle'), findsWidgets);
    await tester.tap(find.text('In chosen years').last);
    await tester.pumpAndSettle();
    final years = find.byKey(const ValueKey('timeline-leap-years'));
    await tester.enterText(years, '1446');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Write each year with BC or AD, as 1446 BC.'),
      findsOneWidget,
    );
    await tester.enterText(years, '1446 BC, 1443 bc; AD 30');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.leapMonths, TimelineLeapMonths.chosen);
    expect(saved?.leapYears, {-1446, -1443, 30});
  });

  testWidgets("an entry on a year's calendar takes a month and day only", (
    tester,
  ) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: const StudyTimelineEntry(
                    id: 'new',
                    title: '',
                    timelineId: 'feasts',
                    start: TimelineTime(0),
                    end: TimelineTime(0),
                  ),
                  creating: true,
                  timelines: const [feasts],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    // No year to enter.
    expect(find.byKey(const ValueKey('timeline-entry-start')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-title')),
      'Unleavened Bread',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Enter when it starts.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('timeline-entry-start-month-12')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 · Nisan').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('timeline-entry-start-day-1-30')),
    );
    await tester.pumpAndSettle();
    // The menu builds only the days in view.
    await tester.scrollUntilVisible(
      find.text('15'),
      48,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duration'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-duration')),
      '7',
    );
    await tester.pump();
    expect(find.text('Ends 21 Nisan'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(saved?.start, const TimelineTime(0, month: 1, day: 15));
    expect(saved?.end, const TimelineTime(0, month: 1, day: 21));
    expect(
      saved?.duration,
      const TimelineDuration(7, TimelineDurationUnit.days),
    );
  });

  testWidgets('the timeline page adds, edits and removes entries in place', (
    tester,
  ) async {
    var timeline = _timeline;
    var entries = [_temple];
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TimelinePage(
                  timeline: timeline,
                  entries: entries,
                  useEnglishBookNames: true,
                  onOpenPassage: (_) {},
                  reload: () => (timeline: timeline, entries: entries),
                  onEditTimeline: () async {
                    calls.add('timeline');
                    timeline = timeline.copyWith(title: 'Kings of Israel');
                  },
                  onAddEntry: (span, _, {sabbath = false, anchor}) async {
                    calls.add('add ${span ? 'span' : 'event'}');
                    entries = [...entries, _reign];
                  },
                  onEditEntry: (entry) async {
                    calls.add('edit ${entry.id}');
                    entries = [
                      for (final e in entries)
                        e.id == entry.id ? e.copyWith(title: 'Temple') : e,
                    ];
                  },
                  onRemoveEntry: (entry) async {
                    calls.add('remove ${entry.id}');
                    entries = [
                      for (final e in entries)
                        if (e.id != entry.id) e,
                    ];
                  },
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

    await tester.tap(find.byTooltip('Edit timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Kings of Israel'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to timeline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add span'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-row-reign')), findsOneWidget);

    await tester.tap(find.byTooltip('Edit event'));
    await tester.pumpAndSettle();
    expect(find.text('Temple'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('timeline-row-temple')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-row-temple')), findsNothing);
    expect(calls, ['timeline', 'add span', 'edit temple', 'remove temple']);
  });

  testWidgets('an event is pinned into a span in the editor, and listed and '
      'added from the span', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    const unleavened = StudyTimelineEntry(
      id: 'unleavened',
      title: 'Unleavened Bread',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 15),
      end: TimelineTime(0, month: 1, day: 21),
    );
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: const StudyTimelineEntry(
                    id: 'wave',
                    title: 'Wave sheaf',
                    timelineId: 'feasts',
                    start: TimelineTime(0, month: 1, day: 17),
                  ),
                  creating: false,
                  timelines: const [feasts],
                  entries: const [unleavened],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    await tester.tap(find.byKey(const ValueKey('timeline-entry-pin-feasts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unleavened Bread').last);
    await tester.pumpAndSettle();
    // Its day in the span is taken from when it was.
    expect(find.text('3'), findsOneWidget);
    expect(
      find.text('Falls on 17 Nisan, moving with Unleavened Bread'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-offset')),
      '10',
    );
    // Then moved on to the Sabbath after.
    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-entry-weekday')),
    );
    await tester.tap(find.byKey(const ValueKey('timeline-entry-weekday')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The first Sabbath from it').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Day 10 of seven still counts on from the start, to 24 Nisan, a 3rd
    // day of the week; the Sabbath after is the 28th.
    expect(
      saved?.pin,
      const TimelinePin(
        'unleavened',
        TimelineDuration(10, TimelineDurationUnit.days),
        weekday: 7,
      ),
    );
    expect(saved?.start, const TimelineTime(0, month: 1, day: 28));

    // The span lists it, and adds another in it.
    final pinned = saved!;
    StudyTimelineEntry? addedTo;
    StudyTimelineEntry? duplicated;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: [unleavened, pinned],
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          reload: () => (timeline: feasts, entries: [unleavened, pinned]),
          onAddEntry: (span, at, {sabbath = false, anchor}) async {
            addedTo = anchor;
          },
          onDuplicateEntry: (entry) async => duplicated = entry,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('28 Nisan · The first Sabbath from day 10 of Unleavened Bread'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('timeline-row-unleavened')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-pinned-wave')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timeline-add-pinned')));
    await tester.pumpAndSettle();
    expect(addedTo?.id, 'unleavened');
    await tester.tap(find.byKey(const ValueKey('timeline-row-unleavened')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-duplicate')));
    await tester.pumpAndSettle();
    expect(duplicated?.id, 'unleavened');
  });

  testWidgets('a counted span numbers its days and weeks on the page and '
      'the calendar', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    // Fifty days, from 16 Nisan to 6 Sivan.
    const count = StudyTimelineEntry(
      id: 'count',
      title: 'The count',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 16),
      end: TimelineTime(0, month: 3, day: 6),
      counted: true,
    );
    const pentecost = StudyTimelineEntry(
      id: 'pentecost',
      title: 'Pentecost',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 3, day: 6),
    );
    expect(feasts.daysIn(count), 50);
    expect(feasts.countIn(count, const TimelineTime(0, month: 2, day: 1)), (
      day: 16,
      week: 3,
      dayOfWeek: 2,
    ));
    expect(
      feasts.countIn(count, const TimelineTime(0, month: 3, day: 7)),
      isNull,
    );
    expect(StudyTimelineEntry.fromJson(count.toJson())?.isCounted, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: const [count, pentecost],
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-row-count')));
    await tester.pumpAndSettle();
    expect(find.text('Counted, 50 days: 7 weeks and 1 day'), findsOneWidget);
    Navigator.of(tester.element(find.text('The count').last)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-row-pentecost')));
    await tester.pumpAndSettle();
    expect(find.text('Day 50 of The count: week 8, day 1'), findsOneWidget);
    Navigator.of(tester.element(find.text('Pentecost').last)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show calendar'));
    await tester.pumpAndSettle();
    Text countOn(int month, int day) =>
        tester.widget(find.byKey(ValueKey('calendar-count-$month-$day')));
    expect(countOn(1, 16).data, '1');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('calendar-count-3-6')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(countOn(3, 6).data, '50');
    expect(find.byKey(const ValueKey('calendar-count-3-7')), findsNothing);
  });

  testWidgets('an event falls in a part of its day, which runs from sunset', (
    tester,
  ) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    const day14 = TimelineTime(0, month: 1, day: 14);
    StudyTimelineEntry at(String id, TimelineDayPart? part) =>
        StudyTimelineEntry(
          id: id,
          title: id,
          timelineId: 'feasts',
          start: day14,
          part: part,
        );
    final evening = at('killed', TimelineDayPart.evening);
    final night = at('night', TimelineDayPart.night);
    final whole = at('whole', null);
    // Night, then day, then evening, across the day's stretch.
    final from = feasts.positionOf(day14);
    final to = feasts.endOf(day14);
    double point(StudyTimelineEntry e) => timelineEntryReach(feasts, e).start;
    expect(point(night), inExclusiveRange(from, point(whole)));
    expect(point(evening), inExclusiveRange(point(whole), to));
    expect(
      ([evening, whole, night]..sort(compareTimelineEntries)).map((e) => e.id),
      ['whole', 'night', 'killed'],
    );
    expect(
      timelineEntryTime(feasts, evening),
      '14 Nisan, between the evenings',
    );
    expect(
      StudyTimelineEntry.fromJson(evening.toJson())?.part,
      TimelineDayPart.evening,
    );
    // A span, or a time without its day, has no part.
    expect(evening.withTime(start: day14, end: day14).dayPart, isNull);
    // Each of a year's days has its night, the first half.
    final nights = timelineNights(feasts, 0, 1);
    expect(nights, hasLength(354));
    expect(nights.first.to - nights.first.from, closeTo(0.5 / 354, 1e-12));

    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: whole,
                  creating: false,
                  timelines: const [feasts],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-entry-part')),
    );
    await tester.tap(find.text('Evening'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.part, TimelineDayPart.evening);
  });

  testWidgets('seasons of the land and the moons show on the timeline and '
      'its calendar, kept with the timeline', (tester) async {
    var feasts = const StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    const passover = StudyTimelineEntry(
      id: 'passover',
      title: 'Passover',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
    );
    // A year's seasons, each within it; and its new and full moons.
    final bands = timelineSeasonsIn(feasts, 0, 1);
    expect(
      bands.map((b) => b.season.name),
      contains('Qetsir seʿorim (barley harvest)'),
    );
    for (final band in bands) {
      expect(band.start, greaterThanOrEqualTo(0));
      expect(band.end, lessThanOrEqualTo(1 + 1e-9));
    }
    expect(timelineMoons(feasts, 0, 1), hasLength(24));
    expect(timelineMoons(feasts, 0, 1).where((m) => m.full), hasLength(12));
    // The latter rain runs to the year's end, through Adar II in a leap
    // year.
    final leap = feasts.copyWith(leapMonths: TimelineLeapMonths.chosen);
    final adar = timelineSeasons.firstWhere((s) => s.to == null);
    expect(adar.inYear(leap, 0).end, closeTo(1, 1e-9));
    expect(
      StudyTimeline.fromJson(
        feasts.copyWith(showSeasons: true).toJson(),
      )?.showSeasons,
      isTrue,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: const [passover],
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          reload: () => (timeline: feasts, entries: const [passover]),
          onUpdateTimeline: (changed) async => feasts = changed,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('timeline-season-Qetsir seʿorim (barley harvest)'),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Show seasons'));
    await tester.pumpAndSettle();
    expect(feasts.showSeasons, isTrue);
    expect(
      find.byKey(
        const ValueKey('timeline-season-Qetsir seʿorim (barley harvest)'),
      ),
      findsWidgets,
    );

    await tester.tap(find.byTooltip('Show calendar'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('calendar-season-1-Qetsir seʿorim (barley harvest)'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar-moon-1-15')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-moon-1-14')), findsNothing);
  });

  testWidgets('the year wheel sets the feasts round the year, and opens '
      'one tapped', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
      showSeasons: true,
    );
    StudyTimelineEntry event(String id, int month, int day) =>
        StudyTimelineEntry(
          id: id,
          title: id,
          timelineId: 'feasts',
          start: TimelineTime(0, month: month, day: day),
        );
    final passover = event('Passover', 1, 14);
    final firstDay = event('First day', 1, 15);
    final trumpets = event('Trumpets', 7, 1);
    const unleavened = StudyTimelineEntry(
      id: 'unleavened',
      title: 'Unleavened Bread',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 15),
      end: TimelineTime(0, month: 1, day: 21),
    );
    const tabernacles = StudyTimelineEntry(
      id: 'tabernacles',
      title: 'Tabernacles',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 7, day: 15),
      end: TimelineTime(0, month: 7, day: 21),
    );
    final entries = [passover, firstDay, trumpets, unleavened, tabernacles];
    final marks = timelineWheelMarks(feasts, entries, 0);
    TimelineWheelMark mark(String id) =>
        marks.singleWhere((m) => m.entry.id == id);
    // Trumpets stands about half the year round from Passover.
    expect(mark('Trumpets').from - mark('Passover').from, closeTo(0.5, 0.05));
    // Events a day apart take rings of labels of their own.
    expect(mark('First day').labelRadius, isNot(mark('Passover').labelRadius));
    // Spans apart round the wheel share a ring of arcs.
    expect(mark('unleavened').radius, mark('tabernacles').radius);
    expect(mark('unleavened').to, greaterThan(mark('unleavened').from));

    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: entries,
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show year wheel'));
    await tester.pumpAndSettle();
    final wheel = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-wheel')),
        matching: find.byType(CustomPaint),
      ),
    );
    final radius = wheel.shortestSide / 2;
    Offset at(TimelineWheelMark m) =>
        timelineWheelPoint(wheel.center, m.radius * radius, m.from);
    await tester.tapAt(at(mark('Trumpets')));
    await tester.pumpAndSettle();
    expect(find.text('1 Tishri'), findsOneWidget);
    Navigator.of(tester.element(find.text('1 Tishri'))).pop();
    await tester.pumpAndSettle();
    await tester.tapAt(
      timelineWheelPoint(
        wheel.center,
        mark('tabernacles').radius * radius,
        (mark('tabernacles').from + mark('tabernacles').to) / 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('15 Tishri – 21 Tishri'), findsOneWidget);
    Navigator.of(tester.element(find.text('15 Tishri – 21 Tishri'))).pop();
    await tester.pumpAndSettle();
    // A season tapped says what it is: the barley harvest on 1 Iyyar.
    await tester.tapAt(
      timelineWheelPoint(wheel.center, 0.8 * radius, 30 / 354),
    );
    await tester.pump();
    expect(
      find.textContaining('Qetsir seʿorim (barley harvest) · Exodus 9:31-32'),
      findsOneWidget,
    );
  });

  testWidgets('categories colour entries, which a key shows and hides, and '
      'recolours', (tester) async {
    var feasts = const StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    StudyTimelineEntry event(String id, int month, int day, String category) =>
        StudyTimelineEntry(
          id: id,
          title: id,
          timelineId: 'feasts',
          start: TimelineTime(0, month: month, day: day),
          category: category,
        );
    final passover = event('passover', 1, 14, 'Pilgrim feast');
    final trumpets = event('trumpets', 7, 1, 'Holy convocation');
    // Each category new to the timeline takes the next free colour, as an
    // entry with it is put there.
    var workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).putTimeline(feasts).putTimelineEntry(passover).putTimelineEntry(trumpets);
    feasts = workspace.timelineById('feasts')!;
    expect(feasts.categoryColors, {'Pilgrim feast': 0, 'Holy convocation': 1});
    expect(feasts.colorOf(trumpets), 1);
    expect(
      StudyTimeline.fromJson(feasts.toJson())?.categoryColors,
      feasts.categoryColors,
    );
    expect(
      StudyTimelineEntry.fromJson(passover.toJson())?.category,
      'Pilgrim feast',
    );

    final entries = [passover, trumpets];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: entries,
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          reload: () => (timeline: feasts, entries: entries),
          onUpdateTimeline: (changed) async => feasts = changed,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-row-trumpets')), findsOneWidget);
    await tester.tap(find.text('Holy convocation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-row-trumpets')), findsNothing);
    expect(find.byKey(const ValueKey('timeline-mark-trumpets')), findsNothing);
    expect(find.byKey(const ValueKey('timeline-row-passover')), findsOneWidget);
    await tester.tap(find.text('Holy convocation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-row-trumpets')), findsOneWidget);

    await tester.tap(find.byTooltip('Colour Pilgrim feast'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-color-3')));
    await tester.pumpAndSettle();
    expect(feasts.categoryColors['Pilgrim feast'], 3);

    // The editor offers the categories already on the timeline.
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: event('booths', 7, 15, ''),
                  creating: false,
                  timelines: [feasts],
                  entries: entries,
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pilgrim feast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.category, 'Pilgrim feast');
  });

  testWidgets("a span's days take notes, entered in the editor and shown "
      'day by day', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    const tabernacles = StudyTimelineEntry(
      id: 'tabernacles',
      title: 'Tabernacles',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 7, day: 15),
      end: TimelineTime(0, month: 7, day: 21),
    );
    expect(
      feasts.dayIn(tabernacles, const TimelineTime(0, month: 7, day: 17)),
      3,
    );
    expect(
      feasts.dayIn(tabernacles, const TimelineTime(0, month: 7, day: 22)),
      isNull,
    );
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: tabernacles,
                  creating: false,
                  timelines: const [feasts],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-entry-day-notes')),
    );
    await tester.tap(find.text('Notes for each day'));
    await tester.pumpAndSettle();
    // Seven days, from 15 Tishri.
    expect(find.text('Day 1 · 15 Tishri'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('timeline-entry-day-note-7')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('timeline-entry-day-note-8')),
      findsNothing,
    );
    for (var day = 1; day <= 7; day++) {
      final field = find.byKey(ValueKey('timeline-entry-day-note-$day'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '${14 - day} bulls');
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.dayNotes[1], '13 bulls');
    expect(saved?.dayNotes[7], '7 bulls');
    expect(
      StudyTimelineEntry.fromJson(saved!.toJson())?.dayNotes,
      saved!.dayNotes,
    );

    final noted = saved!;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: [noted],
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-row-tabernacles')));
    await tester.pumpAndSettle();
    expect(find.text('Day by day'), findsOneWidget);
    expect(find.text('Day 3 · 17 Tishri'), findsOneWidget);
    expect(find.text('11 bulls'), findsOneWidget);
    // Each day's bar is drawn to its number of bulls.
    final first = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-day-note-1')),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(first.width, greaterThan(0));
    Navigator.of(tester.element(find.text('Day by day'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show calendar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('calendar-day-7-17')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-day-7-17')));
    await tester.pumpAndSettle();
    expect(find.text('Tabernacles, day 3: 11 bulls'), findsOneWidget);
  });

  testWidgets('an entry links to one on another timeline or the Bible '
      "timeline, picked in the editor, and its sheet opens it", (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    const passion = StudyTimeline(
      id: 'passion',
      title: 'Passion week',
      scale: TimelineScale.calendar,
    );
    const cross = StudyTimelineEntry(
      id: 'cross',
      title: 'Crucifixion',
      timelineId: 'passion',
      start: TimelineTime(30, month: 1, day: 14),
    );
    const passover = StudyTimelineEntry(
      id: 'passover',
      title: 'Passover',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
    );
    var loads = 0;
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: passover,
                  creating: false,
                  timelines: const [feasts, passion],
                  entries: const [passover, cross],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
                  loadBibleEntries: () async {
                    loads++;
                    return const [
                      StudyTimelineEntry(
                        id: '412',
                        title: 'The Last Supper',
                        timelineId: bibleTimelineId,
                        start: TimelineTime(30),
                      ),
                      StudyTimelineEntry(
                        id: '7',
                        title: 'The Flood',
                        timelineId: bibleTimelineId,
                        start: TimelineTime(-2348),
                      ),
                    ];
                  },
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
    // The other timeline is offered first.
    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-entry-add-link')),
    );
    await tester.tap(find.byKey(const ValueKey('timeline-entry-add-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-link-choice-cross')));
    await tester.pumpAndSettle();
    expect(find.text('Crucifixion · Passion week'), findsOneWidget);
    // Then the Bible's, read only when chosen, found by title.
    expect(loads, 0);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-entry-add-link')),
    );
    await tester.tap(find.byKey(const ValueKey('timeline-entry-add-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-link-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bible timeline').last);
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.enterText(
      find.byKey(const ValueKey('timeline-link-search')),
      'supper',
    );
    await tester.pumpAndSettle();
    expect(find.text('The Flood'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('timeline-link-choice-412')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.links, const [
      TimelineLink('passion', 'cross'),
      TimelineLink(bibleTimelineId, '412'),
    ]);
    expect(saved?.links.last.title, 'The Last Supper');

    // Its sheet lists the links, and opens one tapped.
    TimelineLink? opened;
    final linked = saved!;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: feasts,
          entries: [linked],
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          linksOf: (entry) => [
            for (final link in entry.links)
              (
                link: link,
                title: link.title,
                timelineTitle: link.timelineId,
                back: false,
              ),
          ],
          onOpenLink: (link) => opened = link,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-row-passover')));
    await tester.pumpAndSettle();
    expect(find.text('Linked'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('timeline-link-$bibleTimelineId-412')),
    );
    await tester.pumpAndSettle();
    expect(opened, const TimelineLink(bibleTimelineId, '412'));
  });

  testWidgets('the calendar draws a span across its weeks, its pinned '
      'events beneath it', (tester) async {
    // 1 Nisan on the 4th day of the week: the feast runs from a 4th day
    // into the next week.
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
      nisanWeekday: 4,
    );
    const unleavened = StudyTimelineEntry(
      id: 'unleavened',
      title: 'Unleavened Bread',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 15),
      end: TimelineTime(0, month: 1, day: 21),
    );
    const passover = StudyTimelineEntry(
      id: 'passover',
      title: 'Passover',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
    );
    final wave =
        const StudyTimelineEntry(
          id: 'wave',
          title: 'Wave sheaf',
          timelineId: 'feasts',
          start: TimelineTime(0, month: 1, day: 19),
        ).pinnedTo(
          const TimelinePin(
            'unleavened',
            TimelineDuration(5, TimelineDurationUnit.days),
          ),
        );
    TimelineTime? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineCalendar(
            timeline: feasts,
            entries: [passover, unleavened, wave],
            year: 0,
            onTapDay: (day) => tapped = day,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A bar in each of the two weeks it runs in, and none in others.
    final bars = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'calendar-span-unleavened-1-',
          ),
    );
    expect(bars, findsNWidgets(2));
    // The wave sheaf beneath the bar on its day, not a dot in its cell.
    final pinned = find.byKey(
      const ValueKey('calendar-pinned-unleavened-wave'),
    );
    expect(pinned, findsOneWidget);
    expect(
      tester.getCenter(pinned).dx,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('calendar-day-1-19'))).dx,
        2,
      ),
    );
    expect(
      tester.getTopLeft(pinned).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('calendar-day-1-19')))
            .dy,
      ),
    );
    await tester.tap(pinned);
    expect(tapped, const TimelineTime(0, month: 1, day: 19));
  });

  testWidgets('a timeline built on the moʿadim shows them faded beneath its '
      'own, and pins its own to them', (tester) async {
    final standard = standardTimelineById('moadim')!;
    var workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).addStandardTimeline(standard, id: 'm');
    // The editor builds it on the moʿadim, set in a year.
    StudyTimeline? created;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              created = await showDialog<StudyTimeline>(
                context: context,
                builder: (_) => StudyTimelineEditor(
                  initial: const StudyTimeline(
                    id: 'passion',
                    title: '',
                    scale: TimelineScale.annual,
                  ),
                  creating: true,
                  bases: workspace.timelines,
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
    await tester.enterText(
      find.byKey(const ValueKey('timeline-title')),
      'The last week',
    );
    await tester.tap(find.byKey(const ValueKey('timeline-base-annual')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(standard.template.title).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('timeline-year')));
    await tester.enterText(find.byKey(const ValueKey('timeline-year')), '33');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
      find.text('Write the year with BC or AD, as AD 30.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-year')),
      'AD 33',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(created?.baseId, 'm');
    expect(created?.year, 33);

    // The entry editor offers the moʿadim to pin to.
    workspace = workspace.putTimeline(created!);
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: const StudyTimelineEntry(
                    id: 'risen',
                    title: 'Raised',
                    timelineId: 'passion',
                    start: TimelineTime(0, month: 1, day: 1),
                  ),
                  creating: false,
                  timelines: [created!],
                  entries: workspace.timelineEntries,
                  anchorsFor: workspace.viewOf,
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    await tester.tap(find.byKey(const ValueKey('timeline-entry-pin-passion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ʿOmer haTenufah (sheaf of the waving)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-offset')),
      '1',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.pin?.anchorId, 'm:omer');
    workspace = workspace.putTimelineEntry(saved!);

    // Its page: the moʿadim faded beneath, changed only where they are, but
    // counted from.
    StudyTimelineEntry? anchored;
    final view = workspace.viewOf('passion');
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: workspace.viewTimeline('passion')!,
          entries: view,
          baseTitles: {'m': standard.template.title},
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          reload: () =>
              (timeline: workspace.viewTimeline('passion')!, entries: view),
          onAddEntry: (span, at, {sabbath = false, anchor}) async =>
              anchored = anchor,
          onEditEntry: (_) async {},
          onRemoveEntry: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The last week · AD 33'), findsOneWidget);
    Opacity fade(String id) => tester.widget(
      find
          .ancestor(
            of: find.byKey(ValueKey('timeline-mark-$id')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(fade('m:pesach').opacity, 0.45);
    expect(fade('risen').opacity, 1);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('timeline-row-m:omer')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    // Midway, the whole row within the page.
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('timeline-row-m:omer'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-row-m:omer')));
    await tester.pumpAndSettle();
    expect(find.text('From ${standard.template.title}'), findsOneWidget);
    expect(find.text('Edit event'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-add-pinned')),
    );
    await tester.tap(find.byKey(const ValueKey('timeline-add-pinned')));
    await tester.pumpAndSettle();
    expect(anchored?.id, 'm:omer');
  });

  testWidgets('a shabbaton is drawn as its whole day, the height of the '
      'chart, behind the rest', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    const day15 = TimelineTime(0, month: 1, day: 15);
    const shabbaton = StudyTimelineEntry(
      id: 'first',
      title: 'Miqra qodesh',
      timelineId: 'feasts',
      start: day15,
      sabbath: true,
    );
    const pesach = StudyTimelineEntry(
      id: 'pesach',
      title: 'Pesach',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
    );
    StudyTimelineEntry? tapped;
    const ppu = 354 * 40.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimelineChart(
              timeline: feasts,
              entries: const [pesach, shabbaton],
              pixelsPerUnit: ppu,
              onTapEntry: (e) => tapped = e,
            ),
          ),
        ),
      ),
    );
    final chart = tester.getRect(find.byType(TimelineChart));
    final block = tester.getRect(
      find.byKey(const ValueKey('timeline-mark-first')),
    );
    // Its day, sundown to sundown: 40 pixels a day here.
    expect(block.width, closeTo(40, 0.5));
    expect(
      block.left - chart.left,
      closeTo(TimelineChart.padding + feasts.positionOf(day15) * ppu, 0.5),
    );
    // From the top down to the axis, taking no lane: Pesach alone has one.
    expect(block.top, chart.top);
    expect(chart.height, TimelineChart.laneHeight + TimelineChart.axisHeight);
    expect(block.height, greaterThan(TimelineChart.laneHeight));
    await tester.tapAt(Offset(block.center.dx, block.bottom - 4));
    expect(tapped?.id, 'first');
  });

  testWidgets('a shabbaton is shaded in its category\'s colour', (
    tester,
  ) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
      categoryColors: {'Qodesh': 3},
    );
    const shabbaton = StudyTimelineEntry(
      id: 'first',
      title: 'Miqra qodesh',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 15),
      sabbath: true,
      category: 'Qodesh',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimelineChart(
              timeline: feasts,
              entries: [shabbaton],
              pixelsPerUnit: 354 * 40.0,
            ),
          ),
        ),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('timeline-mark-first')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    final colour = timelineCategoryColor(3, Brightness.light);
    expect(decoration.color?.withValues(alpha: 1), colour);
    expect(
      (decoration.border! as Border).left.color.withValues(alpha: 1),
      colour,
    );
  });

  testWidgets('the calendar shows Sabbaths and adds high Sabbath events', (
    tester,
  ) async {
    var timeline = const StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    var entries = const [
      StudyTimelineEntry(
        id: 'passover',
        title: 'Passover',
        timelineId: 'feasts',
        start: TimelineTime(0, month: 1, day: 14),
      ),
    ];
    final added = <(TimelineTime?, bool)>[];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePage(
          timeline: timeline,
          entries: entries,
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          initialCalendar: true,
          reload: () => (timeline: timeline, entries: entries),
          onUpdateTimeline: (changed) async => timeline = changed,
          onAddEntry: (span, at, {sabbath = false, anchor}) async {
            added.add((at, sabbath));
            // As the reader would, once the editor is saved.
            entries = [
              ...entries,
              StudyTimelineEntry(
                id: 'added-${added.length}',
                title: sabbath ? 'First day of Unleavened Bread' : 'Event',
                timelineId: 'feasts',
                start: at!,
                note: sabbath ? 'No servile work' : '',
                sabbath: sabbath,
              ),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-month-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-month-12')), findsOneWidget);
    // No years on a year's calendar.
    expect(find.byKey(const ValueKey('calendar-year')), findsNothing);
    // Nisan starts on the first day, so its 7th is a Sabbath.
    BoxDecoration? decoration(int month, int day) =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(ValueKey('calendar-day-$month-$day')),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration?;
    final scheme = Theme.of(
      tester.element(find.byType(TimelineCalendar)),
    ).colorScheme;
    expect(decoration(1, 7)?.color, scheme.secondaryContainer);
    expect(decoration(1, 15)?.color, isNull);

    // Move the week: 1 Nisan on the Sabbath.
    await tester.tap(find.text('Day 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sabbath').last);
    await tester.pumpAndSettle();
    expect(timeline.nisanWeekday, 7);
    expect(timeline.weekYear, isNull);
    expect(decoration(1, 1)?.color, scheme.secondaryContainer);

    // Keep 15 Nisan as a high Sabbath: an event of its own, with a note.
    await tester.tap(find.byKey(const ValueKey('calendar-day-1-15')));
    await tester.pumpAndSettle();
    expect(find.text('15 Nisan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-high-sabbath')));
    await tester.pumpAndSettle();
    expect(added, [(const TimelineTime(0, month: 1, day: 15), true)]);
    expect(decoration(1, 15)?.color, scheme.tertiaryContainer);
    // Its day now lists it, with its note, and offers no second one.
    await tester.tap(find.byKey(const ValueKey('calendar-day-1-15')));
    await tester.pumpAndSettle();
    expect(find.text('Shabbaton · Sabbath'), findsOneWidget);
    expect(find.text('First day of Unleavened Bread'), findsOneWidget);
    expect(find.textContaining('No servile work'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-high-sabbath')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Add an event on a day.
    await tester.tap(find.byKey(const ValueKey('calendar-day-7-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add event on this day'));
    await tester.pumpAndSettle();
    expect(added.last, (const TimelineTime(0, month: 7, day: 10), false));

    // And back to the timeline.
    await tester.tap(find.byTooltip('Show timeline'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('timeline-mark-passover')),
      findsOneWidget,
    );
  });

  testWidgets('an event marked a high Sabbath needs its day', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: const StudyTimelineEntry(
                    id: 'new',
                    title: '',
                    timelineId: 'kings',
                    start: TimelineTime(0),
                  ),
                  creating: true,
                  timelines: const [_timeline],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
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
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-title')),
      'Day of Atonement',
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-start')),
      '1445',
    );
    await tester.tap(find.byKey(const ValueKey('timeline-entry-sabbath')));
    await tester.pumpAndSettle();
    expect(find.text('New shabbaton'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('A shabbaton needs its month and day.'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('timeline-entry-start-month-12')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 · Tishri').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('timeline-entry-start-day-7-30')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(saved?.isHighSabbath, isTrue);
    expect(saved?.start, const TimelineTime(-1445, month: 7, day: 10));
  });
  testWidgets('a span draws the days before and after it as wedges in its '
      'row, which open it', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    const span = StudyTimelineEntry(
      id: 'sukkot',
      title: 'Sukkot',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 7, day: 15),
      end: TimelineTime(0, month: 7, day: 21),
      lead: TimelineTaper(days: 4, title: 'Going up'),
      trail: TimelineTaper(days: 2),
    );
    StudyTimelineEntry? tapped;
    const ppu = 354 * 80.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimelineChart(
              timeline: feasts,
              entries: const [span],
              pixelsPerUnit: ppu,
              onTapEntry: (e) => tapped = e,
            ),
          ),
        ),
      ),
    );
    final bar = tester.getRect(
      find.byKey(const ValueKey('timeline-mark-sukkot')),
    );
    final lead = tester.getRect(
      find.byKey(const ValueKey('timeline-lead-sukkot')),
    );
    final trail = tester.getRect(
      find.byKey(const ValueKey('timeline-trail-sukkot')),
    );
    // Its four days before it and two after, 80 pixels a day, in its row.
    expect(lead.width, closeTo(320, 0.5));
    expect(lead.right, closeTo(bar.left, 0.5));
    expect(lead.top, bar.top);
    expect(trail.width, closeTo(160, 0.5));
    expect(trail.left, closeTo(bar.left + 7 * 80, 0.5));
    // Zoomed in, the wedge's title fits in it.
    expect(find.text('Going up'), findsOneWidget);
    final trailing = find.byKey(const ValueKey('timeline-trail-sukkot'));
    await tester.ensureVisible(trailing);
    await tester.pumpAndSettle();
    await tester.tap(trailing);
    expect(tapped?.id, 'sukkot');
  });
  testWidgets('an entry shows its short title where its title will not fit, '
      'and its title zoomed in or chosen', (tester) async {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    const pesach = StudyTimelineEntry(
      id: 'pesach',
      title: 'Pesach (the passing over)',
      shortTitle: 'Pesach',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
    );
    const matzot = StudyTimelineEntry(
      id: 'matzot',
      title: 'Matzot',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 17),
    );
    expect(StudyTimelineEntry.fromJson(pesach.toJson())?.shortTitle, 'Pesach');
    Future<void> chart(double ppu, {String? selected}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimelineChart(
              timeline: feasts,
              entries: const [pesach, matzot],
              pixelsPerUnit: ppu,
              selectedId: selected,
            ),
          ),
        ),
      ),
    );
    // Three days apart at 30 pixels a day: too close for the title.
    await chart(354 * 30.0);
    expect(find.text('Pesach'), findsOneWidget);
    expect(find.text('Pesach (the passing over)'), findsNothing);
    // Chosen, its title, cut short as need be.
    await chart(354 * 30.0, selected: 'pesach');
    expect(find.text('Pesach (the passing over)'), findsOneWidget);
    // Zoomed in, there is room for it.
    await chart(354 * 200.0);
    expect(find.text('Pesach (the passing over)'), findsOneWidget);
  });
}
