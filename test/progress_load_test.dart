import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/boot_failure.dart';
import 'package:haqor/src/progress_load.dart';

void main() {
  test('a stored snapshot, or none, is passed through', () async {
    final bytes = Uint8List.fromList([1, 2]);
    expect(await readStoredProgress(() async => bytes), bytes);
    expect(await readStoredProgress(() async => null), isNull);
  });

  test('a failed read stops the boot rather than reading as empty', () {
    expect(
      readStoredProgress(() async => throw 'NotReadableError'),
      throwsA(
        isA<BootFailure>().having(
          (f) => f.message,
          'message',
          contains('NotReadableError'),
        ),
      ),
    );
  });
}
