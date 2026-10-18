import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'name_details.dart';
import 'timeline_chart.dart';

/// The timeline the Bible's events are shown on: calendar years, from the
/// creation in 4004 BC.
const bibleTimeline = StudyTimeline(
  id: bibleTimelineId,
  title: 'Bible timeline',
  scale: TimelineScale.calendar,
  note:
      'Dated from the creation in 4004 BC, after Floyd Nolen Jones\'s '
      '*Chronology of the Old Testament*, as [Theographic Bible Metadata]'
      '(https://github.com/robertrouse/theographic-bible-metadata) gives '
      'them (CC BY-SA 4.0).',
  categoryColors: {
    'Lifetimes': 0,
    'Births': 1,
    'Reigns': 3,
    'Judges': 4,
    'Prophets': 5,
    'Periods': 6,
    'Deaths': 7,
  },
);

/// What kind of event of the Bible [title] names, from how it reads:
/// "Birth of Seth" a birth, "Reign of Asa" a reign, the judges' times of
/// deliverance and subjugation together; else a period, for a [span], or
/// an event.
String bibleEventCategory(String title, {required bool span}) {
  if (title.startsWith('Birth of ')) return 'Births';
  if (title.startsWith('Death of ')) return 'Deaths';
  if (title.startsWith('Lifetime of ')) return 'Lifetimes';
  if (title.startsWith('Reign of ')) return 'Reigns';
  if (title.startsWith('Prophecies of ')) return 'Prophets';
  if (RegExp(
    r'^(Judgeship of|Deliverance by|Subjugation by|Oppression by|'
    r'Usurpation by|Philistine Dominion)',
  ).hasMatch(title)) {
    return 'Judges';
  }
  return span ? 'Periods' : 'Events';
}

/// The people [title] is about, where it reads "Birth of …", "Lifetime of
/// …", "Reign of …" or the like: "Birth of Jacob and Esau" is about Jacob
/// and Esau, "Death of Eli, Ark Captured" about Eli, and "Reign of Ahaziah
/// (Jehoahaz)" about him by either name.
List<String> _subjects(String title) {
  final match = RegExp(
    r'^(?:Birth|Death|Lifetime|Reign|Judgeship) of ([^,]+)',
  ).firstMatch(title);
  if (match == null) return const [];
  return [
    for (final name in match.group(1)!.split(RegExp(r' and |[()]')))
      if (name.trim().isNotEmpty) name.trim(),
  ];
}

/// How long a [BibleEventEntry] lasted, as written: "40 days", "1 week".
String bibleEventDuration(BibleEventEntry event) {
  final unit = event.unit.endsWith('s')
      ? event.unit.substring(0, event.unit.length - 1)
      : event.unit;
  return '${event.duration} $unit${event.duration == 1 ? '' : 's'}';
}

/// [events] as entries of [bibleTimeline]: those lasting years as spans,
/// the rest as events, saying how long they lasted; each in its category
/// (see [bibleEventCategory]), and a birth or death pinned to the life of
/// the one born or dying (see [TimelinePin]), or else a death to their
/// reign or judgeship, so that it is grouped under it.
List<StudyTimelineEntry> bibleTimelineEntries(List<BibleEventEntry> events) {
  final entries = [
    for (final (order, event) in events.indexed) _entry(event, order),
  ];
  // The spans of each person's life, reign or judgeship, by name.
  final spans = <String, List<StudyTimelineEntry>>{};
  for (final entry in entries) {
    if (!entry.isSpan) continue;
    for (final name in _subjects(entry.title)) {
      (spans[name] ??= []).add(entry);
    }
  }
  return [
    for (final entry in entries)
      switch (_pinFor(entry, spans)) {
        final pin? => entry.pinnedTo(pin),
        null => entry,
      },
  ];
}

/// How a birth or death is pinned to the span, among [spans] by name, of
/// the life (or, for a death, the reign or judgeship) of one it names
/// that runs over its year, a year either way; null for none.
TimelinePin? _pinFor(
  StudyTimelineEntry entry,
  Map<String, List<StudyTimelineEntry>> spans,
) {
  if (entry.isSpan) return null;
  final birth = entry.category == 'Births';
  if (!birth && entry.category != 'Deaths') return null;
  final at = bibleTimeline.positionOf(entry.start);
  // A life first, then (only for a death) a reign or judgeship.
  for (final kinds in [
    const ['Lifetimes'],
    if (!birth) const ['Reigns', 'Judges'],
  ]) {
    for (final name in _subjects(entry.title)) {
      for (final span in spans[name] ?? const <StudyTimelineEntry>[]) {
        if (!kinds.contains(span.category)) continue;
        final start = bibleTimeline.positionOf(span.start);
        final end = bibleTimeline.positionOf(span.last);
        if (at < start - 1 || at > end + 1) continue;
        final years = math.max(0, (at - start).round());
        return TimelinePin(
          span.id,
          TimelineDuration(years.toDouble(), TimelineDurationUnit.years),
        );
      }
    }
  }
  return null;
}

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
    category: bibleEventCategory(event.title, span: end != null),
    order: order,
  );
}

/// The id of the next request for the Bible's events, so that each page
/// and loader knows its answer.
int _nextRequestId = 1;

/// Asks for the Bible's events, as entries of [bibleTimeline]: for linking
/// a study's entries to them (see [TimelineLink]). [sendRequest] stands in
/// for the signal to Rust, for tests.
Future<List<StudyTimelineEntry>> loadBibleTimelineEntries({
  void Function(GetBibleEvents)? sendRequest,
}) async {
  final id = _nextRequestId++;
  final answer = Completer<List<BibleEventEntry>>();
  final sub = BibleEvents.rustSignalStream.listen((pack) {
    if (pack.message.requestId == id && !answer.isCompleted) {
      answer.complete(pack.message.events);
    }
  });
  try {
    final request = GetBibleEvents(requestId: id);
    if (sendRequest != null) {
      sendRequest(request);
    } else {
      request.sendSignalToRust();
    }
    return bibleTimelineEntries(
      await answer.future.timeout(const Duration(seconds: 30)),
    );
  } finally {
    await sub.cancel();
  }
}

/// The events of the Bible on a timeline, from the creation: drawn to
/// scale, listed beneath, each opening its verses in the reader and the
/// people and places taking part.
class BibleTimelinePage extends StatefulWidget {
  const BibleTimelinePage({
    super.key,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.ntGreek = false,
    this.onNtGreekChanged,
    this.onNavigateToPassage,
    this.bookmarks,
    this.initialEventId,
    this.sendRequest,
    this.linksOf,
    this.onOpenLink,
  });

  /// The links to its events from a study's timelines, and how one opens
  /// (see [TimelinePage.linksOf]).
  final List<TimelineLinkView> Function(StudyTimelineEntry entry)? linksOf;
  final ValueChanged<TimelineLink>? onOpenLink;

  /// The event to open on, its details shown.
  final String? initialEventId;

  final bool useEnglishBookNames;

  /// Show New Testament verses in Syriac script, as the reader is set to.
  final bool ntSyriac;

  /// Show New Testament verses in Greek, as the reader is set to, and where
  /// a name page's switch between the Greek and the Peshitta is reported.
  final bool ntGreek;
  final ValueChanged<bool>? onNtGreekChanged;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final NameBookmarks? bookmarks;

  /// Stands in for the signal to Rust, for tests.
  final void Function(GetBibleEvents)? sendRequest;

  static Future<void> open(
    BuildContext context, {
    String? initialEventId,
    bool useEnglishBookNames = false,
    bool ntSyriac = false,
    bool ntGreek = false,
    ValueChanged<bool>? onNtGreekChanged,
    void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
    NameBookmarks? bookmarks,
    void Function(GetBibleEvents)? sendRequest,
    List<TimelineLinkView> Function(StudyTimelineEntry entry)? linksOf,
    ValueChanged<TimelineLink>? onOpenLink,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BibleTimelinePage(
        initialEventId: initialEventId,
        useEnglishBookNames: useEnglishBookNames,
        ntSyriac: ntSyriac,
        ntGreek: ntGreek,
        onNtGreekChanged: onNtGreekChanged,
        onNavigateToPassage: onNavigateToPassage,
        bookmarks: bookmarks,
        sendRequest: sendRequest,
        linksOf: linksOf,
        onOpenLink: onOpenLink,
      ),
    ),
  );

  @override
  State<BibleTimelinePage> createState() => _BibleTimelinePageState();
}

class _BibleTimelinePageState extends State<BibleTimelinePage> {
  /// The NT text a name page was last switched to, for the next one opened.
  late bool _ntGreek = widget.ntGreek;

  void _ntGreekChanged(bool greek) {
    _ntGreek = greek;
    widget.onNtGreekChanged?.call(greek);
  }

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
      ntSyriac: widget.ntSyriac,
      ntGreek: _ntGreek,
      onNtGreekChanged: _ntGreekChanged,
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
      initialSelectedId: widget.initialEventId,
      showInitialSelected: widget.initialEventId != null,
      useEnglishBookNames: widget.useEnglishBookNames,
      onOpenPassage: (passage) =>
          navigate?.call(passage.bookIndex, passage.chapter, passage.verse),
      entryDetails: _details,
      // Births and deaths fold under the lives they belong to.
      collapseGroups: true,
      linksOf: widget.linksOf,
      onOpenLink: widget.onOpenLink,
    );
  }
}
