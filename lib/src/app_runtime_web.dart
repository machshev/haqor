import 'package:flutter/widgets.dart';

import 'db_installer_web.dart';
import 'reader_page.dart';

Future<Widget> initializeAppRuntime() async {
  final bible = await initializeWebDatabases();
  return BibleReaderPage(sendChapterRequest: bible.sendChapter);
}
