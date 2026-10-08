import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rinf/rinf.dart';

import 'bindings/bindings.dart';
import 'boot_failure.dart';
import 'db_installer_native.dart';
import 'issue_reporting.dart';
import 'reader_page.dart';
import 'reading_presets.dart';
import 'tutor/progress_sync.dart';

Future<Widget> initializeAppRuntime() async {
  await initializeRust(assignRustSignal);
  String? notice;
  BootFailure? failure;
  try {
    notice = await initializeDatabases();
  } on BootFailure catch (error) {
    failure = error;
  }
  return BootGate(
    start: initializeDatabases,
    reinstall: canReinstallDatabases
        ? () => initializeDatabases(reinstall: true)
        : null,
    resetProgress: canResetProgress ? startWithFreshProgress : null,
    onReady: () {
      unawaited(migrateLegacyFlaggedWords());
      unawaited(syncProgressNow());
    },
    initialFailure: failure,
    initialNotice: notice,
    child: const WelcomeGate(child: BibleReaderPage()),
  );
}
