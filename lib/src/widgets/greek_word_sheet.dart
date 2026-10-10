import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'name_details.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart' show VerseModeIcon;

/// A word of the Greek New Testament (the TR), as the word pane shows it:
/// the word and its dictionary form, its English here, its grammar in words,
/// the person or place it names, and every word sharing its dictionary form,
/// each in its verse.
class GreekWordSheet extends StatefulWidget {
  const GreekWordSheet({
    super.key,
    required this.word,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.position,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.onNavigateToPassage,
    this.nameBookmarks,
    this.sendRequest,
    this.sendVerseTextsRequest,
  });

  /// The word as the reader shows it, shown until its details arrive.
  final String word;

  /// Where the word stands: its book (40 Matthew … 66 Revelation), chapter,
  /// verse and its position in the verse, from 0.
  final int book;
  final int chapter;
  final int verse;
  final int position;
  final bool useEnglishBookNames;

  /// The Peshitta's script, for the pages of a person or place it opens.
  final bool ntSyriac;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final NameBookmarks? nameBookmarks;

  /// Test seams: how the word and the occurrences' verses are asked for.
  final void Function(GetGreekWord request)? sendRequest;
  final void Function(GetVerseTexts request)? sendVerseTextsRequest;

  @override
  State<GreekWordSheet> createState() => _GreekWordSheetState();
}

class _GreekWordSheetState extends State<GreekWordSheet> {
  /// Request ids are handed out app-wide: replies are broadcast, and two
  /// panes must not take each other's.
  static int _nextRequestId = 1;

  late final int _requestId = _nextRequestId++;
  StreamSubscription<RustSignalPack<GreekWordInfo>>? _sub;
  GreekWordInfo? _info;
  bool _englishOnly = false;
  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );

  @override
  void initState() {
    super.initState();
    _sub = GreekWordInfo.rustSignalStream.listen((pack) {
      if (pack.message.requestId != _requestId || !mounted) return;
      setState(() => _info = pack.message);
    });
    final request = GetGreekWord(
      requestId: _requestId,
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
      position: widget.position,
    );
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
    unawaited(
      occurrenceVerseEnglishOnlyEnabled().then((enabled) {
        if (mounted) setState(() => _englishOnly = enabled);
      }),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _verseTexts.dispose();
    super.dispose();
  }

  void _toggleEnglishOnly() {
    setState(() => _englishOnly = !_englishOnly);
    unawaited(setOccurrenceVerseEnglishOnlyEnabled(_englishOnly));
  }

  String _reference(int book, int chapter, int verse) =>
      '${bookSelectorLabel(book - 1, useEnglish: widget.useEnglishBookNames)} '
      '$chapter:$verse';

  void _openName(NameSummaryEntry name) => NameDetailsPage.open(
    context,
    id: name.id,
    title: name.name,
    useEnglishBookNames: widget.useEnglishBookNames,
    ntSyriac: widget.ntSyriac,
    onNavigateToPassage: widget.onNavigateToPassage,
    bookmarks: widget.nameBookmarks,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    final greekStyle = TextStyle(
      fontFamily: 'Cardo',
      fontSize: 30,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface,
    );
    final header = <Widget>[
      Text(
        info?.word.isNotEmpty == true ? info!.word : widget.word,
        style: greekStyle,
      ),
      Text(
        _reference(widget.book, widget.chapter, widget.verse),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
    if (info == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ...header,
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (!info.found) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ...header,
          const SizedBox(height: 16),
          const Text('Nothing is known of this word.'),
        ],
      );
    }
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          value,
        ],
      ),
    );
    final occurrences = info.occurrences;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          sliver: SliverList.list(
            children: [
              ...header,
              if (info.name case final name?) ...[
                const SizedBox(height: 12),
                NameCard(name: name, onOpen: () => _openName(name)),
              ],
              if (info.lemma.isNotEmpty)
                row(
                  'Dictionary form',
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: info.lemma,
                          style: const TextStyle(
                            fontFamily: 'Cardo',
                            fontSize: 20,
                          ),
                        ),
                        if (info.gloss.isNotEmpty)
                          TextSpan(
                            text: '  ${info.gloss}',
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                ),
              if (info.english.isNotEmpty)
                row(
                  'Here',
                  Text(info.english, style: theme.textTheme.bodyMedium),
                ),
              if (info.grammar.isNotEmpty)
                row(
                  'Grammar',
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: info.grammarDescription,
                          style: theme.textTheme.bodyMedium,
                        ),
                        TextSpan(
                          text: '  ${info.grammar}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (occurrences.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        occurrences.length == 1
                            ? 'Its only occurrence'
                            : '${occurrences.length} occurrences of '
                                  '${info.lemma}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: _englishOnly ? 'Show the Greek' : 'Show English',
                      onPressed: _toggleEnglishOnly,
                      icon: VerseModeIcon(
                        englishOnly: _englishOnly,
                        sourceLetter: 'α',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          sliver: SliverList.builder(
            itemCount: occurrences.length,
            itemBuilder: (context, index) {
              final occurrence = occurrences[index];
              return _GreekOccurrenceRow(
                key: ValueKey(
                  '${occurrence.book}:${occurrence.chapter}:'
                  '${occurrence.verse}:${occurrence.position}',
                ),
                occurrence: occurrence,
                reference: _reference(
                  occurrence.book,
                  occurrence.chapter,
                  occurrence.verse,
                ),
                current:
                    occurrence.book == widget.book &&
                    occurrence.chapter == widget.chapter &&
                    occurrence.verse == widget.verse &&
                    occurrence.position == widget.position,
                text: _verseTexts.textFor(
                  book: occurrence.book,
                  chapter: occurrence.chapter,
                  verse: occurrence.verse,
                  englishOnly: _englishOnly,
                  greek: true,
                ),
                englishOnly: _englishOnly,
                onTap: widget.onNavigateToPassage == null
                    ? null
                    : () => widget.onNavigateToPassage!(
                        occurrence.book - 1,
                        occurrence.chapter,
                        occurrence.verse,
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One occurrence: its reference and its verse, Greek or English, with the
/// word itself, or the English rendering it, highlighted.
class _GreekOccurrenceRow extends StatelessWidget {
  const _GreekOccurrenceRow({
    super.key,
    required this.occurrence,
    required this.reference,
    required this.current,
    required this.text,
    required this.englishOnly,
    this.onTap,
  });

  final GreekOccurrenceEntry occurrence;
  final String reference;
  final bool current;
  final ValueListenable<VerseTextData?> text;
  final bool englishOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = TextStyle(
      fontFamily: 'Cardo',
      fontSize: 16,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    final highlight = base.copyWith(
      backgroundColor: theme.colorScheme.primaryContainer,
      color: theme.colorScheme.onPrimaryContainer,
    );
    final refStyle = base.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        color: current
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: ValueListenableBuilder<VerseTextData?>(
          valueListenable: text,
          builder: (context, data, _) {
            final children = <InlineSpan>[
              TextSpan(text: '$reference  ', style: refStyle),
            ];
            if (data == null) {
              children.add(TextSpan(text: '…', style: base));
            } else if (englishOnly && data.translation.isNotEmpty) {
              bool renders(TranslationSpanEntry span) => span.words.any(
                (w) =>
                    w.chapter == occurrence.chapter &&
                    w.verse == occurrence.verse &&
                    w.position == occurrence.position,
              );
              for (final span in data.translation) {
                children.add(
                  TextSpan(
                    text: span.text,
                    style: (renders(span) ? highlight : base).copyWith(
                      fontStyle: span.supplied ? FontStyle.italic : null,
                    ),
                  ),
                );
              }
            } else {
              final words = englishOnly
                  ? data.glossWords
                  : data.text.split(' ');
              for (final (i, word) in words.indexed) {
                if (i > 0) children.add(TextSpan(text: ' ', style: base));
                children.add(
                  TextSpan(
                    text: word,
                    style: i == occurrence.position ? highlight : base,
                  ),
                );
              }
            }
            return Text.rich(TextSpan(children: children));
          },
        ),
      ),
    );
  }
}
