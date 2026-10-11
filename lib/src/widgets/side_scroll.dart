import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A scroll behaviour a mouse may drag too, for a strip that only scrolls
/// sideways: a desktop's wheel scrolls down, so a mouse otherwise has no way
/// past the strip's edge. Not for a page whose text a mouse selects.
ScrollBehavior mouseDraggable(BuildContext context) => ScrollConfiguration.of(
  context,
).copyWith(dragDevices: PointerDeviceKind.values.toSet());

/// A row that runs past its edge, with a bar that shows there is more, and
/// that a mouse may drag.
class SideScroll extends StatefulWidget {
  /// A [SingleChildScrollView] of [child], with [padding] below for the bar.
  SideScroll({EdgeInsetsGeometry? padding, required Widget child, super.key})
    : builder = ((context, controller) => SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: child,
      ));

  /// The scroll view [builder] makes, scrolling sideways by its controller.
  const SideScroll.builder({required this.builder, super.key});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<SideScroll> createState() => _SideScrollState();
}

class _SideScrollState extends State<SideScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: mouseDraggable(context),
    child: Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: widget.builder(context, _controller),
    ),
  );
}
