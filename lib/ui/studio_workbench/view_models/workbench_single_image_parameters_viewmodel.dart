import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/vibe_encoding_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

class WorkbenchSingleImageParametersViewmodel extends ChangeNotifier {
  static const maxCharacterCount = 6;
  static const minGenerationCount = 1;
  static const maxGenerationCount = 20;

  final PayloadConfig payloadConfig;
  final Map<int, List<String>> _characterPromptTagifiedBackups = {};
  final Set<int> _tagifiedCharacterIndexes = {};
  int _generationCount = minGenerationCount;
  late String _draftWidthText;
  late String _draftHeightText;

  WorkbenchSingleImageParametersViewmodel(this.payloadConfig) {
    _syncDraftSizeFromConfig();
  }

  ParamConfig get config => payloadConfig.paramConfig;

  int get generationCount => _generationCount;

  bool get isV4 => config.model.contains('-4-');

  GenerationSize get selectedSize =>
      config.sizes.isEmpty ? ParamConfig().sizes.first : config.sizes.first;

  String get draftWidthText => _draftWidthText;

  String get draftHeightText => _draftHeightText;

  int get referenceCount =>
      payloadConfig.vibeConfigList.length +
      payloadConfig.vibeConfigListV4.length +
      payloadConfig.preciseReferenceList.length +
      (payloadConfig.i2iConfig.imageB64 == null ? 0 : 1);

  int get vibeReferenceCount =>
      payloadConfig.vibeConfigList.length +
      payloadConfig.vibeConfigListV4.length;

  bool get vibeEnabled => payloadConfig.generationRuntimeState.vibeEnabled;

  bool get hasVibeReferences => vibeReferenceCount > 0;

  bool get hasI2iImage => payloadConfig.i2iConfig.imageB64 != null;

  int get pendingVibeEncodingCount {
    if (!vibeEnabled || !isV4 || preciseReferenceActive) return 0;
    return VibeEncodingService.pendingEncodingCount(
      payloadConfig.vibeConfigListV4,
      config.model,
    );
  }

  int get vibeEncodingAnlas => pendingVibeEncodingCount * 2;

  int get multivibeExtraAnlas {
    if (!vibeEnabled || !isV4 || preciseReferenceActive) return 0;
    final activeVibeCount = payloadConfig.vibeConfigListV4
        .where(
          (vibe) =>
              vibe.vibeB64.trim().isNotEmpty ||
              VibeEncodingService.hasSourceImage(vibe),
        )
        .length;
    final extraVibes = activeVibeCount - 4;
    return extraVibes > 0 ? extraVibes * 2 * generationCount : 0;
  }

  bool get preciseReferenceActive =>
      payloadConfig.usePreciseReference &&
      config.model.contains('-4-5-') &&
      payloadConfig.preciseReferenceList.isNotEmpty;

  int get preciseReferenceExtraAnlas {
    if (!preciseReferenceActive) return 0;
    return payloadConfig.preciseReferenceList.length * 5 * generationCount;
  }

  int get knownExtraAnlas =>
      vibeEncodingAnlas + multivibeExtraAnlas + preciseReferenceExtraAnlas;

  String get knownExtraAnlasLabel {
    final parts = <String>[];
    if (vibeEncodingAnlas > 0) {
      parts.add('Vibe 编码 +$vibeEncodingAnlas');
    }
    if (multivibeExtraAnlas > 0) {
      parts.add('多 Vibe +$multivibeExtraAnlas');
    }
    if (preciseReferenceExtraAnlas > 0) {
      parts.add('精确参考 +$preciseReferenceExtraAnlas');
    }
    return '额外 $knownExtraAnlas Anlas · ${parts.join(' · ')}';
  }

  void notifyReferenceInputsChanged() {
    notifyListeners();
  }

  void disableI2iInputs() {
    payloadConfig.i2iConfig.clearImage();
    notifyListeners();
  }

  void setVibeEnabled(bool value) {
    payloadConfig.generationRuntimeState.vibeEnabled = value;
    if (value) {
      payloadConfig.usePreciseReference = false;
    }
    notifyListeners();
  }

  int get characterCount => payloadConfig.characterConfigList.length;

  bool isCharacterPromptTagified(int index) =>
      _tagifiedCharacterIndexes.contains(index);

  void refreshFromPayload() {
    _characterPromptTagifiedBackups.clear();
    _tagifiedCharacterIndexes.clear();
    _syncDraftSizeFromConfig();
    notifyListeners();
  }

  void setGenerationCount(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    final next = parsed.clamp(minGenerationCount, maxGenerationCount).toInt();
    if (next == _generationCount) return;
    _generationCount = next;
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
    _draftWidthText = width.trim();
    _draftHeightText = height.trim();
    commitDraftSize();
  }

  void setDraftWidthText(String value) {
    _draftWidthText = value;
  }

  void setDraftHeightText(String value) {
    _draftHeightText = value;
  }

  void commitPendingInputs() {
    commitDraftSize();
  }

  bool commitDraftSize() {
    final parsedWidth = int.tryParse(_draftWidthText);
    final parsedHeight = int.tryParse(_draftHeightText);
    if (parsedWidth == null || parsedHeight == null) return false;
    if (parsedWidth <= 0 || parsedHeight <= 0) return false;

    final nextSize = GenerationSize(
      width: _roundToGenerationMultiple(parsedWidth),
      height: _roundToGenerationMultiple(parsedHeight),
    );
    _setSelectedSize(nextSize);
    return true;
  }

  void setSize(GenerationSize size) {
    _setSelectedSize(size);
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

  void _setSelectedSize(GenerationSize size) {
    config.sizes = [size];
    _draftWidthText = size.width.toString();
    _draftHeightText = size.height.toString();
    notifyListeners();
  }

  void _syncDraftSizeFromConfig() {
    final size = selectedSize;
    _draftWidthText = size.width.toString();
    _draftHeightText = size.height.toString();
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
