import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/core/constants/defaults.dart';
import 'package:nai_casrand/core/constants/parameters.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';
import 'package:nai_casrand/ui/i2i_tab/widgets/i2i_tab_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_generated_image_gallery.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

const _characterCardRadius = BorderRadius.only(
  topLeft: Radius.circular(StudioTokens.radiusSmall),
  topRight: Radius.circular(StudioTokens.radiusSmall),
  bottomLeft: Radius.circular(StudioTokens.radiusSmall),
  bottomRight: Radius.zero,
);

class WorkbenchGenerationResultsPanel extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const WorkbenchGenerationResultsPanel({
    super.key,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('workbench-generation-results-panel'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResultsHeader(viewmodel: viewmodel),
          const SizedBox(height: 10),
          Expanded(child: _GenerationResultList(viewmodel: viewmodel)),
        ],
      ),
    );
  }
}

class WorkbenchCreativeInputsPanel extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;

  const WorkbenchCreativeInputsPanel({
    super.key,
    required this.parametersViewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('workbench-creative-inputs-panel'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.brush_outlined, color: StudioTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '画面输入',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListenableBuilder(
              listenable: parametersViewmodel,
              builder: (context, _) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CharacterSection(viewmodel: parametersViewmodel),
                      const Divider(height: 24),
                      _ReferenceInputSection(viewmodel: parametersViewmodel),
                      const Divider(height: 24),
                      _PromptControlSection(viewmodel: parametersViewmodel),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WorkbenchSingleImageConsole extends StatelessWidget {
  final GenerationPageViewmodel generationViewmodel;
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;
  final StudioWorkbenchAssetService workbenchAssetService;
  final WorkbenchTransferViewModel? transferViewModel;

  const WorkbenchSingleImageConsole({
    super.key,
    required this.generationViewmodel,
    required this.parametersViewmodel,
    required this.workbenchAssetService,
    this.transferViewModel,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('workbench-single-image-console'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConsoleHeader(
            viewmodel: generationViewmodel,
            transferViewModel: transferViewModel,
          ),
          const SizedBox(height: 12),
          _ExecutionSection(
            viewmodel: generationViewmodel,
            parametersViewmodel: parametersViewmodel,
            workbenchAssetService: workbenchAssetService,
            transferViewModel: transferViewModel,
          ),
          const Divider(height: 24),
          Expanded(
            child: ListenableBuilder(
              listenable: parametersViewmodel,
              builder: (context, _) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CoreOutputSection(viewmodel: parametersViewmodel),
                      const Divider(height: 24),
                      _AdvancedSection(viewmodel: parametersViewmodel),
                      const Divider(height: 24),
                      _RandomnessSection(viewmodel: parametersViewmodel),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _ResultsHeader({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return Row(
          children: [
            const Icon(Icons.image_outlined, color: StudioTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '生成结果',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            StudioChip(
              icon: Icons.collections_outlined,
              label: viewmodel.commandList.length.toString(),
            ),
          ],
        );
      },
    );
  }
}

class _ConsoleHeader extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;
  final WorkbenchTransferViewModel? transferViewModel;

  const _ConsoleHeader({
    required this.viewmodel,
    required this.transferViewModel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewmodel,
        viewmodel.commandStatus.isBatchActive,
        viewmodel.commandStatus.isCoolingDown,
        transferViewModel,
      ]),
      builder: (context, _) {
        final active = viewmodel.commandStatus.isBatchActive.value;
        final coolingDown = viewmodel.commandStatus.isCoolingDown.value;
        return Row(
          children: [
            const Icon(Icons.auto_awesome, color: StudioTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '生成控制',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            StudioChip(
              icon: coolingDown
                  ? Icons.hourglass_bottom
                  : active
                      ? Icons.bolt
                      : Icons.radio_button_unchecked,
              label: coolingDown
                  ? '冷却'
                  : active
                      ? '生成中'
                      : '待机',
              selected: active || coolingDown,
              accentColor:
                  coolingDown ? StudioTokens.warning : StudioTokens.active,
            ),
            if (transferViewModel != null) ...[
              const SizedBox(width: 8),
              StudioIconButton(
                key: const ValueKey('workbench-export-action'),
                tooltip: '导出工作台',
                icon: Icons.file_download_outlined,
                onPressed: transferViewModel!.exportToFile,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ExecutionSection extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;
  final StudioWorkbenchAssetService workbenchAssetService;
  final WorkbenchTransferViewModel? transferViewModel;

  const _ExecutionSection({
    required this.viewmodel,
    required this.parametersViewmodel,
    required this.workbenchAssetService,
    required this.transferViewModel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewmodel.commandStatus.isBatchActive,
        viewmodel.commandStatus.isCoolingDown,
      ]),
      builder: (context, _) {
        final active = viewmodel.commandStatus.isBatchActive.value;
        return Row(
          children: [
            Expanded(
              child: StudioButton(
                key: const ValueKey('workbench-start-generation-button'),
                label: active ? '停止生成' : '开始生成',
                icon: active ? Icons.stop : Icons.play_arrow,
                tone:
                    active ? StudioButtonTone.danger : StudioButtonTone.primary,
                onPressed: active
                    ? () => viewmodel.stopBatch()
                    : viewmodel.startSingleImageGeneration,
              ),
            ),
            if (transferViewModel != null) ...[
              const SizedBox(width: 10),
              StudioButton(
                key: const ValueKey('workbench-import-action'),
                label: '导入',
                icon: Icons.file_upload_outlined,
                tone: StudioButtonTone.secondary,
                onPressed: () => transferViewModel!.importFromFile(context),
              ),
            ],
            const SizedBox(width: 10),
            StudioIconButton(
              key: const ValueKey('workbench-reset-action'),
              tooltip: context.tr('reset'),
              icon: Icons.restart_alt,
              onPressed: active
                  ? null
                  : () {
                      workbenchAssetService.resetCreativeState();
                      parametersViewmodel.refreshFromPayload();
                    },
            ),
          ],
        );
      },
    );
  }
}

class _GenerationResultList extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _GenerationResultList({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final itemCount = viewmodel.commandList.length;
        if (itemCount == 0) {
          return Center(
            child: Text(
              '暂无结果',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
          );
        }
        final items = [
          for (var index = itemCount - 1; index >= 0; index -= 1)
            _workbenchGeneratedImageItem(
              viewmodel.commandList[index].value,
              displayIndex: itemCount - index,
              executing: viewmodel.commandList[index].isExecuting.value,
            ),
        ];
        return StudioGeneratedImageGallery(
          items: items,
          columnWidth: 220,
          scrollable: true,
          padding: const EdgeInsets.all(2),
          onOpen: (context, item) {
            StudioGeneratedImageViewerDialog.show(
              context,
              items: items,
              initialItemId: item.id,
            );
          },
        );
      },
    );
  }
}

StudioGeneratedImageItem _workbenchGeneratedImageItem(
  InfoCardContent content, {
  required int displayIndex,
  required bool executing,
}) {
  final title = content.title.toString().trim();
  final order = content.contentOrderText?.toString().trim();
  final nameParts = <String>[
    if (order != null && order.isNotEmpty) order else '#$displayIndex',
    if (title.isNotEmpty) title,
  ];
  final name = nameParts.join(' ');
  final bytes = executing ? null : content.imageBytes;
  if (bytes != null) {
    return StudioGeneratedImageItem.memory(
      id: 'workbench-$displayIndex',
      name: name,
      imageBytes: bytes,
    );
  }
  return StudioGeneratedImageItem(
    id: 'workbench-$displayIndex',
    name: name.isEmpty ? '#$displayIndex' : name,
    placeholder: executing ? '生成中' : '暂无图片',
  );
}

class _CoreOutputSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CoreOutputSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    final samplerOptions = viewmodel.isV4 ? samplersV4 : samplers;
    final noiseOptions = viewmodel.isV4 ? noiseSchedulesV4 : noiseSchedules;

    return Column(
      key: const ValueKey('workbench-core-output-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.tune, title: '出图核心'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const ValueKey('workbench-model-control'),
          initialValue: _safeDropdownValue(config.model, models),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '生成模型',
            prefixIcon: Icon(Icons.auto_awesome_outlined),
          ),
          items: _items(models),
          onChanged: (value) {
            if (value != null) viewmodel.setModel(value);
          },
        ),
        const SizedBox(height: 10),
        _SizeSelector(viewmodel: viewmodel),
        const SizedBox(height: 10),
        _SliderRow(
          key: const ValueKey('workbench-steps-slider'),
          label: 'Steps',
          valueText: config.steps.toString(),
          value: config.steps.toDouble(),
          min: 0,
          max: 28,
          divisions: 28,
          onChanged: (value) => viewmodel.setSteps(value.round()),
        ),
        _SliderRow(
          key: const ValueKey('workbench-scale-slider'),
          label: 'Prompt Guidance',
          valueText: config.scale.toStringAsFixed(1),
          value: config.scale,
          min: 0,
          max: 10,
          divisions: 100,
          onChanged: viewmodel.setScale,
        ),
        _SliderRow(
          key: const ValueKey('workbench-cfg-rescale-slider'),
          label: 'Prompt Guidance Rescale',
          valueText: config.cfgRescale.toStringAsFixed(2),
          value: config.cfgRescale,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: viewmodel.setCfgRescale,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const ValueKey('workbench-sampler-control'),
          initialValue: _safeDropdownValue(config.sampler, samplerOptions),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '采样器',
            prefixIcon: Icon(Icons.manage_search),
          ),
          items: _items(samplerOptions),
          onChanged: (value) {
            if (value != null) viewmodel.setSampler(value);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const ValueKey('workbench-noise-schedule-control'),
          initialValue: _safeDropdownValue(config.noiseSchedule, noiseOptions),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '噪声调度',
            prefixIcon: Icon(Icons.waves),
          ),
          items: _items(noiseOptions),
          onChanged: (value) {
            if (value != null) viewmodel.setNoiseScheduler(value);
          },
        ),
      ],
    );
  }
}

class _SizeSelector extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _SizeSelector({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final selectedSize = viewmodel.selectedSize;
    return Column(
      key: const ValueKey('workbench-size-control'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '图像尺寸',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: StudioTokens.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in defaultSizes)
              ChoiceChip(
                label: Text('${size.width} x ${size.height}'),
                selected: selectedSize == size,
                onSelected: (_) => viewmodel.setSize(size),
              ),
          ],
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: ValueKey('size-${selectedSize.width}-${selectedSize.height}'),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: selectedSize.width.toString(),
                  decoration: const InputDecoration(
                    labelText: '宽度',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (value) => viewmodel.setManualSize(
                    width: value,
                    height: selectedSize.height.toString(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: selectedSize.height.toString(),
                  decoration: const InputDecoration(
                    labelText: '高度',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (value) => viewmodel.setManualSize(
                    width: selectedSize.width.toString(),
                    height: value,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PromptControlSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _PromptControlSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    return Column(
      key: const ValueKey('workbench-prompt-control-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('workbench-negative-prompt-editor'),
          child: PromptTagEditor(
            value: config.negativePrompt,
            label: '负面提示词',
            emptyText: '暂无负面提示词',
            negative: true,
            onChanged: viewmodel.setNegativePrompt,
          ),
        ),
      ],
    );
  }
}

class _ReferenceInputSection extends StatefulWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _ReferenceInputSection({required this.viewmodel});

  @override
  State<_ReferenceInputSection> createState() => _ReferenceInputSectionState();
}

class _ReferenceInputSectionState extends State<_ReferenceInputSection> {
  late bool _i2iEnabled = widget.viewmodel.hasI2iImage;

  @override
  void didUpdateWidget(covariant _ReferenceInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.viewmodel.hasI2iImage && widget.viewmodel.hasI2iImage) {
      _i2iEnabled = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    return ListenableBuilder(
      listenable: viewmodel.payloadConfig.i2iConfig,
      builder: (context, _) {
        final payload = viewmodel.payloadConfig;
        final i2iConfig = payload.i2iConfig;
        final vibeCount =
            payload.vibeConfigList.length + payload.vibeConfigListV4.length;
        final preciseCount = payload.preciseReferenceList.length;
        final hasSourceImage = viewmodel.hasI2iImage;
        final sourceSize = i2iConfig.width > 0 && i2iConfig.height > 0
            ? '${i2iConfig.width} x ${i2iConfig.height}'
            : '已选择';
        final title = !_i2iEnabled
            ? '图生图（可选）'
            : hasSourceImage
                ? '图生图已启用'
                : '图生图已开启';
        final referenceCount = payload.usePreciseReference
            ? preciseCount
            : payload.generationRuntimeState.vibeEnabled
                ? vibeCount
                : 0;
        return Column(
          key: const ValueKey('workbench-reference-input-section'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _SectionTitle(
                      icon: Icons.compare_outlined,
                      title: title,
                    ),
                  ),
                  if (_i2iEnabled) ...[
                    StudioChip(
                      icon: hasSourceImage
                          ? Icons.image_outlined
                          : Icons.add_photo_alternate_outlined,
                      label: hasSourceImage ? '底图 $sourceSize' : '未选择底图',
                      selected: hasSourceImage,
                    ),
                    if (referenceCount > 0) ...[
                      const SizedBox(width: 8),
                      StudioChip(
                        icon: payload.usePreciseReference
                            ? Icons.center_focus_strong_outlined
                            : Icons.auto_awesome_outlined,
                        label: payload.usePreciseReference
                            ? '精确参考 $referenceCount'
                            : '风格参考 $referenceCount',
                        selected: true,
                      ),
                    ],
                    const SizedBox(width: 8),
                  ],
                  StudioChip(
                    key: const ValueKey('workbench-i2i-section-toggle'),
                    icon: _i2iEnabled
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    label: _i2iEnabled ? '关闭' : '开启',
                    selected: _i2iEnabled,
                    onTap: _toggleI2iEnabled,
                  ),
                ],
              ),
            ),
            if (_i2iEnabled) ...[
              const SizedBox(height: 8),
              KeyedSubtree(
                key: const ValueKey('workbench-reference-editor'),
                child: I2iTabView(
                  viewmodel: I2iTabViewmodel(),
                  compact: true,
                  showImageSizeControl: false,
                  showPresetControl: false,
                  useReferenceModeCards: true,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _toggleI2iEnabled() {
    final nextEnabled = !_i2iEnabled;
    if (!nextEnabled) {
      widget.viewmodel.disableI2iInputs();
    }
    setState(() => _i2iEnabled = nextEnabled);
  }
}

class _CharacterSection extends StatefulWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CharacterSection({required this.viewmodel});

  @override
  State<_CharacterSection> createState() => _CharacterSectionState();
}

class _CharacterSectionState extends State<_CharacterSection> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    final characters = viewmodel.payloadConfig.characterConfigList;
    final expandedIndex = _expandedIndex != null &&
            _expandedIndex! >= 0 &&
            _expandedIndex! < characters.length
        ? _expandedIndex
        : null;
    return Column(
      key: const ValueKey('workbench-character-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: _SectionTitle(icon: Icons.group_outlined, title: '角色词'),
            ),
            StudioIconButton(
              key: const ValueKey('workbench-add-character'),
              tooltip: '新增角色',
              icon: Icons.person_add_alt_1_outlined,
              onPressed: characters.length >=
                      WorkbenchSingleImageParametersViewmodel.maxCharacterCount
                  ? null
                  : _addCharacter,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.merge_type),
          title: const Text('手写 Prompt 覆盖时保留角色词'),
          value: viewmodel.payloadConfig.useCharacterPromptWithOverride,
          onChanged: viewmodel.setUseCharacterPromptWithOverride,
        ),
        if (characters.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: StudioTokens.surface3,
              borderRadius: _characterCardRadius,
              border: StudioTokens.cardBorder,
            ),
            child: Text(
              '暂无角色。可以从左侧素材库添加角色，或导入 NovelAI PNG / JSON 解析角色提示词。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final width = _cardWidthFor(constraints.maxWidth, gap);
              return Wrap(
                key: const ValueKey('workbench-character-card-strip'),
                spacing: gap,
                runSpacing: 12,
                children: [
                  for (final (index, character) in characters.indexed)
                    _CharacterTileCard(
                      index: index,
                      width: width,
                      character: character,
                      selected: expandedIndex == index,
                      onTap: () => _selectCharacter(index),
                      onDrop: (data) {
                        viewmodel.applyCharacterDrop(index, data);
                        setState(() => _expandedIndex = index);
                      },
                    ),
                ],
              );
            },
          ),
        if (expandedIndex != null) ...[
          const SizedBox(height: 12),
          _CharacterExpandedCard(
            index: expandedIndex,
            character: characters[expandedIndex],
            viewmodel: viewmodel,
            onRemove: () => _removeCharacter(expandedIndex),
          ),
        ],
      ],
    );
  }

  void _selectCharacter(int index) {
    setState(() {
      _expandedIndex = _expandedIndex == index ? null : index;
    });
  }

  void _addCharacter() {
    final nextIndex = widget.viewmodel.payloadConfig.characterConfigList.length;
    widget.viewmodel.addCharacter();
    setState(() => _expandedIndex = nextIndex);
  }

  void _removeCharacter(int index) {
    setState(() {
      if (_expandedIndex == index) {
        _expandedIndex = null;
      } else if (_expandedIndex != null && _expandedIndex! > index) {
        _expandedIndex = _expandedIndex! - 1;
      }
    });
    widget.viewmodel.removeCharacter(index);
  }

  double _cardWidthFor(double maxWidth, double gap) {
    final available = maxWidth.isFinite ? maxWidth : 852.0;
    final maxCount = WorkbenchSingleImageParametersViewmodel.maxCharacterCount;
    final rawWidth = (available - gap * (maxCount - 1)) / maxCount;
    return rawWidth.clamp(96.0, 132.0).toDouble();
  }
}

class _CharacterTileCard extends StatelessWidget {
  final int index;
  final double width;
  final CharacterConfig character;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<StudioWorkbenchCharacterDropData> onDrop;

  const _CharacterTileCard({
    required this.index,
    required this.width,
    required this.character,
    required this.selected,
    required this.onTap,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    final name = _characterName(character, index);
    final textTheme = Theme.of(context).textTheme;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is StudioWorkbenchCharacterDropData,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is StudioWorkbenchCharacterDropData) {
          onDrop(data);
        }
      },
      builder: (context, candidates, rejected) {
        final dropActive = candidates.isNotEmpty;
        return SizedBox(
          width: width,
          height: 172,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('workbench-character-card-$index'),
              borderRadius: _characterCardRadius,
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dropActive || selected
                      ? StudioTokens.surface2
                      : StudioTokens.surface3,
                  borderRadius: _characterCardRadius,
                  border: Border.all(
                    color: dropActive || selected
                        ? StudioTokens.primary
                        : character.enabled
                            ? StudioTokens.border
                            : StudioTokens.border.withValues(alpha: 0.5),
                    width: dropActive || selected ? 2 : 1,
                  ),
                ),
                child: Opacity(
                  opacity: character.enabled ? 1 : 0.52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            character.enabled
                                ? Icons.person_outline
                                : Icons.person_off_outlined,
                            size: 18,
                            color: selected
                                ? StudioTokens.primary
                                : StudioTokens.textMuted,
                          ),
                          const Spacer(),
                          Icon(
                            selected ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: StudioTokens.textMuted,
                          ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: textTheme.displaySmall?.copyWith(
                              color: selected
                                  ? StudioTokens.primary
                                  : StudioTokens.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: StudioTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _characterName(CharacterConfig character, int index) {
    final name = character.name.trim();
    return name.isEmpty ? '角色 ${index + 1}' : name;
  }
}

class _CharacterExpandedCard extends StatelessWidget {
  final int index;
  final CharacterConfig character;
  final WorkbenchSingleImageParametersViewmodel viewmodel;
  final VoidCallback onRemove;

  const _CharacterExpandedCard({
    required this.index,
    required this.character,
    required this.viewmodel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = _characterName(character, index);
    return Container(
      key: ValueKey('workbench-character-expanded-card-$index'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: _characterCardRadius,
        border: Border.all(
          color: character.enabled
              ? StudioTokens.primary.withValues(alpha: 0.72)
              : StudioTokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StudioChip(
                icon: Icons.person_outline,
                label: name,
                selected: character.enabled,
              ),
              const Spacer(),
              Text(
                character.enabled ? '启用' : '停用',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: character.enabled
                          ? StudioTokens.primary
                          : StudioTokens.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 6),
              Switch(
                value: character.enabled,
                onChanged: (value) =>
                    viewmodel.setCharacterEnabled(index, value),
              ),
              const SizedBox(width: 4),
              StudioIconButton(
                tooltip: '移除角色',
                icon: Icons.close,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('workbench-character-name-$index'),
            initialValue: name,
            maxLines: 1,
            decoration: const InputDecoration(
              labelText: '角色名',
              prefixIcon: Icon(Icons.drive_file_rename_outline),
            ),
            onChanged: (value) => viewmodel.setCharacterName(index, value),
          ),
          const SizedBox(height: 10),
          _CharacterPromptStack(
            characterIndex: index,
            character: character,
            viewmodel: viewmodel,
          ),
        ],
      ),
    );
  }

  String _characterName(CharacterConfig character, int index) {
    final name = character.name.trim();
    return name.isEmpty ? '角色 ${index + 1}' : name;
  }
}

class _CharacterPromptStack extends StatelessWidget {
  final int characterIndex;
  final CharacterConfig character;
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CharacterPromptStack({
    required this.characterIndex,
    required this.character,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = character.positivePromptConfig.strs;
    final displayBlocks = blocks.isEmpty ? const [''] : blocks;
    final tagified = viewmodel.isCharacterPromptTagified(characterIndex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StudioChip(
              icon: Icons.badge_outlined,
              label: 'Prompt 块',
              selected: blocks.isNotEmpty,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '可拖入角色、动作、服装等素材并叠加',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '标签化',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tagified
                        ? StudioTokens.primary
                        : StudioTokens.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Switch(
              key:
                  ValueKey('workbench-character-tagify-toggle-$characterIndex'),
              value: tagified,
              onChanged: (value) =>
                  viewmodel.setCharacterPromptTagified(characterIndex, value),
              activeThumbColor: StudioTokens.primary,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tagified)
          Container(
            key: ValueKey('workbench-character-tagified-tags-$characterIndex'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: StudioTokens.surface2,
              borderRadius: StudioTokens.radiusSlot,
              border: Border.all(color: StudioTokens.primary.withAlpha(180)),
            ),
            child: PromptTagDisplay(
              text: blocks.join(', '),
              defaultTranslated: true,
              dense: true,
              enableTagActions: true,
              emptyText: '当前角色没有可标签化的角色词',
            ),
          )
        else ...[
          _CharacterPromptDropTarget(
            characterIndex: characterIndex,
            targetIndex: 0,
            viewmodel: viewmodel,
          ),
          for (final (blockIndex, block) in displayBlocks.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: [
                  _CharacterPromptBlockDraggable(
                    characterIndex: characterIndex,
                    blockIndex: blockIndex,
                    prompt: block,
                    enabled: blocks.isNotEmpty,
                    child: _CharacterPromptBlockRow(
                      characterIndex: characterIndex,
                      blockIndex: blockIndex,
                      prompt: block,
                      viewmodel: viewmodel,
                      canMoveUp: blocks.isNotEmpty && blockIndex > 0,
                      canMoveDown:
                          blocks.isNotEmpty && blockIndex < blocks.length - 1,
                      canRemove: blocks.isNotEmpty,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _CharacterPromptDropTarget(
                    characterIndex: characterIndex,
                    targetIndex: blockIndex + 1,
                    viewmodel: viewmodel,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _CharacterPromptDropTarget extends StatelessWidget {
  final int characterIndex;
  final int targetIndex;
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CharacterPromptDropTarget({
    required this.characterIndex,
    required this.targetIndex,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is _CharacterPromptBlockDropData) {
          return data.characterIndex == characterIndex;
        }
        return data is StudioWorkbenchCharacterDropData &&
            data.characterPrompt.trim().isNotEmpty;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is _CharacterPromptBlockDropData) {
          viewmodel.moveCharacterPromptBlock(
            characterIndex,
            data.blockIndex,
            targetIndex,
          );
          return;
        }
        if (data is StudioWorkbenchCharacterDropData) {
          viewmodel.insertCharacterPromptBlock(
            characterIndex,
            targetIndex,
            data.characterPrompt,
          );
        }
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          key: ValueKey(
            'workbench-character-prompt-drop-$characterIndex-$targetIndex',
          ),
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          height: active ? 32 : 18,
          decoration: BoxDecoration(
            color: active
                ? StudioTokens.primary.withAlpha(28)
                : StudioTokens.surface2.withAlpha(120),
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: active ? StudioTokens.primary : StudioTokens.cardOutline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            active ? '松开叠加到这里' : '拖到这里',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: active ? StudioTokens.primary : StudioTokens.textMuted,
                ),
          ),
        );
      },
    );
  }
}

class _CharacterPromptBlockDraggable extends StatelessWidget {
  final int characterIndex;
  final int blockIndex;
  final String prompt;
  final bool enabled;
  final Widget child;

  const _CharacterPromptBlockDraggable({
    required this.characterIndex,
    required this.blockIndex,
    required this.prompt,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final label = 'Prompt 块 ${blockIndex + 1}';
    return LongPressDraggable<Object>(
      data: _CharacterPromptBlockDropData(
        characterIndex: characterIndex,
        blockIndex: blockIndex,
        label: label,
        characterPrompt: prompt,
      ),
      feedback: _CharacterPromptDragFeedback(label: label),
      childWhenDragging: Opacity(opacity: 0.38, child: child),
      child: child,
    );
  }
}

class _CharacterPromptBlockDropData
    implements StudioWorkbenchCharacterDropData {
  final int characterIndex;
  final int blockIndex;

  @override
  final String label;

  @override
  final String characterPrompt;

  const _CharacterPromptBlockDropData({
    required this.characterIndex,
    required this.blockIndex,
    required this.label,
    required this.characterPrompt,
  });

  @override
  String get characterName => '';
}

class _CharacterPromptDragFeedback extends StatelessWidget {
  final String label;

  const _CharacterPromptDragFeedback({required this.label});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.primary),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.drag_indicator,
              size: 18,
              color: StudioTokens.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterPromptBlockRow extends StatelessWidget {
  final int characterIndex;
  final int blockIndex;
  final String prompt;
  final WorkbenchSingleImageParametersViewmodel viewmodel;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canRemove;

  const _CharacterPromptBlockRow({
    required this.characterIndex,
    required this.blockIndex,
    required this.prompt,
    required this.viewmodel,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(
        'workbench-character-prompt-block-$characterIndex-$blockIndex',
      ),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StudioChip(
                icon: Icons.auto_awesome_mosaic_outlined,
                label: '块 ${blockIndex + 1}',
              ),
              const Spacer(),
              StudioIconButton(
                key: ValueKey(
                  'workbench-character-prompt-up-$characterIndex-$blockIndex',
                ),
                tooltip: '上移',
                icon: Icons.keyboard_arrow_up,
                onPressed: canMoveUp
                    ? () => viewmodel.moveCharacterPromptBlock(
                          characterIndex,
                          blockIndex,
                          blockIndex - 1,
                        )
                    : null,
              ),
              const SizedBox(width: 6),
              StudioIconButton(
                key: ValueKey(
                  'workbench-character-prompt-down-$characterIndex-$blockIndex',
                ),
                tooltip: '下移',
                icon: Icons.keyboard_arrow_down,
                onPressed: canMoveDown
                    ? () => viewmodel.moveCharacterPromptBlock(
                          characterIndex,
                          blockIndex,
                          blockIndex + 2,
                        )
                    : null,
              ),
              const SizedBox(width: 6),
              StudioIconButton(
                key: ValueKey(
                  'workbench-character-prompt-remove-$characterIndex-$blockIndex',
                ),
                tooltip: '移除',
                icon: Icons.close,
                onPressed: canRemove
                    ? () => viewmodel.removeCharacterPromptBlock(
                          characterIndex,
                          blockIndex,
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _fieldKey,
            child: PromptTagEditor(
              value: prompt,
              label: '角色词',
              dense: true,
              onChanged: (value) => viewmodel.setCharacterPromptBlock(
                characterIndex,
                blockIndex,
                value,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Key get _fieldKey {
    if (blockIndex == 0) {
      return ValueKey('workbench-character-prompt-$characterIndex');
    }
    return ValueKey('workbench-character-prompt-$characterIndex-$blockIndex');
  }
}

class _AdvancedSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _AdvancedSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    return Column(
      key: const ValueKey('workbench-advanced-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.tune_outlined, title: '高级'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.do_not_disturb),
          title: const Text('旧版提示词条件模式'),
          value: config.legacyUc,
          onChanged: viewmodel.setLegacyUc,
        ),
        if (viewmodel.isV4)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.not_listed_location_outlined),
            title: const Text('自动角色位置'),
            value: config.autoPosition,
            onChanged: viewmodel.setAutoPosition,
          ),
        if (!viewmodel.isV4)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.keyboard_double_arrow_right),
            title: const Text('SMEA'),
            value: config.sm,
            onChanged: viewmodel.setSm,
          ),
        if (!viewmodel.isV4)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.keyboard_double_arrow_right),
            title: const Text('SMEA DYN'),
            value: config.smDyn,
            onChanged: viewmodel.setSmDyn,
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.dynamic_form_outlined),
          title: const Text('动态阈值'),
          value: config.dynamicThresholding,
          onChanged: viewmodel.setDynamicThresholding,
        ),
      ],
    );
  }
}

class _RandomnessSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _RandomnessSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    return Column(
      key: const ValueKey('workbench-randomness-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.shuffle, title: '随机性'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.casino_outlined),
          title: const Text('使用随机种子'),
          value: config.randomSeed,
          onChanged: viewmodel.setRandomSeedEnabled,
        ),
        if (!config.randomSeed)
          KeyedSubtree(
            key: ValueKey('seed-${config.seed}'),
            child: TextFormField(
              key: const ValueKey('workbench-seed-field'),
              initialValue: config.seed.toString(),
              decoration: const InputDecoration(
                labelText: '种子',
                prefixIcon: Icon(Icons.tag),
              ),
              keyboardType: TextInputType.number,
              onChanged: viewmodel.setSeed,
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.add),
          title: const Text('Variety+'),
          value: config.varietyPlus,
          onChanged: viewmodel.setVarietyPlus,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: StudioTokens.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: StudioTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(
              valueText,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: StudioTokens.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

List<DropdownMenuItem<String>> _items(List<String> values) {
  return values
      .map(
        (value) => DropdownMenuItem<String>(
          value: value,
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      )
      .toList(growable: false);
}

String? _safeDropdownValue(String value, List<String> options) {
  return options.contains(value) ? value : null;
}
