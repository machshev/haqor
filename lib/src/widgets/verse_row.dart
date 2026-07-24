import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../bindings/bindings.dart';
import '../tutor/transliterate.dart';

final RegExp _sourceTextLetter = RegExp(
  r'[\u05D0-\u05EA\u0710-\u072F\u074D-\u074F]',
);
final RegExp _hebrewMarks = RegExp(r'[^\u05D0-\u05EA]');
final RegExp _yahwehWithPrefixes = RegExp(r'^[ובלכמשה]*יהוה$');
final RegExp _readerWordMarks = RegExp(
  r'[\u0591-\u05AF\u05BD\u05BE\u05C0\u05C3\u05C4-\u05C6]',
);
const _maqaf = '\u05BE';

String compactInterlinearMorphology(String morphology) {
  const abbreviations = {
    'noun': 'N',
    'proper': 'prop',
    'verb': 'V',
    'singular': 'sg',
    'plural': 'pl',
    'dual': 'du',
    'absolute': 'abs',
    'construct': 'cstr',
    'perfect': 'perf',
    'imperfect': 'impf',
    'imperative': 'imp',
  };
  return morphology
      .split(RegExp(r'\s+'))
      .map((part) => abbreviations[part.toLowerCase()] ?? part)
      .join(' ');
}

/// Whether [word] is the tetragrammaton, allowing common attached particles.
bool isYahweh(String word) =>
    _yahwehWithPrefixes.hasMatch(word.replaceAll(_hebrewMarks, ''));

/// Splits a maqaf from its neighbouring word for interlinear display.
///
/// The Bible text preserves the printed convention of a trailing maqaf followed
/// by a space (`עַל־ פְּנֵי`). Interlinear mode gives the mark its own column so
/// that both joined words keep their own aligned glosses.
List<String> interlinearVerseWords(List<String> words) {
  final parts = <String>[];
  for (final word in words) {
    final wordParts = word.split(_maqaf);
    for (var i = 0; i < wordParts.length; i++) {
      if (wordParts[i].isNotEmpty) parts.add(wordParts[i]);
      if (i < wordParts.length - 1) parts.add(_maqaf);
    }
  }
  return parts;
}

/// Maps displayed verse tokens to their lexical gloss positions.
///
/// The Bible text includes standalone punctuation such as the paseq (`׀`).
/// Those tokens remain visible, but the core deliberately does not emit a
/// gloss for them.
List<int?> verseGlossPositions(List<String> words) {
  var glossPosition = 0;
  return [
    for (final word in words)
      if (_sourceTextLetter.hasMatch(word)) glossPosition++ else null,
  ];
}

double verseRowScrollExtent({
  required double fontSize,
  required String fontFamily,
  required bool interlinear,
}) {
  final textPainter = TextPainter(
    text: TextSpan(
      text: 'אבגדהוזחט',
      style: TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: const ['Noto Serif Hebrew'],
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.6,
      ),
    ),
    textDirection: TextDirection.rtl,
    maxLines: 1,
  )..layout();

  final lineHeight = textPainter.preferredLineHeight;
  final verticalMargin = interlinear ? 2.0 : 1.0;
  final verticalPadding = interlinear ? 8.0 : 4.0;
  return lineHeight + (verticalMargin * 2) + (verticalPadding * 2);
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
    this.showCantillation = true,
    this.glossInterlinear = false,
    this.morphologyInterlinear = false,
    this.highlightProperNames = false,
  });

  final VerseEntry entry;
  final bool isSelected;
  final bool hebrewNumerals;
  final VoidCallback onTap;
  final void Function(String word, String? readerGloss, int? position)
  onWordTap;
  final double fontSize;
  final String fontFamily;
  final bool showCantillation;
  final bool glossInterlinear;
  final bool morphologyInterlinear;
  final bool highlightProperNames;

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
    if (old.entry.text != widget.entry.text) {
      _disposeRecognizers();
      _rebuild();
    }
  }

  void _rebuild() {
    _words = widget.entry.text.split(' ').where((w) => w.isNotEmpty).toList();
    final positions = verseGlossPositions(_words);
    _recognizers = [
      for (final (i, word) in _words.indexed)
        TapGestureRecognizer()
          ..onTap = () => widget.onWordTap(word, null, positions[i]),
    ];
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
    final displayWords = widget.showCantillation
        ? _words
        : _words.map(stripCantillation).toList();
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
    final properNameStyle = wordStyle.copyWith(
      color: theme.colorScheme.tertiary,
      fontWeight: FontWeight.w700,
    );
    final yahwehStyle = wordStyle.copyWith(
      // A warm, legible gold that remains distinct from the ordinary
      // proper-name colour in both light and dark themes.
      color: const Color(0xFFB8860B),
      fontWeight: FontWeight.w800,
    );
    final morphologyStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.secondary,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );
    TextStyle styleForWord(String word, int lexicalPosition) {
      if (!widget.highlightProperNames) return wordStyle;
      // The corpus's traditional pointing `יַהְוֶה` currently has a verb
      // analysis, so its special reader treatment must not depend on the
      // general proper-name flag.
      if (isYahweh(word)) return yahwehStyle;
      return lexicalPosition < widget.entry.names.length &&
              widget.entry.names[lexicalPosition]
          ? properNameStyle
          : wordStyle;
    }

    final Widget content;
    if ((widget.glossInterlinear || widget.morphologyInterlinear) &&
        (widget.entry.glosses.isNotEmpty ||
            widget.entry.morphologies.isNotEmpty)) {
      final interlinearWords = interlinearVerseWords(_words);
      final interlinearDisplayWords = widget.showCantillation
          ? interlinearWords
          : interlinearWords.map(stripCantillation).toList();
      content = Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          // In an RTL wrap, `start` is the visual right edge.  Using
          // `end` puts a partially filled final run on the left.
          alignment: WrapAlignment.start,
          // Keep adjacent word columns visibly separated even when a gloss or
          // morphology label is very short.
          spacing: 6,
          textDirection: TextDirection.rtl,
          children: [
            for (final (i, glossPosition) in verseGlossPositions(
              interlinearWords,
            ).indexed)
              GestureDetector(
                onTap: glossPosition == null
                    ? null
                    : () => widget.onWordTap(
                        interlinearWords[i].replaceAll(_readerWordMarks, ''),
                        glossPosition < widget.entry.glosses.length
                            ? widget.entry.glosses[glossPosition]
                            : null,
                        glossPosition,
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        interlinearDisplayWords[i],
                        style: glossPosition == null
                            ? wordStyle
                            : styleForWord(interlinearWords[i], glossPosition),
                      ),
                      if (glossPosition != null &&
                          widget.morphologyInterlinear &&
                          glossPosition < widget.entry.morphologies.length &&
                          widget.entry.morphologies[glossPosition].isNotEmpty)
                        Text(
                          compactInterlinearMorphology(
                            widget.entry.morphologies[glossPosition],
                          ),
                          style: morphologyStyle,
                        ),
                      if (glossPosition != null &&
                          widget.glossInterlinear &&
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
      );
    } else {
      final spans = <InlineSpan>[];
      final displayNamePositions = verseGlossPositions(_words);
      for (var i = 0; i < _words.length; i++) {
        if (i > 0 && !_words[i - 1].endsWith(_maqaf)) {
          spans.add(const TextSpan(text: '  '));
        }
        spans.add(
          TextSpan(
            text: displayWords[i],
            // A standalone paseq is visible text but has no lexical row, so it
            // must not shift name styling for the words that follow.
            style: displayNamePositions[i] == null
                ? wordStyle
                : styleForWord(_words[i], displayNamePositions[i]!),
            recognizer: _recognizers[i],
          ),
        );
      }
      content = SelectableText.rich(
        TextSpan(children: spans),
        textDirection: TextDirection.rtl,
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.symmetric(
          vertical: widget.glossInterlinear || widget.morphologyInterlinear
              ? 2
              : 1,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: widget.glossInterlinear || widget.morphologyInterlinear
              ? 8
              : 4,
        ),
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
