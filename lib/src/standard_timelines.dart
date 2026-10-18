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

const _genesis = 0;
const _exodus = 1;
const _leviticus = 2;
const _numbers = 3;
const _deuteronomy = 4;
const _kings1 = 9;
const _psalms = 26;
const _ezra = 35;
const _ezekiel = 13;
const _nehemiah = 36;
const _chronicles2 = 38;
const _mark = 40;
const _luke = 41;
const _john = 42;
const _acts = 43;
const _corinthians = 45;
const _chag = 'Chag (pilgrimage)';
const _before = 'Penei Yahweh (before Yahweh)';
const _derekh = 'Derekh (the way)';
const _qodesh = 'Miqra qodesh (a calling of holiness)';
const _qorban = 'Qorban (a bringing near)';

const _day = TimelineDurationUnit.days;

/// The appointed times of Yahweh, Leviticus 23, with their offerings from
/// Numbers 28-29 and Deuteronomy 16; dated as the text dates them, by the
/// number of the month and day, and counted where the text counts. Names
/// are the text's, glossed literally, and verses rendered literally.
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
    categoryColors: {_before: 5, _derekh: 6, _chag: 0, _qodesh: 3, _qorban: 2},
    note:
        'מוֹעֲדֵי יְהוָה, "the appointed times of Yahweh, which ye shall call '
        'callings of holiness" (Leviticus 23:2, 4), dated as the text dates '
        'them, by the number of the month. "The morrow of the sabbath" '
        '(Leviticus 23:11, 15-16) is read as the weekly Sabbath, so the '
        'ʿomer and Shavuot fall on the first day of the week: set the day '
        'of the week the 1st of the 1st month falls on to see a year\'s '
        'weeks. Names are glossed, and verses rendered, literally. Each '
        'chag is a pilgrimage: "three times in the year shall all thy males '
        'appear before Yahweh thy God in the place which he shall choose" '
        '(Deuteronomy 16:16); "I went with them to the house of God ... a '
        'multitude keeping pilgrimage (chogeg)" (Psalm 42:4). The three '
        'times before Yahweh are shown as the days spent at the place, the '
        'feasts of each pinned to it; the seven sabbaths run from the first '
        'to the second.',
  ),
  entries: [
    StudyTimelineEntry(
      id: 'before-1',
      title: 'Penei Yahweh (before Yahweh): 1st time',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 14),
      end: const TimelineTime(0, month: 1, day: 21),
      duration: const TimelineDuration(8, _day),
      category: _before,
      verses: [
        _ref(_deuteronomy, 16, 16),
        _ref(_exodus, 23, 17),
        _ref(_deuteronomy, 16, 5, 8),
        _ref(_chronicles2, 30, 21),
        _ref(_chronicles2, 35, 17),
        _ref(_luke, 2, 41, 43),
        _ref(_john, 11, 55),
      ],
      note:
          '"Three times (shalosh peʿamim) in the year shall all thy males '
          'appear before Yahweh thy God in the place which he shall choose: '
          'in the chag of the matzot, and in the chag of the shavuot, and in '
          'the chag of the sukkot" (Deuteronomy 16:16). The first, from '
          'the pesach, sacrificed "at the place which Yahweh thy God shall '
          'choose" (Deuteronomy 16:5-6), through the seven days of the '
          'matzot: "they kept the chag of the matzot seven days" (2 '
          'Chronicles 35:17); "his parents went to Jerusalem every year at '
          'the pilgrimage of the pascha ... and having fulfilled the days, '
          'as they returned" (Luke 2:41, 43). "Thou shalt turn in the '
          'morning and go to thy tents" (Deuteronomy 16:7) follows the '
          'pesach, before the six days of matzot and the ʿatzeret of the '
          'seventh (Deuteronomy 16:8).',
    ),
    StudyTimelineEntry(
      id: 'pesach',
      title: 'Pesach (the passing over)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 14),
      part: TimelineDayPart.evening,
      pin: const TimelinePin('before-1', TimelineDuration(1, _day)),
      // A single day, kept where the pilgrims came up for Chag haMatzot, and
      // named with it, but not a chag of its own.
      category: _qorban,
      verses: [
        _ref(_leviticus, 23, 5),
        _ref(_exodus, 12, 6),
        _ref(_exodus, 12, 13),
        _ref(_numbers, 28, 16),
        _ref(_exodus, 34, 25),
        _ref(_deuteronomy, 16, 5, 7),
        _ref(_ezekiel, 45, 21),
        _ref(_john, 11, 55),
      ],
      note:
          '"In the first month, in the fourteenth of the month, between the '
          'evenings, a passing over (pesach) to Yahweh" (Leviticus 23:5); "I '
          'will pass over (ufasachti) you" (Exodus 12:13). A single day, '
          'kept where the pilgrims came up, the evening before Chag '
          'haMatzot: "thou mayest not sacrifice the pesach within any of thy '
          'gates, but at the place which Yahweh thy God shall choose ... and '
          'thou shalt turn in the morning and go to thy tents" (Deuteronomy '
          '16:5-7); "many went up to Jerusalem out of the country before the '
          'pascha" (John 11:55). Named with the pilgrimage that follows it: '
          '"the sacrifice of the pilgrimage of the passing over (zevach chag '
          'hapesach)" (Exodus 34:25); "the pesach, a pilgrimage of seven '
          'days" (Ezekiel 45:21), the seven those of Matzot.',
    ),
    StudyTimelineEntry(
      id: 'matzot',
      title: 'Chag haMatzot (pilgrimage of the unleavened)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 15),
      end: const TimelineTime(0, month: 1, day: 21),
      duration: const TimelineDuration(7, _day),
      category: _chag,
      pin: const TimelinePin('before-1', TimelineDuration(2, _day)),
      verses: [
        _ref(_leviticus, 23, 6, 8),
        _ref(_exodus, 12, 15, 20),
        _ref(_deuteronomy, 16, 3, 8),
        _ref(_deuteronomy, 16, 16),
      ],
      note:
          '"And on the fifteenth day of this month, a pilgrimage of the '
          'unleavened (chag hamatzot) to Yahweh: seven days unleavened things '
          'ye shall eat" (Leviticus 23:6).',
    ),
    StudyTimelineEntry(
      id: 'matzot-1',
      title: 'Miqra qodesh (1st day of Matzot)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 15),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('matzot', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 7)],
      note:
          '"On the first day a calling of holiness shall be to you; any work '
          'of service ye shall not do" (Leviticus 23:7).',
    ),
    StudyTimelineEntry(
      id: 'matzot-7',
      title: 'Miqra qodesh (7th day of Matzot)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 21),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('matzot', TimelineDuration(7, _day)),
      verses: [_ref(_leviticus, 23, 8)],
      note:
          '"On the seventh day a calling of holiness; any work of service ye '
          'shall not do" (Leviticus 23:8).',
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
          '"Ye shall bring the sheaf of the beginning (reshit) of your harvest '
          'to the priest, and he shall wave the sheaf before Yahweh for your '
          'acceptance; from the morrow of the sabbath (mimmochorat hashabbat) '
          'the priest shall wave it" (Leviticus 23:10-11). Read as the weekly '
          'Sabbath in Chag haMatzot, it falls on the first day of the week, '
          'when they came to the tomb "very early on the first of the '
          'sabbaths (mia tōn sabbatōn)" (Mark 16:2): "Christ has been raised '
          'from the dead, a first portion (aparchē) of those fallen asleep" '
          '(1 Corinthians 15:20, 23).',
    ),
    StudyTimelineEntry(
      id: 'count',
      title: 'Sheva shabbatot temimot (seven complete sabbaths)',
      timelineId: '',
      start: const TimelineTime(0, month: 1, day: 16),
      end: const TimelineTime(0, month: 3, day: 6),
      duration: const TimelineDuration(50, _day),
      counted: true,
      pin: const TimelinePin('omer', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 15, 16)],
      note:
          '"And ye shall count for yourselves from the morrow of the sabbath, '
          'from the day of your bringing the sheaf of the waving: seven '
          'complete sabbaths (sheva shabbatot temimot) they shall be. Until '
          'the morrow of the seventh sabbath ye shall count fifty days" '
          '(Leviticus 23:15-16).',
    ),
    StudyTimelineEntry(
      id: 'before-2',
      title: 'Penei Yahweh (before Yahweh): 2nd time',
      timelineId: '',
      start: const TimelineTime(0, month: 3, day: 6),
      end: const TimelineTime(0, month: 3, day: 6),
      duration: const TimelineDuration(1, _day),
      category: _before,
      pin: const TimelinePin('omer', TimelineDuration(50, _day)),
      verses: [
        _ref(_deuteronomy, 16, 16),
        _ref(_deuteronomy, 16, 11),
        _ref(_acts, 2, 1, 5),
        _ref(_acts, 20, 16),
      ],
      note:
          'The second of the three times, the fiftieth day, the one day the '
          'text gives: "thou shalt rejoice before Yahweh thy God ... in the '
          'place which Yahweh thy God shall choose" (Deuteronomy 16:11); '
          '"there were dwelling at Jerusalem Jews, devout men, out of every '
          'nation under heaven" (Acts 2:5); "he hastened, if it were possible '
          'for him, to be at Jerusalem the day of the fiftieth" (Acts '
          '20:16).',
    ),
    StudyTimelineEntry(
      id: 'shavuot',
      title: 'Chag Shavuot (pilgrimage of weeks)',
      timelineId: '',
      start: const TimelineTime(0, month: 3, day: 6),
      // A span of its one day, to stand with the other pilgrimages.
      end: const TimelineTime(0, month: 3, day: 6),
      duration: const TimelineDuration(1, _day),
      category: _chag,
      pin: const TimelinePin('before-2', TimelineDuration(1, _day)),
      verses: [
        _ref(_leviticus, 23, 15, 21),
        _ref(_exodus, 34, 22),
        _ref(_numbers, 28, 26),
        _ref(_deuteronomy, 16, 9, 10),
        _ref(_acts, 2, 1),
      ],
      note:
          'The fiftieth day, "the morrow of the seventh sabbath" (Leviticus '
          '23:16): the first day of the week. "A pilgrimage of weeks '
          '(shavuot, sevens) thou shalt make for thee, the first-ripe of the '
          'wheat harvest" (Exodus 34:22); "the day of the first-ripe (yom '
          'habikkurim)" (Numbers 28:26). "In the day of the fiftieth '
          '(pentēkostē) being fulfilled" (Acts 2:1).',
    ),
    StudyTimelineEntry(
      id: 'shavuot-qodesh',
      title: 'Miqra qodesh (Shavuot)',
      timelineId: '',
      start: const TimelineTime(0, month: 3, day: 6),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('shavuot', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 21)],
      note:
          '"And ye shall call on the bone of this day (beʿetsem hayom hazeh): '
          'a calling of holiness it shall be to you; any work of service ye '
          'shall not do" (Leviticus 23:21).',
    ),
    StudyTimelineEntry(
      id: 'teruah',
      title: 'Yom Teruah (day of the shout and blast)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 1),
      category: _qodesh,
      verses: [
        _ref(_leviticus, 23, 23, 25),
        _ref(_numbers, 29, 1, 6),
        _ref(_numbers, 10, 9),
      ],
      note:
          '"In the seventh month, on the first of the month, shall be to you '
          'a ceasing (shabbaton), a remembrance of shout and blast (zikhron '
          'teruah), a calling of holiness" (Leviticus 23:24); "a day of '
          'shout and blast (yom teruah) it shall be to you" (Numbers 29:1). '
          'Teruah, from rua, is the shout of the people at Jericho (Joshua '
          '6:5, 20) and the blast of alarm sounded (Numbers 10:5-9).',
    ),
    StudyTimelineEntry(
      id: 'teruah-shabbaton',
      title: 'Shabbaton (a ceasing, Yom Teruah)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 1),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('teruah', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 24, 25)],
    ),
    StudyTimelineEntry(
      id: 'kippurim',
      title: 'Yom haKippurim (day of the coverings)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 10),
      category: _qodesh,
      verses: [
        _ref(_leviticus, 23, 26, 32),
        _ref(_leviticus, 16, 29, 34),
        _ref(_numbers, 29, 7, 11),
        _ref(_genesis, 6, 14),
      ],
      note:
          '"Only, on the tenth of this seventh month, a day of the coverings '
          '(yom hakippurim) it is: a calling of holiness it shall be to you, '
          'and ye shall humble your souls" (Leviticus 23:27); "a ceasing of '
          'ceasing (shabbat shabbaton) it is to you ... from evening to '
          'evening ye shall cease your ceasing" (Leviticus 23:32). Kippurim '
          'is plural, from kaphar, to cover: "thou shalt cover (kaphar) it '
          'within and without with covering (kopher)" (Genesis 6:14).',
    ),
    StudyTimelineEntry(
      id: 'kippurim-shabbaton',
      title: 'Shabbat shabbaton (a ceasing of ceasing, Yom haKippurim)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 10),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('kippurim', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 32)],
    ),
    StudyTimelineEntry(
      id: 'before-3',
      title: 'Penei Yahweh (before Yahweh): 3rd time',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 15),
      end: const TimelineTime(0, month: 7, day: 22),
      duration: const TimelineDuration(8, _day),
      category: _before,
      verses: [
        _ref(_deuteronomy, 16, 15, 16),
        _ref(_chronicles2, 7, 8, 10),
        _ref(_nehemiah, 8, 18),
      ],
      note:
          'The third of the three times, the seven days of the sukkot and '
          'the eighth: "seven days shalt thou keep pilgrimage to Yahweh thy '
          'God in the place which Yahweh shall choose" (Deuteronomy 16:15); '
          '"they kept the chag seven days, and on the eighth day an '
          'ʿatzeret, according to the judgment" (Nehemiah 8:18); "and in the '
          'eighth day they made an ʿatzeret ... and on the twenty-third day '
          'of the seventh month he sent the people away to their tents" (2 '
          'Chronicles 7:9-10).',
    ),
    StudyTimelineEntry(
      id: 'sukkot',
      title: 'Chag haSukkot (pilgrimage of the booths)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 15),
      end: const TimelineTime(0, month: 7, day: 21),
      duration: const TimelineDuration(7, _day),
      category: _chag,
      pin: const TimelinePin('before-3', TimelineDuration(1, _day)),
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
        _ref(_deuteronomy, 16, 13, 16),
      ],
      note:
          '"On the fifteenth day of this seventh month, a pilgrimage of the '
          'booths (chag hasukkot), seven days, to Yahweh" (Leviticus 23:34); '
          '"in the booths ye shall dwell seven days" (Leviticus 23:42).',
    ),
    StudyTimelineEntry(
      id: 'sukkot-1',
      title: 'Shabbaton (a ceasing, 1st day of Sukkot)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 15),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('sukkot', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 35), _ref(_leviticus, 23, 39)],
    ),
    StudyTimelineEntry(
      id: 'atzeret',
      title: 'Shemini ʿAtzeret (the eighth, a restraint)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 22),
      category: _qodesh,
      pin: const TimelinePin('before-3', TimelineDuration(8, _day)),
      verses: [
        _ref(_leviticus, 23, 36),
        _ref(_leviticus, 23, 39),
        _ref(_numbers, 29, 35, 38),
      ],
      note:
          '"On the eighth day a calling of holiness shall be to you ... a '
          'restraint (ʿatzeret) it is; any work of service ye shall not do" '
          '(Leviticus 23:36); ʿatzeret from ʿatzar, to restrain, shut in. 1 '
          'bull, 1 ram, 7 lambs (Numbers 29:36).',
    ),
    StudyTimelineEntry(
      id: 'atzeret-shabbaton',
      title: 'Shabbaton (a ceasing, the eighth day)',
      timelineId: '',
      start: const TimelineTime(0, month: 7, day: 22),
      sabbath: true,
      category: _qodesh,
      pin: const TimelinePin('atzeret', TimelineDuration(1, _day)),
      verses: [_ref(_leviticus, 23, 39)],
    ),
    ..._ways,
  ],
);

/// The days on the way to and from each of the three times, from Galilee,
/// as the family of Luke 2:41-44 went up from Nazareth. The text gives no
/// count of days for it: [_wayDays] is reckoned from Abraham's way from
/// Beersheba to the place, seen "on the third day" (Genesis 22:4), Galilee
/// lying further off.
const _wayDays = 4.0;

const _wayNote =
    'The text gives no count of days for the way: four from Galilee '
    'is reckoned from Abraham\'s, who went from Beersheba (Genesis 22:19) '
    'and "on the third day lifted up his eyes, and saw the place afar off" '
    '(Genesis 22:4); Judah lay nearer, Dan further. "Three times in the '
    'year shall all thy males appear before Yahweh thy God" (Deuteronomy '
    '16:16); "neither shall any man desire thy land, when thou goest up to '
    'appear before Yahweh thy God three times in the year" (Exodus 34:24). '
    '"If the way (hadderekh) be too long for thee ... the place too far '
    'from thee" (Deuteronomy 14:24); "it is too much for you to go up to '
    'Jerusalem" (1 Kings 12:28). One "in a way far off (bederekh '
    'rechoqah)" kept the pesach in the second month (Numbers 9:10-11).';

/// The way up to the time [n], and home from it, which lasts [days].
List<StudyTimelineEntry> _way(
  int n,
  String ordinal,
  (TimelineTime, TimelineTime) up,
  (TimelineTime, TimelineTime) home,
  int days, {
  required List<StudyPassage> upVerses,
  required List<StudyPassage> homeVerses,
  required String upNote,
  required String homeNote,
}) {
  final anchor = 'before-$n';
  return [
    StudyTimelineEntry(
      id: 'up-$n',
      title: 'Maʿalah (going up) to the $ordinal time',
      timelineId: '',
      start: up.$1,
      end: up.$2,
      duration: const TimelineDuration(_wayDays, _day),
      category: _derekh,
      pin: TimelinePin(anchor, const TimelineDuration(1 - _wayDays, _day)),
      verses: [...upVerses, _ref(_genesis, 22, 4), _ref(_deuteronomy, 14, 24)],
      note: '$upNote $_wayNote',
    ),
    StudyTimelineEntry(
      id: 'home-$n',
      title: 'Leʾohalekha (to thy tents) from the $ordinal time',
      timelineId: '',
      start: home.$1,
      end: home.$2,
      duration: const TimelineDuration(_wayDays, _day),
      category: _derekh,
      pin: TimelinePin(anchor, TimelineDuration(days + 1.0, _day)),
      verses: [...homeVerses, _ref(_genesis, 22, 4)],
      note: '$homeNote $_wayNote',
    ),
  ];
}

TimelineTime _date(int month, int day) =>
    TimelineTime(0, month: month, day: day);

final _ways = [
  ..._way(
    1,
    '1st',
    (_date(1, 10), _date(1, 13)),
    (_date(1, 22), _date(1, 25)),
    8,
    upVerses: [
      _ref(_john, 11, 55),
      _ref(_luke, 2, 41, 42),
      _ref(_numbers, 9, 10),
    ],
    homeVerses: [_ref(_luke, 2, 43, 44)],
    upNote:
        '"Many went up out of the country to Jerusalem before the pascha, to '
        'purify themselves" (John 11:55): one unclean by the dead was so '
        'seven days (Numbers 19:11-12), and came up the sooner.',
    homeNote:
        '"And having fulfilled the days, as they returned ... supposing him '
        'to have been in the company, they went a day\'s journey" (Luke '
        '2:43-44).',
  ),
  ..._way(
    2,
    '2nd',
    (_date(3, 2), _date(3, 5)),
    (_date(3, 7), _date(3, 10)),
    1,
    upVerses: [_ref(_psalms, 84, 5, 7), _ref(_exodus, 34, 22)],
    homeVerses: [_ref(_exodus, 34, 22)],
    upNote:
        'In the wheat harvest (Exodus 34:22), for the one day: "blessed is '
        'the man whose strength is in thee, the highways in their heart ... '
        'they go from strength to strength, he appeareth before God in Zion" '
        '(Psalm 84:5, 7).',
    homeNote: 'Back to the wheat harvest (Exodus 34:22).',
  ),
  ..._way(
    3,
    '3rd',
    (_date(7, 11), _date(7, 14)),
    (_date(7, 23), _date(7, 26)),
    8,
    upVerses: [_ref(_psalms, 122, 1, 4), _ref(_ezra, 7, 9)],
    homeVerses: [_ref(_kings1, 8, 66), _ref(_chronicles2, 7, 10)],
    upNote:
        '"Our feet shall stand within thy gates, O Jerusalem ... whither the '
        'tribes go up (ʿalu), the tribes of Yah" (Psalm 122:2, 4); the '
        'going up (hammaʿalah) from Babylon took from the first of the first '
        'month to the first of the fifth (Ezra 7:9).',
    homeNote:
        '"On the twenty-third day of the seventh month he sent the people '
        'away to their tents (leʾohaleihem)" (2 Chronicles 7:10); "they went '
        'unto their tents joyful and glad of heart" (1 Kings 8:66).',
  ),
];
