import 'dart:math';

import 'package:flutter/material.dart';

import 'alphabet_data.dart';

enum _QuizMode { nameTheLetter, findTheLetter }

class AlphabetQuiz extends StatefulWidget {
  final List<int> mastery;
  final void Function(int letterIndex, bool correct) onAnswered;

  const AlphabetQuiz({
    super.key,
    required this.mastery,
    required this.onAnswered,
  });

  @override
  State<AlphabetQuiz> createState() => _AlphabetQuizState();
}

class _AlphabetQuizState extends State<AlphabetQuiz> {
  final Random _rng = Random();

  _QuizMode _mode = _QuizMode.nameTheLetter;
  int _target = 0;
  List<int> _options = [];
  int? _chosen; // null until the user answers
  int _sessionCorrect = 0;
  int _sessionTotal = 0;

  @override
  void initState() {
    super.initState();
    _nextQuestion();
  }

  // Weighted pick favouring letters the user hasn't mastered yet, never
  // repeating the previous target.
  int _pickTarget() {
    final weights = List.generate(kAlphabet.length, (i) {
      if (_sessionTotal > 0 && i == _target) return 0;
      final w = kMasteryTarget + 1 - widget.mastery[i].clamp(0, kMasteryTarget);
      return w * w; // 1 (mastered) .. 16 (untouched)
    });
    final total = weights.reduce((a, b) => a + b);
    var roll = _rng.nextInt(total);
    for (var i = 0; i < weights.length; i++) {
      roll -= weights[i];
      if (roll < 0) return i;
    }
    return kAlphabet.length - 1;
  }

  void _nextQuestion() {
    final target = _pickTarget();
    final others = List.generate(kAlphabet.length, (i) => i)
      ..remove(target)
      ..shuffle(_rng);
    final options = [target, ...others.take(3)]..shuffle(_rng);
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
    widget.onAnswered(_target, correct);
  }

  void _setMode(_QuizMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _nextQuestion();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final mastered = widget.mastery.where((m) => m >= kMasteryTarget).length;
    final letter = kAlphabet[_target];

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
                        value: mastered / kAlphabet.length,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Mastered $mastered/${kAlphabet.length}',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: SegmentedButton<_QuizMode>(
                  segments: const [
                    ButtonSegment(
                      value: _QuizMode.nameTheLetter,
                      label: Text('Name the letter'),
                    ),
                    ButtonSegment(
                      value: _QuizMode.findTheLetter,
                      label: Text('Find the letter'),
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
                  child: _mode == _QuizMode.nameTheLetter
                      ? Column(
                          children: [
                            Text(
                              'What is this letter called?',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              letter.letter,
                              style: const TextStyle(
                                fontFamily: 'Cardo',
                                fontFamilyFallback: ['Noto Serif Hebrew'],
                                fontSize: 88,
                                height: 1.1,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Text(
                              'Which letter is this?',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${letter.name} · ${letter.hebrewName}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              letter.sound,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
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
                childAspectRatio: _mode == _QuizMode.nameTheLetter ? 2.6 : 1.8,
                children: [
                  for (final option in _options)
                    _OptionTile(
                      label: _mode == _QuizMode.nameTheLetter
                          ? kAlphabet[option].name
                          : kAlphabet[option].letter,
                      hebrew: _mode == _QuizMode.findTheLetter,
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
                _AnswerCard(letter: letter, correct: _chosen == _target),
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: hebrew
                ? TextStyle(
                    fontFamily: 'Cardo',
                    fontFamilyFallback: const ['Noto Serif Hebrew'],
                    fontSize: 40,
                    color: foreground,
                  )
                : theme.textTheme.titleMedium?.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final HebrewLetter letter;
  final bool correct;

  const _AnswerCard({required this.letter, required this.correct});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            color: correct
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${letter.letter} is ${letter.name} — ${letter.sound}. '
              'As in ${letter.example} (${letter.exampleTranslit}, '
              '“${letter.exampleMeaning}”).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: correct
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onErrorContainer,
                fontFamilyFallback: const ['Cardo', 'Noto Serif Hebrew'],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
