import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_info.dart';
import 'app_update.dart';
import 'external_link.dart';

/// Whether there is any update check on this build at all.
bool get appUpdateSupported => _targets().isNotEmpty && !_installedByNix;

const _channel = MethodChannel('org.haqor/update');

/// A Linux build run from the Nix store is the Nix package, whose updates come
/// with the flake.
bool get _installedByNix =>
    Platform.isLinux && Platform.resolvedExecutable.startsWith('/nix/store/');

List<UpdateTarget> _targets() {
  final abi = Abi.current();
  if (Platform.isAndroid) {
    // The running ABI rather than the device's best one: a 32-bit install
    // stays 32-bit, and its version codes keep counting up.
    return [
      if (abi == Abi.androidArm64) UpdateTarget.androidArm64,
      if (abi == Abi.androidArm) UpdateTarget.androidArm,
      if (abi == Abi.androidX64) UpdateTarget.androidX64,
      UpdateTarget.androidUniversal,
    ];
  }
  if (Platform.isWindows && abi == Abi.windowsX64) {
    return [UpdateTarget.windowsX64];
  }
  if (Platform.isLinux && abi == Abi.linuxX64) return [UpdateTarget.linuxX64];
  if (Platform.isMacOS) return [UpdateTarget.macos];
  if (Platform.isIOS) return [UpdateTarget.ios];
  return const [];
}

Future<UpdateSupport> updateSupport() async {
  final targets = _targets();
  if (targets.isEmpty || _installedByNix) {
    return UpdateSupport(
      UpdateMethod.none,
      targets,
      reason: _installedByNix
          ? 'This is the Nix package: update it with your flake.'
          : 'There is no Haqor release build for this device.',
    );
  }
  if (Platform.isAndroid) return UpdateSupport(UpdateMethod.install, targets);
  if (Platform.isWindows || Platform.isLinux) {
    if (await _canWrite(_installDir)) {
      return UpdateSupport(UpdateMethod.install, targets);
    }
    return UpdateSupport(
      UpdateMethod.download,
      targets,
      reason:
          'Haqor cannot write to its folder (${_installDir.path}), so it '
          'will open the download instead.',
    );
  }
  return UpdateSupport(UpdateMethod.download, targets);
}

Directory get _installDir => File(Platform.resolvedExecutable).parent;

Future<bool> _canWrite(Directory dir) async {
  final probe = File('${dir.path}${Platform.pathSeparator}.haqor-update-probe');
  try {
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

HttpClient _client() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 20)
  ..userAgent = 'Haqor/$appVersion';

/// The latest published release. Throws when GitHub cannot be reached or
/// answers with something else.
Future<AppRelease> fetchLatestRelease() async {
  final client = _client();
  try {
    final request = await client.getUrl(Uri.parse(latestReleaseApiUrl));
    request.headers.set('Accept', 'application/vnd.github+json');
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('GitHub answered ${response.statusCode}');
    }
    final release = AppRelease.fromGitHubJson(jsonDecode(body));
    if (release == null) {
      throw const FormatException('GitHub sent an unreadable release');
    }
    return release;
  } finally {
    client.close(force: true);
  }
}

/// Whether Android lets Haqor hand an APK to the installer. Always true
/// elsewhere.
Future<bool> canInstallUpdates() async {
  if (!Platform.isAndroid) return true;
  return await _channel.invokeMethod<bool>('canInstall') ?? false;
}

/// Android's "install unknown apps" page for Haqor.
Future<void> openInstallPermissionSettings() =>
    _channel.invokeMethod<void>('openInstallSettings');

/// Take [release]'s [asset] as [support] says. [onProgress] hears the bytes
/// downloaded so far and the total (0 when unknown).
///
/// On Android this returns once the system installer is showing; on Windows
/// and Linux, once the files are ready, it closes Haqor, which a helper
/// restarts after replacing them, so it never returns.
Future<void> takeUpdate(
  UpdateSupport support,
  AppRelease release,
  ReleaseAsset asset, {
  void Function(int received, int total)? onProgress,
}) async {
  if (support.method == UpdateMethod.download) {
    await openExternalLink(Platform.isIOS ? release.pageUrl : asset.url);
    return;
  }
  if (support.method != UpdateMethod.install) {
    throw UpdateFailure(support.reason ?? 'Haqor cannot update itself here.');
  }
  final work = Platform.isAndroid
      ? await _androidUpdateDir()
      : await Directory.systemTemp.createTemp('haqor-update-');
  final download = File('${work.path}${Platform.pathSeparator}${asset.name}');
  final expected = await _expectedDigest(release, asset);
  final actual = await _download(asset, download, onProgress);
  if (actual != expected) {
    await download.delete().catchError((_) => download);
    throw const UpdateFailure(
      'The download did not match the release checksum. Nothing was '
      'installed; try again.',
    );
  }
  if (Platform.isAndroid) {
    final started = await _channel.invokeMethod<bool>('install', {
      'path': download.path,
    });
    if (started != true) {
      throw const UpdateFailure('Android would not open the installer.');
    }
    return;
  }
  final staging = Directory('${work.path}${Platform.pathSeparator}new');
  await staging.create();
  await _unpack(download, staging);
  final exeName = File(Platform.resolvedExecutable).uri.pathSegments.last;
  if (!File('${staging.path}${Platform.pathSeparator}$exeName').existsSync()) {
    throw UpdateFailure('The download has no $exeName in it.');
  }
  await _startReplacer(work, staging, exeName);
  exit(0);
}

/// Android's installer reads the APK through Haqor's file provider, which
/// shares only this folder.
Future<Directory> _androidUpdateDir() async {
  final dir = Directory(
    '${(await getApplicationCacheDirectory()).path}/updates',
  );
  if (dir.existsSync()) await dir.delete(recursive: true);
  return dir.create(recursive: true);
}

Future<String> _expectedDigest(AppRelease release, ReleaseAsset asset) async {
  final sums = release.checksums;
  if (sums == null) {
    throw const UpdateFailure('The release has no checksums to verify with.');
  }
  final client = _client();
  try {
    final response = await (await client.getUrl(sums.url)).close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw UpdateFailure(
        'Fetching the checksums failed (${response.statusCode}).',
      );
    }
    final digest = parseSha256Sums(text)[asset.name];
    if (digest == null) {
      throw UpdateFailure('The release checksums do not list ${asset.name}.');
    }
    return digest;
  } finally {
    client.close(force: true);
  }
}

/// Stream [asset] into [file], returning its SHA-256.
Future<String> _download(
  ReleaseAsset asset,
  File file,
  void Function(int received, int total)? onProgress,
) async {
  final client = _client();
  final sink = file.openWrite();
  final digest = _DigestSink();
  final hasher = sha256.startChunkedConversion(digest);
  try {
    final response = await (await client.getUrl(asset.url)).close();
    if (response.statusCode != 200) {
      throw UpdateFailure('The download failed (${response.statusCode}).');
    }
    final total = response.contentLength > 0
        ? response.contentLength
        : asset.size;
    var received = 0;
    await for (final chunk in response) {
      sink.add(chunk);
      hasher.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    hasher.close();
    return digest.value.toString();
  } finally {
    await sink.close();
    client.close(force: true);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<void> _unpack(File archive, Directory into) async {
  final ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Expand-Archive -LiteralPath ${_psQuote(archive.path)} '
          '-DestinationPath ${_psQuote(into.path)} -Force',
    ]);
  } else {
    result = await Process.run('tar', ['-xzf', archive.path, '-C', into.path]);
  }
  if (result.exitCode != 0) {
    throw UpdateFailure('Unpacking the download failed: ${result.stderr}');
  }
}

String _psQuote(String text) => "'${text.replaceAll("'", "''")}'";

/// Start the helper that waits for this process to end, copies [staging] over
/// the install and starts Haqor again — even when the copy failed, so the
/// reader is never left without an app.
Future<void> _startReplacer(
  Directory work,
  Directory staging,
  String exeName,
) async {
  final dest = _installDir.path;
  if (Platform.isWindows) {
    final script = File('${work.path}\\apply-update.ps1');
    await script.writeAsString(_windowsReplacer);
    await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
      '-ProcessId',
      '$pid',
      '-Staging',
      staging.path,
      '-Dest',
      dest,
      '-Exe',
      exeName,
    ], mode: ProcessStartMode.detached);
    return;
  }
  final script = File('${work.path}/apply-update.sh');
  await script.writeAsString(_unixReplacer);
  await Process.start('/bin/sh', [
    script.path,
    '$pid',
    staging.path,
    dest,
    exeName,
  ], mode: ProcessStartMode.detached);
}

const _unixReplacer = r'''#!/bin/sh
# Written by Haqor's updater: wait for Haqor to close, copy the new build over
# the old one, then start it again.
pid="$1"; staging="$2"; dest="$3"; exe="$4"
work="$(dirname "$staging")"
i=0
while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 300 ]; do
  sleep 0.2; i=$((i + 1))
done
if cp -a "$staging/." "$dest/" 2>"$work/update-error.log"; then
  rm -rf "$staging" "$work"/*.tar.gz
fi
cd "$dest" && exec "./$exe"
''';

const _windowsReplacer = r'''
# Written by Haqor's updater: wait for Haqor to close, copy the new build over
# the old one, then start it again.
param([int]$ProcessId, [string]$Staging, [string]$Dest, [string]$Exe)
Wait-Process -Id $ProcessId -Timeout 60 -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
$log = Join-Path (Split-Path $Staging) 'update.log'
robocopy $Staging $Dest /E /R:10 /W:1 /NP /LOG:$log | Out-Null
if ($LASTEXITCODE -lt 8) { Remove-Item -Recurse -Force $Staging -ErrorAction SilentlyContinue }
Start-Process -FilePath (Join-Path $Dest $Exe) -WorkingDirectory $Dest
''';
