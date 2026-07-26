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
}
