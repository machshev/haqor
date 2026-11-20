import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_service_worker.dart';

void main() {
  late Directory build;

  setUp(() {
    build = Directory.systemTemp.createTempSync('haqor-web-build-');
    File('${build.path}/index.html').writeAsStringSync('<html></html>');
    File('${build.path}/main.dart.js').writeAsStringSync('main();');
    File('${build.path}/flutter_service_worker.js').writeAsStringSync('old');
    Directory('${build.path}/pkg').createSync();
    File('${build.path}/pkg/hub.wasm').writeAsBytesSync([0, 97, 115, 109]);
  });

  tearDown(() => build.deleteSync(recursive: true));

  Map<String, dynamic> resources(String worker) => jsonDecode(
    RegExp(r'const RESOURCES = (.*);').firstMatch(worker)!.group(1)!,
  );

  test('lists every file but the worker, and the shell the build has', () {
    final worker = serviceWorker(
      build,
      r'const RESOURCES = $$RESOURCES_MAP;'
      '\n'
      r'const CORE = $$CORE_LIST;',
    );
    final listed = resources(worker);
    expect(listed.keys, ['/', 'index.html', 'main.dart.js', 'pkg/hub.wasm']);
    expect(listed['/'], listed['index.html']);
    expect(listed['index.html'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(worker, contains('const CORE = ["main.dart.js","index.html"];'));
  });

  test('the Haqor worker template fills in', () {
    final template = File('tool/web_service_worker.js').readAsStringSync();
    final worker = serviceWorker(build, template);
    expect(worker, isNot(contains(r'$$')));
    expect(resources(worker), contains('pkg/hub.wasm'));
  });

  test('a template missing a placeholder is refused', () {
    expect(
      () => serviceWorker(build, r'const CORE = $$CORE_LIST;'),
      throwsStateError,
    );
  });
}
