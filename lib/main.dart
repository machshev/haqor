import 'package:rinf/rinf.dart';
import 'src/bindings/bindings.dart';
import 'package:flutter/material.dart';

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
              return Text('Nothing received yet');
            }
            final verse = signalPack.message.text;
            return Text(
              verse.toString(),
              style: Theme.of(context).textTheme.headlineMedium,
            );
          },
        ),
        ElevatedButton(
          onPressed: () async {
            GetVerseText(book: 1, chapter: 1, verse: 1).sendSignalToRust();
          },
          child: Text('Get Verse'),
        ),
      ],
    );
  }
}
