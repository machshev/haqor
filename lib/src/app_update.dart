/// What the update check makes of a GitHub release: whether it is newer than
/// the running app, and which of its files this platform installs.
///
/// Pure data and rules, with no I/O, so they can be tested without a network;
/// the checking and installing live in `app_update_service.dart`.
library;

import 'app_info.dart';

/// Where releases are published. The API's `latest` skips drafts and
/// pre-releases, so a release is offered only once it is published.
const latestReleaseApiUrl =
    'https://api.github.com/repos/machshev/haqor/releases/latest';
const latestReleasePageUrl = '$appSourceUrl/releases/latest';

/// The platform builds the release workflow publishes, by the suffix each
/// file carries after `haqor-<version>-`.
enum UpdateTarget {
  androidArm64('android-arm64-v8a.apk'),
  androidArm('android-armeabi-v7a.apk'),
  androidX64('android-x86_64.apk'),
  androidUniversal('android.apk'),
  windowsX64('windows-x64.zip'),
  macos('macos-universal.dmg'),
  linuxX64('linux-x64.tar.gz'),
  ios('ios-unsigned.ipa');

  const UpdateTarget(this.suffix);

  final String suffix;
}

/// One downloadable file of a release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final Uri url;
  final int size;
}

/// A published release, as much of it as the update check uses.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.pageUrl,
    required this.notes,
    required this.assets,
  });

  /// The version without the tag's `v`, e.g. `0.9.21`.
  final String version;
  final Uri pageUrl;
  final String notes;
  final List<ReleaseAsset> assets;

  /// The GitHub API's release JSON, or null when it is not a usable release.
  static AppRelease? fromGitHubJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final page = json['html_url'];
    if (tag is! String || page is! String) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (parseVersion(version) == null) return null;
    final assets = <ReleaseAsset>[];
    for (final asset in (json['assets'] as List<Object?>?) ?? const []) {
      if (asset is! Map<String, Object?>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      final size = asset['size'];
      if (name is! String || url is! String) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') continue;
      assets.add(
        ReleaseAsset(name: name, url: uri, size: size is int ? size : 0),
      );
    }
    return AppRelease(
      version: version,
      pageUrl: Uri.parse(page),
      notes: (json['body'] as String?) ?? '',
      assets: assets,
    );
  }

  /// Whether this release is newer than [installed] (`pubspec.yaml`'s
  /// `version`, build number and all).
  bool isNewerThan(String installed) {
    final mine = parseVersion(installed);
    final theirs = parseVersion(version);
    if (mine == null || theirs == null) return false;
    return compareVersions(theirs, mine) > 0;
  }

  /// The file [target] installs from this release, if it was published.
  ReleaseAsset? assetFor(UpdateTarget target) {
    final name = 'haqor-$version-${target.suffix}';
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  /// The checksum list the release workflow publishes beside the files.
  ReleaseAsset? get checksums {
    for (final asset in assets) {
      if (asset.name == 'SHA256SUMS') return asset;
    }
    return null;
  }
}

/// `1.2.3`, `v1.2.3` or `1.2.3+45` as its three numbers; the build number
/// is ignored, since a release is named by its version alone. Null when it is
/// not that shape.
List<int>? parseVersion(String text) {
  var core = text.trim();
  if (core.startsWith('v')) core = core.substring(1);
  core = core.split('+').first;
  final parts = core.split('.');
  if (parts.length != 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    numbers.add(n);
  }
  return numbers;
}

int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// `sha256sum` output as file name → lowercase hex digest.
Map<String, String> parseSha256Sums(String text) {
  final sums = <String, String>{};
  final line = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$');
  for (final raw in text.split('\n')) {
    final match = line.firstMatch(raw.trimRight());
    if (match == null) continue;
    sums[match.group(2)!] = match.group(1)!.toLowerCase();
  }
  return sums;
}

/// The release's file [targets] names, taking the first that was published:
/// Android tries its own ABI's APK before the universal one.
ReleaseAsset? pickAsset(AppRelease release, List<UpdateTarget> targets) {
  for (final target in targets) {
    final asset = release.assetFor(target);
    if (asset != null) return asset;
  }
  return null;
}

/// `142924903` as `136 MB`.
String formatDownloadSize(int bytes) {
  if (bytes <= 0) return '';
  final mb = bytes / (1024 * 1024);
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}

/// How this build takes an update.
enum UpdateMethod {
  /// Haqor downloads the new build and installs it: through the system
  /// installer on Android, by replacing its own files and restarting on
  /// Windows and Linux.
  install,

  /// Haqor opens the new build's download in the browser, and the reader
  /// installs it as they did the first time (macOS's sandbox keeps the app
  /// from replacing itself; iOS builds are sideloaded).
  download,

  /// Updates come from somewhere else (the Nix package), or there is no build
  /// for this platform.
  none,
}

/// What this build can do about updates, decided once per run.
class UpdateSupport {
  const UpdateSupport(this.method, this.targets, {this.reason});

  final UpdateMethod method;

  /// The release files this build installs, most specific first.
  final List<UpdateTarget> targets;

  /// Why [method] is [UpdateMethod.none] or not [UpdateMethod.install].
  final String? reason;
}

/// An update that could not be installed, with a message for the reader.
class UpdateFailure implements Exception {
  const UpdateFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
