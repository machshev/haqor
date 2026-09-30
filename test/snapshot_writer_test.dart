import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/snapshot_writer.dart';

Uint8List _bytes(int n) => Uint8List.fromList([n]);

void main() {
  testWidgets('a burst of snapshots is written once, newest last', (
    tester,
  ) async {
    final written = <int>[];
    final writer = SnapshotWriter(
      write: (b) async => written.add(b.single),
      onFailure: (_) {},
      delay: const Duration(seconds: 3),
    );
    for (var i = 1; i <= 5; i++) {
      writer.schedule(_bytes(i));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(written, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    expect(written, [5]);
    await tester.pump(const Duration(seconds: 10));
    expect(written, [5], reason: 'nothing more to write');
  });

  testWidgets('flush writes at once and leaves no timer behind', (
    tester,
  ) async {
    final written = <int>[];
    final writer = SnapshotWriter(
      write: (b) async => written.add(b.single),
      onFailure: (_) {},
    );
    writer.schedule(_bytes(7));
    await writer.flush();
    expect(written, [7]);
  });

  testWidgets('a failed write is reported once and retried by the next flush', (
    tester,
  ) async {
    var failing = true;
    final written = <int>[];
    final failures = <Object>[];
    final writer = SnapshotWriter(
      write: (b) async {
        if (failing) throw StateError('quota');
        written.add(b.single);
      },
      onFailure: failures.add,
    );
    writer.schedule(_bytes(1));
    await writer.flush();
    writer.schedule(_bytes(2));
    await writer.flush();
    expect(failures, hasLength(1));
    failing = false;
    await writer.flush();
    expect(written, [2]);
    // A later failure is news again.
    failing = true;
    writer.schedule(_bytes(3));
    await writer.flush();
    expect(failures, hasLength(2));
  });
}
