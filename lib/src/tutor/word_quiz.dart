import 'dart:math';

import 'package:flutter/material.dart';

import 'alphabet_data.dart';
import 'words_tab.dart';

enum _WordQuizMode { meaning, reading }

/// Multiple-choice drill over the vocabulary words available so far: either
/// read the Hebrew and pick the meaning, or read a meaning and pick the
/// Hebrew word.
class WordQuiz extends StatefulWidget {
  /// Words eligible for quizzing (the ones browsed so far, with a minimum
  /// starter pool).
  final List<TutorWord> pool;
  final Map<String, int> mastery;
  final void Function(String surface, bool correct) onAnswered;

  const WordQuiz({
    super.key,
    required this.pool,
    required this.mastery,
    required this.onAnswered,
  });

  @override
  State<WordQuiz> createState() => _WordQuizState();
}

class _WordQuizState extends State<WordQuiz> {
  final Random _rng = Random();

  _WordQuizMode _mode = _WordQuizMode.meaning;
  int _target = 0;
  List<int> _options = [];
  int? _chosen;
  int _sessionCorrect = 0;
  int _sessionTotal = 0;

  int _masteryOf(int index) => (widget.mastery[widget.pool[index].surface] ?? 0)
      .clamp(0, kMasteryTarget);

  @override
  void initState() {
    super.initState();
    _nextQuestion();
  }

  // Weighted pick favouring words the user hasn't mastered yet, never
  // repeating the previous target.
  int _pickTarget() {
    final weights = List.generate(widget.pool.length, (i) {
      if (_sessionTotal > 0 && i == _target) return 0;
      final w = kMasteryTarget + 1 - _masteryOf(i);
      return w * w;
    });
    final total = weights.reduce((a, b) => a + b);
    var roll = _rng.nextInt(max(total, 1));
    for (var i = 0; i < weights.length; i++) {
      roll -= weights[i];
      if (roll < 0) return i;
    }
    return widget.pool.length - 1;
  }

  void _nextQuestion() {
    final target = _pickTarget();
    // Distractors must differ in both spelling and meaning, or the right
    // answer is ambiguous.
    final used = <String>{widget.pool[target].gloss};
    final others = List.generate(widget.pool.length, (i) => i)
      ..remove(target)
      ..shuffle(_rng);
    final distractors = <int>[];
    for (final i in others) {
      if (distractors.length == 3) break;
      if (used.add(widget.pool[i].gloss)) distractors.add(i);
    }
    final options = [target, ...distractors]..shuffle(_rng);
    setState(() {
      _target = target;
      _options = options;
      _chosen = null;
    });
  }

  void _answer(int index) {
    if (_chosen != null) return;
    final correct = index == _target;
    setState(() {
      _chosen = index;
      _sessionTotal++;
      if (correct) _sessionCorrect++;
    });
    widget.onAnswered(widget.pool[_target].surface, correct);
  }

  void _setMode(_WordQuizMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _nextQuestion();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    if (widget.pool.length < 4) {
      return const Center(child: Text('Browse some words first'));
    }
    final mastered = widget.pool
        .where((w) => (widget.mastery[w.surface] ?? 0) >= kMasteryTarget)
        .length;
    final word = widget.pool[_target];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: mastered / widget.pool.length,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Mastered $mastered/${widget.pool.length}',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: SegmentedButton<_WordQuizMode>(
                  segments: const [
                    ButtonSegment(
                      value: _WordQuizMode.meaning,
                      label: Text('What does it mean?'),
                    ),
                    ButtonSegment(
                      value: _WordQuizMode.reading,
                      label: Text('Find the word'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => _setMode(s.first),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _mode == _WordQuizMode.meaning
                      ? Column(
                          children: [
                            Text(
                              'What does this word mean?',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              word.surface,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontFamily: 'Cardo',
                                fontFamilyFallback: ['Noto Serif Hebrew'],
                                fontSize: 56,
                                height: 1.2,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Text(
                              'Which word means…',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              word.gloss,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: _mode == _WordQuizMode.meaning ? 2.2 : 1.8,
                children: [
                  for (final option in _options)
                    _OptionTile(
                      label: _mode == _WordQuizMode.meaning
                          ? widget.pool[option].gloss
                          : widget.pool[option].surface,
                      hebrew: _mode == _WordQuizMode.reading,
                      state: _chosen == null
                          ? _OptionState.idle
                          : option == _target
                          ? _OptionState.correct
                          : option == _chosen
                          ? _OptionState.wrong
                          : _OptionState.dimmed,
                      onTap: () => _answer(option),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_chosen != null) ...[
                _AnswerCard(word: word, correct: _chosen == _target),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _nextQuestion,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                ),
              ],
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Session: $_sessionCorrect/$_sessionTotal correct',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _OptionTile extends StatelessWidget {
  final String label;
  final bool hebrew;
  final _OptionState state;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.hebrew,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (state) {
      _OptionState.idle => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurface,
      ),
      _OptionState.correct => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      _OptionState.wrong => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
      ),
      _OptionState.dimmed => (
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              textDirection: hebrew ? TextDirection.rtl : TextDirection.ltr,
              style: hebrew
                  ? TextStyle(
                      fontFamily: 'Cardo',
                      fontFamilyFallback: const ['Noto Serif Hebrew'],
                      fontSize: 32,
                      color: foreground,
                    )
                  : theme.textTheme.titleSmall?.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final TutorWord word;
  final bool correct;

  const _AnswerCard({required this.word, required this.correct});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = correct
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: correct
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            correct ? Icons.check_circle_outline : Icons.close,
            color: foreground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${word.surface} — ${word.gloss}'
              '${word.note != null ? '. ${word.note}' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontFamilyFallback: const ['Cardo', 'Noto Serif Hebrew'],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
