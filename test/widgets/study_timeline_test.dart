import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/study_timeline_editor.dart';
import 'package:haqor/src/widgets/study_workspace_panel.dart';
import 'package:haqor/src/widgets/timeline_chart.dart';

const _timeline = StudyTimeline(id: 'kings', title: 'Kings', era: true);
const _reign = StudyTimelineEntry(
  id: 'reign',
  title: 'Solomon reigns',
  timelineId: 'kings',
  start: -970,
  end: -931,
  verses: [StudyPassage(bookIndex: 9, chapter: 1, verse: 39)],
);
const _temple = StudyTimelineEntry(
  id: 'temple',
  title: 'Temple begun',
  timelineId: 'kings',
  start: -966,
  date: 'c.',
  note: 'In the fourth year',
  verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
);

Future<List<VerseEntry>> _chapter(int book, int chapter) async => [
  for (var v = 1; v <= 10; v++)
    VerseEntry(
      verse: v,
      text: 'אב גד',
      glosses: const [],
      morphologies: const [],
      roots: const [],
      names: const [],
      ketivs: const [],
      crossReferenceScores: const [],
    ),
];

void main() {
  test('entries pack into the fewest lanes, in time order', () {
    final slots = packTimelineLanes(
      [_temple, _reign, _temple.copyWith(title: 'Later')],
      x: (t) => t,
      width: (_) => 2,
      gap: 1,
    );
    // The reign starts first and spans the temple, which takes a new lane.
    expect(slots.map((s) => (s.entry.title, s.lane)), [
      ('Solomon reigns', 0),
      ('Temple begun', 1),
      ('Later', 2),
    ]);
    expect(timelineTicks(0, 100, 500), [0, 20, 40, 60, 80, 100]);
    expect(timelineExtent([_temple]), (start: -967, end: -965));
  });

  testWidgets('the outline shows a timeline, its strip and entries, and '
      'offers its actions', (tester) async {
    final workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
    ).putTimeline(_timeline).putTimelineEntry(_temple).putTimelineEntry(_reign);
    StudyTimeline? opened, edited, deleted;
    StudyTimelineEntry? editedEntry, removed;
    StudyPassage? openedPassage;
    final created = <(String, bool)>[];
    final createdTimelines = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 900,
            child: StudyWorkspacePanel(
              workspaces: [workspace],
              activeWorkspace: workspace,
              currentPassage: const StudyPassage(
                bookIndex: 0,
                chapter: 1,
                verse: 1,
              ),
              useEnglishBookNames: true,
              onCreate: () {},
              onSelect: (_) {},
              onRename: () {},
              onDelete: () {},
              onToggleHighlights: (_) {},
              onCreateGroup: (_) {},
              onEditGroup: (_) {},
              onDeleteGroup: (_) {},
              onBookmarkCurrent: (_) {},
              onOpenPassage: (p) => openedPassage = p,
              onEditPassage: (_) {},
              onUpdatePassage: (_) {},
              onRemovePassage: (_) {},
              onEditWord: (_) {},
              onUpdateWord: (_) {},
              onSwitchWordKind: (_) {},
              onRemoveWord: (_) {},
              onOpenWord: (_) {},
              onCreateNote: (_) {},
              onEditNote: (_) {},
              onUpdateNote: (_) {},
              onRemoveNote: (_) {},
              onMoveItem: (_, _, _) {},
              onCreateTimeline: createdTimelines.add,
              onOpenTimeline: (t) => opened = t,
              onEditTimeline: (t) => edited = t,
              onDeleteTimeline: (t) => deleted = t,
              onCreateTimelineEntry: (id, span) => created.add((id, span)),
              onEditTimelineEntry: (e) => editedEntry = e,
              onRemoveTimelineEntry: (e) => removed = e,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Kings'), findsOneWidget);
    // The strip's first and last times.
    expect(find.text('970 BC'), findsOneWidget);
    expect(find.text('931 BC'), findsOneWidget);
    // Entries in time order, with their times, verses and notes.
    expect(
      tester.getTopLeft(find.text('Solomon reigns')).dy,
      lessThan(tester.getTopLeft(find.text('Temple begun')).dy),
    );
    expect(find.text('970 BC – 931 BC'), findsOneWidget);
    expect(find.text('c. 966 BC'), findsOneWidget);
    expect(find.text('In the fourth year'), findsOneWidget);
    await tester.tap(find.text('1 Kings 6:1'));
    expect(openedPassage?.chapter, 6);

    await tester.tap(find.byKey(const ValueKey('timeline-strip-kings')));
    expect(opened?.id, 'kings');

    for (final (label, check) in [
      ('Add event', () => created.last == ('kings', false)),
      ('Add span', () => created.last == ('kings', true)),
      ('Edit timeline', () => edited?.id == 'kings'),
      ('Delete timeline', () => deleted?.id == 'kings'),
    ]) {
      await tester.tap(find.byTooltip('Timeline options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(check(), isTrue, reason: label);
    }

    await tester.tap(find.text('Temple begun'));
    expect(editedEntry?.id, 'temple');
    await tester.tap(find.byTooltip('Event options'));
    await tester.pumpAndSettle();
    // With one timeline there is nowhere to move an entry to.
    expect(find.text('Move to timeline'), findsNothing);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed?.id, 'temple');

    await tester.tap(find.byTooltip('Add study item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New timeline'));
    await tester.pumpAndSettle();
    expect(createdTimelines, [null]);
  });

  testWidgets('the entry editor saves a BC span and its linked verses', (
    tester,
  ) async {
    StudyTimelineEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimelineEntry>(
                context: context,
                builder: (_) => StudyTimelineEntryEditor(
                  initial: const StudyTimelineEntry(
                    id: 'new',
                    title: '',
                    timelineId: 'kings',
                    start: 0,
                    end: 0,
                    verses: [StudyPassage(bookIndex: 9, chapter: 6, verse: 1)],
                  ),
                  creating: true,
                  timelines: const [_timeline],
                  useEnglishBookNames: true,
                  loadChapter: _chapter,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('New timeline span'), findsOneWidget);
    expect(find.text('1 Kings 6:1'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Give the span a title.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-title')),
      'Building the temple',
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-start')),
      '966',
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-end')),
      '970',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    // 970 BC is before 966 BC.
    expect(find.text('The end must be at or after the start.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-end')),
      '959',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('timeline-entry-add-verses')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-entry-add-verses')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    // The same verse is linked once only.
    expect(find.text('1 Kings 6:1'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(saved?.title, 'Building the temple');
    expect(saved?.start, -966);
    expect(saved?.end, -959);
    expect(saved?.verses.single.reference, '6:1');
  });

  testWidgets('the timeline editor counts in a unit of its own', (
    tester,
  ) async {
    StudyTimeline? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<StudyTimeline>(
                context: context,
                builder: (_) => const StudyTimelineEditor(
                  initial: StudyTimeline(id: 't', title: '', era: true),
                  creating: true,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-unit')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('timeline-era')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('timeline-title')),
      'Creation week',
    );
    await tester.enterText(find.byKey(const ValueKey('timeline-unit')), 'Day');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(saved?.title, 'Creation week');
    expect(saved?.era, isFalse);
    expect(saved?.formatTime(3), 'Day 3');
  });

  testWidgets('the timeline page draws entries and opens their verses', (
    tester,
  ) async {
    StudyPassage? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TimelinePage(
                  timeline: _timeline,
                  entries: const [_temple, _reign],
                  useEnglishBookNames: true,
                  onOpenPassage: (p) => opened = p,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-mark-reign')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-mark-temple')), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-row-temple')));
    await tester.pumpAndSettle();
    expect(find.text('In the fourth year'), findsOneWidget);
    await tester.tap(find.text('1 Kings 6:1'));
    await tester.pumpAndSettle();
    expect(opened?.chapter, 6);
    // The page closes back to the reader.
    expect(find.text('open'), findsOneWidget);
  });
}
