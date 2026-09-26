import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/word_proximity.dart';

ProximityHit _hit(
  int chapter,
  int verse, {
  int book = 1,
  List<String> words = const [],
  List<int> positions = const [],
}) => ProximityHit(
  book: book,
  chapter: chapter,
  verse: verse,
  words: words,
  positions: positions,
);

List<String> _refs(List<ProximityVerse> verses) => [
  for (final v in verses) '${v.book}:${v.chapter}:${v.verse}',
];

void main() {
  test('same verse keeps only verses every word stands in', () {
    final matches = proximityMatches([
      [_hit(1, 1), _hit(1, 5), _hit(2, 3)],
      [_hit(1, 1), _hit(1, 4), _hit(2, 3)],
      [_hit(1, 1), _hit(2, 3), _hit(2, 4)],
    ], ProximityDistance.sameVerse);

    expect(_refs(matches), ['1:1:1', '1:2:3']);
    expect([for (final m in matches) m.passage], [0, 1]);
  });

  test('a verse window joins nearby matches into one passage', () {
    final matches = proximityMatches([
      [_hit(1, 1), _hit(1, 5), _hit(1, 20)],
      [_hit(1, 3), _hit(1, 30)],
    ], const ProximityDistance.withinVerses(2));

    // 1 and 3 fall in one window, and 3 and 5 in another; 20 and 30 are ten
    // verses apart.
    expect(_refs(matches), ['1:1:1', '1:1:3', '1:1:5']);
    expect({for (final m in matches) m.passage}, {0});
  });

  test('separate windows in one chapter are separate passages', () {
    final matches = proximityMatches([
      [_hit(1, 1), _hit(1, 10)],
      [_hit(1, 2), _hit(1, 11)],
    ], const ProximityDistance.withinVerses(1));

    expect(_refs(matches), ['1:1:1', '1:1:2', '1:1:10', '1:1:11']);
    expect([for (final m in matches) m.passage], [0, 0, 1, 1]);
  });

  test('a verse window never reaches across a chapter or book', () {
    final matches = proximityMatches([
      [_hit(1, 31), _hit(1, 5, book: 2)],
      [_hit(2, 1), _hit(1, 5, book: 3)],
    ], const ProximityDistance.withinVerses(5));

    expect(matches, isEmpty);
  });

  test('same chapter keeps every matching verse of a shared chapter', () {
    final matches = proximityMatches([
      [_hit(1, 1), _hit(1, 30), _hit(2, 1)],
      [_hit(1, 15), _hit(3, 1)],
    ], ProximityDistance.sameChapter);

    expect(_refs(matches), ['1:1:1', '1:1:15', '1:1:30']);
    expect({for (final m in matches) m.passage}, {0});
  });

  test('a shared verse highlights what every word matched there', () {
    final matches = proximityMatches([
      [
        _hit(1, 1, words: ['בָּרָא'], positions: [1]),
      ],
      [
        _hit(1, 1, words: ['אֱלֹהִים'], positions: [2]),
      ],
    ], ProximityDistance.sameVerse);

    expect(matches.single.words, ['בָּרָא', 'אֱלֹהִים']);
    expect(matches.single.positions, [1, 2]);
  });

  test('one word alone has nothing to be near', () {
    expect(
      proximityMatches([
        [_hit(1, 1)],
      ], ProximityDistance.sameVerse),
      isEmpty,
    );
  });

  test('distances read as the header offers them', () {
    expect(
      [for (final d in ProximityDistance.options) d.label],
      [
        'Same verse',
        'Within 1 verse',
        'Within 2 verses',
        'Within 3 verses',
        'Within 5 verses',
        'Within 10 verses',
        'Same chapter',
      ],
    );
  });
}
