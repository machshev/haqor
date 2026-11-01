import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/basis_references.dart';

void main() {
  /// Each reference as written, and as "book chapter:verse-endChapter:endVerse".
  List<(String, String)> read(String basis) => [
    for (final r in basisReferences(basis))
      (
        basis.substring(r.start, r.end),
        '${r.passage.bookIndex} ${r.passage.chapter}:'
            '${r.passage.wholeChapter ? '*' : r.passage.verse}'
            '${r.passage.endChapter == null ? '' : '-${r.passage.endChapter}'}'
            '${r.passage.endVerse == null ? '' : ':${r.passage.endVerse}'}',
      ),
  ];

  test('reads a verse, and a range', () {
    expect(read('John 3:24: John was not yet cast into prison'), [
      ('John 3:24', '42 3:24'),
    ]);
    expect(read('John 1:32–33 looks back on the baptism'), [
      ('John 1:32–33', '42 1:32:33'),
    ]);
    expect(read('John 20:11-21:1'), [('John 20:11-21:1', '42 20:11-21:1')]);
  });

  test('reads several, in one book and in others', () {
    expect(read('Matthew 4:12; Mark 1:14: after John was put in prison'), [
      ('Matthew 4:12', '39 4:12'),
      ('Mark 1:14', '40 1:14'),
    ]);
    expect(read('John 3:22 and 4:1-3'), [
      ('John 3:22', '42 3:22'),
      ('4:1-3', '42 4:1:3'),
    ]);
    expect(read('Matthew 4:5, 8: then … again'), [
      ('Matthew 4:5', '39 4:5'),
      ('8', '39 4:8'),
    ]);
    expect(read('Matthew 1:18-25; 2:1-23'), [
      ('Matthew 1:18-25', '39 1:18:25'),
      ('2:1-23', '39 2:1:23'),
    ]);
  });

  test('reads whole chapters, and numbered books', () {
    expect(
      read('John 21 and Matthew 28 precede the final departure in Acts 1:3-12'),
      [
        ('John 21', '42 21:*'),
        ('Matthew 28', '39 28:*'),
        ('Acts 1:3-12', '43 1:3:12'),
      ],
    );
    expect(read('1 Kings 3:4; 2 John 1:1'), [
      ('1 Kings 3:4', '9 3:4'),
      ('2 John 1:1', '62 1:1'),
    ]);
  });

  test('a name not followed by a chapter is not a reference', () {
    expect(read("Mark's order"), isEmpty);
    expect(read('John the Baptist, then Luke'), isEmpty);
    expect(read("Robertson's harmony (1922)"), isEmpty);
  });
}
