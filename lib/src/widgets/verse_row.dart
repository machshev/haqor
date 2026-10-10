import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../study_workspace.dart';
import '../syntax_tree.dart';
import '../bindings/bindings.dart';
import '../tutor/transliterate.dart';

final RegExp _sourceTextLetter = RegExp(
  r'[\u05D0-\u05EA\u0710-\u072F\u074D-\u074F\u0370-\u03FF\u1F00-\u1FFF]',
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

/// The column between the Hebrew and English side by side: room for a verse
/// number, with its note mark and cross-reference marker stacked beneath it.
const _parallelGutterWidth = 28.0;

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

/// The on-screen colour for a study highlight behind reader text.
///
/// Study colours are light pastels, which suit dark text in the light theme.
/// Dark themes draw light text, so there the colour is mixed into the surface
/// to keep its hue while leaving the text readable.
Color studyHighlightBackground(Color color, ThemeData theme) =>
    theme.brightness == Brightness.dark
    ? Color.alphaBlend(color.withValues(alpha: 0.35), theme.colorScheme.surface)
    : color;

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

  return textPainter.preferredLineHeight;
}

class VerseRow extends StatefulWidget {
  const VerseRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.hebrewNumerals,
    required this.onTap,
    required this.onWordTap,
    this.onWordMenu,
    this.onCrossReferences,
    this.onVerseMenu,
    this.crossReferenceMinScore = 0,
    this.fontSize = 20.0,
    this.fontFamily = 'Cardo',
    this.showCantillation = true,
    this.glossInterlinear = false,
    this.morphologyInterlinear = false,
    this.interlinearPositions,
    this.highlightProperNames = false,
    this.studyHighlighted = false,
    this.studyNote = false,
    this.studyTimeline,
    this.onStudyTimeline,
    this.studyWordHighlightColors = const {},
    this.studyFormHighlightColors = const {},
    this.studyPhraseHighlightColors = const {},
    this.studyPassageHighlightColor,
    this.ketivDisplay = KetivDisplay.superscript,
    this.syntaxMarks,
    this.readerText = ReaderText.source,
    this.translation,
    this.translationPending = false,
    this.onTranslationWordTap,
    this.onTranslationWordMenu,
    this.sourceDirection = TextDirection.rtl,
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

  /// A word's menu, asked for by a long press or a secondary click, with the
  /// same word details as [onWordTap] and where on screen the press was.
  final void Function(
    String word,
    String? readerGloss,
    int? position,
    String root,
    Offset globalPosition,
  )?
  onWordMenu;

  /// Opens the verse's cross references. Its marker shows only when the
  /// verse has a link scoring at least [crossReferenceMinScore].
  final VoidCallback? onCrossReferences;

  /// The verse's menu, asked for by a long press or a secondary click on its
  /// number, with where on screen the press was.
  final void Function(Offset globalPosition)? onVerseMenu;

  /// How strong a link must be to count towards the marker.
  final double crossReferenceMinScore;
  final double fontSize;
  final String fontFamily;
  final bool showCantillation;
  final bool glossInterlinear;
  final bool morphologyInterlinear;

  /// The lexical positions whose interlinear layers show, or null for every
  /// word. Empty sets the verse as running text, as with no layers enabled.
  final Set<int>? interlinearPositions;
  final bool highlightProperNames;
  final bool studyHighlighted;
  final bool studyNote;

  /// The titles of the timeline events and spans linked to this verse, shown
  /// as a marker that [onStudyTimeline] opens; null for none.
  final String? studyTimeline;
  final VoidCallback? onStudyTimeline;
  final Map<String, Color> studyWordHighlightColors;
  final Map<String, Color> studyFormHighlightColors;

  /// Occurrence-specific phrase colors, keyed by zero-based lexical position.
  final Map<int, Color> studyPhraseHighlightColors;
  final Color? studyPassageHighlightColor;
  final KetivDisplay ketivDisplay;

  /// The verse's syntax roles and clause starts, when the reader colours
  /// them: each word underlined in its role's colour, and a faint rule before
  /// each clause. Null leaves the text unmarked.
  final VerseSyntaxMarks? syntaxMarks;

  /// Whether the row shows the source text, its English, or both side by
  /// side. Without English for the verse ([translation] null and not
  /// [translationPending]) it shows the source text whatever this says.
  final ReaderText readerText;

  /// The verse's English, each span naming the Hebrew words it renders.
  final List<TranslationSpanEntry>? translation;

  /// Whether the verse's English is still on its way: the row keeps a place
  /// for it rather than falling back to the source text.
  final bool translationPending;

  /// A tap on an English word, with the Hebrew word it mainly renders.
  final void Function(TranslationWordEntry word)? onTranslationWordTap;

  /// An English word's menu (long press or secondary click), with the Hebrew
  /// word it mainly renders and where on screen the press was.
  final void Function(TranslationWordEntry word, Offset globalPosition)?
  onTranslationWordMenu;

  /// Which way the source text reads: right to left for the Hebrew and the
  /// Peshitta, left to right for the Greek.
  final TextDirection sourceDirection;

  @override
  State<VerseRow> createState() => _VerseRowState();
}

/// A word's tap, plus a long press that opens its menu.
///
/// A text span carries a single recognizer, so this one also enters a long
/// press into the gesture arena for each pointer it accepts: a quick release
/// is still a tap, and holding lets the long press win instead. Being deeper
/// in the tree than the selectable text around it, the long press also wins
/// over the text's own long-press selection on a word.
class _WordGestureRecognizer extends TapGestureRecognizer {
  _WordGestureRecognizer({GestureLongPressStartCallback? onLongPressStart})
    : _longPress = onLongPressStart == null
          ? null
          : (LongPressGestureRecognizer()..onLongPressStart = onLongPressStart);

  final LongPressGestureRecognizer? _longPress;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _longPress?.addPointer(event);
  }

  @override
  void dispose() {
    _longPress?.dispose();
    super.dispose();
  }
}

class _VerseRowState extends State<VerseRow> {
  /// Links at least as strong as the reader is set to show.
  int get _crossReferenceCount => widget.entry.crossReferenceScores
      .where((score) => score >= widget.crossReferenceMinScore)
      .length;

  List<String> _words = [];
  List<TapGestureRecognizer> _recognizers = [];

  /// One per span of [VerseRow.translation], null for a span rendering no
  /// Hebrew word.
  List<TapGestureRecognizer?> _translationRecognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuild();
    _rebuildTranslation();
  }

  @override
  void didUpdateWidget(VerseRow old) {
    super.didUpdateWidget(old);
    if (old.entry.text != widget.entry.text ||
        (old.onWordMenu == null) != (widget.onWordMenu == null)) {
      _disposeRecognizers();
      _rebuild();
    }
    if (!identical(old.translation, widget.translation) ||
        (old.onTranslationWordMenu == null) !=
            (widget.onTranslationWordMenu == null)) {
      _disposeTranslationRecognizers();
      _rebuildTranslation();
    }
  }

  void _rebuildTranslation() {
    final hasMenu = widget.onTranslationWordMenu != null;
    _translationRecognizers = [
      for (final span in widget.translation ?? const <TranslationSpanEntry>[])
        if (span.words.isEmpty)
          null
        else
          _WordGestureRecognizer(
              onLongPressStart: hasMenu
                  ? (details) => widget.onTranslationWordMenu?.call(
                      span.words.first,
                      details.globalPosition,
                    )
                  : null,
            )
            ..onTap = () {
              widget.onTranslationWordTap?.call(span.words.first);
            }
            ..onSecondaryTapUp = hasMenu
                ? (details) => widget.onTranslationWordMenu?.call(
                    span.words.first,
                    details.globalPosition,
                  )
                : null,
    ];
  }

  void _disposeTranslationRecognizers() {
    for (final r in _translationRecognizers) {
      r?.dispose();
    }
    _translationRecognizers = [];
  }

  String _rootAt(int? position) =>
      position != null && position < widget.entry.roots.length
      ? widget.entry.roots[position]
      : '';

  void _rebuild() {
    _words = widget.entry.text.split(' ').where((w) => w.isNotEmpty).toList();
    final positions = verseGlossPositions(_words);
    final hasMenu = widget.onWordMenu != null;
    _recognizers = [
      for (final (i, word) in _words.indexed)
        _WordGestureRecognizer(
            onLongPressStart: hasMenu
                ? (details) => widget.onWordMenu?.call(
                    word,
                    null,
                    positions[i],
                    _rootAt(positions[i]),
                    details.globalPosition,
                  )
                : null,
          )
          ..onTap = () {
            widget.onWordTap(word, null, positions[i], _rootAt(positions[i]));
          }
          ..onSecondaryTapUp = hasMenu
              ? (details) => widget.onWordMenu?.call(
                  word,
                  null,
                  positions[i],
                  _rootAt(positions[i]),
                  details.globalPosition,
                )
              : null,
    ];
  }

  void _openInterlinearMenu(String word, int position, Offset globalPosition) {
    widget.onWordMenu?.call(
      word.replaceAll(_readerWordMarks, ''),
      position < widget.entry.glosses.length
          ? widget.entry.glosses[position]
          : null,
      position,
      _rootAt(position),
      globalPosition,
    );
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
    _disposeTranslationRecognizers();
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
    TextStyle lexicalStyleForWord(String word, int lexicalPosition) {
      final root = lexicalPosition < widget.entry.roots.length
          ? widget.entry.roots[lexicalPosition]
          : '';
      // An occurrence-specific phrase takes precedence over form/root colors.
      final storedColor =
          widget.studyPhraseHighlightColors[lexicalPosition] ??
          widget.studyFormHighlightColors[StudyWord.formKey(root, word)] ??
          widget.studyFormHighlightColors[StudyWord.formKey('', word)] ??
          widget.studyWordHighlightColors[root];
      final highlightColor = storedColor == null
          ? null
          : studyHighlightBackground(storedColor, theme);
      final highlighted = highlightColor != null;
      final baseStyle = highlighted
          ? wordStyle.copyWith(
              backgroundColor: highlightColor,
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
                backgroundColor: highlightColor,
                // The usual gold is too dim against a dark-theme tint.
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFFFFCA28)
                    : null,
              )
            : yahwehStyle;
      }
      return lexicalPosition < widget.entry.names.length &&
              widget.entry.names[lexicalPosition]
          ? highlighted
                ? properNameStyle.copyWith(backgroundColor: highlightColor)
                : properNameStyle
          : baseStyle;
    }

    // A word's syntax role shows as an underline, which leaves the colours of
    // study highlights (a background) and proper names (the letters) as they
    // are.
    final syntaxMarks = widget.syntaxMarks;
    TextStyle styleForWord(String word, int lexicalPosition) {
      final style = lexicalStyleForWord(word, lexicalPosition);
      final role = syntaxMarks?.roles[lexicalPosition];
      if (role == null) return style;
      return style.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: syntaxRoleColor(role, theme.brightness),
        decorationThickness: 2.5,
      );
    }

    bool startsClause(int? lexicalPosition) =>
        lexicalPosition != null &&
        (syntaxMarks?.clauseStarts.contains(lexicalPosition) ?? false);

    // The verse number and its marks open the verse's first line, as in a
    // printed Bible, rather than standing in a margin column: a column would
    // indent every line by however wide that verse's marks happen to be.
    //
    // The text reads its own way, whatever the app's own direction (right
    // to left but for the Greek), so the gaps are fixed sides rather than
    // directional ones. English opens its line left to right, and side by
    // side the marks stand between the two texts.
    //
    // Stacked (side by side), the number keeps the first line's height so it
    // stays level with both texts, and the marks hang beneath it.
    Widget verseMarksFor(
      EdgeInsets padding,
      TextDirection direction, {
      bool stacked = false,
    }) {
      final number = _VerseNumber(
        key: ValueKey('verse-number-${widget.entry.verse}'),
        label: widget.hebrewNumerals
            ? _toHebrewNumeral(widget.entry.verse)
            : '${widget.entry.verse}',
        onMenu: widget.onVerseMenu,
      );
      return Padding(
        padding: padding,
        child: Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          textDirection: direction,
          children: [
            if (stacked)
              SizedBox(
                height: widget.fontSize * 1.6,
                child: Center(child: number),
              )
            else
              number,
            if (widget.studyNote)
              Padding(
                padding: stacked
                    ? const EdgeInsets.only(bottom: 4)
                    : const EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 12,
                  color: theme.colorScheme.secondary,
                ),
              ),
            if (widget.studyTimeline != null)
              Padding(
                padding: stacked
                    ? const EdgeInsets.only(bottom: 4)
                    : const EdgeInsets.only(right: 2),
                child: Tooltip(
                  message: widget.studyTimeline!,
                  child: InkWell(
                    key: ValueKey('verse-timeline-${widget.entry.verse}'),
                    onTap: widget.onStudyTimeline,
                    customBorder: const CircleBorder(),
                    child: Icon(
                      Icons.timeline,
                      size: 14,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              ),
            if (_crossReferenceCount > 0 && widget.onCrossReferences != null)
              _CrossReferenceMarker(
                count: _crossReferenceCount,
                onTap: widget.onCrossReferences!,
              ),
          ],
        ),
      );
    }

    final rtl = widget.sourceDirection == TextDirection.rtl;
    final verseMarks = verseMarksFor(
      rtl ? const EdgeInsets.only(left: 6) : const EdgeInsets.only(right: 6),
      widget.sourceDirection,
    );

    final translation = widget.translation;
    final showsEnglish =
        widget.readerText != ReaderText.source &&
        (translation != null || widget.translationPending);
    // The source text opens with the verse's marks unless the English, or
    // the column between the two, has them.
    final sourceMarks = !showsEnglish;

    final Widget source;
    final interlinearPositions = widget.interlinearPositions;
    bool showsInterlinear(int position) =>
        interlinearPositions == null || interlinearPositions.contains(position);
    if ((widget.glossInterlinear || widget.morphologyInterlinear) &&
        (interlinearPositions == null || interlinearPositions.isNotEmpty) &&
        (widget.entry.glosses.isNotEmpty ||
            widget.entry.morphologies.isNotEmpty)) {
      final interlinearWords = interlinearVerseWords(_words);
      final interlinearDisplayWords = widget.showCantillation
          ? interlinearWords
          : interlinearWords.map(stripCantillation).toList();
      source = Align(
        alignment: rtl ? Alignment.topRight : Alignment.topLeft,
        child: Wrap(
          // In an RTL wrap, `start` is the visual right edge.  Using
          // `end` puts a partially filled final run on the left.
          alignment: WrapAlignment.start,
          // Keep adjacent word columns visibly separated even when a gloss or
          // morphology label is very short.
          spacing: 6,
          textDirection: widget.sourceDirection,
          children: [
            if (sourceMarks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SizedBox(
                  height: widget.fontSize * 1.6,
                  // Only as wide as the marks: a wrap offers each child its
                  // full width, which a plain `Center` would take, leaving the
                  // marks alone on a line of their own.
                  child: Center(widthFactor: 1, child: verseMarks),
                ),
              ),
            for (final (i, glossPosition) in verseGlossPositions(
              interlinearWords,
            ).indexed) ...[
              if (startsClause(glossPosition))
                Padding(
                  key: ValueKey('clause-rule-$glossPosition'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    width: 1.5,
                    height: widget.fontSize * 1.6,
                    child: ColoredBox(color: theme.colorScheme.outline),
                  ),
                ),
              GestureDetector(
                onTap: glossPosition == null
                    ? null
                    : () => widget.onWordTap(
                        interlinearWords[i].replaceAll(_readerWordMarks, ''),
                        glossPosition < widget.entry.glosses.length
                            ? widget.entry.glosses[glossPosition]
                            : null,
                        glossPosition,
                        _rootAt(glossPosition),
                      ),
                onLongPressStart:
                    glossPosition == null || widget.onWordMenu == null
                    ? null
                    : (details) => _openInterlinearMenu(
                        interlinearWords[i],
                        glossPosition,
                        details.globalPosition,
                      ),
                onSecondaryTapUp:
                    glossPosition == null || widget.onWordMenu == null
                    ? null
                    : (details) => _openInterlinearMenu(
                        interlinearWords[i],
                        glossPosition,
                        details.globalPosition,
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
                          showsInterlinear(glossPosition) &&
                          widget.glossInterlinear &&
                          glossPosition < widget.entry.glosses.length &&
                          widget.entry.glosses[glossPosition].isNotEmpty)
                        Text(
                          widget.entry.glosses[glossPosition],
                          style: theme.textTheme.labelSmall,
                        ),
                      if (glossPosition != null &&
                          showsInterlinear(glossPosition) &&
                          widget.glossInterlinear &&
                          widget.morphologyInterlinear &&
                          glossPosition < widget.entry.glosses.length &&
                          glossPosition < widget.entry.morphologies.length &&
                          widget.entry.glosses[glossPosition].isNotEmpty &&
                          widget.entry.morphologies[glossPosition].isNotEmpty)
                        const SizedBox(height: 4),
                      if (glossPosition != null &&
                          showsInterlinear(glossPosition) &&
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
          ],
        ),
      );
    } else {
      final spans = <InlineSpan>[
        if (sourceMarks)
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: verseMarks),
      ];
      final displayNamePositions = verseGlossPositions(_words);
      final anchors = widget.ketivDisplay == KetivDisplay.hidden
          ? const <int, List<({KetivEntry ketiv, bool before})>>{}
          : ketivAnchors(_words, widget.entry.ketivs);
      for (var i = 0; i < _words.length; i++) {
        if (i > 0 && startsClause(displayNamePositions[i])) {
          // A clause begins: the gap carries a faint rule.
          spans.add(
            TextSpan(
              text: ' \u2502 ',
              style: wordStyle.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w300,
              ),
            ),
          );
        } else if (i > 0 && !_words[i - 1].endsWith(_maqaf)) {
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
      source = SelectableText.rich(
        TextSpan(children: spans),
        textDirection: widget.sourceDirection,
      );
    }

    // The English, in the app's own type, a little smaller than the
    // Hebrew. Supplied words are in italics, as literal translations print
    // them; a word rendering Hebrew opens that word's details.
    Widget english({required bool withMarks}) {
      final style = theme.textTheme.bodyLarge?.copyWith(
        fontSize: widget.fontSize * 0.8,
        height: 1.6,
        color: wordStyle.color,
      );
      return SelectableText.rich(
        TextSpan(
          style: style,
          children: [
            if (withMarks)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: verseMarksFor(
                  const EdgeInsets.only(right: 6),
                  TextDirection.ltr,
                ),
              ),
            for (final (i, span)
                in (translation ?? const <TranslationSpanEntry>[]).indexed)
              TextSpan(
                text: span.text,
                style: span.supplied
                    ? const TextStyle(fontStyle: FontStyle.italic)
                    : null,
                recognizer: i < _translationRecognizers.length
                    ? _translationRecognizers[i]
                    : null,
              ),
          ],
        ),
        textDirection: TextDirection.ltr,
      );
    }

    final Widget content;
    if (!showsEnglish) {
      content = source;
    } else if (widget.readerText == ReaderText.english) {
      content = Align(
        alignment: Alignment.topLeft,
        child: english(withMarks: true),
      );
    } else {
      // Side by side: the Hebrew reads leftwards from the middle and the
      // English rightwards from it, so both start at the verse number they
      // share.
      content = Row(
        textDirection: TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: source),
          // One width for every verse, whatever marks it carries, so the
          // two texts' inner edges run straight down the page.
          SizedBox(
            width: _parallelGutterWidth,
            child: verseMarksFor(
              EdgeInsets.zero,
              TextDirection.rtl,
              stacked: true,
            ),
          ),
          Expanded(
            child: Padding(
              // Level with the Hebrew's first line, which is taller.
              padding: EdgeInsets.only(top: widget.fontSize * 0.16),
              child: english(withMarks: false),
            ),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        // No space between verses beyond what the lines themselves carry — the
        // running text's leading, or the interlinear words' own padding — so
        // the gap between verses matches the gap between lines.
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // Square corners, so neighbouring highlighted verses join into one band.
        decoration: BoxDecoration(
          color: widget.isSelected
              ? theme.colorScheme.primaryContainer
              : widget.studyHighlighted
              ? theme.brightness == Brightness.dark
                    ? studyHighlightBackground(
                        widget.studyPassageHighlightColor ??
                            theme.colorScheme.secondaryContainer,
                        theme,
                      )
                    : (widget.studyPassageHighlightColor ??
                              theme.colorScheme.secondaryContainer)
                          .withValues(alpha: 0.55)
              : Colors.transparent,
        ),
        child: content,
      ),
    );
  }
}

/// A verse's number, opening the verse's menu on a long press or a secondary
/// click. Its own gesture target, a little larger than the glyphs, so the
/// press is not taken for the verse's tap or a text selection.
class _VerseNumber extends StatelessWidget {
  const _VerseNumber({super.key, required this.label, this.onMenu});

  final String label;
  final void Function(Offset globalPosition)? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
    final menu = onMenu;
    if (menu == null) return text;
    return Semantics(
      label: 'Verse $label menu',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => menu(d.globalPosition),
        onSecondaryTapDown: (d) => menu(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: text,
        ),
      ),
    );
  }
}

/// The margin mark of a verse with cross references: quotations linking it to
/// the other testament, or parallels within its own.
/// Its own tap target, larger than the glyph, so it opens the cross
/// references rather than selecting the verse around it.
class _CrossReferenceMarker extends StatelessWidget {
  const _CrossReferenceMarker({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count == 1 ? '1 cross reference' : '$count cross references';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 16,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Icon(
              Icons.link,
              size: 14,
              color: theme.colorScheme.tertiary,
            ),
          ),
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
