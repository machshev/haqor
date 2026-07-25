import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/app_info.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    // The About view shows appVersion, and nothing else reads the bundle
    // version at runtime, so this is what keeps the two honest after a
    // release bump.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    expect(declared, isNotNull, reason: 'pubspec.yaml has no version');
    expect(appVersion, declared);
  });

  test('every credited source states a licence', () {
    // Attribution is a licence condition for several of these sources; an
    // entry with an empty licence line is a credit that says nothing.
    expect(dataSourceCredits, isNotEmpty);
    for (final credit in dataSourceCredits) {
      expect(credit.title, isNotEmpty);
      expect(credit.description, isNotEmpty);
      expect(credit.licence, isNotEmpty);
    }
  });

  test('SEDRA credit carries the prescribed acknowledgement', () {
    // SEDRA's terms specify the wording; paraphrasing it would not satisfy
    // them, so assert the formula survives edits to the credits list.
    final sedra = dataSourceCredits.firstWhere((c) => c.title == 'SEDRA');
    expect(sedra.note, contains('Syriac Electronic Data Retrieval Archive'));
    expect(sedra.note, contains('George A. Kiraz'));
    expect(sedra.note, contains('Syriac Computing Institute'));
  });
}
