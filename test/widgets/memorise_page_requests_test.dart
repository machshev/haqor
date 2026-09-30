import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/memorise/memorise_page.dart';
import 'package:haqor/src/request_failure.dart';

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

  Future<List<Object>> pump(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(home: MemorisePage(sendRequest: sent.add)),
    );
    await tester.pump();
    return sent;
  }

  testWidgets('passages that cannot be loaded show the error and retry', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(sent.whereType<GetMemoryPassages>(), hasLength(1));

    _fail(requestMemoryPassages, 'database is locked');
    await tester.pump();
    expect(find.textContaining('database is locked'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<GetMemoryPassages>(), hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('passages that never arrive stop spinning', (tester) async {
    await pump(tester);
    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed change to the list is reported, not dropped', (
    tester,
  ) async {
    await pump(tester);
    assignRustSignal['MemoryPassages']!(
      const MemoryPassages(passages: [], savedId: '').bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();

    _fail(requestMemoryPassages, 'database is locked');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);
    expect(
      find.textContaining('Could not update your passages'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
