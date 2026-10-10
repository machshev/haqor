import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';

void main() {
  const kings = StudyTimeline(
    id: 'kings',
    title: 'The divided kingdom',
    scale: TimelineScale.calendar,
    note: 'Dates after Thiele',
  );
  const exodus = StudyTimelineEntry(
    id: 'exodus',
    title: 'The exodus',
    timelineId: 'kings',
    start: TimelineTime(-1446, month: 1, day: 15),
    date: 'c.',
    verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
  );
  const solomon = StudyTimelineEntry(
    id: 'solomon',
    title: 'Solomon reigns',
    timelineId: 'kings',
    start: TimelineTime(-970),
    end: TimelineTime(-931),
    verses: [
      StudyPassage(
        bookIndex: 9,
        chapter: 1,
        verse: 39,
        endChapter: 11,
        endVerse: 43,
      ),
    ],
  );
  const temple = StudyTimelineEntry(
    id: 'temple',
    title: 'Temple begun',
    timelineId: 'kings',
    start: TimelineTime(-966, month: 2),
    verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
  );
  StudyWorkspace build() => const StudyWorkspace(id: 's', name: 'Study')
      .putGroup(const StudyGroup(id: 'g', name: 'Kings'))
      .putTimeline(kings.copyWith(parentId: () => 'g'))
      .putNote(const StudyNote(id: 'intro', text: 'Intro', groupId: 'kings'))
      // Added out of time order: entries sort by time, not insertion.
      .putTimelineEntry(temple)
      .putTimelineEntry(solomon)
      .putTimelineEntry(exodus);

  test('timelines round-trip and list their items before time-ordered '
      'entries', () {
    final workspace = decodeStudyWorkspaces(
      encodeStudyWorkspaces([build().copyWith(timelineMarkersEnabled: false)]),
    ).single;
    expect(workspace.timelineMarkersEnabled, isFalse);
    expect(
      workspace.timelineById('kings')!.toJson(),
      kings.copyWith(parentId: () => 'g', order: 0).toJson(),
    );
    expect(workspace.itemsIn('g').single.key, 'timeline-kings');
    expect(workspace.itemsIn('kings').map((i) => i.key), [
      'note-intro',
      'timeline-entry-exodus',
      'timeline-entry-solomon',
      'timeline-entry-temple',
    ]);
    final stored = workspace.timelineEntries.firstWhere(
      (e) => e.id == 'exodus',
    );
    expect(stored.toJson(), exodus.copyWith(order: stored.order).toJson());
    // Whole numbers are stored without a decimal point.
    expect(stored.toJson()['start'], -1446);
    expect(stored.start, const TimelineTime(-1446, month: 1, day: 15));
    expect(
      workspace.timelineEntries.firstWhere((e) => e.isSpan).end,
      const TimelineTime(-931),
    );
  });

  test('times read in the timeline\'s own unit or era, with biblical '
      'months', () {
    expect(kings.formatTime(const TimelineTime(-1446)), '1446 BC');
    expect(kings.formatTime(const TimelineTime(30)), 'AD 30');
    expect(
      kings.formatTime(const TimelineTime(-1446, month: 1, day: 14)),
      '14 Nisan 1446 BC',
    );
    expect(kings.formatTime(const TimelineTime(30, month: 7)), 'Tishri AD 30');
    const reign = StudyTimeline(
      id: 'r',
      title: 'David',
      scale: TimelineScale.years,
      unit: 'Year of David',
    );
    expect(
      reign.formatTime(const TimelineTime(4, month: 2, day: 2)),
      '2 Iyyar, Year of David 4',
    );
    const days = StudyTimeline(id: 'd', title: 'Creation', unit: 'Day');
    expect(days.formatTime(const TimelineTime(3)), 'Day 3');
    expect(days.formatTime(const TimelineTime(2.5)), 'Day 2.5');
    // Off the year scales there are no months.
    expect(days.formatTime(const TimelineTime(3, month: 2)), 'Day 3');
    const bare = StudyTimeline(id: 'b', title: 'Bare', unit: '');
    expect(bare.formatTime(const TimelineTime(-4)), '-4');
    expect(
      kings.formatDuration(
        const TimelineDuration(1, TimelineDurationUnit.months),
      ),
      '1 month',
    );
    expect(
      days.formatDuration(
        const TimelineDuration(7, TimelineDurationUnit.units),
      ),
      '7 Days',
    );
  });

  test('durations add calendar years without a year zero, and lunar months '
      'and days', () {
    TimelineTime? add(
      StudyTimeline timeline,
      TimelineTime start,
      double amount,
      TimelineDurationUnit unit,
    ) => timeline.addDuration(start, TimelineDuration(amount, unit));
    const years = TimelineDurationUnit.years;
    const months = TimelineDurationUnit.months;
    const days = TimelineDurationUnit.days;
    expect(
      add(kings, const TimelineTime(-970), 40, years),
      const TimelineTime(-930),
    );
    // 4 BC to AD 7 is ten years: 1 BC runs straight on into AD 1.
    expect(
      add(kings, const TimelineTime(-4), 10, years),
      const TimelineTime(7),
    );
    expect(add(kings, const TimelineTime(-1), 1, years), const TimelineTime(1));
    // Months are 30 and 29 days by turns from Nisan, 354 days a year.
    const nisan14 = TimelineTime(-1446, month: 1, day: 14);
    expect(
      add(kings, nisan14, 1, months),
      const TimelineTime(-1446, month: 2, day: 14),
    );
    expect(
      add(kings, const TimelineTime(-1446, month: 1, day: 30), 1, months),
      const TimelineTime(-1446, month: 2, day: 29),
    );
    expect(
      add(kings, const TimelineTime(-1, month: 12), 1, months),
      const TimelineTime(1, month: 1),
    );
    expect(
      add(kings, const TimelineTime(-1446, month: 1, day: 1), 30, days),
      const TimelineTime(-1446, month: 2, day: 1),
    );
    expect(
      add(kings, const TimelineTime(-1446, month: 1, day: 1), 354, days),
      const TimelineTime(-1445, month: 1, day: 1),
    );
    expect(
      add(kings, const TimelineTime(-1446, month: 12, day: 29), 1, days),
      const TimelineTime(-1445, month: 1, day: 1),
    );
    expect(
      add(kings, const TimelineTime(-1445, month: 1, day: 1), -1, days),
      null,
      reason: 'a negative duration is refused',
    );
    // A duration no finer than its start.
    expect(kings.durationUnitsFor(const TimelineTime(-970)), [years]);
    expect(kings.durationUnitsFor(nisan14), [years, months, days]);
    expect(add(kings, const TimelineTime(-970), 6, months), isNull);
    const daysScale = StudyTimeline(id: 'd', title: 'Creation', unit: 'Day');
    expect(
      add(daysScale, const TimelineTime(1), 6, TimelineDurationUnit.units),
      const TimelineTime(7),
    );
    expect(add(daysScale, const TimelineTime(1), 6, years), isNull);
  });

  test('a span given by duration has its end worked out, and again when its '
      'timeline changes', () {
    var workspace = build().putTimelineEntry(
      const StudyTimelineEntry(
        id: 'wilderness',
        title: 'In the wilderness',
        timelineId: 'kings',
        start: TimelineTime(-1446, month: 1, day: 15),
        end: TimelineTime(0),
        duration: TimelineDuration(40, TimelineDurationUnit.years),
      ),
    );
    StudyTimelineEntry wilderness() =>
        workspace.timelineEntries.firstWhere((e) => e.id == 'wilderness');
    expect(wilderness().end, const TimelineTime(-1406, month: 1, day: 15));
    final stored = decodeStudyWorkspaces(
      encodeStudyWorkspaces([workspace]),
    ).single.timelineEntries.firstWhere((e) => e.id == 'wilderness');
    expect(stored.duration, wilderness().duration);
    expect(stored.end, wilderness().end);

    // Counting years of its own, there is a year zero to pass through.
    workspace = workspace.putTimeline(
      workspace.timelineById('kings')!.copyWith(scale: TimelineScale.years),
    );
    expect(wilderness().end, const TimelineTime(-1406, month: 1, day: 15));
    // In another unit years no longer fit: the end stays, as a plain end.
    workspace = workspace.putTimeline(
      workspace.timelineById('kings')!.copyWith(scale: TimelineScale.units),
    );
    expect(wilderness().duration, isNull);
    expect(wilderness().end, const TimelineTime(-1406, month: 1, day: 15));
    // A duration finer than the start is refused.
    final before = workspace.timelineEntries;
    workspace = workspace.putTimeline(
      workspace.timelineById('kings')!.copyWith(scale: TimelineScale.calendar),
    );
    expect(
      workspace
          .putTimelineEntry(
            const StudyTimelineEntry(
              id: 'bad',
              title: 'Bad',
              timelineId: 'kings',
              start: TimelineTime(-970),
              end: TimelineTime(0),
              duration: TimelineDuration(6, TimelineDurationUnit.months),
            ),
          )
          .timelineEntries,
      hasLength(before.length),
    );
  });

  test('a verse finds the entries linked to it, in time order', () {
    final workspace = build();
    expect(workspace.timelineEntriesAt(9, 6, 1).map((e) => e.id), [
      'exodus',
      'solomon',
      'temple',
    ]);
    expect(workspace.timelineEntriesAt(9, 11, 43).single.id, 'solomon');
    expect(workspace.timelineEntriesAt(9, 12, 1), isEmpty);
  });

  test('entries live only in timelines; other items may join one', () {
    var workspace = build().putTimeline(
      const StudyTimeline(id: 'other', title: 'Other'),
    );
    final entry = StudyItem.of(workspace.timelineEntries.first);
    expect(workspace.canMoveItem(entry, null), isFalse);
    expect(workspace.canMoveItem(entry, 'g'), isFalse);
    expect(workspace.canMoveItem(entry, 'other'), isTrue);
    workspace = workspace.moveItem(entry, 'other');
    expect(workspace.entriesOf('other').single.id, entry.key.substring(15));
    // A timeline cannot move inside itself.
    final timeline = workspace.itemsIn('g').single;
    expect(workspace.canMoveItem(timeline, 'kings'), isFalse);
    final note = workspace.itemsIn('kings').first;
    expect(workspace.canMoveItem(note, 'other'), isTrue);
    // An entry without a timeline, or ending before it starts, is refused.
    expect(
      workspace
          .putTimelineEntry(exodus.copyWith(timelineId: 'missing'))
          .timelineEntries,
      workspace.timelineEntries,
    );
    expect(
      workspace
          .putTimelineEntry(
            exodus.withTime(
              start: const TimelineTime(1),
              end: const TimelineTime(0),
            ),
          )
          .timelineEntries
          .firstWhere((e) => e.id == 'exodus')
          .start
          .value,
      -1446,
    );
  });

  test('deleting a timeline drops its entries and keeps its other items', () {
    final workspace = build().removeTimeline(build().timelineById('kings')!);
    expect(workspace.timelines, isEmpty);
    expect(workspace.timelineEntries, isEmpty);
    expect(workspace.notes.single.groupId, 'g');
  });

  test('deleting a group moves its timeline up', () {
    final workspace = build().removeGroup(build().groupById('g')!);
    expect(workspace.timelines.single.parentId, isNull);
    expect(workspace.timelineEntries, hasLength(3));
  });

  test('entries without a timeline, or misshapen ones, are dropped on load; '
      'a timeline in a vanished group moves to the top', () {
    final workspace = StudyWorkspace.fromJson({
      'id': 's',
      'name': 'Study',
      'ordered': true,
      'timelines': [
        {'id': 't', 'title': 'Days', 'unit': 'Day', 'parent': 'gone'},
        {'id': 't', 'title': 'Duplicate'},
        {'id': 'untitled', 'title': ''},
      ],
      'timelineEntries': [
        {'id': 'a', 'title': 'Light', 'timeline': 't', 'start': 1},
        {'id': 'b', 'title': 'Lost', 'timeline': 'gone', 'start': 1},
        {'id': 'c', 'title': 'Bad', 'timeline': 't', 'start': 'one'},
        {'id': 'd', 'title': 'Back', 'timeline': 't', 'start': 3, 'end': 2},
        {
          'id': 'f',
          'title': 'No such day',
          'timeline': 't',
          'start': 1,
          'startMonth': 2,
          'startDay': 30,
        },
        {
          'id': 'e',
          'title': 'Rest',
          'timeline': 't',
          'start': 7,
          'verses': [
            {'book': 0, 'chapter': 2, 'verse': 1, 'endVerse': 3},
            {'book': 'x'},
          ],
          'future': 'kept',
        },
      ],
    })!;
    expect(workspace.timelines.single.title, 'Days');
    expect(workspace.timelines.single.parentId, isNull);
    expect(workspace.timelineEntries.map((e) => e.id), ['a', 'e']);
    final rest = workspace.timelineEntries.last;
    expect(rest.verses.single.reference, '2:1–3');
    expect(rest.toJson()['future'], 'kept');
  });

  test('the first timelines\' era flag reads as calendar years', () {
    final timeline = StudyTimeline.fromJson({
      'id': 't',
      'title': 'Kings',
      'era': true,
    })!;
    expect(timeline.scale, TimelineScale.calendar);
    expect(timeline.toJson()['scale'], 'calendar');
    expect(timeline.toJson().containsKey('era'), isFalse);
    expect(
      StudyTimeline.fromJson({'id': 't', 'title': 'Days'})!.scale,
      TimelineScale.units,
    );
  });

  test('a study without timelines stores none', () {
    final json = const StudyWorkspace(id: 's', name: 'Study').toJson();
    expect(json.containsKey('timelines'), isFalse);
    expect(json.containsKey('timelineEntries'), isFalse);
    expect(json.containsKey('timelineMarkers'), isFalse);
  });
}
