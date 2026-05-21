import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../bible_data.dart';

class BookSelectorSheet extends StatelessWidget {
  const BookSelectorSheet({super.key, required this.currentIndex});
  final int currentIndex;

  static const _sections = [
    (hebrew: 'תּוֹרָה', label: 'Torah', start: 0, end: 5),
    (hebrew: 'נְבִיאִים', label: "Nevi'im", start: 5, end: 26),
    (hebrew: 'כְּתוּבִים', label: 'Ketuvim', start: 26, end: 39),
    (hebrew: 'בְּרִית חֲדָשָׁה', label: 'Brit Khadasha', start: 39, end: 66),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sectionColors = [
      theme.colorScheme.primaryContainer,
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiaryContainer,
      theme.colorScheme.surfaceContainerHighest,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          for (int s = 0; s < _sections.length; s++) ...[
            _BookSectionHeader(
              hebrew: _sections[s].hebrew,
              label: _sections[s].label,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (int i = _sections[s].start; i < _sections[s].end; i++)
                  _BookChip(
                    bookIndex: i,
                    book: kBooks[i],
                    selected: i == currentIndex,
                    color: sectionColors[s],
                  ),
              ],
            ),
            if (s < _sections.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _BookSectionHeader extends StatelessWidget {
  const _BookSectionHeader({required this.hebrew, required this.label});
  final String hebrew;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          hebrew,
          textDirection: TextDirection.rtl,
          style: GoogleFonts.getFont(
            'David Libre',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _BookChip extends StatelessWidget {
  const _BookChip({
    required this.bookIndex,
    required this.book,
    required this.selected,
    required this.color,
  });
  final int bookIndex;
  final BookInfo book;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '${book.transliteration}  ${book.hebrew}',
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(bookIndex),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 44,
          height: 32,
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : color,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Text(
            book.short,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
