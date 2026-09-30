import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/tutor/progress_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'progress_sync_server_url': 'http://192.168.1.10:8788',
      'progress_sync_token': 'secret',
    });
  });
  tearDown(() => progressSyncSupported = true);

  test(
    'where sync is unsupported, a sync request is refused untouched',
    () async {
      progressSyncSupported = false;
      var requested = false;
      final started = await syncProgressNow(onRequest: () => requested = true);
      expect(started, isFalse);
      expect(requested, isFalse, reason: 'no manual-sync spinner is started');
      expect(syncsInFlight, 0);
    },
  );

  // A timer left pending fails the test at its end.
  testWidgets('where sync is unsupported, none is scheduled', (tester) async {
    progressSyncSupported = false;
    scheduleProgressSync();
  });
}
