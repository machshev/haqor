import 'package:rinf/rinf.dart';
import 'src/bindings/bindings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> main() async {
  await initializeRust(assignRustSignal);
  runApp(const Haqor());
}

class Haqor extends StatelessWidget {
  const Haqor({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _verse = 1;

  void _increment() {
    setState(() {
      ++_verse;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        StreamBuilder(
          stream: VerseText.rustSignalStream,
          builder: (context, snapshot) {
            final signalPack = snapshot.data;
            if (signalPack == null) {
              return Text('');
            }
            final verse = signalPack.message.text;
            return Text(
              verse.toString(),
              textDirection: TextDirection.rtl,
              style: GoogleFonts.getFont(
                "David Libre",
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            );
          },
        ),
        ElevatedButton(
          onPressed: () async {
            GetVerseText(book: 1, chapter: 1, verse: _verse).sendSignalToRust();
            _increment();
          },
          child: Text('Get Verse'),
        ),
      ],
    );
  }
}
