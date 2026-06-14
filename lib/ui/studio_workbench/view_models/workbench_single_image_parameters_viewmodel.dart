import 'package:flutter/foundation.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/generation_size.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';

class WorkbenchSingleImageParametersViewmodel extends ChangeNotifier {
  static const maxCharacterCount = 6;

  final PayloadConfig payloadConfig;
  final Map<int, List<String>> _characterPromptTagifiedBackups = {};
  final Set<int> _tagifiedCharacterIndexes = {};

  WorkbenchSingleImageParametersViewmodel(this.payloadConfig);

  ParamConfig get config => payloadConfig.paramConfig;

  bool get isV4 => config.model.contains('-4-');

  GenerationSize get selectedSize => config.sizes.first;

  int get referenceCount =>
      payloadConfig.vibeConfigList.length +
      payloadConfig.vibeConfigListV4.length +
      payloadConfig.preciseReferenceList.length +
      (payloadConfig.i2iConfig.imageB64 == null ? 0 : 1);

  bool get hasI2iImage => payloadConfig.i2iConfig.imageB64 != null;

  void disableI2iInputs() {
    payloadConfig.i2iConfig.clearImage();
    payloadConfig.generationRuntimeState.vibeEnabled = false;
    payloadConfig.usePreciseReference = false;
    notifyListeners();
  }

  int get characterCount => payloadConfig.characterConfigList.length;

  bool isCharacterPromptTagified(int index) =>
      _tagifiedCharacterIndexes.contains(index);

  void refreshFromPayload() {
    _characterPromptTagifiedBackups.clear();
    _tagifiedCharacterIndexes.clear();
    notifyListeners();
  }

  void setModel(String value) {
    config.model = value;
    notifyListeners();
  }

  void setManualSize({
    required String width,
    required String height,
  }) {
    final parsedWidth = int.tryParse(width);
    final parsedHeight = int.tryParse(height);
    if (parsedWidth == null || parsedHeight == null) return;
    if (parsedWidth <= 0 || parsedHeight <= 0) return;

    config.sizes = [
      GenerationSize(
        width: _roundToGenerationMultiple(parsedWidth),
        height: _roundToGenerationMultiple(parsedHeight),
      ),
    ];
    notifyListeners();
  }

  void setSize(GenerationSize size) {
    config.sizes = [size];
    notifyListeners();
  }

  void setSteps(int value) {
    config.steps = value.clamp(0, 28);
    notifyListeners();
  }

  void setScale(double value) {
    config.scale = value.clamp(0.0, 10.0);
    notifyListeners();
  }

  void setCfgRescale(double value) {
    config.cfgRescale = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setSampler(String value) {
    config.sampler = value;
    notifyListeners();
  }

  void setNoiseScheduler(String value) {
    config.noiseSchedule = value;
    notifyListeners();
  }

  void setRandomSeedEnabled(bool value) {
    config.randomSeed = value;
    notifyListeners();
  }

  void setSeed(String value) {
    final parsedSeed = int.tryParse(value);
    if (parsedSeed == null) return;
    config.seed = parsedSeed;
    notifyListeners();
  }

  void setNegativePrompt(String value) {
    config.negativePrompt = value;
    notifyListeners();
  }

  void setLegacyUc(bool value) {
    config.legacyUc = value;
    notifyListeners();
  }

  void setAutoPosition(bool value) {
    config.autoPosition = value;
    notifyListeners();
  }

  void setSm(bool value) {
    config.sm = value;
    notifyListeners();
  }

  void setSmDyn(bool value) {
    config.smDyn = value;
    notifyListeners();
  }

  void setVarietyPlus(bool value) {
    config.varietyPlus = value;
    notifyListeners();
  }

  void setDynamicThresholding(bool value) {
    config.dynamicThresholding = value;
    notifyListeners();
  }

  void setUseCharacterPromptWithOverride(bool value) {
    payloadConfig.useCharacterPromptWithOverride = value;
    notifyListeners();
  }

  void addCharacter() {
    if (payloadConfig.characterConfigList.length >= maxCharacterCount) return;
    final nextIndex = payloadConfig.characterConfigList.length + 1;
    payloadConfig.characterConfigList = [
      ...payloadConfig.characterConfigList,
      CharacterConfig.fromEmpty(name: '角色 $nextIndex'),
    ];
    notifyListeners();
  }

  void setCharacterName(int index, String value) {
    if (index < 0 || index >= payloadConfig.characterConfigList.length) return;
    payloadConfig.characterConfigList[index].name = value.trim();
    notifyListeners();
  }

  void setCharacterEnabled(int index, bool value) {
    if (index < 0 || index >= payloadConfig.characterConfigList.length) return;
    payloadConfig.characterConfigList[index].enabled = value;
    notifyListeners();
  }

  void setCharacterNegativePrompt(int index, String value) {
    if (index < 0 || index >= payloadConfig.characterConfigList.length) return;
    payloadConfig.characterConfigList[index].negativePrompt = value.trim();
    notifyListeners();
  }

  void setCharacterPrompt(int index, String value) {
    if (index < 0 || index >= payloadConfig.characterConfigList.length) return;
    _clearCharacterPromptTagified(index);
    _setCharacterPromptBlocks(index, [value.trim()]);
    notifyListeners();
  }

  void setCharacterPromptBlock(
    int characterIndex,
    int blockIndex,
    String value,
  ) {
    if (!_hasCharacter(characterIndex) || blockIndex < 0) return;
    _clearCharacterPromptTagified(characterIndex);
    final blocks = _characterPromptBlocks(characterIndex);
    while (blocks.length <= blockIndex) {
      blocks.add('');
    }
    blocks[blockIndex] = value.trim();
    _setCharacterPromptBlocks(characterIndex, blocks);
    notifyListeners();
  }

  void insertCharacterPromptBlock(
    int characterIndex,
    int targetIndex,
    String value,
  ) {
    if (!_hasCharacter(characterIndex)) return;
    final prompt = _normalizePromptBlock(value);
    if (prompt.isEmpty) return;

    _clearCharacterPromptTagified(characterIndex);
    final blocks = _characterPromptBlocks(characterIndex);
    final insertIndex = targetIndex.clamp(0, blocks.length).toInt();
    blocks.insert(insertIndex, prompt);
    _setCharacterPromptBlocks(characterIndex, blocks);
    notifyListeners();
  }

  void moveCharacterPromptBlock(
    int characterIndex,
    int blockIndex,
    int targetIndex,
  ) {
    if (!_hasCharacter(characterIndex)) return;
    final blocks = _characterPromptBlocks(characterIndex);
    if (blockIndex < 0 || blockIndex >= blocks.length) return;

    _clearCharacterPromptTagified(characterIndex);
    final clampedTarget = targetIndex.clamp(0, blocks.length).toInt();
    final block = blocks.removeAt(blockIndex);
    final shiftedTarget =
        blockIndex < clampedTarget ? clampedTarget - 1 : clampedTarget;
    final insertIndex = shiftedTarget.clamp(0, blocks.length).toInt();
    blocks.insert(insertIndex, block);
    _setCharacterPromptBlocks(characterIndex, blocks);
    notifyListeners();
  }

  void removeCharacterPromptBlock(int characterIndex, int blockIndex) {
    if (!_hasCharacter(characterIndex)) return;
    final blocks = _characterPromptBlocks(characterIndex);
    if (blockIndex < 0 || blockIndex >= blocks.length) return;

    _clearCharacterPromptTagified(characterIndex);
    blocks.removeAt(blockIndex);
    _setCharacterPromptBlocks(characterIndex, blocks);
    notifyListeners();
  }

  void setCharacterPromptTagified(int characterIndex, bool value) {
    if (!_hasCharacter(characterIndex)) return;
    final isTagified = _tagifiedCharacterIndexes.contains(characterIndex);
    if (value == isTagified) return;

    if (value) {
      final originalBlocks = _characterPromptBlocks(characterIndex);
      _characterPromptTagifiedBackups[characterIndex] =
          List<String>.unmodifiable(originalBlocks);
      _setCharacterPromptBlocks(
        characterIndex,
        _tagifiedPromptBlocks(originalBlocks),
      );
      _tagifiedCharacterIndexes.add(characterIndex);
    } else {
      final originalBlocks =
          _characterPromptTagifiedBackups.remove(characterIndex);
      if (originalBlocks != null) {
        _setCharacterPromptBlocks(characterIndex, originalBlocks);
      }
      _tagifiedCharacterIndexes.remove(characterIndex);
    }
    notifyListeners();
  }

  void applyCharacterDrop(
    int index,
    StudioWorkbenchCharacterDropData data,
  ) {
    if (index < 0 || index >= payloadConfig.characterConfigList.length) return;
    final prompt = data.characterPrompt.trim();
    if (prompt.isEmpty) return;
    final character = payloadConfig.characterConfigList[index];
    final name = data.characterName.trim();
    character.name = name.isEmpty ? data.label.trim() : name;
    _clearCharacterPromptTagified(index);
    _setCharacterPromptBlocks(index, [prompt]);
    notifyListeners();
  }

  void removeCharacter(int index) {
    if (index < 0 || index >= payloadConfig.characterConfigList.length) return;
    payloadConfig.characterConfigList = [
      for (final (itemIndex, character)
          in payloadConfig.characterConfigList.indexed)
        if (itemIndex != index) character,
    ];
    _removeCharacterPromptTagifiedState(index);
    notifyListeners();
  }

  int _roundToGenerationMultiple(int value) {
    return (value / 64).ceil() * 64;
  }

  bool _hasCharacter(int index) {
    return index >= 0 && index < payloadConfig.characterConfigList.length;
  }

  List<String> _characterPromptBlocks(int characterIndex) {
    return List<String>.from(
      payloadConfig
          .characterConfigList[characterIndex].positivePromptConfig.strs,
    );
  }

  void _setCharacterPromptBlocks(int characterIndex, List<String> blocks) {
    final promptConfig =
        payloadConfig.characterConfigList[characterIndex].positivePromptConfig;
    promptConfig.type = 'str';
    promptConfig.selectionMethod = 'all';
    promptConfig.shuffled = false;
    promptConfig.strs = blocks;
  }

  void _clearCharacterPromptTagified(int characterIndex) {
    _tagifiedCharacterIndexes.remove(characterIndex);
    _characterPromptTagifiedBackups.remove(characterIndex);
  }

  void _removeCharacterPromptTagifiedState(int removedIndex) {
    final reindexedBackups = <int, List<String>>{};
    final reindexedTagified = <int>{};

    for (final entry in _characterPromptTagifiedBackups.entries) {
      if (entry.key < removedIndex) {
        reindexedBackups[entry.key] = entry.value;
      } else if (entry.key > removedIndex) {
        reindexedBackups[entry.key - 1] = entry.value;
      }
    }
    for (final index in _tagifiedCharacterIndexes) {
      if (index < removedIndex) {
        reindexedTagified.add(index);
      } else if (index > removedIndex) {
        reindexedTagified.add(index - 1);
      }
    }

    _characterPromptTagifiedBackups
      ..clear()
      ..addAll(reindexedBackups);
    _tagifiedCharacterIndexes
      ..clear()
      ..addAll(reindexedTagified);
  }

  List<String> _tagifiedPromptBlocks(List<String> blocks) {
    final tags = <String>[];
    for (final block in blocks) {
      for (final tag in PromptTagProcessor.analyzeWorkshopTags(block)) {
        final text = PromptTagProcessor.cleanTagDisplay(
          tag.text,
          removeWeights: false,
        );
        if (text.isNotEmpty) {
          tags.add(text);
        }
      }
    }
    return tags;
  }

  String _normalizePromptBlock(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(RegExp('[,\n]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
  }
}
