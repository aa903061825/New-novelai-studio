import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';

const double studioAssetDrawerWidth = 320;
const double studioAssetDrawerGap = 12;
const double studioAssetDrawerHoverInset = 4;

typedef StudioAssetDrawerItemBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  int index,
);

class StudioAssetDrawerShell extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback? onBack;
  final Key? backButtonKey;
  final Key? scrollConfigurationKey;
  final bool suppressScrollbars;
  final IconData homeIcon;
  final Widget child;

  const StudioAssetDrawerShell({
    super.key,
    required this.title,
    required this.count,
    required this.child,
    this.onBack,
    this.backButtonKey,
    this.scrollConfigurationKey,
    this.suppressScrollbars = false,
    this.homeIcon = Icons.inventory_2_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final drawerBody = suppressScrollbars
        ? ScrollConfiguration(
            key: scrollConfigurationKey,
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: child,
          )
        : child;
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(14),
      child: StudioMotionSequenceRegion(
        region: StudioMotionRegion.drawer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StudioAssetDrawerHeader(
              title: title,
              count: count,
              onBack: onBack,
              backButtonKey: backButtonKey,
              homeIcon: homeIcon,
            ),
            const SizedBox(height: 12),
            Expanded(child: drawerBody),
          ],
        ),
      ),
    );
  }
}

class StudioAssetDrawerCategory<T> {
  final T value;
  final String keySuffix;
  final String title;
  final IconData icon;
  final int count;
  final Widget? leading;

  const StudioAssetDrawerCategory({
    required this.value,
    required this.keySuffix,
    required this.title,
    required this.icon,
    required this.count,
    this.leading,
  });
}

class StudioAssetDrawerCardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool enabled;
  final double hoverScale;
  final Offset hoverOffset;
  final Color? hoverBorderColor;
  final Color? hoverOverlayColor;
  final List<BoxShadow>? hoverShadow;
  final BorderRadiusGeometry borderRadius;

  const StudioAssetDrawerCardSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.only(bottom: 8),
    this.enabled = true,
    this.hoverScale = 1,
    this.hoverOffset = Offset.zero,
    this.hoverBorderColor,
    this.hoverOverlayColor,
    this.hoverShadow,
    this.borderRadius = StudioTokens.radiusSlot,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: StudioInteractiveSurface(
        enabled: enabled,
        borderRadius: borderRadius,
        hoverScale: hoverScale,
        hoverOffset: hoverOffset,
        hoverBorderColor:
            hoverBorderColor ?? StudioTokens.primary.withValues(alpha: 0.62),
        hoverOverlayColor:
            hoverOverlayColor ?? StudioTokens.primary.withValues(alpha: 0.075),
        hoverShadow: hoverShadow,
        child: child,
      ),
    );
  }
}

class StudioAssetDrawerCategoryList<T> extends StatelessWidget {
  final List<StudioAssetDrawerCategory<T>> categories;
  final bool revealImmediately;
  final String keyPrefix;
  final ValueChanged<T> onSelect;
  final double hoverScale;
  final Offset hoverOffset;
  final Color? hoverBorderColor;
  final Color? hoverOverlayColor;
  final List<BoxShadow>? hoverShadow;

  const StudioAssetDrawerCategoryList({
    super.key,
    required this.categories,
    required this.keyPrefix,
    required this.onSelect,
    this.revealImmediately = false,
    this.hoverScale = 1.012,
    this.hoverOffset = Offset.zero,
    this.hoverBorderColor,
    this.hoverOverlayColor,
    this.hoverShadow,
  });

  @override
  Widget build(BuildContext context) {
    return StudioAssetDrawerRevealList<StudioAssetDrawerCategory<T>>(
      items: categories,
      revealImmediately: revealImmediately,
      duration: const Duration(milliseconds: 220),
      itemDelay: const Duration(milliseconds: 30),
      beginOffset: const Offset(-0.035, 0.018),
      beginScale: 0.982,
      maxStaggeredItems: 8,
      itemBuilder: (context, category, index) {
        return _StudioAssetDrawerCategoryCard<T>(
          category: category,
          keyPrefix: keyPrefix,
          hoverScale: hoverScale,
          hoverOffset: hoverOffset,
          hoverBorderColor: hoverBorderColor,
          hoverOverlayColor: hoverOverlayColor,
          hoverShadow: hoverShadow,
          onTap: () => onSelect(category.value),
        );
      },
    );
  }
}

class StudioAssetDrawerSearchList<T> extends StatelessWidget {
  final Key searchFieldKey;
  final TextEditingController searchController;
  final List<T> items;
  final Widget emptyState;
  final StudioAssetDrawerItemBuilder<T> itemBuilder;
  final ScrollController? scrollController;
  final String hintText;
  final Duration duration;
  final Duration itemDelay;
  final Offset beginOffset;
  final Alignment alignment;
  final double beginScale;
  final int maxStaggeredItems;

  const StudioAssetDrawerSearchList({
    super.key,
    required this.searchFieldKey,
    required this.searchController,
    required this.items,
    required this.emptyState,
    required this.itemBuilder,
    this.scrollController,
    this.hintText = '搜索当前分类',
    this.duration = const Duration(milliseconds: 230),
    this.itemDelay = const Duration(milliseconds: 28),
    this.beginOffset = const Offset(-0.026, 0.022),
    this.alignment = Alignment.center,
    this.beginScale = 0.978,
    this.maxStaggeredItems = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: searchFieldKey,
          controller: searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: hintText,
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: items.isEmpty
              ? emptyState
              : StudioAssetDrawerRevealList<T>(
                  controller: scrollController,
                  items: items,
                  duration: duration,
                  itemDelay: itemDelay,
                  beginOffset: beginOffset,
                  alignment: alignment,
                  beginScale: beginScale,
                  maxStaggeredItems: maxStaggeredItems,
                  itemBuilder: itemBuilder,
                ),
        ),
      ],
    );
  }
}

class StudioAssetDrawerRevealList<T> extends StatelessWidget {
  final List<T> items;
  final StudioAssetDrawerItemBuilder<T> itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;
  final bool revealImmediately;
  final int columns;
  final int maxStaggeredItems;
  final Duration duration;
  final Duration itemDelay;
  final Offset beginOffset;
  final double beginScale;
  final Alignment alignment;

  const StudioAssetDrawerRevealList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.controller,
    this.padding = const EdgeInsets.all(studioAssetDrawerHoverInset),
    this.revealImmediately = false,
    this.columns = 1,
    this.maxStaggeredItems = 10,
    this.duration = const Duration(milliseconds: 230),
    this.itemDelay = const Duration(milliseconds: 28),
    this.beginOffset = const Offset(-0.026, 0.022),
    this.beginScale = 0.978,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: items.length,
      itemBuilder: (context, index) {
        return StudioStaggeredReveal(
          index: index,
          columns: columns,
          maxStaggeredItems: maxStaggeredItems,
          duration: duration,
          itemDelay: itemDelay,
          beginOffset: beginOffset,
          beginScale: beginScale,
          alignment: alignment,
          initiallyRevealed: revealImmediately,
          child: itemBuilder(context, items[index], index),
        );
      },
    );
  }
}

class StudioAssetDrawerStateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final Color? iconColor;

  const StudioAssetDrawerStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 28,
            color: iconColor ?? StudioTokens.textSecondary,
          ),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}

class _StudioAssetDrawerHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback? onBack;
  final Key? backButtonKey;
  final IconData homeIcon;

  const _StudioAssetDrawerHeader({
    required this.title,
    required this.count,
    required this.homeIcon,
    this.onBack,
    this.backButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack == null)
          Icon(homeIcon, color: StudioTokens.primary)
        else
          StudioIconButton(
            key: backButtonKey,
            tooltip: '返回分类',
            icon: Icons.arrow_back,
            onPressed: onBack,
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text(
          count.toString(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: StudioTokens.primary,
              ),
        ),
      ],
    );
  }
}

class _StudioAssetDrawerCategoryCard<T> extends StatelessWidget {
  final StudioAssetDrawerCategory<T> category;
  final String keyPrefix;
  final double hoverScale;
  final Offset hoverOffset;
  final Color? hoverBorderColor;
  final Color? hoverOverlayColor;
  final List<BoxShadow>? hoverShadow;
  final VoidCallback onTap;

  const _StudioAssetDrawerCategoryCard({
    required this.category,
    required this.keyPrefix,
    required this.hoverScale,
    required this.hoverOffset,
    required this.onTap,
    this.hoverBorderColor,
    this.hoverOverlayColor,
    this.hoverShadow,
  });

  @override
  Widget build(BuildContext context) {
    return StudioAssetDrawerCardSurface(
      padding: const EdgeInsets.only(bottom: 10),
      hoverScale: hoverScale,
      hoverOffset: hoverOffset,
      hoverBorderColor: hoverBorderColor,
      hoverOverlayColor: hoverOverlayColor,
      hoverShadow: hoverShadow,
      child: InkWell(
        key: ValueKey('$keyPrefix-drawer-category-${category.keySuffix}'),
        onTap: onTap,
        borderRadius: StudioTokens.radiusSlot,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StudioTokens.surface3,
            borderRadius: StudioTokens.radiusSlot,
            border: StudioTokens.cardBorder,
          ),
          child: Row(
            children: [
              category.leading ??
                  Icon(
                    category.icon,
                    size: 20,
                    color: StudioTokens.primary,
                  ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                category.count.toString(),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: StudioTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
