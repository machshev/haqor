import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import '../tutor/progress_sync.dart';
import 'memorise_drill.dart';

/// Shape a passage for learning: where each verse breaks into lines (the
/// pauses and emphasis the learner hears in it) and where the passage breaks
/// into sections learnt as one piece. Reading a passage through closely
/// enough to shape it is itself a first step in learning it.
///
/// Tapping a word ends a line after it (or joins the line back up); tapping a
/// verse number starts a new section there (or joins it to the one before).
class MemoryShapePage extends StatefulWidget {
  const MemoryShapePage({
    super.key,
    required this.passageId,
    required this.book,
    required this.title,
    this.offerStart = false,
  });

  final String passageId;
  final int book;
  final String title;

  /// Show a "Start learning" button that opens practice (after adding a
  /// passage).
  final bool offerStart;

  @override
  State<MemoryShapePage> createState() => _MemoryShapePageState();
}

class _MemoryShapePageState extends State<MemoryShapePage> {
  StreamSubscription<RustSignalPack<MemoryLayout>>? _sub;
  List<MemoryLayoutVerse>? _verses;

  @override
  void initState() {
    super.initState();
    _sub = MemoryLayout.rustSignalStream.listen((pack) {
      if (!mounted || pack.message.passageId != widget.passageId) return;
      setState(() => _verses = pack.message.verses);
    });
    GetMemoryLayout(passageId: widget.passageId).sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _send(MemoryLayoutVerse v, {List<int>? lineStarts, bool? sectionStart}) {
    SetMemoryLayout(
      passageId: widget.passageId,
      book: widget.book,
      chapter: v.chapter,
      verse: v.verse,
      lineStarts: lineStarts ?? v.lineStarts,
      defaultLines: lineStarts == null && !v.customLines,
      sectionStart: sectionStart != null
          ? (sectionStart ? 1 : 0)
          : v.customSection
          ? (v.sectionStart ? 1 : 0)
          : -1,
    ).sendSignalToRust();
    scheduleProgressSync();
  }

  /// Toggle a line break after word `i` of a verse.
  void _toggleBreak(MemoryLayoutVerse v, int i) {
    final start = i + 1;
    if (start >= v.words.length) return;
    final starts = [...v.lineStarts];
    starts.contains(start) ? starts.remove(start) : starts.add(start);
    starts.sort();
    _send(v, lineStarts: starts);
  }

  void _toggleSection(MemoryLayoutVerse v) =>
      _send(v, sectionStart: !v.sectionStart);

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use the suggested shape?'),
        content: const Text(
          'Every line break and section is put back to the suggestion: '
          'longer verses split at their main pause, sections of about four '
          'verses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ResetMemoryLayout(passageId: widget.passageId).sendSignalToRust();
    scheduleProgressSync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verses = _verses;
    // Sections as runs of verses.
    final sections = <List<MemoryLayoutVerse>>[];
    for (final v in verses ?? const <MemoryLayoutVerse>[]) {
      if (sections.isEmpty || v.sectionStart) sections.add([]);
      sections.last.add(v);
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text('Shape ${widget.title}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: 'Use the suggested shape',
            onPressed: verses == null ? null : _reset,
          ),
        ],
      ),
      body: verses == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Card(
                  elevation: 0,
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Read it through aloud, and mark where you pause.',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap a word to end a line after it. Tap a verse '
                          'number to start a new section there. Each line is '
                          'learnt on its own, then joined to the lines before '
                          'it; each section is learnt, and reviewed, as one '
                          'piece. Deciding where the breaks fall is the first '
                          'step in learning it.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (var s = 0; s < sections.length; s++)
                  _SectionCard(
                    index: s,
                    verses: sections[s],
                    first: s == 0,
                    onToggleBreak: _toggleBreak,
                    onToggleSection: _toggleSection,
                  ),
              ],
            ),
      floatingActionButton: widget.offerStart && verses != null
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => MemoryDrillPage(
                    passageId: widget.passageId,
                    title: widget.title,
                  ),
                ),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start learning'),
            )
          : null,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.index,
    required this.verses,
    required this.first,
    required this.onToggleBreak,
    required this.onToggleSection,
  });

  final int index;
  final List<MemoryLayoutVerse> verses;
  final bool first;
  final void Function(MemoryLayoutVerse, int) onToggleBreak;
  final ValueChanged<MemoryLayoutVerse> onToggleSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = verses.length == 1
        ? '${verses.first.chapter}:${verses.first.verse}'
        : '${verses.first.chapter}:${verses.first.verse}–'
              '${verses.last.verse}';
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Section ${index + 1} · $span',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < verses.length; i++)
              _VerseShape(
                verse: verses[i],
                canStartSection: !(first && i == 0),
                onToggleBreak: (w) => onToggleBreak(verses[i], w),
                onToggleSection: () => onToggleSection(verses[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _VerseShape extends StatelessWidget {
  const _VerseShape({
    required this.verse,
    required this.canStartSection,
    required this.onToggleBreak,
    required this.onToggleSection,
  });

  final MemoryLayoutVerse verse;
  final bool canStartSection;
  final ValueChanged<int> onToggleBreak;
  final VoidCallback onToggleSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bounds = [0, ...verse.lineStarts, verse.words.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: canStartSection
                  ? (verse.sectionStart
                        ? 'Join this verse to the section before'
                        : 'Start a new section here')
                  : 'The passage starts here',
              child: InkWell(
                onTap: canStartSection ? onToggleSection : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: verse.sectionStart
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    '${verse.verse}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: verse.sectionStart
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var l = 0; l + 1 < bounds.length; l++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 4,
                        children: [
                          for (var w = bounds[l]; w < bounds[l + 1]; w++)
                            _ShapeWord(
                              text: verse.words[w],
                              endsLine:
                                  w + 1 == bounds[l + 1] &&
                                  w + 1 < verse.words.length,
                              canBreak: w + 1 < verse.words.length,
                              onTap: () => onToggleBreak(w),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapeWord extends StatelessWidget {
  const _ShapeWord({
    required this.text,
    required this.endsLine,
    required this.canBreak,
    required this.onTap,
  });

  final String text;
  final bool endsLine;
  final bool canBreak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: canBreak ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: memoryHebrewStyle(theme, 22)),
            if (endsLine)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Icon(
                  Icons.keyboard_return,
                  size: 16,
                  color: theme.colorScheme.primary,
                  semanticLabel: 'line break',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
