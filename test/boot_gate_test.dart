import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/boot_failure.dart';
import 'package:haqor/src/db_installer_native.dart';

Widget _app(BootGate gate) => MaterialApp(home: gate);

void main() {
  test('a failed boot report becomes a BootFailure with its reason', () {
    expect(
      () => bootNotice(
        BootStatus(
          failed: true,
          progressReset: false,
          progressUnreadable: false,
          message: 'not a db',
        ),
      ),
      throwsA(
        isA<BootFailure>().having((f) => f.message, 'message', 'not a db'),
      ),
    );
  });

  test('a reset of progress is passed on as a notice, a clean boot is not', () {
    expect(
      bootNotice(
        BootStatus(
          failed: false,
          progressReset: true,
          progressUnreadable: false,
          message: 'reset',
        ),
      ),
      'reset',
    );
    expect(
      bootNotice(
        BootStatus(
          failed: false,
          progressReset: false,
          progressUnreadable: false,
          message: '',
        ),
      ),
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
          initialFailure: const BootFailure('disk is full'),
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
          initialFailure: const BootFailure('first'),
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
          initialFailure: const BootFailure('damaged'),
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

  testWidgets('fresh progress is offered only when the progress file failed', (
    tester,
  ) async {
    Future<void> show(BootFailure failure) => tester.pumpWidget(
      _app(
        BootGate(
          key: UniqueKey(),
          start: () async => null,
          resetProgress: () async => null,
          initialFailure: failure,
          child: const Text('reader'),
        ),
      ),
    );
    await show(const BootFailure('bad databases'));
    expect(find.text('Start with fresh progress'), findsNothing);
    await show(const BootFailure('bad progress', progressUnreadable: true));
    expect(find.text('Start with fresh progress'), findsOneWidget);
  });

  testWidgets('fresh progress asks first, then sets aside and retries', (
    tester,
  ) async {
    var resets = 0;
    await tester.pumpWidget(
      _app(
        BootGate(
          start: () async => null,
          resetProgress: () async {
            resets++;
            return 'old file kept as progress.db.unreadable-1';
          },
          initialFailure: const BootFailure(
            'bad progress',
            progressUnreadable: true,
          ),
          child: const Scaffold(body: Text('reader')),
        ),
      ),
    );
    await tester.tap(find.text('Start with fresh progress'));
    await tester.pumpAndSettle();
    expect(find.textContaining('set it aside, not delete it'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, 0);

    await tester.tap(find.text('Start with fresh progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start fresh'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(find.text('reader'), findsOneWidget);
    expect(find.textContaining('old file kept as'), findsOneWidget);
  });

  test('setAsideProgress renames the database and its sidecars', () async {
    final dir = Directory.systemTemp.createTempSync('haqor_progress');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/progress.db').writeAsStringSync('db');
    File('${dir.path}/progress.db-wal').writeAsStringSync('wal');
    File('${dir.path}/haqor.db').writeAsStringSync('corpus');

    final backup = await setAsideProgress(dir, DateTime.utc(2026, 9, 30, 8, 5));

    expect(backup, '${dir.path}/progress.db.unreadable-20260930T080500000Z');
    expect(File('${dir.path}/progress.db').existsSync(), isFalse);
    expect(File(backup).readAsStringSync(), 'db');
    expect(File('$backup-wal').readAsStringSync(), 'wal');
    expect(File('${dir.path}/haqor.db').existsSync(), isTrue);
  });
}
