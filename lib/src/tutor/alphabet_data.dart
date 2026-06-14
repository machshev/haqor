/// Static reference data for the alphabet tutor.
///
/// Pronunciations follow modern Israeli convention, with classical
/// (biblical) values noted where they differ — consistent with the app's
/// focus on the Hebrew Bible.
class HebrewLetter {
  final String letter; // bare consonant
  final String? finalForm; // sofit form, if any
  final String name; // English name
  final String hebrewName; // pointed Hebrew name
  final String translit; // romanization of the consonant
  final String sound; // pronunciation guide
  final int value; // numeric (gematria) value
  final String example; // pointed example word
  final String exampleTranslit;
  final String exampleMeaning;
  final String? tip; // mnemonic / look-alike warning

  const HebrewLetter({
    required this.letter,
    this.finalForm,
    required this.name,
    required this.hebrewName,
    required this.translit,
    required this.sound,
    required this.value,
    required this.example,
    required this.exampleTranslit,
    required this.exampleMeaning,
    this.tip,
  });
}

/// A letter or word is considered mastered after this many net-correct quiz
/// answers.
const int kMasteryTarget = 3;

/// Alphabet index for every letter glyph, including final forms.
final Map<String, int> kLetterIndex = {
  for (var i = 0; i < kAlphabet.length; i++) ...{
    kAlphabet[i].letter: i,
    if (kAlphabet[i].finalForm != null) kAlphabet[i].finalForm!: i,
  },
};

const List<HebrewLetter> kAlphabet = [
  HebrewLetter(
    letter: 'א',
    name: 'Alef',
    hebrewName: 'אָלֶף',
    translit: 'ʾ',
    sound: 'silent — a glottal stop, like the catch in “uh-oh”',
    value: 1,
    example: 'אָב',
    exampleTranslit: 'av',
    exampleMeaning: 'father',
    tip:
        'Alef makes no sound of its own; it carries whatever vowel is '
        'written with it.',
  ),
  HebrewLetter(
    letter: 'ב',
    name: 'Bet',
    hebrewName: 'בֵּית',
    translit: 'b / v',
    sound: 'b as in boy (בּ with dagesh); v as in vine (ב without)',
    value: 2,
    example: 'בַּיִת',
    exampleTranslit: 'bayit',
    exampleMeaning: 'house',
    tip:
        'Don’t confuse with Kaf (כ): Bet has a square corner and a small '
        'heel at the bottom right.',
  ),
  HebrewLetter(
    letter: 'ג',
    name: 'Gimel',
    hebrewName: 'גִּימֶל',
    translit: 'g',
    sound: 'g as in girl',
    value: 3,
    example: 'גָּמָל',
    exampleTranslit: 'gamal',
    exampleMeaning: 'camel',
  ),
  HebrewLetter(
    letter: 'ד',
    name: 'Dalet',
    hebrewName: 'דָּלֶת',
    translit: 'd',
    sound: 'd as in door',
    value: 4,
    example: 'דֶּלֶת',
    exampleTranslit: 'delet',
    exampleMeaning: 'door',
    tip:
        'Don’t confuse with Resh (ר): Dalet has a sharp corner, Resh is '
        'rounded.',
  ),
  HebrewLetter(
    letter: 'ה',
    name: 'He',
    hebrewName: 'הֵא',
    translit: 'h',
    sound: 'h as in hay',
    value: 5,
    example: 'הַר',
    exampleTranslit: 'har',
    exampleMeaning: 'mountain',
    tip:
        'The left leg doesn’t touch the roof — compare Het (ח), which is '
        'fully closed.',
  ),
  HebrewLetter(
    letter: 'ו',
    name: 'Vav',
    hebrewName: 'וָו',
    translit: 'v / w',
    sound: 'v as in vine (classically w as in way)',
    value: 6,
    example: 'וָו',
    exampleTranslit: 'vav',
    exampleMeaning: 'hook',
    tip: 'Also serves as a vowel letter: וֹ is ō and וּ is ū.',
  ),
  HebrewLetter(
    letter: 'ז',
    name: 'Zayin',
    hebrewName: 'זַיִן',
    translit: 'z',
    sound: 'z as in zebra',
    value: 7,
    example: 'זָהָב',
    exampleTranslit: 'zahav',
    exampleMeaning: 'gold',
    tip: 'Like Vav (ו) but the head juts out on both sides of the stem.',
  ),
  HebrewLetter(
    letter: 'ח',
    name: 'Het',
    hebrewName: 'חֵית',
    translit: 'ḥ',
    sound: 'ch as in Bach — a rough sound from the throat',
    value: 8,
    example: 'חַי',
    exampleTranslit: 'chai',
    exampleMeaning: 'alive, living',
    tip: 'Fully closed at the top — compare He (ה), which has a gap.',
  ),
  HebrewLetter(
    letter: 'ט',
    name: 'Tet',
    hebrewName: 'טֵית',
    translit: 'ṭ',
    sound: 't as in tin',
    value: 9,
    example: 'טוֹב',
    exampleTranslit: 'tov',
    exampleMeaning: 'good',
  ),
  HebrewLetter(
    letter: 'י',
    name: 'Yod',
    hebrewName: 'יוֹד',
    translit: 'y',
    sound: 'y as in yes',
    value: 10,
    example: 'יָד',
    exampleTranslit: 'yad',
    exampleMeaning: 'hand',
    tip:
        'The smallest letter — it floats near the top of the line. Also '
        'serves as a vowel letter for ī.',
  ),
  HebrewLetter(
    letter: 'כ',
    finalForm: 'ך',
    name: 'Kaf',
    hebrewName: 'כַּף',
    translit: 'k / kh',
    sound: 'k as in king (כּ with dagesh); ch as in Bach (כ without)',
    value: 20,
    example: 'כֶּלֶב',
    exampleTranslit: 'kelev',
    exampleMeaning: 'dog',
    tip:
        'Rounded corners — compare Bet (ב). At the end of a word it '
        'becomes ך, dropping below the line.',
  ),
  HebrewLetter(
    letter: 'ל',
    name: 'Lamed',
    hebrewName: 'לָמֶד',
    translit: 'l',
    sound: 'l as in look',
    value: 30,
    example: 'לֵב',
    exampleTranslit: 'lev',
    exampleMeaning: 'heart',
    tip: 'The only letter that rises above the top line — easy to spot.',
  ),
  HebrewLetter(
    letter: 'מ',
    finalForm: 'ם',
    name: 'Mem',
    hebrewName: 'מֵם',
    translit: 'm',
    sound: 'm as in mother',
    value: 40,
    example: 'מַיִם',
    exampleTranslit: 'mayim',
    exampleMeaning: 'water',
    tip:
        'The final form ם is closed on all sides — compare Samekh (ס), '
        'which is round.',
  ),
  HebrewLetter(
    letter: 'נ',
    finalForm: 'ן',
    name: 'Nun',
    hebrewName: 'נוּן',
    translit: 'n',
    sound: 'n as in now',
    value: 50,
    example: 'נָהָר',
    exampleTranslit: 'nahar',
    exampleMeaning: 'river',
    tip:
        'The final form ן is a straight stroke dropping below the line — '
        'compare Vav (ו), which sits on it.',
  ),
  HebrewLetter(
    letter: 'ס',
    name: 'Samekh',
    hebrewName: 'סָמֶךְ',
    translit: 's',
    sound: 's as in sun',
    value: 60,
    example: 'סוּס',
    exampleTranslit: 'sus',
    exampleMeaning: 'horse',
    tip: 'Fully round — compare final Mem (ם), which is squared off.',
  ),
  HebrewLetter(
    letter: 'ע',
    name: 'Ayin',
    hebrewName: 'עַיִן',
    translit: 'ʿ',
    sound:
        'silent today; classically a deep sound from the back of the '
        'throat',
    value: 70,
    example: 'עַיִן',
    exampleTranslit: 'ayin',
    exampleMeaning: 'eye',
  ),
  HebrewLetter(
    letter: 'פ',
    finalForm: 'ף',
    name: 'Pe',
    hebrewName: 'פֵּא',
    translit: 'p / f',
    sound: 'p as in pay (פּ with dagesh); f as in fish (פ without)',
    value: 80,
    example: 'פֶּה',
    exampleTranslit: 'peh',
    exampleMeaning: 'mouth',
  ),
  HebrewLetter(
    letter: 'צ',
    finalForm: 'ץ',
    name: 'Tsadi',
    hebrewName: 'צָדִי',
    translit: 'ts',
    sound: 'ts as in cats',
    value: 90,
    example: 'צַדִּיק',
    exampleTranslit: 'tsaddik',
    exampleMeaning: 'righteous',
  ),
  HebrewLetter(
    letter: 'ק',
    name: 'Qof',
    hebrewName: 'קוֹף',
    translit: 'q',
    sound: 'k as in king, classically from further back in the throat',
    value: 100,
    example: 'קוֹל',
    exampleTranslit: 'qol',
    exampleMeaning: 'voice',
    tip: 'Its tail drops below the line.',
  ),
  HebrewLetter(
    letter: 'ר',
    name: 'Resh',
    hebrewName: 'רֵישׁ',
    translit: 'r',
    sound: 'r as in run (rolled or guttural)',
    value: 200,
    example: 'רֹאשׁ',
    exampleTranslit: 'rosh',
    exampleMeaning: 'head',
    tip: 'Rounded corner — compare Dalet (ד), which is sharp.',
  ),
  HebrewLetter(
    letter: 'ש',
    name: 'Shin',
    hebrewName: 'שִׁין',
    translit: 'sh / ś',
    sound:
        'sh as in ship (שׁ, dot on the right); s as in sun (שׂ, dot on '
        'the left)',
    value: 300,
    example: 'שָׁלוֹם',
    exampleTranslit: 'shalom',
    exampleMeaning: 'peace',
  ),
  HebrewLetter(
    letter: 'ת',
    name: 'Tav',
    hebrewName: 'תָּו',
    translit: 't',
    sound: 't as in tin',
    value: 400,
    example: 'תּוֹרָה',
    exampleTranslit: 'torah',
    exampleMeaning: 'instruction, law',
    tip: 'Compare Het (ח): Tav has a small foot on its left leg.',
  ),
];
