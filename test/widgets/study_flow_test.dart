import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/request_failure.dart';
import 'package:haqor/src/tutor/study_flow.dart';

void _fail(String request, String message) {
  assignRustSignal['RequestFailed']!(
    RequestFailed(
      request: request,
      key: '',
      message: message,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<Object>> pump(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(home: StudyFlowPage(sendRequest: sent.add)),
    );
    await tester.pump();
    return sent;
  }

  testWidgets('a failed first card shows the error and retries the request', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(sent.single, isA<GetNextStudyItem>());
    expect(find.byType(RequestErrorView), findsNothing);

    _fail(requestNextStudyItem, 'database is locked');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsOneWidget);
    expect(find.textContaining('database is locked'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent, hasLength(2));
    expect(sent.last, isA<GetNextStudyItem>());
    expect(find.byType(RequestErrorView), findsNothing);
  });

  testWidgets('a card that never comes ends in the error state', (
    tester,
  ) async {
    final sent = await pump(tester);

    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent, hasLength(2));

    // Leave no timer pending.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failure for another request is ignored', (tester) async {
    await pump(tester);
    _fail(requestMemoryStats, 'not ours');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
