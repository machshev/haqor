import 'dart:typed_data';

import 'boot_failure.dart';

/// Read the stored progress snapshot. A read that fails is not an empty store:
/// starting fresh would let the next save overwrite the snapshot that could
/// not be read, so it stops the boot instead, with the stored copy untouched.
Future<Uint8List?> readStoredProgress(
  Future<Uint8List?> Function() read,
) async {
  try {
    return await read();
  } catch (error) {
    throw BootFailure(
      'Haqor could not read your saved progress from this browser, so it has '
      'not started, to keep that progress safe. ($error)',
    );
  }
}
