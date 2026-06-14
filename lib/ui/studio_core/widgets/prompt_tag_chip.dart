import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/ui/studio_core/theme/prompt_tag_category_style.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

enum PromptTagChipVariant { display, editor }

enum PromptTagChipDiffState { unchanged, added, removed }

class PromptTagChip extends StatelessWidget {
  final String label;
  final String translation;
  final bool translationFirst;
  final String? weightLabel;
  final double? weight;
  final bool loading;
  final String loadingLabel;
  final bool hovered;
  final bool previewed;
  final bool warning;
  final bool selected;
  final bool highlighted;
  final String? highlightTooltip;
  final PromptTagChipDiffState diffState;
  final PromptTagCategory category;
  final bool dense;
  final bool enabled;
  final PromptTagChipVariant variant;
  final double? maxWidth;
  final Key? bodyKey;
  final Key? markerKey;
  final Key? weightKey;
  final Key? deleteKey;
  final Key? checkKey;
  final Key? highlightKey;
  final Key? diffKey;
  final VoidCallback? onDeleted;
  final ValueChanged<bool>? onHoverChanged;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final String deleteTooltip;
  final String? semanticsLabel;

  const PromptTagChip({
    super.key,
    required this.label,
    required this.translation,
    this.translationFirst = false,
    this.weightLabel,
    this.weight,
    this.loading = false,
    this.loadingLabel = '\u7ffb\u8bd1\u4e2d...',
    this.hovered = false,
    this.previewed = false,
    this.warning = false,
    this.selected = false,
    this.highlighted = false,
    this.highlightTooltip,
    this.diffState = PromptTagChipDiffState.unchanged,
    required this.category,
    this.dense = false,
    this.enabled = true,
    this.variant = PromptTagChipVariant.display,
    this.maxWidth,
    this.bodyKey,
    this.markerKey,
    this.weightKey,
    this.deleteKey,
    this.checkKey,
    this.highlightKey,
    this.diffKey,
    this.onDeleted,
    this.onHoverChanged,
    this.onSecondaryTapDown,
    this.onTap,
    this.onDoubleTap,
    this.deleteTooltip = '\u5220\u9664\u6807\u7b7e',
    this.semanticsLabel,
  });

  bool get _isEditor => variant == PromptTagChipVariant.editor;

  bool get _hasDiff => diffState != PromptTagChipDiffState.unchanged;

  Color get _diffColor => switch (diffState) {
        PromptTagChipDiffState.added => StudioTokens.active,
        PromptTagChipDiffState.removed => StudioTokens.danger,
        PromptTagChipDiffState.unchanged => StudioTokens.textPrimary,
      };

  @override
  Widget build(BuildContext context) {
    final trimmedTranslation = translation.trim();
    final hasTranslation = trimmedTranslation.isNotEmpty;
    final showLoading = loading && !hasTranslation;
    final weightText = weightLabel?.trim();
    final hasWeight = weightText != null && weightText.isNotEmpty;
    final isNegativeWeight = (weight ?? 0) < 0;
    final weightColor =
        isNegativeWeight ? StudioTokens.danger : StudioTokens.primary;
    final weightBackgroundColor = weightColor.withAlpha(
      isNegativeWeight ? 30 : 28,
    );
    final weightBorderColor = weightColor.withAlpha(
      isNegativeWeight ? 150 : 120,
    );
    final borderColor = _borderColor();
    final backgroundColor = _backgroundColor();
    final constraints = BoxConstraints(maxWidth: _maxWidth());
    final decoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: StudioTokens.radiusTag,
      border: Border.all(color: borderColor),
      boxShadow: selected
          ? const [
              BoxShadow(
                color: Color(0xCCFFE500),
                blurRadius: 0,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ]
          : null,
    );
    final chipContent = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: DecoratedBox(
            key: markerKey,
            decoration: BoxDecoration(
              color: promptTagCategoryColor(category),
              borderRadius: StudioTokens.radiusTagStripe,
            ),
            child: const SizedBox(width: 3),
          ),
        ),
        if (_isEditor)
          _buildEditorContent(
            context,
            hasTranslation: hasTranslation,
            translationText: trimmedTranslation,
            translationFirst: translationFirst,
            hasWeight: hasWeight,
            weightText: weightText,
            weightColor: weightColor,
            weightBackgroundColor: weightBackgroundColor,
            weightBorderColor: weightBorderColor,
          )
        else
          _buildDisplayContent(
            context,
            hasTranslation: hasTranslation,
            showLoading: showLoading,
            translationText: trimmedTranslation,
            hasWeight: hasWeight,
            weightText: weightText,
            weightColor: weightColor,
            weightBackgroundColor: weightBackgroundColor,
            weightBorderColor: weightBorderColor,
          ),
        if (!_isEditor && !previewed && onDeleted != null)
          _buildOverlayDeleteButton(),
      ],
    );
    final chipBody = previewed
        ? Container(
            key: bodyKey,
            constraints: constraints,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: decoration,
            child: chipContent,
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            key: bodyKey,
            constraints: constraints,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: decoration,
            child: chipContent,
          );
    final chip = Stack(
      clipBehavior: Clip.none,
      children: [
        chipBody,
        if (selected) _buildSelectedCheck(),
        if (highlighted) _buildHighlightBadge(),
      ],
    );
    final hasGesture = onTap != null ||
        onDoubleTap != null ||
        onSecondaryTapDown != null ||
        onHoverChanged != null;
    return MouseRegion(
      cursor: enabled && (hasGesture || _isEditor)
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: onHoverChanged == null ? null : (_) => onHoverChanged!(true),
      onExit: onHoverChanged == null ? null : (_) => onHoverChanged!(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        onDoubleTap: enabled ? onDoubleTap : null,
        onSecondaryTapDown: enabled ? onSecondaryTapDown : null,
        child: Semantics(
          selected: selected,
          button: hasGesture || _isEditor,
          label: semanticsLabel ?? label,
          child: chip,
        ),
      ),
    );
  }

  Widget _buildDisplayContent(
    BuildContext context, {
    required bool hasTranslation,
    required bool showLoading,
    required String translationText,
    required bool hasWeight,
    required String? weightText,
    required Color weightColor,
    required Color weightBackgroundColor,
    required Color weightBorderColor,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        7,
        onDeleted == null ? 11 : (dense ? 28 : 30),
        7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasDiff) ...[
                _buildDiffPrefix(),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (dense
                          ? Theme.of(context).textTheme.labelSmall
                          : Theme.of(context).textTheme.labelMedium)
                      ?.copyWith(
                    color: _hasDiff ? _diffColor : StudioTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    decoration: diffState == PromptTagChipDiffState.removed
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: StudioTokens.danger,
                  ),
                ),
              ),
              if (hasWeight) ...[
                const SizedBox(width: 6),
                _WeightBadge(
                  badgeKey: weightKey,
                  dense: dense,
                  text: weightText!,
                  color: weightColor,
                  backgroundColor: weightBackgroundColor,
                  borderColor: weightBorderColor,
                ),
              ],
            ],
          ),
          if (hasTranslation || showLoading) ...[
            SizedBox(height: dense ? 1 : 2),
            Text(
              hasTranslation ? translationText : loadingLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditorContent(
    BuildContext context, {
    required bool hasTranslation,
    required String translationText,
    required bool translationFirst,
    required bool hasWeight,
    required String? weightText,
    required Color weightColor,
    required Color weightBackgroundColor,
    required Color weightBorderColor,
  }) {
    final primaryText =
        translationFirst && hasTranslation ? translationText : label;
    final secondaryText = translationFirst && hasTranslation
        ? label
        : (hasTranslation ? translationText : null);
    final primaryStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: enabled
              ? (_hasDiff ? _diffColor : StudioTokens.textPrimary)
              : StudioTokens.textMuted,
          fontWeight: FontWeight.w700,
          decoration: diffState == PromptTagChipDiffState.removed
              ? TextDecoration.lineThrough
              : TextDecoration.none,
          decorationColor: StudioTokens.danger,
        );
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: StudioTokens.textSecondary,
        );
    return Padding(
      padding: EdgeInsets.only(
        left: dense ? 12 : 14,
        right: 2,
        top: dense ? 3 : 5,
        bottom: dense ? 3 : 5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasDiff) ...[
                      _buildDiffPrefix(),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        primaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: primaryStyle,
                      ),
                    ),
                    if (hasWeight) ...[
                      const SizedBox(width: 6),
                      _WeightBadge(
                        badgeKey: weightKey,
                        dense: dense,
                        text: weightText!,
                        color: weightColor,
                        backgroundColor: weightBackgroundColor,
                        borderColor: weightBorderColor,
                      ),
                    ],
                  ],
                ),
                if (secondaryText != null) ...[
                  SizedBox(height: dense ? 1 : 2),
                  Text(
                    secondaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondaryStyle,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: deleteKey,
            tooltip: deleteTooltip,
            icon: const Icon(Icons.close),
            iconSize: dense ? 15 : 16,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: dense ? 32 : 36,
              height: dense ? 32 : 36,
            ),
            color: StudioTokens.textMuted,
            onPressed: onDeleted,
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayDeleteButton() {
    return Positioned(
      top: dense ? 1 : 2,
      right: dense ? 1 : 2,
      child: Tooltip(
        message: deleteTooltip,
        child: SizedBox.square(
          dimension: dense ? 22 : 24,
          child: IconButton(
            key: deleteKey,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            iconSize: dense ? 13 : 14,
            color: StudioTokens.textMuted,
            icon: const Icon(Icons.close),
            onPressed: onDeleted,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCheck() {
    return Positioned(
      top: -7,
      right: -6,
      child: DecoratedBox(
        key: checkKey,
        decoration: const BoxDecoration(
          color: StudioTokens.primary,
          shape: BoxShape.circle,
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: Icon(
              Icons.check,
              size: 12,
              color: StudioTokens.onPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightBadge() {
    return Positioned(
      top: -7,
      left: -6,
      child: Tooltip(
        message: highlightTooltip ?? '',
        child: DecoratedBox(
          key: highlightKey,
          decoration: const BoxDecoration(
            color: StudioTokens.info,
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 18,
            height: 18,
            child: Center(
              child: Icon(
                Icons.cached_outlined,
                size: 11,
                color: StudioTokens.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiffPrefix() {
    final (icon, tooltip) = switch (diffState) {
      PromptTagChipDiffState.added => (
          Icons.add_circle_outline,
          '\u65b0\u589e\u63d0\u793a\u8bcd',
        ),
      PromptTagChipDiffState.removed => (
          Icons.remove_circle_outline,
          '\u5220\u9664\u63d0\u793a\u8bcd',
        ),
      PromptTagChipDiffState.unchanged => (
          Icons.circle_outlined,
          '\u672a\u53d8\u63d0\u793a\u8bcd',
        ),
    };
    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        key: diffKey,
        size: dense ? 13 : 14,
        color: _diffColor,
      ),
    );
  }

  Color _borderColor() {
    if (_isEditor) {
      return selected
          ? StudioTokens.primary
          : highlighted
              ? StudioTokens.info
              : _hasDiff
                  ? _diffColor
                  : previewed
                      ? StudioTokens.info
                      : StudioTokens.borderStrong;
    }
    return selected
        ? StudioTokens.primary
        : previewed
            ? StudioTokens.info
            : hovered
                ? StudioTokens.borderStrong
                : _hasDiff
                    ? _diffColor
                    : warning
                        ? StudioTokens.warning
                        : StudioTokens.border;
  }

  Color _backgroundColor() {
    if (_isEditor) {
      return selected
          ? const Color(0xFF22200B)
          : highlighted
              ? const Color(0xFF1F2430)
              : _hasDiff
                  ? _diffColor.withAlpha(22)
                  : previewed
                      ? const Color(0xFF1F2430)
                      : StudioTokens.surface3;
    }
    return selected
        ? const Color(0xFF22200B)
        : previewed
            ? const Color(0xFF1F2430)
            : hovered
                ? const Color(0xFF1C1C1C)
                : _hasDiff
                    ? _diffColor.withAlpha(22)
                    : warning
                        ? const Color(0xFF2B1E12)
                        : const Color(0xFF181818);
  }

  double _maxWidth() {
    final explicit = maxWidth;
    if (explicit != null) {
      return explicit;
    }
    if (_isEditor) {
      return 280;
    }
    return dense ? 210 : 280;
  }
}

class _WeightBadge extends StatelessWidget {
  final Key? badgeKey;
  final bool dense;
  final String text;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const _WeightBadge({
    this.badgeKey,
    required this.dense,
    required this.text,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: badgeKey,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: StudioTokens.radiusBadge,
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 4 : 5,
          vertical: dense ? 1 : 2,
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}
