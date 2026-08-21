import 'dart:convert';

import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';

enum RecastMappingVariantSummaryKind {
  empty,
  strategiesOnly,
  mappedWithoutRules,
  mappedWithRules,
}

class RecastMappingVariantSummary {
  final int mappingCount;
  final int ruleCount;
  final int strategyCount;

  const RecastMappingVariantSummary({
    required this.mappingCount,
    required this.ruleCount,
    required this.strategyCount,
  });

  RecastMappingVariantSummaryKind get kind {
    if (mappingCount == 0 && ruleCount == 0) {
      return strategyCount == 0
          ? RecastMappingVariantSummaryKind.empty
          : RecastMappingVariantSummaryKind.strategiesOnly;
    }
    return ruleCount == 0
        ? RecastMappingVariantSummaryKind.mappedWithoutRules
        : RecastMappingVariantSummaryKind.mappedWithRules;
  }

  bool get hasEffectiveMapping => mappingCount > 0 || ruleCount > 0;
}

class ScriptRecastMappingVariantService {
  const ScriptRecastMappingVariantService();

  RecastScriptCache capture({
    required RecastScriptCache cache,
    required String id,
    required String name,
    required DateTime capturedAt,
    Map<String, String> targetCharacterNamesByRoleId = const {},
  }) {
    final normalizedId = id.trim();
    final normalizedName = name.trim();
    _validateCacheIdentity(cache);
    if (normalizedId.isEmpty) {
      throw const FormatException('映射版本 ID 不能为空。');
    }
    if (normalizedName.isEmpty) {
      throw const FormatException('映射版本名称不能为空。');
    }
    if (cache.mappingVariants.any((variant) => variant.id == normalizedId)) {
      throw const FormatException('映射版本 ID 已存在。');
    }

    final variant = RecastMappingVariant(
      id: normalizedId,
      name: normalizedName,
      scriptId: cache.scriptId,
      sourceFingerprint: cache.sourceFingerprint,
      sourceContentFingerprint: cache.sourceContentFingerprint,
      capturedAt: capturedAt.toUtc(),
      mapping: _mappingSnapshot(cache.mapping),
      targetCharacterNamesByRoleId: Map.unmodifiable({
        for (final entry in targetCharacterNamesByRoleId.entries)
          if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
            entry.key.trim(): entry.value.trim(),
      }),
    );
    return cache.copyWith(
      updatedAt: capturedAt.toUtc(),
      mappingVariants: List.unmodifiable([
        ...cache.mappingVariants,
        variant,
      ]),
      activeMappingVariantId: normalizedId,
    );
  }

  RecastScriptCache activate({
    required RecastScriptCache cache,
    required String variantId,
    required String expectedScriptId,
    required String expectedSourceFingerprint,
    required String expectedSourceContentFingerprint,
    required DateTime activatedAt,
  }) {
    final normalizedVariantId = variantId.trim();
    final normalizedScriptId = expectedScriptId.trim();
    final normalizedSourceFingerprint = expectedSourceFingerprint.trim();
    final normalizedSourceContentFingerprint =
        expectedSourceContentFingerprint.trim();
    if (normalizedVariantId.isEmpty) {
      throw const FormatException('映射版本 ID 不能为空。');
    }
    if (normalizedScriptId.isEmpty || normalizedSourceFingerprint.isEmpty) {
      throw const FormatException('当前剧本缺少可校验的来源指纹。');
    }
    if (cache.scriptId.trim() != normalizedScriptId ||
        cache.sourceFingerprint.trim() != normalizedSourceFingerprint) {
      throw const FormatException('当前缓存与打开的剧本不匹配，已拒绝切换。');
    }

    final variant = cache.mappingVariants
        .where((entry) => entry.id == normalizedVariantId)
        .firstOrNull;
    if (variant == null) {
      throw const FormatException('找不到要切换的映射版本。');
    }
    if (variant.scriptId.trim() != normalizedScriptId ||
        variant.mapping.scriptId.trim() != normalizedScriptId ||
        variant.sourceFingerprint.trim() != normalizedSourceFingerprint) {
      throw const FormatException('该版本属于其他剧本或来源，已拒绝切换。');
    }
    final variantContentFingerprint = variant.sourceContentFingerprint.trim();
    if (variantContentFingerprint.isNotEmpty &&
        normalizedSourceContentFingerprint.isNotEmpty &&
        variantContentFingerprint != normalizedSourceContentFingerprint) {
      throw const FormatException('该版本的源内容指纹已变化，已拒绝切换。');
    }

    final mapping = _mappingSnapshot(variant.mapping).copyWith(
      id: 'mapping-$normalizedScriptId',
      scriptId: normalizedScriptId,
    );
    return cache.copyWith(
      mapping: mapping,
      activeMappingVariantId: normalizedVariantId,
      updatedAt: activatedAt.toUtc(),
    );
  }

  RecastMappingVariantSummary summarize(RecastMapping mapping) {
    var mappingCount = mapping.roleSwaps.where((swap) {
      return swap.sourceRoleId.trim().isNotEmpty &&
          swap.targetCharacterId.trim().isNotEmpty;
    }).length;

    for (final assembly in mapping.roleAssemblies) {
      mappingCount += assembly.stages.where(_assemblyStageHasEffect).length;
    }
    mappingCount += mapping.rolePromptReplacements.where((replacement) {
      return replacement.targetCharacterId?.trim().isNotEmpty == true ||
          replacement.targetIdentityPrompt.trim().isNotEmpty;
    }).length;
    final artistSwap = mapping.artistSwap;
    if (artistSwap != null &&
        (artistSwap.targetArtistChainId.trim().isNotEmpty ||
            artistSwap.manualPrompt.trim().isNotEmpty ||
            artistSwap.deleteSource)) {
      mappingCount += 1;
    }
    mappingCount += mapping.promptBlockSwaps.where((swap) {
      return swap.manualPrompt.trim().isNotEmpty || swap.deleteSource;
    }).length;
    mappingCount += mapping.manualVibeRefs.length;

    final ruleCount = [
      for (final replacement in mapping.rolePromptReplacements)
        ...replacement.rules,
      for (final replacement in mapping.scenePromptReplacements)
        ...replacement.rules,
    ].where((rule) => rule.hasEffect).length;
    final strategyCount = mapping.suppressedPromptTagWarningKeys.length +
        (mapping.preservePresetId?.trim().isNotEmpty == true ? 1 : 0) +
        (mapping.outputPolicy?.trim().isNotEmpty == true ? 1 : 0);
    return RecastMappingVariantSummary(
      mappingCount: mappingCount,
      ruleCount: ruleCount,
      strategyCount: strategyCount,
    );
  }

  bool sameMapping(RecastMapping left, RecastMapping right) {
    return jsonEncode(stableJsonValue(left.toJson())) ==
        jsonEncode(stableJsonValue(right.toJson()));
  }

  void _validateCacheIdentity(RecastScriptCache cache) {
    if (cache.scriptId.trim().isEmpty ||
        cache.sourceFingerprint.trim().isEmpty) {
      throw const FormatException('当前剧本缺少可保存的来源指纹。');
    }
    if (cache.mapping.scriptId.trim() != cache.scriptId.trim()) {
      throw const FormatException('当前映射与剧本 ID 不一致。');
    }
  }

  bool _assemblyStageHasEffect(RoleAssemblyStage stage) {
    return stage.targetCharacterId?.trim().isNotEmpty == true ||
        stage.targetUpperOutfitId?.trim().isNotEmpty == true ||
        stage.targetLowerOutfitId?.trim().isNotEmpty == true ||
        stage.omittedParts.isNotEmpty ||
        stage.preservedParts.isNotEmpty ||
        !stage.manualParts.isEmpty;
  }

  RecastMapping _mappingSnapshot(RecastMapping mapping) {
    return RecastMapping.fromJson(
      Map<String, dynamic>.from(mapping.toJson()),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
