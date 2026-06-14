import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/core/widgets/compact_image_config_card.dart';
import 'package:nai_casrand/ui/vibe_config/view_models/vibe_config_list_viewmodel.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../view_models/vibe_config_viewmodel.dart';
import 'vibe_config_view.dart';

class VibeConfigListView extends StatelessWidget {
  final VibeConfigListViewmodel viewmodel;
  final bool vibeEnabled;
  final ValueChanged<bool> onVibeEnabledChanged;
  final Widget? footer;
  final bool compact;
  final bool showEnabledSwitch;

  const VibeConfigListView({
    super.key,
    required this.viewmodel,
    required this.vibeEnabled,
    required this.onVibeEnabledChanged,
    this.footer,
    this.compact = false,
    this.showEnabledSwitch = true,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactVibeConfigList(
        viewmodel: viewmodel,
        vibeEnabled: vibeEnabled,
        onVibeEnabledChanged: onVibeEnabledChanged,
        footer: footer,
        showEnabledSwitch: showEnabledSwitch,
      );
    }

    final addVibeImage = Icon(
      Icons.add_photo_alternate_outlined,
      size: 100.0,
      color: Colors.grey.withAlpha(127),
    );

    final addVibeDropArea = InkWell(
      onTap: () => viewmodel.addNewVibe(),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              addVibeImage,
              Text(context.tr('drag_and_drop_image_notice')),
            ],
          ),
        ),
      ),
    );

    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, child) {
        final itemCount = viewmodel.vibeList.length + 2;
        return ListView.builder(
          itemCount: itemCount + (footer == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (footer != null && index == itemCount) {
              return footer!;
            }

            if (index == 0) {
              return SwitchListTile(
                title: Text(context.tr('enable_vibe_transfer')),
                subtitle: Text(context.tr('enable_vibe_transfer_hint')),
                secondary: const Icon(Icons.auto_awesome_outlined),
                value: vibeEnabled,
                onChanged: onVibeEnabledChanged,
              );
            }

            final contentIndex = index - 1;
            final Widget child;
            if (contentIndex < viewmodel.vibeList.length) {
              final config = viewmodel.vibeList[contentIndex];
              // Each item needs its own ViewModel instance
              final itemViewModel = VibeConfigViewmodel(config: config);
              child = VibeConfigView(
                key: ValueKey(config.imageB64),
                viewmodel: itemViewModel,
                onDelete: () => viewmodel.removeConfigAtIndex(contentIndex),
              );
            } else {
              child = DropRegion(
                formats: Formats.standardFormats,
                onDropOver: (_) => DropOperation.copy,
                onPerformDrop: (event) => viewmodel.handleVibeDropEvent(event),
                child: addVibeDropArea,
              );
            }

            return Opacity(
              opacity: vibeEnabled ? 1.0 : 0.45,
              child: IgnorePointer(
                ignoring: !vibeEnabled,
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}

class _CompactVibeConfigList extends StatelessWidget {
  final VibeConfigListViewmodel viewmodel;
  final bool vibeEnabled;
  final ValueChanged<bool> onVibeEnabledChanged;
  final Widget? footer;
  final bool showEnabledSwitch;

  const _CompactVibeConfigList({
    required this.viewmodel,
    required this.vibeEnabled,
    required this.onVibeEnabledChanged,
    required this.footer,
    required this.showEnabledSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showEnabledSwitch)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('enable_vibe_transfer')),
                subtitle: Text(context.tr('enable_vibe_transfer_hint')),
                secondary: const Icon(Icons.auto_awesome_outlined),
                value: vibeEnabled,
                onChanged: onVibeEnabledChanged,
              ),
            Opacity(
              opacity: !showEnabledSwitch || vibeEnabled ? 1 : 0.45,
              child: IgnorePointer(
                ignoring: showEnabledSwitch && !vibeEnabled,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (index, config) in viewmodel.vibeList.indexed)
                      _CompactVibeCard(
                        viewmodel: VibeConfigViewmodel(config: config),
                        onDelete: () => viewmodel.removeConfigAtIndex(index),
                      ),
                    DropRegion(
                      formats: Formats.standardFormats,
                      onDropOver: (_) => DropOperation.copy,
                      onPerformDrop: viewmodel.handleVibeDropEvent,
                      child: CompactAddImageCard(
                        onTap: viewmodel.addNewVibe,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (footer != null) footer!,
          ],
        );
      },
    );
  }
}

class _CompactVibeCard extends StatelessWidget {
  final VibeConfigViewmodel viewmodel;
  final VoidCallback onDelete;

  const _CompactVibeCard({
    required this.viewmodel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return CompactImageConfigCard(
          height: 210,
          thumbnail: Image.memory(
            base64Decode(viewmodel.config.imageB64),
            fit: BoxFit.cover,
          ),
          fileName: viewmodel.fileName,
          onDelete: onDelete,
          controls: [
            MiniLabeledSlider(
              label: 'S',
              value: viewmodel.referenceStrength,
              onChanged: viewmodel.setReferenceStrength,
            ),
            MiniLabeledSlider(
              label: 'I',
              value: viewmodel.infoExtracted,
              onChanged: viewmodel.setInfoExtracted,
            ),
          ],
        );
      },
    );
  }
}
