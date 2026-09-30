@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Runs a copy of tool/sync-dbs.sh against a fixture tree, so the real
// assets/db and the local install marker are never touched.
Future<({Directory root, ProcessResult result})> _run({
  required String cmake,
  List<String> args = const [],
}) async {
  final root = await Directory.systemTemp.createTemp('sync_dbs_');
  addTearDown(() => root.delete(recursive: true));
  Directory('${root.path}/haqor/tool').createSync(recursive: true);
  Directory('${root.path}/haqor/linux').createSync();
  Directory('${root.path}/haqor-core/data').createSync(recursive: true);
  File('tool/sync-dbs.sh').copySync('${root.path}/haqor/tool/sync-dbs.sh');
  File('${root.path}/haqor/linux/CMakeLists.txt').writeAsStringSync(cmake);
  final made = await Process.run('sqlite3', [
    '${root.path}/haqor-core/data/haqor.db',
    "CREATE TABLE meta (key TEXT, value TEXT);"
        "INSERT INTO meta VALUES ('built', '2026-01-02T03:04:05Z');",
  ]);
  expect(made.exitCode, 0, reason: '${made.stderr}');
  final result = await Process.run(
    'bash',
    ['${root.path}/haqor/tool/sync-dbs.sh', ...args],
    environment: {'HOME': root.path, 'XDG_DATA_HOME': '${root.path}/share'},
  );
  return (root: root, result: result);
}

void main() {
  test(
    'reads the application id without GNU grep and writes the version',
    () async {
      final run = await _run(
        cmake: 'project(x)\nset(APPLICATION_ID "org.example.app")\n',
      );
      expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
      expect(
        File('${run.root.path}/haqor/assets/db/version.txt').readAsStringSync(),
        '2026-01-02T03:04:05Z\n',
      );
      expect(
        run.result.stdout,
        contains('${run.root.path}/share/org.example.app/db/.version'),
      );
    },
  );

  test(
    'leaves version.txt unwritten when the application id is missing',
    () async {
      final run = await _run(cmake: 'project(x)\n');
      expect(run.result.exitCode, isNot(0));
      expect(
        File('${run.root.path}/haqor/assets/db/version.txt').existsSync(),
        isFalse,
      );
    },
  );

  test('--keep needs no application id', () async {
    final run = await _run(cmake: 'project(x)\n', args: ['--keep']);
    expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
    expect(
      File('${run.root.path}/haqor/assets/db/version.txt').existsSync(),
      isTrue,
    );
  });
}
