import 'package:flutter/material.dart';

import '../bindings/bindings.dart';
import '../bible_data.dart';

/// The families the kinds of a sequence's events fall in, each with its
/// colour: what the chips filter by.
enum SequenceFamily {
  miracles('Miracles', Icons.auto_awesome, Color(0xFF00897B)),
  teaching(
    'Teaching and preaching',
    Icons.record_voice_over_outlined,
    Color(0xFF1E88E5),
  ),
  journeys('Journeys', Icons.directions_walk, Color(0xFFEF6C00)),
  callings('Callings', Icons.group_add_outlined, Color(0xFF5E35B1)),
  encounters('Encounters', Icons.handshake_outlined, Color(0xFFD81B60)),
  conflict('Conflict', Icons.gavel, Color(0xFFE53935)),
  revelation('Revelation', Icons.light_mode_outlined, Color(0xFFB28704)),
  feasts(
    'Feasts and observances',
    Icons.celebration_outlined,
    Color(0xFF43A047),
  ),
  births('Birth and childhood', Icons.child_care, Color(0xFF8E24AA)),
  baptisms('Baptisms', Icons.water_drop_outlined, Color(0xFF0097A7)),
  ecclesial('Ecclesial life', Icons.groups_outlined, Color(0xFF546E7A)),
  letters('Letters', Icons.mail_outline, Color(0xFF6D4C41)),
  beginnings('Creation', Icons.public, Color(0xFF00897B)),
  judgement('Judgement', Icons.gavel, Color(0xFFE53935)),
  deaths('Deaths', Icons.event_busy, Color(0xFF78909C)),
  rulers('Kings and judges', Icons.account_balance, Color(0xFF795548)),
  prophets('Prophets', Icons.campaign_outlined, Color(0xFFB28704)),
  baptist('John the Baptist', Icons.water_drop_outlined, Color(0xFF00ACC1));

  const SequenceFamily(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// Its colour as a card's ground: faint over the surface.
  Color tint(ColorScheme scheme) => Color.alphaBlend(
    color.withValues(alpha: scheme.brightness == Brightness.dark ? 0.26 : 0.14),
    scheme.surfaceContainerHigh,
  );

  /// Its colour as an icon or a mark, lightened on a dark ground.
  Color ink(ColorScheme scheme) => scheme.brightness == Brightness.dark
      ? Color.lerp(color, Colors.white, 0.3)!
      : color;
}

/// A kind of event, as the data writes it (see
/// [SequenceEventDetailsEntry.kinds]).
enum SequenceKind {
  creation('creation', 'Creation', Icons.public, SequenceFamily.beginnings),
  judgement('judgement', 'Judgement', Icons.gavel, SequenceFamily.judgement),
  death('death', 'Death', Icons.event_busy, SequenceFamily.deaths),
  reign('reign', 'Reign', Icons.account_balance, SequenceFamily.rulers),
  judgeship('judgeship', 'Judgeship', Icons.gavel, SequenceFamily.rulers),
  prophecy(
    'prophecy',
    'Prophecy',
    Icons.campaign_outlined,
    SequenceFamily.prophets,
  ),
  preaching(
    'preaching',
    'Preaching',
    Icons.campaign_outlined,
    SequenceFamily.teaching,
  ),
  testimony(
    'testimony',
    'Testimony',
    Icons.record_voice_over_outlined,
    SequenceFamily.teaching,
  ),
  baptism(
    'baptism',
    'Baptism',
    Icons.water_drop_outlined,
    SequenceFamily.baptisms,
  ),
  ecclesia(
    'ecclesia',
    'Ecclesial life',
    Icons.groups_outlined,
    SequenceFamily.ecclesial,
  ),
  birth('birth', 'Birth', Icons.child_care, SequenceFamily.births),
  childhood('childhood', 'Childhood', Icons.child_care, SequenceFamily.births),
  covenant(
    'covenant',
    'Covenant observance',
    Icons.event_outlined,
    SequenceFamily.feasts,
  ),
  letter('letter', 'Letter', Icons.mail_outline, SequenceFamily.letters),
  healing('healing', 'Healing', Icons.healing, SequenceFamily.miracles),
  exorcism('exorcism', 'Casting out', Icons.bolt, SequenceFamily.miracles),
  raising(
    'raising',
    'Raising the dead',
    Icons.wb_twilight,
    SequenceFamily.miracles,
  ),
  sign('sign', 'Sign', Icons.auto_awesome, SequenceFamily.miracles),
  teaching(
    'teaching',
    'Teaching',
    Icons.record_voice_over_outlined,
    SequenceFamily.teaching,
  ),
  parable('parable', 'Parable', Icons.spa_outlined, SequenceFamily.teaching),
  journey('journey', 'Journey', Icons.directions_walk, SequenceFamily.journeys),
  calling(
    'calling',
    'Calling',
    Icons.group_add_outlined,
    SequenceFamily.callings,
  ),
  encounter(
    'encounter',
    'Encounter',
    Icons.handshake_outlined,
    SequenceFamily.encounters,
  ),
  conflict('conflict', 'Conflict', Icons.gavel, SequenceFamily.conflict),
  revelation(
    'revelation',
    'Revelation',
    Icons.light_mode_outlined,
    SequenceFamily.revelation,
  ),
  feast('feast', 'Feast', Icons.celebration_outlined, SequenceFamily.feasts),
  baptist(
    'john-baptist',
    'John the Baptist',
    Icons.water_drop_outlined,
    SequenceFamily.baptist,
  );

  const SequenceKind(this.key, this.label, this.icon, this.family);

  final String key;
  final String label;
  final IconData icon;
  final SequenceFamily family;

  static SequenceKind? byKey(String key) =>
      values.where((k) => k.key == key).firstOrNull;
}

/// The regions a sequence's events happen in, as the data writes them, in
/// the order their lanes are drawn: roughly north to south.
const sequenceRegions = <String, String>{
  'north': 'Phoenicia and the north',
  'galilee': 'Galilee',
  'east': 'East of the lake',
  'samaria': 'Samaria',
  'perea': 'Perea',
  'judea': 'Judea',
  'egypt': 'Egypt',
  'syria': 'Syria',
  'cyprus': 'Cyprus',
  'asia-minor': 'Asia Minor',
  'macedonia': 'Macedonia',
  'achaia': 'Achaia',
  'malta': 'Malta',
  'italy': 'Italy',
};

/// The lane of [region], in [sequenceRegions]' order; null for none.
int? regionLane(String region) {
  final i = sequenceRegions.keys.toList().indexOf(region);
  return i < 0 ? null : i;
}

/// The Gospels, by book (counted from 1), with the letters a card shows.
const gospels = <int, String>{40: 'Mt', 41: 'Mk', 42: 'Lk', 43: 'Jn'};

/// The Gospels telling [event], in order, by book.
Set<int> gospelsOf(BibleEventEntry? event) => {
  for (final p in event?.passages ?? const <ThematicTarget>[])
    if (gospels.containsKey(p.book)) p.book,
};

/// The kinds of [details], known ones only, the chief first.
List<SequenceKind> kindsOf(SequenceEventDetailsEntry? details) => [
  for (final k in details?.kinds ?? const <String>[]) ?SequenceKind.byKey(k),
];

/// The Gospels' letters, those telling it strong and the others faint.
class GospelMarks extends StatelessWidget {
  const GospelMarks({super.key, required this.books, required this.color});

  final Set<int> books;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final MapEntry(key: book, value: letters) in gospels.entries)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              letters,
              semanticsLabel: books.contains(book) ? letters : '',
              style: style?.copyWith(
                fontSize: 10,
                height: 1,
                fontWeight: books.contains(book)
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: color.withValues(
                  alpha: books.contains(book) ? 0.95 : 0.25,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Gospel witnesses keep their comparison marks; other accounts show only
/// the books actually attached to the event, such as Acts or Galatians.
class SequenceSourceMarks extends StatelessWidget {
  const SequenceSourceMarks({
    super.key,
    required this.event,
    required this.color,
  });

  final BibleEventEntry? event;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final books = {
      for (final p in event?.passages ?? const <ThematicTarget>[]) p.book,
    };
    final gospelBooks = books.where(gospels.containsKey).toSet();
    final otherBooks =
        books
            .where(
              (b) =>
                  !gospels.containsKey(b) &&
                  b > 0 &&
                  b <= kEnglishBookAbbreviations.length,
            )
            .toList()
          ..sort();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (gospelBooks.isNotEmpty)
          GospelMarks(books: gospelBooks, color: color),
        for (final book in otherBooks)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              kEnglishBookAbbreviations[book - 1],
              semanticsLabel: kEnglishBookNames[book - 1],
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
      ],
    );
  }
}
