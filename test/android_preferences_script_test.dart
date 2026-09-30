@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _script = 'scripts/sync-flutter-preferences-to-android.sh';
const _doublePrefix = 'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu';

void main() {
  test(
    'the Android sync stores doubles as doubles and ints as longs',
    () async {
      final dir = Directory.systemTemp.createTempSync('android-prefs-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/shared_preferences.json')
        ..writeAsStringSync(
          jsonEncode({
            'flutter.cross_reference_min_score': 0.0,
            'flutter.font_size': 20.0,
            'flutter.reader_side_panel_width': 360.0,
            'flutter.reader_tiled_panel_width': 412.5,
            'flutter.book': 3,
            'flutter.tutor_admin_mode': true,
          }),
        );

      final result = await Process.run('bash', [
        _script,
        '--render',
        '--source',
        source.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final xml = result.stdout as String;
      for (final key in [
        'cross_reference_min_score',
        'font_size',
        'reader_side_panel_width',
        'reader_tiled_panel_width',
      ]) {
        expect(xml, contains('<string name="flutter.$key">$_doublePrefix'));
      }
      expect(xml, contains('<long name="flutter.book" value="3" />'));
      expect(xml, isNot(contains('<long name="flutter.cross_reference')));
    },
  );
}
