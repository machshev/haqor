import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/bindings/bincode/bincode.dart';

void main() {
  test('signed i64 values use the Rust little-endian wire format on web', () {
    const fixtures = <int, List<int>>{
      0: [0, 0, 0, 0, 0, 0, 0, 0],
      -1: [255, 255, 255, 255, 255, 255, 255, 255],
      3600: [16, 14, 0, 0, 0, 0, 0, 0],
      -3600: [240, 241, 255, 255, 255, 255, 255, 255],
      4294967296: [0, 0, 0, 0, 1, 0, 0, 0],
      -4294967296: [0, 0, 0, 0, 255, 255, 255, 255],
      9007199254740991: [255, 255, 255, 255, 255, 255, 31, 0],
      -9007199254740991: [1, 0, 0, 0, 0, 0, 224, 255],
    };
    for (final entry in fixtures.entries) {
      final serializer = BincodeSerializer()..serializeInt64(entry.key);
      expect(serializer.bytes, entry.value, reason: '${entry.key}');
      final deserializer = BincodeDeserializer(Uint8List.fromList(entry.value));
      expect(deserializer.deserializeInt64(), entry.key);
      expect(deserializer.offset, 8);
    }
  });

  test('Memorise timezone requests serialize and decode on web', () {
    const request = GetMemoryStats(utcOffset: -3600);
    expect(request.bincodeSerialize(), [
      240,
      241,
      255,
      255,
      255,
      255,
      255,
      255,
    ]);
    expect(
      GetMemoryStats.bincodeDeserialize(request.bincodeSerialize()),
      request,
    );
  });

  test('tutor progress replies decode Rust i64 counters on web', () {
    final bytes = Uint8List.fromList([
      // Ten little-endian i64 counters from TutorProgress in Rust field order.
      1, 0, 0, 0, 0, 0, 0, 0,
      22, 0, 0, 0, 0, 0, 0, 0,
      2, 0, 0, 0, 0, 0, 0, 0,
      12, 0, 0, 0, 0, 0, 0, 0,
      3, 0, 0, 0, 0, 0, 0, 0,
      20, 0, 0, 0, 0, 0, 0, 0,
      4, 0, 0, 0, 0, 0, 0, 0,
      5, 0, 0, 0, 0, 0, 0, 0,
      6, 0, 0, 0, 0, 0, 0, 0,
      232, 3, 0, 0, 0, 0, 0, 0,
    ]);
    final progress = TutorProgress.bincodeDeserialize(bytes);
    expect(progress.lettersKnown, 1);
    expect(progress.lettersTotal, 22);
    expect(progress.wordsKnown, 4);
    expect(progress.versesReadable, 6);
    expect(progress.totalVerses, 1000);
    expect(progress.bincodeSerialize(), bytes);
  });
}
