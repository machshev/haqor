import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/tutor/transliterate.dart';

void main() {
  group('transliterateHebrew', () {
    test('common words read naturally', () {
      expect(transliterateHebrew('שָׁלוֹם'), 'shalom');
      expect(transliterateHebrew('בַּיִת'), 'bayit');
      expect(transliterateHebrew('תּוֹרָה'), 'tora'); // silent final he
      expect(transliterateHebrew('בְּרֵאשִׁית'), 'bereshit'); // mater yod folded
    });

    test('dagesh hardens begadkefat', () {
      expect(transliterateHebrew('בּ'), 'b');
      expect(transliterateHebrew('ב'), 'v');
      expect(transliterateHebrew('כּ'), 'k');
      expect(transliterateHebrew('כ'), 'kh');
    });

    test('sin vs shin dot', () {
      expect(transliterateHebrew('שׁ'), 'sh');
      expect(transliterateHebrew('שׂ'), 's');
    });

    test('furtive patah is read before the guttural', () {
      expect(transliterateHebrew('רוּחַ'), 'ruach');
    });

    test('maqaf becomes a hyphen', () {
      expect(transliterateHebrew('עַל־כֵּן'), 'al-ken');
    });

    test('spaces between words are kept', () {
      expect(transliterateHebrew('בַּיִת שָׁלוֹם'), 'bayit shalom');
    });
  });

  group('consonantOnset', () {
    test('voices a lone consonant, incl. he (not swallowed as final)', () {
      // The word-level "silent final he" rule must NOT apply to a syllable host.
      expect(consonantOnset('ה'), 'h');
      expect(consonantOnset('מ'), 'm');
      expect(consonantOnset('ח'), 'ch');
      expect(consonantOnset('ב'), 'v'); // bare host: soft begadkefat
    });

    test('non-consonants have no onset', () {
      expect(consonantOnset(''), '');
      expect(consonantOnset('ֶ'), ''); // a bare vowel point
    });
  });
}
