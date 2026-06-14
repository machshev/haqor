import 'package:flutter/material.dart';

import 'alphabet_data.dart';

/// Flashcard browser for the whole alphabet: a jump strip of all letters
/// above a swipeable pager of [LetterCard]s.
class LettersTab extends StatefulWidget {
  final List<int> mastery;

  const LettersTab({super.key, required this.mastery});

  @override
  State<LettersTab> createState() => _LettersTabState();
}

class _LettersTabState extends State<LettersTab> {
  static const _stripItemWidth = 48.0;

  final PageController _pageController = PageController();
  final ScrollController _stripController = ScrollController();
  int _index = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _stripController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (!_stripController.hasClients) return;
    // Keep the current letter roughly centered in the strip.
    final viewport = _stripController.position.viewportDimension;
    final target = (index * _stripItemWidth - (viewport - _stripItemWidth) / 2)
        .clamp(0.0, _stripController.position.maxScrollExtent);
    _stripController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _jumpTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView.builder(
            controller: _stripController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: kAlphabet.length,
            itemBuilder: (context, i) {
              final selected = i == _index;
              final mastered = widget.mastery[i] >= kMasteryTarget;
              return SizedBox(
                width: _stripItemWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Material(
                    color: selected
                        ? theme.colorScheme.primaryContainer
                        : mastered
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _jumpTo(i),
                      child: Center(
                        child: Text(
                          kAlphabet[i].letter,
                          style: TextStyle(
                            fontFamily: 'Cardo',
                            fontFamilyFallback: const ['Noto Serif Hebrew'],
                            fontSize: 22,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: kAlphabet.length,
            itemBuilder: (context, i) =>
                SingleChildScrollView(child: LetterCard(letter: kAlphabet[i])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${_index + 1} / ${kAlphabet.length}  —  swipe to browse',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full teaching card for one letter: glyph (with final form), name, sound,
/// numeric value, example word and tip. Used by the letters pager and as a
/// bottom-sheet detail from word cards.
class LetterCard extends StatelessWidget {
  final HebrewLetter letter;

  const LetterCard({super.key, required this.letter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottomPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        letter.letter,
                        style: const TextStyle(
                          fontFamily: 'Cardo',
                          fontFamilyFallback: ['Noto Serif Hebrew'],
                          fontSize: 96,
                          height: 1.1,
                        ),
                      ),
                      if (letter.finalForm != null) ...[
                        const SizedBox(width: 24),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              letter.finalForm!,
                              style: TextStyle(
                                fontFamily: 'Cardo',
                                fontFamilyFallback: const ['Noto Serif Hebrew'],
                                fontSize: 56,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'final form',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${letter.name} · ${letter.hebrewName}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    letter.translit,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    letter.sound,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Chip(
                    label: Text('Numeric value: ${letter.value}'),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    letter.example,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontFamily: 'Cardo',
                      fontFamilyFallback: ['Noto Serif Hebrew'],
                      fontSize: 36,
                    ),
                  ),
                  Text(
                    '${letter.exampleTranslit} — ${letter.exampleMeaning}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (letter.tip != null) ...[
                    const SizedBox(height: 16),
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
                              letter.tip!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
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

/// Open a [LetterCard] as a modal bottom sheet.
void showLetterSheet(BuildContext context, HebrewLetter letter) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: LetterCard(letter: letter),
    ),
  );
}
