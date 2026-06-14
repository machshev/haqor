import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/tutor/alphabet_data.dart';
import 'package:haqor/src/tutor/vocab_overrides.dart';
import 'package:haqor/src/tutor/words_tab.dart';

VocabEntry entry(
  String surface, {
  int occurrences = 1,
  String gloss = '',
  String morph = '',
  String root = '',
  String? lexicalClass,
}) => VocabEntry(
  surface: surface,
  occurrences: occurrences,
  lexicalClass: lexicalClass,
  root: root,
  gloss: gloss,
  morph: morph,
);

void main() {
  group('vocabKey', () {
    test('collapses dagesh variants', () {
      expect(vocabKey('בֶּן'), vocabKey('בֶן'));
      expect(vocabKey('כָּל'), vocabKey('כָל'));
    });

    test('is insensitive to combining-mark order', () {
      // Mem + segol + dagesh (database NFC order) vs mem + dagesh + segol
      // (traditional order).
      expect(vocabKey('\u05DE\u05B6\u05BC'), vocabKey('\u05DE\u05BC\u05B6'));
    });

    test('keeps meaningful vowel distinctions', () {
      expect(vocabKey('עַם'), isNot(vocabKey('עִם')));
    });

    test('keeps the shin/sin dot', () {
      expect(vocabKey('שׁ'), isNot(vocabKey('שׂ')));
    });
  });

  group('kVocabOverrides', () {
    test('matches database-order surfaces', () {
      // אֶת as stored: alef + segol (vowel-first NFC order), tav.
      final fromDb = vocabKey('אֶת');
      expect(kVocabOverrides[fromDb]?.gloss, '(marks the direct object)');
    });
  });

  group('buildTutorWords', () {
    test('applies overrides and suppresses automatic morph', () {
      final words = buildTutorWords([
        entry('אֶת', gloss: 'thou', morph: 'bogus'),
      ]);
      expect(words.single.gloss, '(marks the direct object)');
      expect(words.single.morph, isEmpty);
      expect(words.single.note, isNotNull);
    });

    test('drops entries without any gloss', () {
      final words = buildTutorWords([entry('קךק')]);
      expect(words, isEmpty);
    });

    test('dedupes dagesh variants keeping the first', () {
      final words = buildTutorWords([
        entry('בֶּן', occurrences: 1226, gloss: 'son'),
        entry('בֶן', occurrences: 274, gloss: 'son'),
      ]);
      expect(words, hasLength(1));
      expect(words.single.occurrences, 1226);
    });

    test('maps letters including final forms to alphabet indices', () {
      final words = buildTutorWords([entry('אֶרֶץ', gloss: 'earth')]);
      // Alef, Resh, Tsadi (final ץ folds to צ).
      expect(words.single.letters, [
        kLetterIndex['א'],
        kLetterIndex['ר'],
        kLetterIndex['צ'],
      ]);
    });

    test('letters are distinct and in word order', () {
      final words = buildTutorWords([entry('שָׁלוֹם', gloss: 'peace')]);
      expect(words.single.letters, [
        kLetterIndex['ש'],
        kLetterIndex['ל'],
        kLetterIndex['ו'],
        kLetterIndex['מ'],
      ]);
    });
  });
}
