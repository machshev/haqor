import 'package:shared_preferences/shared_preferences.dart';

/// Reads that give `null` for a stored value of the wrong type.
///
/// The typed getters throw on a mismatch, and a preference file edited by
/// hand or copied from another platform can hold one: the Android sync script
/// used to store whole doubles as longs. One bad value then aborted the whole
/// load instead of falling back to its default.
extension TolerantPreferences on SharedPreferences {
  bool? readBool(String key) {
    final value = get(key);
    return value is bool ? value : null;
  }

  /// An int where a double was saved is still a number, so it is accepted.
  double? readDouble(String key) {
    final value = get(key);
    return value is num ? value.toDouble() : null;
  }

  int? readInt(String key) {
    final value = get(key);
    if (value is int) return value;
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  String? readString(String key) {
    final value = get(key);
    return value is String ? value : null;
  }

  List<String>? readStringList(String key) {
    final value = get(key);
    return value is List ? value.whereType<String>().toList() : null;
  }
}
