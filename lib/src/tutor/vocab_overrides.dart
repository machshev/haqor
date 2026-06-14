/// Curated learner glosses for the most frequent words, overriding the
/// automatic BDB bridge from Rust where it is wrong or empty — almost all
/// closed-class particles, pronominal-suffixed forms and construct plurals,
/// which the lexicon keys by citation form only.
library;

class VocabOverride {
  /// Concise learner gloss shown on the card and used in quizzes.
  final String gloss;

  /// Optional composition/teaching note ("לְ (to) + ־וֹ (him)").
  final String? note;

  const VocabOverride(this.gloss, [this.note]);
}

/// Reduce a pointed surface form to a stable lookup key: dagesh, meteg and
/// accents dropped, remaining marks sorted within each letter's cluster.
/// Both the database surfaces and the literals in this file pass through
/// this, so differing combining-mark orders and dagesh variants (בֶּן/בֶן)
/// collapse to one key.
String vocabKey(String surface) {
  final out = StringBuffer();
  final marks = <int>[];
  void flush() {
    marks.sort();
    marks.forEach(out.writeCharCode);
    marks.clear();
  }

  for (final c in surface.runes) {
    final isMark = c >= 0x0591 && c <= 0x05C7;
    if (!isMark) {
      flush();
      out.writeCharCode(c);
    } else if (c != 0x05BC && c != 0x05BD && !(c >= 0x0591 && c <= 0x05AF)) {
      marks.add(c);
    }
  }
  flush();
  return out.toString();
}

final Map<String, VocabOverride> kVocabOverrides = {
  for (final e in _overrides.entries) vocabKey(e.key): e.value,
};

const Map<String, VocabOverride> _overrides = {
  // Object marker and its forms.
  'אֶת': VocabOverride(
    '(marks the direct object)',
    'Untranslated particle pointing to the object of the verb — the most '
        'common word in the Bible.',
  ),
  'אֵת': VocabOverride('(marks the direct object); with'),
  'וְאֶת': VocabOverride('and — (object marker)', 'וְ (and) + אֶת'),
  'וְאֵת': VocabOverride('and — (object marker)', 'וְ (and) + אֵת'),
  'אֹתוֹ': VocabOverride('him, it', 'אֵת (object marker) + ־וֹ (him)'),
  'אוֹתוֹ': VocabOverride('him, it', 'אֵת (object marker) + ־וֹ (him)'),
  'אֹתָם': VocabOverride('them', 'אֵת (object marker) + ־ָם (them)'),
  'אוֹתָם': VocabOverride('them', 'אֵת (object marker) + ־ָם (them)'),
  'אֹתָהּ': VocabOverride('her, it', 'אֵת (object marker) + ־ָהּ (her)'),
  'אֹתִי': VocabOverride('me', 'אֵת (object marker) + ־ִי (me)'),
  'אֶתְכֶם': VocabOverride('you (plural)', 'אֵת (object marker) + ־כֶם'),

  // The divine name.
  'יְהוָה': VocabOverride(
    'the LORD (YHWH)',
    'The divine name, traditionally read aloud as אֲדֹנָי (Adonai).',
  ),
  'יְהוִה': VocabOverride(
    'the LORD (YHWH)',
    'Pointed to be read as אֱלֹהִים when it follows אֲדֹנָי.',
  ),
  'לַיהוָה': VocabOverride('to the LORD', 'לְ (to) + the divine name'),
  'בַּיהוָה': VocabOverride('in the LORD', 'בְּ (in) + the divine name'),

  // Core particles.
  'אֲשֶׁר': VocabOverride('who, which, that'),
  'כִּי': VocabOverride('for, because, that, when'),
  'עַד': VocabOverride('until, as far as'),
  'וְעַד': VocabOverride('and until', 'וְ (and) + עַד'),
  'אִם': VocabOverride('if'),
  'וְאִם': VocabOverride('and if', 'וְ (and) + אִם'),
  'אַל': VocabOverride(
    'not, do not',
    'Negative used with commands and wishes.',
  ),
  'נָא': VocabOverride('please, now', 'Particle of entreaty.'),
  'אֵין': VocabOverride('there is not, without'),
  'וְאֵין': VocabOverride('and there is not', 'וְ (and) + אֵין'),
  'אַף': VocabOverride('also, even; anger, nose'),
  'לָכֵן': VocabOverride('therefore'),
  'אַחֲרֵי': VocabOverride('after, behind'),
  'עַתָּה': VocabOverride('now'),
  'וְעַתָּה': VocabOverride('and now', 'וְ (and) + עַתָּה (now)'),
  'עוֹד': VocabOverride('still, yet, again'),
  'וְגַם': VocabOverride('and also', 'וְ (and) + גַּם (also)'),
  'בֵּין': VocabOverride('between'),
  'זֶה': VocabOverride('this (m.)'),
  'זֹאת': VocabOverride('this (f.)'),
  'הַזֹּאת': VocabOverride('this (f.)', 'הַ (the) + זֹאת'),

  // Pronouns.
  'אַתָּה': VocabOverride('you (m.)'),
  'אַתֶּם': VocabOverride('you (plural)'),
  'הִיא': VocabOverride('she, it'),
  'הֵם': VocabOverride('they'),
  'הֵמָּה': VocabOverride('they'),

  // לְ + suffixes.
  'לוֹ': VocabOverride('to him, for him', 'לְ (to) + ־וֹ (him)'),
  'לִי': VocabOverride('to me, for me', 'לְ (to) + ־ִי (me)'),
  'לְךָ': VocabOverride('to you (m.)', 'לְ (to) + ־ךָ (you)'),
  'לָךְ': VocabOverride('to you (f.)', 'לְ (to) + ־ךְ (you)'),
  'לָהּ': VocabOverride('to her', 'לְ (to) + ־ָהּ (her)'),
  'לָהֶם': VocabOverride('to them', 'לְ (to) + ־הֶם (them)'),
  'לָכֶם': VocabOverride('to you (plural)', 'לְ (to) + ־כֶם (you)'),
  'לָנוּ': VocabOverride('to us', 'לְ (to) + ־נוּ (us)'),

  // בְּ + suffixes.
  'בּוֹ': VocabOverride('in him, in it', 'בְּ (in) + ־וֹ'),
  'בָּהּ': VocabOverride('in her, in it', 'בְּ (in) + ־ָהּ'),
  'בָּהֶם': VocabOverride('in them', 'בְּ (in) + ־הֶם'),

  // אֶל / עַל / מִן + suffixes.
  'אֵלָיו': VocabOverride('to him', 'אֶל (to) + ־ָיו (him)'),
  'אֵלַי': VocabOverride('to me', 'אֶל (to) + ־ַי (me)'),
  'אֵלֶיךָ': VocabOverride('to you', 'אֶל (to) + ־ֶיךָ (you)'),
  'אֲלֵיהֶם': VocabOverride('to them', 'אֶל (to) + ־ֵיהֶם (them)'),
  'עָלָיו': VocabOverride('on him, on it', 'עַל (on) + ־ָיו'),
  'עָלֶיהָ': VocabOverride('on her, on it', 'עַל (on) + ־ֶיהָ'),
  'עֲלֵיהֶם': VocabOverride('on them', 'עַל (on) + ־ֵיהֶם'),
  'עָלַי': VocabOverride('on me', 'עַל (on) + ־ַי'),
  'מִמֶּנּוּ': VocabOverride('from him, from it', 'From מִן (from).'),
  'עִמּוֹ': VocabOverride('with him', 'עִם (with) + ־וֹ'),

  // כֹּל family.
  'כָּל': VocabOverride('all, every, the whole', 'Construct form of כֹּל.'),
  'וְכָל': VocabOverride('and all', 'וְ (and) + כָּל'),
  'בְּכָל': VocabOverride('in all, with all', 'בְּ (in) + כָּל'),
  'לְכָל': VocabOverride('to all', 'לְ (to) + כָּל'),
  'מִכָּל': VocabOverride('from all', 'מִ (from) + כָּל'),

  // הָיָה (to be) forms the parser misses.
  'וַיְהִי': VocabOverride(
    'and it was, and it came to pass',
    'Narrative form of הָיָה (to be) — opens countless episodes.',
  ),
  'הָיוּ': VocabOverride('they were', 'Perfect plural of הָיָה (to be).'),
  'לֵאמֹר': VocabOverride(
    'saying',
    'לְ (to) + אָמַר (say); introduces quoted speech.',
  ),

  // Construct chains and suffixed nouns.
  'בְּנֵי': VocabOverride('sons of', 'Construct plural of בֵּן (son).'),
  'וּבְנֵי': VocabOverride('and the sons of', 'וּ (and) + בְּנֵי'),
  'לִבְנֵי': VocabOverride('to the sons of', 'לְ (to) + בְּנֵי'),
  'בַּת': VocabOverride('daughter'),
  'בֵּית': VocabOverride('house of', 'Construct of בַּיִת (house).'),
  'לְבֵית': VocabOverride('to the house of', 'לְ (to) + בֵּית'),
  'הַבַּיִת': VocabOverride('the house', 'הַ (the) + בַּיִת'),
  'פְּנֵי': VocabOverride('face of', 'Construct of פָּנִים (face).'),
  'מִפְּנֵי': VocabOverride('from before, because of', 'מִ (from) + פְּנֵי'),
  'לִפְנֵי': VocabOverride('before, in front of', 'לְ (to) + פְּנֵי (face of)'),
  'דִּבְרֵי': VocabOverride('words of', 'Construct plural of דָּבָר (word).'),
  'הַדָּבָר': VocabOverride('the word, the matter', 'הַ (the) + דָּבָר'),
  'דָּבָר': VocabOverride('word, thing, matter'),
  'אַנְשֵׁי': VocabOverride('men of', 'Construct plural of אִישׁ (man).'),
  'אָבִיו': VocabOverride('his father', 'אָב (father) + ־ִיו (his)'),
  'עַמִּי': VocabOverride('my people', 'עַם (people) + ־ִי (my)'),
  'נַפְשִׁי': VocabOverride('my soul, my life', 'נֶפֶשׁ (soul) + ־ִי (my)'),
  'בְּיַד': VocabOverride('in the hand of, by', 'בְּ (in) + יַד (hand)'),
  'יְמֵי': VocabOverride('days of', 'Construct plural of יוֹם (day).'),
  'שְׁנֵי': VocabOverride('two of', 'Construct of שְׁנַיִם (two).'),
  'שָׁנָה': VocabOverride('year'),
  'יָמִים': VocabOverride('days', 'Plural of יוֹם (day).'),
  'מֵאוֹת': VocabOverride('hundreds', 'Plural of מֵאָה (hundred).'),
  'מֵאָה': VocabOverride('hundred'),
  'מַיִם': VocabOverride('water'),
  'רַבִּים': VocabOverride('many', 'Plural of רַב (much, many).'),

  // אֱלֹהִים family.
  'אֱלֹהִים': VocabOverride(
    'God; gods',
    'Plural in form, usually singular in meaning when naming God.',
  ),
  'הָאֱלֹהִים': VocabOverride('the God, God', 'הָ (the) + אֱלֹהִים'),
  'אֱלֹהֵי': VocabOverride('God of', 'Construct of אֱלֹהִים.'),
  'אֱלֹהֶיךָ': VocabOverride('your God', 'אֱלֹהִים + ־ֶיךָ (your)'),
  'אֱלֹהֵינוּ': VocabOverride('our God', 'אֱלֹהִים + ־ֵינוּ (our)'),
  'אֵל': VocabOverride('God, god'),

  // Article + common noun forms the parser misreads.
  'הָעָם': VocabOverride('the people', 'הָ (the) + עַם'),
  'הָעִיר': VocabOverride('the city', 'הָ (the) + עִיר'),
  'הַשָּׁמַיִם': VocabOverride('the heavens', 'הַ (the) + שָׁמַיִם'),
  'שָׁמַיִם': VocabOverride('heavens, sky'),
  'הַכֹּהֲנִים': VocabOverride('the priests', 'הַ (the) + plural of כֹּהֵן'),
  'הַכֹּהֵן': VocabOverride('the priest', 'הַ (the) + כֹּהֵן'),
  'הַגּוֹיִם': VocabOverride('the nations', 'הַ (the) + plural of גּוֹי'),
  'צְבָאוֹת': VocabOverride(
    'hosts, armies',
    'Plural of צָבָא; in יְהוָה צְבָאוֹת, “the LORD of hosts”.',
  ),
  'עוֹלָם': VocabOverride('forever; eternity, long ago'),
  'לַעֲשׂוֹת': VocabOverride(
    'to do, to make',
    'לְ (to) + infinitive of עָשָׂה.',
  ),
  'אֶלֶף': VocabOverride('thousand'),

  // Names the lexicon glosses oddly.
  'יִשְׂרָאֵל': VocabOverride('Israel'),
  'שָׁאוּל': VocabOverride('Saul', 'Means “asked (of God)”.'),
  'יוֹסֵף': VocabOverride('Joseph', 'Means “he adds”.'),
  'דָּוִיד': VocabOverride('David', 'Later spelling of דָּוִד.'),
  'יְהוֹשֻׁעַ': VocabOverride('Joshua'),
};
