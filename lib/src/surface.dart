import 'dart:ui' show TextDirection;

int _hebCombiningClass(int cp) {
  switch (cp) {
    case 0x05B0:
      return 10;
    case 0x05B1:
      return 11;
    case 0x05B2:
      return 12;
    case 0x05B3:
      return 13;
    case 0x05B4:
      return 14;
    case 0x05B5:
      return 15;
    case 0x05B6:
      return 16;
    case 0x05B7:
      return 17;
    case 0x05B8:
    case 0x05C7:
      return 18;
    case 0x05B9:
      return 19;
    case 0x05BB:
      return 20;
    case 0x05BC:
      return 21;
    case 0x05C1:
      return 24;
    case 0x05C2:
      return 25;
    default:
      return 0;
  }
}

/// Canonical surface key mirroring the Rust `normalize_surface`: keep only
/// consonants and pointing (dropping cantillation/maqaf/etc.), then stable-sort
/// each run of combining marks by combining class. Used to match the looked-up
/// word and verse tokens against the DB's normalised surface forms regardless
/// of trope or combining-mark order.
String hebrewSurfaceKey(String word) {
  final kept = word.runes.where((cp) {
    return (cp >= 0x05D0 && cp <= 0x05EA) ||
        (cp >= 0x05B0 && cp <= 0x05B9) ||
        cp == 0x05BB ||
        cp == 0x05BC ||
        cp == 0x05C1 ||
        cp == 0x05C2 ||
        cp == 0x05C7;
  }).toList();

  final out = <int>[];
  var i = 0;
  while (i < kept.length) {
    if (_hebCombiningClass(kept[i]) == 0) {
      out.add(kept[i]);
      i++;
    } else {
      final start = i;
      while (i < kept.length && _hebCombiningClass(kept[i]) != 0) {
        i++;
      }
      final run = kept.sublist(
        start,
        i,
      )..sort((a, b) => _hebCombiningClass(a).compareTo(_hebCombiningClass(b)));
      out.addAll(run);
    }
  }
  return String.fromCharCodes(out);
}

/// Whether [word] is written in Greek letters.
bool isGreekWord(String word) => word.runes.any(
  (cp) => (cp >= 0x0370 && cp <= 0x03FF) || (cp >= 0x1F00 && cp <= 0x1FFF),
);

/// A Greek word's letters alone, in lower case, without accents, breathings
/// or iota subscripts, and with final sigma as any other: a form as the TR
/// spells it, whether it opens a sentence or carries a grave accent before
/// the next word.
String greekSurfaceKey(String word) {
  final out = StringBuffer();
  for (final cp in word.runes) {
    final base = _greekBase(cp);
    if (base != null) out.writeCharCode(base);
  }
  return out.toString();
}

/// The bare lower-case letter of a Greek code point, or null for anything
/// else (punctuation, combining marks).
int? _greekBase(int cp) {
  // Basic Greek capitals, and final sigma.
  if (cp >= 0x0391 && cp <= 0x03A9 && cp != 0x03A2) return cp + 0x20;
  if (cp == 0x03C2) return 0x03C3;
  if (cp >= 0x03B1 && cp <= 0x03C9) return cp;
  final tonos = _greekTonos[cp];
  if (tonos != null) return tonos.codeUnitAt(0);
  if (cp >= 0x1F00 && cp <= 0x1FFF) {
    for (final (first, last, letter) in _greekExtended) {
      if (cp >= first && cp <= last) return letter.codeUnitAt(0);
    }
  }
  return null;
}

const _greekTonos = {
  0x0386: 'α', 0x0388: 'ε', 0x0389: 'η', 0x038A: 'ι', 0x038C: 'ο', //
  0x038E: 'υ', 0x038F: 'ω', 0x0390: 'ι', 0x03AA: 'ι', 0x03AB: 'υ', //
  0x03AC: 'α', 0x03AD: 'ε', 0x03AE: 'η', 0x03AF: 'ι', 0x03B0: 'υ', //
  0x03CA: 'ι', 0x03CB: 'υ', 0x03CC: 'ο', 0x03CD: 'υ', 0x03CE: 'ω',
};

/// The Greek Extended block's letters, by range: polytonic vowels and rho,
/// capital or small, with whatever marks they carry.
const _greekExtended = [
  (0x1F00, 0x1F0F, 'α'),
  (0x1F10, 0x1F1D, 'ε'),
  (0x1F20, 0x1F2F, 'η'),
  (0x1F30, 0x1F3F, 'ι'),
  (0x1F40, 0x1F4D, 'ο'),
  (0x1F50, 0x1F5F, 'υ'),
  (0x1F60, 0x1F6F, 'ω'),
  (0x1F70, 0x1F71, 'α'),
  (0x1F72, 0x1F73, 'ε'),
  (0x1F74, 0x1F75, 'η'),
  (0x1F76, 0x1F77, 'ι'),
  (0x1F78, 0x1F79, 'ο'),
  (0x1F7A, 0x1F7B, 'υ'),
  (0x1F7C, 0x1F7D, 'ω'),
  (0x1F80, 0x1F8F, 'α'),
  (0x1F90, 0x1F9F, 'η'),
  (0x1FA0, 0x1FAF, 'ω'),
  (0x1FB0, 0x1FBC, 'α'),
  (0x1FC2, 0x1FC7, 'η'),
  (0x1FC8, 0x1FC9, 'ε'),
  (0x1FCA, 0x1FCC, 'η'),
  (0x1FD0, 0x1FDB, 'ι'),
  (0x1FE0, 0x1FE3, 'υ'),
  (0x1FE4, 0x1FE5, 'ρ'),
  (0x1FE6, 0x1FEB, 'υ'),
  (0x1FEC, 0x1FEC, 'ρ'),
  (0x1FF2, 0x1FF7, 'ω'),
  (0x1FF8, 0x1FF9, 'ο'),
  (0x1FFA, 0x1FFC, 'ω'),
];

/// The direction [word] reads in: left to right for Greek, right to left for
/// Hebrew and Syriac.
TextDirection wordDirection(String word) =>
    isGreekWord(word) ? TextDirection.ltr : TextDirection.rtl;
