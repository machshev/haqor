import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/request_failure.dart';
import 'package:haqor/src/tutor/concept_reference.dart';
import 'package:haqor/src/tutor/study_flow.dart';

void _fail(String request, String message) =>
    assignRustSignal['RequestFailed']!(
      RequestFailed(
        request: request,
        key: '',
        message: message,
      ).bincodeSerialize(),
      Uint8List(0),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('stats sheet', () {
    Future<List<Object>> open(WidgetTester tester) async {
      final sent = <Object>[];
      await tester.pumpWidget(
        MaterialApp(home: StudyFlowPage(sendRequest: sent.add)),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.insights_outlined));
      await tester.pump(const Duration(milliseconds: 500));
      return sent;
    }

    testWidgets('stats that cannot be loaded show the error and retry', (
      tester,
    ) async {
      final sent = await open(tester);
      expect(sent.whereType<GetTutorStats>(), hasLength(1));

      _fail(requestTutorStats, 'database is locked');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('database is locked'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(sent.whereType<GetTutorStats>(), hasLength(2));
      expect(find.byType(RequestErrorView), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stats that never arrive stop spinning', (tester) async {
      await open(tester);
      await tester.pump(requestTimeout + const Duration(seconds: 1));
      expect(
        find.textContaining('Could not load your progress'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('concept reference', () {
    Future<List<GetSeenConcepts>> open(WidgetTester tester) async {
      final sent = <GetSeenConcepts>[];
      await tester.pumpWidget(
        MaterialApp(home: ConceptReferencePage(sendRequest: sent.add)),
      );
      return sent;
    }

    testWidgets('cards that cannot be loaded show the error and retry', (
      tester,
    ) async {
      final sent = await open(tester);
      expect(sent, hasLength(1));

      _fail(requestSeenConcepts, 'database is locked');
      await tester.pump();
      expect(find.textContaining('database is locked'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(sent, hasLength(2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cards that never arrive stop spinning', (tester) async {
      await open(tester);
      await tester.pump(requestTimeout + const Duration(seconds: 1));
      expect(find.byType(RequestErrorView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
