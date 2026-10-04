import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/patch_bindings.dart';

const serializer = '''void serializeInt64(int value) {
    final bdata = ByteData(8)..setInt64(0, value, Endian.little);
    output.addAll(bdata.buffer.asUint8List());
}''';
const deserializer = '''int deserializeInt64() {
    final result = input.getInt64(_offset, Endian.little);
    _offset += 8;
    return result;
}''';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('haqor-bindings-test-');
    File(
      '${directory.path}/binary_serializer.dart',
    ).writeAsStringSync(serializer);
    File(
      '${directory.path}/binary_deserializer.dart',
    ).writeAsStringSync(deserializer);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('patch survives repeated generation and is idempotent', () {
    patchBindings(directory);
    final file = File('${directory.path}/binary_serializer.dart');
    final patched = file.readAsStringSync();
    expect(
      patched,
      contains('serializeUint64(Uint64(BigInt.from(value).toUnsigned(64)))'),
    );
    patchBindings(directory);
    expect(file.readAsStringSync(), patched);
    file.writeAsStringSync(serializer);
    patchBindings(directory);
    expect(file.readAsStringSync(), patched);
  });

  test('template drift fails before either codec is written', () {
    File(
      '${directory.path}/binary_deserializer.dart',
    ).writeAsStringSync('changed template');
    expect(() => patchBindings(directory), throwsStateError);
    expect(
      File('${directory.path}/binary_serializer.dart').readAsStringSync(),
      serializer,
    );
  });
}
