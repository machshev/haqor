import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Write Haqor's offline service worker (tool/web_service_worker.js) into a
/// web build as `flutter_service_worker.js`, the name the bootstrap in
/// web/index.html registers and installed copies already run under.
///
/// Flutter 3.41 stopped generating an offline worker, so this does what its
/// generator did: list every file of the build with a hash of its contents, so
/// an upgrade keeps unchanged files cached, and name the app shell to download
/// before the worker starts.
void main(List<String> args) {
  final root = args.isEmpty
      ? Directory.fromUri(Platform.script.resolve('../build/web/'))
      : Directory(args.single);
  final template = File.fromUri(
    Platform.script.resolve('web_service_worker.js'),
  ).readAsStringSync();
  File(
    '${root.path}/flutter_service_worker.js',
  ).writeAsStringSync(serviceWorker(root, template));
}

const worker = 'flutter_service_worker.js';

/// The application shell, as Flutter's generator listed it, where the build
/// has each file.
const core = [
  'main.dart.js',
  'main.dart.wasm',
  'main.dart.mjs',
  'index.html',
  'flutter_bootstrap.js',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
];

String serviceWorker(Directory root, String template) {
  final rootPath = root.absolute.uri.path;
  final resources = <String, String>{};
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    final key = file.absolute.uri.path.substring(rootPath.length);
    if (key == worker) continue;
    resources[key] = md5.convert(file.readAsBytesSync()).toString();
  }
  final index = resources['index.html'];
  if (index == null) {
    throw StateError('No index.html in ${root.path}: is it a web build?');
  }
  resources['/'] = index;
  final sorted = {
    for (final key in resources.keys.toList()..sort()) key: resources[key],
  };
  final shell = [
    for (final file in core)
      if (resources.containsKey(file)) file,
  ];

  String fill(String text, String placeholder, Object value) {
    if (placeholder.allMatches(text).length != 1) {
      throw StateError('$placeholder must appear once in the worker template');
    }
    return text.replaceFirst(placeholder, jsonEncode(value));
  }

  return fill(
    fill(template, r'$$RESOURCES_MAP', sorted),
    r'$$CORE_LIST',
    shell,
  );
}
