import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/i2i_config/view_models/i2i_config_viewmodel.dart';
import 'package:nai_casrand/ui/core/utils/flushbar.dart';
import 'package:nai_casrand/ui/core/widgets/editable_list_tile.dart';
import 'package:nai_casrand/ui/core/widgets/slider_list_tile.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class I2iConfigView extends StatelessWidget {
  final I2iVibeViewmodel viewmodel;

  const I2iConfigView({super.key, required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return Column(
          children: [
            _buildImageWidget(context),

            Row(children: [
              Expanded(child: _buildSizeTile(context)),
              Expanded(child: _buildPresetTile(context)),
            ]),
            Row(children: [
              Expanded(child: _buildStrengthTile(context)),
              Expanded(child: _buildNoiseTile(context)),
            ]),
            // Prompt override settings
            CheckboxListTile(
                title: Text(context.tr('override_random_prompts')),
                secondary: const Icon(Icons.edit_note),
                value: viewmodel.config.overridePromptEnabled,
                onChanged: (value) =>
                    viewmodel.setOverridePromptEnabled(value)),
            viewmodel.config.overridePromptEnabled
                ? Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: EditableListTile(
                        title: context.tr('override_prompt'),
                        currentValue: viewmodel.config.overridePrompt,
                        confirmOnSubmit: true,
                        onEditComplete: (value) =>
                            viewmodel.setOverridePrompt(value)))
                : const SizedBox.shrink(),
          ],
        );
      },
    );
  }

  Widget _buildImageWidget(BuildContext context) {
    // Image
    final Widget image;
    if (viewmodel.config.imageB64 == null) {
      image = Icon(Icons.add_photo_alternate_outlined,
          size: viewmodel.imageSize, color: Colors.grey.withAlpha(127));
    } else {
      image = Image.memory(
        base64Decode(viewmodel.config.imageB64!),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }

    void readFailureEvent() {
      showWarningBar(context, context.tr('metadata_not_found'));
    }

    void readSuccessEvent(Map<String, dynamic> parameters) {
      showInfoBar(context, context.tr('metadata_found'));
      _showImportMetadataDialog(context, parameters);
    }

    final dropArea = InkWell(
        key: const ValueKey('workbench-i2i-source-image'),
        onTap: () => viewmodel.addImage(
              context,
              readSuccessEvent,
              readFailureEvent,
            ),
        child: SizedBox(
            width: viewmodel.imageSize + 40.0,
            height: viewmodel.imageSize + 40.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border:
                    Border.all(color: Colors.grey.withAlpha(127), width: 2.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(child: image),
                    Text(context.tr('drag_and_drop_image_notice'))
                  ],
                ),
              ),
            )));

    // Buttons
    final buttons = Row(children: [
      if (viewmodel.config.imageB64 != null)
        Expanded(
            child: IconButton(
                onPressed: viewmodel.removeImage,
                icon: const Icon(Icons.delete_outline)))
    ]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropRegion(
          formats: Formats.standardFormats,
          onDropOver: (_) => DropOperation.copy,
          onPerformDrop: (event) => viewmodel.handleDragEvent(
            event,
            readSuccessEvent,
            readFailureEvent,
          ),
          child: dropArea,
        ),
        buttons,
      ],
    );
  }

  void _showImportMetadataDialog(
      BuildContext context, Map<String, dynamic> parameters) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('import_metadata_from_image')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Text(
              const JsonEncoder.withIndent('  ').convert(parameters),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final count = viewmodel.importMetadataParameters(parameters);
              Navigator.of(dialogContext).pop();
              showInfoBar(
                context,
                context.tr(
                  'loaded_parameters_count',
                  namedArgs: {'num': count.toString()},
                ),
              );
            },
            child: Text(context.tr('import_all_metadata_from_image')),
          ),
        ],
      ),
    );
  }

  Widget _buildSizeTile(BuildContext context) {
    return ListTile(
      title: Text(context.tr('image_size')),
      leading: const Icon(Icons.photo_size_select_large),
      subtitle: Text(viewmodel.getSizeChangeText()),
      onTap: () => _showI2ISizeDialog(context),
    );
  }

  void _showI2ISizeDialog(BuildContext context) {
    final options = viewmodel.getTargetSizeOptions();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('鐩爣鍥惧儚灏哄'),
        content: SizedBox(
          width: 360,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final size = options[index];
              final selected = viewmodel.paramConfig.sizes.contains(size);
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text('${size.width} x ${size.height}'),
                onTap: () {
                  viewmodel.setTargetSize(size);
                  Navigator.of(dialogContext).pop();
                  showInfoBar(
                    context,
                    '鐩爣灏哄宸茶涓?${size.width} x ${size.height}銆?',
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPresetTile(BuildContext context) {
    final presetLevel = viewmodel.getEnhancePresetValue();
    final presetTile = SliderListTile(
      title: context.tr('enhance_presets') +
          context.tr('colon') +
          presetLevel.toInt().toString(),
      leading: const Icon(Icons.tune),
      sliderValue: presetLevel,
      min: 1,
      max: 5,
      divisions: 4,
      onChanged: (value) => viewmodel.setPreset(value),
    );
    return presetTile;
  }

  Widget _buildStrengthTile(BuildContext context) {
    return SliderListTile(
      key: const ValueKey('workbench-i2i-strength-slider'),
      title:
          "鍥剧敓鍥惧己搴?${context.tr('colon')}${viewmodel.config.strength.toStringAsFixed(2)}",
      leading: const Icon(Icons.grain),
      sliderValue: viewmodel.config.strength,
      min: 0.0,
      max: 1.0,
      divisions: 100,
      onChanged: (value) => viewmodel.setStrength(value),
    );
  }

  Widget _buildNoiseTile(BuildContext context) {
    return SliderListTile(
      key: const ValueKey('workbench-i2i-noise-slider'),
      title:
          '鍣０寮哄害${context.tr('colon')}${viewmodel.config.noise.toStringAsFixed(2)}',
      leading: const Icon(Icons.waves),
      sliderValue: viewmodel.config.noise,
      min: 0.0,
      max: 1.0,
      divisions: 100,
      onChanged: (value) => viewmodel.setNoise(value),
    );
  }
}
