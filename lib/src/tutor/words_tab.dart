import 'package:flutter/material.dart';

import '../bindings/bindings.dart';
import 'alphabet_data.dart';
import 'letters_tab.dart';
import 'vocab_overrides.dart';

/// One word of the frequency-ordered vocabulary, ready for display: the Rust
/// entry merged with any curated override, plus the alphabet indices of its
/// letters so new letters can be taught alongside the word.
class TutorWord {
  final String surface;
  final int occurrences;
  final String gloss;
  final String? note;
  final String morph; // empty when unknown
  final String root; // empty when unresolved
  final String? lexicalClass; // "function" | "proper" | null
  final List<int> letters; // distinct alphabet indices, in word order

  const TutorWord({
    required this.surface,
    required this.occurrences,
    required this.gloss,
    required this.note,
    required this.morph,
    required this.root,
    required this.lexicalClass,
    required this.letters,
  });
}

/// Merge the Rust vocabulary with curated overrides: overridden glosses win
/// (and suppress the automatic morphology, which the override note replaces),
/// near-duplicate spellings collapse (בֶּן/בֶן), and entries left without any
/// gloss are dropped rather than shown as meaningless cards.
List<TutorWord> buildTutorWords(List<VocabEntry> entries) {
  final seen = <String>{};
  final words = <TutorWord>[];
  for (final e in entries) {
    final key = vocabKey(e.surface);
    if (!seen.add(key)) continue;
    final override = kVocabOverrides[key];
    final gloss = override?.gloss ?? e.gloss;
    if (gloss.isEmpty) continue;
    final letters = <int>[];
    for (final ch in e.surface.runes) {
      final idx = kLetterIndex[String.fromCharCode(ch)];
      if (idx != null && !letters.contains(idx)) letters.add(idx);
    }
    words.add(
      TutorWord(
        surface: e.surface,
        occurrences: e.occurrences,
        gloss: gloss,
        note: override?.note,
        morph: override == null ? e.morph : '',
        root: e.root,
        lexicalClass: e.lexicalClass,
        letters: letters,
      ),
    );
  }
  return words;
}

/// Swipeable pager of vocabulary cards in frequency order. Letters the user
/// hasn't met yet are introduced on the first card that contains them.
class WordsTab extends StatefulWidget {
  final List<TutorWord> words;
  final int initialIndex;

  /// Letters already introduced (alphabet indices) — owned by the parent and
  /// updated through [onWordViewed].
  final Set<int> lettersSeen;

  /// Called when a card becomes current, with the letters it newly
  /// introduces (possibly empty).
  final void Function(int index, List<int> newLetters) onWordViewed;

  const WordsTab({
    super.key,
    required this.words,
    required this.initialIndex,
    required this.lettersSeen,
    required this.onWordViewed,
  });

  @override
  State<WordsTab> createState() => _WordsTabState();
}

class _WordsTabState extends State<WordsTab> {
  late final PageController _pageController;
  late int _index;

  /// Letters first introduced by each visited card, kept for the session so
  /// the "new letters" teaching block doesn't vanish once they're marked
  /// seen.
  final Map<int, List<int>> _introduced = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
    _visit(_index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _visit(int index) {
    final fresh = widget.words[index].letters
        .where((l) => !widget.lettersSeen.contains(l))
        .toList();
    if (fresh.isNotEmpty) {
      _introduced[index] = fresh;
    }
    widget.onWordViewed(index, fresh);
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _visit(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: widget.words.length,
            itemBuilder: (context, i) => _WordCard(
              word: widget.words[i],
              rank: i + 1,
              newLetters: _introduced[i] ?? const [],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Word ${_index + 1} of ${widget.words.length}  —  most frequent '
            'first',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _WordCard extends StatelessWidget {
  final TutorWord word;
  final int rank;
  final List<int> newLetters;

  const _WordCard({
    required this.word,
    required this.rank,
    required this.newLetters,
  });

  String get _classLabel => switch (word.lexicalClass) {
    'function' => 'particle',
    'proper' => 'name',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottomPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#$rank',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${word.occurrences}× in the Bible',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    word.surface,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontFamily: 'Cardo',
                      fontFamilyFallback: ['Noto Serif Hebrew'],
                      fontSize: 64,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    word.gloss,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (word.morph.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        word.morph,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamilyFallback: const [
                            'Cardo',
                            'Noto Serif Hebrew',
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (_classLabel.isNotEmpty)
                        Chip(
                          label: Text(_classLabel),
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          padding: EdgeInsets.zero,
                        ),
                      if (word.root.isNotEmpty)
                        Chip(
                          label: Text(
                            'root ${word.root}',
                            style: const TextStyle(
                              fontFamilyFallback: [
                                'Cardo',
                                'Noto Serif Hebrew',
                              ],
                            ),
                          ),
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  if (word.note != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 18,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              word.note!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontFamilyFallback: const [
                                  'Cardo',
                                  'Noto Serif Hebrew',
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Letters in this word',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    textDirection: TextDirection.rtl,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final idx in word.letters)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _LetterChip(
                            letterIndex: idx,
                            isNew: newLetters.contains(idx),
                          ),
                        ),
                    ],
                  ),
                  if (newLetters.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            newLetters.length == 1
                                ? 'New letter'
                                : 'New letters',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          for (final idx in newLetters)
                            _NewLetterRow(letter: kAlphabet[idx]),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LetterChip extends StatelessWidget {
  final int letterIndex;
  final bool isNew;

  const _LetterChip({required this.letterIndex, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Badge(
      isLabelVisible: isNew,
      label: const Text('new'),
      child: Material(
        color: isNew
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showLetterSheet(context, kAlphabet[letterIndex]),
          child: SizedBox(
            width: 44,
            height: 48,
            child: Center(
              child: Text(
                kAlphabet[letterIndex].letter,
                style: const TextStyle(
                  fontFamily: 'Cardo',
                  fontFamilyFallback: ['Noto Serif Hebrew'],
                  fontSize: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewLetterRow extends StatelessWidget {
  final HebrewLetter letter;

  const _NewLetterRow({required this.letter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showLetterSheet(context, letter),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                letter.finalForm == null
                    ? letter.letter
                    : '${letter.letter} ${letter.finalForm}',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontFamily: 'Cardo',
                  fontFamilyFallback: ['Noto Serif Hebrew'],
                  fontSize: 32,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    letter.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(letter.sound, style: theme.textTheme.bodySmall),
                  if (letter.tip != null)
                    Text(
                      letter.tip!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
