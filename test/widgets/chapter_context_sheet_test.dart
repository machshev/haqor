import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bible_data.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/archaeology_page.dart';
import 'package:haqor/src/widgets/chapter_context_sheet.dart';
import 'package:haqor/src/widgets/chapter_span.dart';
import 'package:haqor/src/widgets/name_details.dart';

void main() {
  testWidgets('a chapter sheet holds places, people and archaeology as tabs', (
    tester,
  ) async {
    final places = <GetChapterPlaces>[];
    final people = <GetChapterPeople>[];
    final finds = <GetChapterArtifacts>[];
    final shown = <ChapterContextTab>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterContextSheet(
            bookIndex: 30,
            chapter: 4,
            useEnglishBookNames: true,
            initialTab: ChapterContextTab.people,
            onTabChanged: shown.add,
            sendPlacesRequest: places.add,
            sendPeopleRequest: people.add,
            sendArtifactsRequest: finds.add,
          ),
        ),
      ),
    );

    // One heading for the chapter; the tabs do not repeat it.
    expect(find.text('Ruth 4'), findsOneWidget);
    expect(find.text('People in Ruth 4'), findsNothing);
    // It opens on the tab last read, asking only for that.
    expect(find.byType(ChapterPeopleSheet), findsOneWidget);
    expect(people.single.book, 31);
    expect(places, isEmpty);
    expect(finds, isEmpty);

    await tester.tap(find.byKey(const ValueKey('chapter-context-archaeology')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChapterArtifactsSheet), findsOneWidget);
    expect(finds.single.chapter, 4);
    expect(find.text('Archaeology in Ruth 4'), findsNothing);
    expect(shown, [ChapterContextTab.archaeology]);

    // Going back keeps the people already fetched.
    await tester.tap(find.byKey(const ValueKey('chapter-context-people')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(people, hasLength(1));
    expect(shown.last, ChapterContextTab.people);
  });

  testWidgets('the sheet widens to nearby chapters and the whole book', (
    tester,
  ) async {
    final people = <GetChapterPeople>[];
    final scopes = <ChapterContextScope>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterContextSheet(
            // Genesis 12, of 50.
            bookIndex: 0,
            chapter: 12,
            useEnglishBookNames: true,
            initialTab: ChapterContextTab.people,
            onScopeChanged: scopes.add,
            sendPeopleRequest: people.add,
          ),
        ),
      ),
    );
    expect(find.text('Genesis 12'), findsOneWidget);
    expect((people.last.chapter, people.last.lastChapter), (12, 12));

    await tester.tap(find.text('Nearby'));
    await tester.pump();
    expect(find.text('Genesis 10–14'), findsOneWidget);
    expect((people.last.chapter, people.last.lastChapter), (10, 14));

    await tester.tap(find.text('Book'));
    await tester.pump();
    expect(find.text('Genesis'), findsOneWidget);
    expect((people.last.chapter, people.last.lastChapter), (1, 50));
    expect(scopes, [ChapterContextScope.nearby, ChapterContextScope.book]);
  });

  testWidgets('a one-chapter book offers no wider scope', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterContextSheet(
            bookIndex: kBooks.indexWhere((b) => b.chapters == 1),
            chapter: 1,
            initialTab: ChapterContextTab.people,
            sendPeopleRequest: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chapter-context-scope')), findsNothing);
  });

  testWidgets('cross references come first, over the span picked', (
    tester,
  ) async {
    final spans = <(int, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterContextSheet(
            bookIndex: 0,
            chapter: 12,
            crossReferencesBuilder: (context, first, last) {
              spans.add((first, last));
              return Text('links $first–$last');
            },
          ),
        ),
      ),
    );
    expect(find.text('Cross refs'), findsOneWidget);
    expect(find.text('links 12–12'), findsOneWidget);
    await tester.tap(find.text('Nearby'));
    await tester.pump();
    expect(find.text('links 10–14'), findsOneWidget);
    expect(spans.last, (10, 14));
  });

  test('verses read by chapter across a run of chapters', () {
    List<ChapterVerseEntry> at(List<(int, int)> refs) => [
      for (final (chapter, verse) in refs)
        ChapterVerseEntry(chapter: chapter, verse: verse),
    ];
    expect(
      namedVersesLabel(at([(4, 1), (4, 2), (4, 19)]), oneChapter: true),
      'verses 1, 2, 19',
    );
    expect(
      namedVersesLabel(at([(1, 1), (1, 2), (4, 11)]), oneChapter: false),
      'verses 1:1, 2; 4:11',
    );
    expect(
      namedVersesLabel(
        at([(1, 1), (1, 2), (1, 3)]),
        oneChapter: false,
        limit: 2,
      ),
      'verses 1:1, 2 and 1 more',
    );
    expect(
      coveredVersesLabel(at([(18, 13), (18, 14), (18, 15)]), oneChapter: true),
      'Verses 13–15',
    );
    expect(
      coveredVersesLabel(
        at([(18, 36), (18, 37), (19, 1), (19, 2), (19, 9)]),
        oneChapter: false,
      ),
      'Verses 18:36–19:2 and 19:9',
    );
    expect(
      coveredVersesLabel(at([(18, 13), (18, 14)]), oneChapter: false),
      'Verses 18:13–14',
    );
  });
}
