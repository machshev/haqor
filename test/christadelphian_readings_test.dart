import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/christadelphian_readings.dart';

void main() {
  test('returns the July 26 Bible Companion readings', () {
    final readings = christadelphianReadingsFor(DateTime(2026, 7, 26));

    expect(readings.map((reading) => reading.reference), [
      '2 Samuel 12',
      'Jeremiah 16',
      'Matthew 27',
    ]);
  });

  test('keeps the fixed schedule aligned after leap day', () {
    expect(
      christadelphianReadingsFor(
        DateTime(2028, 2, 29),
      ).map((reading) => reading.reference),
      christadelphianReadingsFor(
        DateTime(2028, 2, 28),
      ).map((reading) => reading.reference),
    );
    expect(
      christadelphianReadingsFor(DateTime(2028, 7, 26)).first.reference,
      '2 Samuel 12',
    );
  });

  test('reads every chapter of Genesis exactly once', () {
    final chapters = <int>[];
    for (var day = 0; day < 365; day++) {
      final date = DateTime.utc(2027, 1, 1).add(Duration(days: day));
      for (final reading in christadelphianReadingsFor(date)) {
        if (reading.bookIndex != 0) continue;
        final listed = reading.reference.substring('Genesis '.length);
        for (final part in listed.split(',')) {
          final bounds = part.split('-').map((n) => int.parse(n.trim()));
          chapters.addAll([
            for (var c = bounds.first; c <= bounds.last; c++) c,
          ]);
        }
      }
    }
    expect(chapters, [for (var c = 1; c <= 50; c++) c]);
  });
}
