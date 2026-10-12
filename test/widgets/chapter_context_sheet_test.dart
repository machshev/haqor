import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/archaeology_page.dart';
import 'package:haqor/src/widgets/chapter_context_sheet.dart';
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
}
