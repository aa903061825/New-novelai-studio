import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/core/widgets/compact_image_config_card.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../viewmodels/precise_reference_item_viewmodel.dart';
import '../viewmodels/precise_reference_list_viewmodel.dart';
import 'precise_reference_item_view.dart';

class PreciseReferenceListView extends StatelessWidget {
  final PreciseReferenceListViewmodel viewmodel;
  final Widget? footer;
  final bool compact;

  const PreciseReferenceListView({
    super.key,
    required this.viewmodel,
    this.footer,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactPreciseReferenceList(
        viewmodel: viewmodel,
        footer: footer,
      );
    }

    final addReferenceImage = Icon(
      Icons.add_photo_alternate_outlined,
      size: 120.0,
      color: Colors.grey.withAlpha(127),
    );

    final addReferenceDropArea = InkWell(
      onTap: () => viewmodel.pickAndAddNewConfig(context),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              addReferenceImage,
              Text(context.tr('drag_and_drop_image_notice')),
            ],
          ),
        ),
      ),
    );

    final pageTipCard = ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(context.tr('precise_reference_tip')),
      dense: true,
    );

    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final itemCount = viewmodel.referenceList.length + 2;
        return ListView.builder(
          itemCount: itemCount + (footer == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (footer != null && index == itemCount) {
              return footer!;
            }

            if (index < viewmodel.referenceList.length) {
              final config = viewmodel.referenceList[index];
              return PreciseReferenceItemView(
                key: ValueKey(config.imageB64),
                viewmodel: PreciseReferenceItemViewmodel(config: config),
                onDelete: () => viewmodel.removeAt(index),
              );
            }
            if (index == viewmodel.referenceList.length) {
              return DropRegion(
                formats: Formats.standardFormats,
                onDropOver: (_) => DropOperation.copy,
                onPerformDrop: (event) => viewmodel.handleDropEvent(
                  context,
                  event,
                ),
                child: addReferenceDropArea,
              );
            }
            return pageTipCard;
          },
        );
      },
    );
  }
}

class _CompactPreciseReferenceList extends StatelessWidget {
  final PreciseReferenceListViewmodel viewmodel;
  final Widget? footer;

  const _CompactPreciseReferenceList({
    required this.viewmodel,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (index, config) in viewmodel.referenceList.indexed)
                  _CompactPreciseReferenceCard(
                    viewmodel: PreciseReferenceItemViewmodel(config: config),
                    onDelete: () => viewmodel.removeAt(index),
                  ),
                DropRegion(
                  formats: Formats.standardFormats,
                  onDropOver: (_) => DropOperation.copy,
                  onPerformDrop: (event) =>
                      viewmodel.handleDropEvent(context, event),
                  child: CompactAddImageCard(
                    onTap: () => viewmodel.pickAndAddNewConfig(context),
                  ),
                ),
              ],
            ),
            if (footer != null) footer!,
          ],
        );
      },
    );
  }
}

class _CompactPreciseReferenceCard extends StatelessWidget {
  final PreciseReferenceItemViewmodel viewmodel;
  final VoidCallback onDelete;

  const _CompactPreciseReferenceCard({
    required this.viewmodel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final thumbnail = viewmodel.imageBytes != null
            ? Image.memory(viewmodel.imageBytes!, fit: BoxFit.cover)
            : const Icon(Icons.broken_image_outlined, size: 36);
        return CompactImageConfigCard(
          height: 210,
          thumbnail: thumbnail,
          fileName: viewmodel.fileName,
          onDelete: onDelete,
          controls: [
            MiniLabeledSlider(
              label: 'S',
              value: viewmodel.strength,
              onChanged: viewmodel.setStrength,
            ),
            MiniLabeledSlider(
              label: 'F',
              value: viewmodel.fidelity,
              onChanged: viewmodel.setFidelity,
            ),
          ],
        );
      },
    );
  }
}
