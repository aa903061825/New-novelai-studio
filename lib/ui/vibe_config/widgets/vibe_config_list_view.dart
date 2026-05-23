import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/vibe_config/view_models/vibe_config_list_viewmodel.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../view_models/vibe_config_viewmodel.dart';
import 'vibe_config_view.dart';

class VibeConfigListView extends StatelessWidget {
  final VibeConfigListViewmodel viewmodel;
  final bool vibeEnabled;
  final ValueChanged<bool> onVibeEnabledChanged;

  const VibeConfigListView({
    super.key,
    required this.viewmodel,
    required this.vibeEnabled,
    required this.onVibeEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
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
        return ListView.builder(
          itemCount: viewmodel.vibeList.length + 2,
          itemBuilder: (context, index) {
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
