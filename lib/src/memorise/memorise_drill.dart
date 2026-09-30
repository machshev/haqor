import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import '../request_failure.dart';
import '../tutor/progress_sync.dart';
import 'memorise_page.dart' show memoryUtcOffset;
import 'memorise_shape.dart';

const _gradeLabels = ['Forgot', 'Hard', 'Good', 'Easy'];

/// The grade a check suggests: nothing missed is Good; a single slip, or up
/// to a quarter of the words, Hard; more than that Forgot.
int suggestedMemoryGrade(int missed, int words) {
  if (missed == 0) return 2;
  return missed == 1 || missed <= words / 4 ? 1 : 0;
}

/// Each verse's grade for a recital: its own suggestion, moved by however
/// far the learner's overall grade departs from the overall suggestion.
List<int> memoryVerseGrades({
  required List<int> missedPerVerse,
  required List<int> wordsPerVerse,
  required int chosen,
}) {
  final missed = missedPerVerse.fold(0, (a, b) => a + b);
  final words = wordsPerVerse.fold(0, (a, b) => a + b);
  final shift = chosen - suggestedMemoryGrade(missed, words);
  return [
    for (var i = 0; i < missedPerVerse.length; i++)
      (suggestedMemoryGrade(missedPerVerse[i], wordsPerVerse[i]) + shift).clamp(
        0,
        3,
      ),
  ];
}

/// Practise one passage (or all passages when `passageId` is empty), card by
/// card as the scheduler offers them — or, with `run`, recite everything
/// learnt of the passage once.
class MemoryDrillPage extends StatefulWidget {
  const MemoryDrillPage({
    super.key,
    required this.passageId,
    required this.title,
    this.run = false,
    this.sendRequest,
  });

  final String passageId;
  final String title;
  final bool run;

  /// Stands in for the signal to Rust so a test can capture the page's
  /// requests (`sendSignalToRust` needs the native library).
  final void Function(Object request)? sendRequest;

  @override
  State<MemoryDrillPage> createState() => _MemoryDrillPageState();
}

class _MemoryDrillPageState extends State<MemoryDrillPage> {
  StreamSubscription<RustSignalPack<MemoryItem>>? _itemSub;
  StreamSubscription<RustSignalPack<MemoryReviewResult>>? _resultSub;
  final List<StreamSubscription<RequestFailed>> _failureSubs = [];
  final RequestTimer _timer = RequestTimer();
  MemoryItem? _item;
  int _seq = 0;
  bool _waiting = true;
  // Set when Rust fails or never answers the request for the next card; the
  // page then offers to ask again instead of spinning.
  String? _error;
  // The answer last sent, kept so a failure to record it can be retried.
  SubmitMemoryRecital? _lastRecital;
  bool _runDone = false;
  int _sessionXp = 0;
  int _sessionCards = 0;
  int _sessionLearnt = 0;
  MemoryReviewResult? _lastResult;

  /// A short note on what the last answer earned, shown over the top of the
  /// card without blocking it.
  String? _note;
  Timer? _noteTimer;

  @override
  void initState() {
    super.initState();
    _itemSub = MemoryItem.rustSignalStream.listen((pack) {
      if (!mounted) return;
      _timer.stop();
      setState(() {
        _item = pack.message;
        _seq++;
        _waiting = false;
        _error = null;
      });
    });
    _resultSub = MemoryReviewResult.rustSignalStream.listen(_onResult);
    _failureSubs
      ..add(
        listenForFailure(requestMemoryItem, (failure) {
          if (mounted && _waiting) _fail(failure.message);
        }, key: widget.passageId),
      )
      ..add(listenForFailure(requestMemoryRecital, _onRecitalFailed));
    _requestNext();
  }

  void _send(Object request) {
    final hook = widget.sendRequest;
    if (hook != null) return hook(request);
    switch (request) {
      case GetMemoryRun():
        request.sendSignalToRust();
      case GetNextMemoryCard():
        request.sendSignalToRust();
      case SubmitMemoryRecital():
        request.sendSignalToRust();
    }
  }

  void _fail(String message) {
    _timer.stop();
    setState(() {
      _waiting = false;
      _error = message;
    });
  }

  /// The answer just given could not be recorded. The next card is already on
  /// its way, so offer to send the answer again rather than block on it.
  void _onRecitalFailed(RequestFailed failure) {
    final recital = _lastRecital;
    if (!mounted || recital == null || failure.key != recital.passageId) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Your answer was not saved: ${failure.message}'),
        action: SnackBarAction(
          label: 'Try again',
          onPressed: () => _send(recital),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _itemSub?.cancel();
    _resultSub?.cancel();
    for (final sub in _failureSubs) {
      sub.cancel();
    }
    _timer.stop();
    _noteTimer?.cancel();
    super.dispose();
  }

  void _requestNext({bool extraNew = false}) {
    setState(() {
      _waiting = true;
      _error = null;
    });
    if (widget.run) {
      if (_runDone) {
        setState(() {
          _item = MemoryItem(
            kind: 'done',
            card: null,
            nextDueEpoch: 0,
            canLearnMore: false,
            shapePassageId: '',
          );
          _waiting = false;
        });
      } else {
        _timer.start(() {
          if (mounted) _fail('Haqor did not answer.');
        });
        _send(GetMemoryRun(passageId: widget.passageId));
      }
      return;
    }
    _timer.start(() {
      if (mounted) _fail('Haqor did not answer.');
    });
    _send(
      GetNextMemoryCard(
        passageId: widget.passageId,
        extraNew: extraNew,
        utcOffset: memoryUtcOffset(),
      ),
    );
  }

  /// Open the shaping page for the passage whose next section waits on it,
  /// and carry on from there when the learner comes back.
  Future<void> _shape(String passageId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryShapePage(
          passageId: passageId,
          title: passageId == widget.passageId ? widget.title : '',
          exit: ShapeExit.resume,
        ),
      ),
    );
    if (mounted) _requestNext();
  }

  void _submit(MemoryCard card, int grade, List<(int, int, int)> verses) {
    final recital = SubmitMemoryRecital(
      passageId: card.passageId,
      book: card.book,
      purpose: card.purpose,
      targetChapter: card.targetChapter,
      targetVerse: card.targetVerse,
      step: card.step,
      grade: grade,
      chapters: [for (final v in verses) v.$1],
      verses: [for (final v in verses) v.$2],
      grades: [for (final v in verses) v.$3],
      utcOffset: memoryUtcOffset(),
    );
    _lastRecital = recital;
    _send(recital);
    scheduleProgressSync();
    if (widget.run) _runDone = true;
    _requestNext();
  }

  Future<void> _onResult(RustSignalPack<MemoryReviewResult> pack) async {
    if (!mounted) return;
    final r = pack.message;
    setState(() {
      _sessionXp += r.xp;
      _sessionCards++;
      if (r.firstGraduation) _sessionLearnt++;
      _lastResult = r;
    });
    final notes = <String>[
      if (r.xp > 0) '+${r.xp} XP',
      if (r.firstGraduation) '${r.targetChapter}:${r.targetVerse} learnt!',
      if (r.relearn > 0)
        '${r.relearn} ${r.relearn == 1 ? 'verse' : 'verses'} to go over again',
      if (r.purpose == 'run' && r.intervalDays > 0)
        'next run-through in ${r.intervalDays} days',
      if (r.goalReachedNow) 'daily goal reached!',
      if (r.levelAfter > r.levelBefore) 'level ${r.levelAfter}!',
    ];
    if (notes.isNotEmpty) {
      _noteTimer?.cancel();
      setState(() => _note = notes.join(' · '));
      _noteTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _note = null);
      });
    }
    if (r.completedPassages.isNotEmpty) {
      await _celebrate(
        icon: Icons.verified,
        title: 'Passage complete!',
        body:
            'Every verse of ${widget.title} is now learnt by heart. Keep '
            'reciting it and it will stay with you.',
      );
    } else if (r.sectionCompleted) {
      await _celebrate(
        icon: Icons.auto_awesome,
        title: 'Section learnt!',
        body:
            'You can recite this whole section. It will come back for review '
            'as one piece, so it stays joined together.',
      );
    }
  }

  Future<void> _celebrate({
    required IconData icon,
    required String title,
    required String body,
  }) {
    if (!mounted) return Future.value();
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(icon, size: 48, color: theme.colorScheme.primary),
        title: Text(title),
        content: Text(body, textAlign: TextAlign.center),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep going'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;
    final card = item?.card;
    final result = _lastResult;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(widget.run ? 'Recite ${widget.title}' : widget.title),
        bottom: result == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(6),
                child: LinearProgressIndicator(
                  value: result.dailyGoalXp <= 0
                      ? 0
                      : (result.todayXp / result.dailyGoalXp).clamp(0.0, 1.0),
                  minHeight: 6,
                  semanticsLabel: 'Daily goal',
                ),
              ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Icon(Icons.bolt, size: 18, color: theme.colorScheme.primary),
                  Text('$_sessionXp XP', style: theme.textTheme.labelLarge),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _error != null
                  ? RequestErrorView(
                      key: const ValueKey('memory-error'),
                      message: 'Could not load the next card: $_error',
                      onRetry: _requestNext,
                    )
                  : _waiting || item == null
                  ? const Center(
                      key: ValueKey('memory-loading'),
                      child: CircularProgressIndicator(),
                    )
                  : card != null
                  ? KeyedSubtree(
                      key: ValueKey(_seq),
                      child: MemoryRecitalView(
                        card: card,
                        onSubmit: (grade, verses) =>
                            _submit(card, grade, verses),
                      ),
                    )
                  : _DoneView(
                      key: const ValueKey('memory-done'),
                      item: item,
                      run: widget.run,
                      sessionXp: _sessionXp,
                      sessionCards: _sessionCards,
                      sessionLearnt: _sessionLearnt,
                      streakDays: result?.streakDays ?? 0,
                      onLearnMore: () => _requestNext(extraNew: true),
                      onShape: () => _shape(item.shapePassageId),
                    ),
            ),
          ),
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _note == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: Material(
                    elevation: 2,
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Text(
                        _note ?? '',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A word's place on a card: its segment, and its index within the segment.
typedef _WordRef = ({int segment, int word});

/// One card. A read card shows its lines in full, with transliteration and
/// glosses, to read aloud. A recital card hides every word: the learner
/// recites, revealing each word in turn as they say it ("Next word"), or
/// marking the one they could not bring to mind ("Missed it") — or reveals
/// the rest at once. Once everything is showing, any word can be tapped to
/// mark it missed or not, and the grade buttons suggest a grade.
class MemoryRecitalView extends StatefulWidget {
  const MemoryRecitalView({
    super.key,
    required this.card,
    required this.onSubmit,
  });

  final MemoryCard card;

  /// The card's grade, and each verse's (chapter, verse, grade).
  final void Function(int grade, List<(int, int, int)> verses) onSubmit;

  @override
  State<MemoryRecitalView> createState() => _MemoryRecitalViewState();
}

class _MemoryRecitalViewState extends State<MemoryRecitalView> {
  late final List<_WordRef> _order = [
    for (var s = 0; s < widget.card.segments.length; s++)
      for (var w = 0; w < widget.card.segments[s].words.length; w++)
        (segment: s, word: w),
  ];
  late final List<GlobalKey> _keys = [for (final _ in _order) GlobalKey()];
  final _missed = <int>{};
  final _focus = FocusNode();
  int _revealed = 0;
  late bool _showMeaning = !_hidden;
  late bool _showSounds = !_hidden;

  MemoryCard get _card => widget.card;
  bool get _hidden => _card.purpose != 'read';
  bool get _complete => !_hidden || _revealed >= _order.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not while a dialog is over the page: it keeps the keyboard.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _next({bool missed = false}) {
    if (_revealed >= _order.length) return;
    setState(() {
      if (missed) _missed.add(_revealed);
      _revealed++;
    });
    // Keep the word being recited in view on a long recital.
    final key = _keys[_revealed.clamp(0, _keys.length - 1)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.4,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  void _revealAll() => setState(() => _revealed = _order.length);

  void _toggleMissed(int i) =>
      setState(() => _missed.contains(i) ? _missed.remove(i) : _missed.add(i));

  /// Verses on the card in order, with their missed and total word counts.
  List<(int, int, int, int)> _verseTallies() {
    final out = <(int, int, int, int)>[];
    for (var i = 0; i < _order.length; i++) {
      final seg = _card.segments[_order[i].segment];
      final missed = _missed.contains(i) ? 1 : 0;
      if (out.isNotEmpty &&
          out.last.$1 == seg.chapter &&
          out.last.$2 == seg.verse) {
        final last = out.removeLast();
        out.add((last.$1, last.$2, last.$3 + missed, last.$4 + 1));
      } else {
        out.add((seg.chapter, seg.verse, missed, 1));
      }
    }
    return out;
  }

  int get _suggested => suggestedMemoryGrade(_missed.length, _order.length);

  void _grade(int grade) {
    final tallies = _verseTallies();
    final grades = _hidden
        ? memoryVerseGrades(
            missedPerVerse: [for (final t in tallies) t.$3],
            wordsPerVerse: [for (final t in tallies) t.$4],
            chosen: grade,
          )
        : [for (final _ in tallies) grade];
    widget.onSubmit(grade, [
      for (var i = 0; i < tallies.length; i++)
        (tallies[i].$1, tallies[i].$2, grades[i]),
    ]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!_hidden) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
        _grade(2);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_complete) {
      final digit = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ].indexOf(key);
      if (digit >= 0) {
        _grade(digit);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter) {
        _grade(_suggested);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowLeft) {
      _next();
    } else if (key == LogicalKeyboardKey.keyX ||
        key == LogicalKeyboardKey.backspace) {
      _next(missed: true);
    } else if (key == LogicalKeyboardKey.enter) {
      _revealAll();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final learning = _card.stepCount > 0;
    var index = 0;
    final lines = <Widget>[];
    for (final seg in _card.segments) {
      final first = index;
      index += seg.words.length;
      lines.add(
        _LineRow(
          segment: seg,
          firstIndex: first,
          keys: _keys,
          hidden: _hidden,
          revealed: _revealed,
          missed: _missed,
          showMeaning: _showMeaning,
          showSounds: _showSounds,
          complete: _complete,
          onTapWord: (i) {
            if (!_hidden) return;
            if (_complete) {
              _toggleMissed(i);
            } else if (i == _revealed) {
              _next();
            }
          },
        ),
      );
    }
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _card.title,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (_card.total > 0)
                        Text(
                          'verse ${_card.position} of ${_card.total}'
                          '${_card.sectionCount > 1 ? ' · section ${_card.section}/${_card.sectionCount}' : ''}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (learning) ...[
                    const SizedBox(height: 6),
                    _StepDots(step: _card.step, count: _card.stepCount),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _hidden
                            ? Icons.record_voice_over_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _card.prompt,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_card.cue.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _card.cue,
                        textDirection: TextDirection.rtl,
                        style: memoryHebrewStyle(
                          theme,
                          20,
                        ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ...lines,
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Meaning'),
                        selected: _showMeaning,
                        onSelected: (v) => setState(() => _showMeaning = v),
                      ),
                      FilterChip(
                        label: const Text('Sounds'),
                        selected: _showSounds,
                        onSelected: (v) => setState(() => _showSounds = v),
                      ),
                    ],
                  ),
                  if (_hidden && _complete)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _missed.isEmpty
                            ? 'Word perfect? Tap any word you got wrong.'
                            : '${_missed.length} missed — tap a word to change it.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    const tall = Size.fromHeight(52);
    if (!_hidden) {
      return FilledButton.icon(
        onPressed: () => _grade(2),
        icon: const Icon(Icons.record_voice_over),
        label: const Text('I have read it aloud'),
        style: FilledButton.styleFrom(minimumSize: tall),
      );
    }
    if (!_complete) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _next(missed: true),
                  icon: const Icon(Icons.close),
                  label: const Text('Missed it'),
                  style: OutlinedButton.styleFrom(minimumSize: tall),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _next,
                  icon: const Icon(Icons.check),
                  label: const Text('Next word'),
                  style: FilledButton.styleFrom(minimumSize: tall),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _revealAll,
            child: Text(
              _revealed == 0
                  ? 'Recite it all first, then reveal'
                  : 'Reveal the rest',
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        for (var g = 0; g < 4; g++) ...[
          if (g > 0) const SizedBox(width: 8),
          Expanded(
            child: g == _suggested
                ? FilledButton(
                    onPressed: () => _grade(g),
                    style: FilledButton.styleFrom(
                      minimumSize: tall,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(_gradeLabels[g]),
                  )
                : OutlinedButton(
                    onPressed: () => _grade(g),
                    style: OutlinedButton.styleFrom(
                      minimumSize: tall,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(_gradeLabels[g]),
                  ),
          ),
        ],
      ],
    );
  }
}

TextStyle memoryHebrewStyle(ThemeData theme, double size) =>
    (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: 'Cardo',
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: size,
      height: 1.4,
    );

/// A learning step's place in its verse's script.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.count});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Step ${step + 1} of $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < step
                    ? scheme.primary
                    : i == step
                    ? scheme.tertiary
                    : scheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of a verse, right to left, its verse number leading the verse's
/// first line.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.segment,
    required this.firstIndex,
    required this.keys,
    required this.hidden,
    required this.revealed,
    required this.missed,
    required this.showMeaning,
    required this.showSounds,
    required this.complete,
    required this.onTapWord,
  });

  final MemorySegment segment;
  final int firstIndex;
  final List<GlobalKey> keys;
  final bool hidden;
  final int revealed;
  final Set<int> missed;
  final bool showMeaning;
  final bool showSounds;
  final bool complete;
  final ValueChanged<int> onTapWord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: segment.line == 0
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${segment.verse}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var w = 0; w < segment.words.length; w++)
                    KeyedSubtree(
                      key: keys[firstIndex + w],
                      child: _WordTile(
                        word: segment.words[w],
                        shown: !hidden || firstIndex + w < revealed,
                        isNext:
                            hidden && !complete && firstIndex + w == revealed,
                        missed: missed.contains(firstIndex + w),
                        showMeaning: showMeaning,
                        showSounds: showSounds,
                        onTap: () => onTapWord(firstIndex + w),
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

class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.shown,
    required this.isNext,
    required this.missed,
    required this.showMeaning,
    required this.showSounds,
    required this.onTap,
  });

  final MemoryWord word;
  final bool shown;
  final bool isNext;
  final bool missed;
  final bool showMeaning;
  final bool showSounds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = memoryHebrewStyle(
      theme,
      28,
    ).copyWith(color: missed ? scheme.error : scheme.onSurface);
    // A hidden word keeps its own width (laid out invisibly), so the shape of
    // the line stays; the next word to recite is underlined more strongly.
    final Widget hebrew = shown
        ? Text(word.text, style: style)
        : Stack(
            children: [
              Opacity(opacity: 0, child: Text(word.text, style: style)),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isNext ? scheme.primary : scheme.outlineVariant,
                        width: isNext ? 3 : 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
    final small = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            hebrew,
            if (shown && showSounds && word.translit.isNotEmpty)
              Text(
                word.translit,
                textDirection: TextDirection.ltr,
                style: small,
              ),
            if (shown && showMeaning && word.gloss.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  word.gloss,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  style: small,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    super.key,
    required this.item,
    required this.run,
    required this.sessionXp,
    required this.sessionCards,
    required this.sessionLearnt,
    required this.streakDays,
    required this.onLearnMore,
    required this.onShape,
  });

  final MemoryItem item;
  final bool run;
  final int sessionXp;
  final int sessionCards;
  final int sessionLearnt;
  final int streakDays;
  final VoidCallback onLearnMore;
  final VoidCallback onShape;

  String _nextDue() {
    if (item.nextDueEpoch <= 0) return '';
    final due = DateTime.fromMillisecondsSinceEpoch(item.nextDueEpoch * 1000);
    final minutes = due.difference(DateTime.now()).inMinutes;
    if (minutes < 1) return 'Next review: now';
    if (minutes < 60) return 'Next review in $minutes min';
    final hours = (minutes / 60).round();
    if (hours < 24) return 'Next review in $hours h';
    final days = (hours / 24).round();
    return 'Next review in $days ${days == 1 ? 'day' : 'days'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = item.kind == 'empty';
    // The next verse waits for its section to be shaped.
    final shape = !run && item.shapePassageId.isNotEmpty;
    final next = _nextDue();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              empty
                  ? Icons.playlist_add
                  : shape && !item.canLearnMore
                  ? Icons.wrap_text
                  : Icons.celebration,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              empty
                  ? 'No passages yet'
                  : run
                  ? (sessionCards > 0 ? 'Recited!' : 'Nothing learnt yet')
                  : shape && !item.canLearnMore
                  ? 'Shape the next section'
                  : 'All caught up',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (sessionCards > 0)
              Text(
                '$sessionCards ${sessionCards == 1 ? 'card' : 'cards'} · +$sessionXp XP'
                '${sessionLearnt > 0 ? ' · $sessionLearnt new ${sessionLearnt == 1 ? 'verse' : 'verses'} learnt' : ''}'
                '${streakDays > 0 ? ' · $streakDays-day streak' : ''}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            if (next.isNotEmpty && !run) ...[
              const SizedBox(height: 4),
              Text(
                next,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (shape && !item.canLearnMore) ...[
              const SizedBox(height: 8),
              Text(
                'Read it through, work out what each verse says, and mark '
                'where its lines break. Learning carries on as soon as the '
                'section is shaped.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            if (item.canLearnMore && !run)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: onLearnMore,
                  icon: const Icon(Icons.add),
                  label: const Text('Learn the next verse'),
                ),
              ),
            if (shape)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: item.canLearnMore
                    ? OutlinedButton.icon(
                        onPressed: onShape,
                        icon: const Icon(Icons.wrap_text),
                        label: const Text('Shape the next section'),
                      )
                    : FilledButton.icon(
                        onPressed: onShape,
                        icon: const Icon(Icons.wrap_text),
                        label: const Text('Shape the next section'),
                      ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to passages'),
            ),
          ],
        ),
      ),
    );
  }
}
