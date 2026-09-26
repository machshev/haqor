import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart' show OccurrenceVerseRow;

/// How strongly a quotation's words line up, in words a reader can use. The
/// cut-offs follow the build's score scale: its weakest stored matches sit at
/// 7, and nearly every link above 15 is a recognised quotation.
String crossReferenceStrength(double score) {
  if (score >= 15) return 'Strong match';
  if (score >= 10) return 'Likely match';
  return 'Possible echo';
}

/// The quotations linking one verse to the other testament: for an OT verse
/// the NT verses quoting it, for an NT verse the OT verses it quotes. The
/// matched words are highlighted on both sides, and tapping a linked verse
/// opens it in the reader.
class CrossReferencesSheet extends StatefulWidget {
  const CrossReferencesSheet({
    super.key,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.useEnglishBookNames,
    this.onNavigateToPassage,
    this.sendRequest,
    this.sendVerseTextsRequest,
  });

  /// 1-based book number of the verse whose links are shown.
  final int book;
  final int chapter;
  final int verse;
  final bool useEnglishBookNames;

  /// Opens a linked verse: 0-based book index, chapter, verse.
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Test seams: how requests reach Rust, which a widget test cannot load.
  final void Function(GetCrossReferences)? sendRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  @override
  State<CrossReferencesSheet> createState() => _CrossReferencesSheetState();
}

class _CrossReferencesSheetState extends State<CrossReferencesSheet> {
  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  StreamSubscription<RustSignalPack<CrossReferences>>? _sub;

  /// Null until the reply arrives.
  List<CrossReferenceEntry>? _entries;

  /// The linked verse whose matched words are shown on the source verse.
  int _focused = 0;

  bool get _fromNt => widget.book >= 40;

  @override
  void initState() {
    super.initState();
    _sub = CrossReferences.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.book != widget.book ||
          reply.chapter != widget.chapter ||
          reply.verse != widget.verse) {
        return;
      }
      if (mounted) setState(() => _entries = reply.entries);
    });
    final request = GetCrossReferences(
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
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
    _verseTexts.dispose();
    super.dispose();
  }

  String _ref(int book, int chapter, int verse) =>
      '${bookDisplayName(book - 1, useEnglish: widget.useEnglishBookNames)} '
      '$chapter:$verse';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;
    final title = _fromNt ? 'Quotes from the OT' : 'Quoted in the NT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              Text(
                _ref(widget.book, widget.chapter, widget.verse),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (entries == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (entries.isEmpty)
          const Expanded(
            child: Center(child: Text('No quotations found for this verse.')),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OccurrenceVerseRow(
              key: ValueKey('source-$_focused'),
              cache: _verseTexts,
              displayRef: _ref(widget.book, widget.chapter, widget.verse),
              bookIndex: widget.book - 1,
              chapter: widget.chapter,
              verse: widget.verse,
              highlightWords: const [],
              positions: entries[_focused.clamp(0, entries.length - 1)]
                  .sourcePositions,
              isCurrent: true,
              englishOnly: false,
              useEnglishBookNames: widget.useEnglishBookNames,
            ),
          ),
          const Divider(height: 17),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _entryRow(context, entries, i),
            ),
          ),
        ],
      ],
    );
  }

  Widget _entryRow(
    BuildContext context,
    List<CrossReferenceEntry> entries,
    int i,
  ) {
    final theme = Theme.of(context);
    final entry = entries[i];
    final navigate = widget.onNavigateToPassage;
    final words = entry.positions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _focused = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Icon(
                  i == _focused ? Icons.link : Icons.link_outlined,
                  size: 14,
                  color: i == _focused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${crossReferenceStrength(entry.score)} · '
                    '$words ${words == 1 ? 'word' : 'words'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        OccurrenceVerseRow(
          cache: _verseTexts,
          displayRef: _ref(entry.book, entry.chapter, entry.verse),
          bookIndex: entry.book - 1,
          chapter: entry.chapter,
          verse: entry.verse,
          highlightWords: const [],
          positions: entry.positions,
          englishOnly: false,
          useEnglishBookNames: widget.useEnglishBookNames,
          onTap: navigate == null
              ? null
              : () => navigate(entry.book - 1, entry.chapter, entry.verse),
        ),
      ],
    );
  }
}
