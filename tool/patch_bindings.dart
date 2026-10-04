import 'dart:io';

/// Keep Rinf's wire format while using the bytewise BigInt codec on web.
/// Generated bindings are ignored by Git, so apply this after every generation.
void main(List<String> args) {
  final directory = args.isEmpty
      ? Directory.fromUri(Platform.script.resolve('../lib/src/bindings/serde/'))
      : Directory(args.single);
  patchBindings(directory);
}

void patchBindings(Directory directory) {
  const replacements = {
    'binary_serializer.dart': (
      '''    final bdata = ByteData(8)..setInt64(0, value, Endian.little);
    output.addAll(bdata.buffer.asUint8List());''',
      '''    // ByteData's signed 64-bit accessors are unsupported by dart2js.
    serializeUint64(Uint64(BigInt.from(value).toUnsigned(64)));''',
    ),
    'binary_deserializer.dart': (
      '''    final result = input.getInt64(_offset, Endian.little);
    _offset += 8;
    return result;''',
      '''    // Read the same little-endian two's-complement bytes on every target.
    final result = _bytesToBigInt(8, signed: true);
    _offset += 8;
    return result.toInt();''',
    ),
  };
  final updates = <File, String>{};
  // Validate both templates before writing either file. Fail clearly on drift.
  for (final entry in replacements.entries) {
    final file = File('${directory.path}/${entry.key}');
    final source = file.readAsStringSync().replaceAll('\r\n', '\n');
    final (original, patched) = entry.value;
    if (source.contains(patched)) continue;
    if (original.allMatches(source).length != 1) {
      throw StateError(
        'Unexpected Rinf i64 codec in ${file.path}; '
        'review the generated template before updating the patch.',
      );
    }
    updates[file] = source.replaceFirst(original, patched);
  }
  for (final entry in updates.entries) {
    entry.key.writeAsStringSync(entry.value);
  }
}
