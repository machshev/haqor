import 'package:flutter/material.dart';

import 'haqor_lexicon_view.dart';

/// The Semitic sound correspondences: which older consonants sit behind each
/// Hebrew letter, and where Aramaic writes one differently. The lexicon's
/// reference for splitting a Hebrew root's senses by its cognates.
class SemiticSoundsPage extends StatelessWidget {
  const SemiticSoundsPage({super.key, this.onNavigateToPassage});

  final LexiconNavigate? onNavigateToPassage;

  static Future<void> open(
    BuildContext context, {
    LexiconNavigate? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SemiticSoundsPage(onNavigateToPassage: onNavigateToPassage),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = _Colors.of(theme);
    Widget heading(String s) =>
        Text(s, style: text.headlineSmall?.copyWith(fontFamily: 'Cardo'));
    Widget para(String s, {TextStyle? style}) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Text(s, style: _mixed(style ?? text.bodyLarge)),
    );
    void go(_Ref ref) {
      Navigator.of(context).pop();
      onNavigateToPassage!(ref.book, ref.chapter, ref.verse);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Semitic sounds')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            Text(
              'HAQOR LEXICON · REFERENCE',
              style: text.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Semitic sound correspondences',
              style: text.headlineMedium?.copyWith(fontFamily: 'Cardo'),
            ),
            const SizedBox(height: 12),
            para(
              'The Semitic languages share most of their roots, but not their '
              'alphabets. Comparing them shows about 29 consonants that once '
              'kept words apart. The 22-letter alphabet used for Hebrew and '
              'Aramaic has fewer letters than that, so several Hebrew letters '
              'each stand for two or three of those older sounds.',
            ),
            const SizedBox(height: 8),
            para(
              'This page shows which sounds sit behind each Hebrew letter. The '
              'lexicon uses it to explain why one Hebrew spelling can carry '
              'two different senses: cognates in languages that kept the '
              'sounds apart show which sense goes with which sound. It makes '
              'no claim about which language came first.',
            ),
            const SizedBox(height: 32),
            heading('The consonants side by side'),
            const SizedBox(height: 8),
            para(
              'Each row is one older consonant, in the standard notation of '
              'Semitic studies, with the letter each language uses for it. '
              'A dash (∅) means the sound was lost.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                _Key(
                  fill: colors.mergeBg,
                  edge: colors.merge,
                  label: 'Hebrew letter that also covers another older sound',
                ),
                _Key(
                  fill: colors.divBg,
                  edge: colors.div,
                  label: 'Aramaic writes it differently from Hebrew',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SoundTable(colors: colors),
            const SizedBox(height: 8),
            para(
              'Aramaic here is Biblical and Imperial Aramaic. “Old Aram.” '
              'marks the spelling of the earliest Aramaic inscriptions, which '
              'borrowed the nearest Phoenician letter for a sound the alphabet '
              'had no letter for, and changed it once the sound itself had '
              'shifted.',
              style: text.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            heading('Where sounds meet and part'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 24,
              children: [
                _Figure(
                  painter: _MergePainter(colors, theme),
                  size: const Size(360, 476),
                  caption:
                      'Two or three older sounds funnel into one Hebrew '
                      'letter. A Hebrew root spelled with one of these letters '
                      'can therefore hide two older roots; a cognate in a '
                      'language that kept the sounds apart can tell them '
                      'apart again.',
                ),
                _Figure(
                  painter: _SplitPainter(colors, theme),
                  size: const Size(360, 440),
                  caption:
                      'One older sound, two spellings. Where Hebrew and '
                      'Aramaic took different paths, the same root looks '
                      'different in each, as in זָהָב and דְּהַב. These are '
                      'the correspondences that link the Aramaic portions of '
                      'scripture to Hebrew roots.',
                ),
              ],
            ),
            const SizedBox(height: 32),
            heading('How many letters each script has'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final s in _sizes) _SizeCard(s)],
            ),
            const SizedBox(height: 32),
            heading('Worked examples'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final e in _examples)
                  _ExampleCard(
                    e,
                    colors: colors,
                    onGo: onNavigateToPassage == null ? null : go,
                  ),
              ],
            ),
            const SizedBox(height: 32),
            para(
              'Reference for the Haqor lexicon. Each correspondence here is a '
              'lead: an entry that relies on one cites the cognate’s own '
              'dictionary or text, as the lexicon’s rules require.',
              style: text.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Body text that may hold Hebrew, Arabic, Syriac or Ge'ez words inline.
TextStyle? _mixed(TextStyle? style) => style?.copyWith(
  fontFamilyFallback: const [
    'Noto Serif Hebrew',
    'Cardo',
    ...cognateFontFallback,
  ],
);

/// The page's two marks: a Hebrew letter covering several older sounds, and
/// an Aramaic spelling that differs from the Hebrew.
class _Colors {
  const _Colors(this.merge, this.mergeBg, this.div, this.divBg);

  factory _Colors.of(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return dark
        ? const _Colors(
            Color(0xFF93B2F2),
            Color(0xFF1C2843),
            Color(0xFFE3AA5E),
            Color(0xFF33281A),
          )
        : const _Colors(
            Color(0xFF2F55A4),
            Color(0xFFE5ECF9),
            Color(0xFF9A5E14),
            Color(0xFFF5EAD9),
          );
  }

  final Color merge;
  final Color mergeBg;
  final Color div;
  final Color divBg;
}

class _Key extends StatelessWidget {
  const _Key({required this.fill, required this.edge, required this.label});

  final Color fill;
  final Color edge;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: edge),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(child: Text(label)),
    ],
  );
}

/// One older consonant and how each language writes it.
class _Sound {
  const _Sound(
    this.sound,
    this.hebrew,
    this.aramaic,
    this.syriac,
    this.ugaritic,
    this.arabic,
    this.geez,
    this.akkadian, {
    this.oldAramaic,
    this.merges = false,
    this.differs = false,
    this.note = '',
  });

  final String sound;
  final String hebrew;
  final String aramaic;
  final String? oldAramaic;
  final String syriac;
  final String ugaritic;
  final String arabic;
  final String geez;
  final String akkadian;

  /// The Hebrew letter also covers another older sound.
  final bool merges;

  /// Aramaic writes it differently from Hebrew.
  final bool differs;
  final String note;
}

const _sounds = [
  _Sound(
    'ʾ',
    'א',
    'א',
    'ܐ',
    'ʾa ʾi ʾu',
    'ء',
    'አ',
    '∅',
    note: 'Ugaritic has three signs, one for each vowel after ʾ.',
  ),
  _Sound('b', 'ב', 'ב', 'ܒ', 'b', 'ب', 'በ', 'b'),
  _Sound(
    'g',
    'ג',
    'ג',
    'ܓ',
    'g',
    'ج',
    'ገ',
    'g',
    note: 'Arabic now says ǧ (j).',
  ),
  _Sound('d', 'ד', 'ד', 'ܕ', 'd', 'د', 'ደ', 'd'),
  _Sound(
    'ḏ',
    'ז',
    'ד',
    'ܕ',
    'ḏ (often d)',
    'ذ',
    'ዘ',
    'z',
    oldAramaic: 'ז',
    merges: true,
    differs: true,
    note: 'Hebrew merged it with z; Aramaic later with d. זָהָב / דְּהַב.',
  ),
  _Sound('h', 'ה', 'ה', 'ܗ', 'h', 'ه', 'ሀ', '∅'),
  _Sound(
    'w',
    'ו',
    'ו',
    'ܘ',
    'w',
    'و',
    'ወ',
    'w',
    note: 'At the start of a word Hebrew and Aramaic mostly turned w into y.',
  ),
  _Sound(
    'z',
    'ז',
    'ז',
    'ܙ',
    'z',
    'ز',
    'ዘ',
    'z',
    merges: true,
    note: 'Shares ז with ḏ.',
  ),
  _Sound(
    'ḥ',
    'ח',
    'ח',
    'ܚ',
    'ḥ',
    'ح',
    'ሐ',
    '∅',
    merges: true,
    note: 'Shares ח with ḫ.',
  ),
  _Sound(
    'ḫ',
    'ח',
    'ח',
    'ܚ',
    'ḫ',
    'خ',
    'ኀ',
    'ḫ',
    merges: true,
    note:
        'Still spoken apart in Hebrew when the Septuagint was made: some '
        'names come over with χ, others with no consonant.',
  ),
  _Sound('ṭ', 'ט', 'ט', 'ܛ', 'ṭ', 'ط', 'ጠ', 'ṭ'),
  _Sound(
    'ṯ̣',
    'צ',
    'ט',
    'ܛ',
    'ẓ',
    'ظ',
    'ጸ',
    'ṣ',
    oldAramaic: 'צ',
    merges: true,
    differs: true,
    note: 'Hebrew צ, Aramaic ט: Hebrew צֵל “shade”, Aramaic טְלַל.',
  ),
  _Sound('y', 'י', 'י', 'ܝ', 'y', 'ي', 'የ', 'y / ∅'),
  _Sound('k', 'כ', 'כ', 'ܟ', 'k', 'ك', 'ከ', 'k'),
  _Sound('l', 'ל', 'ל', 'ܠ', 'l', 'ل', 'ለ', 'l'),
  _Sound('m', 'מ', 'מ', 'ܡ', 'm', 'م', 'መ', 'm'),
  _Sound('n', 'נ', 'נ', 'ܢ', 'n', 'ن', 'ነ', 'n'),
  _Sound('s', 'ס', 'ס', 'ܣ', 's', 'س', 'ሰ', 's', note: 'Samekh.'),
  _Sound(
    'ś',
    'שׂ',
    'שׂ, later ס',
    'ܣ',
    'š',
    'ش',
    'ሠ',
    'š',
    oldAramaic: 'ש',
    merges: true,
    differs: true,
    note:
        'Written with the same letter as shin; the dots that tell them '
        'apart came much later. Later Hebrew said it as s, so some words '
        'are spelt both ways. The lexicon’s root keys write it שׂ, apart '
        'from shin.',
  ),
  _Sound(
    'š',
    'שׁ',
    'שׁ',
    'ܫ',
    'š',
    'س',
    'ሰ',
    'š',
    merges: true,
    note: 'Shares שׁ with ṯ. Arabic and Geʿez merged it with s instead.',
  ),
  _Sound(
    'ṣ',
    'צ',
    'צ',
    'ܨ',
    'ṣ',
    'ص',
    'ጸ',
    'ṣ',
    merges: true,
    note: 'Shares צ with ṣ́ and ṯ̣.',
  ),
  _Sound(
    'ṣ́',
    'צ',
    'ע',
    'ܥ',
    'ṣ',
    'ض',
    'ፀ',
    'ṣ',
    oldAramaic: 'ק',
    merges: true,
    differs: true,
    note:
        'Hebrew אֶרֶץ, Aramaic אַרְעָא. Jeremiah 10:11 has both Aramaic '
        'spellings, אַרְקָא and אַרְעָא.',
  ),
  _Sound(
    'ʿ',
    'ע',
    'ע',
    'ܥ',
    'ʿ',
    'ع',
    'ዐ',
    '∅',
    merges: true,
    note: 'Shares ע with ġ.',
  ),
  _Sound(
    'ġ',
    'ע',
    'ע',
    'ܥ',
    'ġ',
    'غ',
    'ዐ',
    '∅',
    merges: true,
    note:
        'Still spoken in Hebrew when the Septuagint was made: עַזָּה is '
        'Γάζα, עֲמֹרָה is Γόμορρα.',
  ),
  _Sound(
    'p',
    'פ',
    'פ',
    'ܦ',
    'p',
    'ف',
    'ፈ',
    'p',
    note: 'Arabic and Geʿez say f.',
  ),
  _Sound('q', 'ק', 'ק', 'ܩ', 'q', 'ق', 'ቀ', 'q'),
  _Sound('r', 'ר', 'ר', 'ܪ', 'r', 'ر', 'ረ', 'r'),
  _Sound(
    'ṯ',
    'שׁ',
    'ת',
    'ܬ',
    'ṯ',
    'ث',
    'ሰ',
    'š',
    oldAramaic: 'ש',
    merges: true,
    differs: true,
    note: 'Hebrew שָׁלֹשׁ, Aramaic תְּלָת, Arabic ثلاث.',
  ),
  _Sound('t', 'ת', 'ת', 'ܬ', 't', 'ت', 'ተ', 't'),
];

class _SoundTable extends StatelessWidget {
  const _SoundTable({required this.colors});

  final _Colors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = BorderSide(color: theme.colorScheme.outlineVariant);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget cell(Widget child, {Color? fill, bool centre = true}) => Container(
      color: fill,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      alignment: centre ? Alignment.center : Alignment.centerLeft,
      child: child,
    );
    Widget script(String s, {Color? color, bool bold = false}) => Text(
      s,
      style: foreignStyle(
        s,
        size: 20,
      ).copyWith(color: color, fontWeight: bold ? FontWeight.w600 : null),
    );
    Widget translit(String s) => Text(
      s,
      style: const TextStyle(
        fontFamily: 'Cardo',
        fontStyle: FontStyle.italic,
        fontSize: 16,
      ),
    );
    final head = theme.textTheme.labelSmall?.copyWith(
      color: muted,
      letterSpacing: .8,
    );
    const columns = [
      'OLDER SOUND',
      'HEBREW',
      'ARAMAIC',
      'SYRIAC',
      'UGARITIC',
      'ARABIC',
      'GEʿEZ',
      'AKKADIAN',
      'NOTES',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: const {8: FixedColumnWidth(320)},
          defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
          border: TableBorder(horizontalInside: line),
          children: [
            TableRow(
              children: [
                for (final c in columns)
                  cell(Text(c, style: head), centre: false),
              ],
            ),
            for (final s in _sounds)
              TableRow(
                children: [
                  cell(
                    Text(
                      s.sound,
                      style: const TextStyle(
                        fontFamily: 'Cardo',
                        fontStyle: FontStyle.italic,
                        fontSize: 19,
                      ),
                    ),
                    centre: false,
                  ),
                  cell(
                    script(
                      s.hebrew,
                      color: s.merges ? colors.merge : null,
                      bold: s.merges,
                    ),
                    fill: s.merges ? colors.mergeBg : null,
                  ),
                  cell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        script(
                          s.aramaic,
                          color: s.differs ? colors.div : null,
                          bold: s.differs,
                        ),
                        if (s.oldAramaic != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Old Aram. ${s.oldAramaic}',
                            style: _mixed(
                              theme.textTheme.bodySmall?.copyWith(color: muted),
                            ),
                          ),
                        ],
                      ],
                    ),
                    fill: s.differs ? colors.divBg : null,
                  ),
                  cell(script(s.syriac)),
                  cell(translit(s.ugaritic), centre: false),
                  cell(script(s.arabic)),
                  cell(script(s.geez)),
                  cell(translit(s.akkadian), centre: false),
                  cell(
                    Text(
                      s.note,
                      style: _mixed(
                        theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                    centre: false,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.painter,
    required this.size,
    required this.caption,
  });

  final CustomPainter painter;
  final Size size;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: size.width + 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: FittedBox(
              child: CustomPaint(size: size, painter: painter),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: _mixed(
              theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared drawing for the two diagrams.
abstract class _Diagram extends CustomPainter {
  _Diagram(this.colors, this.theme);

  final _Colors colors;
  final ThemeData theme;

  Color get fg => theme.colorScheme.onSurface;
  Color get muted => theme.colorScheme.onSurfaceVariant;

  /// Draws [s] with its baseline at [y], like SVG text.
  void text(
    Canvas canvas,
    String s,
    double x,
    double y, {
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(canvas, Offset(x, y - baseline));
  }

  TextStyle get sound => TextStyle(
    color: fg,
    fontFamily: 'Cardo',
    fontStyle: FontStyle.italic,
    fontSize: 17,
  );
  TextStyle hebrew(Color color) =>
      foreignStyle('א', size: 28).copyWith(color: color);
  TextStyle get label => (theme.textTheme.bodySmall ?? const TextStyle())
      .copyWith(color: muted, fontSize: 12);

  Paint stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  void dot(Canvas canvas, double x, double y) {
    canvas.drawCircle(
      Offset(x, y),
      4,
      Paint()..color = theme.colorScheme.surfaceContainerLowest,
    );
    canvas.drawCircle(Offset(x, y), 4, stroke(muted, 1.4));
  }

  /// SVG's `M x0 y0 C c1x c1y, c2x c2y, x1 y1`.
  Path curve(
    double x0,
    double y0,
    double cx1,
    double cy1,
    double cx2,
    double cy2,
    double x1,
    double y1,
  ) => Path()
    ..moveTo(x0, y0)
    ..cubicTo(cx1, cy1, cx2, cy2, x1, y1);

  @override
  bool shouldRepaint(covariant _Diagram old) =>
      old.theme != theme || old.colors.merge != colors.merge;
}

/// Older sounds converging into one Hebrew letter.
class _MergePainter extends _Diagram {
  _MergePainter(super.colors, super.theme);

  @override
  void paint(Canvas canvas, Size size) {
    text(canvas, 'older sound', 40, 14, style: label);
    text(canvas, 'Hebrew', 256, 14, style: label);
    final base = stroke(muted, 1.6);
    final merge = stroke(colors.merge, 2.2);
    // Each group: its sounds' rows, where they meet, and the letter.
    const groups = [
      (['z', 'ḏ'], 40.0, 'ז'),
      (['ḥ', 'ḫ'], 116.0, 'ח'),
      (['ʿ', 'ġ'], 192.0, 'ע'),
      (['š', 'ṯ'], 268.0, 'שׁ'),
      (['ṣ', 'ṣ́', 'ṯ̣'], 344.0, 'צ'),
    ];
    for (final (sounds, top, letter) in groups) {
      final meet = top + (sounds.length - 1) * 15;
      for (var i = 0; i < sounds.length; i++) {
        final y = top + i * 30;
        canvas.drawPath(
          curve(70, y, 160, y, 170, meet, 236, meet),
          i == 0 ? base : merge,
        );
        dot(canvas, 64, y);
        text(canvas, sounds[i], 38, y + 6, style: sound);
      }
      text(canvas, letter, 250, meet + 10, style: hebrew(colors.merge));
    }
    // ś: the same letter shape as shin.
    canvas.drawLine(const Offset(70, 450), const Offset(236, 450), merge);
    dot(canvas, 64, 450);
    text(canvas, 'ś', 38, 456, style: sound);
    text(canvas, 'שׂ', 250, 460, style: hebrew(colors.merge));
    text(canvas, 'same letter', 290, 446, style: label);
    text(canvas, 'as shin', 290, 460, style: label);
  }
}

/// One older sound written differently in Hebrew and Aramaic.
class _SplitPainter extends _Diagram {
  _SplitPainter(super.colors, super.theme);

  @override
  void paint(Canvas canvas, Size size) {
    text(canvas, 'older sound', 30, 14, style: label);
    text(canvas, 'Hebrew · Aramaic', 230, 14, style: label);
    final base = stroke(muted, 1.6);
    final div = stroke(colors.div, 2.2);
    const rows = [
      ('ḏ', 'ז', 'ד', 'ז'),
      ('ṯ', 'שׁ', 'ת', 'ש'),
      ('ṯ̣', 'צ', 'ט', 'צ'),
      ('ṣ́', 'צ', 'ע', 'ק'),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (older, hebrewLetter, aramaic, old) = rows[i];
      final y = 70.0 + i * 100;
      dot(canvas, 64, y);
      text(canvas, older, 34, y + 6, style: sound);
      canvas.drawPath(curve(70, y, 150, y, 170, y - 24, 228, y - 24), base);
      canvas.drawPath(curve(70, y, 150, y, 170, y + 24, 228, y + 24), div);
      text(canvas, hebrewLetter, 240, y - 14, style: hebrew(fg));
      text(canvas, 'Hebrew', 274, y - 18, style: label);
      text(canvas, aramaic, 240, y + 34, style: hebrew(colors.div));
      text(canvas, 'Aramaic', 274, y + 30, style: label);
      text(
        canvas,
        '(Old Aram. $old)',
        274,
        y + 44,
        style: label.copyWith(fontFamilyFallback: const ['Noto Serif Hebrew']),
      );
    }
  }
}

class _ScriptSize {
  const _ScriptSize(this.count, this.name, this.detail);

  final int count;
  final String name;
  final String detail;
}

const _sizes = [
  _ScriptSize(
    30,
    'Ugaritic',
    '(13th century BC). 27 consonants, plus three signs for ʾ with '
        'different vowels. It keeps nearly every older sound apart.',
  ),
  _ScriptSize(
    29,
    'Old South Arabian',
    'One letter for each of the 29 older consonants.',
  ),
  _ScriptSize(
    28,
    'Arabic',
    'Built on a 22-letter Aramaic-derived script, with dots added to '
        'recover the extra sounds its speakers still made. Merges s and š.',
  ),
  _ScriptSize(
    22,
    'Phoenician, Hebrew, Aramaic',
    'The alphabet fits the sounds of Phoenician, which had already merged '
        'several. Hebrew and Aramaic took it over and wrote their extra sounds '
        'with the nearest letter.',
  ),
];

class _SizeCard extends StatelessWidget {
  const _SizeCard(this.size);

  final _ScriptSize size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${size.count}',
              style: theme.textTheme.displaySmall?.copyWith(
                fontFamily: 'Cardo',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: size.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: size.detail.startsWith('(')
                        ? ' ${size.detail}'
                        : '. ${size.detail}',
                  ),
                ],
              ),
              style: _mixed(theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// A verse the reader can go to: a 0-based book index, as the reader takes.
class _Ref {
  const _Ref(this.label, this.book, this.chapter, this.verse);

  final String label;
  final int book;
  final int chapter;
  final int verse;
}

class _Example {
  const _Example(
    this.tag,
    this.forms,
    this.shows, {
    this.refs = const [],
    this.verify,
  });

  final String tag;
  final List<String> forms;
  final String shows;
  final List<_Ref> refs;

  /// What still needs checking against the cognate's own dictionary.
  final String? verify;
}

const _examples = [
  _Example(
    'ḏ · Hebrew and Aramaic differ',
    ['זָהָב', 'דְּהַב', 'ذَهَب'],
    '“Gold”. Hebrew writes ז, Biblical Aramaic ד (Dan 2:32, the image’s head '
        'of gold), Arabic keeps ḏ. One word, one older sound, two spellings.',
    refs: [_Ref('Dan 2:32', 34, 2, 32)],
  ),
  _Example(
    'ṯ · Hebrew and Aramaic differ',
    ['שָׁלֹשׁ', 'תְּלָת', 'ثَلَاث'],
    '“Three”. Hebrew שׁ, Aramaic ת, Arabic ث all go back to ṯ, in both the '
        'first and last letter.',
  ),
  _Example(
    'ṣ́ · Hebrew and Aramaic differ',
    ['אֶרֶץ', 'אַרְעָא', 'أَرْض'],
    '“Earth, land”. Hebrew צ, Aramaic ע, Arabic ض. Jeremiah 10:11, an '
        'Aramaic verse, spells it both אַרְקָא (the older spelling) and אַרְעָא.',
    refs: [_Ref('Jer 10:11', 12, 10, 11)],
  ),
  _Example(
    'ע · two senses, two sounds',
    ['עֶרֶב', 'עָרַב', 'עֹרֵב'],
    '“Evening” matches Arabic غَرْب ġarb “sunset, west”, and the raven '
        'matches غُرَاب ġurāb: both ġ. “Stand surety, pledge” matches Arabic '
        'عَرَبُون ʿarabūn “earnest money”, with ʿ.',
    verify: 'ʿarabūn',
  ),
  _Example(
    'ע · ġ',
    ['עֶלֶם', 'עַלְמָה'],
    '“Young man, young woman”. Ugaritic ġlm “lad” and Arabic غُلَام ġulām '
        '“boy” show ġ, which sets these words apart from other roots spelled עלם.',
  ),
  _Example(
    'ח and שׁ · two mergers in one spelling',
    ['חָרַשׁ', 'חֵרֵשׁ'],
    '“Plough, engrave” matches Arabic حَرَثَ ḥaraṯa and Ugaritic ḥrṯ: ḥ and '
        'ṯ. “Deaf, silent” points to a root with ḫ and š, as in Arabic أَخْرَس '
        'ʾaḫras “mute”.',
    verify: 'ʾaḫras',
  ),
  _Example(
    'ע · ġ still spoken',
    ['עַזָּה', 'Γάζα', 'غَزَّة'],
    'The Septuagint (about the 3rd century BC) writes Gaza with a g, as '
        'Arabic still does. Hebrew speakers still said ġ in this word, though '
        'the letter was ע.',
  ),
  _Example(
    'שׁ · from ṯ',
    ['אֲשֶׁר', 'אֲתַר', 'أَثَر'],
    'The ש of אשר goes back to ṯ. Biblical Aramaic has אֲתַר “place” '
        '(Dan 2:35), and Arabic ʾaṯar “trace, footprint”. So shin’s later letter '
        'name says nothing about this root.',
    refs: [_Ref('Dan 2:35', 34, 2, 35)],
  ),
  _Example(
    'ז · no merger: one root',
    ['זָכַר', 'זָכָר', 'ذَكَرَ', 'ذَكَر'],
    '“Remember” and “male” both have ḏkr in Arabic, and Aramaic writes both '
        'with ד (דִּכְרִין “rams”, Ezra 6:9). The cognates show no split, so the '
        'two senses belong to one root and the link between them is one of '
        'meaning.',
    refs: [_Ref('Ezra 6:9', 35, 6, 9)],
  ),
  _Example(
    'Scripture records an accent',
    ['שִׁבֹּלֶת', 'סִבֹּלֶת'],
    'Judges 12:6. The men of Gilead heard the Ephraimites say the word '
        'differently, and the text spells their form with ס. Spoken Hebrew had '
        'regional differences that its letters could show only roughly.',
    refs: [_Ref('Judg 12:6', 6, 12, 6)],
  ),
];

class _ExampleCard extends StatelessWidget {
  const _ExampleCard(this.example, {required this.colors, this.onGo});

  final _Example example;
  final _Colors colors;
  final void Function(_Ref)? onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                example.tag.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  for (final f in example.forms)
                    Text(f, style: foreignStyle(f, size: 24)),
                ],
              ),
              const SizedBox(height: 8),
              Text(example.shows, style: _mixed(theme.textTheme.bodyMedium)),
              if (example.verify != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.div),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'TO VERIFY: ${example.verify}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.div,
                    ),
                  ),
                ),
              ],
              if (onGo != null && example.refs.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: [
                    for (final ref in example.refs)
                      TextButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(ref.label),
                        onPressed: () => onGo!(ref),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
