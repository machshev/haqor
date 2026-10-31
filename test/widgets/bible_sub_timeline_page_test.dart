import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/event_sequence.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/bible_sub_timeline_page.dart';
import 'package:haqor/src/widgets/bible_timeline_page.dart';
import 'package:haqor/src/widgets/event_sequence_page.dart';
import 'package:haqor/src/widgets/timeline_chart.dart';
import 'package:haqor/src/widgets/timeline_wheel.dart';

BibleEventEntry event(int id, String title, int year, {int duration = 0}) =>
    BibleEventEntry(
      id: id,
      title: title,
      year: year,
      duration: duration,
      unit: duration == 0 ? '' : 'years',
      note: '',
      people: const [],
      places: const [],
      passages: [
        ThematicTarget(
          book: 2,
          chapter: 20,
          verse: 1,
          lastChapter: 20,
          lastVerse: 1,
        ),
      ],
    );
EventSequenceEntry section(String key, List<int> events, {int? expands}) =>
    EventSequenceEntry(
      key: key,
      title: key,
      events: events,
      expands: expands,
      note: '',
      edges: const [],
      groupings: const [],
      milestones: const [],
      details: const [],
    );

void main() {
  for (final key in bibleDatedSections) {
    testWidgets('$key opens a wheel covering its dated events', (tester) async {
      final s = section(key, [1, 2]);
      final events = {
        1: event(1, 'First reign', -955, duration: 41),
        2: event(2, 'Last event', -892),
      };
      await tester.pumpWidget(
        MaterialApp(
          home: BibleSubTimelinePage(
            section: s,
            sequences: BibleSequences([s]),
            events: events,
            useEnglishBookNames: true,
            onOpenPassage: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show time span wheel'));
      await tester.pumpAndSettle();
      final wheel = tester.widget<TimelineWheel>(find.byType(TimelineWheel));
      expect(wheel.cycle!.length, greaterThan(60));
      expect(
        timelineWheelMarks(
          wheel.timeline,
          wheel.entries,
          wheel.year,
          cycle: wheel.cycle,
        ),
        hasLength(2),
      );
      expect(find.textContaining('years per segment'), findsOneWidget);
      expect(find.textContaining('Kingdom of Christ'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'dated membership retains lifetimes and durations without its own anchor',
    () {
      final s = section('abraham', [65, 80, 88], expands: 66);
      final selected = bibleSubTimelineEvents(s, [
        event(65, 'Birth of Abraham', -1996),
        event(66, 'Lifetime of Abraham', -1996, duration: 175),
        event(80, 'Birth of Isaac', -1896),
        event(81, 'Lifetime of Isaac', -1896, duration: 180),
        event(88, 'Death of Abraham', -1821),
        event(100, 'Lifetime of someone else', -1900, duration: 90),
      ]);
      expect(selected.map((e) => e.id), [65, 80, 81, 88]);
      expect(selected.singleWhere((e) => e.id == 81).duration, 180);
      final overview = bibleTimelineEntries(
        selected,
        sequences: BibleSequences([
          section('beginnings', [65, 80, 88]),
        ]),
      );
      expect(overview.first.category, 'Sub-timelines');
    },
  );

  testWidgets(
    'kings open as dated bars and offer event order with back navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final s = section('judah-kings', [1, 2, 3]);
      final events = {
        for (final e in [
          event(1, 'Reign of Asa', -955, duration: 41),
          event(2, 'Reign of Jehoshaphat', -917, duration: 25),
          event(3, 'Death of Asa', -914),
        ])
          e.id: e,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openBibleSection(
                context,
                section: s,
                sequences: BibleSequences([s]),
                events: events,
                useEnglishBookNames: true,
                onOpenPassage: (_) {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(BibleSubTimelinePage), findsOneWidget);
      expect(find.byType(EventSequencePage), findsNothing);
      final page = tester.widget<TimelinePage>(find.byType(TimelinePage));
      expect(page.timeline.scale, TimelineScale.calendar);
      expect(page.timeline.parentId, bibleTimeline.id);
      final asa = page.entries.singleWhere((e) => e.id == '1');
      final jehoshaphat = page.entries.singleWhere((e) => e.id == '2');
      expect(asa.end!.value, -914);
      expect(jehoshaphat.start.value, lessThan(asa.end!.value));
      expect(page.entries.singleWhere((e) => e.id == '3').pin!.anchorId, '1');
      await tester.tap(find.byKey(const ValueKey('bible-section-event-order')));
      await tester.pumpAndSettle();
      expect(find.byType(EventSequencePage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(BibleSubTimelinePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('histories open alone and combine with independent event pins', (
    tester,
  ) async {
    final histories = [
      for (final key in bibleHistoryVariants.keys) section(key, [1, 2]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: BibleSubTimelinePage(
          section: histories[3],
          sequences: BibleSequences(histories),
          events: {
            1: event(1, 'Reign of Asa', -955, duration: 41),
            2: event(2, 'Death of Asa', -914),
          },
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = tester.widget<TimelinePage>(find.byType(TimelinePage));
    expect(page.timeline.id, 'bible-history');
    expect(page.variants, hasLength(5));
    expect(page.entries.map((e) => e.id).toSet(), hasLength(10));
    for (final entry in page.entries.where((e) => e.pin != null)) {
      final anchor = page.entries.singleWhere(
        (e) => e.id == entry.pin!.anchorId,
      );
      expect(anchor.variant, entry.variant);
      expect(anchor.start.value, -955);
    }
    FilterChip chip(String key) => tester.widget<FilterChip>(
      find.byKey(ValueKey('timeline-variant-$key')),
    );
    expect(chip('judah-kings').selected, isTrue);
    expect(chip('prophets').selected, isFalse);
    await tester.tap(find.byKey(const ValueKey('timeline-variant-prophets')));
    await tester.pumpAndSettle();
    expect(chip('judah-kings').selected, isTrue);
    expect(chip('prophets').selected, isTrue);
    await tester.tap(
      find.byKey(const ValueKey('timeline-variant-judah-kings')),
    );
    await tester.pumpAndSettle();
    expect(chip('judah-kings').selected, isFalse);
    expect(chip('prophets').selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('timeline-variant-all')));
    await tester.pumpAndSettle();
    for (final key in bibleHistoryVariants.keys) {
      expect(chip(key).selected, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('deep links traverse a dated parent into a nested narrative', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final moses = section('moses-exodus', [125, 126], expands: 121);
    final sinai = section('sinai', [127, 128], expands: 126);
    final events = {
      for (final e in [
        event(121, 'Lifetime of Moses', -1571, duration: 120),
        event(125, 'Exodus from Egypt', -1491),
        event(126, 'Wilderness Wanderings', -1491, duration: 40),
        event(127, 'Ten Commandments Given', -1491),
        event(128, 'Tabernacle Built', -1490),
      ])
        e.id: e,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: BibleSubTimelinePage(
          section: moses,
          sequences: BibleSequences([moses, sinai]),
          events: events,
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          focusEventId: 128,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final graph = tester.widget<EventSequencePage>(
      find.byType(EventSequencePage),
    );
    expect(graph.sequence.key, 'sinai');
    expect(graph.focusEventId, 128);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final page = tester.widget<TimelinePage>(find.byType(TimelinePage));
    expect(page.entries.map((e) => e.id), ['125', '126']);
    expect(tester.takeException(), isNull);
  });
}
