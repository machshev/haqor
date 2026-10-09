import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/external_link_native.dart';

void main() {
  test('a browser opened from Haqor does not load its libraries', () {
    expect(
      environmentForOtherPrograms({
        'LD_LIBRARY_PATH': '/nix/store/x-libffi-3.5.2/lib',
        'GIO_EXTRA_MODULES': '/nix/store/x-dconf/lib/gio/modules',
        'HOME': '/home/reader',
        'XDG_DATA_DIRS': '/run/current-system/sw/share',
        'DISPLAY': ':0',
      }),
      {
        'HOME': '/home/reader',
        'XDG_DATA_DIRS': '/run/current-system/sw/share',
        'DISPLAY': ':0',
      },
    );
  });
}
