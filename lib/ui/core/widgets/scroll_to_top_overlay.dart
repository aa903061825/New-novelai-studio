import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

class ScrollToTopOverlay extends StatefulWidget {
  static const floatingButtonKey = ValueKey('scroll-to-top-floating-button');
  static const showAfterOffset = 160.0;

  final Widget child;

  const ScrollToTopOverlay({
    super.key,
    required this.child,
  });

  @override
  State<ScrollToTopOverlay> createState() => _ScrollToTopOverlayState();
}

class _ScrollToTopOverlayState extends State<ScrollToTopOverlay> {
  static const _buttonExtent = 46.0;
  static const _edgePadding = 22.0;
  static const _defaultBottomPadding = 72.0;

  Offset? _buttonOffset;
  ScrollPosition? _activePosition;
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        final currentOffset = _clampedOffset(_buttonOffset, bounds);

        return NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (_visible)
                Positioned(
                  left: currentOffset.dx,
                  top: currentOffset.dy,
                  child: _FloatingScrollToTopButton(
                    key: ScrollToTopOverlay.floatingButtonKey,
                    onTap: _scrollToTop,
                    onDrag: (delta) {
                      setState(() {
                        _buttonOffset = _clampedOffset(
                          currentOffset + delta,
                          bounds,
                        );
                      });
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final scrollContext = notification.context;
    final scrollable =
        scrollContext == null ? null : Scrollable.maybeOf(scrollContext);
    final position = scrollable?.position;
    if (position == null || !position.hasPixels) {
      return false;
    }

    _activePosition = position;
    final shouldShow = position.pixels > ScrollToTopOverlay.showAfterOffset;
    if (shouldShow != _visible) {
      setState(() {
        _visible = shouldShow;
      });
    }
    return false;
  }

  Future<void> _scrollToTop() async {
    final position = _activePosition;
    if (position == null || !position.hasPixels) {
      _hide();
      return;
    }

    try {
      await position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // A page may have been switched while the float was visible.
    }

    _hide();
  }

  void _hide() {
    if (!mounted || !_visible) return;
    setState(() {
      _visible = false;
    });
  }

  Offset _clampedOffset(Offset? value, Size bounds) {
    final defaultOffset = Offset(
      bounds.width - _buttonExtent - _edgePadding,
      bounds.height - _buttonExtent - _defaultBottomPadding,
    );
    final offset = value ?? defaultOffset;
    final maxX = (bounds.width - _buttonExtent - _edgePadding).clamp(
      _edgePadding,
      double.infinity,
    );
    final maxY = (bounds.height - _buttonExtent - _edgePadding).clamp(
      _edgePadding,
      double.infinity,
    );
    return Offset(
      offset.dx.clamp(_edgePadding, maxX).toDouble(),
      offset.dy.clamp(_edgePadding, maxY).toDouble(),
    );
  }
}

class _FloatingScrollToTopButton extends StatelessWidget {
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;

  const _FloatingScrollToTopButton({
    super.key,
    required this.onTap,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '回到顶部（可拖动）',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanUpdate: (details) => onDrag(details.delta),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _ScrollToTopOverlayState._buttonExtent,
            height: _ScrollToTopOverlayState._buttonExtent,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: StudioTokens.surface3.withValues(alpha: 0.96),
              border: Border.all(
                color: StudioTokens.primary.withValues(alpha: 0.72),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.keyboard_arrow_up_rounded,
              color: StudioTokens.primary,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
