import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/tutor/progress_sync.dart';
import 'package:haqor/src/tutor/sync_join.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _pin = 'ab' * 32;
final _token = 'e1249ea6' * 8;

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

  group('join links', () {
    test('parse the form haqor-sync-server join prints', () {
      // Kept identical to haqor-sync-server's join_link test, so a change to
      // the format on either side shows up here.
      final link = SyncJoinLink.tryParse(
        'haqor://join?user=alice&server=https://10.0.0.2:8788'
        '&server=https://sync-host.lan:8788&pin=$_pin&token=ab%26c%23d$_token',
      );
      expect(link, isNotNull);
      expect(link!.user, 'alice');
      expect(link.servers, [
        'https://10.0.0.2:8788',
        'https://sync-host.lan:8788',
      ]);
      expect(link.pin, _pin);
      expect(link.token, 'ab&c#d$_token');
    });

    test('round-trip through their text form', () {
      final link = SyncJoinLink(
        user: 'alice',
        servers: const ['https://10.0.0.2:8788', 'http://192.168.1.10:8788'],
        pin: _pin,
        token: 'a b&c=$_token',
      );
      final text = link.toLinkString();
      expect(text, startsWith('haqor://join?user=alice&server=https://'));
      final parsed = SyncJoinLink.tryParse(text)!;
      expect(parsed.servers, link.servers);
      expect(parsed.token, link.token);
      expect(parsed.pin, link.pin);
    });

    test('pins written with colons or capitals are accepted', () {
      final colons = List.filled(32, 'AB').join(':');
      final link = SyncJoinLink.tryParse(
        'haqor://join?server=https://h:1&pin=$colons&token=$_token',
      );
      expect(link?.pin, _pin);
    });

    test('are refused when they could not be trusted or used', () {
      for (final text in [
        'https://example.com/join?server=https://h:1&pin=$_pin&token=$_token',
        'haqor://other?server=https://h:1&pin=$_pin&token=$_token',
        'haqor://join?pin=$_pin&token=$_token',
        // https without a fingerprint could never be verified.
        'haqor://join?server=https://h:1&token=$_token',
        'haqor://join?server=https://h:1&pin=abc&token=$_token',
        'haqor://join?server=ftp://h:1&pin=$_pin&token=$_token',
        'haqor://join?server=https://h:1&pin=$_pin&token=short',
        'not a link',
      ]) {
        expect(SyncJoinLink.tryParse(text), isNull, reason: text);
      }
    });

    test('for plain http need no fingerprint', () {
      final link = SyncJoinLink.tryParse(
        'haqor://join?server=http://192.168.1.10:8788&token=$_token',
      );
      expect(link?.pin, '');
    });
  });

  group('settings', () {
    test('read a single address saved before join links', () async {
      final config = await loadProgressSyncConfig();
      expect(config.servers, ['http://192.168.1.10:8788']);
      expect(config.token, 'secret');
      expect(config.isConfigured, isTrue);
    });

    test('keep every address and the first under the old key', () async {
      await saveProgressSyncConfig(
        ProgressSyncConfig(
          servers: const [
            'https://10.0.0.2:8788',
            'https://sync-host.lan:8788',
          ],
          pin: _pin,
          token: _token,
          user: 'alice',
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('progress_sync_server_url'),
        'https://10.0.0.2:8788',
      );
      final config = await loadProgressSyncConfig();
      expect(config.servers, hasLength(2));
      expect(config.pin, _pin);
      expect(config.user, 'alice');
      expect(config.joinLink.toLinkString(), contains('user=alice'));
    });

    test('try the address that answered last first', () {
      final config = ProgressSyncConfig(
        servers: const ['https://a:1', 'https://b:1', 'https://c:1'],
        pin: _pin,
        token: _token,
        lastServer: 'https://b:1',
      );
      expect(config.tryOrder, ['https://b:1', 'https://a:1', 'https://c:1']);
      final forgotten = ProgressSyncConfig(
        servers: config.servers,
        pin: _pin,
        token: _token,
        lastServer: 'https://gone:1',
      );
      expect(forgotten.tryOrder, config.servers);
    });

    test('flag plain-HTTP addresses, which would be shared on', () async {
      expect((await loadProgressSyncConfig()).usesPlainHttp, isTrue);
      final https = ProgressSyncConfig(
        servers: const ['https://10.0.0.2:8788'],
        pin: _pin,
        token: _token,
      );
      expect(https.usesPlainHttp, isFalse);
    });

    test('with no addresses turn sync off', () async {
      await saveProgressSyncConfig(ProgressSyncConfig.empty);
      final config = await loadProgressSyncConfig();
      expect(config.isConfigured, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
