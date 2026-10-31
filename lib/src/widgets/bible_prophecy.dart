import '../study_workspace.dart';
import 'bible_timeline_page.dart';

/// The category of Daniel's kingdoms and times on [bibleTimeline] (see
/// [bibleDaniel]).
const bibleDanielCategory = 'Daniel';

/// The category of the Apocalypse's seals, trumpets and vials, and the
/// events in them, on [bibleTimeline] (see [bibleApocalypse]).
const bibleApocalypseCategory = 'Apocalypse';

/// The books of Daniel and Revelation, by their index among the books.
const _danielBook = 34;
const _revelation = 65;

StudyPassage _passage(
  int book,
  int chapter,
  int verse, [
  int? endChapter,
  int? endVerse,
]) => StudyPassage(
  bookIndex: book,
  chapter: chapter,
  verse: verse,
  endChapter: endChapter == chapter ? null : endChapter,
  endVerse: endVerse,
);

StudyPassage _dan(int chapter, int verse, [int? endChapter, int? endVerse]) =>
    _passage(_danielBook, chapter, verse, endChapter, endVerse);

StudyPassage _rev(int chapter, int verse, [int? endChapter, int? endVerse]) =>
    _passage(_revelation, chapter, verse, endChapter, endVerse);

/// The year now, to which what is still running is drawn.
int get _now => DateTime.now().year;

TimelineTime _year(int year, [int? month, int? day]) =>
    TimelineTime(year.toDouble(), month: month, day: day);

/// Makes the entries of one prophecy's [category] on [bibleTimeline], in
/// the order made, after the Bible's own events (ordered by their index),
/// each id under [prefix]: a span from its start to its end, or an event
/// at its start for no end.
StudyTimelineEntry Function(
  String id,
  String title,
  TimelineTime start,
  TimelineTime? end,
  List<StudyPassage> verses,
  String note,
)
_maker(String prefix, String category, int first) {
  var order = first;
  return (id, title, start, end, verses, note) {
    final length = end == null
        ? null
        : TimelineDuration(
            bibleTimeline.positionOf(end) - bibleTimeline.positionOf(start),
            TimelineDurationUnit.years,
          );
    return StudyTimelineEntry(
      id: '$prefix:$id',
      title: title,
      timelineId: bibleTimeline.id,
      start: start,
      end: end,
      duration: length,
      verses: verses,
      note: note,
      category: category,
      order: order++,
    );
  };
}

/// Daniel's kingdoms and times, read through history, a day for a year:
/// the image of Daniel 2, the beasts from the sea of Daniel 7, the ram and
/// the he-goat of Daniel 8, the seventy weeks of Daniel 9, the kings of
/// the north and south of Daniel 11, and the times of Daniel 12. The stone
/// cut out without hands, still to strike the image, is not drawn.
List<StudyTimelineEntry> get bibleDaniel {
  final entry = _maker('daniel', bibleDanielCategory, 1000000);
  return [
    // The image of Daniel 2.
    entry(
      'image:gold',
      'Head of gold: Babylon',
      _year(-605),
      _year(-539, 10, 12),
      [_dan(2, 31, 2, 38)],
      '"Thou art this head of gold": Nebuchadnezzar\'s kingdom, from '
          'Carchemish and the first captivity, to Babylon taken by the '
          'Medes and Persians.',
    ),
    entry(
      'image:silver',
      'Breast and arms of silver: Medo-Persia',
      _year(-539, 10, 12),
      _year(-331, 10, 1),
      [_dan(2, 32), _dan(2, 39)],
      'The kingdom of the Medes and Persians, from Cyrus to the defeat of '
          'Darius III at Gaugamela.',
    ),
    entry(
      'image:brass',
      'Belly and thighs of brass: Greece',
      _year(-331, 10, 1),
      _year(-168, 6, 22),
      [_dan(2, 32), _dan(2, 39)],
      'Alexander\'s kingdom and those of his successors, ruling over all '
          'the earth, until Rome broke Macedon at Pydna.',
    ),
    entry(
      'image:iron',
      'Legs of iron: Rome',
      _year(-168, 6, 22),
      _year(476, 9, 4),
      [_dan(2, 33), _dan(2, 40)],
      'Rome, breaking in pieces and subduing all things: from Pydna, '
          'divided into its two legs, East and West, in 395, to the end of '
          'the empire in the West.',
    ),
    entry(
      'image:feet',
      'Feet of iron and clay',
      _year(476, 9, 4),
      _year(_now),
      [_dan(2, 33), _dan(2, 41, 2, 43)],
      'The kingdoms of Europe out of Rome, partly strong and partly '
          'broken, mingling but not cleaving together, until the stone '
          'cut out without hands strikes the image on its feet.',
    ),
    // The beasts from the sea, Daniel 7.
    entry(
      'beast:lion',
      'The lion with eagle\'s wings',
      _year(-605),
      _year(-539, 10, 12),
      [_dan(7, 4), _dan(7, 17)],
      'Babylon: its wings plucked, made to stand as a man and given a '
          'man\'s heart, as Nebuchadnezzar was humbled.',
    ),
    entry(
      'beast:bear',
      'The bear raised up on one side',
      _year(-539, 10, 12),
      _year(-331, 10, 1),
      [_dan(7, 5)],
      'Medo-Persia, Persia the higher side, with three ribs in its mouth: '
          'Lydia, Babylon and Egypt devoured.',
    ),
    entry(
      'beast:leopard',
      'The leopard with four wings and four heads',
      _year(-331, 10, 1),
      _year(-30, 8, 1),
      [_dan(7, 6)],
      'Greece, swift as Alexander\'s conquests, its four heads his '
          'successors\' kingdoms, to the last of them, Ptolemaic Egypt, '
          'taken by Rome.',
    ),
    entry(
      'beast:fourth',
      'The fourth beast, dreadful and terrible',
      _year(-168, 6, 22),
      _year(_now),
      [_dan(7, 7), _dan(7, 19, 7, 23)],
      'Rome, with great iron teeth, devouring and breaking in pieces, '
          'and living on in the kingdoms out of it, until the judgment sits '
          'and its dominion is taken away.',
    ),
    entry(
      'beast:horns',
      'The ten horns',
      _year(476, 9, 4),
      _year(_now),
      [_dan(7, 7), _dan(7, 24)],
      'Ten kings arising out of the fourth kingdom: the kingdoms of the '
          'West that divided the empire among them.',
    ),
    entry(
      'beast:little-horn',
      'The little horn: a time, times and the dividing of time',
      _year(533),
      _year(1793, 1, 21),
      [_dan(7, 8), _dan(7, 20, 7, 21), _dan(7, 24, 7, 26)],
      'The papacy, with eyes and a mouth speaking great things, three '
          'horns plucked up before it, wearing out the saints 1,260 years: '
          'from Justinian\'s letter making the Bishop of Rome head of all '
          'the churches, to the execution of Louis XVI.',
    ),
    // The ram and the he-goat, Daniel 8.
    entry(
      'ram',
      'The ram with two horns',
      _year(-539, 10, 12),
      _year(-331, 10, 1),
      [_dan(8, 3, 8, 4), _dan(8, 20)],
      'The kings of Media and Persia, the higher horn coming up last, '
          'pushing westward, northward and southward.',
    ),
    entry(
      'goat',
      'The he-goat smites the ram',
      _year(-334, 5),
      _year(-331, 10, 1),
      [_dan(8, 5, 8, 7), _dan(8, 21)],
      'The king of Grecia, coming from the west without touching the '
          'ground: Alexander crosses into Asia, and breaks Persia at the '
          'Granicus, Issus and Gaugamela.',
    ),
    entry(
      'goat:horn-broken',
      'The great horn broken',
      _year(-323, 6, 11),
      null,
      [_dan(8, 8), _dan(8, 22)],
      'Alexander dies at Babylon, when he was strong.',
    ),
    entry(
      'goat:four-horns',
      'Four notable horns toward the four winds',
      _year(-301),
      _year(-30, 8, 1),
      [_dan(8, 8), _dan(8, 22)],
      'Four kingdoms out of the nation, not in his power: Cassander, '
          'Lysimachus, Seleucus and Ptolemy, from the battle of Ipsus, to '
          'Egypt taken by Rome.',
    ),
    entry(
      'goat:little-horn',
      'The little horn waxes exceeding great',
      _year(-148),
      _year(70, 8, 30),
      [_dan(8, 9, 8, 12), _dan(8, 23, 8, 25)],
      'Rome, rising out of the Macedonian horn when Macedonia became its '
          'province, great toward the south, the east and the pleasant '
          'land; magnifying itself against the Prince of the host, and '
          'casting down the place of his sanctuary.',
    ),
    // The seventy weeks, Daniel 9.
    entry(
      'weeks:69',
      'Seven weeks and threescore and two weeks',
      _year(-457),
      _year(27),
      [_dan(9, 24, 9, 25)],
      '483 years from the commandment to restore and build Jerusalem, in '
          'the seventh year of Artaxerxes (Ezra 7), unto Messiah the '
          'Prince.',
    ),
    entry(
      'weeks:70',
      'The seventieth week',
      _year(27),
      _year(34),
      [_dan(9, 26, 9, 27)],
      'He confirms the covenant with many for one week; in the midst of '
          'it Messiah is cut off, causing the sacrifice and oblation to '
          'cease.',
    ),
    entry(
      'sanctuary',
      'The city and the sanctuary destroyed',
      _year(70, 8, 30),
      null,
      [_dan(8, 11), _dan(9, 26), _dan(9, 27)],
      'The people of the prince that shall come, Rome under Titus, '
          'destroy the city and the sanctuary, the end with a flood, '
          'unto the end of the war desolations determined.',
    ),
    // The kings of the north and south, Daniel 11.
    entry(
      'persia-kings',
      'Three kings in Persia and a fourth far richer',
      _year(-539, 10, 12),
      _year(-480),
      [_dan(11, 2)],
      'From Cyrus to Xerxes, who by his riches stirred up all against the '
          'realm of Grecia.',
    ),
    entry(
      'north-south',
      'The kings of the north and the south',
      _year(-301),
      _year(-63),
      [_dan(11, 4, 11, 20)],
      'The mighty king\'s kingdom divided to the four winds: the wars of '
          'the Seleucid kings of Syria, the north, and the Ptolemies of '
          'Egypt, the south, over the glorious land, until Pompey made '
          'Syria a Roman province.',
    ),
    entry(
      'antiochus',
      'A vile person: Antiochus Epiphanes',
      _year(-175),
      _year(-164),
      [_dan(11, 21, 11, 30)],
      'Obtaining the kingdom by flatteries, going against Egypt until the '
          'ships of Chittim, Rome, turn him back; and his indignation '
          'against the holy covenant.',
    ),
    // The times of Daniel 12.
    entry(
      'days:1290',
      'A thousand two hundred and ninety days',
      _year(531),
      _year(1821, 3, 25),
      [_dan(12, 11)],
      '1,290 years from Justinian\'s laws setting up the abomination in '
          'the place of the daily, to the Greek revolution, when the '
          'Ottoman Euphrates began to dry up.',
    ),
  ];
}

/// The Apocalypse read through the history of the Roman world, from the
/// vision on Patmos to the gathering to Armageddon, as John Thomas reads
/// it in *Eureka*: the seals on pagan Rome, the trumpets on the empire
/// in the West and East, and the vials of the seventh trumpet, each day
/// for a year. The seventh vial, still to be poured out, is not drawn.
List<StudyTimelineEntry> get bibleApocalypse {
  final entry = _maker('apocalypse', bibleApocalypseCategory, 2000000);
  return [
    entry(
      'patmos',
      'The Apocalypse given on Patmos',
      _year(96),
      null,
      [_rev(1, 1, 1, 3), _rev(1, 9, 1, 11)],
      'John, banished to Patmos under Domitian, is shown "things which '
          'must shortly come to pass", signified to him in signs.',
    ),
    // The seals: pagan Rome.
    entry(
      'seal:1',
      'First seal: the white horse',
      _year(96),
      _year(180),
      [_rev(6, 1, 6, 2)],
      'From Nerva to the death of Marcus Aurelius: the peace and triumph '
          'of the empire under the five good emperors.',
    ),
    entry(
      'seal:2',
      'Second seal: the red horse',
      _year(193),
      _year(197),
      [_rev(6, 3, 6, 4)],
      'Peace taken from the earth: the civil wars of Severus against '
          'Niger and Albinus, ending in the battle of Lyons.',
    ),
    entry(
      'seal:3',
      'Third seal: the black horse',
      _year(212),
      _year(235),
      [_rev(6, 5, 6, 6)],
      'The balances: from Caracalla\'s edict, making every free man a '
          'citizen to be taxed, to Alexander Severus, under the jurists.',
    ),
    entry(
      'seal:4',
      'Fourth seal: the pale horse',
      _year(235),
      _year(303),
      [_rev(6, 7, 6, 8)],
      'Death and the grave, by sword, famine, pestilence and beasts: '
          'from the murder of Alexander Severus through the third '
          'century\'s anarchy and plague.',
    ),
    entry(
      'seal:5',
      'Fifth seal: the souls under the altar',
      _year(303, 2, 23),
      _year(311, 4, 30),
      [_rev(6, 9, 6, 11)],
      'The great persecution under Diocletian, to Galerius\'s edict of '
          'toleration.',
    ),
    entry(
      'seal:6',
      'Sixth seal: the great earthquake',
      _year(311),
      _year(324, 9, 18),
      [_rev(6, 12, 6, 17)],
      'The pagan heaven of the empire overthrown: Constantine\'s rise, '
          'to his defeat of Licinius at Chrysopolis.',
    ),
    entry(
      'sealing',
      'The sealing of the servants of God',
      _year(324),
      _year(395),
      [_rev(7, 1, 7, 8)],
      'The four winds held back while the servants are sealed: the '
          'empire under Constantine and his successors, to the death of '
          'Theodosius. The seventh seal opens into the trumpets.',
    ),
    // The trumpets: the empire overthrown, West and then East.
    entry(
      'trumpet:1',
      'First trumpet: hail and fire',
      _year(395),
      _year(410, 8, 24),
      [_rev(8, 7)],
      'Alaric and the Goths, from the death of Theodosius, to the sack '
          'of Rome.',
    ),
    entry(
      'trumpet:2',
      'Second trumpet: a burning mountain cast into the sea',
      _year(429),
      _year(468),
      [_rev(8, 8, 8, 9)],
      'Genseric and the Vandals, crossing to Africa, masters of the '
          'sea: Rome sacked in 455, the empire\'s fleet burnt in 468.',
    ),
    entry(
      'trumpet:3',
      'Third trumpet: the star Wormwood',
      _year(450),
      _year(453),
      [_rev(8, 10, 8, 11)],
      'Attila and the Huns, falling on the rivers of the West: Gaul '
          'invaded in 451, Italy in 452, to his death.',
    ),
    entry(
      'trumpet:4',
      'Fourth trumpet: sun, moon and stars smitten',
      _year(476, 9, 4),
      _year(554),
      [_rev(8, 12)],
      'The western empire extinguished: Odoacer deposes Romulus '
          'Augustulus, and the Gothic wars end the consuls and senate, to '
          'Justinian\'s Pragmatic Sanction.',
    ),
    entry(
      'trumpet:5',
      'Fifth trumpet: the locusts (first woe)',
      _year(632),
      _year(932),
      [_rev(9, 1, 9, 12)],
      'The Saracens, out of Arabia from the death of Mohammed: their '
          'five months, 150 years, run twice, to the breaking of the '
          'caliphate.',
    ),
    entry(
      'trumpet:6',
      'Sixth trumpet: the Euphratean horsemen (second woe)',
      _year(1062, 4, 29),
      _year(1453, 5, 29),
      [_rev(9, 13, 9, 21)],
      'The Turks loosed from the Euphrates, prepared for an hour, a day, '
          'a month and a year, 391 years and 30 days: from the Seljuks\' '
          'march westward to the capture of Constantinople.',
    ),
    entry(
      'trumpet:7',
      'Seventh trumpet (third woe)',
      _year(1790),
      _year(_now),
      [_rev(11, 15, 11, 19)],
      'Sounding from the French Revolution, its seven vials poured out '
          'in it, to the kingdoms of this world becoming the kingdom of '
          'Christ.',
    ),
    // The witnesses and the beast.
    entry(
      'witnesses',
      'The witnesses prophesy in sackcloth, the woman in the wilderness',
      _year(312),
      _year(1572),
      [_rev(11, 3, 11, 6), _rev(12, 6), _rev(12, 14)],
      '1,260 days, years: from Constantine\'s banishing of the '
          'Donatists, the faithful outside the state church, to the '
          'massacre of St Bartholomew.',
    ),
    entry(
      'bartholomew',
      'Massacre of St Bartholomew',
      _year(1572, 8, 24),
      null,
      [_rev(11, 7)],
      'The beast makes war on the witnesses: the Huguenots massacred in '
          'Paris and across France.',
    ),
    entry(
      'witnesses-dead',
      'The witnesses lie dead three days and a half',
      _year(1685, 10, 22),
      _year(1790, 7, 10),
      [_rev(11, 7, 11, 11)],
      'Killed by the revocation of the Edict of Nantes, Protestantism '
          'outlawed in France; they stand on their feet in the Revolution.',
    ),
    entry(
      'beast',
      'The beast\'s forty-two months',
      _year(533),
      _year(1793, 1, 21),
      [_rev(13, 5, 13, 7)],
      '1,260 years from Justinian\'s letter making the Bishop of Rome '
          'head of all the churches, to the execution of Louis XVI, king '
          'of the eldest son of the Church.',
    ),
    entry(
      'phocas',
      'The pope made universal bishop',
      _year(607),
      _year(1870, 9, 20),
      [_rev(13, 5, 13, 8)],
      '1,260 years from Phocas acknowledging the Bishop of Rome as head '
          'of all the churches, to the loss of the popes\' temporal power '
          'when Italy took Rome.',
    ),
    entry(
      'earthquake',
      'The great earthquake: the tenth part of the city falls',
      _year(1789, 7, 14),
      _year(1795),
      [_rev(11, 13)],
      'The French Revolution: France, a tenth of the papal kingdoms, '
          'falls from Rome, the titles of nobility slain.',
    ),
    // The vials of the seventh trumpet.
    entry(
      'vial:1',
      'First vial: a grievous sore',
      _year(1790),
      _year(1793, 1, 21),
      [_rev(16, 1, 16, 2)],
      'The Revolution in France, to the execution of the king.',
    ),
    entry(
      'vial:2',
      'Second vial: the sea as blood',
      _year(1793, 2, 1),
      _year(1815, 6, 18),
      [_rev(16, 3)],
      'The naval wars: Britain against the fleets of France and her '
          'allies, from the declaration of war to Waterloo.',
    ),
    entry(
      'vial:3',
      'Third vial: the rivers and fountains as blood',
      _year(1796, 4, 12),
      _year(1801, 2, 9),
      [_rev(16, 4, 16, 7)],
      'Napoleon\'s wars in the Alpine lands and the valleys of the Po, '
          'the Rhine and the Danube, where the Waldenses\' blood was shed: '
          'from Montenotte to the peace of Lunéville.',
    ),
    entry(
      'vial:4',
      'Fourth vial: the sun scorches men',
      _year(1805, 10),
      _year(1815, 6, 18),
      [_rev(16, 8, 16, 9)],
      'Napoleon\'s empire burning on the kings of Europe, from Ulm and '
          'Austerlitz to Waterloo.',
    ),
    entry(
      'vial:5',
      'Fifth vial: on the throne of the beast',
      _year(1808, 2, 2),
      _year(1814, 5, 24),
      [_rev(16, 10, 16, 11)],
      'Rome occupied, the Papal States annexed to France and Pius VII '
          'taken captive, until his return to Rome.',
    ),
    entry(
      'vial:6',
      'Sixth vial: the Euphrates dried up',
      _year(1821, 3, 25),
      _year(_now),
      [_rev(16, 12, 16, 16)],
      'The Ottoman power wasting away, from the Greek revolution, to '
          'prepare the way of the kings from the sunrising; and the '
          'gathering of the nations to Armageddon. The seventh vial follows '
          'at Christ\'s coming.',
    ),
    entry(
      'frogs',
      'The three unclean spirits like frogs',
      _year(1848, 2, 22),
      null,
      [_rev(16, 13, 16, 14)],
      'The revolutions of 1848, from Paris: the spirits going forth to the '
          'kings of the earth, to gather them to the battle.',
    ),
    entry(
      'jerusalem-1917',
      'Jerusalem taken from the Turks',
      _year(1917, 12, 9),
      null,
      [_rev(16, 12)],
      'Allenby takes Jerusalem: the Ottoman Euphrates dried up from the '
          'land.',
    ),
  ];
}
