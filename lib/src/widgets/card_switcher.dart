import 'package:flutter/widgets.dart';

/// An [AnimatedSwitcher] transition that fades like the default one but stops
/// the outgoing child taking taps, so a card that is fading out cannot be
/// answered a second time.
Widget fadeIgnoringOutgoing(Widget child, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) => IgnorePointer(
      ignoring: animation.status == AnimationStatus.reverse,
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
}
