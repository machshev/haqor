import '../bible_data.dart';
import '../bindings/bindings.dart';

/// A run of chapters of one book by name: "Ruth 4", "Ruth 2–4", or "Ruth"
/// for the whole book.
String chapterSpanName(
  int bookIndex,
  int first,
  int last, {
  required bool useEnglish,
}) {
  final book = bookDisplayName(bookIndex, useEnglish: useEnglish);
  if (first == 1 && last >= kBooks[bookIndex].chapters) return book;
  return first == last ? '$book $first' : '$book $first–$last';
}

/// The verses naming someone or somewhere: "verses 1, 2, 19" within one
/// chapter, "verses 1:1, 2; 4:11" across several. A long list gives its
/// first [limit] and how many more.
String namedVersesLabel(
  List<ChapterVerseEntry> verses, {
  required bool oneChapter,
  int limit = 12,
}) {
  final word = verses.length == 1 ? 'verse' : 'verses';
  final shown = verses.take(limit).toList();
  final parts = StringBuffer();
  for (var i = 0; i < shown.length; i++) {
    final v = shown[i];
    if (oneChapter) {
      if (i > 0) parts.write(', ');
      parts.write(v.verse);
    } else if (i == 0) {
      parts.write('${v.chapter}:${v.verse}');
    } else if (v.chapter == shown[i - 1].chapter) {
      parts.write(', ${v.verse}');
    } else {
      parts.write('; ${v.chapter}:${v.verse}');
    }
  }
  final more = verses.length - shown.length;
  return '$word $parts${more > 0 ? ' and $more more' : ''}';
}

/// The verses a find's passages cover, as runs: "Verses 13–37" and "Verses
/// 2, 5 and 7–9" within one chapter; "Verses 18:13–19:37" across several.
String coveredVersesLabel(
  List<ChapterVerseEntry> verses, {
  required bool oneChapter,
}) {
  // A run goes on to the next verse, or from a chapter's end to the next
  // chapter's start: the verses come as the corpus numbers them.
  bool follows(ChapterVerseEntry a, ChapterVerseEntry b) =>
      (b.chapter == a.chapter && b.verse == a.verse + 1) ||
      (b.chapter == a.chapter + 1 && b.verse == 1);
  String at(ChapterVerseEntry v, {ChapterVerseEntry? from}) =>
      oneChapter || from?.chapter == v.chapter
      ? '${v.verse}'
      : '${v.chapter}:${v.verse}';
  final runs = <String>[];
  var i = 0;
  while (i < verses.length) {
    var j = i;
    while (j + 1 < verses.length && follows(verses[j], verses[j + 1])) {
      j++;
    }
    runs.add(
      i == j
          ? at(verses[i])
          : '${at(verses[i])}–${at(verses[j], from: verses[i])}',
    );
    i = j + 1;
  }
  final word = verses.length == 1 ? 'Verse' : 'Verses';
  if (runs.length == 1) return '$word ${runs.single}';
  return '$word ${runs.sublist(0, runs.length - 1).join(', ')} and ${runs.last}';
}
