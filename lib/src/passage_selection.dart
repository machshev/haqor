import 'package:flutter/foundation.dart';

import 'study_workspace.dart';

/// What a passage chosen in the reader covers.
enum PassageScope { words, verses, chapter }

/// A place in the text: its 0-based book, chapter and verse, and a word's
/// lexical position, or -1 for the verse itself.
typedef WordPoint = ({int book, int chapter, int verse, int position});

int compareWordPoints(WordPoint a, WordPoint b) => a.chapter != b.chapter
    ? a.chapter.compareTo(b.chapter)
    : a.verse != b.verse
    ? a.verse.compareTo(b.verse)
    : a.position.compareTo(b.position);

/// A passage being chosen in the reader, from where it was started
/// ([anchor]) to where it was last taken ([focus]), in either order, within
/// one book. Its words are chosen by tapping or highlighting them, its verses
/// by tapping them, and the [scope] widens words to their verses, or either
/// to the chapter, and back.
@immutable
class PassageSelection {
  const PassageSelection({
    required this.anchor,
    required this.focus,
    this.scope = PassageScope.words,
  });

  /// One word.
  const PassageSelection.word(WordPoint point)
    : this(anchor: point, focus: point);

  /// One verse.
  const PassageSelection.verse(int book, int chapter, int verse)
    : this(
        anchor: (book: book, chapter: chapter, verse: verse, position: -1),
        focus: (book: book, chapter: chapter, verse: verse, position: -1),
        scope: PassageScope.verses,
      );

  /// The selection [passage] makes, to change it.
  factory PassageSelection.of(StudyPassage passage) {
    WordPoint point(int chapter, int verse, int? position) => (
      book: passage.bookIndex,
      chapter: chapter,
      verse: verse,
      position: position ?? -1,
    );
    return PassageSelection(
      anchor: point(passage.chapter, passage.verse, passage.startWord),
      focus: point(passage.lastChapter, passage.lastVerse, passage.endWord),
      scope: passage.wholeChapter
          ? PassageScope.chapter
          : passage.isPhrase
          ? PassageScope.words
          : PassageScope.verses,
    );
  }

  final WordPoint anchor;
  final WordPoint focus;
  final PassageScope scope;

  int get book => anchor.book;

  /// Whether its ends are words, so it can narrow to them.
  bool get hasWords => anchor.position >= 0 && focus.position >= 0;

  (WordPoint, WordPoint) get _ordered =>
      compareWordPoints(anchor, focus) <= 0 ? (anchor, focus) : (focus, anchor);

  /// The passage chosen: its words, the verses they are in, or the chapter
  /// it starts in.
  StudyPassage get passage {
    final (start, end) = _ordered;
    return switch (scope) {
      PassageScope.chapter => StudyPassage(
        bookIndex: book,
        chapter: start.chapter,
        verse: 1,
        wholeChapter: true,
      ),
      PassageScope.verses => StudyPassage(
        bookIndex: book,
        chapter: start.chapter,
        verse: start.verse,
        endChapter: end.chapter,
        endVerse: end.verse,
      ),
      PassageScope.words => StudyPassage(
        bookIndex: book,
        chapter: start.chapter,
        verse: start.verse,
        endChapter: end.chapter,
        endVerse: end.verse,
        startWord: start.position,
        endWord: end.position,
      ),
    };
  }

  /// Widened or narrowed to [scope]; words only while its ends are words.
  PassageSelection withScope(PassageScope scope) =>
      scope == PassageScope.words && !hasWords
      ? this
      : PassageSelection(anchor: anchor, focus: focus, scope: scope);

  /// A word tapped: the end of a span of words in the same book, or else the
  /// start of a new one.
  PassageSelection tapWord(WordPoint point) =>
      scope == PassageScope.words && point.book == book && hasWords
      ? PassageSelection(anchor: anchor, focus: point)
      : PassageSelection.word(point);

  /// A verse tapped: the end of a range of verses in the same book, or else
  /// the start of a new one.
  PassageSelection tapVerse(int book, int chapter, int verse) =>
      scope == PassageScope.verses && book == this.book
      ? PassageSelection(
          anchor: anchor,
          focus: (book: book, chapter: chapter, verse: verse, position: -1),
          scope: PassageScope.verses,
        )
      : PassageSelection.verse(book, chapter, verse);

  @override
  bool operator ==(Object other) =>
      other is PassageSelection &&
      other.anchor == anchor &&
      other.focus == focus &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(anchor, focus, scope);
}
