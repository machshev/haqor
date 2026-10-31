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
    this.variants = const [],
  });

  final String id;

  /// How a study's timeline linked to it starts out: its title, scale,
  /// months, note and colours, which the study may then change.
  final StudyTimeline template;

  /// Its entries, their pins to one another by these ids.
  final List<StudyTimelineEntry> entries;

  /// What it is, as offered to add.
  final String description;

  /// Its readings, each entry in one (see [StudyTimelineEntry.variant]),
  /// the first shown first; none for a timeline of one reading.
  final List<TimelineVariant> variants;
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
const _isaiah = 11;
const _jeremiah = 12;
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
      'ʿomer and Shavuot counted from the weekly Sabbath; and as kept at the '
      'going out and in the second year, by Solomon and Hezekiah, in '
      'Ezekiel\'s house, and fulfilled in the Messiah, each a reading to '
      'show alone or side by side.',
  template: const StudyTimeline(
    id: '',
    title: 'Moʿadei Yahweh (appointed times of Yahweh)',
    scale: TimelineScale.annual,
    monthNaming: TimelineMonthNaming.numbered,
    showSeasons: true,
    categoryColors: {
      _before: 5,
      _chag: 0,
      _qodesh: 3,
      _qorban: 2,
      _kipper: 4,
      _qiddush: 1,
      _aremot: 6,
      _masa: 7,
      _torah: 4,
    },
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
  variants: [for (final r in _readings) r.variant],
  entries: [for (final r in _readings) ..._read(r.variant.id, r.entries)],
);

/// The entries of the Torah's reading, Leviticus 23 with Numbers 28-29
/// and Deuteronomy 16.
final _torahEntries = <StudyTimelineEntry>[
  StudyTimelineEntry(
    id: 'before-1',
    title: 'Penei Yahweh (before Yahweh): 1st time',
    shortTitle: 'Penei Yahweh, 1st',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    end: const TimelineTime(0, month: 1, day: 21),
    duration: const TimelineDuration(8, _day),
    category: _before,
    lead: _up1,
    trail: _home1,
    style: TimelineSpanStyle.bracket,
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
    shortTitle: 'Pesach',
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
    shortTitle: 'Chag haMatzot',
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
    shortTitle: 'Miqra qodesh',
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
    shortTitle: 'Miqra qodesh',
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
    shortTitle: 'ʿOmer',
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
    shortTitle: 'Sheva shabbatot',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 16),
    end: const TimelineTime(0, month: 3, day: 6),
    duration: const TimelineDuration(50, _day),
    counted: true,
    style: TimelineSpanStyle.arrow,
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
    shortTitle: 'Penei Yahweh, 2nd',
    timelineId: '',
    start: const TimelineTime(0, month: 3, day: 6),
    end: const TimelineTime(0, month: 3, day: 6),
    duration: const TimelineDuration(1, _day),
    category: _before,
    lead: _up2,
    trail: _home2,
    style: TimelineSpanStyle.bracket,
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
    shortTitle: 'Chag Shavuot',
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
    shortTitle: 'Miqra qodesh',
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
    shortTitle: 'Yom Teruah',
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
    shortTitle: 'Shabbaton',
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
    shortTitle: 'Yom haKippurim',
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
    shortTitle: 'Shabbat shabbaton',
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
    shortTitle: 'Penei Yahweh, 3rd',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 15),
    end: const TimelineTime(0, month: 7, day: 22),
    duration: const TimelineDuration(8, _day),
    category: _before,
    lead: _up3,
    trail: _home3,
    style: TimelineSpanStyle.bracket,
    verses: [
      _ref(_deuteronomy, 16, 15, 16),
      _ref(_chronicles2, 7, 8, 10),
      _ref(_nehemiah, 8, 18),
      _ref(_leviticus, 23, 34),
      _ref(_leviticus, 23, 39),
      _ref(_numbers, 29, 12),
      _ref(_ezekiel, 45, 21),
      _ref(_ezekiel, 45, 23, 25),
      _ref(_nehemiah, 8, 14, 15),
    ],
    note:
        'The third of the three times, the seven days of the sukkot and '
        'the eighth: "seven days shalt thou keep pilgrimage to Yahweh thy '
        'God in the place which Yahweh shall choose" (Deuteronomy 16:15); '
        '"they kept the chag seven days, and on the eighth day an '
        'ʿatzeret, according to the judgment" (Nehemiah 8:18); "and in the '
        'eighth day they made an ʿatzeret ... and on the twenty-third day '
        'of the seventh month he sent the people away to their tents" (2 '
        'Chronicles 7:9-10). The first time is named by its first day, '
        '"the pesach, a chag of seven days" (Ezekiel 45:21), the pesach '
        'running on into the matzot; but Yom Teruah and Yom haKippurim '
        'stand apart from the sukkot, and are each a calling of holiness, '
        'not a chag. Each time the text counts this chag, it counts from '
        'the fifteenth: "the fifteenth day of this seventh month is the '
        'chag of the sukkot, seven days to Yahweh" (Leviticus 23:34; so '
        '23:39 and Numbers 29:12); and Ezekiel, who names the first by '
        'the pesach, begins this one "in the seventh month, in the '
        'fifteenth day of the month, in the chag, shall he do the like '
        '(kaʾelleh) seven days, according to the sin offering, according '
        'to the burnt offering" (Ezekiel 45:25), the two weeks a pair, '
        'each with seven bulls and seven rams a day, and a he-goat for a '
        'sin offering (Ezekiel 45:23). Gathered at Jerusalem on the first '
        'of the month, on the second they found the sukkot written, and "proclaimed in all '
        'their cities, and in Jerusalem, saying, Go forth unto the mount" '
        '(Nehemiah 8:14-15).',
  ),
  StudyTimelineEntry(
    id: 'sukkot',
    title: 'Chag haSukkot (pilgrimage of the booths)',
    shortTitle: 'Chag haSukkot',
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
    shortTitle: 'Shabbaton',
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
    shortTitle: 'Shemini ʿAtzeret',
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
    shortTitle: 'Shabbaton',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 22),
    sabbath: true,
    category: _qodesh,
    pin: const TimelinePin('atzeret', TimelineDuration(1, _day)),
    verses: [_ref(_leviticus, 23, 39)],
  ),
];

/// The days on the way to and from each of the three times, from Galilee,
/// as the family of Luke 2:41-44 went up from Nazareth. The text gives no
/// count of days for it: [_wayDays] is reckoned from Abraham's way from
/// Beersheba to the place, seen "on the third day" (Genesis 22:4), Galilee
/// lying further off.
const _wayDays = 4;

const _wayNote =
    'The text gives no count of days for the way: four from Galilee '
    'is reckoned from Abraham\'s, who went from Beersheba (Genesis 22:19) '
    'and "on the third day lifted up his eyes, and saw the place afar off" '
    '(Genesis 22:4); Judah lay nearer, Dan further. "Neither shall any man '
    'desire thy land, when thou goest up to appear before Yahweh thy God '
    'three times in the year" (Exodus 34:24). "If the way (hadderekh) be '
    'too long for thee ... the place too far from thee" (Deuteronomy '
    '14:24); "it is too much for you to go up to Jerusalem" (1 Kings '
    '12:28). One "in a way far off (bederekh rechoqah)" kept the pesach in '
    'the second month (Numbers 9:10-11).';

TimelineTaper _up(String note, List<StudyPassage> verses) => TimelineTaper(
  days: _wayDays,
  title: 'Maʿalah (going up)',
  note: '$note $_wayNote',
  verses: [...verses, _ref(_genesis, 22, 4), _ref(_deuteronomy, 14, 24)],
);

TimelineTaper _home(String note, List<StudyPassage> verses) => TimelineTaper(
  days: _wayDays,
  title: 'Leʾohalekha (to thy tents)',
  note: '$note $_wayNote',
  verses: [...verses, _ref(_genesis, 22, 4)],
);

final _up1 = _up(
  '"Many went up out of the country to Jerusalem before the pascha, to '
  'purify themselves" (John 11:55): one unclean by the dead was so seven '
  'days (Numbers 19:11-12), and came up the sooner.',
  [_ref(_john, 11, 55), _ref(_luke, 2, 41, 42), _ref(_numbers, 9, 10)],
);

final _home1 = _home(
  '"And having fulfilled the days, as they returned ... supposing him to '
  'have been in the company, they went a day\'s journey" (Luke 2:43-44).',
  [_ref(_luke, 2, 43, 44)],
);

final _up2 = _up(
  'In the wheat harvest (Exodus 34:22), for the one day: "blessed is the '
  'man whose strength is in thee, the highways in their heart ... they go '
  'from strength to strength, he appeareth before God in Zion" (Psalm 84:5, '
  '7).',
  [_ref(_psalms, 84, 5, 7), _ref(_exodus, 34, 22)],
);

final _home2 = _home('Back to the wheat harvest (Exodus 34:22).', [
  _ref(_exodus, 34, 22),
]);

final _up3 = _up(
  '"Our feet shall stand within thy gates, O Jerusalem ... whither the '
  'tribes go up (ʿalu), the tribes of Yah" (Psalm 122:2, 4); the going up '
  '(hammaʿalah) from Babylon took from the first of the first month to the '
  'first of the fifth (Ezra 7:9).',
  [_ref(_psalms, 122, 1, 4), _ref(_ezra, 7, 9)],
);

final _home3 = _home(
  '"On the twenty-third day of the seventh month he sent the people away '
  'to their tents (leʾohaleihem)" (2 Chronicles 7:10); "they went unto '
  'their tents joyful and glad of heart" (1 Kings 8:66).',
  [_ref(_kings1, 8, 66), _ref(_chronicles2, 7, 10)],
);

const _kipper = 'Kipper (a covering)';
const _qiddush = 'Qiddush (a hallowing)';
const _aremot = 'ʿAremot (heaps)';

/// The seven bulls, seven rams and he-goat of each day of both of
/// Ezekiel's weeks (Ezekiel 45:23), alike for both (Ezekiel 45:25).
const _ezekielDay = '7 bulls, 7 rams, 1 he-goat (Ezekiel 45:23)';

/// The appointed times as Ezekiel gives them, Ezekiel 45:18-25: the
/// sanctuary covered at the head of the year, and two weeks alike, the
/// pesach's in the first month and the chag's in the seventh.
final _ezekielEntries = <StudyTimelineEntry>[
  StudyTimelineEntry(
    id: 'cleanse-1',
    title: 'Chitte hammiqdash (cleansing the sanctuary)',
    shortTitle: 'Chitte hammiqdash',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 1),
    category: _kipper,
    verses: [_ref(_ezekiel, 45, 18, 19)],
    note:
        '"In the first month, on the first of the month, thou shalt take a '
        'young bull without blemish, and thou shalt cleanse (chitteta) the '
        'sanctuary; and the priest shall take of the blood of the sin '
        'offering and put it on the posts of the house, and on the four '
        'corners of the ledge of the altar, and on the posts of the gate '
        'of the inner court" (Ezekiel 45:18-19).',
  ),
  StudyTimelineEntry(
    id: 'cleanse-2',
    title: 'Kipper habbayit (covering the house)',
    shortTitle: 'Kipper habbayit',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 7),
    category: _kipper,
    pin: const TimelinePin('cleanse-1', TimelineDuration(7, _day)),
    verses: [_ref(_ezekiel, 45, 20)],
    note:
        '"And so thou shalt do on the seventh in the month (beshivʿah '
        'bachodesh) for every one that strayeth, and for the simple: so ye '
        'shall cover (vekhippartem) the house" (Ezekiel 45:20), as the '
        'Hebrew reads. The Septuagint reads "in the seventh month, on the '
        'first of the month" (en tō hebdomō mēni mia tou mēnos): see the '
        'Kipper habbayit of the seventh month.',
  ),
  StudyTimelineEntry(
    id: 'cleanse-7',
    title: 'Kipper habbayit (covering the house), as the Septuagint reads',
    shortTitle: 'Kipper habbayit (LXX)',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 1),
    category: _kipper,
    verses: [_ref(_ezekiel, 45, 20)],
    note:
        '"And so shalt thou do in the seventh month, on the first of the '
        'month (en tō hebdomō mēni mia tou mēnos)" (Ezekiel 45:20, '
        'Septuagint), where the Hebrew reads "on the seventh in the month" '
        'of the first. So read, each half of the year opens with the house '
        'covered on the first of the month, and its week follows at the '
        'full moon: the day of Yom Teruah (Leviticus 23:24), a covering '
        'done by the priest, not a calling up of the people.',
  ),
  StudyTimelineEntry(
    id: 'before-1',
    title: 'Penei Yahweh (before Yahweh): the first month',
    shortTitle: 'Penei Yahweh, 1st',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    end: const TimelineTime(0, month: 1, day: 21),
    duration: const TimelineDuration(8, _day),
    category: _before,
    style: TimelineSpanStyle.bracket,
    verses: [_ref(_ezekiel, 46, 9, 10)],
    note:
        '"And when the people of the land come before Yahweh (lifnei '
        'Yahweh) in the moʿadim, he that entereth by the way of the north '
        'gate to worship shall go out by the way of the south gate ... and '
        'the prince in the midst of them, when they go in, shall go in" '
        '(Ezekiel 46:9-10).',
  ),
  StudyTimelineEntry(
    id: 'pesach',
    title: 'Pesach (the passing over)',
    shortTitle: 'Pesach',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    part: TimelineDayPart.evening,
    category: _qorban,
    pin: const TimelinePin('before-1', TimelineDuration(1, _day)),
    verses: [_ref(_ezekiel, 45, 21, 22)],
    note:
        '"In the first month, on the fourteenth day of the month, the '
        'pesach shall be to you, a chag of weeks of days (shevuʿot '
        'yamim); matzot shall be eaten. And the prince shall prepare on '
        'that day, for himself and for all the people of the land, a bull '
        'for a sin offering" (Ezekiel 45:21-22). "Weeks of days" is most '
        'often read "seven days" (shivʿat yamim), as Ezekiel 45:23.',
  ),
  StudyTimelineEntry(
    id: 'chag-1',
    title: 'Chag (pilgrimage) of seven days: the first month',
    shortTitle: 'Chag, 1st month',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 15),
    end: const TimelineTime(0, month: 1, day: 21),
    duration: const TimelineDuration(7, _day),
    category: _chag,
    pin: const TimelinePin('before-1', TimelineDuration(2, _day)),
    dayNotes: const {
      1: _ezekielDay,
      2: _ezekielDay,
      3: _ezekielDay,
      4: _ezekielDay,
      5: _ezekielDay,
      6: _ezekielDay,
      7: _ezekielDay,
    },
    verses: [_ref(_ezekiel, 45, 23, 24)],
    note:
        '"And the seven days of the chag he shall prepare a burnt offering '
        'to Yahweh, seven bulls and seven rams without blemish daily the '
        'seven days, and a he-goat daily for a sin offering; and a meal '
        'offering, an ephah for a bull and an ephah for a ram, and a hin '
        'of oil for an ephah" (Ezekiel 45:23-24). Numbers gives two bulls '
        'a day (Numbers 28:19).',
  ),
  StudyTimelineEntry(
    id: 'before-7',
    title: 'Penei Yahweh (before Yahweh): the seventh month',
    shortTitle: 'Penei Yahweh, 7th',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 15),
    end: const TimelineTime(0, month: 7, day: 21),
    duration: const TimelineDuration(7, _day),
    category: _before,
    style: TimelineSpanStyle.bracket,
    verses: [_ref(_ezekiel, 46, 9, 11)],
    note:
        'The people of the land before Yahweh "in the moʿadim" (Ezekiel '
        '46:9), and "in the chaggim and in the moʿadim" (Ezekiel 46:11). '
        'Ezekiel gives the chag of the seventh month seven days, with no '
        'eighth.',
  ),
  StudyTimelineEntry(
    id: 'chag-7',
    title: 'Chag (pilgrimage) of seven days: the seventh month',
    shortTitle: 'Chag, 7th month',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 15),
    end: const TimelineTime(0, month: 7, day: 21),
    duration: const TimelineDuration(7, _day),
    category: _chag,
    pin: const TimelinePin('before-7', TimelineDuration(1, _day)),
    dayNotes: const {
      1: _ezekielDay,
      2: _ezekielDay,
      3: _ezekielDay,
      4: _ezekielDay,
      5: _ezekielDay,
      6: _ezekielDay,
      7: _ezekielDay,
    },
    verses: [_ref(_ezekiel, 45, 25), _ref(_kings1, 8, 2)],
    note:
        '"In the seventh month, on the fifteenth day of the month, in the '
        'chag, he shall do the like (kaʾelleh) seven days, according to the '
        'sin offering, according to the burnt offering, and according to '
        'the meal offering, and according to the oil" (Ezekiel 45:25): the '
        'week of the first month again. "The chag", as "in the month '
        'Ethanim, in the chag, which is the seventh month" (1 Kings 8:2). '
        'Numbers gives thirteen bulls on its first day, falling to seven '
        '(Numbers 29:13-32).',
  ),
];

/// Hezekiah's pesach, 2 Chronicles 29-31: in the first year of his reign
/// the house hallowed through the first month, the pesach kept in the
/// second, and the chag of the matzot kept twice over.
final _hezekiahEntries = <StudyTimelineEntry>[
  StudyTimelineEntry(
    id: 'hallow',
    title: 'Qiddush habbayit (hallowing the house)',
    shortTitle: 'Qiddush habbayit',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 1),
    end: const TimelineTime(0, month: 1, day: 16),
    duration: const TimelineDuration(16, _day),
    category: _qiddush,
    verses: [_ref(_chronicles2, 29, 3, 19)],
    note:
        '"And they began on the first of the first month to hallow, and on '
        'the eighth day of the month they came to the porch of Yahweh; and '
        'they hallowed the house of Yahweh in eight days, and on the '
        'sixteenth day of the first month they made an end" (2 Chronicles '
        '29:17). "Carry forth the uncleanness (hanniddah) out of the holy '
        'place" (2 Chronicles 29:5).',
  ),
  StudyTimelineEntry(
    id: 'porch',
    title: 'Ulam Yahweh (the porch of Yahweh)',
    shortTitle: 'The porch',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 8),
    category: _qiddush,
    pin: const TimelinePin('hallow', TimelineDuration(8, _day)),
    verses: [_ref(_chronicles2, 29, 16, 17)],
    note:
        'The court cleansed in eight days, "and on the eighth day of the '
        'month they came to the porch of Yahweh" (2 Chronicles 29:17): the '
        'house within in eight more. "The priests went into the inner part '
        'of the house of Yahweh to cleanse it, and brought out all the '
        'uncleanness ... and the Levites took it, to carry it out abroad '
        'into the brook Kidron" (2 Chronicles 29:16).',
  ),
  StudyTimelineEntry(
    id: 'pesach-1',
    title: 'Pesach of the first month, not kept',
    shortTitle: 'Pesach, not kept',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    part: TimelineDayPart.evening,
    category: _qorban,
    verses: [_ref(_chronicles2, 30, 2, 3), _ref(_leviticus, 23, 5)],
    note:
        'The fourteenth fell within the hallowing: "for they could not keep '
        'it at that time, because the priests had not hallowed themselves '
        'enough, and the people had not gathered themselves to Jerusalem" '
        '(2 Chronicles 30:3).',
  ),
  StudyTimelineEntry(
    id: 'atonement',
    title: 'Chattat (sin offering) for the kingdom',
    shortTitle: 'Chattat',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 17),
    category: _qorban,
    pin: const TimelinePin('hallow', TimelineDuration(17, _day)),
    verses: [_ref(_chronicles2, 29, 20, 24)],
    note:
        'The text gives no day: "then Hezekiah the king rose early" (2 '
        'Chronicles 29:20), after the making an end on the sixteenth, so '
        'shown the morning after. "Seven bulls, and seven rams, and seven '
        'lambs, and seven he-goats, for a sin offering for the kingdom, and '
        'for the sanctuary, and for Judah ... to cover (lekhapper) for all '
        'Israel" (2 Chronicles 29:21, 24).',
  ),
  StudyTimelineEntry(
    id: 'before',
    title: 'Penei Yahweh (before Yahweh): the second month',
    shortTitle: 'Penei Yahweh',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 14),
    end: const TimelineTime(0, month: 2, day: 28),
    duration: const TimelineDuration(15, _day),
    category: _before,
    lead: _upHezekiah,
    trail: _homeHezekiah,
    style: TimelineSpanStyle.bracket,
    verses: [_ref(_chronicles2, 30, 1, 13)],
    note:
        '"And Hezekiah sent to all Israel and Judah, and wrote letters also '
        'to Ephraim and Manasseh, that they should come to the house of '
        'Yahweh at Jerusalem, to keep the pesach to Yahweh God of Israel" '
        '(2 Chronicles 30:1); "and there gathered at Jerusalem much '
        'people, to keep the chag of the matzot in the second month, a very '
        'great congregation" (2 Chronicles 30:13).',
  ),
  StudyTimelineEntry(
    id: 'pesach',
    title: 'Pesach (the passing over) in the second month',
    shortTitle: 'Pesach',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 14),
    part: TimelineDayPart.evening,
    category: _qorban,
    pin: const TimelinePin('before', TimelineDuration(1, _day)),
    verses: [_ref(_chronicles2, 30, 15, 20), _ref(_numbers, 9, 10, 11)],
    note:
        '"Then they killed the pesach on the fourteenth of the second '
        'month" (2 Chronicles 30:15), as "in the second month, on the '
        'fourteenth day, between the evenings" (Numbers 9:11). Many "had '
        'not cleansed themselves, yet did they eat the pesach otherwise '
        'than it was written; but Hezekiah prayed for them, saying, '
        'Yahweh the good cover (yekhapper) for every one ... and Yahweh '
        'hearkened to Hezekiah, and healed the people" (2 Chronicles '
        '30:18-20).',
  ),
  StudyTimelineEntry(
    id: 'matzot',
    title: 'Chag haMatzot (pilgrimage of the unleavened)',
    shortTitle: 'Chag haMatzot',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 15),
    end: const TimelineTime(0, month: 2, day: 21),
    duration: const TimelineDuration(7, _day),
    category: _chag,
    pin: const TimelinePin('before', TimelineDuration(2, _day)),
    verses: [_ref(_chronicles2, 30, 21, 22)],
    note:
        '"And the children of Israel that were found at Jerusalem kept the '
        'chag of the matzot seven days with great gladness" (2 Chronicles '
        '30:21).',
  ),
  StudyTimelineEntry(
    id: 'other-seven',
    title: 'Shivʿat yamim acherim (other seven days)',
    shortTitle: 'Other seven days',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 22),
    end: const TimelineTime(0, month: 2, day: 28),
    duration: const TimelineDuration(7, _day),
    category: _chag,
    pin: const TimelinePin('before', TimelineDuration(9, _day)),
    verses: [
      _ref(_chronicles2, 30, 23, 27),
      _ref(_kings1, 8, 65),
      _ref(_chronicles2, 7, 8, 9),
    ],
    note:
        '"And the whole assembly took counsel to keep other seven days; '
        'and they kept other seven days with gladness" (2 Chronicles '
        '30:23). Hezekiah gave a thousand bulls and seven thousand sheep, '
        'and the princes a thousand bulls and ten thousand sheep (2 '
        'Chronicles 30:24). Fourteen days, as Solomon\'s "seven days and '
        'seven days" (1 Kings 8:65).',
  ),
  StudyTimelineEntry(
    id: 'heaps',
    title: 'ʿAremot (heaps) of the firstfruits and the tithe',
    shortTitle: 'ʿAremot',
    timelineId: '',
    start: const TimelineTime(0, month: 3),
    end: const TimelineTime(0, month: 7),
    category: _aremot,
    verses: [_ref(_chronicles2, 31, 4, 10)],
    note:
        '"In the third month they began to lay the foundation of the '
        'heaps, and in the seventh month they made an end" (2 Chronicles '
        '31:7): from the wheat harvest of Shavuot to the ingathering of '
        'Sukkot. "The children of Israel brought in abundance the '
        'firstfruits of grain, wine, and oil, and honey, and of all the '
        'increase of the field; and the tithe of all things" (2 Chronicles '
        '31:5).',
  ),
];

final _upHezekiah = _up(
  '"So the runners passed from city to city through the land of Ephraim '
  'and Manasseh, even unto Zebulun; but they laughed them to scorn ... '
  'nevertheless men of Asher and Manasseh and of Zebulun humbled '
  'themselves, and came to Jerusalem" (2 Chronicles 30:10-11).',
  [_ref(_chronicles2, 30, 6, 11), _ref(_numbers, 9, 10)],
);

final _homeHezekiah = _home(
  '"All Israel that were found went out to the cities of Judah, and broke '
  'the pillars ... then all the children of Israel returned, every man to '
  'his possession, into their own cities" (2 Chronicles 31:1).',
  [_ref(_chronicles2, 31, 1)],
);

const _masa = 'Masaʿ (a journeying)';
const _torah = 'Torah (a teaching)';
const _messiah = 'Mashiach (the anointed)';

/// [entries] as the reading [variant] of the moʿadim: each in it, its id
/// and its pin's anchor prefixed with the reading's but for the Torah's.
List<StudyTimelineEntry> _read(
  String variant,
  List<StudyTimelineEntry> entries,
) {
  String own(String id) => variant == _torahReading ? id : '$variant-$id';
  return [
    for (final e in entries)
      StudyTimelineEntry.fromJson({
        ...e.toJson(),
        'id': own(e.id),
        'variant': variant,
        if (e.pin case final pin?)
          'pin': TimelinePin(
            own(pin.anchorId),
            pin.offset,
            weekday: pin.weekday,
          ).toJson(),
      })!,
  ];
}

const _torahReading = 'torah';

/// The readings of the moʿadim, in the order of the text: the Torah's;
/// the year of the going out, and the second year; Solomon's, Hezekiah's
/// and Ezekiel's; and the Messiah's.
final _readings = <({TimelineVariant variant, List<StudyTimelineEntry> entries})>[
  (
    variant: const TimelineVariant(
      id: _torahReading,
      title: 'The Torah: Leviticus 23',
      shortTitle: 'Torah',
    ),
    entries: _torahEntries,
  ),
  (
    variant: const TimelineVariant(
      id: 'going-out',
      title: 'The going out: Exodus 12-20',
      shortTitle: 'Going out',
      note:
          'The first year, "this month shall be to you the beginning of '
          'months" (Exodus 12:2): the lamb taken on the tenth, the pesach on '
          'the fourteenth, the going out on the fifteenth, the manna and the '
          'first sabbath in the second month, and the words at Sinai in the '
          'third. The ʿomer and Shavuot were not yet kept, "when ye come into '
          'the land" (Leviticus 23:10); the text does not tie Shavuot to '
          'Sinai, though counted from the morrow of the pesach the fiftieth '
          'day falls in the first days of the third month. Verses rendered '
          'literally.',
    ),
    entries: _goingOutEntries,
  ),
  (
    variant: const TimelineVariant(
      id: 'second-year',
      title: 'The second year: Exodus 40, Leviticus 8-9, Numbers 1-10',
      shortTitle: 'Second year',
      note:
          '"In the first month in the second year, on the first of the month, '
          'the mishkan was raised up" (Exodus 40:17): the priests filled seven '
          'days and the eighth day, the pesach kept at Sinai, and one kept a '
          'month on by those unclean, whence Hezekiah\'s. As Ezekiel\'s altar: '
          '"seven days shall they cover the altar ... and when these days are '
          'fulfilled, on the eighth day and onward" (Ezekiel 43:26-27). The '
          'text dates the raising, the pesach, the counting and the going on; '
          'the filling and the princes\' days are reckoned from the raising, '
          'when the anointing was commanded (Exodus 40:9-15). Verses rendered '
          'literally.',
    ),
    entries: _secondYearEntries,
  ),
  (
    variant: const TimelineVariant(
      id: 'solomon',
      title: 'Solomon\'s dedication: 1 Kings 8, 2 Chronicles 5-7',
      shortTitle: 'Solomon',
      note:
          '"All the men of Israel assembled themselves to king Solomon at the '
          'chag, in the month Ethanim, which is the seventh month" (1 Kings '
          '8:2): the altar dedicated seven days and the chag seven days, '
          '"fourteen days" (1 Kings 8:65), the eighth an ʿatzeret, and the '
          'people sent home on the twenty-third (2 Chronicles 7:9-10). The '
          'house was founded in Ziv, the second month, of his fourth year, and '
          'finished in Bul, the eighth, of his eleventh (1 Kings 6:1, 37-38). '
          'Of the times kept after: "according to the commandment of Moses, '
          'on the sabbaths, and on the new moons, and on the moʿadim, three '
          'times in the year: in the chag of the matzot, and in the chag of '
          'the shavuot, and in the chag of the sukkot" (2 Chronicles 8:13). '
          'Verses rendered literally.',
    ),
    entries: _solomonEntries,
  ),
  (
    variant: const TimelineVariant(
      id: 'hezekiah',
      title: 'Hezekiah\'s pesach: 2 Chronicles 29-31',
      shortTitle: 'Hezekiah',
      note:
          '"In the first year of his reign, in the first month, he opened the '
          'doors of the house of Yahweh, and repaired them" (2 Chronicles '
          '29:3), dated as the text dates it. The house was being hallowed '
          'through the fourteenth of the first month, so the pesach was kept '
          'in the second, as the Torah allows one unclean or "in a way far '
          'off" (Numbers 9:10-11); and having kept the matzot seven days they '
          'kept "other seven days" (2 Chronicles 30:23), fourteen days, as at '
          'Solomon\'s dedication, "seven days and seven days, fourteen days" '
          '(1 Kings 8:65): "since the time of Solomon the son of David king '
          'of Israel there was not the like in Jerusalem" (2 Chronicles '
          '30:26). As in Ezekiel, the house is cleansed from the first of the '
          'month (Ezekiel 45:18), and a sin offering of sevens made "for all '
          'Israel" (2 Chronicles 29:21, 24). Verses rendered literally.',
    ),
    entries: _hezekiahEntries,
  ),
  (
    variant: const TimelineVariant(
      id: 'ezekiel',
      title: 'Ezekiel\'s house: Ezekiel 45:18-25',
      shortTitle: 'Ezekiel',
      note:
          'The times of the house Ezekiel was shown (Ezekiel 40-48), as he '
          'dates them: "it shall be the prince\'s part to give burnt '
          'offerings ... in the chaggim, and in the new moons, and in the '
          'sabbaths, in all the moʿadim of the house of Israel: he shall '
          'prepare the sin offering ... to make atonement (lekhapper) for the '
          'house of Israel" (Ezekiel 45:17). Of the moʿadim of Leviticus 23 '
          'Ezekiel gives the two weeks, and makes them alike, "he shall do '
          'the like (kaʾelleh)" (Ezekiel 45:25), with no Shavuot, Yom Teruah '
          'or Yom haKippurim; the covering is done in the cleansings at the '
          'head of the year (Ezekiel 45:18-20) and in the sin offering of each '
          'day of both weeks. Matzot opens the year, "the beginning of months" '
          '(Exodus 12:2), and the chag of the ingathering is "at the turn of '
          'the year" (Exodus 34:22); both remember the going out of Egypt '
          '(Exodus 23:15; Leviticus 23:43), as Ezekiel\'s is a new going out: '
          '"I will bring you out from the peoples ... into the wilderness of '
          'the peoples" (Ezekiel 20:34-35). Verses rendered literally.',
    ),
    entries: _ezekielEntries,
  ),
  (
    variant: const TimelineVariant(
      id: 'messiah',
      title: 'The Messiah: the Gospels and Acts',
      shortTitle: 'Messiah',
      note:
          '"For even Christ our pascha was sacrificed for us; therefore let us '
          'keep the feast, not with old leaven" (1 Corinthians 5:7-8); "now '
          'Christ has been raised from the dead, a first portion (aparchē) of '
          'those fallen asleep" (1 Corinthians 15:20); "and in the day of the '
          'fiftieth being fulfilled" (Acts 2:1). Dated as John dates the '
          'pesach, "the preparation of the pascha" (John 19:14), and the '
          'resurrection on the morrow of the sabbath, as the ʿomer is here: '
          'set the day of the week the 1st of the 1st month falls on to see '
          'the weeks. John\'s Sukkot and Dedication are of the autumn and '
          'winter before (John 7:2; 10:22). Verses rendered literally.',
    ),
    entries: _messiahEntries,
  ),
];

/// The first year, from the lamb taken to the words at Sinai.
final _goingOutEntries = <StudyTimelineEntry>[
  StudyTimelineEntry(
    id: 'lamb',
    title: 'Seh (a lamb) taken',
    shortTitle: 'Lamb taken',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 10),
    category: _qorban,
    verses: [_ref(_exodus, 12, 3, 6)],
    note:
        '"On the tenth of this month they shall take to them every man a '
        'lamb (seh), according to the house of the fathers ... and ye shall '
        'keep it until the fourteenth day of this month" (Exodus 12:3, 6).',
  ),
  StudyTimelineEntry(
    id: 'pesach',
    title: 'Pesach (the passing over) in Egypt',
    shortTitle: 'Pesach',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    part: TimelineDayPart.evening,
    category: _qorban,
    pin: const TimelinePin('lamb', TimelineDuration(5, _day)),
    verses: [_ref(_exodus, 12, 6, 13)],
    note:
        '"And the whole assembly of the congregation of Israel shall kill it '
        'between the evenings; and they shall take of the blood, and put it '
        'on the two side posts and on the lintel ... and when I see the '
        'blood, I will pass over (ufasachti) you" (Exodus 12:6-7, 13).',
  ),
  StudyTimelineEntry(
    id: 'smiting',
    title: 'Makkat bekhorot (the smiting of the firstborn)',
    shortTitle: 'The firstborn',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 15),
    part: TimelineDayPart.night,
    category: _qorban,
    pin: const TimelinePin('pesach', TimelineDuration(2, _day)),
    verses: [_ref(_exodus, 12, 29, 33)],
    note:
        '"And it came to pass at midnight, that Yahweh smote all the '
        'firstborn in the land of Egypt" (Exodus 12:29): the night after '
        'the lamb was killed, the day running from sunset.',
  ),
  StudyTimelineEntry(
    id: 'going-out',
    title: 'Yetziʾat Mitzrayim (the going out of Egypt)',
    shortTitle: 'The going out',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 15),
    end: const TimelineTime(0, month: 3, day: 1),
    category: _masa,
    pin: const TimelinePin('pesach', TimelineDuration(2, _day)),
    verses: [
      _ref(_numbers, 33, 3, 15),
      _ref(_exodus, 12, 41),
      _ref(_exodus, 13, 4),
    ],
    note:
        '"And they journeyed from Rameses in the first month, on the '
        'fifteenth day of the first month; on the morrow of the pesach the '
        'children of Israel went out with a high hand" (Numbers 33:3); "on '
        'the bone of this day (beʿetsem hayom hazzeh) all the hosts of '
        'Yahweh went out" (Exodus 12:41); "this day ye go out, in the month '
        'Abib" (Exodus 13:4). By Succoth, Etham, the sea, Marah, Elim, the '
        'wilderness of Sin and Rephidim to Sinai (Numbers 33:5-15).',
  ),
  StudyTimelineEntry(
    id: 'matzot',
    title: 'Matzot (the unleavened), seven days',
    shortTitle: 'Matzot',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 15),
    end: const TimelineTime(0, month: 1, day: 21),
    duration: const TimelineDuration(7, _day),
    category: _chag,
    pin: const TimelinePin('pesach', TimelineDuration(2, _day)),
    verses: [_ref(_exodus, 12, 15, 20), _ref(_exodus, 12, 39)],
    note:
        '"They baked unleavened cakes of the dough which they brought forth '
        'out of Egypt, for it was not leavened; because they were thrust out '
        'of Egypt, and could not tarry" (Exodus 12:39); "seven days shall ye '
        'eat matzot" (Exodus 12:15).',
  ),
  StudyTimelineEntry(
    id: 'sea',
    title: 'Yam Suf (the sea of reeds)',
    shortTitle: 'Yam Suf',
    timelineId: '',
    start: const TimelineTime(0, month: 1),
    category: _masa,
    verses: [_ref(_exodus, 14, 21, 31), _ref(_numbers, 33, 5, 8)],
    note:
        'The text gives no day, only the first month: from Rameses to '
        'Succoth, to Etham, to Pi-hahiroth, "and they passed through the '
        'midst of the sea into the wilderness, and went three days\' journey '
        'in the wilderness of Etham, and pitched in Marah" (Numbers '
        '33:5-8).',
  ),
  StudyTimelineEntry(
    id: 'sin',
    title: 'Midbar Sin (the wilderness of Sin): the quail',
    shortTitle: 'Wilderness of Sin',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 15),
    part: TimelineDayPart.evening,
    category: _masa,
    verses: [_ref(_exodus, 16, 1, 13)],
    note:
        '"They came to the wilderness of Sin ... on the fifteenth day of the '
        'second month after their going out of the land of Egypt" (Exodus '
        '16:1); "between the evenings ye shall eat flesh, and in the morning '
        'ye shall be filled with bread ... and at evening the quail came '
        'up" (Exodus 16:12-13).',
  ),
  StudyTimelineEntry(
    id: 'manna',
    title: 'Man (the manna): six days gathered',
    shortTitle: 'Manna',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 16),
    end: const TimelineTime(0, month: 2, day: 21),
    duration: const TimelineDuration(6, _day),
    counted: true,
    category: _qorban,
    pin: const TimelinePin('sin', TimelineDuration(2, _day)),
    verses: [_ref(_exodus, 16, 13, 26)],
    note:
        '"And in the morning the dew lay round about the camp ... and they '
        'said one to another, Man hu (what is it)?" (Exodus 16:13, 15); '
        '"six days ye shall gather it" (Exodus 16:26). The text does not '
        'say the six days began the morning after the quail; so reckoned.',
  ),
  StudyTimelineEntry(
    id: 'sabbath',
    title: 'Shabbaton (a ceasing): the sabbath first named',
    shortTitle: 'The first sabbath',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 22),
    sabbath: true,
    category: _qodesh,
    pin: const TimelinePin('manna', TimelineDuration(7, _day)),
    verses: [_ref(_exodus, 16, 22, 30)],
    note:
        '"Tomorrow is a ceasing (shabbaton), a sabbath of holiness to '
        'Yahweh ... six days ye shall gather it; but on the seventh day, the '
        'sabbath, in it there shall be none" (Exodus 16:23, 26); "so the '
        'people ceased (vayyishbetu) on the seventh day" (Exodus 16:30). '
        'The seventh from the first morning of manna, as reckoned.',
  ),
  StudyTimelineEntry(
    id: 'sinai',
    title: 'Midbar Sinai (the wilderness of Sinai)',
    shortTitle: 'Sinai',
    timelineId: '',
    start: const TimelineTime(0, month: 3, day: 1),
    category: _masa,
    verses: [_ref(_exodus, 19, 1, 2)],
    note:
        '"In the third month (bachodesh hashlishi) after the children of '
        'Israel were gone out of the land of Egypt, on this day (bayyom '
        'hazzeh) they came into the wilderness of Sinai" (Exodus 19:1): '
        'chodesh, month, is the new moon, and "this day" read as its first.',
  ),
  StudyTimelineEntry(
    id: 'before',
    title: 'Penei Yahweh (before Yahweh): the day of the assembly',
    shortTitle: 'Penei Yahweh',
    timelineId: '',
    start: const TimelineTime(0, month: 3, day: 3),
    end: const TimelineTime(0, month: 3, day: 3),
    duration: const TimelineDuration(1, _day),
    category: _before,
    style: TimelineSpanStyle.bracket,
    pin: const TimelinePin('sinai', TimelineDuration(3, _day)),
    verses: [
      _ref(_exodus, 19, 10, 17),
      _ref(_deuteronomy, 4, 10),
      _ref(_deuteronomy, 10, 4),
    ],
    note:
        '"Hallow them today and tomorrow ... and be ready for the third day, '
        'for on the third day Yahweh will come down in the sight of all the '
        'people upon mount Sinai" (Exodus 19:10-11); "and Moses brought '
        'forth the people out of the camp to meet God" (Exodus 19:17); "the '
        'day that thou stoodest before Yahweh thy God (lifnei Yahweh) in '
        'Horeb" (Deuteronomy 4:10), "the day of the assembly (yom '
        'haqqahal)" (Deuteronomy 10:4). The text does not say how long '
        'Moses\' going up and down took (Exodus 19:3-9): shown the third day '
        'from the coming, the soonest it allows; the rabbis reckon the sixth '
        'or seventh (Shabbat 86b).',
  ),
  StudyTimelineEntry(
    id: 'words',
    title: 'ʿAseret haddevarim (the ten words)',
    shortTitle: 'The ten words',
    timelineId: '',
    start: const TimelineTime(0, month: 3, day: 3),
    part: TimelineDayPart.daytime,
    category: _torah,
    pin: const TimelinePin('before', TimelineDuration(1, _day)),
    verses: [
      _ref(_exodus, 19, 16, 19),
      _ref(_exodus, 20, 1, 17),
      _ref(_exodus, 24, 18),
    ],
    note:
        '"And it came to pass on the third day, when it was morning, that '
        'there were voices and lightnings ... and the voice of the shofar '
        'exceeding loud" (Exodus 19:16); "and God spake all these words" '
        '(Exodus 20:1). Then Moses was in the mount "forty days and forty '
        'nights" (Exodus 24:18), undated.',
  ),
];

/// The second year, from the raising of the mishkan to the going on from
/// Sinai.
final _secondYearEntries = <StudyTimelineEntry>[
  StudyTimelineEntry(
    id: 'mishkan',
    title: 'Hakamat hammishkan (the raising of the dwelling)',
    shortTitle: 'The mishkan raised',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 1),
    category: _qiddush,
    verses: [_ref(_exodus, 40, 1, 17), _ref(_exodus, 40, 34, 35)],
    note:
        '"On the first day of the first month shalt thou raise up the '
        'mishkan of the tent of meeting ... and thou shalt anoint it" '
        '(Exodus 40:2, 9); "then the cloud covered the tent of meeting, and '
        'the glory of Yahweh filled the mishkan" (Exodus 40:34).',
  ),
  StudyTimelineEntry(
    id: 'milluim',
    title: 'Yemei milluʾim (the days of filling)',
    shortTitle: 'Milluʾim',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 1),
    end: const TimelineTime(0, month: 1, day: 7),
    duration: const TimelineDuration(7, _day),
    counted: true,
    category: _kipper,
    pin: const TimelinePin('mishkan', TimelineDuration(1, _day)),
    verses: [_ref(_leviticus, 8, 33, 35), _ref(_exodus, 29, 35, 37)],
    note:
        '"Ye shall not go out from the door of the tent of meeting seven '
        'days, until the days of your filling (milluʾeikhem) be fulfilled; '
        'for seven days shall he fill your hand" (Leviticus 8:33); "seven '
        'days thou shalt cover (tekhapper) for the altar" (Exodus 29:37). '
        'Reckoned from the raising, the text not dating them.',
  ),
  StudyTimelineEntry(
    id: 'eighth',
    title: 'Yom hashemini (the eighth day): fire from before Yahweh',
    shortTitle: 'The eighth day',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 8),
    category: _qorban,
    pin: const TimelinePin('milluim', TimelineDuration(8, _day)),
    verses: [_ref(_leviticus, 9, 1, 24), _ref(_ezekiel, 43, 26, 27)],
    note:
        '"And it came to pass on the eighth day, that Moses called Aaron and '
        'his sons" (Leviticus 9:1); "and there came forth fire from before '
        'Yahweh (millifnei Yahweh), and consumed upon the altar the burnt '
        'offering ... and all the people saw, and shouted, and fell on '
        'their faces" (Leviticus 9:24).',
  ),
  StudyTimelineEntry(
    id: 'princes',
    title: 'Chanukkat hammizbeach (the dedicating of the altar): the princes',
    shortTitle: 'The princes',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 1),
    end: const TimelineTime(0, month: 1, day: 12),
    duration: const TimelineDuration(12, _day),
    counted: true,
    category: _qiddush,
    pin: const TimelinePin('mishkan', TimelineDuration(1, _day)),
    verses: [
      _ref(_numbers, 7, 1, 2),
      _ref(_numbers, 7, 10, 12),
      _ref(_numbers, 7, 84, 89),
    ],
    note:
        '"On the day that Moses had made an end of raising the mishkan, and '
        'had anointed it ... the princes offered for the dedicating of the '
        'altar (chanukkat hammizbeach) ... each prince on his day" (Numbers '
        '7:1, 10-11), twelve days. Reckoned from the raising.',
  ),
  StudyTimelineEntry(
    id: 'pesach',
    title: 'Pesach (the passing over) at Sinai',
    shortTitle: 'Pesach',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    part: TimelineDayPart.evening,
    category: _qorban,
    verses: [_ref(_numbers, 9, 1, 5)],
    note:
        '"And they kept the pesach in the first month, on the fourteenth day '
        'of the month, between the evenings, in the wilderness of Sinai" '
        '(Numbers 9:5): the one pesach the text tells of in the wilderness.',
  ),
  StudyTimelineEntry(
    id: 'census',
    title: 'Seʾu et rosh (lift up the head): the counting',
    shortTitle: 'The counting',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 1),
    category: _masa,
    verses: [_ref(_numbers, 1, 1, 3)],
    note:
        '"On the first of the second month, in the second year after they '
        'were come out of the land of Egypt, saying, Lift up the head of all '
        'the congregation" (Numbers 1:1-2).',
  ),
  StudyTimelineEntry(
    id: 'pesach-sheni',
    title: 'Pesach (the passing over) in the second month',
    shortTitle: 'Pesach, 2nd month',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 14),
    part: TimelineDayPart.evening,
    category: _qorban,
    verses: [_ref(_numbers, 9, 6, 14)],
    note:
        '"There were certain men, who were unclean by the soul of a man, '
        'that they could not keep the pesach on that day" (Numbers 9:6); '
        '"if any man be unclean by reason of a soul, or be in a way far off '
        '... in the second month, on the fourteenth day, between the '
        'evenings they shall keep it" (Numbers 9:10-11). Hezekiah kept it '
        'so (2 Chronicles 30:2, 15).',
  ),
  StudyTimelineEntry(
    id: 'onward',
    title: 'Naʿalah heʿanan (the cloud taken up)',
    shortTitle: 'The cloud taken up',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 20),
    category: _masa,
    verses: [_ref(_numbers, 10, 11, 13)],
    note:
        '"And it came to pass in the second year, in the second month, on '
        'the twentieth of the month, that the cloud was taken up from over '
        'the mishkan of the testimony; and the children of Israel journeyed '
        'from the wilderness of Sinai" (Numbers 10:11-12).',
  ),
];

/// Solomon's dedication of the house, in the seventh month.
final _solomonEntries = <StudyTimelineEntry>[
  StudyTimelineEntry(
    id: 'glory',
    title: 'Hakkavod (the glory) fills the house',
    shortTitle: 'The glory',
    timelineId: '',
    start: const TimelineTime(0, month: 7),
    category: _qiddush,
    verses: [
      _ref(_kings1, 8, 1, 11),
      _ref(_chronicles2, 5, 2, 14),
      _ref(_chronicles2, 7, 1, 3),
    ],
    note:
        'The text gives the month, not the day: "at the chag, in the month '
        'Ethanim" (1 Kings 8:2). The ark brought up, "the cloud filled the '
        'house of Yahweh, so that the priests could not stand to minister '
        'because of the cloud" (1 Kings 8:10-11); and when Solomon had made '
        'an end of praying, "the fire came down from heaven, and consumed '
        'the burnt offering" (2 Chronicles 7:1), as on the eighth day of '
        'the filling (Leviticus 9:24).',
  ),
  StudyTimelineEntry(
    id: 'before',
    title: 'Penei Yahweh (before Yahweh): fourteen days',
    shortTitle: 'Penei Yahweh',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 8),
    end: const TimelineTime(0, month: 7, day: 22),
    duration: const TimelineDuration(15, _day),
    category: _before,
    lead: _upSolomon,
    trail: _homeSolomon,
    style: TimelineSpanStyle.bracket,
    verses: [_ref(_kings1, 8, 65, 66), _ref(_chronicles2, 7, 8, 10)],
    note:
        '"And at that time Solomon kept the chag, and all Israel with him, '
        'a great congregation, from the entering in of Hamath to the brook '
        'of Egypt, before Yahweh our God (lifnei Yahweh eloheinu), seven '
        'days and seven days, fourteen days" (1 Kings 8:65), and the eighth '
        'after.',
  ),
  StudyTimelineEntry(
    id: 'dedication',
    title: 'Chanukkat hammizbeach (the dedicating of the altar)',
    shortTitle: 'Chanukkat hammizbeach',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 8),
    end: const TimelineTime(0, month: 7, day: 14),
    duration: const TimelineDuration(7, _day),
    category: _qiddush,
    pin: const TimelinePin('before', TimelineDuration(1, _day)),
    verses: [_ref(_chronicles2, 7, 4, 9), _ref(_kings1, 8, 62, 64)],
    note:
        '"For they kept the dedicating of the altar seven days, and the chag '
        'seven days" (2 Chronicles 7:9): counted back from the twenty-third, '
        'the eighth to the fourteenth. "Solomon offered a sacrifice of '
        'peace offerings ... two and twenty thousand oxen, and a hundred '
        'and twenty thousand sheep" (1 Kings 8:63). The tenth, Yom '
        'haKippurim, falls within them; the text does not speak of it.',
  ),
  StudyTimelineEntry(
    id: 'chag',
    title: 'Hechag (the chag) seven days',
    shortTitle: 'Hechag',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 15),
    end: const TimelineTime(0, month: 7, day: 21),
    duration: const TimelineDuration(7, _day),
    category: _chag,
    pin: const TimelinePin('before', TimelineDuration(8, _day)),
    verses: [_ref(_chronicles2, 7, 8, 9), _ref(_kings1, 8, 65)],
    note:
        '"Also at the same time Solomon kept the chag seven days, and all '
        'Israel with him, a very great congregation" (2 Chronicles 7:8).',
  ),
  StudyTimelineEntry(
    id: 'atzeret',
    title: 'ʿAtzeret (a restraint): the eighth day',
    shortTitle: 'ʿAtzeret',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 22),
    category: _qodesh,
    pin: const TimelinePin('before', TimelineDuration(15, _day)),
    verses: [_ref(_chronicles2, 7, 9)],
    note:
        '"And on the eighth day they made an ʿatzeret" (2 Chronicles 7:9). '
        '"On the eighth day he sent the people away" (1 Kings 8:66): the '
        'eighth of the chag, the people going on the morrow.',
  ),
];

final _upSolomon = _up(
  '"From the entering in of Hamath to the brook of Egypt" (1 Kings 8:65): '
  'the land at its widest, "before Yahweh our God".',
  [_ref(_kings1, 8, 65)],
);

final _homeSolomon = _home(
  '"And on the twenty-third day of the seventh month he sent the people '
  'away to their tents, glad and merry in heart" (2 Chronicles 7:10).',
  [_ref(_kings1, 8, 66), _ref(_chronicles2, 7, 10)],
);

/// The Messiah's feasts: John's Sukkot and Dedication, the pesach of the
/// cross, the resurrection on the morrow of the sabbath, the forty days,
/// and the fiftieth.
final _messiahEntries = <StudyTimelineEntry>[
  StudyTimelineEntry(
    id: 'bethany',
    title: 'Bethany, six days before the pascha',
    shortTitle: 'Bethany',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 8),
    category: _messiah,
    verses: [_ref(_john, 12, 1, 8)],
    note:
        '"Then Jesus six days before the pascha came to Bethany" (John '
        '12:1), counted back from the fourteenth; "she hath kept this '
        'against the day of my burying" (John 12:7).',
  ),
  StudyTimelineEntry(
    id: 'entry',
    title: 'Hoshaʿna (save now): the coming into Jerusalem',
    shortTitle: 'Hoshaʿna',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 9),
    category: _messiah,
    pin: const TimelinePin('bethany', TimelineDuration(2, _day)),
    verses: [
      _ref(_john, 12, 12, 15),
      _ref(_exodus, 12, 3),
      _ref(_psalms, 118, 25, 27),
    ],
    note:
        '"On the morrow (tē epaurion) much people that were come to the '
        'feast ... took branches of palm trees, and went forth to meet him, '
        'and cried, Hosanna" (John 12:12-13), from "save now (hoshiʿah na) '
        '... bind the chag with cords" (Psalm 118:25, 27). The lamb was '
        'taken on the tenth (Exodus 12:3): by John\'s count the ninth, or '
        'the tenth if the six days are counted to the fifteenth.',
  ),
  StudyTimelineEntry(
    id: 'supper',
    title: 'The supper, in the night he was handed over',
    shortTitle: 'The supper',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    part: TimelineDayPart.night,
    category: _messiah,
    verses: [
      _ref(_john, 13, 1, 2),
      _ref(_luke, 22, 15, 20),
      _ref(_corinthians, 11, 23, 26),
    ],
    note:
        '"Now before the feast of the pascha ... and supper being ended" '
        '(John 13:1-2); "with desire I have desired to eat this pascha with '
        'you before I suffer" (Luke 22:15); "the Lord Jesus, in the night in '
        'which he was handed over, took bread" (1 Corinthians 11:23). The '
        'night that begins the fourteenth, the day running from sunset.',
  ),
  StudyTimelineEntry(
    id: 'cross',
    title: 'To pascha hēmōn (our pascha) sacrificed',
    shortTitle: 'Our pascha',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    part: TimelineDayPart.evening,
    category: _qorban,
    verses: [
      _ref(_john, 19, 14, 16),
      _ref(_john, 19, 31, 36),
      _ref(_corinthians, 5, 7, 8),
      _ref(_exodus, 12, 46),
    ],
    note:
        '"And it was the preparation of the pascha, and about the sixth '
        'hour" (John 19:14); "and at the ninth hour Jesus cried with a loud '
        'voice" (Mark 15:34), between the evenings, when the pesach was '
        'killed (Exodus 12:6). "These things were done, that the scripture '
        'should be fulfilled, A bone of him shall not be broken" (John '
        '19:36; Exodus 12:46). "Christ our pascha was sacrificed for us" (1 '
        'Corinthians 5:7).',
  ),
  StudyTimelineEntry(
    id: 'tomb',
    title: 'The burial, before the high day',
    shortTitle: 'The burial',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 14),
    part: TimelineDayPart.evening,
    category: _messiah,
    pin: const TimelinePin('cross', TimelineDuration(1, _day)),
    verses: [
      _ref(_john, 19, 31),
      _ref(_john, 19, 38, 42),
      _ref(_mark, 15, 42, 46),
    ],
    note:
        '"That the bodies should not remain upon the cross on the sabbath, '
        'for that sabbath day was a high day (megalē)" (John 19:31): the '
        'fifteenth, the first day of matzot, a calling of holiness '
        '(Leviticus 23:7). "There laid they Jesus therefore because of the '
        'preparation" (John 19:42).',
  ),
  StudyTimelineEntry(
    id: 'matzot',
    title: 'The days of the unleavened',
    shortTitle: 'Matzot',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 15),
    end: const TimelineTime(0, month: 1, day: 21),
    duration: const TimelineDuration(7, _day),
    category: _chag,
    verses: [_ref(_luke, 22, 1), _ref(_corinthians, 5, 8)],
    note:
        '"The feast of the unleavened drew nigh, which is called the '
        'pascha" (Luke 22:1); "let us keep the feast, not with old leaven ... '
        'but with the unleavened of sincerity and truth" (1 Corinthians '
        '5:8).',
  ),
  StudyTimelineEntry(
    id: 'raised',
    title: 'Aparchē (a first portion): raised',
    shortTitle: 'Raised',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 16),
    category: _messiah,
    pin: const TimelinePin('matzot', TimelineDuration(1, _day), weekday: 1),
    verses: [
      _ref(_mark, 16, 1, 6),
      _ref(_john, 20, 1, 17),
      _ref(_corinthians, 15, 20, 23),
      _ref(_leviticus, 23, 10, 11),
    ],
    note:
        '"Very early on the first of the sabbaths (mia tōn sabbatōn) they '
        'came to the tomb" (Mark 16:2); "he is risen, he is not here" (Mark '
        '16:6); "touch me not, for I am not yet ascended to my Father" (John '
        '20:17). The day of the ʿomer, the sheaf of the beginning waved '
        '"on the morrow of the sabbath" (Leviticus 23:11): "Christ the first '
        'portion (aparchē), afterward they that are Christ\'s" (1 '
        'Corinthians 15:23).',
  ),
  StudyTimelineEntry(
    id: 'forty',
    title: 'Tessarakonta hēmerai (forty days) appearing',
    shortTitle: 'Forty days',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 16),
    end: const TimelineTime(0, month: 2, day: 25),
    duration: const TimelineDuration(40, _day),
    counted: true,
    category: _messiah,
    pin: const TimelinePin('raised', TimelineDuration(1, _day)),
    verses: [_ref(_acts, 1, 3), _ref(_corinthians, 15, 5, 8)],
    note:
        '"To whom also he shewed himself alive after his suffering by many '
        'proofs, being seen of them through forty days, and speaking of the '
        'things of the kingdom of God" (Acts 1:3).',
  ),
  StudyTimelineEntry(
    id: 'ascended',
    title: 'Analēmphthē (taken up)',
    shortTitle: 'Taken up',
    timelineId: '',
    start: const TimelineTime(0, month: 2, day: 25),
    category: _messiah,
    pin: const TimelinePin('raised', TimelineDuration(40, _day)),
    verses: [_ref(_acts, 1, 4, 12), _ref(_luke, 24, 49, 53)],
    note:
        '"While they beheld, he was taken up; and a cloud received him out '
        'of their sight" (Acts 1:9), the fortieth day as Acts 1:3 is read. '
        '"Tarry ye in the city of Jerusalem, until ye be clothed with power '
        'from on high" (Luke 24:49).',
  ),
  StudyTimelineEntry(
    id: 'count',
    title: 'Sheva shabbatot temimot (seven complete sabbaths)',
    shortTitle: 'Sheva shabbatot',
    timelineId: '',
    start: const TimelineTime(0, month: 1, day: 16),
    end: const TimelineTime(0, month: 3, day: 6),
    duration: const TimelineDuration(50, _day),
    counted: true,
    style: TimelineSpanStyle.arrow,
    pin: const TimelinePin('raised', TimelineDuration(1, _day)),
    verses: [_ref(_leviticus, 23, 15, 16)],
    note:
        'Counted from the day of the ʿomer, the day he was raised '
        '(Leviticus 23:15-16).',
  ),
  StudyTimelineEntry(
    id: 'pentecost',
    title: 'Hē hēmera tēs pentēkostēs (the day of the fiftieth)',
    shortTitle: 'The fiftieth',
    timelineId: '',
    start: const TimelineTime(0, month: 3, day: 6),
    category: _chag,
    pin: const TimelinePin('raised', TimelineDuration(50, _day)),
    verses: [
      _ref(_acts, 2, 1, 13),
      _ref(_acts, 2, 41),
      _ref(_exodus, 32, 28),
      _ref(_jeremiah, 31, 33),
    ],
    note:
        '"And in the day of the fiftieth (pentēkostē) being fulfilled, they '
        'were all with one accord in one place ... and they were all filled '
        'with the Holy Spirit" (Acts 2:1, 4); "there were dwelling at '
        'Jerusalem Jews, devout men, out of every nation under heaven" (Acts '
        '2:5), come up for Shavuot. "About three thousand souls" were added '
        '(Acts 2:41), as at Sinai "there fell of the people that day about '
        'three thousand men" (Exodus 32:28): "I will put my law in their '
        'inward parts, and write it in their hearts" (Jeremiah 31:33).',
  ),
  StudyTimelineEntry(
    id: 'sukkot',
    title: 'Skēnopēgia (the pitching of booths)',
    shortTitle: 'Sukkot in John',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 15),
    end: const TimelineTime(0, month: 7, day: 22),
    duration: const TimelineDuration(8, _day),
    category: _chag,
    verses: [_ref(_john, 7, 2, 14)],
    note:
        '"Now the feast of the Jews, the pitching of booths (skēnopēgia), '
        'was at hand" (John 7:2); "now about the middle of the feast Jesus '
        'went up into the temple, and taught" (John 7:14). The autumn '
        'before the pascha of the cross.',
  ),
  StudyTimelineEntry(
    id: 'great-day',
    title: 'The last day, the great day of the feast',
    shortTitle: 'The great day',
    timelineId: '',
    start: const TimelineTime(0, month: 7, day: 22),
    category: _messiah,
    pin: const TimelinePin('sukkot', TimelineDuration(8, _day)),
    verses: [_ref(_john, 7, 37, 39), _ref(_isaiah, 12, 3)],
    note:
        '"In the last day, that great day of the feast, Jesus stood and '
        'cried, saying, If any man thirst, let him come unto me, and drink" '
        '(John 7:37); "with joy shall ye draw water out of the wells of '
        'salvation" (Isaiah 12:3). Shown on the eighth, the ʿatzeret, a '
        'calling of holiness (Leviticus 23:36); some read the seventh.',
  ),
  StudyTimelineEntry(
    id: 'dedication',
    title: 'Ta enkainia (the dedication)',
    shortTitle: 'Dedication',
    timelineId: '',
    start: const TimelineTime(0, month: 9, day: 25),
    category: _qiddush,
    verses: [_ref(_john, 10, 22, 30)],
    note:
        '"And it was at Jerusalem the dedication (ta enkainia), and it was '
        'winter; and Jesus walked in the temple in Solomon\'s porch" (John '
        '10:22-23): the altar dedicated again on the twenty-fifth of the '
        'ninth month (1 Maccabees 4:52-59), not of the moʿadim of the '
        'Torah; the day from Maccabees.',
  ),
];
