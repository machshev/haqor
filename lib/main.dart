import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_runtime.dart';
import 'src/boot_status.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final Widget home;
  try {
    home = await initializeAppRuntime();
  } catch (error) {
    // On web this runs before there is any Flutter view, so an error here shows
    // as a blank page and nothing else. Say so on the boot screen the reader is
    // already looking at, and let the error carry on to the console.
    reportBootFailure(
      'Haqor could not start.',
      detail: 'Reloading the page usually clears it. ($error)',
    );
    rethrow;
  }
  runApp(Haqor(home: home));
  // The boot screen stays up until something has actually been drawn; taking it
  // down any earlier trades a described wait for a blank one.
  WidgetsBinding.instance.addPostFrameCallback((_) => bootFinished());
}

class Haqor extends StatelessWidget {
  const Haqor({required this.home, super.key});

  final Widget home;

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
      home: home,
    );
  }
}
