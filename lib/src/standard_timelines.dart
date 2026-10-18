import 'package:flutter/foundation.dart';

import 'study_timeline.dart';
import 'study_workspace.dart' show StudyPassage;

/// A timeline that comes with the app, which a study may hold, linked (see
/// [StudyTimeline.standardId]): its entries are read from here, so that
/// corrections reach every study holding it, and a study builds on it
/// rather than changing it (see [StudyTimeline.baseId]).
@immutable
class StandardTimeline {
  const StandardTimeline({
    required this.id,
    required this.template,
    required this.entries,
    required this.description,
  });

  final String id;

  /// How a study's timeline linked to it starts out: its title, scale,
  /// months, note and colours, which the study may then change.
  final StudyTimeline template;

  /// Its entries, their pins to one another by these ids.
  final List<StudyTimelineEntry> entries;

  /// What it is, as offered to add.
  final String description;
}

/// The standard timelines a study may add.
final standardTimelines = [_moadim];

/// The standard timeline [id], if there is one.
StandardTimeline? standardTimelineById(String? id) =>
    standardTimelines.where((s) => s.id == id).firstOrNull;

StudyPassage _ref(int book, int chapter, int verse, [int? endVerse]) =>
    StudyPassage(
      bookIndex: book,
      chapter: chapter,
      verse: verse,
      endVerse: endVerse,
    );

const _exodus = 1;
const _leviticus = 2;
const _numbers = 3;
const _deuteronomy = 4;
const _mark = 40;
const _acts = 43;
const _corinthians = 45;

const _chag = 'Chag (feast)';
const _qodesh = 'Mikra qodesh (holy convocation)';
const _qorban = 'Qorban (offering)';

const _day = TimelineDurationUnit.days;

/// The appointed times of Yahweh, Leviticus 23, with their offerings from
/// Numbers 28-29 and Deuteronomy 16; dated as the text dates them, by the
/// number of the month and day, and counted where the text counts.
final _moadim = StandardTimeline(
  id: 'moadim',
  description:
      'Leviticus 23: Pesach, Chag haMatzot, the ʿomer, Shavuot, Yom '
      'Teruah, Yom haKippurim and Chag haSukkot, each with its verses; the '
      'ʿomer and Shavuot counted from the weekly Sabbath.',
  template: const StudyTimeline(
    id: '',
    title: 'Moʿadei Yahweh (appointed times of Yahweh)',
    scale: TimelineScale.annual,
    monthNaming: TimelineMonthNaming.numbered,
    showSeasons: true,
    categoryColors: {_chag: 0, _qodesh: 3, _qorban: 2},
    note:
        'מוֹעֲדֵי יְהוָה, the appointed times (moʿadim) of Yahweh, holy '
        'convocations (Leviticus 23:2, 4), dated as the text dates them, by '
        'the number of the month. "The morrow after the sabbath" (Leviticus '
        '23:11, 15-16) is read as the weekly Sabbath, so the ʿomer and '
        'Shavuot fall on the first day of the week: set the day of the week '
        'the 1st of the 1st month falls on to see a year\'s weeks.',
  ),
  entries: [
    StudyTimelineEntry(
      id: 'pesach',
      title: 'Pesach (Passover)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 14),
      part: TimelineDayPart.evening,
      category: _qorban,
      verses: [
        _ref(_leviticus, 23, 5),
        _ref(_exodus, 12, 6),
        _ref(_numbers, 28, 16),
      ],
      note:
          '"In the fourteenth day of the first month between the evenings '
          '(bein haʿarbayim) is Yahweh\'s pesach" (Leviticus 23:5).',
    ),
    StudyTimelineEntry(
      id: 'matzot',
      title: 'Chag haMatzot (Unleavened Bread)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 15),
      end: const TimelineTime(0, month: 1, day: 21),
      duration: const TimelineDuration(7, _day),
      category: _chag,
      verses: [
        _ref(_leviticus, 23, 6, 8),
        _ref(_exodus, 12, 15, 20),
        _ref(_deuteronomy, 16, 3, 8),
      ],
      note:
          '"On the fifteenth day of the same month is chag hamatzot unto '
          'Yahweh: seven days ye must eat matzot" (Leviticus 23:6).',
    ),
    StudyTimelineEntry(
      id: 'matzot-1',
      title: 'Mikra qodesh (1st day of Matzot)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 15),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('matzot', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 7)],
      note:
          '"In the first day ye shall have an holy convocation: ye shall do '
          'no servile work therein" (Leviticus 23:7).',
    ),
    StudyTimelineEntry(
      id: 'matzot-7',
      title: 'Mikra qodesh (7th day of Matzot)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 21),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('matzot', TimelineDuration(7, _day)),
      verses: [_ref(_leviticus, 23, 8)],
      note:
          '"In the seventh day is an holy convocation: ye shall do no '
          'servile work therein" (Leviticus 23:8).',
    ),
    StudyTimelineEntry(
      id: 'omer',
      title: 'ʿOmer haTenufah (sheaf of the waving)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 16),
      category: _qorban,
      pin: const TimelinePin('matzot', TimelineDuration(1, _day), weekday: 1),
      verses: [
        _ref(_leviticus, 23, 9, 14),
        _ref(_mark, 16, 2),
        _ref(_corinthians, 15, 20, 23),
      ],
      note:
          'The ʿomer of the firstfruits (reshit) of the harvest, waved "on '
          'the morrow after the sabbath" (mimmochorat hashabbat, Leviticus '
          '23:10-11). Read here as the weekly Sabbath in Chag haMatzot, it '
          'falls on the first day of the week, the day Christ rose "very '
          'early in the morning the first day of the week" (Mark 16:2), '
          '"the firstfruits of them that slept" (1 Corinthians 15:20, 23).',
    ),
    StudyTimelineEntry(
      id: 'count',
      title: 'Sheva shabbatot (seven sabbaths complete)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 16),
      end: const TimelineTime(0, month: 3, day: 6),
      duration: const TimelineDuration(50, _day),
      counted: true,
      pin: const TimelinePin('omer', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 15, 16)],
      note:
          '"Ye shall count unto you from the morrow after the sabbath, from '
          'the day that ye brought the ʿomer of the waving; seven sabbaths '
          'shall be complete: even unto the morrow after the seventh sabbath '
          'shall ye number fifty days" (Leviticus 23:15-16).',
    ),
    StudyTimelineEntry(
      id: 'shavuot',
      title: 'Chag Shavuot (Feast of Weeks)',
      timelineId: '',
      start: const TimelineTime(0, month: 3, day: 6),
      category: _chag,
      pin: const TimelinePin('omer', TimelineDuration(50, _day)),
      verses: [
        _ref(_leviticus, 23, 15, 21),
        _ref(_numbers, 28, 26),
        _ref(_deuteronomy, 16, 9, 10),
        _ref(_acts, 2, 1),
      ],
      note:
          'The fiftieth day, "the morrow after the seventh sabbath" '
          '(Leviticus 23:16): the first day of the week. Chag shavuot '
          '(Exodus 34:22; Deuteronomy 16:10), yom habikkurim, the day of the '
          'firstfruits (Numbers 28:26). "When the day of Pentecost was fully '
          'come" (Acts 2:1).',
    ),
    StudyTimelineEntry(
      id: 'shavuot-qodesh',
      title: 'Mikra qodesh (Shavuot)',
      timelineId: '',
      start: const TimelineTime(0, month: 3, day: 6),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('shavuot', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 21)],
      note:
          '"Ye shall proclaim on the selfsame day, that it may be an holy '
          'convocation unto you: ye shall do no servile work therein" '
          '(Leviticus 23:21).',
    ),
    StudyTimelineEntry(
      id: 'teruah',
      title: 'Yom Teruah (day of blowing)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 1),
      category: _qodesh,
      verses: [_ref(_leviticus, 23, 23, 25), _ref(_numbers, 29, 1, 6)],
      note:
          '"In the seventh month, in the first day of the month, shall ye '
          'have a shabbaton, a memorial of blowing (zikhron teruah), an holy '
          'convocation" (Leviticus 23:24); yom teruah (Numbers 29:1).',
    ),
    StudyTimelineEntry(
      id: 'teruah-shabbaton',
      title: 'Shabbaton (Yom Teruah)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 1),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('teruah', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 24, 25)],
    ),
    StudyTimelineEntry(
      id: 'kippurim',
      title: 'Yom haKippurim (day of atonements)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 10),
      category: _qodesh,
      verses: [
        _ref(_leviticus, 23, 26, 32),
        _ref(_leviticus, 16, 29, 34),
        _ref(_numbers, 29, 7, 11),
      ],
      note:
          '"On the tenth day of this seventh month there shall be yom '
          'hakippurim: ... ye shall afflict your souls" (Leviticus 23:27); a '
          'shabbat shabbaton, "from even unto even" (Leviticus 23:32).',
    ),
    StudyTimelineEntry(
      id: 'kippurim-shabbaton',
      title: 'Shabbat shabbaton (Yom haKippurim)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 10),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('kippurim', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 32)],
    ),
    StudyTimelineEntry(
      id: 'sukkot',
      title: 'Chag haSukkot (Feast of Booths)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 15),
      end: const TimelineTime(0, month: 7, day: 21),
      duration: const TimelineDuration(7, _day),
      category: _chag,
      dayNotes: const {
        1: '13 bulls, 2 rams, 14 lambs (Numbers 29:13)',
        2: '12 bulls, 2 rams, 14 lambs (Numbers 29:17)',
        3: '11 bulls, 2 rams, 14 lambs (Numbers 29:20)',
        4: '10 bulls, 2 rams, 14 lambs (Numbers 29:23)',
        5: '9 bulls, 2 rams, 14 lambs (Numbers 29:26)',
        6: '8 bulls, 2 rams, 14 lambs (Numbers 29:29)',
        7: '7 bulls, 2 rams, 14 lambs (Numbers 29:32)',
      },
      verses: [
        _ref(_leviticus, 23, 33, 43),
        _ref(_numbers, 29, 12, 34),
        _ref(_deuteronomy, 16, 13, 15),
      ],
      note:
          '"The fifteenth day of this seventh month shall be chag hasukkot '
          'for seven days unto Yahweh" (Leviticus 23:34); "ye shall dwell in '
          'booths seven days" (Leviticus 23:42).',
    ),
    StudyTimelineEntry(
      id: 'sukkot-1',
      title: 'Shabbaton (1st day of Sukkot)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 15),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('sukkot', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 35), _ref(_leviticus, 23, 39)],
    ),
    StudyTimelineEntry(
      id: 'atzeret',
      title: 'Shemini ʿAtzeret (the 8th day)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 22),
      category: _qodesh,
      pin: const TimelinePin('sukkot', TimelineDuration(8, _day)),
      verses: [
        _ref(_leviticus, 23, 36),
        _ref(_leviticus, 23, 39),
        _ref(_numbers, 29, 35, 38),
      ],
      note:
          '"On the eighth day shall be an holy convocation unto you ... it is '
          'a solemn assembly (ʿatzeret)" (Leviticus 23:36): 1 bull, 1 ram, 7 '
          'lambs (Numbers 29:36).',
    ),
    StudyTimelineEntry(
      id: 'atzeret-shabbaton',
      title: 'Shabbaton (the 8th day)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 22),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('atzeret', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 39)],
    ),
  ],
);
