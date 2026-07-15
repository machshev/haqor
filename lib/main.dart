import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import 'src/bindings/bindings.dart';
import 'src/db_installer.dart';
import 'src/issue_reporting.dart';
import 'src/reader_page.dart';
import 'src/tutor/progress_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await initializeRust(assignRustSignal);
  // Tell Rust where the databases live; it answers no queries until it has
  // opened them, so this must precede runApp (the reader queries in initState).
  final dbDir = await installDatabases();
  SetDataDir(path: dbDir).sendSignalToRust();
  unawaited(migrateLegacyFlaggedWords());
  unawaited(syncProgressNow());
  runApp(const Haqor());
}

class Haqor extends StatelessWidget {
  const Haqor({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'הָקוֹר',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D5A27),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D5A27),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BibleReaderPage(),
    );
  }
}
