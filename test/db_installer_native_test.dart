import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/db_installer_native.dart';

Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);

Future<Uint8List> _asset(String name) async => _bytes('corpus v2');

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('haqor_install'));
  tearDown(() => dir.deleteSync(recursive: true));

  File at(String name) => File('${dir.path}/$name');

  Future<void> install({bool reinstall = false, String version = 'v2'}) =>
      installDatabases(
        dir,
        reinstall: reinstall,
        bundled: version,
        loadAsset: _asset,
      );

  test('a fresh install writes the database and the marker', () async {
    await install();
    expect(at('haqor.db').readAsStringSync(), 'corpus v2');
    expect(at('.version').readAsStringSync(), startsWith('v2'));
  });

  test('a current, intact install is left alone', () async {
    await install();
    at('haqor.db').writeAsStringSync('corpus v3'); // same size, not rewritten
    await install();
    expect(at('haqor.db').readAsStringSync(), 'corpus v3');
  });

  test(
    'a missing database is reinstalled although the version matches',
    () async {
      await install();
      at('haqor.db').deleteSync();
      await install();
      expect(at('haqor.db').readAsStringSync(), 'corpus v2');
    },
  );

  test('a truncated database is reinstalled', () async {
    await install();
    at('haqor.db').writeAsStringSync('corp');
    await install();
    expect(at('haqor.db').readAsStringSync(), 'corpus v2');
  });

  test('a marker without sizes still accepts a non-empty database', () async {
    at('haqor.db').writeAsStringSync('old build');
    at('.version').writeAsStringSync('v2');
    await install();
    expect(at('haqor.db').readAsStringSync(), 'old build');
    at('haqor.db').writeAsStringSync('');
    await install();
    expect(at('haqor.db').readAsStringSync(), 'corpus v2');
  });

  test('a new version replaces the database', () async {
    at('haqor.db').writeAsStringSync('corpus v1');
    at('.version').writeAsStringSync('v1');
    await install();
    expect(at('haqor.db').readAsStringSync(), 'corpus v2');
  });
}
