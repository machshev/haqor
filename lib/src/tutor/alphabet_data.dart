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
  final String translit; // scholarly romanization (macron for long vowels: ā ē ō)
  // Friendlier respelling for quiz syllables, where a macron reads as
  // unfamiliar; only set where it differs from [translit] (long vowels).
  // Callers should fall back to [translit] when this is null.
  final String? vocalisation;
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
    this.vocalisation,
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

/// The niqqud (vowel points and reading dots). Like consonants these are taught
/// lazily by the SRS tutor as words introduce them. They are combining marks,
/// so [HebrewLetter.letter] holds the bare mark; render it on a dotted circle
/// (U+25CC) to show it in isolation. `value` is 0 (points have no gematria).
const List<HebrewLetter> kNiqqud = [
  HebrewLetter(
    letter: 'ַ', // PATAH
    name: 'Patah',
    hebrewName: 'פַּתַח',
    translit: 'a',
    sound: 'a as in father — a short “ah”',
    value: 0,
    example: 'יַד',
    exampleTranslit: 'yad',
    exampleMeaning: 'hand',
    tip: 'A single horizontal stroke under the letter.',
  ),
  HebrewLetter(
    letter: 'ָ', // QAMATS
    name: 'Qamats',
    hebrewName: 'קָמַץ',
    translit: 'ā',
    vocalisation: 'ah',
    sound: 'a as in father (classically a longer “ah”)',
    value: 0,
    example: 'יָד',
    exampleTranslit: 'yad',
    exampleMeaning: 'hand',
    tip: 'Like Patah but with a small tail hanging down from the middle.',
  ),
  HebrewLetter(
    letter: 'ֶ', // SEGOL
    name: 'Segol',
    hebrewName: 'סֶגוֹל',
    translit: 'e',
    sound: 'e as in bed',
    value: 0,
    example: 'אֶרֶץ',
    exampleTranslit: 'erets',
    exampleMeaning: 'land',
    tip: 'Three dots in a downward triangle.',
  ),
  HebrewLetter(
    letter: 'ֵ', // TSERE
    name: 'Tsere',
    hebrewName: 'צֵירֵי',
    translit: 'ē',
    vocalisation: 'ey',
    sound: 'e as in they',
    value: 0,
    example: 'שֵׁם',
    exampleTranslit: 'shem',
    exampleMeaning: 'name',
    tip: 'Two dots side by side under the letter.',
  ),
  HebrewLetter(
    letter: 'ִ', // HIRIQ
    name: 'Hiriq',
    hebrewName: 'חִירִיק',
    translit: 'i',
    sound: 'i as in machine',
    value: 0,
    example: 'מִן',
    exampleTranslit: 'min',
    exampleMeaning: 'from',
    tip: 'A single dot under the letter.',
  ),
  HebrewLetter(
    letter: 'ֹ', // HOLAM
    name: 'Holam',
    hebrewName: 'חוֹלָם',
    translit: 'ō',
    vocalisation: 'oh',
    sound: 'o as in bone',
    value: 0,
    example: 'לֹא',
    exampleTranslit: 'lo',
    exampleMeaning: 'not',
    tip: 'A single dot above and to the left of the letter.',
  ),
  HebrewLetter(
    letter: 'ֻ', // QUBUTS
    name: 'Qubuts',
    hebrewName: 'קֻבּוּץ',
    translit: 'u',
    sound: 'u as in flute',
    value: 0,
    example: 'שֻׁלְחָן',
    exampleTranslit: 'shulchan',
    exampleMeaning: 'table',
    tip: 'Three diagonal dots under the letter.',
  ),
  HebrewLetter(
    // Not a combining mark: a vav carrying a dagesh with no vowel of its own is
    // the shureq vowel. The engine teaches it as its own atomic glyph (like בּ),
    // so it renders standalone — [isNiqqud] is false for it, no carrier circle.
    letter: 'וּ', // VAV + DAGESH (shureq)
    name: 'Shureq',
    hebrewName: 'שׁוּרֶק',
    translit: 'û',
    vocalisation: 'oo',
    sound: 'u as in flute — a vav with a dot in its middle, read as a vowel',
    value: 0,
    example: 'סוּס',
    exampleTranslit: 'sus',
    exampleMeaning: 'horse',
    tip:
        'Not the consonant Vav: the dot makes the letter itself the vowel '
        '“oo”. Compare Qubuts (three dots under a letter), the same sound.',
  ),
  HebrewLetter(
    letter: 'ְ', // SHEVA
    name: 'Sheva',
    hebrewName: 'שְׁוָא',
    translit: 'ᵉ', // vocal sheva, shown as a superscript e (bᵉ)
    sound: 'a faint “uh”, or silent (closing a syllable)',
    value: 0,
    example: 'שְׁמַע',
    exampleTranslit: 'shma',
    exampleMeaning: 'hear!',
    tip: 'Two vertical dots under the letter.',
  ),
  HebrewLetter(
    letter: 'ֱ', // HATAF SEGOL
    name: 'Hataf Segol',
    hebrewName: 'חֲטַף סֶגוֹל',
    translit: 'ᵉ', // hataf segol — reduced e (superscript)
    sound: 'a very short “e” — Segol hurried under a throaty letter',
    value: 0,
    example: 'אֱמֶת',
    exampleTranslit: 'emet',
    exampleMeaning: 'truth',
    tip: 'Segol joined to a Sheva — found under א ה ח ע.',
  ),
  HebrewLetter(
    letter: 'ֲ', // HATAF PATAH
    name: 'Hataf Patah',
    hebrewName: 'חֲטַף פַּתַח',
    translit: 'ᵃ', // hataf patah — reduced a (superscript)
    sound: 'a very short “a” — Patah hurried under a throaty letter',
    value: 0,
    example: 'אֲנִי',
    exampleTranslit: 'ani',
    exampleMeaning: 'I',
    tip: 'Patah joined to a Sheva — found under א ה ח ע.',
  ),
  HebrewLetter(
    letter: 'ֳ', // HATAF QAMATS
    name: 'Hataf Qamats',
    hebrewName: 'חֲטַף קָמַץ',
    translit: 'ᵒ', // hataf qamats — reduced o (superscript)
    sound: 'a very short “o” — Qamats hurried under a throaty letter',
    value: 0,
    example: 'אֳנִי',
    exampleTranslit: 'oni',
    exampleMeaning: 'fleet, ships',
    tip: 'Qamats joined to a Sheva — found under א ה ח ע.',
  ),
  HebrewLetter(
    letter: 'ׇ', // QAMATS QATAN
    name: 'Qamats Qatan',
    hebrewName: 'קָמַץ קָטָן',
    translit: 'o',
    sound: 'o as in soft — looks like Qamats but read as a short “o”',
    value: 0,
    example: 'כָּל',
    exampleTranslit: 'kol',
    exampleMeaning: 'all, every',
    tip: 'Identical in shape to Qamats; context tells you it is “o”.',
  ),
];

/// The reading marks that punctuate verses (taught lazily as the learner first
/// reaches a verse containing them): the sof pasuq (verse-ending full stop) and
/// the maqaf (joins short words). Unlike niqqud these are spacing characters, so
/// they render on their own without a carrier circle.
const List<HebrewLetter> kReadingMarks = [
  HebrewLetter(
    letter: '׃', // SOF PASUQ
    name: 'Sof Pasuq',
    hebrewName: 'סוֹף פָּסוּק',
    translit: ':',
    sound: 'two stacked dots that mark the end of a verse — a full stop',
    value: 0,
    example: 'הָאָרֶץ׃',
    exampleTranslit: '…ha’arets ׃',
    exampleMeaning: '“…the earth.” — the verse ends here',
    tip: 'Every verse in the Bible closes with this mark.',
  ),
  HebrewLetter(
    letter: '־', // MAQAF
    name: 'Maqaf',
    hebrewName: 'מַקָּף',
    translit: '-',
    sound: 'a high hyphen joining short words into a single reading unit',
    value: 0,
    example: 'כָּל־הָאָרֶץ',
    exampleTranslit: 'kol-ha’arets',
    exampleMeaning: 'all the earth',
    tip: 'The joined words share one accent and are read together.',
  ),
];

/// Teaching content for any single tutor glyph — a consonant (keyed by its
/// medial form or, for the five sofit letters, its final form, since the
/// engine now teaches final forms as their own distinct glyphs; for
/// bet/pe/shin, keyed by the letter plus its dagesh/shin-sin-dot, since that
/// mark changes the letter's sound: 'בּ', 'פּ', 'שׁ', 'שׂ'), a niqqud point, or a
/// verse reading mark. Returns null for an unrecognised glyph.
HebrewLetter? glyphInfo(String glyph) {
  for (final l in kAlphabet) {
    if (l.letter == glyph || l.finalForm == glyph) return l;
  }
  for (final n in kNiqqud) {
    if (n.letter == glyph) return n;
  }
  for (final m in kReadingMarks) {
    if (m.letter == glyph) return m;
  }
  return null;
}

/// True if [glyph] is a combining niqqud point (vowels, dagesh, shin/sin dot,
/// accents), so the UI renders it on a dotted circle. Spacing punctuation —
/// maqaf (U+05BE), paseq (U+05C0), sof pasuq (U+05C3), nun hafukha (U+05C6) — is
/// excluded; those display on their own.
bool isNiqqud(String glyph) {
  if (glyph.isEmpty) return false;
  final c = glyph.codeUnitAt(0);
  return (c >= 0x0591 && c <= 0x05BD) || // accents, vowels, meteg
      c == 0x05BF || // rafe
      (c >= 0x05C1 && c <= 0x05C2) || // shin / sin dot
      (c >= 0x05C4 && c <= 0x05C5) || // upper / lower dot
      c == 0x05C7; // qamats qatan
}

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
    name: 'Vet',
    hebrewName: 'בֵית',
    translit: 'v',
    sound: 'v as in vine',
    value: 2,
    example: 'אָב',
    exampleTranslit: 'av',
    exampleMeaning: 'father',
    tip:
        'Don’t confuse with Kaf (כ): Bet has a square corner and a small '
        'heel at the bottom right. With a dagesh (בּ) it becomes Bet.',
  ),
  HebrewLetter(
    letter: 'בּ', // BET + DAGESH
    name: 'Bet',
    hebrewName: 'בֵּית',
    translit: 'b',
    sound: 'b as in boy',
    value: 2,
    example: 'בַּיִת',
    exampleTranslit: 'bayit',
    exampleMeaning: 'house',
    tip: 'The dot (dagesh) inside hardens Vet (ב) into Bet.',
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
    name: 'Fe',
    hebrewName: 'פֵא',
    translit: 'f',
    sound: 'f as in fish',
    value: 80,
    example: 'אֶלֶף',
    exampleTranslit: 'elef',
    exampleMeaning: 'thousand, ox',
    tip: 'With a dagesh (פּ) it becomes Pe. Its final form ף drops below the line.',
  ),
  HebrewLetter(
    letter: 'פּ', // PE + DAGESH
    name: 'Pe',
    hebrewName: 'פֵּא',
    translit: 'p',
    sound: 'p as in pay',
    value: 80,
    example: 'פֶּה',
    exampleTranslit: 'peh',
    exampleMeaning: 'mouth',
    tip: 'The dot (dagesh) inside hardens Fe (פ) into Pe.',
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
    letter: 'שׁ', // SHIN + SHIN DOT
    name: 'Shin',
    hebrewName: 'שִׁין',
    translit: 'sh',
    sound: 'sh as in ship — dot on the upper right',
    value: 300,
    example: 'שָׁלוֹם',
    exampleTranslit: 'shalom',
    exampleMeaning: 'peace',
    tip: 'The dot on the right makes it “sh”; on the left (שׂ) it is Sin, “s”.',
  ),
  HebrewLetter(
    letter: 'שׂ', // SHIN + SIN DOT
    name: 'Sin',
    hebrewName: 'שִׂין',
    translit: 's',
    sound: 's as in sun — dot on the upper left',
    value: 300,
    example: 'יִשְׂרָאֵל',
    exampleTranslit: 'yisra’el',
    exampleMeaning: 'Israel',
    tip: 'The dot on the left makes it “s”; on the right (שׁ) it is Shin, “sh”.',
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
