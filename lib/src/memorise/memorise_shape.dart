import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import '../request_failure.dart';
import '../tutor/progress_sync.dart';
import 'memorise_drill.dart' show memoryHebrewStyle;

/// Where the shaping page leads once a section is ready.
enum ShapeExit {
  /// Just back to wherever it was opened from.
  none,

  /// "Start learning": the page that opened it then starts practice (after
  /// adding a passage).
  start,

  /// "Carry on learning" returns to the practice that sent the learner here.
  resume,
}

/// Shape a passage for learning: where each verse breaks into lines (the
/// pauses and emphasis the learner hears in it) and where the passage breaks
/// into sections learnt as one piece.
///
/// Nothing is shaped for the learner, and a verse is not learnt until its
/// section is shaped: working out what a verse says, and so where it pauses,
/// is the first step in remembering it. Only the section at hand needs doing
/// before learning can begin; the rest can be shaped as it is reached.
///
/// Tapping a word ends a line after it (or joins the line back up), and
/// "Keep whole" settles a verse that is one line; each word's gloss sits
/// under it. Tapping a verse number starts a new section there (or joins it
/// to the one before).
class MemoryShapePage extends StatefulWidget {
  const MemoryShapePage({
    super.key,
    required this.passageId,
    required this.title,
    this.exit = ShapeExit.none,
    this.sendRequest,
  });

  final String passageId;

  /// Stands in for the signal to Rust so a test can capture the page's
  /// requests (`sendSignalToRust` needs the native library).
  final void Function(Object request)? sendRequest;

  /// The passage's name; empty when not known (practising every passage).
  final String title;
  final ShapeExit exit;

  @override
  State<MemoryShapePage> createState() => _MemoryShapePageState();
}

class _MemoryShapePageState extends State<MemoryShapePage> {
  StreamSubscription<RustSignalPack<MemoryLayout>>? _sub;
  StreamSubscription<RequestFailed>? _failureSub;
  final RequestTimer _timer = RequestTimer();
  List<MemoryLayoutVerse>? _verses;
  // Set when the layout could not be loaded; shown in place of the spinner.
  String? _error;
  int _book = 0;
  bool _glosses = true;

  @override
  void initState() {
    super.initState();
    _sub = MemoryLayout.rustSignalStream.listen((pack) {
      if (!mounted || pack.message.passageId != widget.passageId) return;
      _timer.stop();
      setState(() {
        _book = pack.message.book;
        _verses = pack.message.verses;
        _error = null;
      });
    });
    _failureSub = listenForFailure(requestMemoryLayout, _onFailed);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _failureSub?.cancel();
    _timer.stop();
    super.dispose();
  }

  void _request(Object request) {
    final hook = widget.sendRequest;
    if (hook != null) return hook(request);
    switch (request) {
      case GetMemoryLayout():
        request.sendSignalToRust();
      case SetMemoryLayout():
        request.sendSignalToRust();
    }
  }

  void _load() {
    if (_error != null) setState(() => _error = null);
    _timer.start(() {
      if (mounted && _verses == null) _fail('Haqor did not answer.');
    });
    _request(GetMemoryLayout(passageId: widget.passageId));
  }

  void _fail(String message) {
    _timer.stop();
    setState(() => _error = message);
  }

  /// Rust could not load the layout (shown in place of the spinner) or could
  /// not store an edit to it (the shape on screen is then still the old one,
  /// so say so).
  void _onFailed(RequestFailed failure) {
    if (!mounted || failure.key != widget.passageId) return;
    if (_verses == null) {
      _fail(failure.message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save that change: ${failure.message}')),
    );
  }

  /// Store a verse's shape; any change to its lines, or keeping it whole,
  /// settles it as shaped.
  void _send(
    MemoryLayoutVerse v, {
    List<int>? lineStarts,
    bool? sectionStart,
    bool settle = false,
  }) {
    _request(
      SetMemoryLayout(
        passageId: widget.passageId,
        book: _book,
        chapter: v.chapter,
        verse: v.verse,
        lineStarts: lineStarts ?? v.lineStarts,
        shaped: v.shaped || settle || lineStarts != null,
        sectionStart: sectionStart ?? v.sectionStart,
      ),
    );
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

  void _keepWhole(MemoryLayoutVerse v) => _send(v, settle: true);

  void _toggleSection(MemoryLayoutVerse v) =>
      _send(v, sectionStart: !v.sectionStart);

  /// Back to where the learner came from, with `true`: go on and learn.
  void _leave() => Navigator.of(context).pop(true);

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
    final anyReady = verses?.any((v) => v.ready) ?? false;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          widget.title.isEmpty ? 'Shape the passage' : 'Shape ${widget.title}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.translate),
            isSelected: _glosses,
            tooltip: _glosses ? 'Hide word meanings' : 'Show word meanings',
            onPressed: () => setState(() => _glosses = !_glosses),
          ),
        ],
      ),
      body: _error != null
          ? RequestErrorView(
              message: 'Could not load the passage: $_error',
              onRetry: _load,
            )
          : verses == null
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
                          'Work out what it says, then mark where it pauses.',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Read each verse aloud with the meanings under its '
                          'words, and split it where the sense breaks: tap a '
                          'word to end a line after it, or keep a short verse '
                          'whole. Then tap the verse number where the next '
                          'section begins. A section can be learnt once every '
                          'verse in it is shaped — shape the first one now, '
                          'and the rest as you reach them.',
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
                    last: s + 1 == sections.length,
                    glosses: _glosses,
                    onToggleBreak: _toggleBreak,
                    onKeepWhole: _keepWhole,
                    onToggleSection: _toggleSection,
                  ),
              ],
            ),
      floatingActionButton: widget.exit != ShapeExit.none && verses != null
          ? FloatingActionButton.extended(
              onPressed: anyReady ? _leave : null,
              backgroundColor: anyReady
                  ? null
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: anyReady
                  ? null
                  : theme.colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                !anyReady
                    ? 'Shape a section to start'
                    : widget.exit == ShapeExit.start
                    ? 'Start learning'
                    : 'Carry on learning',
              ),
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
    required this.last,
    required this.glosses,
    required this.onToggleBreak,
    required this.onKeepWhole,
    required this.onToggleSection,
  });

  final int index;
  final List<MemoryLayoutVerse> verses;
  final bool first;
  final bool last;
  final bool glosses;
  final void Function(MemoryLayoutVerse, int) onToggleBreak;
  final ValueChanged<MemoryLayoutVerse> onKeepWhole;
  final ValueChanged<MemoryLayoutVerse> onToggleSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = verses.length == 1
        ? '${verses.first.chapter}:${verses.first.verse}'
        : '${verses.first.chapter}:${verses.first.verse}–'
              '${verses.last.verse}';
    final ready = verses.first.ready;
    final left = verses.where((v) => !v.shaped).length;
    final status = ready
        ? 'ready to learn'
        : '$left of ${verses.length} to shape';
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (ready) ...[
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    'Section ${index + 1} · $span · $status',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: ready
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            // The last section runs to the end of the passage: closing it
            // sooner is the way to start sooner.
            if (last && !ready && verses.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'This section runs to the end of the passage. Tap the '
                  'number of the verse where the next section starts, and '
                  'only the verses before it need shaping.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            for (var i = 0; i < verses.length; i++)
              _VerseShape(
                verse: verses[i],
                canStartSection: !(first && i == 0),
                glosses: glosses,
                onToggleBreak: (w) => onToggleBreak(verses[i], w),
                onKeepWhole: () => onKeepWhole(verses[i]),
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
    required this.glosses,
    required this.onToggleBreak,
    required this.onKeepWhole,
    required this.onToggleSection,
  });

  final MemoryLayoutVerse verse;
  final bool canStartSection;
  final bool glosses;
  final ValueChanged<int> onToggleBreak;
  final VoidCallback onKeepWhole;
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
              child: Opacity(
                // An unshaped verse stays faded until the learner settles it.
                opacity: verse.shaped ? 1 : 0.7,
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
                                gloss: glosses && w < verse.glosses.length
                                    ? verse.glosses[w]
                                    : '',
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
            ),
            const SizedBox(width: 4),
            if (verse.shaped)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.colorScheme.primary,
                  semanticLabel: 'shaped',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: OutlinedButton(
                  onPressed: onKeepWhole,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Keep whole'),
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
    required this.gloss,
    required this.endsLine,
    required this.canBreak,
    required this.onTap,
  });

  final String text;
  final String gloss;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: memoryHebrewStyle(theme, 22)),
                if (gloss.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      gloss,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (endsLine)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, top: 6),
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
