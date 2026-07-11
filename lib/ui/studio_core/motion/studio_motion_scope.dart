import 'package:flutter/material.dart';

class StudioMotionScope extends StatelessWidget {
  final bool? disableAnimations;
  final Widget child;

  const StudioMotionScope({
    super.key,
    this.disableAnimations,
    required this.child,
  });

  static bool animationsDisabled(BuildContext context) {
    final scoped =
        context.dependOnInheritedWidgetOfExactType<_StudioMotionScopeData>();
    if (scoped != null) {
      return scoped.disableAnimations;
    }
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  static Duration duration(BuildContext context, Duration duration) {
    return animationsDisabled(context) ? Duration.zero : duration;
  }

  @override
  Widget build(BuildContext context) {
    return _StudioMotionScopeData(
      disableAnimations: disableAnimations ??
          (MediaQuery.maybeOf(context)?.disableAnimations ?? false),
      child: child,
    );
  }
}

class _StudioMotionScopeData extends InheritedWidget {
  final bool disableAnimations;

  const _StudioMotionScopeData({
    required this.disableAnimations,
    required super.child,
  });

  @override
  bool updateShouldNotify(covariant _StudioMotionScopeData oldWidget) {
    return oldWidget.disableAnimations != disableAnimations;
  }
}
