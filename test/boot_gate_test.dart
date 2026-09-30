import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/boot_failure.dart';

Widget _app(BootGate gate) => MaterialApp(home: gate);

void main() {
  test('a failed boot report becomes a BootFailure with its reason', () {
    expect(
      () => bootNotice(
        BootStatus(failed: true, progressReset: false, message: 'not a db'),
      ),
      throwsA(
        isA<BootFailure>().having((f) => f.message, 'message', 'not a db'),
      ),
    );
  });

  test('a reset of progress is passed on as a notice, a clean boot is not', () {
    expect(
      bootNotice(
        BootStatus(failed: false, progressReset: true, message: 'reset'),
      ),
      'reset',
    );
    expect(
      bootNotice(BootStatus(failed: false, progressReset: false, message: '')),
      isNull,
    );
  });

  testWidgets('a failed boot shows the reason and Try again opens the app', (
    tester,
  ) async {
    var ready = 0;
    await tester.pumpWidget(
      _app(
        BootGate(
          start: () async => null,
          onReady: () => ready++,
          initialFailure: 'disk is full',
          child: const Text('reader'),
        ),
      ),
    );
    expect(find.text('disk is full'), findsOneWidget);
    expect(find.text('reader'), findsNothing);
    expect(find.text('Reinstall the databases'), findsNothing);
    expect(ready, 0);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('reader'), findsOneWidget);
    expect(ready, 1);
  });

  testWidgets('a retry that fails again shows the new reason', (tester) async {
    await tester.pumpWidget(
      _app(
        BootGate(
          start: () async => throw const BootFailure('still broken'),
          initialFailure: 'first',
          child: const Text('reader'),
        ),
      ),
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('still broken'), findsOneWidget);
    expect(find.text('reader'), findsNothing);
  });

  testWidgets('reinstall is offered when given and runs its own open', (
    tester,
  ) async {
    var reinstalled = false;
    await tester.pumpWidget(
      _app(
        BootGate(
          start: () async => throw const BootFailure('again'),
          reinstall: () async {
            reinstalled = true;
            return null;
          },
          initialFailure: 'damaged',
          child: const Text('reader'),
        ),
      ),
    );
    await tester.tap(find.text('Reinstall the databases'));
    await tester.pumpAndSettle();
    expect(reinstalled, isTrue);
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('a notice about reset progress is shown once the app opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        BootGate(
          start: () async => null,
          initialNotice: 'started with fresh progress',
          child: const Scaffold(body: Text('reader')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('started with fresh progress'), findsOneWidget);
  });
}
