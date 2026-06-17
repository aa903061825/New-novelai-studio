import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:novel_studio/ui/core/widgets/compact_image_config_card.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';

import '../viewmodels/vibe_config_v4_list_viewmodel.dart';
import '../viewmodels/vibe_config_v4_viewmodel.dart';
import 'vibe_config_v4_view.dart';

class VibeConfigV4ListView extends StatelessWidget {
  final VibeConfigV4ListViewmodel viewmodel;
  final bool vibeEnabled;
  final ValueChanged<bool> onVibeEnabledChanged;
  final Widget? footer;
  final bool compact;
  final bool showEnabledSwitch;

  const VibeConfigV4ListView({
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
      return _CompactVibeConfigV4List(
        viewmodel: viewmodel,
        vibeEnabled: vibeEnabled,
        onVibeEnabledChanged: onVibeEnabledChanged,
        footer: footer,
        showEnabledSwitch: showEnabledSwitch,
      );
    }

    final addVibeImage = Icon(
      Icons.add_photo_alternate_outlined,
      size: 120.0,
      color: Colors.grey.withAlpha(127),
    );

    final addVibeDropArea = InkWell(
      onTap: () => viewmodel.pickAndAddNewConfig(context),
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

    final pageTipCard = ListTile(
      leading: const Icon(Icons.info_outline),
      title: MarkdownBody(
        data: tr('vibe_v4_page_tip'),
        onTapLink: (text, url, title) => launchUrl(
          Uri.parse(url!),
        ),
      ),
      dense: true,
    );

    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, child) {
        final itemCount = viewmodel.vibeList.length + 3;
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
              final itemViewModel = VibeConfigV4Viewmodel(config: config);
              child = VibeConfigV4View(
                key: ValueKey(config.vibeB64),
                viewmodel: itemViewModel,
                onDelete: () => viewmodel.removeConfigAtIndex(contentIndex),
              );
            } else if (contentIndex == viewmodel.vibeList.length) {
              child = DropRegion(
                formats: Formats.standardFormats,
                onDropOver: (_) => DropOperation.copy,
                onPerformDrop: (event) => viewmodel.handleVibeDropEvent(
                  context,
                  event,
                ),
                child: addVibeDropArea,
              );
            } else {
              child = pageTipCard;
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

class _CompactVibeConfigV4List extends StatelessWidget {
  final VibeConfigV4ListViewmodel viewmodel;
  final bool vibeEnabled;
  final ValueChanged<bool> onVibeEnabledChanged;
  final Widget? footer;
  final bool showEnabledSwitch;

  const _CompactVibeConfigV4List({
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
                      _CompactVibeV4Card(
                        viewmodel: VibeConfigV4Viewmodel(config: config),
                        onDelete: () => viewmodel.removeConfigAtIndex(index),
                      ),
                    DropRegion(
                      formats: Formats.standardFormats,
                      onDropOver: (_) => DropOperation.copy,
                      onPerformDrop: (event) =>
                          viewmodel.handleVibeDropEvent(context, event),
                      child: CompactAddImageCard(
                        onTap: () => viewmodel.pickAndAddNewConfig(context),
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

class _CompactVibeV4Card extends StatelessWidget {
  final VibeConfigV4Viewmodel viewmodel;
  final VoidCallback onDelete;

  const _CompactVibeV4Card({
    required this.viewmodel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final imagePath = viewmodel.sourceImagePath;
        final thumbnail = viewmodel.imageBytes != null
            ? Image.memory(viewmodel.imageBytes!, fit: BoxFit.cover)
            : imagePath != null && File(imagePath).existsSync()
                ? Image.file(File(imagePath), fit: BoxFit.cover)
                : const Icon(Icons.broken_image_outlined, size: 36);
        return CompactImageConfigCard(
          height: 186,
          thumbnail: thumbnail,
          fileName: viewmodel.fileName,
          onDelete: onDelete,
          controls: [
            MiniLabeledSlider(
              label: 'S',
              value: viewmodel.referenceStrength,
              onChanged: viewmodel.setReferenceStrength,
            ),
          ],
        );
      },
    );
  }
}
