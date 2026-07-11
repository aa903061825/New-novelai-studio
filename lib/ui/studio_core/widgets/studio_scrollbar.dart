import 'package:flutter/material.dart';

class StudioScrollBehavior extends MaterialScrollBehavior {
  static const double verticalScrollbarGutter = 18;

  const StudioScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) != Axis.vertical) {
      return child;
    }

    switch (getPlatform(context)) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        assert(details.controller != null);
        return Scrollbar(
          controller: details.controller,
          child: Padding(
            padding: _verticalGutter,
            child: child,
          ),
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return child;
    }
  }

  static const EdgeInsetsGeometry _verticalGutter =
      EdgeInsetsDirectional.only(end: verticalScrollbarGutter);
}

class StudioScrollbar extends StatelessWidget {
  final ScrollController? controller;
  final bool? thumbVisibility;
  final Widget child;

  const StudioScrollbar({
    super.key,
    this.controller,
    this.thumbVisibility,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            end: StudioScrollBehavior.verticalScrollbarGutter,
          ),
          child: child,
        ),
      ),
    );
  }
}
