/// A lightweight, approximate romanization of pointed Hebrew, to help a beginner
/// sound out a word or verse before they can read the script fluently.
///
/// This is deliberately *not* a scholarly transliteration. It makes pragmatic
/// choices so the output reads naturally for a learner: modern consonant values
/// (ח → "ch", צ → "ts"), aleph and ayin marked with an apostrophe, sheva voiced
/// as "e", matres lectionis (a vowel-letter vav or yod) folded into the vowel
/// they lengthen, and furtive patah read before its guttural (רוּחַ → "ruach").
/// Cantillation is ignored; spaces are kept and a maqaf becomes a hyphen.
library;

// Niqqud / dagesh / shin-sin dots we consume; cantillation (U+0591–U+05AF) and
// meteg (U+05BD) are intentionally excluded so they're skipped as noise.
bool _isMark(int c) =>
    (c >= 0x05B0 && c <= 0x05BC) ||
    c == 0x05C1 ||
    c == 0x05C2 ||
    c == 0x05C7;

bool _isBase(int c) => c >= 0x05D0 && c <= 0x05EA;

String _vowel(int c) {
  switch (c) {
    case 0x05B0: // sheva (voiced approximation)
    case 0x05B1: // hataf segol
    case 0x05B5: // tsere
    case 0x05B6: // segol
      return 'e';
    case 0x05B2: // hataf patah
    case 0x05B7: // patah
    case 0x05B8: // qamats
      return 'a';
    case 0x05B4: // hiriq
      return 'i';
    case 0x05B3: // hataf qamats
    case 0x05B9: // holam
    case 0x05C7: // qamats qatan
      return 'o';
    case 0x05BB: // qubuts
      return 'u';
    default:
      return '';
  }
}

String _consonant(int c, {required bool dagesh, required bool sinDot}) {
  switch (c) {
    case 0x05D0: // alef — glottal stop
    case 0x05E2: // ayin
      return "'";
    case 0x05D1: // bet
      return dagesh ? 'b' : 'v';
    case 0x05D2: // gimel
      return 'g';
    case 0x05D3: // dalet
      return 'd';
    case 0x05D4: // he
      return 'h';
    case 0x05D5: // vav (consonantal; vowel use handled by caller)
      return 'v';
    case 0x05D6: // zayin
      return 'z';
    case 0x05D7: // het
      return 'ch';
    case 0x05D8: // tet
      return 't';
    case 0x05D9: // yod
      return 'y';
    case 0x05DA: // final kaf
      return 'kh';
    case 0x05DB: // kaf
      return dagesh ? 'k' : 'kh';
    case 0x05DC: // lamed
      return 'l';
    case 0x05DD: // final mem
    case 0x05DE: // mem
      return 'm';
    case 0x05DF: // final nun
    case 0x05E0: // nun
      return 'n';
    case 0x05E1: // samekh
      return 's';
    case 0x05E3: // final pe
      return 'f';
    case 0x05E4: // pe
      return dagesh ? 'p' : 'f';
    case 0x05E5: // final tsadi
    case 0x05E6: // tsadi
      return 'ts';
    case 0x05E7: // qof
      return 'k';
    case 0x05E8: // resh
      return 'r';
    case 0x05E9: // shin / sin
      return sinDot ? 's' : 'sh';
    case 0x05EA: // tav
      return 't';
    default:
      return '';
  }
}

/// Group the codepoints into clusters: each base consonant carries its trailing
/// marks; spaces and maqaf become their own one-element separators.
List<List<int>> _clusters(String text) {
  final out = <List<int>>[];
  for (final c in text.runes) {
    if (_isBase(c)) {
      out.add([c]);
    } else if (_isMark(c)) {
      if (out.isNotEmpty && _isBase(out.last.first)) out.last.add(c);
    } else if (c == 0x20) {
      out.add([0x20]);
    } else if (c == 0x05BE) {
      out.add([0x05BE]); // maqaf
    }
    // everything else (cantillation, sof pasuq, paseq, …) is dropped
  }
  return out;
}

/// True if no base-consonant cluster follows index [k] before a separator/end —
/// i.e. [k] is the last consonant of its word.
bool _wordFinal(List<List<int>> clusters, int k) {
  if (k + 1 >= clusters.length) return true;
  // A word's consonants are contiguous, so the next cluster decides it: another
  // base consonant means more letters follow; a separator means this is the end.
  return !_isBase(clusters[k + 1].first);
}

/// The onset sound of a single base consonant, for voicing a teaching syllable
/// (e.g. building `הֶ` → "he"). Unlike [transliterateHebrew] this bypasses the
/// word-level heuristics — most importantly the "silent final he" rule that
/// drops a vowel-less he — so a lone host consonant is never swallowed. The
/// consonant is read without dagesh (matching a bare, unpointed host), so a
/// begadkefat letter takes its soft value (ב → "v").
String consonantOnset(String glyph) {
  if (glyph.isEmpty) return '';
  final c = glyph.runes.first;
  if (!_isBase(c)) return '';
  return _consonant(c, dagesh: false, sinDot: false);
}

String transliterateHebrew(String text) {
  final clusters = _clusters(text);
  final out = StringBuffer();
  String lastVowel = '';

  for (var k = 0; k < clusters.length; k++) {
    final cl = clusters[k];
    final base = cl.first;

    if (base == 0x20) {
      out.write(' ');
      lastVowel = '';
      continue;
    }
    if (base == 0x05BE) {
      out.write('-');
      lastVowel = '';
      continue;
    }

    final marks = cl.sublist(1);
    final dagesh = marks.contains(0x05BC);
    final sinDot = marks.contains(0x05C2);
    final vowels = marks.where((m) => _vowel(m).isNotEmpty).toList();
    final vstr = vowels.map(_vowel).join();
    final isLast = _wordFinal(clusters, k);

    // Vav serving as a vowel letter: holam male (וֹ → o) or shuruq (וּ → u).
    if (base == 0x05D5) {
      if (marks.contains(0x05B9)) {
        out.write('o');
        lastVowel = 'o';
        continue;
      }
      if (dagesh && vowels.isEmpty) {
        out.write('u');
        lastVowel = 'u';
        continue;
      }
    }

    // Yod as a mater lengthening a preceding hiriq (…ִי): fold into the "i".
    if (base == 0x05D9 && vowels.isEmpty && !dagesh && lastVowel == 'i') {
      continue;
    }

    // Furtive patah under a final guttural is sounded *before* it (רוּחַ → ruach).
    if (isLast &&
        marks.contains(0x05B7) &&
        (base == 0x05D7 || base == 0x05E2 || base == 0x05D4)) {
      out.write('a');
      out.write(_consonant(base, dagesh: dagesh, sinDot: sinDot));
      lastVowel = '';
      continue;
    }

    out.write(_consonant(base, dagesh: dagesh, sinDot: sinDot));
    out.write(vstr);
    lastVowel = vstr.isEmpty ? '' : vstr.substring(vstr.length - 1);
  }

  return out.toString();
}
