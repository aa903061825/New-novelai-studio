import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:novel_studio/ui/core/utils/flushbar.dart';
import 'package:novel_studio/ui/core/widgets/image_config_row_card.dart';
import 'package:novel_studio/ui/vibe_config/view_models/vibe_config_viewmodel.dart';

class VibeConfigView extends StatelessWidget {
  final VibeConfigViewmodel viewmodel;
  final VoidCallback? onDelete;

  const VibeConfigView({
    super.key,
    required this.viewmodel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, child) {
        return ImageConfigRowCard(
          thumbnail: Image.memory(
            base64Decode(viewmodel.config.imageB64),
            fit: BoxFit.cover,
          ),
          fileName: viewmodel.fileName,
          onDelete: onDelete,
          sliders: [
            ImageConfigSliderSpec(
              label: 'Strength',
              editTitle: 'Edit Reference Strength',
              editTooltip: 'Edit Strength Value',
              inputLabel: 'Value',
              value: viewmodel.referenceStrength,
              onChanged: viewmodel.setReferenceStrength,
              allowOutOfRangeDialogValue: true,
            ),
            ImageConfigSliderSpec(
              label: 'Information extracted',
              editTitle: 'Edit Information Extracted',
              editTooltip: 'Edit Information Extracted',
              inputLabel: 'Value (0.0 to 1.0)',
              value: viewmodel.infoExtracted,
              onChanged: viewmodel.setInfoExtracted,
              onInvalidValue: (context, message) =>
                  showErrorBar(context, message),
            ),
          ],
        );
      },
    );
  }
}
