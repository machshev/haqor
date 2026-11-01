import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/event_sequence.dart';
import 'package:haqor/src/widgets/bible_timeline_page.dart';
import 'package:haqor/src/widgets/event_sequence_page.dart';
import 'package:haqor/src/widgets/sequence_style.dart';

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
          book: 1,
          chapter: 8,
          verse: 15,
          lastChapter: 8,
          lastVerse: 15,
        ),
      ],
    );

EventSequenceEntry sequence(
  String key,
  List<int> events, {
  int? expands,
  List<SequenceEventDetailsEntry> details = const [],
}) => EventSequenceEntry(
  setAside: const [],
  key: key,
  title: key,
  note: '',
  expands: expands,
  events: events,
  edges: const [],
  groupings: const [],
  milestones: const [],
  details: details,
);

void main() {
  test(
    'overview includes ministries and nested events through their full spans',
    () {
      final sequences = BibleSequences([
        sequence('Prophets', [1, 2]),
        sequence('Inside', [3], expands: 2),
      ]);
      final entries = bibleTimelineEntries([
        event(1, 'Prophecies of Haggai', -520, duration: 1),
        event(2, 'A ministry', -500, duration: 20),
        event(3, 'Its last episode', -470, duration: 5),
      ], sequences: sequences);
      expect(entries, hasLength(1));
      expect(entries.single.start.value, -520);
      expect(entries.single.end!.value, -465);
      expect(entries.single.duration!.amount, 55);
    },
  );

  test('a sequence spanning BC and AD has no year zero', () {
    final entries = bibleTimelineEntries(
      [event(1, 'First', -2), event(2, 'Last', 1, duration: 3)],
      sequences: BibleSequences([
        sequence('Across', [1, 2]),
      ]),
    );
    expect(entries.single.end!.value, 4);
    expect(entries.single.duration!.amount, 5);
  });

  test(
    'nested Sinai focuses through Moses while the lifetime stays on the overview',
    () {
      final sequences = BibleSequences([
        sequence('Moses', [125, 126], expands: 121),
        sequence('Sinai', [127, 128], expands: 126),
      ]);
      expect(sequences.pathTo(128).map((s) => s.key), ['Moses', 'Sinai']);
      final entries = bibleTimelineEntries([
        event(121, 'Lifetime of Moses', -1571, duration: 120),
        event(125, 'Exodus from Egypt', -1491),
        event(126, 'Wilderness Wanderings', -1491, duration: 40),
        event(127, 'Ten Commandments Given', -1491),
        event(128, 'Tabernacle Built', -1490),
      ], sequences: sequences);
      expect(entries.map((e) => e.id), ['121']);
      expect(sequences.expanding[int.parse(entries.single.id)]!.key, 'Moses');
    },
  );

  testWidgets('Old Testament kinds render and filter with their source marks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final kinds = [
      SequenceKind.creation,
      SequenceKind.judgement,
      SequenceKind.death,
      SequenceKind.reign,
      SequenceKind.judgeship,
      SequenceKind.prophecy,
    ];
    final events = {
      for (final (i, kind) in kinds.indexed)
        i + 1: event(i + 1, 'Example ${kind.name}', -1000 + i),
    };
    final s = sequence(
      'Old Testament',
      events.keys.toList(),
      details: [
        for (final (i, kind) in kinds.indexed)
          SequenceEventDetailsEntry(
            tracks: const [],
            event: i + 1,
            kinds: [kind.name],
            region: '',
            places: const [],
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EventSequencePage(
          useEnglishBookNames: true,
          onOpenPassage: (_) {},
          sequence: s,
          sequences: BibleSequences([s]),
          events: events,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Gen'), findsWidgets);
    final chip = find.byKey(const ValueKey('sequence-kind-rulers'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Example reign'), findsWidgets);
    expect(find.text('Example judgeship'), findsWidgets);
  });
}
