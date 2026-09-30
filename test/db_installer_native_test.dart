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

  Future<void> install({
    bool reinstall = false,
    String version = 'v2',
    Future<File> Function(File, String)? rename,
  }) => installDatabases(
    dir,
    reinstall: reinstall,
    bundled: version,
    loadAsset: _asset,
    rename: rename ?? (from, to) => from.rename(to),
  );

  test('a fresh install writes the database and the marker', () async {
    await install();
    expect(at('haqor.db').readAsStringSync(), 'corpus v2');
    expect(at('.version').readAsStringSync(), startsWith('v2'));
    expect(at('haqor.db.installing').existsSync(), isFalse);
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

  test(
    'obsolete files go; progress, backups and sync temp files stay',
    () async {
      for (final name in [
        'bible.db',
        'sedra.db',
        'hebrew.db',
        'lexicon.db',
        'stray.txt',
      ]) {
        at(name).writeAsStringSync('old');
      }
      final kept = [
        'progress.db',
        'progress.db-wal',
        'progress.db-shm',
        'progress.db-journal',
        'progress.db.unreadable-20260930T080500000Z',
        'progress.db.unreadable-20260930T080500000Z-wal',
        '.progress-sync-upload.db',
        '.progress-sync-download.db',
      ];
      for (final name in kept) {
        at(name).writeAsStringSync('keep');
      }
      await install();

      for (final name in [
        'bible.db',
        'sedra.db',
        'hebrew.db',
        'lexicon.db',
        'stray.txt',
      ]) {
        expect(at(name).existsSync(), isFalse, reason: name);
      }
      for (final name in [...kept, 'haqor.db', '.version']) {
        expect(at(name).existsSync(), isTrue, reason: name);
      }
    },
  );

  Future<File> blocked(File from, String to) =>
      throw const FileSystemException('in use');

  test(
    'a database that cannot be replaced is kept and the update retried',
    () async {
      at('haqor.db').writeAsStringSync('corpus v1');
      at('.version').writeAsStringSync('v1');
      await install(rename: blocked);
      expect(at('haqor.db').readAsStringSync(), 'corpus v1');
      expect(at('haqor.db.installing').existsSync(), isFalse);
      expect(at('.version').readAsStringSync(), 'v1');
    },
  );

  test(
    'a requested reinstall that cannot replace the database throws',
    () async {
      at('haqor.db').writeAsStringSync('corpus v1');
      await expectLater(
        install(reinstall: true, rename: blocked),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('a first install that cannot write the database throws', () async {
    await expectLater(
      install(rename: blocked),
      throwsA(isA<FileSystemException>()),
    );
  });
}
