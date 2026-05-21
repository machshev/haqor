import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../bindings/bindings.dart';

class VerseRow extends StatelessWidget {
  const VerseRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.hebrewNumerals,
    required this.onTap,
  });

  final VerseEntry entry;
  final bool isSelected;
  final bool hebrewNumerals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                entry.text,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.getFont(
                  'David Libre',
                  fontSize: 20,
                  height: 1.6,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hebrewNumerals ? _toHebrewNumeral(entry.verse) : '${entry.verse}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Converts 1–999 to Hebrew numerals using geresh/gershayim
String _toHebrewNumeral(int n) {
  const units = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  const hundreds = ['', 'ק', 'ר', 'ש', 'ת'];

  if (n <= 0) return n.toString();

  String result = '';
  int remaining = n;

  final h = remaining ~/ 100;
  remaining %= 100;
  if (h > 0 && h <= 4) result += hundreds[h];

  // 15 and 16 are written as טו / טז to avoid divine names
  if (remaining == 15) {
    result += 'טו';
    remaining = 0;
  } else if (remaining == 16) {
    result += 'טז';
    remaining = 0;
  }

  final t = remaining ~/ 10;
  final u = remaining % 10;
  if (t > 0) result += tens[t];
  if (u > 0) result += units[u];

  if (result.length == 1) return '$result׳';
  return '${result.substring(0, result.length - 1)}״${result[result.length - 1]}';
}
