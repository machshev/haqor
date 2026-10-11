import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart' show OccurrenceVerseRow;

/// Which prophecies a listing keeps. The index is the [GetProphecies.messianic]
/// code.
enum ProphecyKinds { all, messianic, general }

/// The themes a prophecy may have, in the order the core lists them: the
/// promises concerning Christ, then prophecy in general.
const prophecyThemes = [
  'seed-of-woman',
  'abrahamic',
  'davidic',
  'servant',
  'kingdom',
  'priest',
  'israel',
  'nations',
  'empires',
];

/// A theme's name for a reader.
String prophecyThemeLabel(String theme) => switch (theme) {
  'seed-of-woman' => 'Seed of the woman',
  'abrahamic' => 'Promises to Abraham',
  'davidic' => 'Promises to David',
  'servant' => 'The servant',
  'kingdom' => 'The kingdom',
  'priest' => 'The priest',
  'israel' => 'Israel',
  'nations' => 'The nations',
  'empires' => 'Empires',
  _ => theme,
};

/// When prophecies are fulfilled, in order: the core's stages.
const prophecyStages = [
  'history',
  'first-advent',
  'ad70',
  'return',
  'millennium-end',
];

/// A stage's name for a reader.
String prophecyStageLabel(String stage) => switch (stage) {
  'history' => 'Before Christ',
  'first-advent' => 'Christ\'s first coming',
  'ad70' => 'AD 70',
  'return' => 'Christ\'s return',
  'millennium-end' => 'After the thousand years',
  _ => stage,
};

/// How a passage fulfils a prophecy, for a reader.
String _kindLabel(String kind) => switch (kind) {
  'quotation' => 'Quotation',
  'allusion' => 'Allusion',
  'type' => 'Type',
  'event' => 'Event',
  _ => kind,
};

/// A prophecy of the Old Testament: its passage, title, theme and when it is
/// fulfilled, its first verse, then the passages fulfilling it by stage, each
/// opening in the reader, and the patterns it is part of. A prophecy may have
/// no fulfilment: one still awaiting Christ's return, or one fulfilled in
/// history the Bible does not narrate.
class ProphecyCard extends StatelessWidget {
  const ProphecyCard({
    super.key,
    required this.prophecy,
    required this.cache,
    required this.useEnglishBookNames,
    required this.englishOnly,
    this.ntSyriac = false,
    this.ntGreek = false,
    this.onNavigateToPassage,
    this.onOpenProphecy,
  });

  final ProphecyEntry prophecy;
  final VerseTextCache cache;
  final bool useEnglishBookNames;
  final bool englishOnly;

  /// The reader shows the NT in Syriac script, so NT verse rows do too.
  final bool ntSyriac;

  /// The reader shows the NT in Greek, so NT verse rows do too.
  final bool ntGreek;

  /// Opens a passage: 0-based book index, chapter, verse.
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Shows another prophecy of a pattern, by its id. Without it a pattern's
  /// step opens its passage in the reader.
  final ValueChanged<int>? onOpenProphecy;

  String _ref(int book, int chapter, int verse) =>
      '${bookDisplayName(book - 1, useEnglish: useEnglishBookNames)} '
      '$chapter:$verse';

  /// A passage's reference: one verse, or a run of verses.
  String _span(PassageSpan s) {
    final start = _ref(s.book, s.chapter, s.verse);
    if (s.lastChapter == s.chapter && s.lastVerse == s.verse) return start;
    if (s.lastChapter == s.chapter) return '$start–${s.lastVerse}';
    return '$start–${s.lastChapter}:${s.lastVerse}';
  }

  bool _same(PassageSpan a, PassageSpan b) =>
      a.book == b.book &&
      a.chapter == b.chapter &&
      a.verse == b.verse &&
      a.lastChapter == b.lastChapter &&
      a.lastVerse == b.lastVerse;

  VoidCallback? _open(PassageSpan s) {
    final navigate = onNavigateToPassage;
    if (navigate == null) return null;
    return () => navigate(s.book - 1, s.chapter, s.verse);
  }

  Widget _verseRow(PassageSpan s) => OccurrenceVerseRow(
    cache: cache,
    displayRef: _ref(s.book, s.chapter, s.verse),
    bookIndex: s.book - 1,
    chapter: s.chapter,
    verse: s.verse,
    highlightWords: const [],
    englishOnly: englishOnly,
    syriac: ntSyriac && s.book >= 40,
    greek: ntGreek && s.book >= 40,
    useEnglishBookNames: useEnglishBookNames,
    onTap: _open(s),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final p = prophecy;
    final details = [
      if (p.messianic) 'Messianic',
      if (p.theme.isNotEmpty) prophecyThemeLabel(p.theme),
    ].join(' · ');
    final stageHeading = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.primary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _open(p.passage),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Text(
              _span(p.passage),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            p.title.isEmpty ? 'Quoted as fulfilled in the NT' : p.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontStyle: p.title.isEmpty ? FontStyle.italic : null,
            ),
          ),
        ),
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(details, style: muted),
          ),
        if (p.stages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              'Fulfilled: ${p.stages.map(prophecyStageLabel).join(' · ')}',
              style: muted,
            ),
          ),
        if (p.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(p.note, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 6),
        _verseRow(p.passage),
        const SizedBox(height: 8),
        if (p.fulfilments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('No fulfilment recorded in the Bible.', style: muted),
          )
        else
          for (final stage in [
            ...prophecyStages,
            // A stage this app does not know yet, last.
            ...{
              for (final f in p.fulfilments)
                if (!prophecyStages.contains(f.stage)) f.stage,
            },
          ])
            if (p.fulfilments.where((f) => f.stage == stage).toList()
                case final fulfilments when fulfilments.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(prophecyStageLabel(stage), style: stageHeading),
              ),
              for (final f in fulfilments) ..._fulfilment(context, f, muted),
            ],
        for (final pattern in p.patterns) _pattern(context, pattern),
      ],
    );
  }

  List<Widget> _fulfilment(
    BuildContext context,
    ProphecyFulfilmentEntry f,
    TextStyle? muted,
  ) {
    final theme = Theme.of(context);
    final p = prophecy;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
        child: Text(
          [
            _kindLabel(f.kind),
            _span(f.passage),
            // The verses it takes up, where not the whole prophecy.
            if (!_same(f.prophecyVerses, p.passage))
              'of ${_span(f.prophecyVerses)}',
            if (!f.reviewed) 'found, unreviewed',
          ].join(' · '),
          style: muted,
        ),
      ),
      if (f.note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
          child: Text(
            f.note,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      _verseRow(f.passage),
    ];
  }

  /// A pattern this prophecy is part of: its title and note, then its steps
  /// in order, this prophecy's own marked, the others opening theirs.
  Widget _pattern(BuildContext context, ProphecyPatternEntry pattern) {
    final theme = Theme.of(context);
    final open = onOpenProphecy;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        key: ValueKey('pattern-${pattern.id}'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pattern.title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              if (pattern.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(pattern.note, style: theme.textTheme.bodySmall),
                ),
              for (final m in pattern.members)
                _step(
                  context,
                  m,
                  current: m.prophecyId == prophecy.id,
                  onTap: m.prophecyId == prophecy.id
                      ? null
                      : open != null
                      ? () => open(m.prophecyId)
                      : _open(m.passage),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(
    BuildContext context,
    ProphecyPatternMemberEntry m, {
    required bool current,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(
                prophecyStageLabel(m.stage),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${m.label} · ${_span(m.passage)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: current ? FontWeight.w700 : null,
                  color: current ? null : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
