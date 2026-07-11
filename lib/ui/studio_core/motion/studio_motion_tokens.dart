import 'package:flutter/material.dart';

class StudioMotionTokens {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const expressive = Duration(milliseconds: 560);
  static const showcase = Duration(milliseconds: 360);

  static const utilityCurve = Curves.easeOutCubic;
  static const showcaseCurve = Cubic(0.16, 1, 0.3, 1);
  static const expressiveCurve = Curves.easeOutBack;

  const StudioMotionTokens._();
}
