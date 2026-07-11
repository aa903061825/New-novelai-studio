import 'dart:math';

import 'package:flutter/material.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_scrollbar.dart';

const studioImagePreviewDialogConstraints = BoxConstraints(
  maxWidth: 1180,
  maxHeight: double.infinity,
);

const studioImagePreviewPromptMaxHeight = 320.0;
const studioImagePreviewViewportMaxRatio = 0.90;

class StudioResizableImagePreviewWindow extends StatelessWidget {
  final Key? windowKey;
  final Widget child;
  final EdgeInsets padding;
  final BoxConstraints constraints;

  const StudioResizableImagePreviewWindow({
    super.key,
    this.windowKey,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.constraints = studioImagePreviewDialogConstraints,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AppDisplaySettings.imagePreviewDialogHeight,
      builder: (context, preferredHeight, _) {
        final viewport = MediaQuery.sizeOf(context);
        final width = min(
          constraints.maxWidth,
          max(320.0, viewport.width - 48),
        );
        final viewportMaxHeight =
            max(320.0, viewport.height * studioImagePreviewViewportMaxRatio);
        final availableHeight = min(constraints.maxHeight, viewportMaxHeight);
        final minHeight = min(
          AppDisplaySettings.minImagePreviewDialogHeight,
          availableHeight,
        );
        final height = preferredHeight.clamp(minHeight, availableHeight);
        return SizedBox(
          key: windowKey,
          width: width,
          height: height.toDouble(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: padding,
                  child: child,
                ),
              ),
              _StudioImagePreviewHeightHandle(maxHeight: availableHeight),
            ],
          ),
        );
      },
    );
  }
}

class _StudioImagePreviewHeightHandle extends StatelessWidget {
  final double maxHeight;

  const _StudioImagePreviewHeightHandle({required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        key: const ValueKey('studio-image-preview-height-handle'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          final nextHeight =
              (AppDisplaySettings.imagePreviewDialogHeight.value +
                      details.delta.dy)
                  .clamp(
                    AppDisplaySettings.minImagePreviewDialogHeight,
                    maxHeight,
                  )
                  .toDouble();
          AppDisplaySettings.setImagePreviewDialogHeight(
            nextHeight,
            persist: false,
          );
        },
        onVerticalDragEnd: (_) {
          AppDisplaySettings.setImagePreviewDialogHeight(
            AppDisplaySettings.imagePreviewDialogHeight.value,
          );
        },
        onVerticalDragCancel: () {
          AppDisplaySettings.setImagePreviewDialogHeight(
            AppDisplaySettings.imagePreviewDialogHeight.value,
          );
        },
        child: SizedBox(
          height: 18,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: StudioTokens.border,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const SizedBox(width: 88, height: 4),
            ),
          ),
        ),
      ),
    );
  }
}

class StudioImagePreviewPromptScroll extends StatelessWidget {
  final Widget child;

  const StudioImagePreviewPromptScroll({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: studioImagePreviewPromptMaxHeight,
      ),
      child: StudioScrollbar(
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}
