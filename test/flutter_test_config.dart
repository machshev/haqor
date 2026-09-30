import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // A tap that misses its target lets a test pass without exercising it.
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
