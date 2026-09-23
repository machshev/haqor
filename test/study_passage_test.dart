import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/study_workspace.dart';

void main() {
  test(
    'legacy verses and all range shapes round-trip without losing annotations',
    () {
      final legacy = StudyPassage.fromJson({
        'book': 0,
        'chapter': 1,
        'verse': 3,
      })!;
      expect(legacy.locationKey, '0:1:3');
      final refs = [
        legacy,
        const StudyPassage(
          bookIndex: 0,
          chapter: 1,
          verse: 1,
          wholeChapter: true,
        ),
        const StudyPassage(bookIndex: 0, chapter: 1, verse: 3, endVerse: 5),
        const StudyPassage(
          bookIndex: 0,
          chapter: 1,
          verse: 3,
          startWord: 1,
          endWord: 3,
        ),
        const StudyPassage(
          bookIndex: 0,
          chapter: 1,
          verse: 3,
          endChapter: 2,
          endVerse: 2,
          startWord: 2,
          endWord: 0,
        ),
      ];
      final workspace = StudyWorkspace(
        id: 's',
        name: 'Study',
        passages: [
          for (final p in refs)
            p.copyWith(
              note: 'Keep',
              colorValue: 0xffff0000,
              highlightEnabled: false,
              groupId: () => 'g',
              order: 7,
            ),
        ],
        groups: const [StudyGroup(id: 'g', name: 'Group')],
      );
      final restored = decodeStudyWorkspaces(
        encodeStudyWorkspaces([workspace]),
      ).single;
      expect(restored.toJson(), workspace.toJson());
      expect(refs.map((p) => p.locationKey).toSet(), hasLength(5));
      expect(refs.map((p) => p.reference), [
        '1:3',
        '1',
        '1:3–5',
        '1:3 · words 2–4',
        '1:3 word 3–2:2 word 1',
      ]);
    },
  );

  test(
    'phrase membership clips both endpoints and includes intervening verses',
    () {
      const phrase = StudyPassage(
        bookIndex: 0,
        chapter: 1,
        verse: 3,
        endChapter: 2,
        endVerse: 2,
        startWord: 2,
        endWord: 1,
      );
      expect(phrase.containsWord(0, 1, 3, 1), false);
      expect(phrase.containsWord(0, 1, 3, 2), true);
      expect(phrase.containsWord(0, 1, 4, 0), true);
      expect(phrase.containsWord(0, 2, 1, 9), true);
      expect(phrase.containsWord(0, 2, 2, 1), true);
      expect(phrase.containsWord(0, 2, 2, 2), false);
      expect(phrase.containsWord(0, 2, 3, 0), false);
      expect(phrase.containsWord(1, 1, 3, 2), false);
      const single = StudyPassage(
        bookIndex: 0,
        chapter: 1,
        verse: 3,
        startWord: 2,
        endWord: 3,
      );
      expect(
        [for (var i = 0; i < 5; i++) single.containsWord(0, 1, 3, i)],
        [false, false, true, true, false],
      );
    },
  );

  test('invalid and reversed stored ranges are rejected', () {
    for (final fields in <Map<String, Object?>>[
      {'endVerse': 1},
      {'endChapter': 0},
      {'endChapter': 51},
      {'startWord': 1},
      {'endWord': 2},
      {'startWord': -1, 'endWord': 2},
      {'startWord': 3, 'endWord': 2},
      {'startWord': '1'},
      {'wholeChapter': true},
      {'book': 999},
    ]) {
      expect(
        StudyPassage.fromJson({'book': 0, 'chapter': 1, 'verse': 2, ...fields}),
        isNull,
        reason: '$fields',
      );
    }
  });

  test(
    'editing replaces in place and never overwrites a colliding bookmark',
    () {
      const original = StudyPassage(
        bookIndex: 0,
        chapter: 1,
        verse: 3,
        groupId: 'g',
        note: 'Keep',
        order: 2,
        colorValue: 0xff112233,
        highlightEnabled: false,
      );
      const other = StudyPassage(bookIndex: 0, chapter: 1, verse: 4);
      const workspace = StudyWorkspace(
        id: 's',
        name: 'Study',
        passages: [original, other],
      );
      final edited = original
          .withReference(
            const StudyPassage(
              bookIndex: 0,
              chapter: 1,
              verse: 3,
              endVerse: 5,
              startWord: 1,
              endWord: 2,
            ),
          )
          .copyWith(note: 'Edited');
      final result = workspace.replacePassage(original, edited);
      expect(result.passages.length, 2);
      expect(result.passages.first.toJson(), edited.toJson());
      expect(result.passages.last, same(other));
      expect(result.passageAt(0, 1, 3), isNull);
      expect(result.passagesAt(0, 1, 4), hasLength(2));
      expect(workspace.replacePassage(original, other), same(workspace));
    },
  );
}
