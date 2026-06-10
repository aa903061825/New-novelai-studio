import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_size_getter/file_input.dart' as image_size;
import 'package:image_size_getter/image_size_getter.dart' as image_size;
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_image_preview_layout.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

const _windowChannel = MethodChannel('nai_casrand/window');

class _NativeImagePreviewFullscreen {
  static Future<void> enter() {
    return _invoke('enterImagePreviewFullscreen');
  }

  static Future<void> exit() {
    return _invoke('exitImagePreviewFullscreen');
  }

  static Future<void> _invoke(String method) async {
    try {
      await _windowChannel.invokeMethod<bool>(method);
    } on MissingPluginException {
      // Widget tests and non-Windows platforms still keep the in-app fullscreen.
    } on PlatformException {
      // Native fullscreen is a best-effort enhancement; the viewer remains usable.
    }
  }
}

class StudioGeneratedImageItem {
  final String id;
  final String name;
  final String? imagePath;
  final Uint8List? imageBytes;
  final Object? source;
  final String? placeholder;

  const StudioGeneratedImageItem({
    required this.id,
    required this.name,
    this.imagePath,
    this.imageBytes,
    this.source,
    this.placeholder,
  });

  const StudioGeneratedImageItem.file({
    required this.id,
    required this.name,
    required String this.imagePath,
    this.source,
    this.placeholder,
  }) : imageBytes = null;

  const StudioGeneratedImageItem.memory({
    required this.id,
    required this.name,
    required Uint8List this.imageBytes,
    this.source,
    this.placeholder,
  }) : imagePath = null;

  bool get hasImage =>
      imageBytes != null || _existingImageFile(imagePath) != null;
}

class StudioGeneratedImageGallery extends StatelessWidget {
  final List<StudioGeneratedImageItem> items;
  final String? selectedId;
  final double columnWidth;
  final bool scrollable;
  final EdgeInsets padding;
  final String cardKeyPrefix;
  final String imageKeyPrefix;
  final Map<String, Key> itemKeys;
  final void Function(BuildContext context, StudioGeneratedImageItem item)?
      onOpen;
  final Widget Function(BuildContext context, StudioGeneratedImageItem item)?
      trailingBuilder;

  const StudioGeneratedImageGallery({
    super.key,
    required this.items,
    this.selectedId,
    this.columnWidth = 240,
    this.scrollable = false,
    this.padding = EdgeInsets.zero,
    this.cardKeyPrefix = 'studio-generated-image-card',
    this.imageKeyPrefix = 'studio-generated-image',
    this.itemKeys = const {},
    this.onOpen,
    this.trailingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : columnWidth;
        final columns = max(1, width ~/ columnWidth);
        return WaterfallFlow.builder(
          key: const ValueKey('studio-generated-image-gallery'),
          primary: false,
          shrinkWrap: !scrollable,
          padding: padding,
          physics: scrollable
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final card = _StudioGeneratedImageCard(
              item: item,
              selected: item.id == selectedId,
              onTap: onOpen == null ? null : () => onOpen!(context, item),
              trailing: trailingBuilder?.call(context, item),
              cardKeyPrefix: cardKeyPrefix,
              imageKeyPrefix: imageKeyPrefix,
            );
            final itemKey = itemKeys[item.id];
            return itemKey == null
                ? card
                : KeyedSubtree(key: itemKey, child: card);
          },
        );
      },
    );
  }
}

class StudioGeneratedImageSliverGallery extends StatelessWidget {
  final List<StudioGeneratedImageItem> items;
  final String? selectedId;
  final double columnWidth;
  final String cardKeyPrefix;
  final String imageKeyPrefix;
  final Map<String, Key> itemKeys;
  final void Function(BuildContext context, StudioGeneratedImageItem item)?
      onOpen;
  final Widget Function(BuildContext context, StudioGeneratedImageItem item)?
      trailingBuilder;

  const StudioGeneratedImageSliverGallery({
    super.key,
    required this.items,
    this.selectedId,
    this.columnWidth = 240,
    this.cardKeyPrefix = 'studio-generated-image-card',
    this.imageKeyPrefix = 'studio-generated-image',
    this.itemKeys = const {},
    this.onOpen,
    this.trailingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = max(1, constraints.crossAxisExtent ~/ columnWidth);
        return SliverWaterfallFlow(
          key: key,
          gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              final card = _StudioGeneratedImageCard(
                item: item,
                selected: item.id == selectedId,
                onTap: onOpen == null ? null : () => onOpen!(context, item),
                trailing: trailingBuilder?.call(context, item),
                cardKeyPrefix: cardKeyPrefix,
                imageKeyPrefix: imageKeyPrefix,
              );
              final itemKey = itemKeys[item.id];
              return itemKey == null
                  ? card
                  : KeyedSubtree(key: itemKey, child: card);
            },
            childCount: items.length,
          ),
        );
      },
    );
  }
}

class _StudioGeneratedImageCard extends StatelessWidget {
  final StudioGeneratedImageItem item;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String cardKeyPrefix;
  final String imageKeyPrefix;

  const _StudioGeneratedImageCard({
    required this.item,
    required this.selected,
    required this.onTap,
    this.trailing,
    required this.cardKeyPrefix,
    required this.imageKeyPrefix,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('$cardKeyPrefix-${item.id}'),
      color:
          selected ? StudioTokens.primary.withAlpha(18) : StudioTokens.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: StudioTokens.radiusCard,
        side: BorderSide(
          color: selected ? StudioTokens.primary : StudioTokens.cardOutline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null)
              _ImageNameRow(item: item, trailing: trailing)
            else
              const SizedBox.shrink(),
            _StudioGeneratedImage(
              item: item,
              imageKey: ValueKey('$imageKeyPrefix-${item.id}'),
            ),
            if (trailing == null) _ImageNameRow(item: item),
          ],
        ),
      ),
    );
  }
}

class _ImageNameRow extends StatelessWidget {
  final StudioGeneratedImageItem item;
  final Widget? trailing;

  const _ImageNameRow({required this.item, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class StudioGeneratedImageViewerDialog extends StatefulWidget {
  final List<StudioGeneratedImageItem> items;
  final String initialItemId;
  final List<Widget> Function(
    BuildContext context,
    StudioGeneratedImageItem item,
  )? actionsBuilder;
  final Widget Function(
    BuildContext context,
    StudioGeneratedImageItem item,
    bool fullscreen,
  )? footerBuilder;
  final Key dialogKey;
  final Key windowedKey;
  final Key fullscreenKey;
  final Key zoomableKey;
  final Key fullscreenButtonKey;
  final bool showFooterInFullscreen;

  const StudioGeneratedImageViewerDialog({
    super.key,
    required this.items,
    required this.initialItemId,
    this.actionsBuilder,
    this.footerBuilder,
    this.dialogKey = const ValueKey('studio-generated-image-viewer-dialog'),
    this.windowedKey = const ValueKey('studio-generated-image-viewer-windowed'),
    this.fullscreenKey =
        const ValueKey('studio-generated-image-viewer-fullscreen'),
    this.zoomableKey = const ValueKey('studio-generated-image-zoomable-viewer'),
    this.fullscreenButtonKey =
        const ValueKey('studio-generated-image-viewer-fullscreen'),
    this.showFooterInFullscreen = true,
  });

  static Future<void> show(
    BuildContext context, {
    required List<StudioGeneratedImageItem> items,
    required String initialItemId,
    List<Widget> Function(BuildContext context, StudioGeneratedImageItem item)?
        actionsBuilder,
    Widget Function(
      BuildContext context,
      StudioGeneratedImageItem item,
      bool fullscreen,
    )? footerBuilder,
    Key dialogKey = const ValueKey('studio-generated-image-viewer-dialog'),
    Key windowedKey = const ValueKey('studio-generated-image-viewer-windowed'),
    Key fullscreenKey =
        const ValueKey('studio-generated-image-viewer-fullscreen'),
    Key zoomableKey = const ValueKey('studio-generated-image-zoomable-viewer'),
    Key fullscreenButtonKey =
        const ValueKey('studio-generated-image-viewer-fullscreen'),
    bool showFooterInFullscreen = true,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => StudioGeneratedImageViewerDialog(
        items: items,
        initialItemId: initialItemId,
        actionsBuilder: actionsBuilder,
        footerBuilder: footerBuilder,
        dialogKey: dialogKey,
        windowedKey: windowedKey,
        fullscreenKey: fullscreenKey,
        zoomableKey: zoomableKey,
        fullscreenButtonKey: fullscreenButtonKey,
        showFooterInFullscreen: showFooterInFullscreen,
      ),
    );
  }

  @override
  State<StudioGeneratedImageViewerDialog> createState() =>
      _StudioGeneratedImageViewerDialogState();
}

class _StudioGeneratedImageViewerDialogState
    extends State<StudioGeneratedImageViewerDialog> {
  static const double _fullscreenChromeRevealHeight = 96;
  static const double _imageTapSlop = 6;

  final FocusNode _focusNode =
      FocusNode(debugLabel: 'studio-generated-image-viewer');
  late int _index = _initialIndex();
  bool _fullscreen = false;
  bool _showFullscreenChrome = false;
  Offset? _imageTapStart;
  bool _imageTapMoved = false;

  StudioGeneratedImageItem get _item => widget.items[_index];

  bool get _canNavigate => widget.items.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    if (_fullscreen) {
      unawaited(_NativeImagePreviewFullscreen.exit());
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: widget.dialogKey,
      insetPadding: _fullscreen ? EdgeInsets.zero : const EdgeInsets.all(24),
      backgroundColor: _fullscreen ? Colors.black : StudioTokens.surfaceBase,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: _fullscreen
            ? SizedBox.expand(child: _buildFullscreen(context))
            : StudioResizableImagePreviewWindow(
                windowKey: widget.windowedKey,
                child: _buildWindowed(context),
              ),
      ),
    );
  }

  Widget _buildWindowed(BuildContext context) {
    final footer = widget.footerBuilder?.call(context, _item, false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioGeneratedImageViewerToolbar(
          item: _item,
          index: _index,
          count: widget.items.length,
          fullscreen: _fullscreen,
          canNavigate: _canNavigate,
          onPrevious: () => _navigate(-1),
          onNext: () => _navigate(1),
          onToggleFullscreen: _toggleFullscreen,
          actions: widget.actionsBuilder?.call(context, _item) ?? const [],
          fullscreenButtonKey: widget.fullscreenButtonKey,
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handleWindowedImagePointerDown,
            onPointerMove: _handleWindowedImagePointerMove,
            onPointerUp: _handleWindowedImagePointerUp,
            onPointerCancel: _handleWindowedImagePointerCancel,
            child: ClipRRect(
              borderRadius: StudioTokens.radiusCard,
              child: _StudioGeneratedZoomableImage(
                item: _item,
                zoomableKey: widget.zoomableKey,
              ),
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 12),
          footer,
        ],
      ],
    );
  }

  Widget _buildFullscreen(BuildContext context) {
    final footer = widget.showFooterInFullscreen
        ? widget.footerBuilder?.call(context, _item, true)
        : null;
    return MouseRegion(
      onHover: _handleFullscreenMouseHover,
      child: Stack(
        key: widget.fullscreenKey,
        children: [
          Positioned.fill(
            child: _StudioGeneratedZoomableImage(
              item: _item,
              fullscreen: true,
              zoomableKey: widget.zoomableKey,
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: IgnorePointer(
              ignoring: !_showFullscreenChrome,
              child: AnimatedOpacity(
                key: const ValueKey('studio-generated-image-viewer-top-chrome'),
                opacity: _showFullscreenChrome ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: _OverlayPanel(
                  child: _StudioGeneratedImageViewerToolbar(
                    item: _item,
                    index: _index,
                    count: widget.items.length,
                    fullscreen: _fullscreen,
                    canNavigate: _canNavigate,
                    onPrevious: () => _navigate(-1),
                    onNext: () => _navigate(1),
                    onToggleFullscreen: _toggleFullscreen,
                    actions:
                        widget.actionsBuilder?.call(context, _item) ?? const [],
                    fullscreenButtonKey: widget.fullscreenButtonKey,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),
          if (footer != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _OverlayPanel(child: footer),
            ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        unawaited(_setFullscreen(false));
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _canNavigate) {
      _navigate(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && _canNavigate) {
      _navigate(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int _initialIndex() {
    final index =
        widget.items.indexWhere((item) => item.id == widget.initialItemId);
    return index < 0 ? 0 : index;
  }

  void _navigate(int delta) {
    if (!_canNavigate) return;
    setState(() {
      _index = (_index + delta) % widget.items.length;
      if (_index < 0) _index = widget.items.length - 1;
    });
  }

  void _toggleFullscreen() {
    unawaited(_setFullscreen(!_fullscreen));
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (_fullscreen == fullscreen) return;
    setState(() {
      _fullscreen = fullscreen;
      _showFullscreenChrome = false;
    });
    if (fullscreen) {
      await _NativeImagePreviewFullscreen.enter();
    } else {
      await _NativeImagePreviewFullscreen.exit();
    }
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void _handleFullscreenMouseHover(PointerHoverEvent event) {
    final shouldShow = event.localPosition.dy <= _fullscreenChromeRevealHeight;
    if (_showFullscreenChrome == shouldShow) return;
    setState(() {
      _showFullscreenChrome = shouldShow;
    });
  }

  void _handleWindowedImagePointerDown(PointerDownEvent event) {
    _imageTapStart = event.localPosition;
    _imageTapMoved = false;
  }

  void _handleWindowedImagePointerMove(PointerMoveEvent event) {
    final start = _imageTapStart;
    if (start == null) return;
    if ((event.localPosition - start).distance > _imageTapSlop) {
      _imageTapMoved = true;
    }
  }

  void _handleWindowedImagePointerUp(PointerUpEvent event) {
    final start = _imageTapStart;
    _imageTapStart = null;
    if (start == null || _imageTapMoved) return;
    if ((event.localPosition - start).distance <= _imageTapSlop) {
      _toggleFullscreen();
    }
  }

  void _handleWindowedImagePointerCancel(PointerCancelEvent event) {
    _imageTapStart = null;
    _imageTapMoved = false;
  }
}

class _StudioGeneratedImageViewerToolbar extends StatelessWidget {
  final StudioGeneratedImageItem item;
  final int index;
  final int count;
  final bool fullscreen;
  final bool canNavigate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onClose;
  final List<Widget> actions;
  final Key fullscreenButtonKey;

  const _StudioGeneratedImageViewerToolbar({
    required this.item,
    required this.index,
    required this.count,
    required this.fullscreen,
    required this.canNavigate,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleFullscreen,
    required this.onClose,
    required this.actions,
    required this.fullscreenButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = fullscreen ? Colors.white : StudioTokens.textPrimary;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('studio-generated-image-viewer-previous'),
          tooltip: '上一张',
          color: textColor,
          onPressed: canNavigate ? onPrevious : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          key: const ValueKey('studio-generated-image-viewer-next'),
          tooltip: '下一张',
          color: textColor,
          onPressed: canNavigate ? onNext : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${item.name}  ${index + 1}/$count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        ...actions,
        const SizedBox(width: 8),
        IconButton(
          key: fullscreenButtonKey,
          tooltip: fullscreen ? '退出全屏' : '全屏',
          color: textColor,
          onPressed: onToggleFullscreen,
          icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
        ),
        IconButton(
          key: const ValueKey('studio-generated-image-viewer-close'),
          tooltip: '关闭',
          color: textColor,
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _StudioGeneratedZoomableImage extends StatefulWidget {
  final StudioGeneratedImageItem item;
  final bool fullscreen;
  final Key zoomableKey;

  const _StudioGeneratedZoomableImage({
    required this.item,
    this.fullscreen = false,
    this.zoomableKey = const ValueKey('studio-generated-image-zoomable-viewer'),
  });

  @override
  State<_StudioGeneratedZoomableImage> createState() =>
      _StudioGeneratedZoomableImageState();
}

class _StudioGeneratedZoomableImageState
    extends State<_StudioGeneratedZoomableImage> {
  static const double _minScale = 1;
  static const double _maxScale = 8;

  final TransformationController _controller = TransformationController();
  String? _layoutKey;
  Matrix4 _fitTransform = Matrix4.identity();
  double _currentMinScale = _minScale;

  @override
  void didUpdateWidget(covariant _StudioGeneratedZoomableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.imagePath != widget.item.imagePath ||
        oldWidget.item.imageBytes != widget.item.imageBytes) {
      _layoutKey = null;
      _fitTransform = Matrix4.identity();
      _currentMinScale = _minScale;
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          max(1.0, constraints.maxWidth),
          max(1.0, constraints.maxHeight),
        );
        final sourceSize = _sourceImageSize(widget.item) ?? viewportSize;
        _currentMinScale = _fitScaleFor(viewportSize, sourceSize);
        _scheduleFitTransform(viewportSize, sourceSize);
        return Listener(
          key: widget.zoomableKey,
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _handlePointerSignal,
          child: InteractiveViewer(
            transformationController: _controller,
            constrained: false,
            alignment: Alignment.topLeft,
            minScale: _currentMinScale,
            maxScale: _maxScale,
            boundaryMargin: const EdgeInsets.all(4096),
            child: SizedBox(
              width: sourceSize.width,
              height: sourceSize.height,
              child: ColoredBox(
                color:
                    widget.fullscreen ? Colors.black : StudioTokens.surfaceBase,
                child: _StudioGeneratedImage(
                  item: widget.item,
                  imageKey: ValueKey(
                    'studio-generated-image-viewer-image-${widget.item.id}',
                  ),
                  width: sourceSize.width,
                  height: sourceSize.height,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    _scaleAt(event.localPosition, delta < 0 ? 1.12 : 0.88);
  }

  void _scaleAt(Offset focalPoint, double scaleFactor) {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * scaleFactor)
        .clamp(_currentMinScale, _maxScale)
        .toDouble();
    if (nextScale <= _currentMinScale + 0.01) {
      _controller.value = _fitTransform.clone();
      return;
    }
    final effectiveScale = nextScale / currentScale;
    final next = _controller.value.clone()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(effectiveScale, effectiveScale, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _controller.value = next;
  }

  void _scheduleFitTransform(Size viewportSize, Size sourceSize) {
    final nextKey = [
      widget.item.id,
      viewportSize.width,
      viewportSize.height,
      sourceSize.width,
      sourceSize.height,
    ].join(':');
    if (_layoutKey == nextKey) return;
    _layoutKey = nextKey;
    _fitTransform = _fitMatrix(viewportSize, sourceSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layoutKey != nextKey) return;
      _controller.value = _fitTransform.clone();
    });
  }
}

class _StudioGeneratedImage extends StatelessWidget {
  final StudioGeneratedImageItem item;
  final Key imageKey;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;

  const _StudioGeneratedImage({
    required this.item,
    required this.imageKey,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = item.imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        key: imageKey,
        width: width ?? double.infinity,
        height: height,
        fit: BoxFit.contain,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stackTrace) =>
            _ImagePlaceholder(item: item, placeholderKey: imageKey),
      );
    }

    final file = _existingImageFile(item.imagePath);
    if (file != null) {
      return Image.file(
        file,
        key: imageKey,
        width: width ?? double.infinity,
        height: height,
        fit: BoxFit.contain,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stackTrace) =>
            _ImagePlaceholder(item: item, placeholderKey: imageKey),
      );
    }

    return _ImagePlaceholder(item: item, placeholderKey: imageKey);
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final StudioGeneratedImageItem item;
  final Key placeholderKey;

  const _ImagePlaceholder({
    required this.item,
    required this.placeholderKey,
  });

  @override
  Widget build(BuildContext context) {
    final text = item.placeholder?.trim();
    return SizedBox(
      key: placeholderKey,
      height: 148,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.image_not_supported_outlined,
                color: StudioTokens.textMuted,
              ),
              if (text != null && text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StudioTokens.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayPanel extends StatelessWidget {
  final Widget child;

  const _OverlayPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(176),
        borderRadius: StudioTokens.radiusCard,
        border: Border.all(color: Colors.white.withAlpha(36)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child,
      ),
    );
  }
}

File? _existingImageFile(String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final file = File(trimmed);
  return file.existsSync() ? file : null;
}

Size? _sourceImageSize(StudioGeneratedImageItem item) {
  try {
    final bytes = item.imageBytes;
    final imageSize = bytes != null
        ? image_size.ImageSizeGetter.getSizeResult(
            image_size.MemoryInput(bytes),
          ).size
        : _sourceFileImageSize(item.imagePath);
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return null;
    }
    return Size(imageSize.width.toDouble(), imageSize.height.toDouble());
  } catch (_) {
    return null;
  }
}

image_size.Size? _sourceFileImageSize(String? imagePath) {
  final file = _existingImageFile(imagePath);
  if (file == null) return null;
  return image_size.ImageSizeGetter.getSizeResult(
    image_size.FileInput(file),
  ).size;
}

double _fitScaleFor(Size viewportSize, Size sourceSize) {
  if (sourceSize.width <= 0 || sourceSize.height <= 0) {
    return _StudioGeneratedZoomableImageState._minScale;
  }
  final scale = min(
    viewportSize.width / sourceSize.width,
    viewportSize.height / sourceSize.height,
  );
  return scale.clamp(0.05, 1.0).toDouble();
}

Matrix4 _fitMatrix(Size viewportSize, Size sourceSize) {
  final scale = _fitScaleFor(viewportSize, sourceSize);
  final dx = (viewportSize.width - sourceSize.width * scale) / 2;
  final dy = (viewportSize.height - sourceSize.height * scale) / 2;
  return Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}
