import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('org.haqor/app');

/// Leaves the app as the system back button does from its first screen.
///
/// On Android the app goes to the background, still running, as Android 12+
/// does for other apps' main screens; Flutter's own [SystemNavigator.pop]
/// would finish the activity, so coming back meant starting again from the
/// boot screen. Elsewhere this is [SystemNavigator.pop].
Future<void> leaveApp() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await _channel.invokeMethod<void>('moveToBack');
      return;
    } on MissingPluginException {
      // An embedding without the channel falls back to closing.
    }
  }
  await SystemNavigator.pop();
}
