import 'package:flutter/material.dart';

import '../external_link.dart';

/// Douglas Petrovich's reconstruction of the earliest alphabet: for each of
/// the 22 Hebrew letters, the Egyptian hieroglyph he takes as its exemplar,
/// the Hebrew word whose first sound it gave (acrophony), and the letter's
/// Iron Age form. The data follows his chart *Hebrew Consonantals* (© 2015),
/// as set out in haqor-core's `doc/lexicon/alphabet-origin.md`.
class EarlyAlphabetPage extends StatelessWidget {
  const EarlyAlphabetPage({super.key});

  static final Uri chartUri = Uri.parse(
    'https://www.ancient-hebrew.org/alphabet/files/'
    'hebrew-alphabet-evolution-petrovich-chart.pdf',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    Widget heading(String s) =>
        Text(s, style: text.headlineSmall?.copyWith(fontFamily: 'Cardo'));
    Widget para(String s) => Text(s, style: _mixed(text.bodyLarge));
    return Scaffold(
      appBar: AppBar(title: const Text('The earliest alphabet')),
      body: SelectionArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
              children: [
                Text(
                  'REFERENCE · DOUGLAS PETROVICH',
                  style: text.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hebrew’s first letters',
                  style: text.headlineMedium?.copyWith(fontFamily: 'Cardo'),
                ),
                const SizedBox(height: 12),
                para(
                  'The earliest alphabetic inscriptions, from the turquoise '
                  'mines of Serabit el-Khadim in Sinai and from Wadi el-Hol in '
                  'Egypt, were written by Semitic speakers who knew Egyptian '
                  'hieroglyphs. They took a picture, many of them modelled on '
                  'a hieroglyph, and gave it the first sound of their own word '
                  'for the thing pictured. This is acrophony: an ox head, '
                  'ʾelef, writes ʾ.',
                ),
                const SizedBox(height: 8),
                para(
                  'Douglas Petrovich (The World’s Oldest Alphabet, 2016) '
                  'reads that language as Hebrew, written by Hebrews in '
                  'Egypt from about 1842 BC, in the reign of Amenemhat III. '
                  'He counts 22 letters from the start, and matches each to a '
                  'Middle Egyptian hieroglyph and a Hebrew word.',
                ),
                const SizedBox(height: 24),
                heading('The letters'),
                const SizedBox(height: 4),
                Text(
                  'Hieroglyph (Gardiner number) → Iron Age form → square '
                  'letter, with the Hebrew word it was named from.',
                  style: text.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final l in petrovichLetters) _LetterCard(letter: l),
                const SizedBox(height: 24),
                heading('Notes'),
                const SizedBox(height: 8),
                para(
                  'ח and ס each have two exemplars, and their acrophones begin '
                  'with two different older sounds: חָצֵר “enclosure” has ḥ, '
                  'חוּט “thread” has ḫ; שֵׂעָר “hair” has ś, סָרַח “stink” has '
                  's. The first writers seem to have had a sign for each sound '
                  'of a pair that the 22 letters later write with one (see '
                  'Semitic sounds).',
                ),
                const SizedBox(height: 8),
                para(
                  'Some acrophones come from what the Egyptian sign meant, not '
                  'what it pictured: F35 is the Egyptian nfr “good”, and ט is '
                  'טוֹב “good”.',
                ),
                const SizedBox(height: 8),
                para(
                  'His chart draws no Middle Kingdom form for ט, צ or ש: their '
                  'earliest forms are from the New Kingdom. The hieroglyphs '
                  'here are the standard sign forms, not the drawn letters of '
                  'the inscriptions; the Iron Age forms are the Phoenician '
                  'letters.',
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text(
                      'Petrovich’s chart, with the letters as drawn in each '
                      'period',
                    ),
                    onPressed: () => openExternalLink(chartUri),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One Egyptian sign Petrovich takes as a letter's exemplar.
class PetrovichSign {
  const PetrovichSign(this.glyph, this.gardiner, this.description);

  final String glyph;
  final String gardiner;
  final String description;
}

/// One Hebrew word whose first sound names the letter.
class PetrovichAcrophone {
  const PetrovichAcrophone(this.hebrew, this.translit, this.meaning);

  final String hebrew;
  final String translit;
  final String meaning;
}

class PetrovichLetter {
  const PetrovichLetter({
    required this.letter,
    required this.name,
    required this.ironAge,
    required this.signs,
    required this.acrophones,
  });

  final String letter;
  final String name;

  /// The Phoenician letter, standing for the Iron Age form.
  final String ironAge;
  final List<PetrovichSign> signs;
  final List<PetrovichAcrophone> acrophones;
}

/// The 22 letters, in order. Exemplars, Gardiner numbers and acrophones are
/// Petrovich's; the sign descriptions are added.
const List<PetrovichLetter> petrovichLetters = [
  PetrovichLetter(
    letter: 'א',
    name: 'Alef',
    ironAge: '𐤀',
    signs: [PetrovichSign('𓃾', 'F1', 'ox head')],
    acrophones: [PetrovichAcrophone('אֶלֶף', 'ʾelef', 'cattle')],
  ),
  PetrovichLetter(
    letter: 'ב',
    name: 'Bet',
    ironAge: '𐤁',
    signs: [
      PetrovichSign('𓉐', 'O1', 'house plan'),
      PetrovichSign('𓉔', 'O4', 'reed shelter'),
    ],
    acrophones: [PetrovichAcrophone('בַּיִת', 'bayit', 'house')],
  ),
  PetrovichLetter(
    letter: 'ג',
    name: 'Gimel',
    ironAge: '𐤂',
    signs: [PetrovichSign('𓊋', 'O38', 'corner of a wall')],
    acrophones: [PetrovichAcrophone('גָּהַר', 'gāhar', 'bend')],
  ),
  PetrovichLetter(
    letter: 'ד',
    name: 'Dalet',
    ironAge: '𐤃',
    signs: [PetrovichSign('𓉿', 'O31', 'door')],
    acrophones: [PetrovichAcrophone('דֶּלֶת', 'delet', 'door')],
  ),
  PetrovichLetter(
    letter: 'ה',
    name: 'He',
    ironAge: '𐤄',
    signs: [PetrovichSign('𓀠', 'A28', 'man with raised arms')],
    acrophones: [PetrovichAcrophone('הָלַל', 'hālal', 'praise')],
  ),
  PetrovichLetter(
    letter: 'ו',
    name: 'Vav',
    ironAge: '𐤅',
    signs: [PetrovichSign('𓉽', 'O30', 'support pole')],
    acrophones: [PetrovichAcrophone('וָו', 'wāw', 'pillar, support')],
  ),
  PetrovichLetter(
    letter: 'ז',
    name: 'Zayin',
    ironAge: '𐤆',
    signs: [PetrovichSign('𓂃', 'D13', 'eyebrow')],
    acrophones: [PetrovichAcrophone('זֵעָה', 'zēʿāh', 'sweat (of the brows)')],
  ),
  PetrovichLetter(
    letter: 'ח',
    name: 'Het',
    ironAge: '𐤇',
    signs: [
      PetrovichSign('𓉗', 'O6', 'enclosure'),
      PetrovichSign('𓎛', 'V28', 'twisted wick'),
    ],
    acrophones: [
      PetrovichAcrophone('חָצֵר', 'ḥāṣēr', 'enclosure'),
      PetrovichAcrophone('חוּט', 'ḥûṭ', 'thread'),
    ],
  ),
  PetrovichLetter(
    letter: 'ט',
    name: 'Tet',
    ironAge: '𐤈',
    signs: [PetrovichSign('𓄤', 'F35', 'heart and windpipe')],
    acrophones: [PetrovichAcrophone('טוֹב', 'ṭôv', 'good')],
  ),
  PetrovichLetter(
    letter: 'י',
    name: 'Yod',
    ironAge: '𐤉',
    signs: [
      PetrovichSign('𓂝', 'D36', 'arm'),
      PetrovichSign('𓂩', 'D47', 'hand'),
    ],
    acrophones: [PetrovichAcrophone('יָד', 'yād', 'hand')],
  ),
  PetrovichLetter(
    letter: 'כ',
    name: 'Kaf',
    ironAge: '𐤊',
    signs: [PetrovichSign('𓂓', 'D28', 'raised arms')],
    acrophones: [PetrovichAcrophone('כַּף', 'kap', 'palm')],
  ),
  PetrovichLetter(
    letter: 'ל',
    name: 'Lamed',
    ironAge: '𐤋',
    signs: [PetrovichSign('𓋿', 'S39', 'crook')],
    acrophones: [PetrovichAcrophone('לָמַד', 'lāmad', 'teach')],
  ),
  PetrovichLetter(
    letter: 'מ',
    name: 'Mem',
    ironAge: '𐤌',
    signs: [PetrovichSign('𓈖', 'N35', 'water ripple')],
    acrophones: [PetrovichAcrophone('מַיִם', 'mayim', 'water')],
  ),
  PetrovichLetter(
    letter: 'נ',
    name: 'Nun',
    ironAge: '𐤍',
    signs: [
      PetrovichSign('𓆑', 'I9', 'horned viper'),
      PetrovichSign('𓆓', 'I10', 'cobra'),
    ],
    acrophones: [PetrovichAcrophone('נָחָשׁ', 'nāḥāš', 'snake')],
  ),
  PetrovichLetter(
    letter: 'ס',
    name: 'Samekh',
    ironAge: '𐤎',
    signs: [
      PetrovichSign('𓁸', 'D3', 'hair'),
      PetrovichSign('𓆟', 'K5', 'fish'),
    ],
    acrophones: [
      PetrovichAcrophone('שֵׂעָר', 'śēʿār', 'hair'),
      PetrovichAcrophone('סָרַח', 'sāraḥ', 'stink'),
    ],
  ),
  PetrovichLetter(
    letter: 'ע',
    name: 'Ayin',
    ironAge: '𐤏',
    signs: [PetrovichSign('𓁹', 'D4', 'eye')],
    acrophones: [PetrovichAcrophone('עַיִן', 'ʿayin', 'eye')],
  ),
  PetrovichLetter(
    letter: 'פ',
    name: 'Pe',
    ironAge: '𐤐',
    signs: [PetrovichSign('𓂋', 'D21', 'mouth')],
    acrophones: [PetrovichAcrophone('פֶּה', 'peh', 'mouth')],
  ),
  PetrovichLetter(
    letter: 'צ',
    name: 'Tsade',
    ironAge: '𐤑',
    signs: [PetrovichSign('𓎤', 'V33', 'linen bag')],
    acrophones: [PetrovichAcrophone('צְרוֹר', 'ṣǝrôr', 'sack')],
  ),
  PetrovichLetter(
    letter: 'ק',
    name: 'Qof',
    ironAge: '𐤒',
    signs: [PetrovichSign('𓎘', 'V25', 'cord wound on a stick')],
    acrophones: [PetrovichAcrophone('קוּר', 'qûr', 'spun fibre')],
  ),
  PetrovichLetter(
    letter: 'ר',
    name: 'Resh',
    ironAge: '𐤓',
    signs: [PetrovichSign('𓁶', 'D1', 'head')],
    acrophones: [PetrovichAcrophone('רֹאשׁ', 'roʾš', 'head')],
  ),
  PetrovichLetter(
    letter: 'ש',
    name: 'Shin',
    ironAge: '𐤔',
    signs: [PetrovichSign('𓂑', 'D27', 'breasts')],
    acrophones: [PetrovichAcrophone('שָׁדַיִם', 'šādayim', 'breasts')],
  ),
  PetrovichLetter(
    letter: 'ת',
    name: 'Tav',
    ironAge: '𐤕',
    signs: [PetrovichSign('𓇬', 'M42', 'flower')],
    acrophones: [PetrovichAcrophone('תַּיִשׁ', 'tayiš', 'male goat')],
  ),
];

const String _hieroglyphFont = 'Noto Sans Egyptian Hieroglyphs';
const String _phoenicianFont = 'Noto Sans Phoenician';

TextStyle? _mixed(TextStyle? style) =>
    style?.copyWith(fontFamilyFallback: const ['Noto Serif Hebrew', 'Cardo']);

class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.letter});

  final PetrovichLetter letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final arrow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(Icons.arrow_forward, size: 16, color: muted),
    );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left to right, as the sign developed: hieroglyph, Iron Age,
            // square letter.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                for (final (i, s) in letter.signs.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('or', style: text.bodySmall),
                    ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.glyph,
                        style: const TextStyle(
                          fontFamily: _hieroglyphFont,
                          fontSize: 34,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        s.gardiner,
                        style: text.labelSmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ],
                arrow,
                Text(
                  letter.ironAge,
                  style: const TextStyle(
                    fontFamily: _phoenicianFont,
                    fontSize: 30,
                    height: 1.2,
                  ),
                ),
                arrow,
                Text(
                  letter.letter,
                  style: const TextStyle(
                    fontFamily: 'Cardo',
                    fontFamilyFallback: ['Noto Serif Hebrew'],
                    fontSize: 34,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                Text(letter.name, style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              letter.signs
                  .map((s) => '${s.description} (${s.gardiner})')
                  .join('; '),
              style: text.bodyMedium?.copyWith(color: muted),
            ),
            for (final a in letter.acrophones)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: a.hebrew,
                      style: const TextStyle(fontSize: 20),
                    ),
                    TextSpan(
                      text: '  ${a.translit}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                    TextSpan(text: ' “${a.meaning}”'),
                  ],
                ),
                style: _mixed(text.bodyLarge?.copyWith(fontFamily: 'Cardo')),
              ),
          ],
        ),
      ),
    );
  }
}
