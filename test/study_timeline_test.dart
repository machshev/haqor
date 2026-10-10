import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';

void main() {
  const kings = StudyTimeline(
    id: 'kings',
    title: 'The divided kingdom',
    era: true,
    note: 'Dates after Thiele',
  );
  const exodus = StudyTimelineEntry(
    id: 'exodus',
    title: 'The exodus',
    timelineId: 'kings',
    start: -1446,
    date: 'c.',
    verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
  );
  const solomon = StudyTimelineEntry(
    id: 'solomon',
    title: 'Solomon reigns',
    timelineId: 'kings',
    start: -970,
    end: -931,
    verses: [
      StudyPassage(
        bookIndex: 9,
        chapter: 1,
        verse: 39,
        endChapter: 11,
        endVerse: 43,
      ),
    ],
  );
  const temple = StudyTimelineEntry(
    id: 'temple',
    title: 'Temple begun',
    timelineId: 'kings',
    start: -966,
    verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
  );
  StudyWorkspace build() => const StudyWorkspace(id: 's', name: 'Study')
      .putGroup(const StudyGroup(id: 'g', name: 'Kings'))
      .putTimeline(kings.copyWith(parentId: () => 'g'))
      .putNote(const StudyNote(id: 'intro', text: 'Intro', groupId: 'kings'))
      // Added out of time order: entries sort by time, not insertion.
      .putTimelineEntry(temple)
      .putTimelineEntry(solomon)
      .putTimelineEntry(exodus);

  test('timelines round-trip and list their items before time-ordered '
      'entries', () {
    final workspace = decodeStudyWorkspaces(
      encodeStudyWorkspaces([build().copyWith(timelineMarkersEnabled: false)]),
    ).single;
    expect(workspace.timelineMarkersEnabled, isFalse);
    expect(
      workspace.timelineById('kings')!.toJson(),
      kings.copyWith(parentId: () => 'g', order: 0).toJson(),
    );
    expect(workspace.itemsIn('g').single.key, 'timeline-kings');
    expect(workspace.itemsIn('kings').map((i) => i.key), [
      'note-intro',
      'timeline-entry-exodus',
      'timeline-entry-solomon',
      'timeline-entry-temple',
    ]);
    final stored = workspace.timelineEntries.firstWhere(
      (e) => e.id == 'exodus',
    );
    expect(stored.toJson(), exodus.copyWith(order: stored.order).toJson());
    // Whole numbers are stored without a decimal point.
    expect(stored.toJson()['start'], -1446);
    expect(workspace.timelineEntries.firstWhere((e) => e.isSpan).end, -931);
  });

  test('times read in the timeline\'s own unit or era', () {
    expect(kings.formatTime(-1446), '1446 BC');
    expect(kings.formatTime(30), 'AD 30');
    const days = StudyTimeline(id: 'd', title: 'Creation', unit: 'Day');
    expect(days.formatTime(3), 'Day 3');
    expect(days.formatTime(2.5), 'Day 2.5');
    const bare = StudyTimeline(id: 'b', title: 'Bare', unit: '');
    expect(bare.formatTime(-4), '-4');
  });

  test('a verse finds the entries linked to it, in time order', () {
    final workspace = build();
    expect(workspace.timelineEntriesAt(9, 6, 1).map((e) => e.id), [
      'exodus',
      'solomon',
      'temple',
    ]);
    expect(workspace.timelineEntriesAt(9, 11, 43).single.id, 'solomon');
    expect(workspace.timelineEntriesAt(9, 12, 1), isEmpty);
  });

  test('entries live only in timelines; other items may join one', () {
    var workspace = build().putTimeline(
      const StudyTimeline(id: 'other', title: 'Other'),
    );
    final entry = StudyItem.of(workspace.timelineEntries.first);
    expect(workspace.canMoveItem(entry, null), isFalse);
    expect(workspace.canMoveItem(entry, 'g'), isFalse);
    expect(workspace.canMoveItem(entry, 'other'), isTrue);
    workspace = workspace.moveItem(entry, 'other');
    expect(workspace.entriesOf('other').single.id, entry.key.substring(15));
    // A timeline cannot move inside itself.
    final timeline = workspace.itemsIn('g').single;
    expect(workspace.canMoveItem(timeline, 'kings'), isFalse);
    final note = workspace.itemsIn('kings').first;
    expect(workspace.canMoveItem(note, 'other'), isTrue);
    // An entry without a timeline, or ending before it starts, is refused.
    expect(
      workspace
          .putTimelineEntry(exodus.copyWith(timelineId: 'missing'))
          .timelineEntries,
      workspace.timelineEntries,
    );
    expect(
      workspace
          .putTimelineEntry(exodus.withTime(start: 1, end: 0))
          .timelineEntries
          .firstWhere((e) => e.id == 'exodus')
          .start,
      -1446,
    );
  });

  test('deleting a timeline drops its entries and keeps its other items', () {
    final workspace = build().removeTimeline(build().timelineById('kings')!);
    expect(workspace.timelines, isEmpty);
    expect(workspace.timelineEntries, isEmpty);
    expect(workspace.notes.single.groupId, 'g');
  });

  test('deleting a group moves its timeline up', () {
    final workspace = build().removeGroup(build().groupById('g')!);
    expect(workspace.timelines.single.parentId, isNull);
    expect(workspace.timelineEntries, hasLength(3));
  });

  test('entries without a timeline, or misshapen ones, are dropped on load; '
      'a timeline in a vanished group moves to the top', () {
    final workspace = StudyWorkspace.fromJson({
      'id': 's',
      'name': 'Study',
      'ordered': true,
      'timelines': [
        {'id': 't', 'title': 'Days', 'unit': 'Day', 'parent': 'gone'},
        {'id': 't', 'title': 'Duplicate'},
        {'id': 'untitled', 'title': ''},
      ],
      'timelineEntries': [
        {'id': 'a', 'title': 'Light', 'timeline': 't', 'start': 1},
        {'id': 'b', 'title': 'Lost', 'timeline': 'gone', 'start': 1},
        {'id': 'c', 'title': 'Bad', 'timeline': 't', 'start': 'one'},
        {'id': 'd', 'title': 'Back', 'timeline': 't', 'start': 3, 'end': 2},
        {
          'id': 'e',
          'title': 'Rest',
          'timeline': 't',
          'start': 7,
          'verses': [
            {'book': 0, 'chapter': 2, 'verse': 1, 'endVerse': 3},
            {'book': 'x'},
          ],
          'future': 'kept',
        },
      ],
    })!;
    expect(workspace.timelines.single.title, 'Days');
    expect(workspace.timelines.single.parentId, isNull);
    expect(workspace.timelineEntries.map((e) => e.id), ['a', 'e']);
    final rest = workspace.timelineEntries.last;
    expect(rest.verses.single.reference, '2:1–3');
    expect(rest.toJson()['future'], 'kept');
  });

  test('a study without timelines stores none', () {
    final json = const StudyWorkspace(id: 's', name: 'Study').toJson();
    expect(json.containsKey('timelines'), isFalse);
    expect(json.containsKey('timelineEntries'), isFalse);
    expect(json.containsKey('timelineMarkers'), isFalse);
  });
}
