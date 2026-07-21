import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rinf/rinf.dart';

import 'bindings/bindings.dart';
import 'db_installer_web.dart';
import 'issue_reporting.dart';
import 'reader_page.dart';
import 'tutor/progress_sync.dart';

Future<Widget> initializeAppRuntime() async {
  await initializeRust(assignRustSignal);
  await initializeDatabases();
  unawaited(migrateLegacyFlaggedWords());
  unawaited(syncProgressNow());
  return const BibleReaderPage();
}
