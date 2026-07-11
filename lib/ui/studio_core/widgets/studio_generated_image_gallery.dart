import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_size_getter/file_input.dart' as image_size;
import 'package:image_size_getter/image_size_getter.dart' as image_size;
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_wheel_zoom.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

const _windowChannel = MethodChannel('novel_studio/window');

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
  final String? leadingLabel;
  final String? imagePath;
  final Uint8List? imageBytes;
  final Object? source;
  final String? placeholder;
  final double? imageHeight;

  const StudioGeneratedImageItem({
    required this.id,
    required this.name,
    this.leadingLabel,
    this.imagePath,
    this.imageBytes,
    this.source,
    this.placeholder,
    this.imageHeight,
  });

  const StudioGeneratedImageItem.file({
    required this.id,
    required this.name,
    this.leadingLabel,
    required String this.imagePath,
    this.source,
    this.placeholder,
    this.imageHeight,
  }) : imageBytes = null;

  const StudioGeneratedImageItem.memory({
    required this.id,
    required this.name,
    this.leadingLabel,
    required Uint8List this.imageBytes,
    this.source,
    this.placeholder,
    this.imageHeight,
  }) : imagePath = null;

  bool get hasImage =>
      imageBytes != null || imagePath?.trim().isNotEmpty == true;
}

const _thumbnailMaxDecodeExtent = 1024;

class StudioGeneratedImageGallery extends StatelessWidget {
  final List<StudioGeneratedImageItem> items;
  final String? selectedId;
  final Set<String> selectedIds;
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
  final Widget Function(BuildContext context, StudioGeneratedImageItem item)?
      imageOverlayBuilder;

  const StudioGeneratedImageGallery({
    super.key,
    required this.items,
    this.selectedId,
    this.selectedIds = const {},
    this.columnWidth = 240,
    this.scrollable = false,
    this.padding = EdgeInsets.zero,
    this.cardKeyPrefix = 'studio-generated-image-card',
    this.imageKeyPrefix = 'studio-generated-image',
    this.itemKeys = const {},
    this.onOpen,
    this.trailingBuilder,
    this.imageOverlayBuilder,
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
              selected: item.id == selectedId || selectedIds.contains(item.id),
              onTap: onOpen == null ? null : () => onOpen!(context, item),
              trailing: trailingBuilder?.call(context, item),
              imageOverlay: imageOverlayBuilder?.call(context, item),
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
  final Set<String> selectedIds;
  final double columnWidth;
  final String cardKeyPrefix;
  final String imageKeyPrefix;
  final Map<String, Key> itemKeys;
  final void Function(BuildContext context, StudioGeneratedImageItem item)?
      onOpen;
  final Widget Function(BuildContext context, StudioGeneratedImageItem item)?
      trailingBuilder;
  final Widget Function(BuildContext context, StudioGeneratedImageItem item)?
      imageOverlayBuilder;

  const StudioGeneratedImageSliverGallery({
    super.key,
    required this.items,
    this.selectedId,
    this.selectedIds = const {},
    this.columnWidth = 240,
    this.cardKeyPrefix = 'studio-generated-image-card',
    this.imageKeyPrefix = 'studio-generated-image',
    this.itemKeys = const {},
    this.onOpen,
    this.trailingBuilder,
    this.imageOverlayBuilder,
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
                selected:
                    item.id == selectedId || selectedIds.contains(item.id),
                onTap: onOpen == null ? null : () => onOpen!(context, item),
                trailing: trailingBuilder?.call(context, item),
                imageOverlay: imageOverlayBuilder?.call(context, item),
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
  final Widget? imageOverlay;
  final String cardKeyPrefix;
  final String imageKeyPrefix;

  const _StudioGeneratedImageCard({
    required this.item,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.imageOverlay,
    required this.cardKeyPrefix,
    required this.imageKeyPrefix,
  });

  @override
  Widget build(BuildContext context) {
    return StudioInteractiveSurface(
      child: Material(
        key: ValueKey('$cardKeyPrefix-${item.id}'),
        color: selected
            ? StudioTokens.primary.withAlpha(18)
            : StudioTokens.surface2,
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
              Stack(
                children: [
                  _StudioGeneratedImage(
                    item: item,
                    imageKey: ValueKey('$imageKeyPrefix-${item.id}'),
                    height: item.imageHeight,
                    filterQuality: FilterQuality.low,
                    maxDecodeExtent: _thumbnailMaxDecodeExtent,
                  ),
                  if (imageOverlay != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: imageOverlay!,
                      ),
                    ),
                ],
              ),
              if (trailing == null) _ImageNameRow(item: item),
            ],
          ),
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
          if (item.leadingLabel != null) ...[
            Text(
              item.leadingLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: StudioTokens.primary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(width: 6),
          ],
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
  final bool wheelNavigationEnabled;
  final Map<String, List<String>> wheelNavigationScopeIdsByItemId;
  final Future<void> Function(String path)? revealInFileManager;

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
    this.wheelNavigationEnabled = false,
    this.wheelNavigationScopeIdsByItemId = const {},
    this.revealInFileManager,
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
    bool wheelNavigationEnabled = false,
    Map<String, List<String>> wheelNavigationScopeIdsByItemId = const {},
    Future<void> Function(String path)? revealInFileManager,
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
        wheelNavigationEnabled: wheelNavigationEnabled,
        wheelNavigationScopeIdsByItemId: wheelNavigationScopeIdsByItemId,
        revealInFileManager: revealInFileManager,
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

  bool get _canNavigate => _linearNavigationIndexes.length > 1;

  bool get _canWheelNavigate =>
      widget.wheelNavigationEnabled &&
      _wheelNavigationIndexesForCurrentItem().length > 1;

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
          index: _linearNavigationIndex,
          count: _linearNavigationCount,
          fullscreen: _fullscreen,
          canNavigate: _canNavigate,
          onPrevious: () => _navigate(-1),
          onNext: () => _navigate(1),
          onToggleFullscreen: _toggleFullscreen,
          onRevealInFileManager: _revealActionForCurrentItem(context),
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _StudioGeneratedZoomableImage(
                    item: _item,
                    zoomableKey: widget.zoomableKey,
                    onWheelNavigation:
                        _canWheelNavigate ? _navigateWheel : null,
                  ),
                  if (_navigationDotCount > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: _StudioGeneratedVariantDots(
                        key: const ValueKey(
                          'studio-generated-image-viewer-dots',
                        ),
                        index: _navigationDotIndex,
                        count: _navigationDotCount,
                      ),
                    ),
                ],
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                _StudioGeneratedZoomableImage(
                  item: _item,
                  fullscreen: true,
                  zoomableKey: widget.zoomableKey,
                  onWheelNavigation: _canWheelNavigate ? _navigateWheel : null,
                ),
                if (_navigationDotCount > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 18,
                    child: _StudioGeneratedVariantDots(
                      key: const ValueKey(
                        'studio-generated-image-viewer-dots-fullscreen',
                      ),
                      index: _navigationDotIndex,
                      count: _navigationDotCount,
                    ),
                  ),
              ],
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
                    index: _linearNavigationIndex,
                    count: _linearNavigationCount,
                    fullscreen: _fullscreen,
                    canNavigate: _canNavigate,
                    onPrevious: () => _navigate(-1),
                    onNext: () => _navigate(1),
                    onToggleFullscreen: _toggleFullscreen,
                    onRevealInFileManager: _revealActionForCurrentItem(context),
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
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _canWheelNavigate) {
      _navigateWheel(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _canWheelNavigate) {
      _navigateWheel(1);
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
    final indexes = _linearNavigationIndexes;
    if (indexes.length <= 1) return;
    final currentGroupKey = _navigationGroupKey(_item);
    var localIndex = indexes.indexWhere(
      (index) => _navigationGroupKey(widget.items[index]) == currentGroupKey,
    );
    if (localIndex < 0) {
      localIndex = indexes.indexOf(_index);
    }
    if (localIndex < 0) {
      return;
    }
    var nextLocalIndex = (localIndex + delta) % indexes.length;
    if (nextLocalIndex < 0) {
      nextLocalIndex += indexes.length;
    }
    setState(() {
      _index = indexes[nextLocalIndex];
    });
  }

  void _navigateWheel(int delta) {
    final indexes = _wheelNavigationIndexesForCurrentItem();
    if (indexes.length <= 1) return;
    final localIndex = indexes.indexOf(_index);
    if (localIndex < 0) return;
    var nextLocalIndex = (localIndex + delta) % indexes.length;
    if (nextLocalIndex < 0) {
      nextLocalIndex += indexes.length;
    }
    setState(() {
      _index = indexes[nextLocalIndex];
    });
  }

  int get _navigationDotCount => _navigationDotIndexes.length;

  int get _navigationDotIndex {
    final indexes = _navigationDotIndexes;
    final localIndex = indexes.indexOf(_index);
    return localIndex < 0 ? _index : localIndex;
  }

  List<int> get _navigationDotIndexes {
    final wheelIndexes = _wheelNavigationIndexesForCurrentItem();
    if (widget.wheelNavigationScopeIdsByItemId.isNotEmpty &&
        wheelIndexes.length > 1) {
      return wheelIndexes;
    }
    return [for (var index = 0; index < widget.items.length; index += 1) index];
  }

  List<int> _wheelNavigationIndexesForCurrentItem() {
    final scopeIds = widget.wheelNavigationScopeIdsByItemId.isEmpty
        ? [for (final item in widget.items) item.id]
        : widget.wheelNavigationScopeIdsByItemId[_item.id] ?? [_item.id];
    final indexes = <int>[];
    final seen = <String>{};
    for (final itemId in scopeIds) {
      if (!seen.add(itemId)) continue;
      final index = widget.items.indexWhere((item) => item.id == itemId);
      if (index >= 0) {
        indexes.add(index);
      }
    }
    return indexes;
  }

  int get _linearNavigationCount => _linearNavigationIndexes.length;

  int get _linearNavigationIndex {
    final indexes = _linearNavigationIndexes;
    final currentGroupKey = _navigationGroupKey(_item);
    final localIndex = indexes.indexWhere(
      (index) => _navigationGroupKey(widget.items[index]) == currentGroupKey,
    );
    return localIndex < 0 ? _index : localIndex;
  }

  List<int> get _linearNavigationIndexes {
    if (widget.wheelNavigationScopeIdsByItemId.isEmpty) {
      return [
        for (var index = 0; index < widget.items.length; index += 1) index
      ];
    }
    final indexes = <int>[];
    final seen = <String>{};
    for (var index = 0; index < widget.items.length; index += 1) {
      final key = _navigationGroupKey(widget.items[index]);
      if (seen.add(key)) {
        indexes.add(index);
      }
    }
    return indexes;
  }

  String _navigationGroupKey(StudioGeneratedImageItem item) {
    if (widget.wheelNavigationScopeIdsByItemId.isEmpty) {
      return 'item:${item.id}';
    }
    final scopeIds = widget.wheelNavigationScopeIdsByItemId[item.id];
    if (scopeIds == null || scopeIds.isEmpty) {
      return 'item:${item.id}';
    }
    final seen = <String>{};
    final normalized = [
      for (final id in scopeIds)
        if (seen.add(id)) id,
    ];
    return 'scope:${normalized.join('\u001f')}';
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

  VoidCallback? _revealActionForCurrentItem(BuildContext context) {
    final file = _existingImageFile(_item.imagePath);
    if (file == null) return null;
    return () {
      unawaited(_revealInFileManager(context, file.path));
    };
  }

  Future<void> _revealInFileManager(BuildContext context, String path) async {
    try {
      await (widget.revealInFileManager ?? FileService().revealInFileManager)(
        path,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
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
  final VoidCallback? onRevealInFileManager;
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
    required this.onRevealInFileManager,
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
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('studio-generated-image-viewer-reveal-file'),
          tooltip: '在资源管理器中显示',
          color: textColor,
          onPressed: onRevealInFileManager,
          icon: const Icon(Icons.folder_open_outlined),
        ),
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

class _StudioGeneratedVariantDots extends StatelessWidget {
  final int index;
  final int count;

  const _StudioGeneratedVariantDots({
    super.key,
    required this.index,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final dotCount = min(count, 9);
    final activeIndex = count <= dotCount
        ? index.clamp(0, dotCount - 1)
        : ((index / count) * dotCount).floor().clamp(0, dotCount - 1);
    return Center(
      child: Semantics(
        label: '图片 ${index + 1}/$count',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var dot = 0; dot < dotCount; dot += 1) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: dot == activeIndex ? 8 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: dot == activeIndex
                          ? StudioTokens.primary
                          : Colors.white.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  if (dot != dotCount - 1) const SizedBox(width: 4),
                ],
                if (count > dotCount) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudioGeneratedZoomableImage extends StatefulWidget {
  final StudioGeneratedImageItem item;
  final bool fullscreen;
  final Key zoomableKey;
  final ValueChanged<int>? onWheelNavigation;

  const _StudioGeneratedZoomableImage({
    required this.item,
    this.fullscreen = false,
    this.zoomableKey = const ValueKey('studio-generated-image-zoomable-viewer'),
    this.onWheelNavigation,
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
  late final StudioWheelZoomController _wheelZoom = StudioWheelZoomController(
    transformationController: _controller,
    minScale: _currentMinScale,
    maxScale: _maxScale,
    resetTransform: () => _fitTransform.clone(),
    requireControlModifier: true,
  );
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
      _wheelZoom.minScale = _currentMinScale;
      _wheelZoom.reset();
    }
  }

  @override
  void dispose() {
    _wheelZoom.dispose();
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
        _wheelZoom.minScale = _currentMinScale;
        _wheelZoom.maxScale = _maxScale;
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
                  filterQuality: FilterQuality.medium,
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
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scrollEvent = event as PointerScrollEvent;
      if (_wheelZoom.handlePointerSignal(scrollEvent)) {
        return;
      }
      final navigate = widget.onWheelNavigation;
      if (navigate == null) return;
      final delta = scrollEvent.scrollDelta.dy == 0
          ? scrollEvent.scrollDelta.dx
          : scrollEvent.scrollDelta.dy;
      if (delta == 0) return;
      navigate(delta > 0 ? 1 : -1);
    });
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
    _controller.value = _fitTransform.clone();
  }
}

class _StudioGeneratedImage extends StatelessWidget {
  final StudioGeneratedImageItem item;
  final Key imageKey;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final int? maxDecodeExtent;

  const _StudioGeneratedImage({
    required this.item,
    required this.imageKey,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.medium,
    this.maxDecodeExtent,
  });

  @override
  Widget build(BuildContext context) {
    final sourceSize = _sourceImageSize(item);
    final effectiveHeight = sourceSize == null ? height : null;
    final bytes = item.imageBytes;
    if (bytes != null) {
      return _NaturalAspectRatio(
        sourceSize: sourceSize,
        child: Image.memory(
          bytes,
          key: imageKey,
          width: width ?? double.infinity,
          height: effectiveHeight,
          fit: BoxFit.contain,
          filterQuality: filterQuality,
          errorBuilder: (context, error, stackTrace) =>
              _ImagePlaceholder(item: item, placeholderKey: imageKey),
        ),
      );
    }

    final file = _imageFile(item.imagePath);
    if (file != null) {
      final maxDecodeExtent = this.maxDecodeExtent;
      if (maxDecodeExtent == null) {
        return _NaturalAspectRatio(
          sourceSize: sourceSize,
          child: Image.file(
            file,
            key: imageKey,
            width: width ?? double.infinity,
            height: effectiveHeight,
            fit: BoxFit.contain,
            filterQuality: filterQuality,
            errorBuilder: (context, error, stackTrace) =>
                _ImagePlaceholder(item: item, placeholderKey: imageKey),
          ),
        );
      }
      return _NaturalAspectRatio(
        sourceSize: sourceSize,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            final cacheWidth = _cacheImageExtentFor(
              width ?? constraints.maxWidth,
              devicePixelRatio,
              maxExtent: maxDecodeExtent,
            );
            final cacheHeight = _cacheImageExtentFor(
              effectiveHeight ?? constraints.maxHeight,
              devicePixelRatio,
              maxExtent: maxDecodeExtent,
            );
            return Image(
              key: imageKey,
              image: ResizeImage(
                FileImage(file),
                width: cacheWidth,
                height: cacheHeight,
                policy: ResizeImagePolicy.fit,
              ),
              width: width ?? double.infinity,
              height: effectiveHeight,
              fit: BoxFit.contain,
              filterQuality: filterQuality,
              errorBuilder: (context, error, stackTrace) =>
                  _ImagePlaceholder(item: item, placeholderKey: imageKey),
            );
          },
        ),
      );
    }

    return _ImagePlaceholder(item: item, placeholderKey: imageKey);
  }
}

class _NaturalAspectRatio extends StatelessWidget {
  final Size? sourceSize;
  final Widget child;

  const _NaturalAspectRatio({
    required this.sourceSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = sourceSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return child;
    }
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: child,
    );
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
      height: item.imageHeight ?? 148,
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
  final file = _imageFile(path);
  if (file == null) return null;
  try {
    return file.existsSync() ? file : null;
  } catch (_) {
    return null;
  }
}

File? _imageFile(String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  try {
    return File(trimmed);
  } catch (_) {
    return null;
  }
}

int? _cacheImageExtentFor(
  double extent,
  double devicePixelRatio, {
  required int maxExtent,
}) {
  if (!extent.isFinite || extent <= 0 || devicePixelRatio <= 0) {
    return null;
  }
  return (extent * devicePixelRatio).ceil().clamp(1, maxExtent).toInt();
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
