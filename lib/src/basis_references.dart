import 'bible_data.dart';
import 'study_workspace.dart';
import 'verse_counts.dart';

/// A passage named in a sequence ordering's basis, and where in the basis
/// it is written.
typedef BasisReference = ({int start, int end, StudyPassage passage});

/// Other names the bases write a book by, beside [kEnglishBookNames].
const _aliases = {'Psalm': 26, 'Song of Solomon': 29};

final _books = <String, int>{
  for (final (i, name) in kEnglishBookNames.indexed) name: i,
  ..._aliases,
};

/// A book's name, the longest first so that "1 John" is not read as
/// "John", then a chapter.
final _bookAt = RegExp(
  '(?<![A-Za-z0-9])(${(_books.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).map(RegExp.escape).join('|')})'
  r' (?=\d)',
);

/// One reference in a book: a chapter, a run of chapters ("8–9"), or a
/// chapter and verse, either running on to a verse or to another chapter's
/// verse.
final _one = RegExp(
  r'(\d+)(?::(\d+)(?:[–-](\d+)(?::(\d+))?)?|[–-](\d+)(?![\d:]))?',
);

/// What may join one reference to the next in the same book: a further
/// verse of the chapter (", 8"), or a further chapter ("; 2:1", " and 4:1").
final _verseOn = RegExp(r', (\d+)(?!\d|:\d)');
final _chapterOn = RegExp(r'(?:; | and )(?=\d+:)');

/// The passages [basis] names, in order: "Matthew 4:12; Mark 1:14",
/// "John 3:22 and 4:1-3", "Matthew 4:5, 8", "John 20:11-21:1",
/// "John 21". A book's name alone, or one not followed by a chapter
/// ("John the Baptist"), is not a reference.
List<BasisReference> basisReferences(String basis) {
  final found = <BasisReference>[];
  var from = 0;
  while (true) {
    final book = _bookAt.allMatches(basis, from).firstOrNull;
    if (book == null) break;
    final bookStart = book.start;
    final bookIndex = _books[book.group(1)]!;
    var at = book.end;
    var start = bookStart;
    while (true) {
      final ref = _one.matchAsPrefix(basis, at);
      if (ref == null) break;
      final chapter = int.parse(ref.group(1)!);
      final verse = ref.group(2) == null ? null : int.parse(ref.group(2)!);
      final lastChapter = ref.group(5) == null
          ? null
          : int.parse(ref.group(5)!);
      final (endChapter, endVerse) = switch ((ref.group(3), ref.group(4))) {
        (final c?, final v?) => (int.parse(c), int.parse(v)),
        (final v?, null) => (null, int.parse(v)),
        // A run of chapters, to the last verse of the last.
        _ when lastChapter != null => (
          lastChapter,
          verseCount(bookIndex, lastChapter) ?? 1,
        ),
        _ => (null, null),
      };
      found.add((
        start: start,
        end: ref.end,
        passage: StudyPassage(
          bookIndex: bookIndex,
          chapter: chapter,
          verse: verse ?? 1,
          wholeChapter: verse == null && lastChapter == null,
          endChapter: endChapter,
          endVerse: endVerse,
        ),
      ));
      at = ref.end;
      // Further verses of the same chapter, each its own.
      for (
        var more = _verseOn.matchAsPrefix(basis, at);
        more != null;
        more = _verseOn.matchAsPrefix(basis, at)
      ) {
        final v = int.parse(more.group(1)!);
        found.add((
          start: more.start + 2,
          end: more.end,
          passage: StudyPassage(
            bookIndex: bookIndex,
            chapter: chapter,
            verse: v,
          ),
        ));
        at = more.end;
      }
      final on = _chapterOn.matchAsPrefix(basis, at);
      if (on == null) break;
      at = on.end;
      start = at;
    }
    from = at > bookStart ? at : bookStart + 1;
  }
  return found;
}
