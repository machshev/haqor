import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/memorise/memorise_shape.dart';
import 'package:haqor/src/request_failure.dart';

void _fail(String key, String message) => assignRustSignal['RequestFailed']!(
  RequestFailed(
    request: requestMemoryLayout,
    key: key,
    message: message,
  ).bincodeSerialize(),
  Uint8List(0),
);

void main() {
  Future<List<Object>> pump(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryShapePage(
          passageId: 'p',
          title: 'Psalm 23',
          sendRequest: sent.add,
        ),
      ),
    );
    return sent;
  }

  testWidgets('a layout that cannot be loaded shows the error and retries', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(sent.single, isA<GetMemoryLayout>());

    _fail('other', 'not ours');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);

    _fail('p', 'database is locked');
    await tester.pump();
    expect(find.textContaining('database is locked'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<GetMemoryLayout>(), hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a layout that never arrives stops spinning', (tester) async {
    await pump(tester);
    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
