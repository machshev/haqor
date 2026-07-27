/// Dart's half of the boot screen in `web/index.html`.
///
/// The loader there reports what it can see — fetching the app, applying an
/// update — and then hands over: everything from "the Dart runtime is alive" to
/// the first painted frame is only visible from here, and it is the longest part
/// of the wait, since it includes handing a 38 MB database to the Rust engine.
///
/// Every call is a no-op when the page has no boot screen (it has already been
/// dismissed, or a host page embedded the app without one), so callers need not
/// check.
library;

import 'dart:js_interop';

@JS('window.haqorBoot')
external _HaqorBoot? get _boot;

extension type _HaqorBoot._(JSObject _) implements JSObject {
  external void status(String text, double? fraction, String? note);
  external void fail(String text, String? note);
  external void done();
}

/// Describe the phase now under way. [progress] is a 0..1 fraction where it can
/// be measured, and null where the wait has no known length — the boot screen
/// sweeps rather than sitting at zero.
void reportBootStatus(String message, {double? progress, String? detail}) {
  _boot?.status(message, progress, detail);
}

/// Leave a failure on screen. Startup failures happen before there is any
/// Flutter view to report them through, so without this they are a white page.
void reportBootFailure(String message, {String? detail}) {
  _boot?.fail(message, detail);
}

/// Dismiss the boot screen: the app has painted.
void bootFinished() {
  _boot?.done();
}
