import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../app_settings.dart';
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

/// Superscript ketiv, as fractions of the running text's font size: how big the
/// letters are, and how far their baseline is lifted above the reading baseline.
///
/// The rise has to clear the host word's vowel points without reaching its
/// cantillation, which sits above the letters \u2014 so a little over a third of the
/// text height, not the half a Latin superscript can afford.
const _superscriptScale = 0.58;
const _superscriptRise = 0.36;

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

/// Which displayed token each *ketiv* attaches to, and on which side.
///
/// A ketiv covers a range of the running text (`position`, `span`), so it is
/// shown after the last word of that range — the reader has finished the phrase
/// the Masoretes substituted before being told what stands written. The eight
/// readings that are written but never read have `span == 0` and no word of their
/// own; those attach *before* the word they would have preceded, which is where
/// they stand in the manuscript.
///
/// Keyed by index into the displayed tokens, not by lexical position, so the
/// caller can look up as it walks the spans.
Map<int, List<({KetivEntry ketiv, bool before})>> ketivAnchors(
  List<String> words,
  List<KetivEntry> ketivs,
) {
  if (ketivs.isEmpty) return const {};
  final lexical = verseGlossPositions(words);
  // Lexical position -> displayed token index.
  final tokenAt = <int, int>{};
  for (final (i, position) in lexical.indexed) {
    if (position != null) tokenAt[position] = i;
  }
  final anchors = <int, List<({KetivEntry ketiv, bool before})>>{};
  for (final ketiv in ketivs) {
    final before = ketiv.span == 0;
    final target = before ? ketiv.position : ketiv.position + ketiv.span - 1;
    final token = tokenAt[target];
    if (token == null) continue;
    (anchors[token] ??= []).add((ketiv: ketiv, before: before));
  }
  return anchors;
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
    this.studyHighlighted = false,
    this.studyNote = false,
    this.highlightedWordRoots = const {},
    this.studyWordHighlightColor,
    this.studyPassageHighlightColor,
    this.ketivDisplay = KetivDisplay.superscript,
  });

  final VerseEntry entry;
  final bool isSelected;
  final bool hebrewNumerals;
  final VoidCallback onTap;
  final void Function(
    String word,
    String? readerGloss,
    int? position,
    String root,
  )
  onWordTap;
  final double fontSize;
  final String fontFamily;
  final bool showCantillation;
  final bool glossInterlinear;
  final bool morphologyInterlinear;
  final bool highlightProperNames;
  final bool studyHighlighted;
  final bool studyNote;
  final Set<String> highlightedWordRoots;
  final Color? studyWordHighlightColor;
  final Color? studyPassageHighlightColor;
  final KetivDisplay ketivDisplay;

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
          ..onTap = () {
            final position = positions[i];
            widget.onWordTap(
              word,
              null,
              position,
              position != null && position < widget.entry.roots.length
                  ? widget.entry.roots[position]
                  : '',
            );
          },
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

  /// Which ketiv readings the reader has tapped open, by their position.
  final Set<int> _revealed = {};

  /// The spans that show one ketiv, in whichever presentation is configured.
  ///
  /// All three are quiet by design: the qere is the text being read, and the
  /// written form is an aside. So none of them inherits the word colouring —
  /// a ketiv beside a proper name must not look like part of the name.
  List<InlineSpan> _ketivSpans(KetivEntry ketiv, TextStyle wordStyle) {
    final theme = Theme.of(context);
    final aside = wordStyle.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );
    switch (widget.ketivDisplay) {
      case KetivDisplay.hidden:
        return const [];

      case KetivDisplay.superscript:
        // A raised baseline, which is what makes this a superscript.
        //
        // `PlaceholderAlignment.top` looks like one at a glance but is not: it
        // pins the box to the top of the line, so the letters sit at whatever
        // height the tallest thing on that line dictates and drift as the line
        // changes. Aligning on the baseline and then lifting off it keeps the
        // rise proportional to the text it annotates.
        //
        // There is no font-feature route here — OpenType `sups` covers digits
        // and Latin, not Hebrew consonants — so the shift is done by hand. It
        // is a visual translation only, which is what keeps it from opening up
        // the line box the way real vertical space would.
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(0, -widget.fontSize * _superscriptRise),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 1),
                child: Text(
                  ketiv.text,
                  textDirection: TextDirection.rtl,
                  style: aside.copyWith(
                    fontSize: widget.fontSize * _superscriptScale,
                    // No extra leading, so the box is the letters and the rise
                    // below is measured from where they actually sit.
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ];

      case KetivDisplay.brackets:
        return [
          TextSpan(
            text: ' [${ketiv.text}]',
            style: aside.copyWith(fontSize: widget.fontSize * 0.85),
          ),
        ];

      case KetivDisplay.marker:
        // Tapping the marker swaps it for the written form; tapping that puts
        // it away again, so nothing is stranded open.
        final open = _revealed.contains(ketiv.position);
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () => setState(() {
                if (!_revealed.remove(ketiv.position)) {
                  _revealed.add(ketiv.position);
                }
              }),
              child: Padding(
                // A generous tap area around a very small mark.
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: open
                    ? Text(
                        '[${ketiv.text}]',
                        textDirection: TextDirection.rtl,
                        style: aside.copyWith(fontSize: widget.fontSize * 0.85),
                      )
                    : Text(
                        // Circled dot: visible at reading size, and not a
                        // Hebrew mark that could be read as pointing.
                        '⊙',
                        style: aside.copyWith(
                          fontSize: widget.fontSize * 0.5,
                          color: theme.colorScheme.primary,
                        ),
                      ),
              ),
            ),
          ),
        ];
    }
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
      final root = lexicalPosition < widget.entry.roots.length
          ? widget.entry.roots[lexicalPosition]
          : '';
      final highlighted =
          root.isNotEmpty && widget.highlightedWordRoots.contains(root);
      final baseStyle = highlighted
          ? wordStyle.copyWith(
              backgroundColor:
                  widget.studyWordHighlightColor ??
                  theme.colorScheme.tertiaryContainer,
              fontWeight: FontWeight.w700,
            )
          : wordStyle;
      if (!widget.highlightProperNames) return baseStyle;
      // The corpus's traditional pointing `יַהְוֶה` currently has a verb
      // analysis, so its special reader treatment must not depend on the
      // general proper-name flag.
      if (isYahweh(word)) {
        return highlighted
            ? yahwehStyle.copyWith(
                backgroundColor:
                    widget.studyWordHighlightColor ??
                    theme.colorScheme.tertiaryContainer,
              )
            : yahwehStyle;
      }
      return lexicalPosition < widget.entry.names.length &&
              widget.entry.names[lexicalPosition]
          ? highlighted
                ? properNameStyle.copyWith(
                    backgroundColor:
                        widget.studyWordHighlightColor ??
                        theme.colorScheme.tertiaryContainer,
                  )
                : properNameStyle
          : baseStyle;
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
                        glossPosition < widget.entry.roots.length
                            ? widget.entry.roots[glossPosition]
                            : '',
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
                          widget.glossInterlinear &&
                          glossPosition < widget.entry.glosses.length &&
                          widget.entry.glosses[glossPosition].isNotEmpty)
                        Text(
                          widget.entry.glosses[glossPosition],
                          style: theme.textTheme.labelSmall,
                        ),
                      if (glossPosition != null &&
                          widget.glossInterlinear &&
                          widget.morphologyInterlinear &&
                          glossPosition < widget.entry.glosses.length &&
                          glossPosition < widget.entry.morphologies.length &&
                          widget.entry.glosses[glossPosition].isNotEmpty &&
                          widget.entry.morphologies[glossPosition].isNotEmpty)
                        const SizedBox(height: 4),
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
      final anchors = widget.ketivDisplay == KetivDisplay.hidden
          ? const <int, List<({KetivEntry ketiv, bool before})>>{}
          : ketivAnchors(_words, widget.entry.ketivs);
      for (var i = 0; i < _words.length; i++) {
        if (i > 0 && !_words[i - 1].endsWith(_maqaf)) {
          spans.add(const TextSpan(text: '  '));
        }
        for (final anchor in anchors[i] ?? const []) {
          if (anchor.before) spans.addAll(_ketivSpans(anchor.ketiv, wordStyle));
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
        for (final anchor in anchors[i] ?? const []) {
          if (!anchor.before) {
            spans.addAll(_ketivSpans(anchor.ketiv, wordStyle));
          }
        }
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
              : widget.studyHighlighted
              ? (widget.studyPassageHighlightColor ??
                        theme.colorScheme.secondaryContainer)
                    .withValues(alpha: 0.55)
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.hebrewNumerals
                        ? _toHebrewNumeral(widget.entry.verse)
                        : '${widget.entry.verse}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.studyNote)
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 12,
                      color: theme.colorScheme.secondary,
                    ),
                ],
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
