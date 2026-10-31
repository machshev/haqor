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
final standardTimelines = [_moadim, _ezekielMoadim, _hezekiahPesach];

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
    categoryColors: {_before: 5, _chag: 0, _qodesh: 3, _qorban: 2},
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
  ],
);

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
final _ezekielMoadim = StandardTimeline(
  id: 'ezekiel-moadim',
  description:
      'Ezekiel 45:18-25: the sanctuary cleansed at the head of the year, and '
      'two weeks alike, the pesach\'s in the first month and the chag\'s in '
      'the seventh, the prince providing for the people.',
  template: const StudyTimeline(
    id: '',
    title: 'Moʿadim beYechezqel (the appointed times in Ezekiel)',
    scale: TimelineScale.annual,
    monthNaming: TimelineMonthNaming.numbered,
    showSeasons: true,
    categoryColors: {_before: 5, _chag: 0, _qorban: 2, _kipper: 4},
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
  entries: [
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
  ],
);

/// Hezekiah's pesach, 2 Chronicles 29-31: in the first year of his reign
/// the house hallowed through the first month, the pesach kept in the
/// second, and the chag of the matzot kept twice over.
final _hezekiahPesach = StandardTimeline(
  id: 'hezekiah-pesach',
  description:
      '2 Chronicles 29-31: the house hallowed from the first of the first '
      'month, the pesach kept in the second month, the matzot seven days '
      'and other seven days, and the heaps gathered to the seventh month.',
  template: const StudyTimeline(
    id: '',
    title: 'Pesach Chizqiyyahu (the pesach of Hezekiah)',
    scale: TimelineScale.annual,
    monthNaming: TimelineMonthNaming.numbered,
    showSeasons: true,
    categoryColors: {_before: 5, _chag: 0, _qorban: 2, _qiddush: 1, _aremot: 6},
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
  entries: [
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
  ],
);

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
