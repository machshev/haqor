import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/widgets/side_scroll.dart';

void main() {
  testWidgets('a mouse drags a row past its edge, and a bar shows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: SideScroll(
              child: Row(
                children: [
                  for (var i = 0; i < 20; i++)
                    SizedBox(width: 60, height: 40, child: Text('chip $i')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Scrollbar), findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.controller!.offset, 0);

    await tester.dragFrom(
      tester.getCenter(find.text('chip 1')),
      const Offset(-150, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, greaterThan(0));
  });
}
