import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/tutor/vocab_overrides.dart';

void main() {
  group('vocabKey', () {
    test('collapses dagesh variants', () {
      expect(vocabKey('בֶּן'), vocabKey('בֶן'));
      expect(vocabKey('כָּל'), vocabKey('כָל'));
    });

    test('is insensitive to combining-mark order', () {
      // Mem + segol + dagesh in the two possible combining orders: database
      // NFC order (vowel before dagesh) vs traditional (dagesh before vowel).
      final nfc = String.fromCharCodes([0x05DE, 0x05B6, 0x05BC]);
      final traditional = String.fromCharCodes([0x05DE, 0x05BC, 0x05B6]);
      expect(vocabKey(nfc), vocabKey(traditional));
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
}
