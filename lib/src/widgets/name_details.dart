import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'place_map.dart';
import 'word_info_sheet.dart' show BibleRefPreviewDialog;

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
/// the forms of their name, where a place may have been, and every verse
/// naming them.
class NameDetailsPage extends StatefulWidget {
  const NameDetailsPage({
    super.key,
    required this.id,
    this.title,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.sendRequest,
    this.basemap,
  });

  /// The route's name, so going to a passage can close every page of names
  /// opened one from another.
  static const routeName = 'name-details';

  final int id;

  /// Shown until the record arrives.
  final String? title;
  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Stands in for the signal to Rust, for tests.
  final void Function(GetNameEntity)? sendRequest;
  final Basemap? basemap;

  /// Open the page for [id] over [context].
  static Future<void> open(
    BuildContext context, {
    required int id,
    String? title,
    bool useEnglishBookNames = false,
    void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => NameDetailsPage(
        id: id,
        title: title,
        useEnglishBookNames: useEnglishBookNames,
        onNavigateToPassage: onNavigateToPassage,
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
  bool _allVerses = false;

  /// Verses listed before "Show all".
  static const _versesShown = 60;

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
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _openOther(NameSummaryEntry other) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: NameDetailsPage.routeName),
      builder: (_) => NameDetailsPage(
        id: other.id,
        title: other.name,
        useEnglishBookNames: widget.useEnglishBookNames,
        onNavigateToPassage: widget.onNavigateToPassage,
        sendRequest: widget.sendRequest,
        basemap: widget.basemap,
      ),
    ),
  );

  void _openVerse(WordOccurrence verse) {
    final bookIndex = verse.book - 1;
    final reference =
        '${bookDisplayName(bookIndex, useEnglish: widget.useEnglishBookNames)} '
        '${verse.chapter}:${verse.verse}';
    final navigate = widget.onNavigateToPassage;
    showDialog<void>(
      context: context,
      builder: (_) => BibleRefPreviewDialog(
        displayRef: reference,
        bookIndex: bookIndex,
        chapter: verse.chapter,
        verse: verse.verse,
        onNavigate: navigate == null
            ? null
            : () {
                Navigator.of(context).popUntil(
                  (route) => route.settings.name != NameDetailsPage.routeName,
                );
                navigate(bookIndex, verse.chapter, verse.verse);
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: Text(info?.summary.name ?? widget.title ?? '')),
      body: info == null
          ? const Center(child: CircularProgressIndicator())
          : !info.found
          ? const Center(child: Text('Nothing is known of this name.'))
          : _body(context, info),
    );
  }

  Widget _body(BuildContext context, NameEntityInfo info) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = info.summary;
    final heading = theme.textTheme.titleSmall?.copyWith(color: scheme.primary);
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
    final verses = _allVerses
        ? info.verses
        : info.verses.take(_versesShown).toList();
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final horizontalSlack = math.max(
      0.0,
      (MediaQuery.sizeOf(context).width - 760) / 2,
    );

    return ListView(
      // A readable measure on a wide window.
      padding: EdgeInsets.fromLTRB(
        20 + horizontalSlack,
        8,
        20 + horizontalSlack,
        24 + bottom,
      ),
      children: [
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
                    MapPin(
                      latitude: location.latitude,
                      longitude: location.longitude,
                      label: i == 0 ? summary.name : '',
                      primary: i == 0,
                      confidence: location.confidence < 0
                          ? null
                          : location.confidence,
                    ),
                ],
              ),
            ),
          ),
          if (info.locations.length > 1 ||
              info.locations.first.label.isNotEmpty)
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
            for (final form in info.forms) _FormRow(form: form),
          ]),
        if (info.verses.isNotEmpty)
          section(mentionsLabel(summary.occurrences), [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final verse in verses)
                  ActionChip(
                    label: Text(
                      '${bookSelectorLabel(verse.book - 1, useEnglish: widget.useEnglishBookNames)} '
                      '${verse.chapter}:${verse.verse}',
                    ),
                    onPressed: () => _openVerse(verse),
                  ),
              ],
            ),
            if (verses.length < info.verses.length)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _allVerses = true),
                  child: Text('Show all ${info.verses.length} verses'),
                ),
              ),
          ]),
        const SizedBox(height: 24),
        Text(
          [
            'From STEP Bible\'s TIPNR (Tyndale House Cambridge, CC BY 4.0)',
            if (info.locations.any((l) => l.confidence >= 0))
              'Locations from OpenBible.info (CC BY 4.0)',
            // Haqor's own identifications carry a label but no confidence;
            // TIPNR's positions carry neither.
            if (info.locations.any(
              (l) => l.confidence < 0 && l.label.isNotEmpty,
            ))
              "Location as Haqor identifies it, in place of OpenBible.info's "
                  '(see About)',
          ].join('. '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.location, required this.likeliest});

  final PlaceLocationEntry location;
  final bool likeliest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidence = location.confidence < 0
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
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.form});

  final NameFormEntry form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(form.english.join(', '), style: theme.textTheme.bodyLarge),
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
          Text(
            form.hebrew,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontFamily: 'Noto Serif Hebrew',
              fontFamilyFallback: ['Cardo'],
              fontSize: 22,
            ),
          ),
        ],
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
  });

  /// Zero-based, as the reader counts books.
  final int bookIndex;
  final int chapter;
  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final void Function(GetChapterPlaces)? sendRequest;
  final Basemap? basemap;

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
                              MapPin(
                                latitude: entry.location.latitude,
                                longitude: entry.location.longitude,
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
