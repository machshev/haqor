import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// What points a program at libraries and modules of its own. The Nix dev
/// shell and the Nix package's wrapper set these for Haqor, and a browser
/// started from it would load Haqor's libraries in place of its own (Firefox:
/// "version `LIBFFI_CALL_PLAN_8.4' not found … Couldn't load XPCOM").
const _loaderVariables = {
  'LD_LIBRARY_PATH',
  'LD_PRELOAD',
  'GIO_EXTRA_MODULES',
  'GIO_MODULE_DIR',
  'GDK_PIXBUF_MODULE_FILE',
};

/// [environment] without what would make another program load Haqor's
/// libraries.
Map<String, String> environmentForOtherPrograms(
  Map<String, String> environment,
) => {
  for (final MapEntry(:key, :value) in environment.entries)
    if (!_loaderVariables.contains(key)) key: value,
};

/// Open [uri] outside the app, in the browser or the app for it. Whether it
/// opened.
///
/// On Linux it goes through `xdg-open` without Haqor's library paths, which
/// url_launcher would hand on to the browser; elsewhere, where there is no
/// `xdg-open`, and under `flutter test` (which fakes url_launcher), through
/// url_launcher.
Future<bool> openExternalLink(Uri uri) async {
  if (Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST')) {
    try {
      await Process.start(
        'xdg-open',
        [uri.toString()],
        environment: environmentForOtherPrograms(Platform.environment),
        includeParentEnvironment: false,
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      // No xdg-open: try url_launcher's way.
    }
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
