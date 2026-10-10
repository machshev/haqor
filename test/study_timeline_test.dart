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
      ('High Sabbath', const TimelineTime(0, month: 1, day: 15), true),
      ('High Sabbath', const TimelineTime(0, month: 7, day: 10), true),
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

  test('a study without timelines stores none', () {
    final json = const StudyWorkspace(id: 's', name: 'Study').toJson();
    expect(json.containsKey('timelines'), isFalse);
    expect(json.containsKey('timelineEntries'), isFalse);
    expect(json.containsKey('timelineMarkers'), isFalse);
  });
}
