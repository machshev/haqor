import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'prophecy_card.dart';
import 'verse_text_cache.dart';

/// When prophecies are fulfilled, as the page filters them: the core's
/// horizons, or any.
const _horizons = <(String, String)>[
  ('', 'Any time'),
  ('first-advent', 'Christ\'s first coming'),
  ('second-advent', 'Christ\'s return'),
  ('both', 'Both comings'),
  ('history', 'In history'),
];

/// The prophecies of the whole Bible, grouped by theme: the promises
/// concerning Christ, then Israel, the nations and the empires of Daniel.
/// Searched and filtered by theme, by messianic or general, and by when they
/// are fulfilled. Choosing one shows its passage, note and fulfilments —
/// beside the list on a wide screen, on a page of its own on a narrow one —
/// and a verse opens in the reader, closing the page.
class ProphecyPage extends StatefulWidget {
  const ProphecyPage({
    super.key,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.ntGreek = false,
    this.onNavigateToPassage,
    this.sendRequest,
    this.sendVerseTextsRequest,
  });

  final bool useEnglishBookNames;

  /// Show New Testament verses in Syriac script, as the reader is set to.
  final bool ntSyriac;

  /// Show New Testament verses in Greek, as the reader is set to.
  final bool ntGreek;

  /// Opens a passage in the reader: 0-based book index, chapter, verse.
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Stand in for the signals to Rust, for tests.
  final void Function(GetProphecies)? sendRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  static Future<void> open(
    BuildContext context, {
    bool useEnglishBookNames = false,
    bool ntSyriac = false,
    bool ntGreek = false,
    void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProphecyPage(
        useEnglishBookNames: useEnglishBookNames,
        ntSyriac: ntSyriac,
        ntGreek: ntGreek,
        onNavigateToPassage: onNavigateToPassage,
      ),
    ),
  );

  @override
  State<ProphecyPage> createState() => _ProphecyPageState();
}

class _ProphecyPageState extends State<ProphecyPage> {
  /// More than the Bible has: the page asks for them all at once and filters
  /// them itself.
  static const _limit = 10000;
  static int _nextRequestId = 1;

  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  StreamSubscription<RustSignalPack<Prophecies>>? _sub;
  int _requestId = 0;

  /// Every prophecy, in the order of their passages; null until they arrive.
  List<ProphecyEntry>? _all;

  String _query = '';
  String _theme = '';
  ProphecyKinds _kinds = ProphecyKinds.all;
  String _horizon = '';

  /// The prophecy shown beside the list on a wide screen.
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _sub = Prophecies.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId || !mounted) return;
      setState(() => _all = reply.entries);
    });
    final request = GetProphecies(
      requestId: _requestId = _nextRequestId++,
      book: 0,
      firstChapter: 0,
      lastChapter: 0,
      theme: '',
      messianic: 0,
      limit: _limit,
      offset: 0,
    );
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _verseTexts.dispose();
    super.dispose();
  }

  String _passage(PassageSpan s) {
    final start =
        '${bookDisplayName(s.book - 1, useEnglish: widget.useEnglishBookNames)} '
        '${s.chapter}:${s.verse}';
    if (s.lastChapter == s.chapter && s.lastVerse == s.verse) return start;
    if (s.lastChapter == s.chapter) return '$start–${s.lastVerse}';
    return '$start–${s.lastChapter}:${s.lastVerse}';
  }

  bool _matches(ProphecyEntry p) {
    if (_theme.isNotEmpty && p.theme != _theme) return false;
    if (_horizon.isNotEmpty && p.horizon != _horizon) return false;
    switch (_kinds) {
      case ProphecyKinds.messianic when !p.messianic:
      case ProphecyKinds.general when p.messianic:
        return false;
      default:
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      p.title,
      p.note,
      _passage(p.passage),
      for (final f in p.fulfilments) _passage(f.passage),
    ].any((text) => text.toLowerCase().contains(query));
  }

  /// The shown prophecies by theme, in [prophecyThemes]' order, those
  /// without one last.
  List<(String, List<ProphecyEntry>)> _groups(List<ProphecyEntry> shown) => [
    for (final theme in [...prophecyThemes, ''])
      if (shown.where((p) => p.theme == theme).toList() case final group
          when group.isNotEmpty)
        (theme, group),
  ];

  /// Opens a passage in the reader, closing the page (and a prophecy's own
  /// page above it).
  void Function(int, int, int)? get _navigate {
    final navigate = widget.onNavigateToPassage;
    if (navigate == null) return null;
    return (book, chapter, verse) {
      final page = ModalRoute.of(context);
      Navigator.of(context)
        ..popUntil((route) => route == page)
        ..maybePop();
      navigate(book, chapter, verse);
    };
  }

  Widget _card(ProphecyEntry p) => ProphecyCard(
    key: ValueKey('prophecy-${p.id}'),
    prophecy: p,
    cache: _verseTexts,
    useEnglishBookNames: widget.useEnglishBookNames,
    englishOnly: false,
    ntSyriac: widget.ntSyriac,
    ntGreek: widget.ntGreek,
    onNavigateToPassage: _navigate,
  );

  void _openOwnPage(ProphecyEntry p) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(_passage(p.passage))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [_card(p)],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: const Text('Bible prophecy')),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This database has no prophecies. Update the app\'s data '
                  'to see them.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 840;
                final shown = all.where(_matches).toList();
                final list = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _controls(context, shown.length),
                    const Divider(height: 1),
                    Expanded(child: _list(context, shown, wide: wide)),
                  ],
                );
                if (!wide) return list;
                final selected = shown
                    .where((p) => p.id == _selectedId)
                    .firstOrNull;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 420, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected == null
                          ? const Center(child: Text('Choose a prophecy.'))
                          : ListView(
                              key: ValueKey('detail-${selected.id}'),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                24,
                              ),
                              children: [_card(selected)],
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _controls(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            key: const ValueKey('prophecy-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search titles, notes and references',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              for (final (value, label) in [
                ('', 'All themes'),
                for (final t in prophecyThemes) (t, prophecyThemeLabel(t)),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _theme == value,
                  onSelected: (_) => setState(() => _theme = value),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<ProphecyKinds>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ProphecyKinds.all, label: Text('All')),
                  ButtonSegment(
                    value: ProphecyKinds.messianic,
                    label: Text('Messianic'),
                  ),
                  ButtonSegment(
                    value: ProphecyKinds.general,
                    label: Text('General'),
                  ),
                ],
                selected: {_kinds},
                onSelectionChanged: (s) => setState(() => _kinds = s.single),
              ),
              DropdownButton<String>(
                key: const ValueKey('prophecy-horizon'),
                value: _horizon,
                items: [
                  for (final (value, label) in _horizons)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (h) => setState(() => _horizon = h!),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Text(
            count == 1 ? '1 prophecy' : '$count prophecies',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    List<ProphecyEntry> shown, {
    required bool wide,
  }) {
    if (shown.isEmpty) {
      return const Center(child: Text('No prophecies match.'));
    }
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final (group, prophecies) in _groups(shown)) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            group.isEmpty ? 'Other prophecies' : prophecyThemeLabel(group),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
      for (final p in prophecies) {
        final fulfilments = p.fulfilments.length;
        rows.add(
          ListTile(
            key: ValueKey('prophecy-row-${p.id}'),
            dense: true,
            selected: wide && p.id == _selectedId,
            title: Text(
              p.title.isEmpty ? 'Quoted as fulfilled in the NT' : p.title,
            ),
            subtitle: Text(
              [
                _passage(p.passage),
                if (fulfilments > 0)
                  fulfilments == 1 ? '1 fulfilment' : '$fulfilments fulfilments'
                else if (p.horizon.isNotEmpty)
                  prophecyHorizonLabel(p.horizon),
              ].join(' · '),
            ),
            onTap: () =>
                wide ? setState(() => _selectedId = p.id) : _openOwnPage(p),
          ),
        );
      }
    }
    return ListView(
      key: const ValueKey('prophecy-list'),
      padding: const EdgeInsets.only(bottom: 24),
      children: rows,
    );
  }
}
