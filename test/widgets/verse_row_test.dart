import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/widgets/verse_row.dart';

void main() {
  test('standalone paseq does not consume an interlinear gloss', () {
    final words = 'וַיִּקְרָא אֱלֹהִים ׀ לָאוֹר יּוֹם'.split(' ');

    expect(verseGlossPositions(words), [0, 1, null, 2, 3]);
  });
}
