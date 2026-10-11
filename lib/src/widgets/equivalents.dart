import 'package:flutter/material.dart';

import 'greek_word_sheet.dart';
import 'word_info_sheet.dart';

/// One word of the other New Testament text a word is rendered by, as the
/// alignment of the Peshitta and the Greek found it.
typedef Equivalent = ({
  String text,
  String gloss,
  int links,
  VoidCallback onOpen,
});

/// The words of the other New Testament text a word is rendered by, each
/// with its gloss and how many times, opening that word's own sheet.
class EquivalentsSection extends StatelessWidget {
  const EquivalentsSection({
    super.key,
    required this.title,
    required this.equivalents,
  });

  /// "Greek equivalents", "Peshitta equivalents".
  final String title;
  final List<Equivalent> equivalents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message:
                'Found by aligning the Peshitta with the Greek verse by verse, '
                'not given by any edition',
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final e in equivalents)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  onPressed: e.onOpen,
                  label: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: e.text,
                          style: const TextStyle(
                            fontFamily: 'Cardo',
                            fontFamilyFallback: ['Noto Serif Hebrew'],
                            fontSize: 16,
                          ),
                        ),
                        if (e.gloss.isNotEmpty)
                          TextSpan(
                            text: '  ${e.gloss}',
                            style: theme.textTheme.bodySmall,
                          ),
                        TextSpan(
                          text: ' · ${e.links}×',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A Greek dictionary form's sheet, over the one it was opened from.
void openGreekLemmaSheet(
  BuildContext context, {
  required String lemma,
  bool useEnglishBookNames = false,
  bool ntSyriac = false,
  void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * 0.8,
      child: GreekWordSheet(
        word: lemma,
        lemma: lemma,
        useEnglishBookNames: useEnglishBookNames,
        ntSyriac: ntSyriac,
        onNavigateToPassage: onNavigateToPassage,
      ),
    ),
  );
}

/// A Peshitta word's sheet, over the one it was opened from.
void openSyriacWordSheet(
  BuildContext context, {
  required String word,
  bool useEnglishBookNames = false,
  bool ntSyriac = false,
  void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => WordInfoSheet(
      word: word,
      syriac: true,
      ntSyriac: ntSyriac,
      useEnglishBookNames: useEnglishBookNames,
      onNavigateToPassage: onNavigateToPassage,
    ),
  );
}
