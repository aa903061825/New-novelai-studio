import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class StudioWheelZoomController {
  static const double defaultZoomInFactor = 1.12;
  static const double defaultZoomOutFactor = 0.88;

  final TransformationController transformationController;
  double minScale;
  double maxScale;
  Matrix4 Function() resetTransform;
  final bool requireControlModifier;

  bool _disposed = false;
  bool _frameScheduled = false;
  Offset _pendingFocalPoint = Offset.zero;
  double _pendingScaleFactor = 1;

  StudioWheelZoomController({
    required this.transformationController,
    this.minScale = 1,
    this.maxScale = 8,
    Matrix4 Function()? resetTransform,
    this.requireControlModifier = false,
  }) : resetTransform = resetTransform ?? Matrix4.identity;

  bool handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return false;
    if (requireControlModifier && !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    final delta = event.scrollDelta.dy;
    if (delta == 0) return false;
    queueScaleAt(
      event.localPosition,
      delta < 0 ? defaultZoomInFactor : defaultZoomOutFactor,
    );
    return true;
  }

  void queueScaleAt(Offset focalPoint, double scaleFactor) {
    if (_disposed || scaleFactor == 1) return;
    _pendingFocalPoint = focalPoint;
    _pendingScaleFactor *= scaleFactor;
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      _flushPendingScale();
    });
  }

  void reset() {
    _pendingFocalPoint = Offset.zero;
    _pendingScaleFactor = 1;
    transformationController.value = resetTransform().clone();
  }

  void dispose() {
    _disposed = true;
  }

  void _flushPendingScale() {
    if (_disposed) return;
    final scaleFactor = _pendingScaleFactor;
    _pendingScaleFactor = 1;
    if (scaleFactor == 1) return;
    _scaleAt(_pendingFocalPoint, scaleFactor);
  }

  void _scaleAt(Offset focalPoint, double scaleFactor) {
    final currentScale = transformationController.value.getMaxScaleOnAxis();
    if (currentScale <= 0) {
      reset();
      return;
    }
    final nextScale =
        (currentScale * scaleFactor).clamp(minScale, maxScale).toDouble();
    if ((nextScale - currentScale).abs() < 0.0001) return;
    if (nextScale <= minScale + 0.01) {
      reset();
      return;
    }
    final effectiveScale = nextScale / currentScale;
    final next = transformationController.value.clone()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(effectiveScale, effectiveScale, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    transformationController.value = next;
  }
}
