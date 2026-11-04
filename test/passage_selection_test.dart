import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/passage_selection.dart';
import 'package:haqor/src/study_workspace.dart';

WordPoint _word(int chapter, int verse, int position, {int book = 0}) =>
    (book: book, chapter: chapter, verse: verse, position: position);

void main() {
  test('words tapped make a span, in either order', () {
    final selection = PassageSelection.word(
      _word(2, 4, 3),
    ).tapWord(_word(1, 30, 1));
    expect(selection.passage.locationKey, '0:1:30-2:4@1-3');
    expect(selection.passage.reference, '1:30 word 2–2:4 word 4');
  });

  test('a span widens to its verses and its chapter, and narrows back', () {
    final words = PassageSelection.word(_word(1, 3, 2)).tapWord(_word(1, 5, 0));
    final verses = words.withScope(PassageScope.verses);
    expect(verses.passage.locationKey, '0:1:3-1:5');
    final chapter = verses.withScope(PassageScope.chapter);
    expect(chapter.passage.locationKey, '0:1');
    expect(chapter.passage.wholeChapter, isTrue);
    expect(chapter.withScope(PassageScope.words), words);
  });

  test('verses tapped make a range, and have no words to narrow to', () {
    final verses = const PassageSelection.verse(0, 1, 6).tapVerse(0, 1, 2);
    expect(verses.passage.locationKey, '0:1:2-1:6');
    expect(verses.hasWords, isFalse);
    expect(identical(verses.withScope(PassageScope.words), verses), isTrue);
    // A word then starts afresh, as does a verse in another book.
    expect(verses.tapWord(_word(1, 4, 2)).passage.locationKey, '0:1:4@2-2');
    expect(verses.tapVerse(1, 1, 1).passage.locationKey, '1:1:1');
  });

  test('a passage chosen before is chosen again as it was', () {
    for (final passage in const [
      StudyPassage(bookIndex: 4, chapter: 2, verse: 1, wholeChapter: true),
      StudyPassage(bookIndex: 4, chapter: 2, verse: 3, endVerse: 7),
      StudyPassage(
        bookIndex: 4,
        chapter: 2,
        verse: 3,
        endChapter: 3,
        endVerse: 1,
        startWord: 5,
        endWord: 0,
      ),
    ]) {
      expect(
        PassageSelection.of(passage).passage.locationKey,
        passage.locationKey,
      );
    }
  });
}
