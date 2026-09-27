import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/widgets/markdown_note.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  Future<TextEditingController> pumpField(
    WidgetTester tester,
    String text,
  ) async {
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownNoteField(controller: controller, label: 'Note'),
        ),
      ),
    );
    return controller;
  }

  testWidgets('bold wraps and unwraps the selection', (tester) async {
    final controller = await pumpField(tester, 'a word here');
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 6);
    await tester.tap(find.byTooltip('Bold'));
    expect(controller.text, 'a **word** here');
    expect(controller.selection.textInside(controller.text), 'word');
    await tester.tap(find.byTooltip('Bold'));
    expect(controller.text, 'a word here');
  });

  testWidgets('lists toggle on every selected line', (tester) async {
    final controller = await pumpField(tester, 'one\ntwo\nthree');
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    await tester.tap(find.byTooltip('Numbered list'));
    expect(controller.text, '1. one\n2. two\nthree');
    await tester.tap(find.byTooltip('Numbered list'));
    expect(controller.text, 'one\ntwo\nthree');
    await tester.tap(find.byTooltip('Bulleted list'));
    expect(controller.text, '- one\n- two\nthree');
  });

  testWidgets('preview renders the Markdown', (tester) async {
    await pumpField(tester, 'Some **bold** text');
    await tester.tap(find.byTooltip('Preview'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Some bold text', findRichText: true), findsOneWidget);
  });

  testWidgets('link wraps the selection as link text', (tester) async {
    final controller = await pumpField(tester, 'see Rashi');
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 9);
    await tester.tap(find.byTooltip('Link'));
    expect(controller.text, 'see [Rashi](https://)');
    expect(controller.selection.baseOffset, controller.text.length - 1);
  });

  testWidgets('web links open and other schemes are ignored', (tester) async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MarkdownNote('[site](https://example.org)'),
              MarkdownNote('[bad](javascript:alert(1))'),
            ],
          ),
        ),
      ),
    );
    await tester.tapOnText(find.textRange.ofSubstring('site'));
    await tester.tapOnText(find.textRange.ofSubstring('bad'));
    await tester.pump();
    expect(launcher.launched, ['https://example.org']);
  });

  test('plain text drops Markdown syntax', () {
    expect(markdownPlainText('# Title\n\n- **one**\n- *two*'), 'Title one two');
  });
}

class _FakeUrlLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final launched = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}
