import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../external_link.dart';
import '../study_workspace.dart';
import 'bible_timeline_page.dart';
import 'place_map.dart';
import 'timeline_chart.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart'
    show
        BibleRefPreviewDialog,
        CanonDistribution,
        OccurrenceVerseRow,
        VerseModeIcon,
        WordInfoSheet;

/// The icon for a kind of name: `person`, `place` or `other`.
IconData nameKindIcon(String kind) => switch (kind) {
  'person' => Icons.person_outline,
  'place' => Icons.place_outlined,
  _ => Icons.auto_awesome_outlined,
};

/// A word's person or place in brief, at the head of its word sheet: who or
/// what the word names here, which a shared name ("Zechariah") cannot say.
/// Tapping opens [NameDetailsPage].
class NameCard extends StatelessWidget {
  const NameCard({super.key, required this.name, required this.onOpen});

  final NameSummaryEntry name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final details = [
      if (name.description.isNotEmpty) name.description,
      if (name.origin.isNotEmpty) name.origin,
    ].join(' · ');
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(nameKindIcon(name.kind), color: scheme.primary),
        title: Text(name.name, style: theme.textTheme.titleMedium),
        subtitle: Text(
          [
            if (details.isNotEmpty) details,
            mentionsLabel(name.occurrences),
          ].join('\n'),
        ),
        isThreeLine: details.isNotEmpty,
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

String mentionsLabel(int occurrences) =>
    'Named $occurrences time${occurrences == 1 ? '' : 's'} in the Hebrew Bible';

/// How many New Testament verses name it, following [mentionsLabel] or
/// [alone]: its words are not tagged, so it is counted by verse.
String newTestamentLabel(int verses, {bool alone = false}) =>
    '${alone ? 'Named in' : 'in'} $verses New Testament '
    'verse${verses == 1 ? '' : 's'}';

/// A position in Google Maps, as a search for it, so the pin lands on it.
Uri googleMapsUri(double latitude, double longitude) => Uri.https(
  'www.google.com',
  '/maps/search/',
  {'api': '1', 'query': '$latitude,$longitude'},
);

/// A position in Google Earth, seen from 5 km, tilted to show the lie of
/// the land.
Uri googleEarthUri(double latitude, double longitude) => Uri.parse(
  'https://earth.google.com/web/@$latitude,$longitude,0a,5000d,35y,0h,45t,0r',
);

/// How a name page bookmarks its person or place in the active study.
class NameBookmarks {
  const NameBookmarks({required this.isBookmarked, required this.toggle});

  final bool Function(int id) isBookmarked;

  /// Bookmarks the name, or removes it when it is there: true when it ends
  /// up bookmarked.
  final Future<bool> Function(StudyName name) toggle;
}

/// What a link says the other is, in the singular.
String _relationLabel(String relation) => switch (relation) {
  'father' => 'Father',
  'mother' => 'Mother',
  'sibling' => 'Siblings',
  'partner' => 'Married to',
  'child' => 'Children',
  'founder' => 'Founded by',
  'inhabitant' => 'People of the place',
  _ => relation,
};

/// TIPNR's flag on a link, in words.
String? _flagLabel(String flag) => switch (flag) {
  'a' => 'ancestor',
  'd' => 'their descendants',
  'f' => 'founder',
  '?' => 'uncertain',
  _ => null,
};

/// Everything known of a person, place or other named thing: what the text
/// says of them, their family and other links (each opening its own page),
/// the forms of their name (each opening its word sheet), where a place may
/// have been, and every verse naming them, the name marked in each.
class NameDetailsPage extends StatefulWidget {
  const NameDetailsPage({
    super.key,
    required this.id,
    this.title,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.onNavigateToPassage,
    this.sendRequest,
    this.sendVerseTextsRequest,
    this.sendTimelineRequest,
    this.basemap,
    this.bookmarks,
  });

  /// The route's name, so going to a passage can close every page of names
  /// opened one from another.
  static const routeName = 'name-details';

  final int id;

  /// Shown until the record arrives.
  final String? title;
  final bool useEnglishBookNames;

  /// Show New Testament verses in Syriac script, as the reader is set to.
  final bool ntSyriac;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Stand in for the signals to Rust, for tests.
  final void Function(GetNameEntity)? sendRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;
  final void Function(GetBibleEvents)? sendTimelineRequest;
  final Basemap? basemap;

  /// Bookmarking in the active study; without it the page has no bookmark.
  final NameBookmarks? bookmarks;

  /// Open the page for [id] over [context].
  static Future<void> open(
    BuildContext context, {
    required int id,
    String? title,
    bool useEnglishBookNames = false,
    bool ntSyriac = false,
    void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
    NameBookmarks? bookmarks,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => NameDetailsPage(
        id: id,
        title: title,
        useEnglishBookNames: useEnglishBookNames,
        ntSyriac: ntSyriac,
        onNavigateToPassage: onNavigateToPassage,
        bookmarks: bookmarks,
      ),
    ),
  );

  @override
  State<NameDetailsPage> createState() => _NameDetailsPageState();
}

class _NameDetailsPageState extends State<NameDetailsPage> {
  static int _nextRequestId = 1;
  StreamSubscription<RustSignalPack<NameEntityInfo>>? _sub;
  int? _requestId;
  NameEntityInfo? _info;

  /// The verses' text, read as their rows scroll into view.
  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );

  /// Show the verses in English, as the word sheet's Occurrences tab does.
  bool _englishOnly = false;

  /// The books the verse list is narrowed to (1-based); empty for all.
  final Set<int> _books = {};

  @override
  void initState() {
    super.initState();
    _sub = NameEntityInfo.rustSignalStream.listen((pack) {
      final info = pack.message;
      if (!mounted || info.requestId != _requestId) return;
      setState(() => _info = info);
    });
    final request = GetNameEntity(
      requestId: _requestId = _nextRequestId++,
      id: widget.id,
    );
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
    occurrenceVerseEnglishOnlyEnabled().then((enabled) {
      if (mounted) setState(() => _englishOnly = enabled);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _verseTexts.dispose();
    super.dispose();
  }

  void _toggleEnglishOnly() {
    setState(() => _englishOnly = !_englishOnly);
    setOccurrenceVerseEnglishOnlyEnabled(_englishOnly);
  }

  void _openOther(NameSummaryEntry other) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: NameDetailsPage.routeName),
      builder: (_) => NameDetailsPage(
        id: other.id,
        title: other.name,
        useEnglishBookNames: widget.useEnglishBookNames,
        ntSyriac: widget.ntSyriac,
        onNavigateToPassage: widget.onNavigateToPassage,
        sendRequest: widget.sendRequest,
        sendVerseTextsRequest: widget.sendVerseTextsRequest,
        sendTimelineRequest: widget.sendTimelineRequest,
        basemap: widget.basemap,
        bookmarks: widget.bookmarks,
      ),
    ),
  );

  /// Bookmark the person or place in the active study, or remove it.
  Future<void> _toggleBookmark(
    NameBookmarks bookmarks,
    NameSummaryEntry name,
  ) async {
    await bookmarks.toggle(
      StudyName(
        id: name.id,
        name: name.name,
        kind: name.kind,
        description: name.description,
      ),
    );
    if (mounted) setState(() {});
  }

  /// Go to a verse in the reader, closing every page of names on the way.
  void Function(int bookIndex, int chapter, int verse)? get _navigate {
    final navigate = widget.onNavigateToPassage;
    if (navigate == null) return null;
    return (bookIndex, chapter, verse) {
      Navigator.of(
        context,
      ).popUntil((route) => route.settings.name != NameDetailsPage.routeName);
      navigate(bookIndex, chapter, verse);
    };
  }

  /// Go to a verse naming it, or with no reader to go to, show it.
  void _openVerse(NameVerse verse) {
    final bookIndex = verse.book - 1;
    final navigate = _navigate;
    if (navigate != null) {
      navigate(bookIndex, verse.chapter, verse.verse);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => BibleRefPreviewDialog(
        displayRef: _reference(verse),
        bookIndex: bookIndex,
        chapter: verse.chapter,
        verse: verse.verse,
      ),
    );
  }

  String _reference(NameVerse verse) =>
      '${bookDisplayName(verse.book - 1, useEnglish: widget.useEnglishBookNames)} '
      '${verse.chapter}:${verse.verse}';

  /// The word sheet of a form of the name, as for a word in the reader.
  void _openForm(NameFormEntry form) {
    final navigate = _navigate;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => WordInfoSheet(
        word: form.hebrew,
        syriac: false,
        sendVerseTextsRequest: widget.sendVerseTextsRequest,
        useEnglishBookNames: widget.useEnglishBookNames,
        nameBookmarks: widget.bookmarks,
        reportContext: {'nameForm': form.hebrew, 'nameEntity': widget.id},
        onNavigateToPassage: navigate == null
            ? null
            : (bookIndex, chapter, verse) {
                Navigator.pop(sheet);
                navigate(bookIndex, chapter, verse);
              },
      ),
    );
  }

  Widget _verseRow(NameVerse verse) => OccurrenceVerseRow(
    key: ValueKey('${verse.book}:${verse.chapter}:${verse.verse}'),
    cache: _verseTexts,
    displayRef: _reference(verse),
    bookIndex: verse.book - 1,
    chapter: verse.chapter,
    verse: verse.verse,
    highlightWords: const [],
    positions: verse.positions,
    englishOnly: _englishOnly,
    syriac: widget.ntSyriac && verse.book >= 40,
    useEnglishBookNames: widget.useEnglishBookNames,
    onTap: () => _openVerse(verse),
  );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || !info.found) {
      return Scaffold(
        appBar: _appBar(info),
        body: info == null
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Nothing is known of this name.')),
      );
    }
    final tabs = [
      const Tab(text: 'About'),
      if (info.verses.isNotEmpty) Tab(text: 'Verses (${info.verses.length})'),
      if (info.events.isNotEmpty) Tab(text: 'Timeline (${info.events.length})'),
    ];
    final views = [
      _about(context, info),
      if (info.verses.isNotEmpty) _verses(context, info),
      if (info.events.isNotEmpty) _timeline(context, info),
    ];
    if (tabs.length == 1) {
      return Scaffold(appBar: _appBar(info), body: views.single);
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: _appBar(info, bottom: TabBar(tabs: tabs, isScrollable: true)),
        body: TabBarView(children: views),
      ),
    );
  }

  PreferredSizeWidget _appBar(
    NameEntityInfo? info, {
    PreferredSizeWidget? bottom,
  }) => AppBar(
    title: Text(info?.summary.name ?? widget.title ?? ''),
    bottom: bottom,
    actions: [
      if (widget.bookmarks case final bookmarks?)
        if (info != null && info.found)
          bookmarks.isBookmarked(info.summary.id)
              ? IconButton(
                  tooltip: 'Remove from the study',
                  icon: const Icon(Icons.bookmark),
                  onPressed: () => _toggleBookmark(bookmarks, info.summary),
                )
              : IconButton(
                  tooltip: 'Bookmark in the study',
                  icon: const Icon(Icons.bookmark_border),
                  onPressed: () => _toggleBookmark(bookmarks, info.summary),
                ),
    ],
  );

  /// The side margin keeping a readable measure on a wide window.
  double _side(BuildContext context) =>
      20 + math.max(0.0, (MediaQuery.sizeOf(context).width - 760) / 2);

  TextStyle? _heading(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.primary,
    );
  }

  Widget _footnote(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Who or what it is: where a place was, what the text says, its family
  /// and other links, and the forms of its name.
  Widget _about(BuildContext context, NameEntityInfo info) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = info.summary;
    final heading = _heading(context);
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: heading),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );

    final kind = [
      if (info.category.isNotEmpty) info.category,
      if (summary.origin.isNotEmpty) summary.origin,
    ].join(' · ');
    final linkGroups = <String, List<NameLinkEntry>>{};
    for (final link in info.links) {
      linkGroups.putIfAbsent(link.relation, () => []).add(link);
    }
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final side = _side(context);

    final head = <Widget>[
      Row(
        children: [
          Icon(nameKindIcon(summary.kind), color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kind,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      if (summary.description.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(summary.description, style: theme.textTheme.titleMedium),
      ],
      if (info.locations.isNotEmpty) ...[
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            child: PlaceMap(
              basemap: widget.basemap,
              pins: [
                for (final (i, location) in info.locations.indexed)
                  placePin(
                    location,
                    label: i == 0 ? summary.name : '',
                    primary: i == 0,
                  ),
              ],
            ),
          ),
        ),
        section('Where it was', [
          for (final (i, location) in info.locations.indexed)
            _LocationRow(location: location, likeliest: i == 0),
        ]),
      ],
      if (info.text.isNotEmpty)
        section('In the text', [
          for (final line in info.text.split('\n'))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: theme.textTheme.bodyMedium),
            ),
        ]),
      for (final MapEntry(key: relation, value: links) in linkGroups.entries)
        section(_relationLabel(relation), [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final link in links)
                ActionChip(
                  avatar: Icon(nameKindIcon(link.other.kind), size: 18),
                  label: Text(
                    [
                      link.other.name,
                      if (_flagLabel(link.flag) case final flag?) '($flag)',
                    ].join(' '),
                  ),
                  tooltip: link.other.description.isEmpty
                      ? null
                      : link.other.description,
                  onPressed: () => _openOther(link.other),
                ),
            ],
          ),
        ]),
      if (info.forms.isNotEmpty)
        section('Forms of the name', [
          for (final form in info.forms)
            _FormRow(form: form, onOpen: () => _openForm(form)),
        ]),
    ];
    final foot = Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        [
          'From STEP Bible\'s TIPNR (Tyndale House Cambridge, CC BY 4.0)',
          if (info.locations.any((l) => l.confidence >= 0))
            'Locations from OpenBible.info (CC BY 4.0)',
          // Haqor's own identifications carry a label but no confidence;
          // TIPNR's positions carry neither.
          if (info.locations.any((l) => l.confidence < 0 && l.label.isNotEmpty))
            "Location as Haqor identifies it, in place of OpenBible.info's "
                '(see About)',
        ].join('. '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(side, 8, side, 24 + bottom),
      children: [...head, foot],
    );
  }

  /// The verses naming it, narrowed by book.
  Widget _verses(BuildContext context, NameEntityInfo info) {
    final summary = info.summary;
    // How often each book names it, for the book filter, and the verses in
    // the books chosen.
    // A New Testament verse names it by verse alone, and counts once.
    final countsByBook = <int, int>{};
    var newTestament = 0;
    for (final verse in info.verses) {
      countsByBook[verse.book] =
          (countsByBook[verse.book] ?? 0) + math.max(verse.positions.length, 1);
      if (verse.book >= 40) newTestament++;
    }
    final verses = _books.isEmpty
        ? info.verses
        : [
            for (final verse in info.verses)
              if (_books.contains(verse.book)) verse,
          ];
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final side = _side(context);
    final head = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                [
                  if (summary.occurrences > 0 || newTestament == 0)
                    mentionsLabel(summary.occurrences),
                  if (newTestament > 0)
                    newTestamentLabel(
                      newTestament,
                      alone: summary.occurrences == 0,
                    ),
                  if (_books.isNotEmpty)
                    '${verses.length} of ${info.verses.length} verses'
                  else if (newTestament == 0 &&
                      info.verses.length != summary.occurrences)
                    '${info.verses.length} verses',
                ].join(' · '),
                style: _heading(context),
              ),
            ),
            IconButton(
              tooltip: _englishOnly
                  ? 'Show Hebrew verse text'
                  : 'Show English-only verse text',
              icon: VerseModeIcon(englishOnly: _englishOnly),
              onPressed: _toggleEnglishOnly,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: CanonDistribution(
          countsByBook: countsByBook,
          selectedBooks: _books,
          useEnglishBookNames: widget.useEnglishBookNames,
          onSelect: (books) => setState(() {
            _books
              ..clear()
              ..addAll(books);
          }),
        ),
      ),
    ];

    // The verses are built as they scroll into view, so a name in a thousand
    // verses costs no more to open than one in three.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 8, side, 0),
          sliver: SliverList.list(children: head),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side - 4, 0, side - 4, 24 + bottom),
          sliver: SliverList.builder(
            itemCount: verses.length,
            itemBuilder: (context, i) => _verseRow(verses[i]),
          ),
        ),
      ],
    );
  }

  /// Opens the Bible timeline, at [eventId]'s event if one is given.
  void _openTimeline({String? eventId}) => BibleTimelinePage.open(
    context,
    initialEventId: eventId,
    useEnglishBookNames: widget.useEnglishBookNames,
    ntSyriac: widget.ntSyriac,
    bookmarks: widget.bookmarks,
    onNavigateToPassage: _navigate,
    sendRequest: widget.sendTimelineRequest,
  );

  /// The events it takes part in: drawn to scale as a timeline of their
  /// own, and listed, each opening on the Bible timeline.
  Widget _timeline(BuildContext context, NameEntityInfo info) {
    final theme = Theme.of(context);
    final entries = bibleTimelineEntries(info.events);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final side = _side(context);
    final first = entries.first.start;
    final last = entries
        .map((e) => e.last)
        .reduce(
          (a, b) => bibleTimeline.positionOf(a) >= bibleTimeline.positionOf(b)
              ? a
              : b,
        );
    final span = first == last
        ? bibleTimeline.formatTime(first)
        : '${bibleTimeline.formatTime(first)} – '
              '${bibleTimeline.formatTime(last)}';
    return ListView(
      padding: EdgeInsets.fromLTRB(0, 8, 0, 24 + bottom),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${info.events.length == 1 ? '1 event' : '${info.events.length} events'}'
                  ' · $span',
                  style: _heading(context),
                ),
              ),
              TextButton.icon(
                onPressed: _openTimeline,
                icon: const Icon(Icons.timeline),
                label: const Text('Bible timeline'),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final extent = timelineExtent(bibleTimeline, entries);
            final label = math.min(width / 3, 140.0);
            final ppu = math.max(
              1e-6,
              (width - TimelineChart.padding * 2 - label) /
                  (extent.end - extent.start),
            );
            return SingleChildScrollView(
              key: const ValueKey('name-timeline-chart'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8),
              child: TimelineChart(
                timeline: bibleTimeline,
                entries: entries,
                pixelsPerUnit: ppu,
                onTapEntry: (entry) => _openTimeline(eventId: entry.id),
              ),
            );
          },
        ),
        const Divider(height: 1),
        for (final entry in entries)
          ListTile(
            key: ValueKey('name-event-${entry.id}'),
            contentPadding: EdgeInsets.symmetric(horizontal: side),
            leading: Icon(
              timelineEntryIcon(entry),
              color: entry.isSpan
                  ? theme.colorScheme.primary
                  : theme.colorScheme.tertiary,
            ),
            title: Text(entry.title),
            subtitle: Text(
              [
                timelineEntryTime(bibleTimeline, entry),
                for (final passage in entry.verses)
                  '${bookDisplayName(passage.bookIndex, useEnglish: widget.useEnglishBookNames)} '
                      '${passage.reference}',
              ].join(' · '),
            ),
            onTap: () => _openTimeline(eventId: entry.id),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: _footnote(
            context,
            'Events from Theographic Bible Metadata (CC BY-SA 4.0), dated '
            'from the creation in 4004 BC',
          ),
        ),
      ],
    );
  }
}

/// A place's location as a pin on a [PlaceMap]: a region as its ground, a
/// river as its course.
MapPin placePin(
  PlaceLocationEntry location, {
  required String label,
  int? id,
  bool primary = true,
}) => MapPin(
  latitude: location.latitude,
  longitude: location.longitude,
  label: label,
  id: id,
  primary: primary,
  confidence: location.confidence < 0 ? null : location.confidence,
  estimated: location.estimated,
  kind: location.kind,
  area: location.area,
  line: location.line,
);

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.location, required this.likeliest});

  final PlaceLocationEntry location;
  final bool likeliest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidence = location.estimated
        ? 'estimated · low certainty'
        : location.confidence < 0
        ? null
        : '${(location.confidence / 10).round()}% confident';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        likeliest ? Icons.location_on : Icons.location_on_outlined,
        color: likeliest ? theme.colorScheme.primary : null,
      ),
      title: Text(
        location.label.isEmpty ? 'Position given by TIPNR' : location.label,
      ),
      subtitle: Text(
        [if (location.kind.isNotEmpty) location.kind, ?confidence].join(' · '),
      ),
      trailing: PopupMenuButton<Uri>(
        tooltip: 'Open in Google Maps or Google Earth',
        icon: const Icon(Icons.open_in_new, size: 20),
        onSelected: (uri) => openExternalLink(uri),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: googleMapsUri(location.latitude, location.longitude),
            child: const ListTile(
              leading: Icon(Icons.map_outlined),
              title: Text('Google Maps'),
            ),
          ),
          PopupMenuItem(
            value: googleEarthUri(location.latitude, location.longitude),
            child: const ListTile(
              leading: Icon(Icons.public),
              title: Text('Google Earth'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A form of the name, its Hebrew a link to its word sheet.
class _FormRow extends StatelessWidget {
  const _FormRow({required this.form, required this.onOpen});

  final NameFormEntry form;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = theme.colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    form.english.join(', '),
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    form.significance,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Open the word',
              child: Text(
                form.hebrew,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'Noto Serif Hebrew',
                  fontFamilyFallback: const ['Cardo'],
                  fontSize: 22,
                  color: link,
                  decoration: TextDecoration.underline,
                  decorationColor: link.withValues(alpha: .5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The places a chapter names, on a map and in a list: tapping either opens
/// the place's page.
class ChapterPlacesSheet extends StatefulWidget {
  const ChapterPlacesSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.sendRequest,
    this.basemap,
    this.bookmarks,
  });

  /// Zero-based, as the reader counts books.
  final int bookIndex;
  final int chapter;
  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final void Function(GetChapterPlaces)? sendRequest;
  final Basemap? basemap;
  final NameBookmarks? bookmarks;

  @override
  State<ChapterPlacesSheet> createState() => _ChapterPlacesSheetState();
}

class _ChapterPlacesSheetState extends State<ChapterPlacesSheet> {
  static int _nextRequestId = 1;
  StreamSubscription<RustSignalPack<ChapterPlaces>>? _sub;
  int? _requestId;
  ChapterPlaces? _places;

  @override
  void initState() {
    super.initState();
    _sub = ChapterPlaces.rustSignalStream.listen((pack) {
      final places = pack.message;
      if (!mounted || places.requestId != _requestId) return;
      setState(() => _places = places);
    });
    final request = GetChapterPlaces(
      requestId: _requestId = _nextRequestId++,
      book: widget.bookIndex + 1,
      chapter: widget.chapter,
    );
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

  void _open(NameSummaryEntry place) => NameDetailsPage.open(
    context,
    id: place.id,
    title: place.name,
    useEnglishBookNames: widget.useEnglishBookNames,
    bookmarks: widget.bookmarks,
    onNavigateToPassage: widget.onNavigateToPassage == null
        ? null
        : (book, chapter, verse) {
            Navigator.of(context).maybePop();
            widget.onNavigateToPassage!(book, chapter, verse);
          },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final places = _places;
    final title =
        'Places in ${bookDisplayName(widget.bookIndex, useEnglish: widget.useEnglishBookNames)} '
        '${widget.chapter}';
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: places == null
                ? const Center(child: CircularProgressIndicator())
                : places.places.isEmpty
                ? Center(
                    child: Text(
                      'This chapter names no place with a known location.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: PlaceMap(
                          basemap: widget.basemap,
                          pins: [
                            for (final entry in places.places)
                              placePin(
                                entry.location,
                                label: entry.place.name,
                                id: entry.place.id,
                              ),
                          ],
                          onPinTap: (pin) => _open(
                            places.places
                                .firstWhere((p) => p.place.id == pin.id)
                                .place,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: ListView(
                          children: [
                            for (final entry in places.places)
                              ListTile(
                                leading: const Icon(Icons.place_outlined),
                                title: Text(entry.place.name),
                                subtitle: Text(
                                  [
                                    if (entry.place.origin.isNotEmpty)
                                      entry.place.origin,
                                    'verse${entry.verses.length == 1 ? '' : 's'} '
                                        '${entry.verses.join(', ')}',
                                  ].join(' · '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(entry.place),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The people a chapter names, in the order it first names them: who each is,
/// how they are related to the others named there, and the verses naming
/// them. Tapping one opens their page.
class ChapterPeopleSheet extends StatefulWidget {
  const ChapterPeopleSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.sendRequest,
    this.bookmarks,
  });

  /// Zero-based, as the reader counts books.
  final int bookIndex;
  final int chapter;
  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final void Function(GetChapterPeople)? sendRequest;
  final NameBookmarks? bookmarks;

  @override
  State<ChapterPeopleSheet> createState() => _ChapterPeopleSheetState();
}

class _ChapterPeopleSheetState extends State<ChapterPeopleSheet> {
  static int _nextRequestId = 1;
  StreamSubscription<RustSignalPack<ChapterPeople>>? _sub;
  int? _requestId;
  ChapterPeople? _people;

  @override
  void initState() {
    super.initState();
    _sub = ChapterPeople.rustSignalStream.listen((pack) {
      final people = pack.message;
      if (!mounted || people.requestId != _requestId) return;
      setState(() => _people = people);
    });
    final request = GetChapterPeople(
      requestId: _requestId = _nextRequestId++,
      book: widget.bookIndex + 1,
      chapter: widget.chapter,
    );
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

  void _open(NameSummaryEntry person) => NameDetailsPage.open(
    context,
    id: person.id,
    title: person.name,
    useEnglishBookNames: widget.useEnglishBookNames,
    bookmarks: widget.bookmarks,
    onNavigateToPassage: widget.onNavigateToPassage == null
        ? null
        : (book, chapter, verse) {
            Navigator.of(context).maybePop();
            widget.onNavigateToPassage!(book, chapter, verse);
          },
  );

  /// How [entry] is related to the others, by kind: "Father: Lamech".
  static String _relations(
    ChapterPersonEntry entry,
    Map<int, NameSummaryEntry> byId,
  ) {
    final groups = <String, List<String>>{};
    for (final relation in entry.relations) {
      final other = byId[relation.otherId];
      if (other == null) continue;
      groups
          .putIfAbsent(_relationLabel(relation.relation), () => [])
          .add(
            [
              other.name,
              if (_flagLabel(relation.flag) case final flag?) '($flag)',
            ].join(' '),
          );
    }
    return [
      for (final MapEntry(:key, :value) in groups.entries)
        '$key: ${value.join(', ')}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = _people;
    final title =
        'People in ${bookDisplayName(widget.bookIndex, useEnglish: widget.useEnglishBookNames)} '
        '${widget.chapter}';
    final byId = <int, NameSummaryEntry>{
      for (final p in people?.people ?? const <ChapterPersonEntry>[])
        p.person.id: p.person,
    };
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: people == null
                ? const Center(child: CircularProgressIndicator())
                : people.people.isEmpty
                ? Center(
                    child: Text(
                      'This chapter names no one.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView(
                    children: [
                      for (final entry in people.people)
                        _personTile(theme, entry, byId),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _personTile(
    ThemeData theme,
    ChapterPersonEntry entry,
    Map<int, NameSummaryEntry> byId,
  ) {
    final person = entry.person;
    final relations = _relations(entry, byId);
    final lines = [
      [
        if (person.description.isNotEmpty) person.description,
        if (person.origin.isNotEmpty) person.origin,
      ].join(' · '),
      relations,
      'verse${entry.verses.length == 1 ? '' : 's'} ${entry.verses.join(', ')}',
    ].where((line) => line.isNotEmpty).toList();
    return ListTile(
      leading: Icon(nameKindIcon(person.kind)),
      title: Text(person.name),
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(person),
    );
  }
}
