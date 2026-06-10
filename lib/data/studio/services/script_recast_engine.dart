import 'dart:convert';

import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/tools/character_identity_prompt.dart';
import 'package:nai_casrand/data/studio/tools/filter_rule_config.dart';
import 'package:nai_casrand/data/studio/tools/generation_prompt_sanitizer.dart';
import 'package:nai_casrand/data/studio/tools/outfit_identity_prompt.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

class ScriptRecastEngine {
  const ScriptRecastEngine();

  ScriptRecastFramePayload resolveFramePayload({
    required Script script,
    required ScriptFrame frame,
    required RecastMapping mapping,
    required List<CharacterEntry> characters,
    required List<ArtistChain> artistChains,
    String globalBlockWords = '',
    String globalPromptPrefix = '',
    FilterRuleConfig? filterRuleConfig,
  }) {
    final blockWordConfig = _blockWordConfig(
      globalBlockWords,
      filterRuleConfig: filterRuleConfig,
    );
    final characterById = {
      for (final character in characters) character.id: character,
    };
    final artistById = {
      for (final artistChain in artistChains) artistChain.id: artistChain,
    };
    return _resolveFrame(
      script: script,
      frame: frame,
      mapping: mapping,
      characterById: characterById,
      artistById: artistById,
      blockWordConfig: blockWordConfig,
      globalPromptPrefix: globalPromptPrefix,
    );
  }

  ScriptRecastResult resolvePayloads({
    required Script script,
    required RecastMapping mapping,
    required List<CharacterEntry> characters,
    required List<ArtistChain> artistChains,
    String globalBlockWords = '',
    String globalPromptPrefix = '',
    FilterRuleConfig? filterRuleConfig,
  }) {
    final blockWordConfig = _blockWordConfig(
      globalBlockWords,
      filterRuleConfig: filterRuleConfig,
    );
    final characterById = {
      for (final character in characters) character.id: character,
    };
    final artistById = {
      for (final artistChain in artistChains) artistChain.id: artistChain,
    };
    final frames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .map(
          (frame) => _resolveFrame(
            script: script,
            frame: frame,
            mapping: mapping,
            characterById: characterById,
            artistById: artistById,
            blockWordConfig: blockWordConfig,
            globalPromptPrefix: globalPromptPrefix,
          ),
        )
        .toList(growable: false);

    return ScriptRecastResult(
      scriptId: script.id,
      mappingId: mapping.id,
      frames: frames,
      configFingerprint: _fingerprintJson(
        _canonicalJson({
          'scriptId': script.id,
          'mapping': mapping.toJson(),
          if (globalBlockWords.trim().isNotEmpty)
            'globalBlockWords': globalBlockWords,
          if (globalPromptPrefix.trim().isNotEmpty)
            'globalPromptPrefix': globalPromptPrefix,
          if (filterRuleConfig != null)
            'filterRuleConfig': filterRuleConfig.toMap(),
          'frameFingerprints':
              frames.map((frame) => frame.payloadFingerprint).toList(),
        }),
      ),
    );
  }

  Future<ScriptRecastResult> resolvePayloadsAsync({
    required Script script,
    required RecastMapping mapping,
    required List<CharacterEntry> characters,
    required List<ArtistChain> artistChains,
    String globalBlockWords = '',
    String globalPromptPrefix = '',
    FilterRuleConfig? filterRuleConfig,
    int yieldEveryFrames = 12,
  }) async {
    final blockWordConfig = _blockWordConfig(
      globalBlockWords,
      filterRuleConfig: filterRuleConfig,
    );
    final characterById = {
      for (final character in characters) character.id: character,
    };
    final artistById = {
      for (final artistChain in artistChains) artistChain.id: artistChain,
    };
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    final frames = <ScriptRecastFramePayload>[];
    final yieldInterval = yieldEveryFrames <= 0 ? 12 : yieldEveryFrames;

    for (var index = 0; index < parsedFrames.length; index += 1) {
      final frame = parsedFrames[index];
      frames.add(
        _resolveFrame(
          script: script,
          frame: frame,
          mapping: mapping,
          characterById: characterById,
          artistById: artistById,
          blockWordConfig: blockWordConfig,
          globalPromptPrefix: globalPromptPrefix,
        ),
      );
      if ((index + 1) % yieldInterval == 0 && index + 1 < parsedFrames.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return ScriptRecastResult(
      scriptId: script.id,
      mappingId: mapping.id,
      frames: List.unmodifiable(frames),
      configFingerprint: _fingerprintJson(
        _canonicalJson({
          'scriptId': script.id,
          'mapping': mapping.toJson(),
          if (globalBlockWords.trim().isNotEmpty)
            'globalBlockWords': globalBlockWords,
          if (globalPromptPrefix.trim().isNotEmpty)
            'globalPromptPrefix': globalPromptPrefix,
          if (filterRuleConfig != null)
            'filterRuleConfig': filterRuleConfig.toMap(),
          'frameFingerprints':
              frames.map((frame) => frame.payloadFingerprint).toList(),
        }),
      ),
    );
  }

  ScriptRecastFramePayload _resolveFrame({
    required Script script,
    required ScriptFrame frame,
    required RecastMapping mapping,
    required Map<String, CharacterEntry> characterById,
    required Map<String, ArtistChain> artistById,
    FilterRuleConfig? blockWordConfig,
    String globalPromptPrefix = '',
  }) {
    final payload = _deepMutableMap(frame.parsed.sourcePayload);

    final baseCaption = _filterPromptText(
      _prependPromptPrefix(
        globalPromptPrefix,
        _resolveBaseCaption(
          frame: frame,
          mapping: mapping,
          characterById: characterById,
          artistById: artistById,
        ),
      ),
      blockWordConfig,
    );
    final charCaptions = _filterPromptList(
      _resolveCharCaptions(
        frame: frame,
        mapping: mapping,
        characterById: characterById,
      ),
      blockWordConfig,
    );
    final negativeBase = _filterPromptText(
      _resolveNegativeBase(
        frame: frame,
        mapping: mapping,
        artistById: artistById,
      ),
      blockWordConfig,
    );
    final negativeCharCaptions = _filterPromptList(
      frame.parsed.negativeCharCaptions,
      blockWordConfig,
    );
    final vibeRefs = _resolveVibeReferences(mapping: mapping);

    _writePrompt(payload, baseCaption, charCaptions);
    _writeNegativePrompt(payload, negativeBase, negativeCharCaptions);
    _writeParameters(payload, frame.parsed.generationParams);
    _writeVibeReferences(payload, vibeRefs);

    return ScriptRecastFramePayload(
      frameIndex: frame.index,
      sourceFileName: frame.fileName,
      payload: _deepImmutableMap(payload),
      payloadFingerprint: _fingerprintJson(_canonicalJson(payload)),
    );
  }

  String _resolveBaseCaption({
    required ScriptFrame frame,
    required RecastMapping mapping,
    required Map<String, CharacterEntry> characterById,
    required Map<String, ArtistChain> artistById,
  }) {
    final artistSwap = mapping.artistSwap;
    final artistChain = _artistChainForSwap(artistSwap, artistById);
    final manualPrompt = _manualArtistPromptForSwap(artistSwap);
    final sourceCaption = _sourceBaseCaption(frame);
    final hasArtistDelete = artistSwap?.deleteSource ?? false;
    var resolvedCaption = sourceCaption;
    if (artistChain != null || manualPrompt.isNotEmpty || hasArtistDelete) {
      final sourceWithoutArtists = _removeArtistTags(
        sourceCaption,
        sourceArtistPrompt: artistSwap?.sourceArtistPrompt ?? '',
      );
      resolvedCaption = sanitizeGenerationPrompt(_joinTags([
        sourceWithoutArtists,
        if (artistChain != null) ..._artistPromptTags(artistChain),
        if (artistChain == null && manualPrompt.isNotEmpty) manualPrompt,
      ]));
    }

    final roleResolvedCaption = _resolveBaseRoleAssemblies(
      frame: frame,
      sourceCaption: resolvedCaption,
      mapping: mapping,
      characterById: characterById,
    );
    return _applyPromptBlockSwaps(
      roleResolvedCaption,
      mapping.promptBlockSwaps,
    );
  }

  String _resolveBaseRoleAssemblies({
    required ScriptFrame frame,
    required String sourceCaption,
    required RecastMapping mapping,
    required Map<String, CharacterEntry> characterById,
  }) {
    var caption = sourceCaption;
    for (final assembly in mapping.roleAssemblies) {
      if (!_shouldApplyAssemblyToBase(assembly, frame.index)) {
        continue;
      }
      caption = _roleAssemblyCaption(
        sourceCaption: caption,
        frameIndex: frame.index,
        assembly: assembly,
        characterById: characterById,
      );
    }
    return caption;
  }

  List<String> _resolveCharCaptions({
    required ScriptFrame frame,
    required RecastMapping mapping,
    required Map<String, CharacterEntry> characterById,
  }) {
    final captions = frame.parsed.charCaptions.toList(growable: true);
    if (mapping.roleAssemblies.isNotEmpty) {
      for (final assembly in mapping.roleAssemblies) {
        if (assembly.sourceAppearances.isNotEmpty) {
          for (final slotIndex in _appearanceSlotIndexesForFrame(
            assembly: assembly,
            frameIndex: frame.index,
            captionsLength: captions.length,
          )) {
            captions[slotIndex] = _roleAssemblyCaption(
              sourceCaption: captions[slotIndex],
              frameIndex: frame.index,
              assembly: assembly,
              characterById: characterById,
            );
          }
          continue;
        }
        final slotIndex = _slotIndex(assembly.sourceRoleId);
        if (slotIndex == null ||
            slotIndex < 0 ||
            slotIndex >= captions.length) {
          continue;
        }
        captions[slotIndex] = _roleAssemblyCaption(
          sourceCaption: captions[slotIndex],
          frameIndex: frame.index,
          assembly: assembly,
          characterById: characterById,
        );
      }
      return List.unmodifiable(captions);
    }
    for (final roleSwap in mapping.roleSwaps) {
      final slotIndex = _slotIndex(roleSwap.sourceRoleId);
      if (slotIndex == null || slotIndex < 0 || slotIndex >= captions.length) {
        continue;
      }
      final character = characterById[roleSwap.targetCharacterId];
      if (character == null) {
        continue;
      }
      captions[slotIndex] = _characterCaption(
        captions[slotIndex],
        character,
        roleSwap.targetOutfitId,
      );
    }
    return List.unmodifiable(captions);
  }

  List<int> _appearanceSlotIndexesForFrame({
    required RoleAssembly assembly,
    required int frameIndex,
    required int captionsLength,
  }) {
    final slotIndexes = <int>{};
    for (final appearance in assembly.sourceAppearances) {
      if (appearance.frameIndexes.isNotEmpty &&
          !appearance.frameIndexes.contains(frameIndex)) {
        continue;
      }
      if (appearance.sourceKind.trim().isNotEmpty &&
          appearance.sourceKind.trim() != 'slot') {
        continue;
      }
      final slotIndex = _slotIndex(appearance.sourceId);
      if (slotIndex == null || slotIndex < 0 || slotIndex >= captionsLength) {
        continue;
      }
      slotIndexes.add(slotIndex);
    }
    return List.unmodifiable(slotIndexes.toList()..sort());
  }

  bool _shouldApplyAssemblyToBase(RoleAssembly assembly, int frameIndex) {
    if (assembly.sourceAppearances.isNotEmpty) {
      return assembly.sourceAppearances.any(
        (appearance) => _appearanceTargetsBaseForFrame(
          appearance,
          frameIndex,
        ),
      );
    }
    final sourceRoleId = assembly.sourceRoleId.trim().toLowerCase();
    if (!_isBaseRoleSource(sourceRoleId)) {
      return false;
    }
    return _stageForFrame(assembly, frameIndex) != null;
  }

  bool _appearanceTargetsBaseForFrame(
    RoleAssemblySourceAppearance appearance,
    int frameIndex,
  ) {
    if (appearance.frameIndexes.isNotEmpty &&
        !appearance.frameIndexes.contains(frameIndex)) {
      return false;
    }
    final sourceId = appearance.sourceId.trim().toLowerCase();
    final sourceKind = appearance.sourceKind.trim().toLowerCase();
    return _isBaseRoleSource(sourceId) || _isBaseRoleSource(sourceKind);
  }

  bool _isBaseRoleSource(String value) {
    return value == 'base' ||
        value == 'global' ||
        value.startsWith('global-') ||
        value.startsWith('base-');
  }

  String _resolveNegativeBase({
    required ScriptFrame frame,
    required RecastMapping mapping,
    required Map<String, ArtistChain> artistById,
  }) {
    final artistChain = _artistChainForSwap(mapping.artistSwap, artistById);
    if (artistChain == null) {
      return frame.parsed.negativeBase;
    }
    return sanitizeGenerationPrompt(_joinTags([
      frame.parsed.negativeBase,
      ...artistChain.globalNegatives
          .where((tag) => !isUnsafeGenerationPromptTag(tag.tag))
          .map((tag) => tag.tag),
    ]));
  }

  void _writePrompt(
    Map<String, dynamic> payload,
    String baseCaption,
    List<String> charCaptions,
  ) {
    final comment = _ensureMap(payload, 'Comment');
    final prompt = _ensureMap(comment, 'v4_prompt');
    final caption = _ensureMap(prompt, 'caption');
    caption['base_caption'] = sanitizeGenerationPrompt(baseCaption);

    final existing = caption['char_captions'];
    caption['char_captions'] = [
      for (var index = 0; index < charCaptions.length; index += 1)
        {
          ...existing is List &&
                  index < existing.length &&
                  existing[index] is Map
              ? _deepMutableMap(
                  (existing[index] as Map).cast<String, dynamic>())
              : <String, dynamic>{},
          'char_caption': sanitizeGenerationPrompt(charCaptions[index]),
        },
    ];
  }

  void _writeNegativePrompt(
    Map<String, dynamic> payload,
    String negativeBase,
    List<String> negativeCharCaptions,
  ) {
    final comment = _ensureMap(payload, 'Comment');
    final prompt = _ensureMap(comment, 'v4_negative_prompt');
    final caption = _ensureMap(prompt, 'caption');
    caption['base_caption'] = sanitizeGenerationPrompt(negativeBase);
    final existing = caption['char_captions'];
    caption['char_captions'] = [
      for (var index = 0; index < negativeCharCaptions.length; index += 1)
        {
          ...existing is List &&
                  index < existing.length &&
                  existing[index] is Map
              ? _deepMutableMap(
                  (existing[index] as Map).cast<String, dynamic>())
              : <String, dynamic>{},
          'char_caption': sanitizeGenerationPrompt(negativeCharCaptions[index]),
        },
    ];
  }

  void _writeParameters(
    Map<String, dynamic> payload,
    Map<String, dynamic> sourceParams,
  ) {
    final comment = _ensureMap(payload, 'Comment');
    final parameters = <String, dynamic>{};
    for (final entry in sourceParams.entries) {
      if (_isPromptStructureKey(entry.key)) {
        continue;
      }
      parameters[entry.key] = _deepMutableValue(entry.value);
      comment[entry.key] = _deepMutableValue(entry.value);
    }
    payload['parameters'] = parameters;
  }

  List<WorkspaceVibeReference> _resolveVibeReferences({
    required RecastMapping mapping,
  }) {
    return mapping.manualVibeRefs;
  }

  void _writeVibeReferences(
    Map<String, dynamic> payload,
    List<WorkspaceVibeReference> vibeRefs,
  ) {
    if (vibeRefs.isEmpty) {
      return;
    }
    final parameters = _ensureMap(payload, 'parameters');
    final images = _mutableList(parameters['reference_image_multiple']);
    final strengths = _mutableList(parameters['reference_strength_multiple']);
    final infoExtracted = _mutableList(
      parameters['reference_information_extracted_multiple'],
    );
    final seen = images.whereType<String>().toSet();

    for (final vibe in vibeRefs) {
      final encoding = vibe.vibeB64.trim();
      if (encoding.isEmpty || !seen.add(encoding)) {
        continue;
      }
      images.add(encoding);
      strengths.add(vibe.referenceStrength.clamp(0.0, 1.0));
      infoExtracted.add(vibe.infoExtracted.clamp(0.0, 1.0));
    }

    parameters['reference_image_multiple'] = images;
    parameters['reference_strength_multiple'] = strengths;
    parameters['reference_information_extracted_multiple'] = infoExtracted;

    final comment = _ensureMap(payload, 'Comment');
    comment['reference_image_multiple'] = List<dynamic>.from(images);
    comment['reference_strength_multiple'] = List<dynamic>.from(strengths);
    comment['reference_information_extracted_multiple'] =
        List<dynamic>.from(infoExtracted);
  }
}

bool _isPromptStructureKey(String key) {
  return key == 'v4_prompt' || key == 'v4_negative_prompt';
}

class ScriptRecastResult {
  final String scriptId;
  final String mappingId;
  final List<ScriptRecastFramePayload> frames;
  final String configFingerprint;

  const ScriptRecastResult({
    required this.scriptId,
    required this.mappingId,
    required this.frames,
    required this.configFingerprint,
  });

  Map<String, dynamic> toJson() => {
        'scriptId': scriptId,
        'mappingId': mappingId,
        'frames': frames.map((frame) => frame.toJson()).toList(),
        'configFingerprint': configFingerprint,
      };
}

class ScriptRecastFramePayload {
  final int frameIndex;
  final String sourceFileName;
  final Map<String, dynamic> payload;
  final String payloadFingerprint;

  const ScriptRecastFramePayload({
    required this.frameIndex,
    required this.sourceFileName,
    required this.payload,
    required this.payloadFingerprint,
  });

  Map<String, dynamic> toJson() => {
        'frameIndex': frameIndex,
        'sourceFileName': sourceFileName,
        'payload': _canonicalValue(payload),
        'payloadFingerprint': payloadFingerprint,
      };
}

String _characterCaption(
  String sourceCaption,
  CharacterEntry character,
  String? targetOutfitId,
) {
  final outfit = _selectedOutfit(character, targetOutfitId);
  final outfitParts = RecastPromptParts(
    upperBody: _joinTags(outfit?.partTags.upperBodyTags ?? const []),
    lowerBody: _joinTags(outfit?.partTags.lowerBodyTags ?? const []),
    upperClothing: _upperOutfitTags(outfit),
    lowerClothing: _lowerOutfitTags(outfit),
  );
  return _joinTags([
    ..._uniqueTags(_splitTagFragments([
      _characterIdentityPromptExcluding(character, outfitParts),
      outfitParts.upperBody,
      outfitParts.lowerBody,
      outfitParts.upperClothing,
      outfitParts.lowerClothing,
    ])),
  ]);
}

String _roleAssemblyCaption({
  required String sourceCaption,
  required int frameIndex,
  required RoleAssembly assembly,
  required Map<String, CharacterEntry> characterById,
}) {
  final stage = _stageForFrame(assembly, frameIndex);
  if (stage == null) {
    return sourceCaption;
  }
  final character = stage.targetCharacterId == null
      ? null
      : characterById[stage.targetCharacterId];
  final upperOutfit = character == null
      ? null
      : _selectedOutfitById(character, stage.targetUpperOutfitId);
  final lowerOutfit = character == null
      ? null
      : _selectedOutfitById(character, stage.targetLowerOutfitId);
  final parts = _promptPartsFor(
    character: character,
    upperOutfit: upperOutfit,
    lowerOutfit: lowerOutfit,
    omittedParts: stage.omittedParts,
    preservedParts: stage.preservedParts,
    manualParts: stage.manualParts,
  );
  if (parts.isEmpty && character == null) {
    return sourceCaption;
  }
  final sourcePartsToRemove = _sourcePartsToRemoveFor(
    stage: stage,
    hasTargetCharacter: character != null,
  );
  return _joinTags([
    ..._uniqueTags(_splitTagFragments([
      parts.identity,
      parts.upperBody,
      parts.lowerBody,
      parts.upperClothing,
      parts.lowerClothing,
    ])),
    ..._sourceTagsOutsideParts(
      sourceCaption: sourceCaption,
      sourceParts: sourcePartsToRemove,
    ),
  ]);
}

String _prependPromptPrefix(String prefix, String prompt) {
  final cleanPrefix = prefix.trim();
  final cleanPrompt = prompt.trim();
  if (cleanPrefix.isEmpty) {
    return prompt;
  }
  if (cleanPrompt.isEmpty) {
    return cleanPrefix;
  }
  return _joinTags([cleanPrefix, cleanPrompt]);
}

RoleAssemblyStage? _stageForFrame(RoleAssembly assembly, int frameIndex) {
  for (final stage in assembly.stages) {
    if (stage.frameIndexes.contains(frameIndex)) {
      return stage;
    }
  }
  if (assembly.stages.any((stage) => stage.frameIndexes.isNotEmpty)) {
    return null;
  }
  return assembly.stages.isEmpty ? null : assembly.stages.first;
}

RecastPromptParts _promptPartsFor({
  required CharacterEntry? character,
  required WorkspaceOutfit? upperOutfit,
  required WorkspaceOutfit? lowerOutfit,
  required Set<RecastPromptPart> omittedParts,
  required Set<RecastPromptPart> preservedParts,
  required RecastPromptParts manualParts,
}) {
  final upperOutfitBody = _joinTags(
    upperOutfit?.partTags.upperBodyTags ?? const [],
  );
  final lowerOutfitBody = _joinTags(
    lowerOutfit?.partTags.lowerBodyTags ?? const [],
  );
  final resolvedWithoutIdentity = RecastPromptParts(
    upperBody: _firstNonEmptyPrompt([
      upperOutfitBody,
      character?.traits.frontUpper ?? '',
    ]),
    lowerBody: _firstNonEmptyPrompt([
      lowerOutfitBody,
      character?.traits.frontLower ?? '',
    ]),
    upperClothing: _upperOutfitTags(upperOutfit),
    lowerClothing: _lowerOutfitTags(lowerOutfit),
  );
  final outfitIdentity = deriveSelectedOutfitIdentityPrompt(
    upperOutfit,
    lowerOutfit,
  );
  final baseIdentity = character == null
      ? ''
      : _characterIdentityPromptExcluding(character, resolvedWithoutIdentity);
  final resolved = resolvedWithoutIdentity.copyWith(
    identity: character == null
        ? ''
        : outfitIdentity.trim().isEmpty
            ? baseIdentity
            : mergeBaseAndOutfitIdentity(baseIdentity, outfitIdentity),
  );
  return RecastPromptParts(
    identity: _manualOrResolvedIdentity(
      manualParts.identity,
      resolved: resolved.identity,
      baseIdentity: baseIdentity,
      outfitIdentity: outfitIdentity,
      blocked: omittedParts.contains(RecastPromptPart.identity) ||
          preservedParts.contains(RecastPromptPart.identity),
    ),
    upperBody: _manualOrResolvedPart(
      manualParts.upperBody,
      resolved.upperBody,
      blocked: omittedParts.contains(RecastPromptPart.upperBody) ||
          preservedParts.contains(RecastPromptPart.upperBody),
    ),
    lowerBody: _manualOrResolvedPart(
      manualParts.lowerBody,
      resolved.lowerBody,
      blocked: omittedParts.contains(RecastPromptPart.lowerBody) ||
          preservedParts.contains(RecastPromptPart.lowerBody),
    ),
    upperClothing: _manualOrResolvedPart(
      manualParts.upperClothing,
      resolved.upperClothing,
      blocked: omittedParts.contains(RecastPromptPart.upperClothing) ||
          preservedParts.contains(RecastPromptPart.upperClothing),
    ),
    lowerClothing: _manualOrResolvedPart(
      manualParts.lowerClothing,
      resolved.lowerClothing,
      blocked: omittedParts.contains(RecastPromptPart.lowerClothing) ||
          preservedParts.contains(RecastPromptPart.lowerClothing),
    ),
  );
}

String _firstNonEmptyPrompt(Iterable<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String _manualOrResolvedPart(
  String manual,
  String resolved, {
  required bool blocked,
}) {
  if (manual.trim().isNotEmpty) {
    return manual;
  }
  return blocked ? '' : resolved;
}

String _manualOrResolvedIdentity(
  String manual, {
  required String resolved,
  required String baseIdentity,
  required String outfitIdentity,
  required bool blocked,
}) {
  final manualTrimmed = manual.trim();
  if (manualTrimmed.isEmpty) {
    return blocked ? '' : resolved;
  }
  if (outfitIdentity.trim().isNotEmpty &&
      _samePromptIdentity(manualTrimmed, baseIdentity)) {
    return blocked ? '' : resolved;
  }
  return outfitIdentity.trim().isEmpty
      ? manual
      : mergeBaseAndOutfitIdentity(manual, outfitIdentity);
}

bool _samePromptIdentity(String left, String right) {
  final leftKey = _promptIdentityKey(left);
  final rightKey = _promptIdentityKey(right);
  return leftKey.isNotEmpty && leftKey == rightKey;
}

String _promptIdentityKey(String tag) {
  final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
  return PromptTagProcessor.normalizeMatchKey(clean);
}

RecastPromptParts _sourcePartsToRemoveFor({
  required RoleAssemblyStage stage,
  required bool hasTargetCharacter,
}) {
  return RecastPromptParts(
    identity: _sourcePartToRemove(
      stage.sourceParts.identity,
      (hasTargetCharacter &&
              !stage.preservedParts.contains(RecastPromptPart.identity)) ||
          stage.manualParts.identity.trim().isNotEmpty ||
          stage.omittedParts.contains(RecastPromptPart.identity),
    ),
    upperBody: _sourcePartToRemove(
      stage.sourceParts.upperBody,
      (hasTargetCharacter &&
              !stage.preservedParts.contains(RecastPromptPart.upperBody)) ||
          stage.manualParts.upperBody.trim().isNotEmpty ||
          stage.omittedParts.contains(RecastPromptPart.upperBody),
    ),
    lowerBody: _sourcePartToRemove(
      stage.sourceParts.lowerBody,
      (hasTargetCharacter &&
              !stage.preservedParts.contains(RecastPromptPart.lowerBody)) ||
          stage.manualParts.lowerBody.trim().isNotEmpty ||
          stage.omittedParts.contains(RecastPromptPart.lowerBody),
    ),
    upperClothing: _sourcePartToRemove(
      stage.sourceParts.upperClothing,
      (hasTargetCharacter &&
              !stage.preservedParts.contains(RecastPromptPart.upperClothing)) ||
          stage.manualParts.upperClothing.trim().isNotEmpty ||
          stage.omittedParts.contains(RecastPromptPart.upperClothing),
    ),
    lowerClothing: _sourcePartToRemove(
      stage.sourceParts.lowerClothing,
      (hasTargetCharacter &&
              !stage.preservedParts.contains(RecastPromptPart.lowerClothing)) ||
          stage.manualParts.lowerClothing.trim().isNotEmpty ||
          stage.omittedParts.contains(RecastPromptPart.lowerClothing),
    ),
  );
}

String _sourcePartToRemove(String sourcePart, bool shouldRemove) =>
    shouldRemove ? sourcePart : '';

List<String> _sourceTagsOutsideParts({
  required String sourceCaption,
  required RecastPromptParts sourceParts,
}) {
  final sourcePartKeys = {
    ..._promptPartMatchKeys(sourceParts),
  };
  return _uniqueTags(
    _splitTags(sourceCaption).where((tag) {
      final key = PromptTagProcessor.normalizeMatchKey(tag);
      return !sourcePartKeys.contains(key);
    }),
  );
}

Set<String> _promptPartMatchKeys(RecastPromptParts parts) {
  return {
    for (final tag in _splitTagFragments([
      parts.identity,
      parts.upperBody,
      parts.lowerBody,
      parts.upperClothing,
      parts.lowerClothing,
    ]))
      PromptTagProcessor.normalizeMatchKey(tag),
  }..remove('');
}

String _characterIdentityPromptExcluding(
  CharacterEntry character,
  RecastPromptParts usedParts,
) {
  return deriveCharacterIdentityPromptExcluding(character, usedParts);
}

WorkspaceOutfit? _selectedOutfit(
  CharacterEntry character,
  String? targetOutfitId,
) {
  final selectedId = targetOutfitId ?? character.defaultOutfitId;
  return _selectedOutfitById(character, selectedId);
}

WorkspaceOutfit? _selectedOutfitById(
  CharacterEntry character,
  String? selectedId,
) {
  if (selectedId == null) {
    return null;
  }
  for (final outfit in character.outfits) {
    if (outfit.id == selectedId) {
      return outfit;
    }
  }
  return null;
}

String _upperOutfitTags(WorkspaceOutfit? outfit) {
  if (outfit == null) {
    return '';
  }
  if (outfit.partTags.upperClothingTags.isNotEmpty) {
    return _joinTags(outfit.partTags.upperClothingTags);
  }
  return '';
}

String _lowerOutfitTags(WorkspaceOutfit? outfit) {
  if (outfit == null) {
    return '';
  }
  if (outfit.partTags.lowerClothingTags.isNotEmpty) {
    return _joinTags(outfit.partTags.lowerClothingTags);
  }
  return '';
}

List<String> _splitTagFragments(Iterable<String> fragments) {
  return [
    for (final fragment in fragments) ..._splitTags(fragment),
  ];
}

List<String> _uniqueTags(Iterable<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final tag in tags) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final key = PromptTagProcessor.normalizeMatchKey(trimmed);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(trimmed);
  }
  return List.unmodifiable(result);
}

ArtistChain? _artistChainForSwap(
  ArtistSwap? artistSwap,
  Map<String, ArtistChain> artistById,
) {
  final id = artistSwap?.targetArtistChainId.trim() ?? '';
  if (id.isEmpty) {
    return null;
  }
  return artistById[id];
}

String _manualArtistPromptForSwap(ArtistSwap? artistSwap) {
  return artistSwap?.manualPrompt.trim() ?? '';
}

List<String> _artistPromptTags(ArtistChain artistChain) {
  final tags = <String>[];
  if (artistChain.artists.isNotEmpty) {
    tags.addAll(artistChain.artists.map(_artistEntryTag));
  } else {
    tags.addAll(sanitizeGenerationPromptTags(artistChain.tags));
  }
  if (artistChain.prompt.trim().isNotEmpty) {
    final prompt = sanitizeGenerationPrompt(artistChain.prompt);
    if (prompt.isNotEmpty) {
      tags.add(prompt);
    }
  }
  tags.addAll(sanitizeGenerationPromptTags(artistChain.styleTags));
  tags.addAll([
    for (final tag in artistChain.styleHintsWeighted)
      if (!isUnsafeGenerationPromptTag(tag.tag)) _weightedTag(tag),
  ]);
  return sanitizeGenerationPromptTags(tags);
}

String _artistEntryTag(ArtistEntry artist) {
  final tag = '${artist.prefix}${artist.name}';
  return artist.weight == 1 ? tag : _weightedTagValue(tag, artist.weight);
}

String _weightedTag(WorkspaceWeightedTag tag) {
  return tag.weight == 1 ? tag.tag : _weightedTagValue(tag.tag, tag.weight);
}

String _weightedTagValue(String tag, double weight) {
  return PromptTagProcessor.formatInlineWeightTag(tag, weight);
}

String _removeArtistTags(
  String caption, {
  String sourceArtistPrompt = '',
}) {
  final sourceArtistKeys = _artistSourceMatchKeys(sourceArtistPrompt);
  return _joinTags(
    _splitTags(caption).where(
      (tag) => !_shouldRemoveSourceArtistTag(tag, sourceArtistKeys),
    ),
  );
}

bool _shouldRemoveSourceArtistTag(String tag, Set<String> sourceArtistKeys) {
  if (RegExp(r'artist\s*:', caseSensitive: false).hasMatch(tag)) {
    return true;
  }
  final key = _artistSourceMatchKey(tag);
  return key.isNotEmpty && sourceArtistKeys.contains(key);
}

Set<String> _artistSourceMatchKeys(String sourceArtistPrompt) {
  final keys = <String>{};
  for (final tag in _splitTags(sourceArtistPrompt)) {
    _addArtistSourceMatchKeys(keys, tag);
  }
  return keys;
}

void _addArtistSourceMatchKeys(Set<String> keys, String tag) {
  final key = _artistSourceMatchKey(tag);
  if (key.isEmpty) {
    return;
  }
  keys.add(key);
  final artistPrefix = RegExp(r'^artist\s*:\s*', caseSensitive: false);
  final withoutArtistPrefix = key.replaceFirst(artistPrefix, '').trim();
  if (withoutArtistPrefix.isNotEmpty && withoutArtistPrefix != key) {
    keys.add(withoutArtistPrefix);
  }
}

String _artistSourceMatchKey(String tag) {
  final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
  return PromptTagProcessor.normalizeMatchKey(clean);
}

String _applyPromptBlockSwaps(
  String caption,
  List<PromptBlockSwap> swaps,
) {
  var result = caption;
  for (final swap in swaps) {
    if (!_isSupportedPromptBlockSwap(swap)) {
      continue;
    }
    final manualPrompt = sanitizeGenerationPrompt(swap.manualPrompt);
    final shouldRemoveSource =
        manualPrompt.trim().isNotEmpty || swap.deleteSource;
    if (!shouldRemoveSource) {
      continue;
    }
    result = _removePromptTags(
      result,
      sourcePrompt: swap.sourcePrompt,
    );
    if (manualPrompt.trim().isNotEmpty) {
      result = _joinTags([result, manualPrompt]);
    }
  }
  return sanitizeGenerationPrompt(result);
}

bool _isSupportedPromptBlockSwap(PromptBlockSwap swap) {
  final block = swap.block.trim();
  return block == 'style' || block == 'quality';
}

String _removePromptTags(
  String caption, {
  required String sourcePrompt,
}) {
  final sourceKeys = {
    for (final tag in _splitTags(sourcePrompt))
      PromptTagProcessor.normalizeMatchKey(
        PromptTagProcessor.cleanTagDisplay(tag),
      ),
  }..remove('');
  if (sourceKeys.isEmpty) {
    return caption;
  }
  return _joinTags(
    _splitTags(caption).where((tag) {
      final key = PromptTagProcessor.normalizeMatchKey(tag);
      return !sourceKeys.contains(key);
    }),
  );
}

String _sourceBaseCaption(ScriptFrame frame) {
  final prompt = frame.parsed.generationParams['v4_prompt'];
  if (prompt is Map) {
    final caption = prompt['caption'];
    if (caption is Map) {
      final baseCaption = caption['base_caption'];
      if (baseCaption is String && baseCaption.trim().isNotEmpty) {
        return baseCaption;
      }
    }
  }
  return frame.parsed.baseCaption;
}

int? _slotIndex(String sourceRoleId) {
  final match = RegExp(r'^slot-(\d+)$').firstMatch(sourceRoleId);
  return match == null ? null : int.parse(match.group(1)!);
}

List<String> _splitTags(String caption) {
  return PromptTagProcessor.splitWorkshopTags(caption)
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

List<dynamic> _mutableList(dynamic value) {
  if (value is List) {
    return value.map(_deepMutableValue).toList(growable: true);
  }
  return <dynamic>[];
}

String _joinTags(Iterable<String> tags) {
  return tags
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .join(', ');
}

List<String> _filterPromptList(
  List<String> prompts,
  FilterRuleConfig? blockWordConfig,
) {
  if (blockWordConfig == null) {
    return prompts;
  }
  return [
    for (final prompt in prompts) _filterPromptText(prompt, blockWordConfig),
  ];
}

String _filterPromptText(
  String prompt,
  FilterRuleConfig? blockWordConfig,
) {
  if (blockWordConfig == null) {
    return prompt;
  }
  final filtered =
      PromptTagProcessor.filterTags(prompt, config: blockWordConfig);
  return _joinTags([...filtered.clean, ...filtered.quantity]);
}

FilterRuleConfig? _blockWordConfig(
  String globalBlockWords, {
  FilterRuleConfig? filterRuleConfig,
}) {
  final config = filterRuleConfig;
  if (config != null) {
    final deleteKeywords = globalBlockWords.trim().isEmpty
        ? config.deleteKeywords
        : globalBlockWords;
    final effective = config.copyWith(
      deleteKeywords: deleteKeywords,
      exactMatch: false,
    );
    if (effective.deleteKeywords.trim().isEmpty &&
        effective.strongFilterKeywords.trim().isEmpty &&
        effective.replaceRules.trim().isEmpty &&
        !effective.deleteArtistTags) {
      return null;
    }
    return effective;
  }
  if (globalBlockWords.trim().isEmpty) {
    return null;
  }
  return FilterRuleConfig(
    deleteKeywords: globalBlockWords,
    exactMatch: false,
  );
}

Map<String, dynamic> _ensureMap(Map<String, dynamic> parent, String key) {
  final value = parent[key];
  if (value is Map) {
    final map = value.cast<String, dynamic>();
    if (!identical(value, map)) {
      parent[key] = map;
    }
    return map;
  }
  final created = <String, dynamic>{};
  parent[key] = created;
  return created;
}

Map<String, dynamic> _deepMutableMap(Map<String, dynamic> value) {
  return value.map((key, child) => MapEntry(key, _deepMutableValue(child)));
}

dynamic _deepMutableValue(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, child) => MapEntry(key.toString(), _deepMutableValue(child)),
    );
  }
  if (value is List) {
    return value.map(_deepMutableValue).toList(growable: true);
  }
  return value;
}

Map<String, dynamic> _deepImmutableMap(Map<String, dynamic> value) {
  return Map.unmodifiable(
    value.map((key, child) => MapEntry(key, _deepImmutableValue(child))),
  );
}

dynamic _deepImmutableValue(dynamic value) {
  if (value is Map) {
    return Map.unmodifiable(
      value.map(
        (key, child) => MapEntry(key.toString(), _deepImmutableValue(child)),
      ),
    );
  }
  if (value is List) {
    return List.unmodifiable(value.map(_deepImmutableValue));
  }
  return value;
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((left, right) => left.key.toString().compareTo(
            right.key.toString(),
          ));
    return {
      for (final entry in entries)
        entry.key.toString(): _canonicalValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  return value;
}

String _fingerprintJson(String canonicalJson) {
  var hash = _fnv64Offset;
  for (final byte in utf8.encode(canonicalJson)) {
    hash ^= BigInt.from(byte);
    hash = (hash * _fnv64Prime) & _fnv64Mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

final BigInt _fnv64Offset = BigInt.parse('cbf29ce484222325', radix: 16);
final BigInt _fnv64Prime = BigInt.parse('100000001b3', radix: 16);
final BigInt _fnv64Mask = BigInt.parse('ffffffffffffffff', radix: 16);
