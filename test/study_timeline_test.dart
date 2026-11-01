import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/timeline_chart.dart';
import 'package:haqor/src/widgets/bible_timeline_page.dart';
import 'package:haqor/src/widgets/timeline_wheel.dart';

void main() {
  test('Bible creation wheel has evening then morning in all seven days', () {
    expect(bibleCreationWeek.dayParts, hasLength(14));
    final custom = timelineCycleOf(
      const StudyTimeline(
        id: 'creation',
        title: 'Creation',
        scale: TimelineScale.years,
        extent: TimelineExtent.creationWeek,
      ),
    )!;
    expect(bibleCreationWeek.dayParts, custom.dayParts);
    expect(bibleCreationWeek.dayParts.first.label, 'Evening');
    expect(bibleCreationWeek.dayParts.last.label, 'Morning');
    expect(bibleCreationWeek.dayParts.last.to, 1);
  });

  test(
    'every built-in has its full wheel scale, including older saved links',
    () {
      for (final standard in standardTimelines) {
        final expected = standard.id == 'moadim'
            ? TimelineExtent.year
            : TimelineExtent.hayovel;
        expect(standard.template.extent, expected, reason: standard.id);
        final view = StudyWorkspace.viewOfStandard(standard);
        final cycle = timelineCycleOf(view.timeline);
        if (standard.id == 'moadim') {
          expect(view.timeline.isAnnual, isTrue);
          expect(cycle, isNull);
        } else {
          expect(cycle!.start, 1);
          expect(cycle.length, 50);
          for (final entry in view.entries) {
            final reach = timelineEntryReach(view.timeline, entry);
            expect(
              reach.start,
              greaterThanOrEqualTo(cycle.start),
              reason: entry.id,
            );
            expect(
              reach.end,
              lessThanOrEqualTo(cycle.start + cycle.length),
              reason: entry.id,
            );
          }
        }
        final legacy = StudyTimeline.fromJson({
          ...view.timeline.toJson(),
          'extent': null,
        })!;
        final workspace = const StudyWorkspace(
          id: 'w',
          name: 'Old',
        ).putTimeline(legacy);
        expect(workspace.viewTimeline(legacy.id)!.extent, expected);
        final detached = workspace.detachStandardTimeline(legacy);
        expect(detached.timelineById(legacy.id)!.extent, expected);
        expect(detached.timelineById(legacy.id)!.standardId, isNull);
      }
    },
  );

  test(
    'chronology wheels include whole spans and the final event across BC/AD',
    () {
      const timeline = StudyTimeline(
        id: 'history',
        title: 'History',
        scale: TimelineScale.calendar,
      );
      final entries = [
        const StudyTimelineEntry(
          id: 'span',
          title: 'Span',
          timelineId: 'history',
          start: TimelineTime(-10),
          end: TimelineTime(10),
        ),
        const StudyTimelineEntry(
          id: 'last',
          title: 'Last',
          timelineId: 'history',
          start: TimelineTime(20),
        ),
      ];
      final cycle = timelineChronologyCycle(timeline, entries);
      final marks = timelineWheelMarks(timeline, entries, -10, cycle: cycle);
      expect(marks, hasLength(2));
      expect(marks.first.from, greaterThanOrEqualTo(0));
      expect(marks.last.from, lessThan(1));
      expect(cycle.segments.join(' '), isNot(contains('AD 0')));
      expect(cycle.segments.join(' '), contains('BC'));
      expect(cycle.segments.join(' '), contains('AD'));
      final single = timelineChronologyCycle(timeline, [entries.last]);
      expect(single.length, 1);
      expect(
        timelineWheelMarks(timeline, [entries.last], 20, cycle: single),
        hasLength(1),
      );
      expect(timelineChronologyCycle(timeline, []).length, 1);
    },
  );

  for (final extent in TimelineExtent.values) {
    test(
      '${extent.name} survives JSON and supplies its full viewer extent',
      () {
        final timeline = StudyTimeline(
          id: 'extent',
          title: extent.label,
          extent: extent,
          scale: extent.scale,
          unit: extent.unit,
          monthDays: 29,
        );
        final loaded = StudyTimeline.fromJson(timeline.toJson())!;
        expect(loaded.extent, extent);
        final workspace = const StudyWorkspace(
          id: 'w',
          name: 'Spans',
        ).putTimeline(loaded);
        final stored = decodeStudyWorkspaces(
          encodeStudyWorkspaces([workspace]),
        ).single;
        expect(stored.timelineById(loaded.id)!.extent, extent);

        expect(loaded.copyWith(title: 'renamed').extent, extent);
        expect(loaded.hasSameAxis(timeline), isTrue);
        final length = extent == TimelineExtent.month ? 29.0 : extent.length;
        expect(timelineExtent(loaded, []), (
          start: extent.start,
          end: extent.start + length,
        ));
        final wheel = timelineCycleOf(loaded);
        if (extent == TimelineExtent.year) {
          expect(wheel, isNull);
          expect(loaded.isAnnual, isTrue);
        } else {
          expect(wheel!.length, length);
          if (extent == TimelineExtent.day ||
              extent == TimelineExtent.week ||
              extent == TimelineExtent.creationWeek) {
            final days = extent == TimelineExtent.day ? 1 : 7;
            expect(wheel.dayParts, hasLength(days * 2));
            for (var day = 0; day < days; day++) {
              expect(wheel.dayParts[day * 2], (
                label: 'Evening',
                from: day / days,
                to: (day + 0.5) / days,
              ));
              expect(wheel.dayParts[day * 2 + 1], (
                label: 'Morning',
                from: (day + 0.5) / days,
                to: (day + 1) / days,
              ));
            }
          } else {
            expect(wheel.dayParts, isEmpty);
          }

          final entry = StudyTimelineEntry(
            id: 'mid',
            title: 'Middle',
            timelineId: loaded.id,
            start: TimelineTime(extent.start + length / 2),
          );
          final marks = timelineWheelMarks(loaded, [entry], 0, cycle: wheel);
          expect(marks.single.from, closeTo(0.5, 1e-9));
        }
      },
    );
  }

  test('hour timelines retain fractional hours and duration arithmetic', () {
    const day = StudyTimeline(
      id: 'd',
      title: 'Day',
      extent: TimelineExtent.day,
      unit: 'Hour',
    );
    expect(
      day.addDuration(
        const TimelineTime(6.5),
        const TimelineDuration(1.25, TimelineDurationUnit.units),
      ),
      const TimelineTime(7.75),
    );
    expect(day.formatTime(const TimelineTime(6.5)), 'Hour 6.5');
    expect(
      day.hasSameAxis(
        const StudyTimeline(
          id: 'w',
          title: 'Week',
          extent: TimelineExtent.week,
          unit: 'Day',
        ),
      ),
      isFalse,
    );
  });

  test('legacy timelines remain open-ended and unknown extents survive', () {
    final old = StudyTimeline.fromJson({
      'id': 'old',
      'title': 'Old',
      'scale': 'units',
      'unit': 'Day',
    })!;
    expect(old.extent, isNull);
    final future = StudyTimeline.fromJson({
      ...old.toJson(),
      'extent': 'futureCycle',
    })!;
    expect(future.toJson()['extent'], 'futureCycle');
  });

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
      const TimelineTime(-1446, month: 1, day: 30),
    );
    expect(
      add(kings, const TimelineTime(-1446, month: 1, day: 1), 354, days),
      const TimelineTime(-1446, month: 12, day: 29),
    );
    expect(
      add(kings, const TimelineTime(-1446, month: 12, day: 29), 2, days),
      const TimelineTime(-1445, month: 1, day: 1),
    );
    expect(
      add(kings, const TimelineTime(-1445, month: 1, day: 1), -1, days),
      null,
      reason: 'a negative duration is refused',
    );
    expect(
      add(kings, const TimelineTime(-1445, month: 1, day: 1), 0, days),
      null,
      reason: 'days are counted inclusively, so a span lasts at least one',
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
        {
          'id': 't',
          'title': 'Days',
          'scale': 'years',
          'unit': 'Day',
          'parent': 'gone',
        },
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
    // Iyyar has 29 days: an entry on its 30th is settled on its last.
    expect(workspace.timelineEntries.map((e) => e.id), ['a', 'f', 'e']);
    expect(
      workspace.timelineEntries[1].start,
      const TimelineTime(1, month: 2, day: 29),
    );
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

  test('chosen years have a second Adar, and durations count it', () {
    final leap = kings.copyWith(
      leapMonths: TimelineLeapMonths.chosen,
      leapYears: {-1446},
    );
    expect(leap.monthsIn(-1446), 13);
    expect(leap.monthsIn(-1445), 12);
    expect(leap.daysInYear(-1446), 384);
    expect(leap.monthName(-1446, 12), 'Adar I');
    expect(leap.monthName(-1446, 13), 'Adar II');
    expect(leap.monthName(-1445, 12), 'Adar');
    expect(leap.daysInMonth(-1446, 12), 30);
    expect(leap.daysInMonth(-1446, 13), 29);
    expect(leap.daysInMonth(-1445, 12), 29);
    expect(leap.fits(const TimelineTime(-1446, month: 13, day: 29)), isTrue);
    expect(leap.fits(const TimelineTime(-1445, month: 13)), isFalse);
    expect(
      leap.formatTime(const TimelineTime(-1446, month: 13, day: 14)),
      '14 Adar II 1446 BC',
    );
    TimelineTime? add(TimelineTime start, int n, TimelineDurationUnit unit) =>
        leap.addDuration(start, TimelineDuration(n.toDouble(), unit));
    const nisan1 = TimelineTime(-1446, month: 1, day: 1);
    expect(
      add(nisan1, 384, TimelineDurationUnit.days),
      const TimelineTime(-1446, month: 13, day: 29),
    );
    expect(
      add(nisan1, 354, TimelineDurationUnit.days),
      const TimelineTime(-1446, month: 12, day: 29),
    );
    expect(
      add(const TimelineTime(-1446, month: 12), 1, TimelineDurationUnit.months),
      const TimelineTime(-1446, month: 13),
    );
    expect(
      add(const TimelineTime(-1446, month: 13), 1, TimelineDurationUnit.months),
      const TimelineTime(-1445, month: 1),
    );
    expect(
      add(nisan1, 13, TimelineDurationUnit.months),
      const TimelineTime(-1445, month: 1, day: 1),
    );
    // A year on from Adar II, in a year without it, is in Adar.
    expect(
      add(
        const TimelineTime(-1446, month: 13, day: 29),
        1,
        TimelineDurationUnit.years,
      ),
      const TimelineTime(-1445, month: 12, day: 29),
    );
    // Adar II falls after Adar I and before the next Nisan.
    expect(
      leap.positionOf(const TimelineTime(-1446, month: 13)),
      allOf(
        greaterThan(leap.positionOf(const TimelineTime(-1446, month: 12))),
        lessThan(leap.positionOf(const TimelineTime(-1445, month: 1))),
      ),
    );
    final stored = StudyTimeline.fromJson(leap.toJson())!;
    expect(stored.leapMonths, TimelineLeapMonths.chosen);
    expect(stored.leapYears, {-1446});

    // Taking the second Adar away keeps an entry in it, settled in Adar.
    var workspace = build()
        .putTimeline(leap)
        .putTimelineEntry(
          const StudyTimelineEntry(
            id: 'purim',
            title: 'Late feast',
            timelineId: 'kings',
            start: TimelineTime(-1446, month: 13, day: 14),
          ),
        );
    expect(workspace.timelineEntries.any((e) => e.id == 'purim'), isTrue);
    workspace = workspace.putTimeline(leap.copyWith(leapYears: {}));
    expect(
      workspace.timelineEntries.firstWhere((e) => e.id == 'purim').start,
      const TimelineTime(-1446, month: 12, day: 14),
    );
  });

  test(
    'the fixed 19-year cycle places the second Adar by year of the world',
    () {
      final cycle = kings.copyWith(leapMonths: TimelineLeapMonths.cycle);
      // AM 5784 was a leap year: its Adar II fell in March 2024, at the end of
      // the year that began at Nisan 2023. AM 5785 was not; AM 5787 is.
      expect(hebrewCycleLeapYear(5784), isTrue);
      expect(hebrewCycleLeapYear(5785), isFalse);
      expect(cycle.isLeapYear(2023), isTrue);
      expect(cycle.isLeapYear(2024), isFalse);
      expect(cycle.isLeapYear(2026), isTrue);
      // Seven years in every nineteen.
      final leaps = [
        for (var year = -1500; year < -1481; year++)
          if (cycle.isLeapYear(year.toDouble())) year,
      ];
      expect(leaps, hasLength(7));
      // Years of a timeline's own cannot be placed in the cycle.
      final reign = cycle.copyWith(scale: TimelineScale.years);
      expect(reign.isLeapYear(3), isFalse);
    },
  );

  test("a year's calendar has months and days but no years", () {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts of Yahweh',
      scale: TimelineScale.annual,
    );
    const passover = TimelineTime(0, month: 1, day: 14);
    expect(feasts.formatTime(passover), '14 Nisan');
    expect(feasts.formatTime(const TimelineTime(0, month: 7)), 'Tishri');
    expect(feasts.fits(passover), isTrue);
    expect(feasts.fits(const TimelineTime(0)), isFalse);
    expect(feasts.fits(const TimelineTime(3, month: 1)), isFalse);
    expect(feasts.durationUnitsFor(passover), [
      TimelineDurationUnit.months,
      TimelineDurationUnit.days,
    ]);
    expect(
      feasts.addDuration(
        const TimelineTime(0, month: 1, day: 15),
        const TimelineDuration(7, TimelineDurationUnit.days),
      ),
      const TimelineTime(0, month: 1, day: 21),
    );
    // A span must end within the year.
    expect(
      feasts.addDuration(
        const TimelineTime(0, month: 12, day: 25),
        const TimelineDuration(8, TimelineDurationUnit.days),
      ),
      isNull,
    );
    expect(feasts.monthsIn(0), 12);
    final leap = feasts.copyWith(leapMonths: TimelineLeapMonths.chosen);
    expect(leap.monthsIn(0), 13);
    expect(
      leap.addDuration(
        const TimelineTime(0, month: 12, day: 25),
        const TimelineDuration(8, TimelineDurationUnit.days),
      ),
      const TimelineTime(0, month: 13, day: 2),
    );

    // Turned into a year's calendar, a timeline's entries lose their years.
    final workspace = build().putTimeline(
      kings.copyWith(scale: TimelineScale.annual),
    );
    final exodusNow = workspace.timelineEntries.firstWhere(
      (e) => e.id == 'exodus',
    );
    expect(exodusNow.start, const TimelineTime(0, month: 1, day: 15));
  });

  test('weeks run on from 1 Nisan through the years', () {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
      nisanWeekday: 7,
    );
    expect(feasts.weekdayOf(const TimelineTime(0, month: 1, day: 1)), 7);
    expect(feasts.weekdayOf(const TimelineTime(0, month: 1, day: 8)), 7);
    expect(feasts.weekdayOf(const TimelineTime(0, month: 1, day: 14)), 6);
    // Iyyar begins 30 days on: two weeks and two days.
    expect(feasts.weekdayOf(const TimelineTime(0, month: 2, day: 1)), 2);
    expect(StudyTimeline.fromJson(feasts.toJson())!.nisanWeekday, 7);

    // Counting years, the weeks run on through 354- and 384-day years.
    final years = kings.copyWith(
      nisanWeekday: 1,
      weekYear: () => -1446,
      leapMonths: TimelineLeapMonths.chosen,
      leapYears: {-1446},
    );
    expect(years.weekdayOf(const TimelineTime(-1446, month: 1, day: 1)), 1);
    // 384 days on is 54 weeks and 6 days.
    expect(years.weekdayOf(const TimelineTime(-1445, month: 1, day: 1)), 7);
    // And back: 1 Nisan 1447 BC is 354 days (50 weeks and 4 days) before.
    expect(years.weekdayOf(const TimelineTime(-1447, month: 1, day: 1)), 4);
    expect(kings.nextYear(-1), 1);
    expect(kings.nextYear(1, step: -1), -1);
  });

  test('high Sabbaths are events, with notes, found by their day', () {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    const firstDay = StudyTimelineEntry(
      id: 'first',
      title: 'First day of Unleavened Bread',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 15),
      note: 'No servile work (Leviticus 23:7)',
      sabbath: true,
    );
    final workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).putTimeline(feasts).putTimelineEntry(firstDay);
    final stored = decodeStudyWorkspaces(
      encodeStudyWorkspaces([workspace]),
    ).single.timelineEntries.single;
    expect(stored.isHighSabbath, isTrue);
    expect(stored.note, firstDay.note);
    expect(stored.toJson()['sabbath'], isTrue);
    expect(
      feasts.highSabbathsOn([stored], const TimelineTime(0, month: 1, day: 15)),
      [stored],
    );
    expect(
      feasts.highSabbathsOn([stored], const TimelineTime(0, month: 1, day: 16)),
      isEmpty,
    );
    // A span is never one.
    expect(
      firstDay
          .withTime(start: firstDay.start, end: firstDay.start)
          .isHighSabbath,
      isFalse,
    );
    // On a timeline of years, a high Sabbath is kept in its year.
    expect(
      kings.highSabbathsOn([
        firstDay.withTime(
          start: const TimelineTime(-1446, month: 1, day: 15),
          end: null,
        ),
      ], const TimelineTime(-1445, month: 1, day: 15)),
      isEmpty,
    );
  });

  test('high Sabbaths kept by date alone become events on load', () {
    final workspace = StudyWorkspace.fromJson({
      'id': 's',
      'name': 'Study',
      'ordered': true,
      'timelines': [
        {
          'id': 'feasts',
          'title': 'Feasts',
          'scale': 'annual',
          'sabbaths': [
            {'month': 1, 'day': 15},
            {'month': 7, 'day': 10},
            {'month': 'bad', 'day': 1},
          ],
        },
      ],
    })!;
    expect(
      workspace.timelines.single.toJson().containsKey('sabbaths'),
      isFalse,
    );
    final sabbaths = workspace.entriesOf('feasts');
    expect(sabbaths.map((e) => (e.title, e.start, e.isHighSabbath)), [
      ('Shabbaton', const TimelineTime(0, month: 1, day: 15), true),
      ('Shabbaton', const TimelineTime(0, month: 7, day: 10), true),
    ]);
    // Loading again keeps them once.
    final again = decodeStudyWorkspaces(encodeStudyWorkspaces([workspace]));
    expect(again.single.entriesOf('feasts'), hasLength(2));
  });

  test('months are named as after or before the exile, or numbered', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 30].map(ordinal), [
      '1st',
      '2nd',
      '3rd',
      '4th',
      '11th',
      '12th',
      '13th',
      '21st',
      '22nd',
      '23rd',
      '30th',
    ]);
    const passover = TimelineTime(-1446, month: 1, day: 14);
    expect(kings.formatTime(passover), '14 Nisan 1446 BC');
    final before = kings.copyWith(monthNaming: TimelineMonthNaming.preExile);
    expect(before.formatTime(passover), '14 Abib 1446 BC');
    expect(before.formatTime(const TimelineTime(-966, month: 2)), 'Ziv 966 BC');
    expect(
      before.formatTime(const TimelineTime(-966, month: 3, day: 10)),
      '10th of the 3rd month 966 BC',
    );
    expect(before.monthChoice(-966, 7), '7 · Ethanim');
    expect(before.monthChoice(-966, 9), '9th month');
    final numbered = kings.copyWith(monthNaming: TimelineMonthNaming.numbered);
    expect(numbered.formatTime(passover), '14th of the 1st month 1446 BC');
    expect(numbered.monthName(-966, 7), '7th month');
    // The months added in a leap year have no name before the exile.
    final leap = before.copyWith(
      leapMonths: TimelineLeapMonths.chosen,
      leapYears: {-1446},
    );
    expect(leap.monthName(-1446, 12), '12th month');
    expect(leap.monthName(-1446, 13), '13th month');
    expect(
      StudyTimeline.fromJson(numbered.toJson())!.monthNaming,
      TimelineMonthNaming.numbered,
    );
    expect(kings.toJson().containsKey('monthNames'), isFalse);
  });

  test('pins chain the feasts from Passover, counted in days and moved on '
      'to a weekday, and each moves with what it is pinned to', () {
    // 15 Nisan falls on the 4th day of the week.
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
      nisanWeekday: 4,
    );
    TimelineTime nisan(int day) => TimelineTime(0, month: 1, day: day);
    TimelineTime sivan(int day) => TimelineTime(0, month: 3, day: day);
    const passover = StudyTimelineEntry(
      id: 'passover',
      title: 'Passover',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
    );
    // The morrow of Passover, for seven days.
    final unleavened =
        const StudyTimelineEntry(
          id: 'unleavened',
          title: 'Unleavened Bread',
          timelineId: 'feasts',
          start: TimelineTime(0, month: 1, day: 1),
          end: TimelineTime(0, month: 1, day: 7),
          duration: TimelineDuration(7, TimelineDurationUnit.days),
        ).pinnedTo(
          const TimelinePin(
            'passover',
            TimelineDuration(2, TimelineDurationUnit.days),
          ),
        );
    // The morrow after the Sabbath, read as the first day of the week in
    // the feast.
    const wavePin = TimelinePin(
      'unleavened',
      TimelineDuration(2, TimelineDurationUnit.days),
      weekday: 1,
    );
    final wave = const StudyTimelineEntry(
      id: 'wave',
      title: 'Wave sheaf',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 1),
    ).pinnedTo(wavePin);
    // The fiftieth day, counting from the wave sheaf.
    final pentecost =
        const StudyTimelineEntry(
          id: 'pentecost',
          title: 'Pentecost',
          timelineId: 'feasts',
          start: TimelineTime(0, month: 1, day: 1),
        ).pinnedTo(
          const TimelinePin(
            'wave',
            TimelineDuration(50, TimelineDurationUnit.days),
          ),
        );
    // The count between, a span with a plain end, keeps its length.
    final omer =
        const StudyTimelineEntry(
          id: 'omer',
          title: 'The count',
          timelineId: 'feasts',
          start: TimelineTime(0, month: 1, day: 19),
          end: TimelineTime(0, month: 3, day: 8),
        ).pinnedTo(
          const TimelinePin(
            'wave',
            TimelineDuration(1, TimelineDurationUnit.days),
          ),
        );
    // Pinned the day before.
    final preparation =
        const StudyTimelineEntry(
          id: 'preparation',
          title: 'Preparation',
          timelineId: 'feasts',
          start: TimelineTime(0, month: 1, day: 1),
        ).pinnedTo(
          const TimelinePin(
            'passover',
            TimelineDuration(0, TimelineDurationUnit.days),
          ),
        );
    var workspace = const StudyWorkspace(id: 's', name: 'Study')
        .putTimeline(feasts)
        .putTimelineEntry(passover)
        .putTimelineEntry(unleavened)
        .putTimelineEntry(wave)
        .putTimelineEntry(pentecost)
        .putTimelineEntry(omer)
        .putTimelineEntry(preparation);
    StudyTimelineEntry entry(String id) =>
        workspace.timelineEntries.singleWhere((e) => e.id == id);

    expect(entry('unleavened').start, nisan(15));
    expect(entry('unleavened').end, nisan(21));
    expect(entry('preparation').start, nisan(13));
    expect(feasts.weekdayOf(nisan(15)), 4);
    expect(entry('wave').start, nisan(19));
    expect(feasts.weekdayOf(nisan(19)), 1);
    expect(entry('pentecost').start, sivan(9));
    expect(feasts.weekdayOf(sivan(9)), 1);
    expect(entry('omer').end, sivan(8));

    // Passover moves a week on, and the chain with it.
    workspace = workspace.putTimelineEntry(
      passover.withTime(start: nisan(20), end: null),
    );
    expect(entry('unleavened').start, nisan(21));
    expect(entry('unleavened').end, nisan(27));
    expect(entry('wave').start, nisan(26));
    expect(entry('pentecost').start, sivan(16));
    expect(entry('omer').start, nisan(26));
    expect(entry('omer').end, sivan(15));

    // The pins are stored, and placed again on load.
    final stored = decodeStudyWorkspaces(encodeStudyWorkspaces([workspace]));
    final reloaded = stored.single.timelineEntries.singleWhere(
      (e) => e.id == 'wave',
    );
    expect(reloaded.pin, wavePin);
    expect(reloaded.start, nisan(26));

    // Nothing is pinned to itself.
    expect(
      passover
          .pinnedTo(
            const TimelinePin(
              'passover',
              TimelineDuration(1, TimelineDurationUnit.days),
            ),
          )
          .isValid,
      isFalse,
    );
    // A weekday is for days alone.
    expect(
      const TimelinePin(
        'passover',
        TimelineDuration(1, TimelineDurationUnit.months),
        weekday: 1,
      ).isValid,
      isFalse,
    );

    // With Passover gone, what was pinned to it stays put, unpinned, and
    // the rest of the chain still holds to it.
    workspace = workspace.removeTimelineEntry(passover);
    expect(entry('unleavened').pin, isNull);
    expect(entry('unleavened').start, nisan(21));
    expect(entry('preparation').pin, isNull);
    expect(entry('wave').pin, wavePin);
  });

  test('a circle of pins is broken on load', () {
    final workspace = StudyWorkspace.fromJson({
      'id': 's',
      'name': 'Study',
      'timelines': [
        {'id': 'feasts', 'title': 'Feasts', 'scale': 'annual'},
      ],
      'timelineEntries': [
        for (final (id, anchor) in [('a', 'b'), ('b', 'a')])
          {
            'id': id,
            'title': id,
            'timeline': 'feasts',
            'start': 0,
            'startMonth': 1,
            'startDay': 1,
            'pin': {
              'anchor': anchor,
              'offset': {'amount': 2, 'unit': 'days'},
            },
          },
      ],
    })!;
    expect(workspace.timelineEntries.where((e) => e.pin == null), isNotEmpty);
  });

  test('days are counted across years, and Adar II follows Adar I', () {
    const leap = StudyTimeline(
      id: 'k',
      title: 'Kings',
      scale: TimelineScale.calendar,
      leapMonths: TimelineLeapMonths.chosen,
      leapYears: {-966},
    );
    const adar1 = TimelineTime(-966, month: 12, day: 30);
    const adar2 = TimelineTime(-966, month: 13, day: 1);
    expect(leap.positionOf(adar2), greaterThan(leap.positionOf(adar1)));
    expect(leap.addDays(adar1, 1), adar2);
    expect(leap.daysBetween(adar1, adar2), 1);
    // Across the turn of a year, both ways: -966 is a leap year of 384.
    const nisan1 = TimelineTime(-966, month: 1, day: 1);
    const next = TimelineTime(-965, month: 1, day: 1);
    expect(leap.daysBetween(nisan1, next), 384);
    expect(leap.addDays(next, -384), nisan1);
    expect(
      leap.addDays(nisan1, -1),
      const TimelineTime(-967, month: 12, day: 29),
    );
    // One year's calendar keeps within its year.
    const feasts = StudyTimeline(
      id: 'f',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    expect(feasts.addDays(const TimelineTime(0, month: 1, day: 1), -1), isNull);
  });

  test('links lead between timelines, found from either end, and go with '
      'what they lead to', () {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
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
    final passover =
        const StudyTimelineEntry(
          id: 'passover',
          title: 'Passover',
          timelineId: 'feasts',
          start: TimelineTime(0, month: 1, day: 14),
        ).copyWith(
          links: const [
            TimelineLink('passion', 'cross', title: 'Crucifixion'),
            TimelineLink(bibleTimelineId, '412', title: 'The Last Supper'),
          ],
        );
    expect(
      StudyTimelineEntry.fromJson(passover.toJson())?.links,
      passover.links,
    );
    var workspace = const StudyWorkspace(id: 's', name: 'Study')
        .putTimeline(feasts)
        .putTimeline(passion)
        .putTimelineEntry(cross)
        .putTimelineEntry(passover);
    expect(workspace.entriesLinkedTo('passion', 'cross').map((e) => e.id), [
      'passover',
    ]);
    expect(workspace.entriesLinkedTo(bibleTimelineId, '412').map((e) => e.id), [
      'passover',
    ]);
    StudyTimelineEntry stored() =>
        workspace.timelineEntries.singleWhere((e) => e.id == 'passover');
    // The crucifixion gone, the link to it goes; the Bible's stays.
    workspace = workspace.removeTimelineEntry(cross);
    expect(stored().links.map((l) => l.entryId), ['412']);
    // So with a whole timeline.
    workspace = workspace
        .putTimelineEntry(cross)
        .putTimelineEntry(
          stored().copyWith(
            links: [...stored().links, const TimelineLink('passion', 'cross')],
          ),
        )
        .removeTimeline(passion);
    expect(stored().links.map((l) => l.entryId), ['412']);
  });

  test('an entry pinned to another takes a lane below it', () {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    const unleavened = StudyTimelineEntry(
      id: 'unleavened',
      title: 'Unleavened Bread',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 15),
      end: TimelineTime(0, month: 1, day: 21),
    );
    const before = StudyTimelineEntry(
      id: 'before',
      title: 'Before',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 1),
      end: TimelineTime(0, month: 1, day: 10),
    );
    final wave =
        const StudyTimelineEntry(
          id: 'wave',
          title: 'Wave',
          timelineId: 'feasts',
          start: TimelineTime(0, month: 3, day: 1),
        ).pinnedTo(
          const TimelinePin(
            'unleavened',
            TimelineDuration(2, TimelineDurationUnit.days),
          ),
        );
    // The wave sheaf, well after the feast, would fit in its lane, but
    // hangs beneath it.
    final slots = packTimelineLanes(
      feasts,
      [before, unleavened, wave],
      x: (p) => p * 1000,
      width: (_) => 10,
    );
    int lane(String id) => slots.singleWhere((s) => s.entry.id == id).lane;
    expect(lane('unleavened'), 0);
    expect(lane('wave'), 1);
  });

  test('the moʿadim come in readings, each dated as its text dates it, and '
      'the Messiah\'s on the Torah\'s weeks', () {
    TimelineTime day(int month, int day) =>
        TimelineTime(0, month: month, day: day);
    final standard = standardTimelineById('moadim')!;
    final variants = {for (final v in standard.variants) v.id};
    expect(variants.first, 'torah');
    expect(variants, hasLength(standard.variants.length));
    // Every entry in a reading, and pinned only within it.
    final byId = {for (final e in standard.entries) e.id: e};
    expect(byId, hasLength(standard.entries.length));
    for (final e in standard.entries) {
      expect(variants, contains(e.variant), reason: e.id);
      if (e.pin case final pin?) {
        expect(byId[pin.anchorId]?.variant, e.variant, reason: e.id);
      }
    }
    var workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).addStandardTimeline(standard, id: 'm');
    expect(workspace.variantsOf('m'), standard.variants);
    workspace = workspace.putTimeline(
      workspace.timelineById('m')!.copyWith(nisanWeekday: 4),
    );
    final entries = workspace.viewOf('m');
    expect(entries, hasLength(standard.entries.length));
    StudyTimelineEntry entry(String id) =>
        entries.singleWhere((e) => e.id == 'm:$id');
    // Ezekiel's two weeks are alike, from the fifteenth of each.
    expect(entry('ezekiel-cleanse-2').start, day(1, 7));
    expect(entry('ezekiel-chag-1').start, day(1, 15));
    expect(entry('ezekiel-chag-7').start, day(7, 15));
    expect(entry('ezekiel-chag-7').end, day(7, 21));
    // Hezekiah's pesach a month on, and its week twice over.
    expect(entry('hezekiah-porch').start, day(1, 8));
    expect(entry('hezekiah-atonement').start, day(1, 17));
    expect(entry('hezekiah-matzot').start, day(2, 15));
    expect(entry('hezekiah-other-seven').start, day(2, 22));
    expect(entry('hezekiah-other-seven').end, day(2, 28));
    // Solomon's fourteen days and the eighth.
    expect(entry('solomon-dedication').start, day(7, 8));
    expect(entry('solomon-chag').start, day(7, 15));
    expect(entry('solomon-atzeret').start, day(7, 22));
    // The going out on the morrow of the pesach; the sabbath of the manna.
    expect(entry('going-out-going-out').start, day(1, 15));
    expect(entry('going-out-sabbath').start, day(2, 22));
    expect(entry('going-out-words').start, day(3, 3));
    // The sea on the seventh of matzot, as the rabbis place it, and Marah
    // three days from its morrow.
    expect(entry('going-out-sea').start, day(1, 21));
    expect(entry('going-out-marah').start, day(1, 22));
    expect(entry('going-out-marah').end, day(1, 24));
    expect(entry('second-year-eighth').start, day(1, 8));
    // Moses in the mount from the seventh day of the cloud, and each forty
    // after from the morrow of the last.
    expect(entry('going-out-covenant').start, day(3, 4));
    expect(entry('going-out-mount').start, day(3, 11));
    expect(entry('going-out-mount').end, day(4, 20));
    expect(entry('going-out-broken').start, day(4, 20));
    expect(entry('going-out-fallen').start, day(4, 21));
    expect(entry('going-out-fallen').end, day(6, 1));
    expect(entry('going-out-tablets').start, day(6, 2));
    expect(entry('going-out-tablets').end, day(7, 12));
    // From Sinai to Kadesh: a month of flesh, Miriam's seven days, and
    // the forty of the spies.
    expect(entry('second-year-quail').start, day(2, 23));
    expect(entry('second-year-quail').end, day(3, 23));
    expect(entry('second-year-miriam').start, day(3, 24));
    expect(entry('second-year-spies').start, day(4, 1));
    expect(entry('second-year-spies').end, day(5, 11));
    expect(entry('second-year-weeping').start, day(5, 12));
    // The Messiah raised on the day of the ʿomer, the Spirit given on
    // Shavuot.
    expect(entry('messiah-raised').start, entry('omer').start);
    expect(entry('messiah-pentecost').start, entry('shavuot').start);
    expect(entry('messiah-count').end, entry('count').end);
  });

  test('the yovel counts seven sabbaths of years and hallows the fiftieth, '
      'as the moʿadim count to Shavuot', () {
    final standard = standardTimelineById('yovel')!;
    final variants = {for (final v in standard.variants) v.id};
    expect(variants, ['torah', 'prophets', 'messiah']);
    final byId = {for (final e in standard.entries) e.id: e};
    expect(byId, hasLength(standard.entries.length));
    for (final e in standard.entries) {
      expect(e.isValid, isTrue, reason: e.id);
      expect(standard.template.fits(e.start), isTrue, reason: e.id);
      // Each in a reading, or the frame every reading shows.
      expect(e.variant.isEmpty || variants.contains(e.variant), isTrue);
    }
    final view = StudyWorkspace.viewOfStandard(standard);
    StudyTimelineEntry entry(String id) =>
        view.entries.singleWhere((e) => e.id == 'yovel:$id');
    expect(entry('count').start, const TimelineTime(1));
    expect(entry('count').end, entry('yovel').start);
    // Counted in years, marked in sevens: seven sabbaths of years.
    expect(entry('count').isCounted, isTrue);
    expect(view.timeline.yearsIn(entry('count')), 49);
    expect(view.timeline.daysIn(entry('count')), isNull);
    expect(view.timeline.yearsIn(entry('shofar')), isNull);
    expect(entry('yovel').start, const TimelineTime(50));
    expect(
      [for (var n = 1; n <= 7; n++) entry('shabbat-$n').start.value],
      [7, 14, 21, 28, 35, 42, 49],
    );
    expect(entry('shofar').start, entry('yovel').start);
  });

  test('the standard timelines link one another, each link to an entry '
      'there', () {
    for (final standard in standardTimelines) {
      for (final e in standard.entries) {
        for (final link in e.links) {
          final other = standardTimelineLinkedAs(link.timelineId);
          expect(other, isNotNull, reason: '${standard.id}:${e.id}');
          expect(
            other!.entries.map((o) => o.id),
            contains(link.entryId),
            reason: '${standard.id}:${e.id}',
          );
          expect(link.title, isNotEmpty);
        }
      }
    }
    final shavuot = standardTimelineById(
      'moadim',
    )!.entries.singleWhere((e) => e.id == 'shavuot');
    expect(shavuot.links.single.entryId, 'yovel');
  });

  test('a link to a standard timeline leads to the study\'s own linked to '
      'it, where it holds one', () {
    var workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).addStandardTimeline(standardTimelineById('moadim')!, id: 'm');
    TimelineLink shavuotLink() => workspace
        .viewOf('m')
        .singleWhere((e) => e.id == 'm:shavuot')
        .links
        .single;
    // Not held: it opens the standard as it is.
    expect(shavuotLink().timelineId, standardLinkTimelineId('yovel'));
    expect(shavuotLink().entryId, 'yovel');
    StudyTimelineEntry moadim(String id) =>
        workspace.viewOf('m').singleWhere((e) => e.id == 'm:$id');
    // The yovel's links to it read back, opening the yovel as it is.
    expect(workspace.standardLinksBackOutside(moadim('count')), [
      TimelineLink(standardLinkTimelineId('yovel'), 'count'),
    ]);
    expect(
      workspace
          .standardLinksBackOutside(moadim('shavuot'))
          .map((l) => l.entryId),
      ['yovel', 'prophets-weeks'],
    );
    workspace = workspace.addStandardTimeline(
      standardTimelineById('yovel')!,
      id: 'y',
    );
    expect(shavuotLink(), const TimelineLink('y', 'y:yovel'));
    expect(workspace.viewOf('y').where(shavuotLink().leadsTo), hasLength(1));
    // And back again.
    final back = workspace
        .viewOf('y')
        .singleWhere((e) => e.id == 'y:yovel')
        .links
        .single;
    expect(back, const TimelineLink('m', 'm:shavuot'));
    // Held, the yovel's links to it read back from the study's own.
    expect(workspace.standardLinksBackOutside(moadim('count')), isEmpty);
    expect(workspace.entriesLinkedTo('m', 'm:count').map((e) => e.id), [
      'y:count',
    ]);
    expect(
      workspace.entriesLinkedTo('m', 'm:shavuot').map((e) => e.id),
      unorderedEquals(['y:yovel', 'y:prophets-weeks']),
    );
  });

  test('a study links the standard moʿadim, and builds on them a timeline '
      'of its own, placed on its own weeks', () {
    final standard = standardTimelineById('moadim')!;
    var workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).addStandardTimeline(standard, id: 'moadim-1');
    final linked = workspace.timelineById('moadim-1')!;
    expect(linked.isStandard, isTrue);
    expect(linked.monthNaming, TimelineMonthNaming.numbered);
    // Its entries come from the standard, made its own.
    final own = workspace.entriesOf('moadim-1');
    expect(own, hasLength(standard.entries.length));
    expect(own.every((e) => e.timelineId == 'moadim-1'), isTrue);
    expect(workspace.timelineEntries, isEmpty);
    TimelineTime day(int month, int day) =>
        TimelineTime(0, month: month, day: day);
    StudyTimelineEntry entry(List<StudyTimelineEntry> entries, String id) =>
        entries.singleWhere((e) => e.id == id);
    // With the 1st of the 1st month on the 4th day of the week, the 15th
    // is too: the ʿomer is waved on the 19th, the first day of the week,
    // and Shavuot is the fiftieth day, the first day of the week again.
    workspace = workspace.putTimeline(linked.copyWith(nisanWeekday: 4));
    var entries = workspace.entriesOf('moadim-1');
    expect(entry(entries, 'moadim-1:omer').start, day(1, 19));
    expect(entry(entries, 'moadim-1:shavuot').start, day(3, 9));
    final moadim = workspace.timelineById('moadim-1')!;
    expect(moadim.weekdayOf(day(3, 9)), 1);
    expect(entry(entries, 'moadim-1:count').end, day(3, 9));
    expect(entry(entries, 'moadim-1:atzeret').start, day(7, 22));
    // The three times before Yahweh hold their feasts; the second goes
    // with the count.
    expect(entry(entries, 'moadim-1:pesach').start, day(1, 14));
    expect(entry(entries, 'moadim-1:matzot').start, day(1, 15));
    expect(entry(entries, 'moadim-1:before-1').end, day(1, 21));
    expect(entry(entries, 'moadim-1:before-2').start, day(3, 9));
    expect(
      entry(entries, 'moadim-1:shavuot').pin?.anchorId,
      'moadim-1:before-2',
    );
    expect(entry(entries, 'moadim-1:sukkot').start, day(7, 15));
    expect(entry(entries, 'moadim-1:before-3').end, day(7, 22));
    // The way up ends the day before each time, the way home starts the
    // day after it.
    ({TimelineTime from, TimelineTime to})? lead(String id) =>
        timelineEntryTapers(moadim, entry(entries, id)).lead;
    ({TimelineTime from, TimelineTime to})? trail(String id) =>
        timelineEntryTapers(moadim, entry(entries, id)).trail;
    expect(lead('moadim-1:before-1'), (from: day(1, 10), to: day(1, 13)));
    expect(trail('moadim-1:before-1'), (from: day(1, 22), to: day(1, 25)));
    expect(lead('moadim-1:before-2'), (from: day(3, 5), to: day(3, 8)));
    expect(trail('moadim-1:before-2'), (from: day(3, 10), to: day(3, 13)));
    expect(trail('moadim-1:before-3')?.to, day(7, 26));
    expect(timelineEntrySpread(moadim, entry(entries, 'moadim-1:before-1')), (
      start: moadim.positionOf(day(1, 10)),
      end: moadim.endOf(day(1, 25)),
    ));
    // Nothing is added to it: it is built on.
    expect(
      workspace
          .putTimelineEntry(
            const StudyTimelineEntry(
              id: 'x',
              title: 'x',
              timelineId: 'moadim-1',
              start: TimelineTime(0, month: 1, day: 1),
            ),
          )
          .timelineEntries,
      isEmpty,
    );

    // A timeline built on it, set in a year whose 15th of the 1st month
    // falls on the 6th day: there the ʿomer falls on the 17th.
    const passion = StudyTimeline(
      id: 'passion',
      title: 'Last week',
      scale: TimelineScale.annual,
      baseId: 'moadim-1',
      nisanWeekday: 6,
      year: 30,
    );
    expect(StudyTimeline.fromJson(passion.toJson())?.baseId, 'moadim-1');
    expect(StudyTimeline.fromJson(passion.toJson())?.year, 30);
    final risen =
        const StudyTimelineEntry(
          id: 'risen',
          title: 'Raised',
          timelineId: 'passion',
          start: TimelineTime(0, month: 1, day: 1),
        ).pinnedTo(
          const TimelinePin(
            'moadim-1:omer',
            TimelineDuration(1, TimelineDurationUnit.days),
          ),
        );
    final ascended =
        const StudyTimelineEntry(
          id: 'ascended',
          title: 'Taken up',
          timelineId: 'passion',
          start: TimelineTime(0, month: 1, day: 1),
        ).pinnedTo(
          const TimelinePin(
            'risen',
            TimelineDuration(40, TimelineDurationUnit.days),
          ),
        );
    final spirit =
        const StudyTimelineEntry(
          id: 'spirit',
          title: 'The Spirit poured out',
          timelineId: 'passion',
          start: TimelineTime(0, month: 1, day: 1),
        ).pinnedTo(
          const TimelinePin(
            'moadim-1:shavuot',
            TimelineDuration(1, TimelineDurationUnit.days),
          ),
        );
    workspace = workspace
        .putTimeline(passion)
        .putTimelineEntry(risen)
        .putTimelineEntry(ascended)
        .putTimelineEntry(spirit);
    StudyTimelineEntry stored(String id) =>
        workspace.timelineEntries.singleWhere((e) => e.id == id);
    expect(stored('risen').start, day(1, 17));
    expect(stored('ascended').start, day(2, 26));
    expect(stored('spirit').start, day(3, 7));
    expect(passion.weekdayOf(day(3, 7)), 1);
    // Its view holds the base's entries, on its own weeks, beneath its own.
    final view = workspace.viewOf('passion');
    expect(entry(view, 'moadim-1:omer').start, day(1, 17));
    expect(entry(view, 'moadim-1:omer').timelineId, 'moadim-1');
    expect(entry(view, 'risen').timelineId, 'passion');
    // The base's colours, for its categories.
    expect(
      workspace.viewTimeline('passion')?.categoryColors,
      standard.template.categoryColors,
    );
    // Its weeks moved, its events and the base's beneath them move too.
    workspace = workspace.putTimeline(passion.copyWith(nisanWeekday: 4));
    expect(stored('risen').start, day(1, 19));
    expect(stored('spirit').start, day(3, 9));

    // Never built on itself, round a circle.
    final circle = workspace.putTimeline(
      workspace.timelineById('moadim-1')!.copyWith(baseId: () => 'passion'),
    );
    expect(circle.timelineById('moadim-1')?.baseId, isNull);

    // Made the study's own, the standard's entries are copied in, and what
    // is built on them still holds.
    final detached = workspace.detachStandardTimeline(
      workspace.timelineById('moadim-1')!,
    );
    expect(detached.timelineById('moadim-1')?.isStandard, isFalse);
    expect(
      detached.timelineEntries.where((e) => e.timelineId == 'moadim-1'),
      hasLength(standard.entries.length),
    );
    expect(
      detached.timelineEntries.singleWhere((e) => e.id == 'risen').pin,
      isNotNull,
    );

    // The base gone, what stood on it stands alone, where it was.
    workspace = workspace.removeTimeline(workspace.timelineById('moadim-1')!);
    expect(workspace.timelineById('passion')?.baseId, isNull);
    expect(stored('risen').pin, isNull);
    expect(stored('risen').start, day(1, 19));
    expect(stored('ascended').pin, isNotNull);
  });

  test('a timeline linked before its standard renamed its categories is '
      'coloured as the standard now is', () {
    final standard = standardTimelineById('moadim')!;
    final workspace = StudyWorkspace.fromJson({
      'id': 's',
      'name': 'Study',
      'timelines': [
        {
          'id': 'm',
          'title': 'Moʿadim',
          'scale': 'annual',
          'standard': 'moadim',
          'categories': {'Chag (feast)': 5},
        },
      ],
    })!;
    final colours = workspace.viewTimeline('m')!.categoryColors;
    for (final category in standard.template.categoryColors.keys) {
      expect(colours, contains(category));
    }
    final passover = workspace
        .entriesOf('m')
        .firstWhere((e) => e.id == 'm:pesach');
    expect(workspace.viewTimeline('m')!.colorOf(passover), isNotNull);
  });

  test('shabbatons pinned to a feast hang directly beneath it', () {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    const matzot = StudyTimelineEntry(
      id: 'matzot',
      title: 'Chag haMatzot',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 15),
      end: TimelineTime(0, month: 1, day: 21),
    );
    StudyTimelineEntry star(String id, int day, {bool pinned = true}) {
      final entry = StudyTimelineEntry(
        id: id,
        title: id,
        timelineId: 'feasts',
        start: TimelineTime(0, month: 1, day: day),
        sabbath: true,
      );
      return pinned
          ? entry.pinnedTo(
              TimelinePin(
                'matzot',
                TimelineDuration(day - 14.0, TimelineDurationUnit.days),
              ),
            )
          : entry;
    }

    final slots = packTimelineLanes(
      feasts,
      // The first day's star starts with the feast, and sorts before it.
      [
        star('first', 15),
        matzot,
        star('seventh', 21),
        star('alone', 3, pinned: false),
      ],
      x: (p) => p * 10000,
      width: (e) => e.isHighSabbath ? 12 : 100,
    );
    int lane(String id) => slots.singleWhere((s) => s.entry.id == id).lane;
    // The star pinned to nothing keeps the first lane; the feast the next,
    // its stars the one beneath.
    expect(lane('alone'), 0);
    expect(lane('matzot'), 1);
    expect(lane('first'), 2);
    expect(lane('seventh'), 2);
    // With no star pinned to nothing, no lane is kept for them.
    final pinnedOnly = packTimelineLanes(
      feasts,
      [star('first', 15), matzot],
      x: (p) => p * 10000,
      width: (e) => e.isHighSabbath ? 12 : 100,
    );
    expect(pinnedOnly.map((s) => (s.entry.id, s.lane)), [
      ('matzot', 0),
      ('first', 1),
    ]);
  });

  test('spans of one category that never overlap share a row of their own', () {
    const feasts = StudyTimeline(
      id: 'feasts',
      title: 'Feasts',
      scale: TimelineScale.annual,
    );
    StudyTimelineEntry span(
      String id,
      int month,
      int from,
      int to, {
      String category = 'Chag',
    }) => StudyTimelineEntry(
      id: id,
      title: id,
      timelineId: 'feasts',
      start: TimelineTime(0, month: month, day: from),
      end: TimelineTime(0, month: month, day: to),
      category: category,
    );
    const pesach = StudyTimelineEntry(
      id: 'pesach',
      title: 'pesach',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
    );
    List<(String, int)> lanes(List<StudyTimelineEntry> entries) => [
      for (final s in packTimelineLanes(
        feasts,
        entries,
        x: (p) => p * 10000,
        width: (e) => e.isSpan ? 4 : 10,
      ))
        (s.entry.id, s.lane),
    ];
    // Pesach would leave the first lane free for the feasts that follow;
    // they keep a row of their own all the same, and the count, of no
    // category, goes on in Pesach's after its mark.
    expect(
      lanes([
        pesach,
        span('matzot', 1, 15, 21),
        span('count', 1, 16, 30, category: ''),
        span('shavuot', 3, 6, 6),
        span('sukkot', 7, 15, 21),
      ]).toSet(),
      {
        ('matzot', 0),
        ('shavuot', 0),
        ('sukkot', 0),
        ('pesach', 1),
        ('count', 1),
      },
    );
    // Overlapping, they pack as any others.
    expect(lanes([span('a', 1, 1, 10), span('b', 1, 5, 20)]).toSet(), {
      ('a', 0),
      ('b', 1),
    });
  });

  test('a span keeps the days before and after it, which take room in its '
      'row', () {
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
      lead: TimelineTaper(
        days: 3,
        title: 'Going up',
        note: 'The way',
        verses: [StudyPassage(bookIndex: 26, chapter: 122, verse: 1)],
      ),
      trail: TimelineTaper(days: 2),
    );
    final back = StudyTimelineEntry.fromJson(span.toJson())!;
    expect(back.lead?.days, 3);
    expect(back.lead?.title, 'Going up');
    expect(back.lead?.note, 'The way');
    expect(back.lead?.verses.single.chapter, 122);
    expect(back.trail?.days, 2);
    expect(back.copyWith(lead: () => null).lead, isNull);
    // Only a span dated to the day has them.
    expect(
      StudyTimelineEntry.fromJson({
        ...span.toJson(),
        'end': null,
        'endMonth': null,
        'endDay': null,
      }),
      isNull,
    );
    final tapers = timelineEntryTapers(feasts, back);
    expect(tapers.lead, (
      from: const TimelineTime(0, month: 7, day: 12),
      to: const TimelineTime(0, month: 7, day: 14),
    ));
    expect(tapers.trail?.to, const TimelineTime(0, month: 7, day: 23));
    // An event two days before it no longer fits beside it in its row.
    const before = StudyTimelineEntry(
      id: 'before',
      title: 'before',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 7, day: 13),
    );
    List<(String, int)> lanes(List<StudyTimelineEntry> entries) => [
      for (final s in packTimelineLanes(
        feasts,
        entries,
        x: (p) => p * 10000,
        width: (_) => 4,
      ))
        (s.entry.id, s.lane),
    ];
    expect(lanes([before, back]).toSet(), {('before', 0), ('sukkot', 1)});
    expect(lanes([before, back.copyWith(lead: () => null)]).toSet(), {
      ('before', 0),
      ('sukkot', 0),
    });
  });

  test('a span keeps how it is drawn, a bar unless chosen otherwise', () {
    const span = StudyTimelineEntry(
      id: 'pilgrimage',
      title: 'Pilgrimage',
      timelineId: 'feasts',
      start: TimelineTime(0, month: 1, day: 14),
      end: TimelineTime(0, month: 1, day: 21),
    );
    expect(span.toJson().containsKey('style'), isFalse);
    for (final style in TimelineSpanStyle.values) {
      expect(
        StudyTimelineEntry.fromJson(
          span.copyWith(style: style).toJson(),
        )?.style,
        style,
      );
    }
    expect(
      StudyTimelineEntry.fromJson({...span.toJson(), 'style': 'zigzag'})?.style,
      TimelineSpanStyle.bar,
    );
  });

  test('a study without timelines stores none', () {
    final json = const StudyWorkspace(id: 's', name: 'Study').toJson();
    expect(json.containsKey('timelines'), isFalse);
    expect(json.containsKey('timelineEntries'), isFalse);
    expect(json.containsKey('timelineMarkers'), isFalse);
  });
}
