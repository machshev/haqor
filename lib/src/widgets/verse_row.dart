import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../bindings/bindings.dart';

final RegExp _hebrewLetter = RegExp(r'[\u05D0-\u05EA]');

/// Maps displayed verse tokens to their lexical gloss positions.
///
/// The Bible text includes standalone punctuation such as the paseq (`׀`).
/// Those tokens remain visible, but the core deliberately does not emit a
/// gloss for them.
List<int?> verseGlossPositions(List<String> words) {
  var glossPosition = 0;
  return [
    for (final word in words)
      if (_hebrewLetter.hasMatch(word)) glossPosition++ else null,
  ];
}

class VerseRow extends StatefulWidget {
  const VerseRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.hebrewNumerals,
    required this.onTap,
    required this.onWordTap,
    this.fontSize = 20.0,
    this.fontFamily = 'Cardo',
    this.glossInterlinear = false,
  });

  final VerseEntry entry;
  final bool isSelected;
  final bool hebrewNumerals;
  final VoidCallback onTap;
  final void Function(String word) onWordTap;
  final double fontSize;
  final String fontFamily;
  final bool glossInterlinear;

  @override
  State<VerseRow> createState() => _VerseRowState();
}

class _VerseRowState extends State<VerseRow> {
  List<String> _words = [];
  List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(VerseRow old) {
    super.didUpdateWidget(old);
    if (old.entry.text != widget.entry.text ||
        old.onWordTap != widget.onWordTap) {
      _disposeRecognizers();
      _rebuild();
    }
  }

  void _rebuild() {
    _words = widget.entry.text.split(' ').where((w) => w.isNotEmpty).toList();
    _recognizers = _words
        .map((w) => TapGestureRecognizer()..onTap = () => widget.onWordTap(w))
        .toList();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [];
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wordStyle = TextStyle(
      fontFamily: widget.fontFamily,
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w500,
      height: 1.6,
      color: widget.isSelected
          ? theme.colorScheme.onPrimaryContainer
          : theme.colorScheme.onSurface,
    );

    final spans = <InlineSpan>[];
    for (var i = 0; i < _words.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      spans.add(
        TextSpan(
          text: _words[i],
          style: wordStyle,
          recognizer: _recognizers[i],
        ),
      );
    }

    final content = widget.glossInterlinear && widget.entry.glosses.isNotEmpty
        ? Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              textDirection: TextDirection.rtl,
              children: [
                for (final (i, glossPosition) in verseGlossPositions(
                  _words,
                ).indexed)
                  GestureDetector(
                    onTap: () => widget.onWordTap(
                      _words[i].replaceAll(
                        RegExp(
                          r'[\u0591-\u05AF\u05BD\u05BE\u05C0\u05C3\u05C4-\u05C6]',
                        ),
                        '',
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_words[i], style: wordStyle),
                          if (glossPosition != null &&
                              glossPosition < widget.entry.glosses.length &&
                              widget.entry.glosses[glossPosition].isNotEmpty)
                            Text(
                              widget.entry.glosses[glossPosition],
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        : SelectableText.rich(
            TextSpan(children: spans),
            textDirection: TextDirection.rtl,
          );
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.hebrewNumerals
                    ? _toHebrewNumeral(widget.entry.verse)
                    : '${widget.entry.verse}',
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
