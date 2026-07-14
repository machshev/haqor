/// Display filtering for verse text. The romanization itself ("how it
/// sounds") lives in the core (`haqor-core`'s `romanize` module) — every card
/// and verse signal arrives with its voicing attached, so the app only
/// presents it.
library;

/// Strip cantillation accents (te'amim, U+0591–U+05AF) and meteg (U+05BD) from
/// a verse so the reading view matches the un-accented forms taught on the
/// cards. Vowel points (niqqud) and word separators (space, maqaf) are kept.
String stripCantillation(String text) {
  final buf = StringBuffer();
  for (final r in text.runes) {
    if (r >= 0x0591 && r <= 0x05AF) continue; // te'amim
    if (r == 0x05BD) continue; // meteg
    buf.writeCharCode(r);
  }
  return buf.toString();
}
