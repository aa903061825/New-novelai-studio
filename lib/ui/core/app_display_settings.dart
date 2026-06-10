import 'dart:async';

import 'package:flutter/foundation.dart';

class AppDisplaySettings {
  static const double defaultImagePreviewDialogHeight = 760;
  static const double minImagePreviewDialogHeight = 520;
  static const double maxImagePreviewDialogHeight = 980;

  static final ValueNotifier<double> textScale = ValueNotifier<double>(1.1);
  static final ValueNotifier<double> imagePreviewDialogHeight =
      ValueNotifier<double>(defaultImagePreviewDialogHeight);
  static final ValueNotifier<int> promptTranslationShortcutSerial =
      ValueNotifier<int>(0);

  static const String promptTranslationShortcutLabel = 'Ctrl+Shift+T';

  static FutureOr<void> Function(double value)?
      _persistImagePreviewDialogHeight;
  static String? _hoveredPromptTargetId;

  static double clampTextScale(double value) {
    return value.clamp(1.0, 1.35).toDouble();
  }

  static void setTextScale(double value) {
    textScale.value = clampTextScale(value);
  }

  static double clampImagePreviewDialogHeight(double value) {
    return value
        .clamp(minImagePreviewDialogHeight, maxImagePreviewDialogHeight)
        .toDouble();
  }

  static void setImagePreviewDialogHeight(
    double value, {
    bool persist = true,
  }) {
    final next = clampImagePreviewDialogHeight(value);
    imagePreviewDialogHeight.value = next;
    final persistHeight = _persistImagePreviewDialogHeight;
    if (persist && persistHeight != null) {
      unawaited(Future<void>.sync(() => persistHeight(next)));
    }
  }

  static void configureImagePreviewDialogHeightPersistence(
    FutureOr<void> Function(double value) persist,
  ) {
    _persistImagePreviewDialogHeight = persist;
  }

  static void clearImagePreviewDialogHeightPersistence() {
    _persistImagePreviewDialogHeight = null;
  }

  static bool isHoveredPromptTarget(String id) {
    return _hoveredPromptTargetId == id;
  }

  static void registerHoveredPromptTarget(String id) {
    _hoveredPromptTargetId = id;
  }

  static void clearHoveredPromptTarget(String id) {
    if (_hoveredPromptTargetId == id) {
      _hoveredPromptTargetId = null;
    }
  }

  static void translateHoveredPromptCard() {
    promptTranslationShortcutSerial.value++;
  }

  const AppDisplaySettings._();
}
