import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/request_failure.dart';

void main() {
  group('firstWithin', () {
    test(
      'completes with the first matching event and stops listening',
      () async {
        final controller = StreamController<int>.broadcast();
        addTearDown(controller.close);

        final result = firstWithin(
          controller.stream,
          (n) => n > 1,
          requestTimeout,
        );
        expect(controller.hasListener, isTrue);
        controller
          ..add(1)
          ..add(2);

        expect(await result, 2);
        expect(controller.hasListener, isFalse);
      },
    );

    test('stops listening when it times out', () async {
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);

      final result = firstWithin(
        controller.stream,
        (n) => n > 1,
        const Duration(milliseconds: 10),
      );
      await expectLater(result, throwsA(isA<TimeoutException>()));

      // A timed-out wait must not go on listening for a reply nobody wants.
      expect(controller.hasListener, isFalse);
    });
  });
}
