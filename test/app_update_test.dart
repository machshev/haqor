import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/app_update.dart';

Map<String, Object?> _release({
  String tag = 'v0.9.21',
  bool prerelease = false,
  List<String> files = const [
    'haqor-0.9.21-android-arm64-v8a.apk',
    'haqor-0.9.21-android.apk',
    'haqor-0.9.21-linux-x64.tar.gz',
    'SHA256SUMS',
  ],
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/machshev/haqor/releases/tag/$tag',
  'draft': false,
  'prerelease': prerelease,
  'body': 'notes',
  'assets': [
    for (final name in files)
      {
        'name': name,
        'size': 1234,
        'browser_download_url':
            'https://github.com/machshev/haqor/releases/download/$tag/$name',
      },
  ],
};

void main() {
  test('versions compare by number, ignoring the build number', () {
    expect(parseVersion('0.9.20+42'), [0, 9, 20]);
    expect(parseVersion('v1.10.0'), [1, 10, 0]);
    expect(parseVersion('1.2'), isNull);
    expect(parseVersion('1.2.x'), isNull);
    expect(compareVersions([0, 10, 0], [0, 9, 20]), greaterThan(0));
  });

  test('a release is offered only when newer and published', () {
    final release = AppRelease.fromGitHubJson(_release())!;
    expect(release.version, '0.9.21');
    expect(release.isNewerThan('0.9.20+42'), isTrue);
    expect(release.isNewerThan('0.9.21+43'), isFalse);
    expect(release.isNewerThan('0.10.0+50'), isFalse);
    expect(AppRelease.fromGitHubJson(_release(prerelease: true)), isNull);
    expect(AppRelease.fromGitHubJson(_release(tag: 'nightly')), isNull);
    expect(AppRelease.fromGitHubJson('nope'), isNull);
  });

  test('Android prefers its own ABI and falls back to the universal APK', () {
    final release = AppRelease.fromGitHubJson(_release())!;
    expect(
      pickAsset(release, [
        UpdateTarget.androidArm64,
        UpdateTarget.androidUniversal,
      ])?.name,
      'haqor-0.9.21-android-arm64-v8a.apk',
    );
    expect(
      pickAsset(release, [
        UpdateTarget.androidArm,
        UpdateTarget.androidUniversal,
      ])?.name,
      'haqor-0.9.21-android.apk',
    );
    expect(pickAsset(release, [UpdateTarget.windowsX64]), isNull);
    expect(release.checksums?.name, 'SHA256SUMS');
  });

  test('non-HTTPS asset links are ignored', () {
    final json = _release();
    (json['assets'] as List).add({
      'name': 'haqor-0.9.21-windows-x64.zip',
      'browser_download_url': 'http://example.com/haqor.zip',
    });
    final release = AppRelease.fromGitHubJson(json)!;
    expect(release.assetFor(UpdateTarget.windowsX64), isNull);
  });

  test('SHA256SUMS lines map file names to digests', () {
    final a = 'A' * 64;
    final b = 'b' * 64;
    final sums = parseSha256Sums(
      '$a  haqor-0.9.21-android.apk\n$b *haqor-0.9.21-linux-x64.tar.gz\n'
      'garbage\n',
    );
    expect(sums, {
      'haqor-0.9.21-android.apk': 'a' * 64,
      'haqor-0.9.21-linux-x64.tar.gz': b,
    });
  });

  test('download sizes read in megabytes', () {
    expect(formatDownloadSize(142924903), '136 MB');
    expect(formatDownloadSize(3 * 1024 * 1024 + 1), '3.0 MB');
    expect(formatDownloadSize(0), '');
  });
}
