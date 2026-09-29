import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import '../tutor/progress_sync.dart';
import 'memorise_page.dart' show memoryUtcOffset;

const _stageNames = [
  'Read it aloud',
  'Fill the gaps',
  'Fill the gaps',
  'First letters',
  'From memory',
];

const _stageHelp = [
  'Read the verse aloud two or three times, following the meaning.',
  'Say the whole verse aloud. Tap a gap only if you are stuck.',
  'Most words are hidden now. Say the whole verse, then check.',
  'Only first letters are left. Recite the verse, then check.',
  'Recite the verse from memory, then check yourself.',
];

const _gradeLabels = ['Forgot', 'Hard', 'Good', 'Easy'];

/// Practise the verses of one passage (or of all passages when `passageId`
/// is empty), one card at a time as the scheduler offers them. With
/// `runThrough`, instead recite the given verses of `book` in order, each
/// from memory.
class MemoryDrillPage extends StatefulWidget {
  const MemoryDrillPage({
    super.key,
    required this.passageId,
    required this.title,
    this.book,
    this.runThrough,
  });

  final String passageId;
  final String title;
  final int? book;
  final List<(int, int)>? runThrough;

  @override
  State<MemoryDrillPage> createState() => _MemoryDrillPageState();
}

class _MemoryDrillPageState extends State<MemoryDrillPage> {
  StreamSubscription<RustSignalPack<MemoryItem>>? _itemSub;
  StreamSubscription<RustSignalPack<MemoryReviewResult>>? _resultSub;
  MemoryItem? _item;
  int _seq = 0;
  bool _waiting = true;
  int _runIndex = 0;
  int _sessionXp = 0;
  int _sessionAnswers = 0;
  int _sessionLearnt = 0;
  MemoryReviewResult? _lastResult;

  bool get _isRunThrough => widget.runThrough != null;

  @override
  void initState() {
    super.initState();
    _itemSub = MemoryItem.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() {
        _item = pack.message;
        _seq++;
        _waiting = false;
      });
    });
    _resultSub = MemoryReviewResult.rustSignalStream.listen(_onResult);
    _requestNext();
  }

  @override
  void dispose() {
    _itemSub?.cancel();
    _resultSub?.cancel();
    super.dispose();
  }

  void _requestNext({bool extraNew = false}) {
    setState(() => _waiting = true);
    final run = widget.runThrough;
    if (run != null) {
      if (_runIndex >= run.length) {
        setState(() {
          _item = MemoryItem(
            kind: 'done',
            card: null,
            nextDueEpoch: 0,
            canLearnMore: false,
          );
          _waiting = false;
        });
        return;
      }
      final (chapter, verse) = run[_runIndex];
      GetMemoryCard(
        passageId: widget.passageId,
        book: widget.book ?? 1,
        chapter: chapter,
        verse: verse,
        recall: true,
      ).sendSignalToRust();
      return;
    }
    GetNextMemoryCard(
      passageId: widget.passageId,
      extraNew: extraNew,
      utcOffset: memoryUtcOffset(),
    ).sendSignalToRust();
  }

  void _grade(MemoryCard card, int grade) {
    SubmitMemoryReview(
      passageId: widget.passageId,
      book: card.book,
      chapter: card.chapter,
      verse: card.verse,
      grade: grade,
      runThrough: _isRunThrough,
      utcOffset: memoryUtcOffset(),
    ).sendSignalToRust();
    scheduleProgressSync();
    if (_isRunThrough) _runIndex++;
    _requestNext();
  }

  Future<void> _onResult(RustSignalPack<MemoryReviewResult> pack) async {
    if (!mounted) return;
    final r = pack.message;
    setState(() {
      _sessionXp += r.xp;
      _sessionAnswers++;
      if (r.firstGraduation) _sessionLearnt++;
      _lastResult = r;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final notes = <String>[
      '+${r.xp} XP',
      if (r.firstGraduation) 'verse ${r.chapter}:${r.verse} learnt!',
      if (!r.firstGraduation && r.intervalDays > 0 && r.stageBefore >= 4)
        'next in ${r.intervalDays} ${r.intervalDays == 1 ? 'day' : 'days'}',
      if (r.goalReachedNow) 'daily goal reached!',
    ];
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        content: Text(notes.join(' · ')),
      ),
    );
    if (r.completedPassages.isNotEmpty) {
      await _celebrate(
        icon: Icons.verified,
        title: 'Passage complete!',
        body:
            'Every verse of ${widget.title} is now learnt by heart. Keep '
            'reviewing and it will stay with you.',
      );
    }
    if (r.levelAfter > r.levelBefore) {
      await _celebrate(
        icon: Icons.military_tech,
        title: 'Level ${r.levelAfter}!',
        body: '${r.totalXp} XP earned so far.',
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
        title: Text(_isRunThrough ? 'Recite ${widget.title}' : widget.title),
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: _waiting || item == null
            ? const Center(
                key: ValueKey('memory-loading'),
                child: CircularProgressIndicator(),
              )
            : card != null
            ? KeyedSubtree(
                key: ValueKey(_seq),
                child: MemoryVerseDrill(
                  card: card,
                  runThrough: _isRunThrough,
                  runPosition: _isRunThrough
                      ? (_runIndex + 1, widget.runThrough!.length)
                      : null,
                  onGrade: (grade) => _grade(card, grade),
                ),
              )
            : _DoneView(
                key: const ValueKey('memory-done'),
                item: item,
                runThrough: _isRunThrough,
                sessionXp: _sessionXp,
                sessionAnswers: _sessionAnswers,
                sessionLearnt: _sessionLearnt,
                streakDays: result?.streakDays ?? 0,
                onLearnMore: () => _requestNext(extraNew: true),
              ),
      ),
    );
  }
}

/// One verse on the cue ladder. Hidden words are gaps (or first letters);
/// tapping a gap peeks at it and counts it as missed. "Check" reveals the
/// verse, where any word can be tapped to mark it missed, and the grade
/// buttons suggest a grade from how much was missed.
class MemoryVerseDrill extends StatefulWidget {
  const MemoryVerseDrill({
    super.key,
    required this.card,
    required this.runThrough,
    required this.runPosition,
    required this.onGrade,
  });

  final MemoryCard card;
  final bool runThrough;
  final (int, int)? runPosition;
  final ValueChanged<int> onGrade;

  @override
  State<MemoryVerseDrill> createState() => _MemoryVerseDrillState();
}

class _MemoryVerseDrillState extends State<MemoryVerseDrill> {
  final _missed = <int>{};
  bool _checked = false;
  bool _showMeaning = false;
  bool _showTranslit = false;

  MemoryCard get _card => widget.card;
  bool get _reading => _card.stage == 0;

  int get _hiddenCount => _card.words.where((w) => w.hidden).length;

  int get _suggestedGrade => suggestedMemoryGrade(
    _missed.length,
    _hiddenCount == 0 ? _card.words.length : _hiddenCount,
  );

  void _tapWord(int i) {
    final word = _card.words[i];
    setState(() {
      if (_checked) {
        _missed.contains(i) ? _missed.remove(i) : _missed.add(i);
      } else if (word.hidden) {
        _missed.add(i);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = widget.runPosition;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                Row(
                  children: [
                    Text(
                      '${_card.chapter}:${_card.verse}',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(width: 12),
                    if (!widget.runThrough) _StageLadder(stage: _card.stage),
                    const Spacer(),
                    Text(
                      position != null
                          ? '${position.$1} of ${position.$2}'
                          : _card.total > 0
                          ? 'verse ${_card.position} of ${_card.total}'
                          : '',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _card.isNew
                      ? 'New verse · ${_stageNames[0]}'
                      : _card.isReview
                      ? 'Review · ${_stageNames[4]}'
                      : _stageNames[_card.stage.clamp(0, 4)],
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  _stageHelp[_card.stage.clamp(0, 4)],
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (_card.cue.isNotEmpty && !_reading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '…${_card.cue}',
                      textDirection: TextDirection.rtl,
                      style: _hebrewStyle(
                        theme,
                        20,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 14,
                    children: [
                      for (var i = 0; i < _card.words.length; i++)
                        _WordTile(
                          word: _card.words[i],
                          revealed:
                              _reading ||
                              _checked ||
                              !_card.words[i].hidden ||
                              _missed.contains(i),
                          missed: _missed.contains(i),
                          showGloss: _reading || _showMeaning,
                          showTranslit: _reading || _showTranslit,
                          onTap: _reading ? null : () => _tapWord(i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (!_reading)
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
                        selected: _showTranslit,
                        onSelected: (v) => setState(() => _showTranslit = v),
                      ),
                    ],
                  ),
                if ((_reading || _showMeaning) && _card.translation.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _card.translation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (_checked)
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
            child: _reading
                ? FilledButton.icon(
                    onPressed: () => widget.onGrade(2),
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text('I have read it aloud'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  )
                : !_checked
                ? FilledButton.icon(
                    onPressed: () => setState(() => _checked = true),
                    icon: const Icon(Icons.visibility),
                    label: const Text('Check'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  )
                : Row(
                    children: [
                      for (var g = 0; g < 4; g++) ...[
                        if (g > 0) const SizedBox(width: 8),
                        Expanded(
                          child: g == _suggestedGrade
                              ? FilledButton(
                                  onPressed: () => widget.onGrade(g),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text(_gradeLabels[g]),
                                )
                              : OutlinedButton(
                                  onPressed: () => widget.onGrade(g),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text(_gradeLabels[g]),
                                ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The grade a check suggests: nothing missed is Good; a single slip, or up
/// to a quarter of the hidden words, Hard; more than that Forgot.
int suggestedMemoryGrade(int missed, int hidden) {
  if (missed == 0) return 2;
  return missed == 1 || missed <= hidden / 4 ? 1 : 0;
}

TextStyle _hebrewStyle(ThemeData theme, double size) =>
    (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: 'Cardo',
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: size,
      height: 1.4,
    );

/// Five dots for the cue ladder, filled up to the verse's stage.
class _StageLadder extends StatelessWidget {
  const _StageLadder({required this.stage});

  final int stage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Stage ${stage + 1} of 5',
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= stage ? scheme.primary : scheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.revealed,
    required this.missed,
    required this.showGloss,
    required this.showTranslit,
    required this.onTap,
  });

  final MemoryWord word;
  final bool revealed;
  final bool missed;
  final bool showGloss;
  final bool showTranslit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _hebrewStyle(
      theme,
      28,
    ).copyWith(color: missed ? scheme.error : scheme.onSurface);
    // A gap keeps the word's own width (the text is laid out but invisible),
    // so the verse's shape stays a cue; a first-letter hint sits at its start.
    final Widget hebrew = revealed
        ? Text(word.text, style: style)
        : Stack(
            children: [
              Opacity(opacity: 0, child: Text(word.text, style: style)),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: scheme.primary, width: 2),
                    ),
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  child: word.hint.isEmpty
                      ? null
                      : Text(
                          word.hint,
                          style: style.copyWith(color: scheme.primary),
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
            if (revealed && showTranslit && word.translit.isNotEmpty)
              Text(
                word.translit,
                textDirection: TextDirection.ltr,
                style: small,
              ),
            if (revealed && showGloss && word.gloss.isNotEmpty)
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
    required this.runThrough,
    required this.sessionXp,
    required this.sessionAnswers,
    required this.sessionLearnt,
    required this.streakDays,
    required this.onLearnMore,
  });

  final MemoryItem item;
  final bool runThrough;
  final int sessionXp;
  final int sessionAnswers;
  final int sessionLearnt;
  final int streakDays;
  final VoidCallback onLearnMore;

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
    final next = _nextDue();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              empty ? Icons.playlist_add : Icons.celebration,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              empty
                  ? 'No passages yet'
                  : runThrough
                  ? 'Recited!'
                  : 'All caught up',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (sessionAnswers > 0)
              Text(
                '$sessionAnswers answers · +$sessionXp XP'
                '${sessionLearnt > 0 ? ' · $sessionLearnt new ${sessionLearnt == 1 ? 'verse' : 'verses'} learnt' : ''}'
                '${streakDays > 0 ? ' · $streakDays-day streak' : ''}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            if (next.isNotEmpty && !runThrough) ...[
              const SizedBox(height: 4),
              Text(
                next,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (item.canLearnMore && !runThrough)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: onLearnMore,
                  icon: const Icon(Icons.add),
                  label: const Text('Learn another verse'),
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
