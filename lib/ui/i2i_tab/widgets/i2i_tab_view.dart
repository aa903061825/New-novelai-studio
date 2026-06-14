import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/i2i_config/widgets/i2i_config_view.dart';
import 'package:nai_casrand/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';
import 'package:nai_casrand/ui/precise_reference/viewmodels/precise_reference_list_viewmodel.dart';
import 'package:nai_casrand/ui/precise_reference/widgets/precise_reference_list_view.dart';
import 'package:nai_casrand/ui/vibe_config/view_models/vibe_config_list_viewmodel.dart';
import 'package:nai_casrand/ui/vibe_config/widgets/vibe_config_list_view.dart';
import 'package:nai_casrand/ui/vibe_config_v4/viewmodels/vibe_config_v4_list_viewmodel.dart';
import 'package:nai_casrand/ui/vibe_config_v4/widgets/vibe_config_v4_list_view.dart';

class I2iTabView extends StatelessWidget {
  final I2iTabViewmodel viewmodel;
  final Widget? footer;
  final bool compact;
  final bool showImageSizeControl;
  final bool showPresetControl;
  final bool useReferenceModeCards;

  const I2iTabView({
    super.key,
    required this.viewmodel,
    this.footer,
    this.compact = false,
    this.showImageSizeControl = true,
    this.showPresetControl = true,
    this.useReferenceModeCards = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final referenceWidget = viewmodel.isV4
            ? viewmodel.usePreciseReference
                ? PreciseReferenceListView(
                    viewmodel: PreciseReferenceListViewmodel(),
                    footer: footer,
                    compact: compact,
                  )
                : VibeConfigV4ListView(
                    viewmodel: VibeConfigV4ListViewmodel(),
                    vibeEnabled:
                        useReferenceModeCards ? true : viewmodel.vibeEnabled,
                    onVibeEnabledChanged: viewmodel.setVibeEnabled,
                    footer: footer,
                    compact: compact,
                    showEnabledSwitch: !useReferenceModeCards,
                  )
            : VibeConfigListView(
                viewmodel: VibeConfigListViewmodel(),
                vibeEnabled:
                    useReferenceModeCards ? true : viewmodel.vibeEnabled,
                onVibeEnabledChanged: viewmodel.setVibeEnabled,
                footer: footer,
                compact: compact,
                showEnabledSwitch: !useReferenceModeCards,
              );

        final i2iConfigView = I2iConfigView(
          key: const ValueKey('workbench-i2i-config-view'),
          viewmodel: viewmodel.createI2iViewmodel(),
          compact: compact,
          showPromptOverride: !compact,
          showSizeControl: showImageSizeControl,
          showPresetControl: showPresetControl,
        );

        if (compact && !viewmodel.isV45) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              i2iConfigView,
              _OptionalReferenceExpansion(
                child: useReferenceModeCards
                    ? _ReferenceModePanel(
                        mode: viewmodel.vibeEnabled
                            ? _ReferenceMode.style
                            : _ReferenceMode.none,
                        preciseAvailable: false,
                        onChanged: (mode) => _setReferenceMode(mode),
                        child: viewmodel.vibeEnabled ? referenceWidget : null,
                      )
                    : referenceWidget,
              ),
            ],
          );
        }

        if (!viewmodel.isV45) {
          return referenceWidget;
        }

        if (compact) {
          final mode = viewmodel.usePreciseReference
              ? _ReferenceMode.precise
              : viewmodel.vibeEnabled
                  ? _ReferenceMode.style
                  : _ReferenceMode.none;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              i2iConfigView,
              _OptionalReferenceExpansion(
                child: useReferenceModeCards
                    ? _ReferenceModePanel(
                        mode: mode,
                        preciseAvailable: true,
                        onChanged: (mode) => _setReferenceMode(mode),
                        child: mode == _ReferenceMode.none
                            ? null
                            : referenceWidget,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(tr('enable_precise_reference')),
                            subtitle: Text(tr('enable_precise_reference_hint')),
                            secondary:
                                const Icon(Icons.auto_fix_high_outlined),
                            value: viewmodel.usePreciseReference,
                            onChanged: (value) =>
                                viewmodel.setUsePreciseReference(value),
                          ),
                          referenceWidget,
                        ],
                      ),
              ),
            ],
          );
        }

        return Column(
          children: [
            SwitchListTile(
              title: Text(tr('enable_precise_reference')),
              subtitle: Text(tr('enable_precise_reference_hint')),
              secondary: const Icon(Icons.auto_fix_high_outlined),
              value: viewmodel.usePreciseReference,
              onChanged: (value) => viewmodel.setUsePreciseReference(value),
            ),
            Expanded(
              child: referenceWidget,
            ),
          ],
        );
      },
    );
  }

  void _setReferenceMode(_ReferenceMode mode) {
    if (mode == _ReferenceMode.precise && !viewmodel.isV45) return;
    switch (mode) {
      case _ReferenceMode.none:
        viewmodel.setUsePreciseReference(false);
        viewmodel.setVibeEnabled(false);
      case _ReferenceMode.style:
        viewmodel.setUsePreciseReference(false);
        viewmodel.setVibeEnabled(true);
      case _ReferenceMode.precise:
        viewmodel.setVibeEnabled(false);
        viewmodel.setUsePreciseReference(true);
    }
  }
}

enum _ReferenceMode { none, style, precise }

class _ReferenceModePanel extends StatelessWidget {
  final _ReferenceMode mode;
  final bool preciseAvailable;
  final ValueChanged<_ReferenceMode> onChanged;
  final Widget? child;

  const _ReferenceModePanel({
    required this.mode,
    required this.preciseAvailable,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 520;
            final cards = [
              _ReferenceModeCard(
                title: '风格参考',
                subtitle: '风格、笔触、氛围',
                icon: Icons.auto_awesome_outlined,
                selected: mode == _ReferenceMode.style,
                onTap: () => onChanged(
                  mode == _ReferenceMode.style
                      ? _ReferenceMode.none
                      : _ReferenceMode.style,
                ),
              ),
              _ReferenceModeCard(
                title: '精确参考',
                subtitle: '角色/物体，仅 V4.5',
                icon: Icons.center_focus_strong_outlined,
                selected: mode == _ReferenceMode.precise,
                enabled: preciseAvailable,
                onTap: () => onChanged(
                  mode == _ReferenceMode.precise
                      ? _ReferenceMode.none
                      : _ReferenceMode.precise,
                ),
              ),
            ];
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final card in cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: card,
                    ),
                ],
              );
            }
            return Row(
              children: [
                for (final card in cards) ...[
                  Expanded(child: card),
                  if (card != cards.last) const SizedBox(width: 10),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          mode == _ReferenceMode.precise
              ? '精确参考会影响角色或物体的一致性，仅 V4.5 可用。'
              : mode == _ReferenceMode.style
                  ? '风格参考和精确参考互斥；这里只保留一种。'
                  : '可选：只在需要风格或角色参考时选择。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (child != null) ...[
          const SizedBox(height: 10),
          child!,
        ],
      ],
    );
  }
}

class _ReferenceModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ReferenceModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = selected ? scheme.primary : scheme.outlineVariant;
    final foreground = enabled
        ? selected
            ? scheme.primary
            : scheme.onSurface
        : scheme.onSurface.withAlpha(96);
    return Material(
      color: selected ? scheme.primary.withAlpha(28) : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface.withAlpha(96),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionalReferenceExpansion extends StatelessWidget {
  final Widget child;

  const _OptionalReferenceExpansion({required this.child});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const ValueKey('workbench-reference-options-expansion'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: const Icon(Icons.image_search_outlined),
      title: const Text('参考图（可选）'),
      subtitle: const Text('风格参考、精确参考需要时再展开'),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: child,
        ),
      ],
    );
  }
}
