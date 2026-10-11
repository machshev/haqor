import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/prophecy_card.dart';
import 'package:haqor/src/widgets/prophecy_page.dart';

PassageSpan _span(int book, int chapter, int verse, [int? lastVerse]) =>
    PassageSpan(
      book: book,
      chapter: chapter,
      verse: verse,
      lastChapter: chapter,
      lastVerse: lastVerse ?? verse,
    );

ProphecyEntry _prophecy({
  required int id,
  required PassageSpan passage,
  required String title,
  String theme = '',
  bool messianic = true,
  List<String> stages = const [],
  List<ProphecyFulfilmentEntry> fulfilments = const [],
  List<ProphecyPatternEntry> patterns = const [],
}) => ProphecyEntry(
  id: id,
  passage: passage,
  title: title,
  theme: theme,
  messianic: messianic,
  stages: stages,
  note: '',
  fulfilments: fulfilments,
  patterns: patterns,
);

/// Babylon's invasion (Jeremiah 1), then Gog's at the return and after the
/// thousand years (Ezekiel 38), the second a prophecy twice.
final _north = ProphecyPatternEntry(
  id: 1,
  title: 'Invasions from the north',
  note: 'Babylon, Rome, Gog.',
  members: [
    ProphecyPatternMemberEntry(
      prophecyId: 4,
      passage: _span(13, 1, 13, 15),
      stage: 'history',
      label: 'Babylon: the seething pot',
    ),
    ProphecyPatternMemberEntry(
      prophecyId: 5,
      passage: _span(14, 38, 1, 23),
      stage: 'return',
      label: 'Gog at Christ\'s return',
    ),
    ProphecyPatternMemberEntry(
      prophecyId: 5,
      passage: _span(14, 38, 1, 23),
      stage: 'millennium-end',
      label: 'Gog after the thousand years',
    ),
  ],
);

/// Isaiah 7:14, quoted at Matthew 1:22-23; Daniel 2:44, awaiting the
/// return; Tyre, fulfilled in history; and the invasions from the north.
final _prophecies = [
  _prophecy(
    id: 1,
    passage: _span(12, 7, 13, 14),
    title: 'A virgin shall conceive',
    theme: 'davidic',
    stages: ['first-advent'],
    fulfilments: [
      ProphecyFulfilmentEntry(
        passage: _span(40, 1, 22, 23),
        prophecyVerses: _span(12, 7, 14),
        kind: 'quotation',
        stage: 'first-advent',
        formula: 'fulfilled+spoken',
        reviewed: true,
        note: '',
      ),
    ],
  ),
  _prophecy(
    id: 2,
    passage: _span(14, 26, 1, 14),
    title: 'Tyre a place to spread nets',
    theme: 'nations',
    messianic: false,
    stages: ['history'],
  ),
  _prophecy(
    id: 3,
    passage: _span(35, 2, 44, 45),
    title: 'The stone cut out without hands',
    theme: 'kingdom',
    stages: ['return'],
  ),
  _prophecy(
    id: 4,
    passage: _span(13, 1, 13, 15),
    title: 'A seething pot out of the north',
    theme: 'nations',
    messianic: false,
    stages: ['history'],
    patterns: [_north],
  ),
  _prophecy(
    id: 5,
    passage: _span(14, 38, 1, 23),
    title: 'Gog invades the restored land',
    theme: 'nations',
    messianic: false,
    stages: ['return', 'millennium-end'],
    patterns: [_north],
  ),
];

Future<List<GetProphecies>> _pump(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  void Function(int, int, int)? onNavigate,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final requests = <GetProphecies>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProphecyPage(
                  useEnglishBookNames: true,
                  onNavigateToPassage: onNavigate,
                  sendRequest: requests.add,
                  sendVerseTextsRequest: (_) {},
                ),
              ),
            ),
            child: const Text('reader'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('reader'));
  // The page opens on its spinner, which never settles.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return requests;
}

void _deliver(GetProphecies request, List<ProphecyEntry> entries) {
  assignRustSignal['Prophecies']!(
    Prophecies(
      requestId: request.requestId,
      book: 0,
      total: entries.length,
      entries: entries,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  testWidgets('asks for every prophecy and groups them by theme', (
    tester,
  ) async {
    final requests = await _pump(tester);
    final request = requests.single;
    expect((request.book, request.theme, request.messianic), (0, '', 0));
    expect(request.limit, greaterThan(1000));

    _deliver(request, _prophecies);
    await tester.pumpAndSettle();
    expect(find.text('5 prophecies'), findsOneWidget);
    // Theme headings, in the themes' order: David's before the kingdom's.
    final david = tester.getTopLeft(find.text('Promises to David').last);
    final kingdom = tester.getTopLeft(find.text('The kingdom').last);
    expect(david.dy, lessThan(kingdom.dy));
    // Each row says when it is fulfilled.
    expect(find.text("Isaiah 7:13–14 · Christ's first coming"), findsOneWidget);
    expect(find.text("Daniel 2:44–45 · Christ's return"), findsOneWidget);
  });

  testWidgets('filters by theme, kind, time and search', (tester) async {
    final requests = await _pump(tester, size: const Size(900, 800));
    _deliver(requests.single, _prophecies);
    await tester.pumpAndSettle();

    // The theme chips scroll sideways.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'The kingdom'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'The kingdom'));
    await tester.pumpAndSettle();
    expect(find.text('1 prophecy'), findsOneWidget);
    expect(find.text('The stone cut out without hands'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All themes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'All themes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('3 prophecies'), findsOneWidget);
    expect(find.text('Tyre a place to spread nets'), findsOneWidget);
    expect(find.text('A virgin shall conceive'), findsNothing);
    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();

    // A prophecy fulfilled at several stages is found under each.
    await tester.tap(find.byKey(const ValueKey('prophecy-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Christ's return").last);
    await tester.pumpAndSettle();
    expect(find.text('2 prophecies'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prophecy-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('After the thousand years').last);
    await tester.pumpAndSettle();
    expect(find.text('1 prophecy'), findsOneWidget);
    expect(find.text('Gog invades the restored land'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prophecy-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any time').last);
    await tester.pumpAndSettle();

    // A fulfilment's reference finds its prophecy.
    await tester.enterText(
      find.byKey(const ValueKey('prophecy-search')),
      'matthew 1',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 prophecy'), findsOneWidget);
    expect(find.text('A virgin shall conceive'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('prophecy-search')),
      'nothing like this',
    );
    await tester.pumpAndSettle();
    expect(find.text('No prophecies match.'), findsOneWidget);
  });

  testWidgets('wide, a prophecy shows beside the list', (tester) async {
    final requests = await _pump(tester, size: const Size(1200, 800));
    _deliver(requests.single, _prophecies);
    await tester.pumpAndSettle();
    expect(find.text('Choose a prophecy.'), findsOneWidget);

    await tester.tap(find.text('A virgin shall conceive'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-1')), findsOneWidget);
    expect(
      find.text('Quotation · Matthew 1:22–23 · of Isaiah 7:14'),
      findsOneWidget,
    );
  });

  testWidgets('narrow, a prophecy opens on its own page and a verse in the '
      'reader', (tester) async {
    final opened = <(int, int, int)>[];
    final requests = await _pump(
      tester,
      onNavigate: (b, c, v) => opened.add((b, c, v)),
    );
    _deliver(requests.single, _prophecies);
    await tester.pumpAndSettle();

    await tester.tap(find.text('The stone cut out without hands'));
    await tester.pumpAndSettle();
    expect(find.text('No fulfilment recorded in the Bible.'), findsOneWidget);

    // The passage's reference on the card, not the page's title.
    await tester.tap(
      find.descendant(
        of: find.byType(ProphecyCard),
        matching: find.text('Daniel 2:44–45'),
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, [(34, 2, 44)]);
    // Both the prophecy's page and the list are closed: the reader shows.
    expect(find.byType(ProphecyPage), findsNothing);
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('a pattern lists its steps in order and steps between them', (
    tester,
  ) async {
    final requests = await _pump(tester, size: const Size(1200, 900));
    _deliver(requests.single, _prophecies);
    await tester.pumpAndSettle();

    final chip = find.widgetWithText(ChoiceChip, 'Invasions from the north');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    // Gog is two steps: at the return and after the thousand years.
    expect(find.text('2 prophecies'), findsOneWidget);
    for (final (i, subtitle) in [
      'Before Christ · Babylon: the seething pot · Jeremiah 1:13–15',
      "Christ's return · Gog at Christ's return · Ezekiel 38:1–23",
      'After the thousand years · Gog after the thousand years · '
          'Ezekiel 38:1–23',
    ].indexed) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('pattern-row-$i')),
          matching: find.text(subtitle),
        ),
        findsOneWidget,
      );
    }

    // The card's pattern steps to another of its prophecies.
    await tester.tap(find.byKey(const ValueKey('pattern-row-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-4')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pattern-1')),
        matching: find.text("Gog at Christ's return · Ezekiel 38:1–23"),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-5')), findsOneWidget);
  });

  testWidgets('says so when the database has none', (tester) async {
    final requests = await _pump(tester);
    _deliver(requests.single, const []);
    await tester.pumpAndSettle();
    expect(find.textContaining('has no prophecies'), findsOneWidget);
  });
}
