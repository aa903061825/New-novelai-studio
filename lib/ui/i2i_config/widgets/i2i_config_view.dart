import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:novel_studio/ui/i2i_config/view_models/i2i_config_viewmodel.dart';
import 'package:novel_studio/ui/core/utils/flushbar.dart';
import 'package:novel_studio/ui/core/widgets/editable_list_tile.dart';
import 'package:novel_studio/ui/core/widgets/slider_list_tile.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class I2iConfigView extends StatelessWidget {
  final I2iVibeViewmodel viewmodel;
  final bool compact;
  final bool showPromptOverride;
  final bool showSizeControl;
  final bool showPresetControl;

  const I2iConfigView({
    super.key,
    required this.viewmodel,
    this.compact = false,
    this.showPromptOverride = true,
    this.showSizeControl = true,
    this.showPresetControl = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildImageWidget(context),
            _buildControlGrid(context),
            if (showPromptOverride) ...[
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
          ],
        );
      },
    );
  }

  Widget _buildImageWidget(BuildContext context) {
    final hasImage = viewmodel.config.imageB64 != null;
    final imageSize = compact ? 220.0 : viewmodel.imageSize;

    final Widget image;
    if (!hasImage) {
      image = Icon(
        Icons.add_photo_alternate_outlined,
        size: compact ? 92 : 160,
        color: Colors.grey.withAlpha(127),
      );
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

    Future<void> pickImage() => viewmodel.addImage(
          context,
          readSuccessEvent,
          readFailureEvent,
        );

    final sourceSize = viewmodel.config.width > 0 && viewmodel.config.height > 0
        ? '${viewmodel.config.width} x ${viewmodel.config.height}'
        : '已选择';

    final dropArea = InkWell(
      key: const ValueKey('workbench-i2i-source-image'),
      borderRadius: BorderRadius.circular(8),
      onTap: pickImage,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: imageSize + 56,
            minHeight: imageSize + 92,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasImage
                    ? Theme.of(context).colorScheme.primary.withAlpha(190)
                    : Colors.grey.withAlpha(127),
                width: hasImage ? 2.0 : 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: imageSize,
                    child: Center(child: image),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasImage ? '图生图底图' : '选择图生图底图',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasImage ? sourceSize : 'PNG / JPG / WebP',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('drag_and_drop_image_notice'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final buttons = Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const ValueKey('workbench-i2i-pick-image-button'),
          onPressed: pickImage,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(hasImage ? '更换底图' : '选择底图'),
        ),
        if (hasImage)
          OutlinedButton.icon(
            key: const ValueKey('workbench-i2i-clear-image-button'),
            onPressed: viewmodel.removeImage,
            icon: const Icon(Icons.delete_outline),
            label: const Text('清除底图'),
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        const SizedBox(height: 10),
        buttons,
      ],
    );
  }

  Widget _buildControlGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        final controls = [
          if (showSizeControl) _buildSizeTile(context),
          if (showPresetControl) _buildPresetTile(context),
          _buildStrengthTile(context),
          _buildNoiseTile(context),
        ];
        if (narrow) {
          return Column(
            children: controls,
          );
        }
        return Column(
          children: [
            for (var index = 0; index < controls.length; index += 2)
              Row(
                children: [
                  Expanded(child: controls[index]),
                  if (index + 1 < controls.length)
                    Expanded(child: controls[index + 1])
                  else
                    const Spacer(),
                ],
              ),
          ],
        );
      },
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
        title: const Text('目标图像尺寸'),
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
                    '目标尺寸已设为 ${size.width} x ${size.height}。',
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
          "重绘强度${context.tr('colon')}${viewmodel.config.strength.toStringAsFixed(2)}",
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
          '噪声强度${context.tr('colon')}${viewmodel.config.noise.toStringAsFixed(2)}',
      leading: const Icon(Icons.waves),
      sliderValue: viewmodel.config.noise,
      min: 0.0,
      max: 1.0,
      divisions: 100,
      onChanged: (value) => viewmodel.setNoise(value),
    );
  }
}
