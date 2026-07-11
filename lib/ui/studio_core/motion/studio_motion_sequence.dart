import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_reveal.dart';

enum StudioMotionRegion { panel, drawer, editor, controls, result }

class StudioMotionSequenceRegion extends StatelessWidget {
  final StudioMotionRegion region;
  final int order;
  final Widget child;

  const StudioMotionSequenceRegion({
    super.key,
    required this.region,
    required this.child,
    this.order = 0,
  });

  @override
  Widget build(BuildContext context) {
    return StudioReveal(
      delay: Duration(milliseconds: 54 * order.clamp(0, 6)),
      duration: StudioMotionTokens.medium,
      curve: StudioMotionTokens.showcaseCurve,
      beginScale: _beginScale,
      beginOffset: _beginOffset,
      child: child,
    );
  }

  Offset get _beginOffset {
    return switch (region) {
      StudioMotionRegion.drawer => const Offset(-0.035, 0),
      StudioMotionRegion.controls => const Offset(0.035, 0),
      StudioMotionRegion.result => const Offset(0, 0.032),
      StudioMotionRegion.editor => const Offset(0, 0.026),
      StudioMotionRegion.panel => const Offset(0, 0.022),
    };
  }

  double get _beginScale {
    return switch (region) {
      StudioMotionRegion.drawer => 0.992,
      StudioMotionRegion.controls => 0.992,
      StudioMotionRegion.result => 0.985,
      StudioMotionRegion.editor => 0.988,
      StudioMotionRegion.panel => 0.99,
    };
  }
}
