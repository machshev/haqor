import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rinf/rinf.dart';

import 'bindings/bindings.dart';
import 'boot_failure.dart';
import 'boot_status.dart';
import 'db_installer_web.dart';
import 'issue_reporting.dart';
import 'reader_page.dart';
import 'tutor/progress_sync.dart';

Future<Widget> initializeAppRuntime() async {
  // Each phase names the wait the reader is looking at. `web/index.html`
  // reported the ones that happen before Dart exists, and takes the boot screen
  // down once the reader has painted.
  reportBootStatus('Starting the engine…');
  await initializeRust(assignRustSignal);
  String? notice;
  String? failure;
  try {
    notice = await initializeDatabases();
  } on BootFailure catch (error) {
    failure = error.message;
  }
  return BootGate(
    start: initializeDatabases,
    reinstall: canReinstallDatabases
        ? () => initializeDatabases(reinstall: true)
        : null,
    onReady: () {
      unawaited(migrateLegacyFlaggedWords());
      unawaited(syncProgressNow());
    },
    initialFailure: failure,
    initialNotice: notice,
    child: const BibleReaderPage(),
  );
}
