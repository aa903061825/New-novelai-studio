import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../viewmodels/precise_reference_item_viewmodel.dart';
import '../viewmodels/precise_reference_list_viewmodel.dart';
import 'precise_reference_item_view.dart';

class PreciseReferenceListView extends StatelessWidget {
  final PreciseReferenceListViewmodel viewmodel;

  const PreciseReferenceListView({
    super.key,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
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
        return ListView.builder(
          itemCount: viewmodel.referenceList.length + 2,
          itemBuilder: (context, index) {
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
