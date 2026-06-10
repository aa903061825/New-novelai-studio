import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/core/widgets/image_config_row_card.dart';

import '../viewmodels/vibe_config_v4_viewmodel.dart';

class VibeConfigV4View extends StatelessWidget {
  final VibeConfigV4Viewmodel viewmodel;
  final VoidCallback? onDelete; // Callback for delete action

  const VibeConfigV4View({
    super.key,
    required this.viewmodel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = viewmodel.sourceImagePath;
    final thumbnail = viewmodel.imageBytes != null
        ? Image.memory(viewmodel.imageBytes!, fit: BoxFit.cover)
        : imagePath != null && File(imagePath).existsSync()
            ? Image.file(File(imagePath), fit: BoxFit.cover)
            : const Icon(Icons.broken_image_outlined, size: 50);

    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, child) {
        return ImageConfigRowCard(
          thumbnail: thumbnail,
          fileName: viewmodel.fileName,
          onDelete: onDelete,
          sliders: [
            ImageConfigSliderSpec(
              label: 'Strength',
              editTitle: 'Edit Reference Strength',
              editTooltip: 'Edit Strength Value',
              inputLabel: 'Value (0.0 to 1.0)',
              value: viewmodel.referenceStrength,
              onChanged: viewmodel.setReferenceStrength,
            ),
          ],
        );
      },
    );
  }
}
