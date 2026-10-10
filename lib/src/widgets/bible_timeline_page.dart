import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'name_details.dart';
import 'timeline_chart.dart';

/// The timeline the Bible's events are shown on: calendar years, from the
/// creation in 4004 BC.
const bibleTimeline = StudyTimeline(
  id: 'bible-timeline',
  title: 'Bible timeline',
  scale: TimelineScale.calendar,
  note:
      'Dated from the creation in 4004 BC, after Floyd Nolen Jones\'s '
      '*Chronology of the Old Testament*, as [Theographic Bible Metadata]'
      '(https://github.com/robertrouse/theographic-bible-metadata) gives '
      'them (CC BY-SA 4.0).',
);

/// How long a [BibleEventEntry] lasted, as written: "40 days", "1 week".
String bibleEventDuration(BibleEventEntry event) {
  final unit = event.unit.endsWith('s')
      ? event.unit.substring(0, event.unit.length - 1)
      : event.unit;
  return '${event.duration} $unit${event.duration == 1 ? '' : 's'}';
}

/// [events] as entries of [bibleTimeline]: those lasting years as spans,
/// the rest as events, saying how long they lasted.
List<StudyTimelineEntry> bibleTimelineEntries(List<BibleEventEntry> events) => [
  for (final (order, event) in events.indexed) _entry(event, order),
];

StudyTimelineEntry _entry(BibleEventEntry event, int order) {
  final start = TimelineTime(event.year.toDouble());
  final years = event.unit == 'years' && event.duration > 0
      ? TimelineDuration(event.duration.toDouble(), TimelineDurationUnit.years)
      : null;
  final end = years == null ? null : bibleTimeline.addDuration(start, years);
  final lasted = end == null && event.duration > 0
      ? 'Lasted ${bibleEventDuration(event)}.'
      : '';
  return StudyTimelineEntry(
    id: '${event.id}',
    title: event.title,
    timelineId: bibleTimeline.id,
    start: start,
    end: end,
    duration: end == null ? null : years,
    verses: [
      for (final p in event.passages)
        StudyPassage(
          bookIndex: p.book - 1,
          chapter: p.chapter,
          verse: p.verse,
          endChapter: p.lastChapter == p.chapter ? null : p.lastChapter,
          endVerse: p.lastChapter == p.chapter && p.lastVerse == p.verse
              ? null
              : p.lastVerse,
        ),
    ],
    note: [lasted, event.note].where((s) => s.isNotEmpty).join(' '),
    order: order,
  );
}

/// The events of the Bible on a timeline, from the creation: drawn to
/// scale, listed beneath, each opening its verses in the reader and the
/// people and places taking part.
class BibleTimelinePage extends StatefulWidget {
  const BibleTimelinePage({
    super.key,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.bookmarks,
    this.sendRequest,
  });

  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final NameBookmarks? bookmarks;

  /// Stands in for the signal to Rust, for tests.
  final void Function(GetBibleEvents)? sendRequest;

  static Future<void> open(
    BuildContext context, {
    bool useEnglishBookNames = false,
    void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
    NameBookmarks? bookmarks,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BibleTimelinePage(
        useEnglishBookNames: useEnglishBookNames,
        onNavigateToPassage: onNavigateToPassage,
        bookmarks: bookmarks,
      ),
    ),
  );

  @override
  State<BibleTimelinePage> createState() => _BibleTimelinePageState();
}

class _BibleTimelinePageState extends State<BibleTimelinePage> {
  static int _nextRequestId = 1;
  StreamSubscription<RustSignalPack<BibleEvents>>? _sub;
  int? _requestId;
  List<BibleEventEntry>? _events;
  List<StudyTimelineEntry> _entries = const [];
  final _byId = <String, BibleEventEntry>{};

  @override
  void initState() {
    super.initState();
    _sub = BibleEvents.rustSignalStream.listen((pack) {
      final events = pack.message;
      if (!mounted || events.requestId != _requestId) return;
      setState(() {
        _events = events.events;
        _entries = bibleTimelineEntries(events.events);
        _byId
          ..clear()
          ..addAll({for (final e in events.events) '${e.id}': e});
      });
    });
    final request = GetBibleEvents(requestId: _requestId = _nextRequestId++);
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Opens a person's or place's page, from which a verse opens in the
  /// reader, closing the timeline.
  void _openName(BuildContext sheetContext, NameSummaryEntry name) {
    Navigator.pop(sheetContext);
    final navigate = widget.onNavigateToPassage;
    NameDetailsPage.open(
      context,
      id: name.id,
      title: name.name,
      useEnglishBookNames: widget.useEnglishBookNames,
      bookmarks: widget.bookmarks,
      onNavigateToPassage: navigate == null
          ? null
          : (book, chapter, verse) {
              Navigator.of(context)
                ..maybePop()
                ..maybePop();
              navigate(book, chapter, verse);
            },
    );
  }

  Widget _details(BuildContext sheetContext, StudyTimelineEntry entry) {
    final event = _byId[entry.id];
    if (event == null) return const SizedBox.shrink();
    final theme = Theme.of(sheetContext);
    Widget names(String label, IconData icon, List<NameSummaryEntry> list) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final name in list)
                    ActionChip(
                      avatar: Icon(icon),
                      label: Text(name.name),
                      tooltip: name.description.isEmpty
                          ? null
                          : name.description,
                      onPressed: () => _openName(sheetContext, name),
                    ),
                ],
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (event.people.isNotEmpty)
          names('People', Icons.person_outline, event.people),
        if (event.places.isNotEmpty)
          names('Places', Icons.place_outlined, event.places),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    if (events == null || events.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(bibleTimeline.title)),
        body: Center(
          child: events == null
              ? const CircularProgressIndicator()
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This database has no events. Update the Bible data to '
                    'see them.',
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      );
    }
    final navigate = widget.onNavigateToPassage;
    return TimelinePage(
      timeline: bibleTimeline,
      entries: _entries,
      useEnglishBookNames: widget.useEnglishBookNames,
      onOpenPassage: (passage) =>
          navigate?.call(passage.bookIndex, passage.chapter, passage.verse),
      entryDetails: _details,
    );
  }
}
