import 'package:flutter/material.dart';

import '../bindings/bindings.dart';
import '../event_sequence.dart';
import '../study_workspace.dart';
import 'bible_timeline_page.dart';
import 'event_sequence_page.dart';
import 'timeline_chart.dart';
import 'timeline_wheel.dart';

/// Presentation choices for broad sections whose dated spans are useful.
/// Their passage-based order remains available without replacing the dates.
/// Short narratives with only coarse dates continue to open as order graphs.
const bibleDatedSections = {
  'beginnings',
  'abraham',
  'jacob-household',
  'joseph',
  'moses-exodus',
  'conquest',
  'judges',
  'united-kingdom',
  'israel-kings',
  'judah-kings',
  'prophets',
};

/// A section's dated members and the lifetimes that give its births and
/// deaths context. Nested sections stay behind their summary event. The
/// enclosing lifetime is omitted so it cannot open itself recursively.
List<BibleEventEntry> bibleSubTimelineEvents(
  EventSequenceEntry section,
  Iterable<BibleEventEntry> events,
) {
  final members = section.events.toSet();
  final subjects = {
    for (final e in events)
      if (members.contains(e.id)) ...bibleEventSubjects(e.title),
  };
  return [
    for (final e in events)
      if (e.id != section.expands &&
          (members.contains(e.id) ||
              (e.title.startsWith('Lifetime of ') &&
                  bibleEventSubjects(e.title).any(subjects.contains))))
        e,
  ];
}

/// Open a Bible section as a dated sub-timeline or a narrative order graph.
Future<void> openBibleSection(
  BuildContext context, {
  required EventSequenceEntry section,
  required BibleSequences sequences,
  required Map<int, BibleEventEntry> events,
  required bool useEnglishBookNames,
  required ValueChanged<StudyPassage> onOpenPassage,
  int? focusEventId,
}) {
  if (!bibleDatedSections.contains(section.key)) {
    return EventSequencePage.open(
      context,
      sequence: section,
      sequences: sequences,
      events: events,
      useEnglishBookNames: useEnglishBookNames,
      onOpenPassage: onOpenPassage,
      focusEventId: focusEventId,
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BibleSubTimelinePage(
        section: section,
        sequences: sequences,
        events: events,
        useEnglishBookNames: useEnglishBookNames,
        onOpenPassage: onOpenPassage,
        focusEventId: focusEventId,
      ),
    ),
  );
}

/// A calendar-scaled view of one part of the Bible timeline, preserving
/// reign lengths, ministry spans and overlapping lives from the source.
class BibleSubTimelinePage extends StatelessWidget {
  const BibleSubTimelinePage({
    super.key,
    required this.section,
    required this.sequences,
    required this.events,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.focusEventId,
  });

  final EventSequenceEntry section;
  final BibleSequences sequences;
  final Map<int, BibleEventEntry> events;
  final bool useEnglishBookNames;
  final ValueChanged<StudyPassage> onOpenPassage;
  final int? focusEventId;

  @override
  Widget build(BuildContext context) {
    final timeline = StudyTimeline(
      id: 'bible-section:${section.key}',
      parentId: bibleTimeline.id,
      title: section.title,
      scale: TimelineScale.calendar,
      categoryColors: bibleTimeline.categoryColors,
      note:
          '${bibleTimeline.note}\n\n'
          'This sub-timeline retains that chronology, including its '
          'uncertain dates. Overlapping bars show overlapping lifetimes, '
          'reigns and ministries. Event order shows the separate '
          'passage-based ordering.\n\n${section.note}',
    );
    final entries = [
      for (final e in bibleTimelineEntries(
        bibleSubTimelineEvents(section, events.values),
      ))
        e.copyWith(timelineId: timeline.id),
    ];
    // A deep link selects the summary that opens the next nested section.
    final path = focusEventId == null
        ? const <EventSequenceEntry>[]
        : sequences.pathTo(focusEventId!);
    final at = path.indexWhere((s) => s.key == section.key);
    final initial = at >= 0 && at + 1 < path.length
        ? path[at + 1].expands
        : focusEventId;
    void returnToReader(StudyPassage passage) {
      Navigator.pop(context);
      onOpenPassage(passage);
    }

    return TimelinePage(
      timeline: timeline,
      wheelCycle: timelineChronologyCycle(timeline, entries),
      entries: entries,
      useEnglishBookNames: useEnglishBookNames,
      onOpenPassage: onOpenPassage,
      initialSelectedId: initial?.toString(),
      showInitialSelected: initial != null,
      collapseGroups: true,
      onOpenEntry: (entry) {
        final inner = sequences.expanding[int.tryParse(entry.id)];
        if (inner == null || inner.key == section.key) return false;
        openBibleSection(
          context,
          section: inner,
          sequences: sequences,
          events: events,
          useEnglishBookNames: useEnglishBookNames,
          onOpenPassage: returnToReader,
          focusEventId: entry.id == initial?.toString() ? focusEventId : null,
        );
        return true;
      },
      actions: [
        IconButton(
          key: const ValueKey('bible-section-event-order'),
          tooltip: 'Event order',
          icon: const Icon(Icons.account_tree_outlined),
          onPressed: () => EventSequencePage.open(
            context,
            sequence: section,
            sequences: sequences,
            events: events,
            useEnglishBookNames: useEnglishBookNames,
            onOpenPassage: returnToReader,
          ),
        ),
      ],
    );
  }
}
