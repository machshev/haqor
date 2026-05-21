import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import 'src/bindings/bindings.dart';
import 'src/reader_page.dart';

Future<void> main() async {
  await initializeRust(assignRustSignal);
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
