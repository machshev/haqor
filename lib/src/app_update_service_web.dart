import 'app_update.dart';

// The web build is a PWA whose service worker fetches each release itself, so
// it has no update check.

bool get appUpdateSupported => false;

Future<UpdateSupport> updateSupport() async => const UpdateSupport(
  UpdateMethod.none,
  [],
  reason: 'The web app updates itself.',
);

Future<AppRelease> fetchLatestRelease() =>
    throw const UpdateFailure('The web app updates itself.');

Future<bool> canInstallUpdates() async => false;

Future<void> openInstallPermissionSettings() async {}

Future<void> takeUpdate(
  UpdateSupport support,
  AppRelease release,
  ReleaseAsset asset, {
  void Function(int received, int total)? onProgress,
}) => throw const UpdateFailure('The web app updates itself.');
