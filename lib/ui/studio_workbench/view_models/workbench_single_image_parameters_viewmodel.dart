import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/vibe_encoding_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

class WorkbenchSingleImageParametersViewmodel extends ChangeNotifier {
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

  GenerationModelCapabilities get capabilities =>
      GenerationModelCapabilities.fromModel(config.model);

  bool get isV4 => capabilities.isV4;
  bool get usesStructuredPrompts => capabilities.usesStructuredPrompts;
  bool get supportsNoiseSchedule => capabilities.supportsNoiseSchedule;
  bool get supportsSmeaControls => capabilities.supportsSmeaControls;
  bool get supportsVarietyPlus => capabilities.supportsVarietyPlus;
  bool get supportsDynamicThresholding =>
      capabilities.supportsDynamicThresholding;
  bool get supportsLegacyUc => capabilities.supportsLegacyUc;
  bool get supportsAutoPosition => capabilities.supportsAutoPosition;
  bool get supportsFreeformCharacterPosition =>
      capabilities.supportsFreeformCharacterPosition;
  bool get supportsTransparency => capabilities.supportsTransparency;
  bool get supportsQualityPresets => capabilities.supportsQualityPresets;
  bool get supportsUcPresets => capabilities.supportsUcPresets;
  bool get supportsVibeTransfer => capabilities.supportsVibeTransfer;
  int get maxCharacterCount => capabilities.maxCharacters;

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

  bool get vibeEnabled =>
      supportsVibeTransfer && payloadConfig.generationRuntimeState.vibeEnabled;

  bool get hasVibeReferences => vibeReferenceCount > 0;

  bool get hasI2iImage => payloadConfig.i2iConfig.imageB64 != null;

  int get pendingVibeEncodingCount {
    if (!vibeEnabled ||
        !capabilities.supportsVibeTransfer ||
        !isV4 ||
        preciseReferenceActive) {
      return 0;
    }
    return VibeEncodingService.pendingEncodingCount(
      payloadConfig.vibeConfigListV4,
      config.model,
    );
  }

  int get vibeEncodingAnlas => pendingVibeEncodingCount * 2;

  int get multivibeExtraAnlas {
    if (!vibeEnabled ||
        !capabilities.supportsVibeTransfer ||
        !isV4 ||
        preciseReferenceActive) {
      return 0;
    }
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
      capabilities.supportsPreciseReference &&
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
    if (value && !supportsVibeTransfer) return;
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
    final nextCapabilities = GenerationModelCapabilities.fromModel(value);
    for (final (index, character)
        in payloadConfig.characterConfigList.indexed) {
      final fallback = defaultCharacterCenter(index);
      if (nextCapabilities.supportsFreeformCharacterPosition) {
        character.freeformPosition ??= character.positions.isEmpty
            ? fallback
            : _centerFromGridPoint(character.positions.first) ?? fallback;
      } else if (character.positions.isEmpty) {
        character.positions = [
          _gridPointFromCenter(character.freeformPosition ?? fallback),
        ];
      }
    }
    if (!nextCapabilities.supportsNoiseSchedule) {
      config.noiseSchedule = 'karras';
    }
    if (!nextCapabilities.supportsLegacyUc) config.legacyUc = false;
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

  void setQualityPreset(String value) {
    config.qualityPreset = value;
    notifyListeners();
  }

  void setUcPresetMode(String value) {
    config.ucPresetMode = value;
    notifyListeners();
  }

  void setTransparentBackground(bool value) {
    config.transparentBackground = value;
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
    final character = CharacterConfig.fromEmpty(name: '角色 $nextIndex');
    final center = defaultCharacterCenter(nextIndex - 1);
    if (supportsFreeformCharacterPosition) {
      character.freeformPosition = center;
    } else {
      character.positions = [_gridPointFromCenter(center)];
    }
    payloadConfig.characterConfigList = [
      ...payloadConfig.characterConfigList,
      character,
    ];
    notifyListeners();
  }

  Point<double> characterPosition(int index) {
    if (!_hasCharacter(index)) return defaultCharacterCenter(index);
    final character = payloadConfig.characterConfigList[index];
    final position = character.freeformPosition;
    if (supportsFreeformCharacterPosition && position != null) {
      return Point(
        position.x.clamp(0.0, 1.0).toDouble(),
        position.y.clamp(0.0, 1.0).toDouble(),
      );
    }
    if (character.positions.isNotEmpty) {
      return _centerFromGridPoint(character.positions.first) ??
          defaultCharacterCenter(index);
    }
    return character.freeformPosition ?? defaultCharacterCenter(index);
  }

  void setCharacterPosition(int index, Point<double> value) {
    if (!_hasCharacter(index)) return;
    final clamped = Point<double>(
      _roundPosition(value.x),
      _roundPosition(value.y),
    );
    final character = payloadConfig.characterConfigList[index];
    if (supportsFreeformCharacterPosition) {
      character.freeformPosition = clamped;
    } else {
      character.positions = [_gridPointFromCenter(clamped)];
    }
    notifyListeners();
  }

  Set<int> overlappingCharacterIndexes() {
    final enabled = <(int, Point<double>)>[
      for (final (index, character)
          in payloadConfig.characterConfigList.indexed)
        if (character.enabled) (index, characterPosition(index)),
    ];
    final overlapping = <int>{};
    for (var left = 0; left < enabled.length; left++) {
      for (var right = left + 1; right < enabled.length; right++) {
        final (leftIndex, leftPosition) = enabled[left];
        final (rightIndex, rightPosition) = enabled[right];
        final distance = sqrt(
          pow(leftPosition.x - rightPosition.x, 2) +
              pow(leftPosition.y - rightPosition.y, 2),
        );
        final overlaps =
            supportsFreeformCharacterPosition ? distance < 0.1 : distance == 0;
        if (overlaps) {
          overlapping
            ..add(leftIndex)
            ..add(rightIndex);
        }
      }
    }
    return overlapping;
  }

  String characterPositionLabel(int index) {
    final position = characterPosition(index);
    if (supportsFreeformCharacterPosition) {
      return '${(position.x * 100).round()}%, ${(position.y * 100).round()}%';
    }
    final grid = _gridPointFromCenter(position);
    const columns = <int, String>{1: 'A', 2: 'B', 3: 'C', 4: 'D', 5: 'E'};
    return '${columns[grid.x]}${grid.y}';
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

  static Point<double>? _centerFromGridPoint(Point<int> point) {
    const values = <int, double>{
      1: 0.1,
      2: 0.3,
      3: 0.5,
      4: 0.7,
      5: 0.9,
    };
    final x = values[point.x];
    final y = values[point.y];
    return x == null || y == null ? null : Point(x, y);
  }

  static Point<int> _gridPointFromCenter(Point<double> center) {
    const values = <int, double>{
      1: 0.1,
      2: 0.3,
      3: 0.5,
      4: 0.7,
      5: 0.9,
    };
    int nearest(double value) {
      var result = 3;
      var distance = double.infinity;
      for (final entry in values.entries) {
        final candidate = (entry.value - value).abs();
        if (candidate < distance) {
          result = entry.key;
          distance = candidate;
        }
      }
      return result;
    }

    return Point(nearest(center.x), nearest(center.y));
  }

  static double _roundPosition(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return (clamped * 1000).round() / 1000;
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
