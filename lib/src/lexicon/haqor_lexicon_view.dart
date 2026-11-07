import 'dart:async';

import 'package:flutter/material.dart';

import '../bible_data.dart';
import 'haqor_lexicon_store.dart';

/// Edit the string at [node]`[key]`; [label] names it in the editor.
typedef LexiconEdit =
    void Function(
      Map<String, dynamic> node,
      String key, {
      required String label,
      bool multiline,
    });

/// Go to a passage: Haqor's 0-based book index, chapter and verse.
typedef LexiconNavigate = void Function(int bookIndex, int chapter, int verse);

const _hebrewFont = 'Noto Serif Hebrew';

String _str(Map<String, dynamic> node, String key) {
  final value = node[key];
  return value is String ? value : '';
}

List<Map<String, dynamic>> _list(Map<String, dynamic> node, String key) {
  final value = node[key];
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList();
}

List<String> _strings(Map<String, dynamic> node, String key) {
  final value = node[key];
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}

/// The direction of a string's first strong character: Hebrew, Arabic,
/// Syriac and Phoenician run right to left.
TextDirection directionOf(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF) ||
        (rune >= 0x10900 && rune <= 0x1091F)) {
      return TextDirection.rtl;
    }
    if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x00C0 && rune <= 0x024F) ||
        (rune >= 0x0370 && rune <= 0x03FF) ||
        (rune >= 0x1F00 && rune <= 0x1FFF) ||
        (rune >= 0x1200 && rune <= 0x139F) ||
        (rune >= 0x10380 && rune <= 0x1039F) ||
        (rune >= 0x12000 && rune <= 0x1254F)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

/// The style for a word in a Semitic or ancient script.
/// The fonts for the cognates' scripts. The app bundles none of them, so
/// they come from the system where it has them (the Noto families name them).
const cognateFontFallback = [
  'Noto Naskh Arabic',
  'Noto Sans Syriac',
  'Noto Sans Phoenician',
  'Noto Sans Ugaritic',
  'Noto Serif Ethiopic',
  'Noto Sans Cuneiform',
];

TextStyle foreignStyle(String text, {double size = 20}) =>
    directionOf(text) == TextDirection.rtl
    ? TextStyle(
        fontFamily: _hebrewFont,
        fontFamilyFallback: const ['Cardo', ...cognateFontFallback],
        fontSize: size,
      )
    : TextStyle(
        fontFamily: 'Cardo',
        fontFamilyFallback: const [_hebrewFont, ...cognateFontFallback],
        fontSize: size,
      );

/// The cognate languages, by the schema's codes.
const Map<String, String> cognateLanguages = {
  'akk': 'Akkadian',
  'uga': 'Ugaritic',
  'phn': 'Phoenician',
  'arc': 'Aramaic',
  'syc': 'Syriac',
  'ar': 'Arabic',
  'gez': "Ge'ez",
  'sem': 'Semitic',
  'grc': 'Greek',
  'egy': 'Egyptian',
};

const Map<String, String> _stemNames = {
  'qal': 'Qal',
  'niphal': 'Niphal',
  'piel': 'Piel',
  'pual': 'Pual',
  'hiphil': 'Hiphil',
  'hophal': 'Hophal',
  'hithpael': 'Hithpael',
  'polel': 'Polel',
  'polal': 'Polal',
  'hithpolel': 'Hithpolel',
  'poel': 'Poel',
  'poal': 'Poal',
  'hithpoel': 'Hithpoel',
  'pilpel': 'Pilpel',
  'pilpal': 'Pilpal',
  'hithpalpel': 'Hithpalpel',
  'piel-passive': 'Piel passive',
  'hishtaphel': 'Hishtaphel',
  'tiphil': 'Tiphil',
  'nithpael': 'Nithpael',
  // Aramaic: Biblical Aramaic's and the Peshitta's.
  'peal': 'Peal',
  'peil': 'Peil',
  'pael': 'Pael',
  'aphel': 'Aphel',
  'haphel': 'Haphel',
  'shaphel': 'Shaphel',
  'hithpeel': 'Hithpeel',
  'hithpaal': 'Hithpaal',
  'ithpeel': 'Ithpeel',
  'ithpaal': 'Ithpaal',
  'ethpeel': 'Ethpeel',
  'ethpaal': 'Ethpaal',
  'ettaphal': 'Ettaphal',
  'eshtaphal': 'Eshtaphal',
  'palpel': 'Palpel',
  'ethpalpal': 'Ethpalpal',
};

/// The languages of scripture's words besides Hebrew, by the schema's codes.
const Map<String, String> wordLanguages = {
  'arc': 'Biblical Aramaic',
  'syc': 'Peshitta Syriac',
};

/// `kingdom-of-god` as a heading: "Kingdom of god".
String _topicTitle(String topic) {
  const names = {'god', 'yahweh', 'christ', 'jesus', 'israel'};
  String capital(String w) => '${w[0].toUpperCase()}${w.substring(1)}';
  final words = topic.split('-').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return topic;
  return [
    for (final (i, w) in words.indexed)
      i == 0 || names.contains(w) ? capital(w) : w,
  ].join(' ');
}

/// A Haqor lexicon entry as the reader sees it, from the outline down to the
/// evidence: the root and its gloss stay on top; below them an Overview tab
/// gives the summary and lists what the entry holds, and the Words, Cognates
/// and Doctrine tabs hold the detail. Each word opens on a click to its
/// stems, senses and verses. In [editing] mode every text can be tapped to
/// change it.
class HaqorLexiconEntryView extends StatefulWidget {
  const HaqorLexiconEntryView({
    super.key,
    required this.entry,
    this.editing = false,
    this.onEdit,
    this.onToggleStatus,
    this.onNavigateToPassage,
    this.leading,
    this.bottomInset = 0,
  });

  final LexiconEntryDraft entry;
  final bool editing;
  final LexiconEdit? onEdit;
  final VoidCallback? onToggleStatus;
  final LexiconNavigate? onNavigateToPassage;

  /// Shown above the entry: in the word sheet, who or what the word names.
  final Widget? leading;

  /// Room left below each tab's list, for a sheet's bottom inset.
  final double bottomInset;

  @override
  State<HaqorLexiconEntryView> createState() => _HaqorLexiconEntryViewState();
}

enum _Tab { overview, words, cognates, doctrine }

class _HaqorLexiconEntryViewState extends State<HaqorLexiconEntryView>
    with TickerProviderStateMixin {
  late List<_Tab> _tabs = _tabsFor(widget.entry);
  late TabController _controller = TabController(
    length: _tabs.length,
    vsync: this,
  );

  /// The words opened to their detail, by index.
  final Set<int> _expanded = {};
  final Map<int, GlobalKey> _wordKeys = {};

  static List<_Tab> _tabsFor(LexiconEntryDraft entry) => [
    _Tab.overview,
    _Tab.words,
    if (_list(entry.data, 'cognates').isNotEmpty) _Tab.cognates,
    if (_list(entry.data, 'doctrine').isNotEmpty) _Tab.doctrine,
  ];

  @override
  void initState() {
    super.initState();
    // A lone word needs no click to open.
    if (_list(widget.entry.data, 'words').length == 1) _expanded.add(0);
  }

  @override
  void didUpdateWidget(HaqorLexiconEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tabs = _tabsFor(widget.entry);
    if (tabs.length == _tabs.length) return;
    final current = _tabs[_controller.index];
    _controller.dispose();
    _tabs = tabs;
    _controller = TabController(
      length: tabs.length,
      vsync: this,
      initialIndex: tabs.contains(current) ? tabs.indexOf(current) : 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(_Tab tab) {
    final index = _tabs.indexOf(tab);
    if (index >= 0) _controller.animateTo(index);
  }

  /// Open word [index] in the Words tab and scroll it into view.
  void _openWord(int index) {
    setState(() => _expanded.add(index));
    _open(_Tab.words);
    _reveal(index, 30);
  }

  void _reveal(int index, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _wordKeys[index]?.currentContext;
      final box = context?.findRenderObject();
      final scrollable = context == null ? null : Scrollable.maybeOf(context);
      if (box == null || scrollable == null || _controller.indexIsChanging) {
        if (tries > 0) {
          _reveal(index, tries - 1);
          WidgetsBinding.instance.scheduleFrame();
        }
        return;
      }
      unawaited(
        scrollable.position.ensureVisible(
          box,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.entry.data;
    final scope = _EntryScope(
      entry: widget.entry,
      editing: widget.editing,
      onEdit: widget.onEdit,
      onNavigateToPassage: widget.onNavigateToPassage,
    );
    // English text quotes Hebrew and the cognates' scripts inline, which the
    // app's body font lacks.
    final withScripts = theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamilyFallback: const [
          _hebrewFont,
          'Cardo',
          ...cognateFontFallback,
        ],
      ),
    );
    String counted(String name, String key) {
      final n = _list(data, key).length;
      return n == 0 ? name : '$name ($n)';
    }

    return _EntryScopeProvider(
      scope: scope,
      child: Theme(
        data: withScripts,
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?widget.leading,
              _Header(data: data, onToggleStatus: widget.onToggleStatus),
              TabBar(
                controller: _controller,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final tab in _tabs)
                    Tab(
                      text: switch (tab) {
                        _Tab.overview => 'Overview',
                        _Tab.words => counted('Words', 'words'),
                        _Tab.cognates => counted('Cognates', 'cognates'),
                        _Tab.doctrine => counted('Doctrine', 'doctrine'),
                      },
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _controller,
                  children: [
                    for (final tab in _tabs)
                      switch (tab) {
                        _Tab.overview => _overview(context),
                        _Tab.words => _words(context),
                        _Tab.cognates => _tabList(
                          tab,
                          subtitle:
                              'The same root in the other Semitic languages',
                          children: [
                            for (final c in _list(data, 'cognates'))
                              _CognateRow(cognate: c),
                          ],
                        ),
                        _Tab.doctrine => _tabList(
                          tab,
                          subtitle: "What scripture's use of the word teaches",
                          children: [
                            for (final d in _list(data, 'doctrine'))
                              _DoctrineItem(item: d),
                          ],
                        ),
                      },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabList(
    _Tab tab, {
    String? subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return ListView(
      key: PageStorageKey('${widget.entry.id}/${tab.name}'),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + widget.bottomInset),
      children: [
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...children,
      ],
    );
  }

  Widget _overview(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.entry.data;
    final words = _list(data, 'words');
    final cognates = _list(data, 'cognates');
    final doctrine = _list(data, 'doctrine');
    final tags = _strings(data, 'tags');
    return _tabList(
      _Tab.overview,
      children: [
        _EditableText(
          node: data,
          field: 'summary',
          label: 'summary',
          multiline: true,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in tags)
                Chip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  labelStyle: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ],
        if (words.isNotEmpty)
          _OverviewSection(
            title: 'Words',
            onOpen: () => _open(_Tab.words),
            children: [
              for (final (i, word) in words.indexed)
                _WordSummaryRow(word: word, onTap: () => _openWord(i)),
            ],
          ),
        if (cognates.isNotEmpty)
          _OverviewSection(
            title: 'Cognates',
            onOpen: () => _open(_Tab.cognates),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in cognates)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${cognateLanguages[_str(c, 'lang')] ?? _str(c, 'lang')} ',
                              style: theme.textTheme.labelMedium,
                            ),
                            TextSpan(
                              text: _str(c, 'form'),
                              style: foreignStyle(_str(c, 'form'), size: 16),
                            ),
                          ],
                        ),
                      ),
                      onPressed: () => _open(_Tab.cognates),
                    ),
                ],
              ),
            ],
          ),
        if (doctrine.isNotEmpty)
          _OverviewSection(
            title: 'Doctrine',
            onOpen: () => _open(_Tab.doctrine),
            children: [
              for (final d in doctrine)
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _open(_Tab.doctrine),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _topicTitle(_str(d, 'topic')),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        if (widget.editing)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Editor's note (not shown to readers)",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _EditableText(
                    node: data,
                    field: 'note',
                    label: "Editor's note",
                    multiline: true,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _words(BuildContext context) {
    final words = _list(widget.entry.data, 'words');
    final allOpen = _expanded.length >= words.length;
    return _tabList(
      _Tab.words,
      children: [
        if (words.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: Icon(allOpen ? Icons.unfold_less : Icons.unfold_more),
              label: Text(allOpen ? 'Collapse all' : 'Expand all'),
              onPressed: () => setState(() {
                if (allOpen) {
                  _expanded.clear();
                } else {
                  _expanded.addAll([for (var i = 0; i < words.length; i++) i]);
                }
              }),
            ),
          ),
        for (final (i, word) in words.indexed)
          _WordCard(
            key: _wordKeys.putIfAbsent(i, GlobalKey.new),
            word: word,
            support: i < widget.entry.support.length
                ? widget.entry.support[i]
                : null,
            expanded: _expanded.contains(i),
            onToggle: () => setState(() {
              if (!_expanded.remove(i)) _expanded.add(i);
            }),
          ),
      ],
    );
  }
}

/// What every part of the view needs, without threading it through each.
class _EntryScope {
  const _EntryScope({
    required this.entry,
    required this.editing,
    required this.onEdit,
    required this.onNavigateToPassage,
  });

  final LexiconEntryDraft entry;
  final bool editing;
  final LexiconEdit? onEdit;
  final LexiconNavigate? onNavigateToPassage;
}

class _EntryScopeProvider extends InheritedWidget {
  const _EntryScopeProvider({required this.scope, required super.child});

  final _EntryScope scope;

  static _EntryScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EntryScopeProvider>()!.scope;

  @override
  bool updateShouldNotify(_EntryScopeProvider oldWidget) => true;
}

/// A string of the entry, which in editing mode can be tapped to change.
class _EditableText extends StatelessWidget {
  const _EditableText({
    required this.node,
    required this.field,
    required this.label,
    this.style,
    this.multiline = false,
  });

  final Map<String, dynamic> node;
  final String field;
  final String label;
  final TextStyle? style;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final scope = _EntryScopeProvider.of(context);
    final text = _str(node, field);
    final direction = directionOf(text);
    if (!scope.editing || scope.onEdit == null) {
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(text, style: style, textDirection: direction);
    }
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () =>
          scope.onEdit!(node, field, label: label, multiline: multiline),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: text.isEmpty
                  ? Text(
                      'Add $label',
                      style: style?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.outline,
                      ),
                    )
                  : Text(text, style: style, textDirection: direction),
            ),
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// The root, its gloss and its review status: what stays above the tabs.
class _Header extends StatelessWidget {
  const _Header({required this.data, this.onToggleStatus});

  final Map<String, dynamic> data;
  final VoidCallback? onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = _EntryScopeProvider.of(context);
    final root = _str(data, 'root');
    final homograph = data['homograph'];
    final reviewed = _str(data, 'status') == 'reviewed';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(
            message: 'Root',
            child: Text(
              root.split('').join(' '),
              textDirection: TextDirection.rtl,
              style: foreignStyle(root, size: 30),
            ),
          ),
          if (homograph is int)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('$homograph', style: theme.textTheme.labelSmall),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: _EditableText(
              node: data,
              field: 'gloss',
              label: 'gloss',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (scope.editing)
            FilterChip(
              label: Text(reviewed ? 'Reviewed' : 'Draft'),
              selected: reviewed,
              onSelected: onToggleStatus == null
                  ? null
                  : (_) => onToggleStatus!(),
            )
          else if (!reviewed)
            const Chip(
              label: Text('Draft'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// A part of the Overview: a heading that opens its tab, and its outline.
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.onOpen,
    required this.children,
  });

  final String title;
  final VoidCallback onOpen;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              TextButton(onPressed: onOpen, child: const Text('Details')),
            ],
          ),
          const Divider(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// The grammar a word's header shows: `noun m`, `verb`.
String _grammar(Map<String, dynamic> word) {
  final gender = _str(word, 'gender');
  return [
    _str(word, 'pos'),
    if (gender.isNotEmpty) gender == 'mf' ? 'm/f' : gender,
  ].where((s) => s.isNotEmpty).join(' ');
}

/// What a closed word holds: its stems and how many senses.
String _wordOutline(Map<String, dynamic> word) {
  final stems = _list(word, 'stems');
  final senses =
      _list(word, 'senses').length +
      stems.fold(0, (n, s) => n + _list(s, 'senses').length);
  final stemNames = [
    for (final s in stems) _stemNames[_str(s, 'stem')] ?? _str(s, 'stem'),
  ];
  return [
    if (stemNames.isNotEmpty) stemNames.join(', '),
    if (senses > 0) senses == 1 ? '1 sense' : '$senses senses',
    if (_list(word, 'greek').isNotEmpty) 'NT Greek',
  ].join(' · ');
}

/// A word in the Overview: lemma, grammar and gloss; a tap opens it.
class _WordSummaryRow extends StatelessWidget {
  const _WordSummaryRow({required this.word, required this.onTap});

  final Map<String, dynamic> word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lemma = _str(word, 'lemma');
    final lang = _str(word, 'lang');
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              lemma,
              textDirection: TextDirection.rtl,
              style: foreignStyle(lemma, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              _grammar(word),
              style: theme.textTheme.labelMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  _str(word, 'gloss'),
                  if (lang.isNotEmpty) '(${wordLanguages[lang] ?? lang})',
                ].join(' '),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A word the root forms: closed, its lemma, grammar, gloss and outline;
/// open, its summary, stems, senses with their verses, usage and Greek.
class _WordCard extends StatelessWidget {
  const _WordCard({
    super.key,
    required this.word,
    this.support,
    required this.expanded,
    required this.onToggle,
  });

  final Map<String, dynamic> word;
  final bool expanded;
  final VoidCallback onToggle;

  /// Its evidence counted (haqor-core's `WordSupport`), when the hub sent it.
  final Map<String, dynamic>? support;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lemma = _str(word, 'lemma');
    final stems = _list(word, 'stems');
    final senses = _list(word, 'senses');
    final greek = _list(word, 'greek');
    final usage = word['usage'] is Map<String, dynamic>
        ? word['usage'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final lang = _str(word, 'lang');
    final ownRoot = _str(word, 'root');
    final outline = _wordOutline(word);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              lemma,
                              textDirection: TextDirection.rtl,
                              style: foreignStyle(lemma, size: 28),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _grammar(word),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _EditableText(
                                node: word,
                                field: 'gloss',
                                label: 'gloss',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        if (lang.isNotEmpty || ownRoot.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if (lang.isNotEmpty)
                                  wordLanguages[lang] ?? lang,
                                if (ownRoot.isNotEmpty) 'root $ownRoot',
                              ].join(' · '),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.tertiary,
                              ),
                            ),
                          ),
                        if (outline.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              outline,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (support != null) _SupportLine(support: support!),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        _SoundTags(ids: _strings(word, 'cognate_ids')),
                        if (support != null) _SupportDetail(support: support!),
                        _EditableText(
                          node: word,
                          field: 'summary',
                          label: 'summary',
                          multiline: true,
                          style: theme.textTheme.bodyMedium,
                        ),
                        for (final stem in stems) _StemBlock(stem: stem),
                        if (senses.isNotEmpty) _SenseList(senses: senses),
                        if (_list(usage, 'parallels').isNotEmpty ||
                            _list(usage, 'opposites').isNotEmpty ||
                            _list(usage, 'phrases').isNotEmpty)
                          _Usage(usage: usage),
                        if (greek.isNotEmpty) _GreekBridge(greek: greek),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StemBlock extends StatelessWidget {
  const _StemBlock({required this.stem});

  final Map<String, dynamic> stem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _str(stem, 'stem');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _stemNames[name] ?? name,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EditableText(
                  node: stem,
                  field: 'gloss',
                  label: 'stem gloss',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          _SoundTags(ids: _strings(stem, 'cognate_ids')),
          _SenseList(senses: _list(stem, 'senses')),
        ],
      ),
    );
  }
}

/// Senses numbered 1, 2…, their narrower senses a, b….
class _SenseList extends StatelessWidget {
  const _SenseList({required this.senses, this.depth = 0});

  final List<Map<String, dynamic>> senses;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, sense) in senses.indexed)
          Padding(
            padding: EdgeInsets.only(top: 8, left: depth * 20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    depth == 0
                        ? '${i + 1}.'
                        : '${String.fromCharCode(0x61 + i % 26)}.',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EditableText(
                        node: sense,
                        field: 'gloss',
                        label: 'sense gloss',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _EditableText(
                        node: sense,
                        field: 'definition',
                        label: 'definition',
                        multiline: true,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (_strings(sense, 'tags').isNotEmpty)
                        Text(
                          _strings(sense, 'tags').join(', '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      _SoundTags(ids: _strings(sense, 'cognate_ids')),
                      _Citations(evidence: _list(sense, 'evidence')),
                      if (_list(sense, 'senses').isNotEmpty)
                        _SenseList(
                          senses: _list(sense, 'senses'),
                          depth: depth + 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Usage extends StatelessWidget {
  const _Usage({required this.usage});

  final Map<String, dynamic> usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget related(String title, List<Map<String, dynamic>> items, String key) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(title, style: theme.textTheme.labelLarge),
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        _str(item, key),
                        textDirection: TextDirection.rtl,
                        style: foreignStyle(_str(item, key), size: 20),
                      ),
                      _EditableText(
                        node: item,
                        field: key == 'phrase' ? 'gloss' : 'note',
                        label: key == 'phrase' ? 'phrase gloss' : 'note',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  _Citations(evidence: _list(item, 'evidence')),
                ],
              ),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          related('Set in parallel with', _list(usage, 'parallels'), 'lemma'),
          related('Set against', _list(usage, 'opposites'), 'lemma'),
          related('Phrases', _list(usage, 'phrases'), 'phrase'),
        ],
      ),
    );
  }
}

/// The Greek words connecting the New Testament to the Hebrew word. Shown
/// last and labelled: the Septuagint is a translation, no evidence of the
/// Hebrew's meaning; a loan (the Hebrew word borrowed into Greek) is marked.
class _GreekBridge extends StatelessWidget {
  const _GreekBridge({required this.greek});

  final List<Map<String, dynamic>> greek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('In the New Testament', style: theme.textTheme.labelLarge),
          for (final g in greek)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _str(g, 'lemma'),
                        style: foreignStyle(_str(g, 'lemma'), size: 19),
                      ),
                      _EditableText(
                        node: g,
                        field: 'gloss',
                        label: 'Greek gloss',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (_str(g, 'relation') == 'loan')
                        Tooltip(
                          message:
                              'The Hebrew word itself, borrowed into Greek: the '
                              "New Testament's use of it is evidence of its sense",
                          child: Chip(
                            label: const Text('loan'),
                            visualDensity: VisualDensity.compact,
                            labelStyle: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  _Citations(evidence: _list(g, 'evidence')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CognateRow extends StatelessWidget {
  const _CognateRow({required this.cognate});

  final Map<String, dynamic> cognate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = _str(cognate, 'lang');
    final form = _str(cognate, 'form');
    final translit = _str(cognate, 'translit');
    final relation = _str(cognate, 'relation');
    final sounds = cognate['sounds'] is Map
        ? (cognate['sounds'] as Map).entries
              .map((e) => '${e.key} = ${e.value}')
              .join(', ')
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              cognateLanguages[lang] ?? lang,
              style: theme.textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      form,
                      textDirection: directionOf(form),
                      style: foreignStyle(form, size: 22),
                    ),
                    if (translit.isNotEmpty && translit != form)
                      Text(
                        translit,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (relation.isNotEmpty && relation != 'cognate')
                      Chip(
                        label: Text(relation),
                        visualDensity: VisualDensity.compact,
                        labelStyle: theme.textTheme.labelSmall,
                      ),
                    if (sounds.isNotEmpty)
                      Tooltip(
                        message:
                            'The older sound this cognate shows behind the letter',
                        child: Chip(
                          label: Text(sounds),
                          visualDensity: VisualDensity.compact,
                          labelStyle: foreignStyle(sounds, size: 13),
                        ),
                      ),
                  ],
                ),
                _EditableText(
                  node: cognate,
                  field: 'gloss',
                  label: 'cognate gloss',
                  style: theme.textTheme.bodyLarge,
                ),
                _EditableText(
                  node: cognate,
                  field: 'note',
                  label: 'cognate note',
                  multiline: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                _Citations(evidence: _list(cognate, 'evidence')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctrineItem extends StatelessWidget {
  const _DoctrineItem({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _topicTitle(_str(item, 'topic')),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          _EditableText(
            node: item,
            field: 'statement',
            label: 'statement',
            multiline: true,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          _Citations(evidence: _list(item, 'evidence')),
        ],
      ),
    );
  }
}

/// A sense's, cognate's or statement's evidence as chips: verses (★ for those
/// whose use defines the sense) open the verse; sources open the citation.
class _Citations extends StatelessWidget {
  const _Citations({required this.evidence});

  final List<Map<String, dynamic>> evidence;

  @override
  Widget build(BuildContext context) {
    if (evidence.isEmpty) return const SizedBox.shrink();
    final scope = _EntryScopeProvider.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final citation in evidence)
            if (citation['ref'] is String)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: _str(citation, 'role') == 'defining'
                    ? Icon(
                        Icons.star,
                        size: 14,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                label: Text(referenceLabel(scope.entry, citation)),
                tooltip: _str(citation, 'note').isEmpty
                    ? null
                    : _str(citation, 'note'),
                onPressed: () => _showVerse(context, scope, citation),
              )
            else
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.menu_book_outlined, size: 14),
                label: Text(
                  '${_str(citation, 'source')} · ${_str(citation, 'locator')}',
                ),
                tooltip: _str(citation, 'note').isEmpty
                    ? null
                    : _str(citation, 'note'),
                onPressed: () => _showSource(context, scope, citation),
              ),
        ],
      ),
    );
  }
}

/// `Gen.1.3` as `Genesis 1:3`, with a range's end (`–11` or `–2:4`).
String referenceLabel(LexiconEntryDraft entry, Map<String, dynamic> citation) {
  String label(String reference) {
    final verse = entry.verses[reference];
    if (verse == null) return reference;
    final book = bookDisplayName(verse.book - 1, useEnglish: true);
    return '$book ${verse.chapter}:${verse.verse}';
  }

  final first = _str(citation, 'ref');
  final to = _str(citation, 'to');
  if (to.isEmpty) return label(first);
  final a = entry.verses[first];
  final b = entry.verses[to];
  if (a == null || b == null) return '${label(first)}–$to';
  return a.chapter == b.chapter
      ? '${label(first)}–${b.verse}'
      : '${label(first)}–${b.chapter}:${b.verse}';
}

void _showVerse(
  BuildContext context,
  _EntryScope scope,
  Map<String, dynamic> citation,
) {
  final references = [
    _str(citation, 'ref'),
    if (_str(citation, 'to').isNotEmpty) _str(citation, 'to'),
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _EntryScopeProvider(
      scope: scope,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    referenceLabel(scope.entry, citation),
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_str(citation, 'role') == 'defining')
                    Text(
                      'Defines the sense',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  for (final reference in references)
                    if (scope.entry.verses[reference] case final verse?)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              verse.original,
                              textDirection: directionOf(verse.original),
                              style: foreignStyle(
                                verse.original,
                                size: 22,
                              ).copyWith(height: 1.6),
                            ),
                            if (verse.peshitta.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Peshitta',
                                style: theme.textTheme.labelSmall,
                              ),
                              Text(
                                verse.peshitta,
                                textDirection: TextDirection.rtl,
                                style: foreignStyle(
                                  verse.peshitta,
                                  size: 20,
                                ).copyWith(height: 1.6),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              verse.english,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    else
                      Text('$reference: no such verse'),
                  const SizedBox(height: 12),
                  if (scope.editing || _str(citation, 'note').isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notes,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _EditableText(
                            node: citation,
                            field: 'note',
                            label: 'note on this verse',
                            multiline: true,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (scope.onNavigateToPassage != null &&
                      scope.entry.verses[references.first] != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Go to passage'),
                        onPressed: () {
                          final verse = scope.entry.verses[references.first]!;
                          Navigator.of(sheetContext).pop();
                          scope.onNavigateToPassage!(
                            verse.book - 1,
                            verse.chapter,
                            verse.verse,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

void _showSource(
  BuildContext context,
  _EntryScope scope,
  Map<String, dynamic> citation,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => _EntryScopeProvider(
      scope: scope,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final url = _str(citation, 'url');
          return AlertDialog(
            title: Text(_str(citation, 'source')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  _str(citation, 'locator'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _EditableText(
                  node: citation,
                  field: 'note',
                  label: 'note',
                  multiline: true,
                  style: theme.textTheme.bodyMedium,
                ),
                if (url.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(url, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// The cognates a word, stem or sense names in `cognate_ids`, each with the
/// older sound it shows behind a merged letter of the root (`ע ġ`): what
/// tells one older root from another in a single spelling.
class _SoundTags extends StatelessWidget {
  const _SoundTags({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const SizedBox.shrink();
    final scope = _EntryScopeProvider.of(context);
    final theme = Theme.of(context);
    final cognates = {
      for (final c in _list(scope.entry.data, 'cognates'))
        if (_str(c, 'id').isNotEmpty) _str(c, 'id'): c,
    };
    String label(String id) {
      final c = cognates[id];
      if (c == null) return id;
      final sounds = c['sounds'] is Map
          ? (c['sounds'] as Map).entries
                .map((e) => '${e.key} ${e.value}')
                .join(', ')
          : '';
      final lang = cognateLanguages[_str(c, 'lang')] ?? _str(c, 'lang');
      return [
        if (sounds.isNotEmpty) sounds,
        '$lang ${_str(c, 'form')}',
      ].join(' · ');
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final id in ids)
            Tooltip(
              message: 'Cognate evidence for this sense',
              child: Chip(
                avatar: Icon(
                  Icons.call_split,
                  size: 14,
                  color: theme.colorScheme.tertiary,
                ),
                label: Text(label(id)),
                visualDensity: VisualDensity.compact,
                labelStyle: foreignStyle(label(id), size: 13),
              ),
            ),
        ],
      ),
    );
  }
}

int _int(Map<String, dynamic> m, String key) => (m[key] as num?)?.toInt() ?? 0;

Map<String, dynamic> _map(Map<String, dynamic> m, String key) =>
    m[key] is Map<String, dynamic>
    ? m[key] as Map<String, dynamic>
    : const <String, dynamic>{};

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// A word's evidence counted, in a line: its uses in scripture, the verses
/// cited for it, and the balance of cognates sharing its meaning against
/// those of another meaning (which count double).
class _SupportLine extends StatelessWidget {
  const _SupportLine({required this.support});

  final Map<String, dynamic> support;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uses = support['uses'];
    final cognates = _map(support, 'cognates');
    final sharing = _int(cognates, 'sharing_languages');
    final differing = _int(cognates, 'differing_languages');
    final balance = _int(cognates, 'balance');
    final kin = (support['kin'] as List?)?.length ?? 0;
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final balanceColor = balance < 0
        ? theme.colorScheme.error
        : balance > 0
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Tooltip(
        message:
            'Uses in the Old Testament; verses cited (fixing the meaning); '
            'cognate languages sharing its meaning and of another meaning; '
            'balance: sharing less twice another.',
        child: Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(
                text: [
                  if (uses is num) _plural(uses.toInt(), 'use'),
                  '${_plural(_int(support, 'cited'), 'verse')} '
                      '(${_int(support, 'defining')} defining)',
                  'cognates: $sharing for, $differing against',
                ].join(' · '),
              ),
              const TextSpan(text: ' · balance '),
              TextSpan(
                text: balance > 0 ? '+$balance' : '$balance',
                style: style?.copyWith(
                  color: balanceColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (kin > 0) TextSpan(text: ' · ${_plural(kin, 'kin sense')}'),
            ],
          ),
        ),
      ),
    );
  }
}

/// A word's evidence in full: the cognates for and against its meaning, and
/// its kin in sibling words with their own counts.
class _SupportDetail extends StatelessWidget {
  const _SupportDetail({required this.support});

  final Map<String, dynamic> support;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cognates = _map(support, 'cognates');
    List<String> names(String key) => [
      for (final n in (cognates[key] as List?) ?? const []) '$n',
    ];
    final sharing = names('sharing');
    final differing = names('differing');
    final possible = names('possible');
    final kin = [
      for (final k in (support['kin'] as List?) ?? const [])
        if (k is Map<String, dynamic>) k,
    ];
    final style = theme.textTheme.bodySmall;
    Widget line(String label, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: style?.copyWith(fontWeight: FontWeight.w600, color: color),
            ),
            TextSpan(text: text),
          ],
        ),
        style: foreignStyle(text, size: 13),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(
            'Cognates sharing its meaning',
            sharing.isEmpty ? 'none' : sharing.join(', '),
            color: theme.colorScheme.primary,
          ),
          line(
            'Cognates of another meaning (count double)',
            differing.isEmpty ? 'none' : differing.join(', '),
            color: differing.isEmpty ? null : theme.colorScheme.error,
          ),
          if (possible.isNotEmpty) line('Possible', possible.join(', ')),
          for (final k in kin)
            line(
              'Kin',
              '${k['sense']} — ${[if (k['uses'] is num) _plural((k['uses'] as num).toInt(), 'use'), '${_plural(_int(k, 'cited'), 'verse')} (${_int(k, 'defining')} defining)', _plural(_int(k, 'cognates'), 'cognate')].join(', ')}',
            ),
        ],
      ),
    );
  }
}
