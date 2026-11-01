import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bible_data.dart';
import 'package:haqor/src/verse_counts.dart';

void main() {
  test('every book has as many chapters as it is known to have', () {
    expect(kVerseCounts.length, kEnglishBookNames.length);
    for (final (i, chapters) in kVerseCounts.indexed) {
      expect(chapters.length, kBooks[i].chapters, reason: kEnglishBookNames[i]);
    }
  });

  test('counts a chapter, and no chapter beyond the book', () {
    expect(verseCount(41, 1), 80); // Luke 1
    expect(verseCount(42, 21), 25); // John 21
    expect(verseCount(42, 22), isNull);
    expect(verseCount(66, 1), isNull);
  });
}
