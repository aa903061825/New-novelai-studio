import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';

const double kStudioHoverPreviewWidth = 704;
const double kStudioHoverPreviewHeight = 960;
const double kStudioHoverPreviewPadding = 6;
const Offset kStudioHoverPreviewOffset = Offset(54, -96);
const double kStudioHoverPreviewViewportPadding = 12;

class StudioHoverPreviewThumbnail extends StatefulWidget {
  final Widget Function(BuildContext context, String? previewPath) builder;
  final List<String> previewPaths;
  final Key? overlayKey;
  final double overlayWidth;
  final double overlayHeight;
  final double overlayPadding;
  final Offset overlayOffset;

  const StudioHoverPreviewThumbnail({
    super.key,
    required this.builder,
    required this.previewPaths,
    this.overlayKey,
    this.overlayWidth = kStudioHoverPreviewWidth,
    this.overlayHeight = kStudioHoverPreviewHeight,
    this.overlayPadding = kStudioHoverPreviewPadding,
    this.overlayOffset = kStudioHoverPreviewOffset,
  });

  @override
  State<StudioHoverPreviewThumbnail> createState() =>
      _StudioHoverPreviewThumbnailState();
}

class _StudioHoverPreviewThumbnailState
    extends State<StudioHoverPreviewThumbnail> {
  final LayerLink _previewLink = LayerLink();
  OverlayEntry? _previewOverlay;
  int _previewIndex = 0;
  bool _targetHovered = false;
  bool _overlayHovered = false;
  bool _hidePreviewScheduled = false;

  @override
  void dispose() {
    _hidePreview();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StudioHoverPreviewThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_previewIndex >= widget.previewPaths.length) {
      _previewIndex = 0;
    }
    if (oldWidget.previewPaths.join('\n') != widget.previewPaths.join('\n')) {
      _previewOverlay?.markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _handlePreviewScroll,
      child: MouseRegion(
        onEnter: (_) {
          _targetHovered = true;
          _showPreview();
        },
        onExit: (_) {
          _targetHovered = false;
          _scheduleHidePreview();
        },
        child: CompositedTransformTarget(
          link: _previewLink,
          child: widget.builder(context, _currentPreviewPath),
        ),
      ),
    );
  }

  String? get _currentPreviewPath {
    if (widget.previewPaths.isEmpty) return null;
    return widget.previewPaths[_previewIndex];
  }

  void _handlePreviewScroll(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent || _currentPreviewPath == null) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(signal, (event) {
      final scrollEvent = event as PointerScrollEvent;
      final delta = scrollEvent.scrollDelta.dy == 0
          ? scrollEvent.scrollDelta.dx
          : scrollEvent.scrollDelta.dy;
      if (delta == 0) return;
      _selectPreview(_previewIndex + (delta > 0 ? 1 : -1));
    });
  }

  void _selectPreview(int index) {
    final length = widget.previewPaths.length;
    if (length < 2) return;
    final nextIndex = index % length;
    if (nextIndex == _previewIndex) return;
    setState(() {
      _previewIndex = nextIndex;
    });
    _previewOverlay?.markNeedsBuild();
  }

  void _showPreview() {
    if (_currentPreviewPath == null || _previewOverlay != null) return;
    final overlay = Overlay.of(context);
    _previewOverlay = OverlayEntry(
      builder: (context) {
        final previewPath = _currentPreviewPath;
        if (previewPath == null) return const SizedBox.shrink();
        final geometry = _resolvePreviewGeometry(overlay);
        return CompositedTransformFollower(
          link: _previewLink,
          showWhenUnlinked: false,
          offset: geometry.offset,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: geometry.size.width,
              height: geometry.size.height,
              child: MouseRegion(
                onEnter: (_) {
                  _overlayHovered = true;
                },
                onExit: (_) {
                  _overlayHovered = false;
                  _scheduleHidePreview();
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: _handlePreviewScroll,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      key: widget.overlayKey,
                      width: geometry.size.width,
                      height: geometry.size.height,
                      padding: EdgeInsets.all(widget.overlayPadding),
                      decoration: BoxDecoration(
                        color: StudioTokens.surface2,
                        borderRadius: StudioTokens.radiusCard,
                        border: Border.all(color: StudioTokens.primary),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: StudioTokens.radiusSlot,
                        child: Image.file(
                          File(previewPath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_previewOverlay!);
  }

  _HoverPreviewGeometry _resolvePreviewGeometry(OverlayState overlay) {
    final overlaySize = _overlaySize(overlay);
    final targetTopLeft = _targetTopLeftInOverlay(overlay);
    final previewSize = _previewSizeFor(overlaySize);
    final desiredTopLeft = targetTopLeft + widget.overlayOffset;
    final left = _clampDouble(
      desiredTopLeft.dx,
      kStudioHoverPreviewViewportPadding,
      overlaySize.width -
          previewSize.width -
          kStudioHoverPreviewViewportPadding,
    );
    final top = _clampDouble(
      desiredTopLeft.dy,
      kStudioHoverPreviewViewportPadding,
      overlaySize.height -
          previewSize.height -
          kStudioHoverPreviewViewportPadding,
    );
    return _HoverPreviewGeometry(
      offset: Offset(left - targetTopLeft.dx, top - targetTopLeft.dy),
      size: previewSize,
    );
  }

  Size _overlaySize(OverlayState overlay) {
    final overlayRenderObject = overlay.context.findRenderObject();
    if (overlayRenderObject is RenderBox &&
        overlayRenderObject.hasSize &&
        !overlayRenderObject.size.isEmpty) {
      return overlayRenderObject.size;
    }
    final mediaSize = MediaQuery.maybeSizeOf(context);
    if (mediaSize != null && !mediaSize.isEmpty) return mediaSize;
    return Size(widget.overlayWidth, widget.overlayHeight);
  }

  Offset _targetTopLeftInOverlay(OverlayState overlay) {
    final targetRenderObject = context.findRenderObject();
    final overlayRenderObject = overlay.context.findRenderObject();
    if (targetRenderObject is! RenderBox ||
        overlayRenderObject is! RenderBox ||
        !targetRenderObject.hasSize ||
        !overlayRenderObject.hasSize) {
      return Offset.zero;
    }
    return targetRenderObject.localToGlobal(Offset.zero) -
        overlayRenderObject.localToGlobal(Offset.zero);
  }

  Size _previewSizeFor(Size overlaySize) {
    final availableWidth =
        overlaySize.width - kStudioHoverPreviewViewportPadding * 2;
    final availableHeight =
        overlaySize.height - kStudioHoverPreviewViewportPadding * 2;
    if (availableWidth <= 0 || availableHeight <= 0) {
      return Size(widget.overlayWidth, widget.overlayHeight);
    }
    final scale = math.min(
      1.0,
      math.min(
        availableWidth / widget.overlayWidth,
        availableHeight / widget.overlayHeight,
      ),
    );
    return Size(widget.overlayWidth * scale, widget.overlayHeight * scale);
  }

  void _scheduleHidePreview() {
    if (_hidePreviewScheduled) return;
    _hidePreviewScheduled = true;
    scheduleMicrotask(() {
      _hidePreviewScheduled = false;
      if (!_targetHovered && !_overlayHovered) {
        _hidePreview();
      }
    });
  }

  void _hidePreview() {
    _previewOverlay?.remove();
    _previewOverlay = null;
    _overlayHovered = false;
  }
}

class _HoverPreviewGeometry {
  final Offset offset;
  final Size size;

  const _HoverPreviewGeometry({
    required this.offset,
    required this.size,
  });
}

double _clampDouble(double value, double min, double max) {
  if (max < min) return min;
  return value.clamp(min, max).toDouble();
}
