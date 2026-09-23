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
