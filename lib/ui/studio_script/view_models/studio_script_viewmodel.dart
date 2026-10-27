import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/services/role_mapping_profile_repository.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_assembly_application.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_parser.dart';
import 'package:novel_studio/data/studio/services/script_recast_asset_context_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_path_rebinder.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_mapping_variant_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_production_service.dart';
import 'package:novel_studio/data/studio/services/script_role_mapping_profile_service.dart';
import 'package:novel_studio/data/studio/services/script_role_replacement_layer_service.dart';
import 'package:novel_studio/data/studio/tools/character_identity_prompt.dart';
import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';
import 'package:novel_studio/data/studio/tools/outfit_identity_prompt.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/ui/core/operation_status.dart';
import 'package:novel_studio/ui/studio_core/services/prompt_tag_filter_rules.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_recast_plan.dart';
import 'package:uuid/uuid.dart';

typedef StudioScriptDirectoryPicker = Future<String?> Function();
typedef StudioScriptCharactersLoader = Future<List<CharacterEntry>> Function();
typedef StudioScriptArtistChainsLoader = Future<List<ArtistChain>> Function();
typedef StudioScriptRecipesLoader = Future<List<Recipe>> Function();
typedef StudioScriptTagsLoader = Future<List<TagEntry>> Function();
typedef StudioScriptPromptAssetCategoriesLoader
    = Future<List<PromptAssetCategory>> Function();
typedef StudioScriptVibesLoader = Future<List<WorkspaceVibeReference>>
    Function();
typedef StudioScriptVibesImporter = Future<List<WorkspaceVibeReference>>
    Function();
typedef StudioScriptFilterRulesLoader = Future<Map<String, dynamic>> Function();
typedef StudioScriptFilterRulesSaver = Future<void> Function(
    Map<String, dynamic> filterRules);
typedef StudioScriptAssetContextLoader = Future<ScriptRecastAssetContext>
    Function();
typedef StudioScriptCacheSnapshotHydrator = Future<Script> Function({
  required Map<String, dynamic> scriptSnapshot,
  String? importPath,
});
typedef StudioScriptOpenTimingSink = void Function(
  StudioScriptOpenTiming timing,
);
typedef StudioScriptCachesLoader = Future<List<RecastScriptCache>> Function();
typedef StudioScriptCachesSaver = Future<void> Function(
    List<RecastScriptCache> caches);
typedef StudioScriptCacheByScriptIdLoader = Future<RecastScriptCache?> Function(
    String scriptId);
typedef StudioScriptCacheSnapshotByScriptIdRestorer
    = Future<RecastScriptCacheSnapshotRestore?> Function({
  required String scriptId,
  String? importPath,
});
typedef StudioScriptCacheSaver = Future<void> Function(RecastScriptCache cache);
typedef StudioScriptKnowledgeBaseLoader = Future<Map<String, dynamic>>
    Function();
typedef StudioScriptKnowledgeBaseSaver = Future<void> Function(
    Map<String, dynamic> knowledgeBase);
typedef StudioScriptAiSettingProvider = String Function();
typedef StudioScriptTagClassificationCacheSaver = Future<void> Function(
    PromptTagClassificationCache cache);
typedef StudioScriptTranslationCacheSaver = Future<void> Function(
    TranslationCache cache);

class StudioScriptReplacementSourceTermDraft {
  final String text;
  final PromptTagCategory category;

  const StudioScriptReplacementSourceTermDraft({
    required this.text,
    required this.category,
  });
}

class _AddedFrameReviewRuleResult {
  final List<ScriptPromptReplacementRule> rules;
  final String selectedRuleId;

  const _AddedFrameReviewRuleResult({
    required this.rules,
    required this.selectedRuleId,
  });
}

class _ReplacementRuleSplitResult {
  final List<ScriptPromptReplacementRule> rules;
  final String newRuleId;

  const _ReplacementRuleSplitResult({
    required this.rules,
    required this.newRuleId,
  });
}

sealed class _SelectedReplacementRuleTarget {
  const _SelectedReplacementRuleTarget();
}

class _SelectedRoleReplacementRuleTarget
    extends _SelectedReplacementRuleTarget {
  final String sourceRoleId;
  final String ruleId;

  const _SelectedRoleReplacementRuleTarget({
    required this.sourceRoleId,
    required this.ruleId,
  });
}

class _SelectedSceneReplacementRuleTarget
    extends _SelectedReplacementRuleTarget {
  final String groupId;
  final String ruleId;

  const _SelectedSceneReplacementRuleTarget({
    required this.groupId,
    required this.ruleId,
  });
}

enum StudioScriptTimelineStatus { warning, error, sent, failed }

enum StudioScriptAiProgressStepState { waiting, active, done, failed }

enum StudioScriptAiTraceEventKind {
  input,
  reasoning,
  content,
  parse,
  result,
  error,
}

class StudioScriptAiProgressStep {
  final String label;
  final StudioScriptAiProgressStepState state;

  const StudioScriptAiProgressStep({
    required this.label,
    this.state = StudioScriptAiProgressStepState.waiting,
  });

  StudioScriptAiProgressStep copyWith({
    StudioScriptAiProgressStepState? state,
  }) {
    return StudioScriptAiProgressStep(label: label, state: state ?? this.state);
  }
}

class StudioScriptAiTraceEvent {
  final StudioScriptAiTraceEventKind kind;
  final DateTime at;
  final String title;
  final String detail;

  const StudioScriptAiTraceEvent({
    required this.kind,
    required this.at,
    required this.title,
    required this.detail,
  });
}

class StudioScriptTimelineItem {
  final int frameIndex;
  final String label;
  final bool selected;
  final bool warning;
  final List<StudioScriptTimelineStatus> statuses;

  const StudioScriptTimelineItem({
    required this.frameIndex,
    required this.label,
    this.selected = false,
    this.warning = false,
    this.statuses = const [],
  });
}

class StudioScriptFrameTagGroup {
  final String id;
  final String label;
  final List<String> tags;

  const StudioScriptFrameTagGroup({
    required this.id,
    required this.label,
    this.tags = const [],
  });
}

class StudioScriptFrameSplitPreview {
  final String id;
  final String title;
  final List<StudioScriptFrameTagGroup> groups;

  const StudioScriptFrameSplitPreview({
    required this.id,
    required this.title,
    this.groups = const [],
  });
}

enum StudioScriptRolePart {
  identity,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
  nonRole,
}

class _AiRoleDraftParts {
  final String identity;
  final String upperBody;
  final String lowerBody;
  final String upperClothing;
  final String lowerClothing;
  final String nonRole;

  const _AiRoleDraftParts({
    this.identity = '',
    this.upperBody = '',
    this.lowerBody = '',
    this.upperClothing = '',
    this.lowerClothing = '',
    this.nonRole = '',
  });

  factory _AiRoleDraftParts.fromPromptParts(RecastPromptParts parts) {
    return _AiRoleDraftParts(
      identity: parts.identity,
      upperBody: parts.upperBody,
      lowerBody: parts.lowerBody,
      upperClothing: parts.upperClothing,
      lowerClothing: parts.lowerClothing,
    );
  }

  factory _AiRoleDraftParts.fromStage(ScriptAiExtractedStage stage) {
    return _AiRoleDraftParts(
      identity: stage.identity,
      upperBody: stage.upperBody,
      lowerBody: stage.lowerBody,
      upperClothing: stage.upperClothing,
      lowerClothing: stage.lowerClothing,
      nonRole: stage.nonRole,
    );
  }

  String textFor(StudioScriptRolePart part) {
    return switch (part) {
      StudioScriptRolePart.identity => identity,
      StudioScriptRolePart.upperBody => upperBody,
      StudioScriptRolePart.lowerBody => lowerBody,
      StudioScriptRolePart.upperClothing => upperClothing,
      StudioScriptRolePart.lowerClothing => lowerClothing,
      StudioScriptRolePart.nonRole => nonRole,
    };
  }

  bool containsTag(String tag) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (key.isEmpty) {
      return false;
    }
    return _contains(identity, key) ||
        _contains(upperBody, key) ||
        _contains(lowerBody, key) ||
        _contains(upperClothing, key) ||
        _contains(lowerClothing, key) ||
        _contains(nonRole, key);
  }

  static bool _contains(String text, String key) {
    return PromptTagProcessor.splitWorkshopTags(text)
        .map(PromptTagProcessor.cleanTagDisplay)
        .map(PromptTagProcessor.normalizeMatchKey)
        .contains(key);
  }

  @override
  bool operator ==(Object other) {
    return other is _AiRoleDraftParts &&
        other.identity == identity &&
        other.upperBody == upperBody &&
        other.lowerBody == lowerBody &&
        other.upperClothing == upperClothing &&
        other.lowerClothing == lowerClothing &&
        other.nonRole == nonRole;
  }

  @override
  int get hashCode => Object.hash(
        identity,
        upperBody,
        lowerBody,
        upperClothing,
        lowerClothing,
        nonRole,
      );
}

class StudioScriptRoleStageItem {
  final String id;
  final String label;
  final List<int> frameIndexes;
  final String sourceSummary;
  final RecastPromptParts sourceParts;
  final RecastPromptParts? currentFrameSourceParts;
  final RecastPromptParts parts;
  final String? selectedCharacterId;
  final String? selectedUpperOutfitId;
  final String? selectedLowerOutfitId;
  final Set<RecastPromptPart> omittedParts;

  const StudioScriptRoleStageItem({
    required this.id,
    required this.label,
    this.frameIndexes = const [],
    this.sourceSummary = '',
    this.sourceParts = const RecastPromptParts(),
    this.currentFrameSourceParts,
    this.parts = const RecastPromptParts(),
    this.selectedCharacterId,
    this.selectedUpperOutfitId,
    this.selectedLowerOutfitId,
    this.omittedParts = const {},
  });

  RecastPromptParts get visibleSourceParts => sourceParts;

  bool get isCurrentFrameSourceScoped => false;
}

class StudioScriptRoleMappingItem {
  final String sourceRoleId;
  final String sourceLabel;
  final String sourcePreview;
  final String? selectedCharacterId;
  final String? selectedOutfitId;
  final List<StudioScriptRoleStageItem> stageItems;
  final String? selectedStageId;

  const StudioScriptRoleMappingItem({
    required this.sourceRoleId,
    required this.sourceLabel,
    required this.sourcePreview,
    this.selectedCharacterId,
    this.selectedOutfitId,
    this.stageItems = const [],
    this.selectedStageId,
  });

  StudioScriptRoleStageItem? get selectedStage {
    if (stageItems.isEmpty) {
      return null;
    }
    return stageItems
            .where((stage) => stage.id == selectedStageId)
            .firstOrNull ??
        stageItems.first;
  }

  StudioScriptRoleMappingItem copyWith({
    Object? selectedCharacterId = _unset,
    Object? selectedOutfitId = _unset,
    List<StudioScriptRoleStageItem>? stageItems,
    Object? selectedStageId = _unset,
  }) {
    return StudioScriptRoleMappingItem(
      sourceRoleId: sourceRoleId,
      sourceLabel: sourceLabel,
      sourcePreview: sourcePreview,
      selectedCharacterId: identical(selectedCharacterId, _unset)
          ? this.selectedCharacterId
          : selectedCharacterId as String?,
      selectedOutfitId: identical(selectedOutfitId, _unset)
          ? this.selectedOutfitId
          : selectedOutfitId as String?,
      stageItems: stageItems ?? this.stageItems,
      selectedStageId: identical(selectedStageId, _unset)
          ? this.selectedStageId
          : selectedStageId as String?,
    );
  }
}

class StudioScriptReplacementRuleItem {
  final String id;
  final List<ScriptPromptReplacementTerm> sourceTerms;
  final List<String> excludedTermIds;
  final ScriptPromptReplacementAction action;
  final ScriptPromptReplacementMatchMode matchMode;
  final String targetPrompt;
  final double? targetWeightMultiplier;
  final String manualPhrase;
  final String anchorTermId;
  final bool selected;
  final ScriptRoleReplacementRuleLayerKind layerKind;
  final String layerStageId;
  final bool manuallyLayered;
  final bool hasStaleLayerOverride;

  const StudioScriptReplacementRuleItem({
    required this.id,
    this.sourceTerms = const [],
    this.excludedTermIds = const [],
    this.action = ScriptPromptReplacementAction.none,
    this.matchMode = ScriptPromptReplacementMatchMode.any,
    this.targetPrompt = '',
    this.targetWeightMultiplier,
    this.manualPhrase = '',
    this.anchorTermId = '',
    this.selected = false,
    this.layerKind = ScriptRoleReplacementRuleLayerKind.pending,
    this.layerStageId = '',
    this.manuallyLayered = false,
    this.hasStaleLayerOverride = false,
  });

  ScriptPromptReplacementAction get effectiveAction {
    if (action == ScriptPromptReplacementAction.delete) {
      return ScriptPromptReplacementAction.delete;
    }
    if (targetPrompt.trim().isNotEmpty) {
      return ScriptPromptReplacementAction.replace;
    }
    if (targetWeightMultiplier != null) {
      return ScriptPromptReplacementAction.replace;
    }
    return ScriptPromptReplacementAction.none;
  }

  StudioScriptReplacementRuleItem copyWith({
    List<ScriptPromptReplacementTerm>? sourceTerms,
    List<String>? excludedTermIds,
    ScriptPromptReplacementAction? action,
    ScriptPromptReplacementMatchMode? matchMode,
    String? targetPrompt,
    double? targetWeightMultiplier,
    String? manualPhrase,
    String? anchorTermId,
    bool? selected,
    ScriptRoleReplacementRuleLayerKind? layerKind,
    String? layerStageId,
    bool? manuallyLayered,
    bool? hasStaleLayerOverride,
  }) {
    return StudioScriptReplacementRuleItem(
      id: id,
      sourceTerms: sourceTerms ?? this.sourceTerms,
      excludedTermIds: excludedTermIds ?? this.excludedTermIds,
      action: action ?? this.action,
      matchMode: matchMode ?? this.matchMode,
      targetPrompt: targetPrompt ?? this.targetPrompt,
      targetWeightMultiplier:
          targetWeightMultiplier ?? this.targetWeightMultiplier,
      manualPhrase: manualPhrase ?? this.manualPhrase,
      anchorTermId: anchorTermId ?? this.anchorTermId,
      selected: selected ?? this.selected,
      layerKind: layerKind ?? this.layerKind,
      layerStageId: layerStageId ?? this.layerStageId,
      manuallyLayered: manuallyLayered ?? this.manuallyLayered,
      hasStaleLayerOverride:
          hasStaleLayerOverride ?? this.hasStaleLayerOverride,
    );
  }
}

class StudioScriptRoleReplacementLayerItem {
  final String id;
  final String label;
  final ScriptRoleReplacementRuleLayerKind kind;
  final String stageId;
  final List<int> frameIndexes;
  final List<StudioScriptReplacementRuleItem> rules;
  final int mappedRuleCount;

  const StudioScriptRoleReplacementLayerItem({
    required this.id,
    required this.label,
    required this.kind,
    this.stageId = '',
    this.frameIndexes = const [],
    this.rules = const [],
    this.mappedRuleCount = 0,
  });

  int get ruleCount => rules.length;
}

class StudioScriptRoleReplacementItem {
  final String sourceRoleId;
  final String sourceLabel;
  final String sourcePreview;
  final String? targetCharacterId;
  final String targetIdentityPrompt;
  final String? activeMappingProfileId;
  final List<StudioScriptReplacementRuleItem> rules;
  final List<StudioScriptRoleReplacementLayerItem> layers;

  const StudioScriptRoleReplacementItem({
    required this.sourceRoleId,
    required this.sourceLabel,
    required this.sourcePreview,
    this.targetCharacterId,
    this.targetIdentityPrompt = '',
    this.activeMappingProfileId,
    this.rules = const [],
    this.layers = const [],
  });

  int get stageCount => layers
      .where((layer) => layer.kind == ScriptRoleReplacementRuleLayerKind.stage)
      .length;

  int get pendingRuleCount => layers
      .where(
          (layer) => layer.kind == ScriptRoleReplacementRuleLayerKind.pending)
      .fold(0, (count, layer) => count + layer.ruleCount);

  StudioScriptRoleReplacementItem copyWith({
    Object? targetCharacterId = _unset,
    String? targetIdentityPrompt,
    Object? activeMappingProfileId = _unset,
    List<StudioScriptReplacementRuleItem>? rules,
    List<StudioScriptRoleReplacementLayerItem>? layers,
  }) {
    return StudioScriptRoleReplacementItem(
      sourceRoleId: sourceRoleId,
      sourceLabel: sourceLabel,
      sourcePreview: sourcePreview,
      targetCharacterId: identical(targetCharacterId, _unset)
          ? this.targetCharacterId
          : targetCharacterId as String?,
      targetIdentityPrompt: targetIdentityPrompt ?? this.targetIdentityPrompt,
      activeMappingProfileId: identical(activeMappingProfileId, _unset)
          ? this.activeMappingProfileId
          : activeMappingProfileId as String?,
      rules: rules ?? this.rules,
      layers: layers ?? this.layers,
    );
  }
}

class StudioScriptSceneReplacementItem {
  final String id;
  final String label;
  final List<StudioScriptReplacementRuleItem> rules;

  const StudioScriptSceneReplacementItem({
    required this.id,
    required this.label,
    this.rules = const [],
  });

  StudioScriptSceneReplacementItem copyWith({
    List<StudioScriptReplacementRuleItem>? rules,
  }) {
    return StudioScriptSceneReplacementItem(
      id: id,
      label: label,
      rules: rules ?? this.rules,
    );
  }
}

class StudioScriptArtistMappingItem {
  final String sourceLabel;
  final String? selectedArtistChainId;
  final String manualPrompt;
  final bool deleteSource;

  const StudioScriptArtistMappingItem({
    required this.sourceLabel,
    this.selectedArtistChainId,
    this.manualPrompt = '',
    this.deleteSource = false,
  });
}

class StudioScriptPromptBlockMappingItem {
  final String block;
  final String label;
  final String sourcePrompt;
  final String manualPrompt;
  final bool deleteSource;

  const StudioScriptPromptBlockMappingItem({
    required this.block,
    required this.label,
    required this.sourcePrompt,
    this.manualPrompt = '',
    this.deleteSource = false,
  });
}

class StudioScriptMappingVariantItem {
  final String id;
  final String name;
  final DateTime capturedAt;
  final RecastMappingVariantSummary summary;
  final List<String> targetCharacterNames;
  final Map<String, String> targetCharacterNamesByRoleId;
  final bool isActive;
  final bool isModified;

  const StudioScriptMappingVariantItem({
    required this.id,
    required this.name,
    required this.capturedAt,
    required this.summary,
    this.targetCharacterNames = const [],
    this.targetCharacterNamesByRoleId = const {},
    required this.isActive,
    required this.isModified,
  });

  String get summaryLabel => _mappingVariantSummaryLabel(summary);

  String? targetCharacterNameForRole(String sourceRoleId) {
    final value = targetCharacterNamesByRoleId[sourceRoleId]?.trim() ?? '';
    return value.isEmpty ? null : value;
  }
}

String _mappingVariantSummaryLabel(RecastMappingVariantSummary summary) {
  return switch (summary.kind) {
    RecastMappingVariantSummaryKind.empty => '空映射（无规则）',
    RecastMappingVariantSummaryKind.strategiesOnly =>
      '无映射 · ${summary.strategyCount} 项策略',
    RecastMappingVariantSummaryKind.mappedWithoutRules =>
      '${summary.mappingCount} 项映射 · 无规则',
    RecastMappingVariantSummaryKind.mappedWithRules =>
      '${summary.mappingCount} 项映射 · ${summary.ruleCount} 条规则',
  };
}

const Object _unset = Object();

class StudioScriptDiff {
  final String original;
  final String recast;

  const StudioScriptDiff({required this.original, required this.recast});
}

class StudioScriptOpenTiming {
  final String operation;
  final String stage;
  final Duration elapsed;
  final bool cacheHit;

  const StudioScriptOpenTiming({
    required this.operation,
    required this.stage,
    required this.elapsed,
    this.cacheHit = false,
  });
}

Future<Script> defaultStudioScriptCacheSnapshotHydrator({
  required Map<String, dynamic> scriptSnapshot,
  String? importPath,
}) {
  return Isolate.run(() {
    final cachedScript = Script.fromJson(scriptSnapshot);
    final normalizedImportPath = importPath?.trim();
    if (normalizedImportPath == null || normalizedImportPath.isEmpty) {
      return cachedScript;
    }
    return rebindCachedScriptToImportDirectory(
      cachedScript,
      Directory(normalizedImportPath),
    );
  });
}

class StudioScriptViewModel extends ChangeNotifier {
  static const List<String> _requiredScriptMappingProfileNames = [
    '佩佩（无兜帽）',
    '铃兰',
    '巫恋',
    '迷迭香',
    '薄绿',
    '洛可可',
    '洛茜',
    '果宝',
    '佩佩（星移）',
  ];
  static const String _autoGlobalProfileVariantIdPrefix =
      'auto-global-profile-';

  final StudioScriptDirectoryPicker? pickScriptDirectory;
  final ScriptRecastParserService parserService;
  final ScriptRecastEngine recastEngine;
  final ScriptRecastProductionService? productionService;
  final StudioScriptCharactersLoader? loadCharacters;
  final StudioScriptArtistChainsLoader? loadArtistChains;
  final StudioScriptRecipesLoader? loadRecipes;
  final StudioScriptTagsLoader? loadTags;
  final StudioScriptPromptAssetCategoriesLoader? loadPromptAssetCategories;
  final StudioScriptVibesLoader? loadVibes;
  final StudioScriptVibesImporter? importVibes;
  final StudioScriptFilterRulesLoader? loadFilterRules;
  final StudioScriptFilterRulesSaver? saveFilterRules;
  final StudioScriptAssetContextLoader? loadAssetContext;
  final StudioScriptCachesLoader? loadRecastCaches;
  final StudioScriptCachesSaver? saveRecastCaches;
  final StudioScriptCacheByScriptIdLoader? loadRecastCacheByScriptId;
  final StudioScriptCacheSnapshotByScriptIdRestorer?
      restoreRecastCacheSnapshotByScriptId;
  final StudioScriptCacheSaver? saveRecastCache;
  final StudioScriptKnowledgeBaseLoader? loadRecastKnowledgeBase;
  final StudioScriptKnowledgeBaseSaver? saveRecastKnowledgeBase;
  final StudioScriptCacheSnapshotHydrator hydrateCachedScriptSnapshot;
  final StudioScriptOpenTimingSink? openTimingSink;
  final ScriptAiRoleExtractionService? scriptAiRoleExtractionService;
  final ScriptRecastCacheRestoreService cacheRestoreService;
  final StudioScriptAiSettingProvider? scriptAiBaseUrlProvider;
  final StudioScriptAiSettingProvider? scriptAiTokenProvider;
  final StudioScriptAiSettingProvider? scriptAiModelProvider;
  final StudioScriptAiSettingProvider? scriptAiReasoningEffortProvider;
  final StudioScriptAiSettingProvider? scriptAiProxyProvider;
  final TranslationCache translationCache;
  final PromptTagClassificationCache classificationCache;
  final StudioScriptTranslationCacheSaver? saveTranslationCache;
  final StudioScriptTagClassificationCacheSaver? saveClassificationCache;
  final RoleMappingProfileRepository? roleMappingProfileRepository;
  final ScriptRoleMappingProfileService roleMappingProfileService;
  final ScriptRoleReplacementLayerService roleReplacementLayerService;
  final ScriptRecastMappingVariantService mappingVariantService;
  final Duration recastCacheRefreshDebounce;

  Script? _script;
  _ScriptSourceTermFrameIndex? _sourceTermFrameIndex;
  RecastMapping? _mapping;
  List<RecastMappingVariant> _mappingVariants = const [];
  String? _activeMappingVariantId;
  RecastScriptCache? _changedSourceCache;
  ScriptRecastResult? _previewResult;
  List<CharacterEntry> _characters = const [];
  List<ArtistChain> _availableArtistChains = const [];
  List<Recipe> _availableRecipes = const [];
  List<TagEntry> _availableTags = const [];
  List<PromptAssetCategory> _promptAssetCategories = const [];
  List<WorkspaceVibeReference> _availableVibes = const [];
  Map<String, String> _characterPreviewPaths = const {};
  Map<String, String> _outfitPreviewPaths = const {};
  Map<String, String> _artistChainPreviewPaths = const {};
  String? _artistSourceLabelOverride;
  FilterRuleConfig _filterRuleConfig = const FilterRuleConfig();
  bool _assetsLoaded = false;
  int? _selectedFrameIndex;
  final Map<String, String> _manualSelectedStageIdsByRole = <String, String>{};
  final Map<String, Set<String>> _selectedRoleReplacementRuleIdsByRole =
      <String, Set<String>>{};
  final Map<String, Set<String>> _selectedSceneReplacementRuleIdsByGroup =
      <String, Set<String>>{};
  int _roleStageEditBatchDepth = 0;
  final Set<String> _batchedRoleEditSourceRoleIds = <String>{};
  bool _batchedRoleEditNeedsCacheSave = false;
  int _aiProgressIndex = -1;
  int _aiOperationGeneration = 0;
  bool _aiRoleExtractionDraftDismissed = false;
  bool _aiRoleExtractionDraftSuppressed = false;
  bool _aiRoleExtractionFinalized = false;
  Map<int, FrameResultStatus> _frameResultStatuses = const {};

  String folderStatus = '未导入剧本目录';
  int frameCount = 0;
  int parsedCount = 0;
  int warningCount = 0;
  int roleCount = 0;
  bool sentToProduction = false;
  String? lastProductionPlanId;
  String? lastProductionPlanName;
  String schemaLabel = 'unknown';
  String globalBlockWords = '';
  String scriptBlockWords = '';
  String globalPromptPrefix = '';
  String globalBlockWordsStatus = '未设置全局屏蔽词';
  String analysisStatus = '尚未分析角色';
  String cacheStatus = '未载入缓存';
  String aiStatus = '尚未进行 AI 分析';
  OperationStatus importOperationStatus = const OperationStatus.idle();
  OperationStatus cacheOperationStatus = const OperationStatus.idle();
  OperationStatus aiOperationStatus = const OperationStatus.idle();
  List<String> roles = const [];
  bool isExtractingAiRoleEvidence = false;
  bool isApplyingAiRoleExtraction = false;
  bool isSendingToProduction = false;
  bool isImportingScript = false;
  String importProgressLabel = '';
  double? importProgressValue;
  String aiProgressTitle = '';
  List<StudioScriptAiProgressStep> aiProgressSteps = const [];
  List<String> artistChains = const [];
  ScriptAiRoleExtraction aiRoleExtraction = const ScriptAiRoleExtraction();
  Map<String, dynamic> aiRoleExtractionRequestPreview = const {};
  String aiRoleExtractionReasoningContent = '';
  String aiRoleExtractionStreamingContent = '';
  List<StudioScriptAiTraceEvent> aiRoleExtractionTraceEvents = const [];
  List<ScriptAiRoleExtraction> aiRoleExtractionChunks = const [];
  int aiRoleExtractionRequestCount = 0;
  DateTime? _lastAiRoleExtractionStreamNotifyAt;
  int _pendingAiRoleExtractionStreamChars = 0;
  Timer? _aiRoleExtractionStreamNotifyTimer;
  Timer? _cacheSaveDebounceTimer;
  Timer? _recastCacheRefreshTimer;
  StreamSubscription<void>? _recastCacheChangesSubscription;
  Future<void>? _cacheSaveTail;
  int _mappingVariantRefreshGeneration = 0;
  int _deferredAssetRefreshGeneration = 0;
  int _scriptOpenGeneration = 0;
  int _productionSendGeneration = 0;
  bool _disposed = false;
  bool _roleMappingProfilesLoaded = false;
  final List<RoleMappingProfileDeletionPrompt>
      _pendingRoleMappingProfileDeletions = [];
  List<StudioScriptRoleMappingItem> roleMappings = const [];
  List<StudioScriptRoleReplacementItem> roleReplacementMappings = const [];
  List<StudioScriptSceneReplacementItem> sceneReplacementMappings = const [];
  List<StudioScriptArtistMappingItem> artistMappings = const [];
  List<StudioScriptPromptBlockMappingItem> promptBlockMappings = const [];
  List<String> warnings = const [];
  List<StudioScriptTimelineItem> timeline = const [];
  List<StudioScriptFrameTagGroup> selectedFrameTagGroups = const [];
  List<StudioScriptFrameSplitPreview> selectedFramePreviews = const [];
  StudioScriptDiff diff = const StudioScriptDiff(original: '', recast: '');
  StudioScriptRecastPlan recastPlan = const StudioScriptRecastPlan();
  List<RoleMappingProfile> roleMappingProfiles = const [];
  String roleMappingProfileStatus = '';
  Object? roleMappingProfileError;
  String mappingVariantStatus = '';

  List<CharacterEntry> get characterOptions => _characters;

  List<ArtistChain> get artistChainOptions => _availableArtistChains;

  List<Recipe> get recipeOptions => _availableRecipes;

  List<TagEntry> get tagOptions => _availableTags;

  List<PromptAssetCategory> get promptAssetCategories => _promptAssetCategories;

  List<WorkspaceVibeReference> get vibeOptions => _availableVibes;

  List<WorkspaceVibeReference> get sourceVibeOptions =>
      _sourceVibesFromScript(_script, _availableVibes);

  List<WorkspaceVibeReference> get selectedManualVibes =>
      _mapping?.manualVibeRefs ?? const [];

  String get targetGenerationModel => studioTargetGenerationModelFor(
        _mapping?.targetGenerationModel,
      );

  GenerationModelCapabilities get targetGenerationCapabilities =>
      GenerationModelCapabilities.fromModel(targetGenerationModel);

  bool get targetSupportsVibeTransfer =>
      targetGenerationCapabilities.supportsVibeTransfer;

  RecastMapping? get currentMapping => _mapping;

  List<RecastMappingVariant> get mappingVariants =>
      List.unmodifiable(_mappingVariants);

  String? get activeMappingVariantId => _activeMappingVariantId;

  RecastMappingVariantSummary? get currentMappingVariantSummary {
    final mapping = _mapping;
    return mapping == null ? null : mappingVariantService.summarize(mapping);
  }

  String get currentMappingVariantSummaryLabel {
    final summary = currentMappingVariantSummary;
    return summary == null ? '尚无剧本映射' : _mappingVariantSummaryLabel(summary);
  }

  Map<String, String> get currentMappingTargetCharacterNamesByRoleId {
    final mapping = _mapping;
    return mapping == null ? const {} : _targetCharacterNamesByRoleId(mapping);
  }

  bool get hasOpenScript => _script != null;

  bool get canPersistMappingVariants =>
      saveRecastCache != null ||
      (loadRecastCaches != null && saveRecastCaches != null);

  List<StudioScriptMappingVariantItem> get mappingVariantItems {
    final currentMapping = _mapping;
    final variants = [..._mappingVariants]
      ..sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return List.unmodifiable([
      for (final variant in variants)
        StudioScriptMappingVariantItem(
          id: variant.id,
          name: variant.name,
          capturedAt: variant.capturedAt,
          summary: mappingVariantService.summarize(variant.mapping),
          targetCharacterNames: List.unmodifiable(
            variant.targetCharacterNamesByRoleId.values.toSet()..remove(''),
          ),
          targetCharacterNamesByRoleId:
              Map.unmodifiable(variant.targetCharacterNamesByRoleId),
          isActive: variant.id == _activeMappingVariantId,
          isModified: variant.id == _activeMappingVariantId &&
              currentMapping != null &&
              !mappingVariantService.sameMapping(
                currentMapping,
                variant.mapping,
              ),
        ),
    ]);
  }

  Set<String> get suppressedPromptTagWarningKeys =>
      _mapping?.suppressedPromptTagWarningKeys ?? const {};

  String? characterPreviewPath(CharacterEntry character) =>
      _firstPreviewPath(characterPreviewPaths(character));

  List<String> characterPreviewPaths(CharacterEntry character) =>
      _previewPathsForAsset(
        _characterPreviewPaths[character.id],
        character.imageRefs,
      );

  String? outfitPreviewPath(CharacterEntry character, WorkspaceOutfit outfit) =>
      _firstPreviewPath(outfitPreviewPaths(character, outfit));

  List<String> outfitPreviewPaths(
    CharacterEntry character,
    WorkspaceOutfit outfit,
  ) =>
      _previewPathsForAsset(
        _outfitPreviewPaths[ScriptRecastAssetContext.outfitKey(
          character.id,
          outfit.id,
        )],
        outfit.imageRefs,
      );

  String? artistChainPreviewPath(ArtistChain chain) =>
      _firstPreviewPath(artistChainPreviewPaths(chain));

  List<String> artistChainPreviewPaths(ArtistChain chain) =>
      _artistChainPreviewPathsForTargetModel(chain);

  List<String> _artistChainPreviewPathsForTargetModel(ArtistChain chain) {
    final previewFamily =
        generationPreviewFamilyForModel(targetGenerationModel);
    final modelPreviewRefs = previewFamily == null
        ? const <String>[]
        : chain.previewRefsForFamily(previewFamily);
    if (modelPreviewRefs.isNotEmpty) {
      return _previewPathsForAsset(null, modelPreviewRefs);
    }
    return _previewPathsForAsset(
      _artistChainPreviewPaths[chain.id],
      chain.imageRefs,
    );
  }

  bool artistChainHasTargetModelPreview(ArtistChain chain) {
    final previewFamily =
        generationPreviewFamilyForModel(targetGenerationModel);
    return previewFamily != null &&
        chain.previewRefsForFamily(previewFamily).isNotEmpty;
  }

  bool get hasChangedSourceCache => _changedSourceCache != null;
  int? get selectedFrameIndex => _selectedFrameIndex;

  bool get isAiBusy => isExtractingAiRoleEvidence || isApplyingAiRoleExtraction;

  bool get supportsRoleMappingProfiles => roleMappingProfileRepository != null;

  bool get roleMappingProfilesLoaded => _roleMappingProfilesLoaded;

  RoleMappingProfileDeletionPrompt? get pendingRoleMappingProfileDeletion =>
      _pendingRoleMappingProfileDeletions.firstOrNull;

  bool get showAiProgressPanel => aiProgressSteps.isNotEmpty;

  bool get showAiRoleExtractionDraftPanel =>
      !_aiRoleExtractionDraftSuppressed && !_aiRoleExtractionDraftDismissed;

  bool get isAiRoleExtractionDraftCollapsed =>
      !_aiRoleExtractionDraftSuppressed && _aiRoleExtractionDraftDismissed;

  bool get isAiRoleExtractionDraftSuppressed =>
      _aiRoleExtractionDraftSuppressed;

  StudioScriptViewModel({
    this.pickScriptDirectory,
    this.parserService = const ScriptRecastParserService(),
    this.recastEngine = const ScriptRecastEngine(),
    this.productionService,
    this.loadCharacters,
    this.loadArtistChains,
    this.loadRecipes,
    this.loadTags,
    this.loadPromptAssetCategories,
    this.loadVibes,
    this.importVibes,
    this.loadFilterRules,
    this.saveFilterRules,
    this.loadAssetContext,
    this.loadRecastCaches,
    this.saveRecastCaches,
    this.loadRecastCacheByScriptId,
    this.restoreRecastCacheSnapshotByScriptId,
    this.saveRecastCache,
    this.loadRecastKnowledgeBase,
    this.saveRecastKnowledgeBase,
    StudioScriptCacheSnapshotHydrator? hydrateCachedScriptSnapshot,
    this.openTimingSink,
    this.scriptAiRoleExtractionService,
    this.cacheRestoreService = const ScriptRecastCacheRestoreService(),
    this.scriptAiBaseUrlProvider,
    this.scriptAiTokenProvider,
    this.scriptAiModelProvider,
    this.scriptAiReasoningEffortProvider,
    this.scriptAiProxyProvider,
    TranslationCache? translationCache,
    PromptTagClassificationCache? classificationCache,
    this.saveTranslationCache,
    this.saveClassificationCache,
    this.roleMappingProfileRepository,
    this.roleMappingProfileService = const ScriptRoleMappingProfileService(),
    this.roleReplacementLayerService =
        const ScriptRoleReplacementLayerService(),
    this.mappingVariantService = const ScriptRecastMappingVariantService(),
    Stream<void>? recastCacheChanges,
    this.recastCacheRefreshDebounce = const Duration(milliseconds: 600),
  })  : translationCache = translationCache ?? TranslationCache(),
        hydrateCachedScriptSnapshot = hydrateCachedScriptSnapshot ??
            defaultStudioScriptCacheSnapshotHydrator,
        classificationCache =
            classificationCache ?? PromptTagClassificationCache() {
    _recastCacheChangesSubscription = recastCacheChanges?.listen(
      (_) => _scheduleCurrentMappingVariantsRefresh(),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'Failed to watch script recast cache changes: '
          '$error\n$stackTrace',
        );
      },
    );
  }

  Future<void> ensureRoleMappingProfilesLoaded({bool force = false}) async {
    final repository = roleMappingProfileRepository;
    if (repository == null || (_roleMappingProfilesLoaded && !force)) {
      return;
    }
    try {
      final library = await repository.load();
      if (_disposed) return;
      _setRoleMappingProfileLibrary(library);
      _roleMappingProfilesLoaded = true;
      roleMappingProfileError = null;
      roleMappingProfileStatus = library.profiles.isEmpty
          ? '暂无全局角色档案'
          : '已加载 ${library.profiles.length} 个全局角色档案';
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      _roleMappingProfilesLoaded = true;
      roleMappingProfileError = error;
      roleMappingProfileStatus = '全局角色档案加载失败，原文件未被覆盖';
      notifyListeners();
    }
  }

  RoleMappingProfile? roleMappingProfileById(String? profileId) {
    if (profileId == null || profileId.trim().isEmpty) return null;
    return roleMappingProfiles
        .where((profile) => profile.id == profileId)
        .firstOrNull;
  }

  RoleMappingProfile? activeRoleMappingProfile(String sourceRoleId) {
    final replacement = _roleReplacementById(sourceRoleId);
    return roleMappingProfileById(replacement?.activeMappingProfileId);
  }

  Map<String, String> _targetCharacterNamesByRoleId(RecastMapping mapping) {
    final result = <String, String>{};

    void record(
      String roleKey,
      String? characterId, {
      String? profileId,
    }) {
      final normalizedRoleKey = roleKey.trim();
      final normalizedCharacterId = characterId?.trim() ?? '';
      if (normalizedRoleKey.isEmpty) return;
      final profileName =
          roleMappingProfileById(profileId)?.targetCharacterNameSnapshot.trim();
      final characterName = normalizedCharacterId.isEmpty
          ? null
          : _characterById(normalizedCharacterId)?.name.trim();
      final resolvedName = profileName?.isNotEmpty == true
          ? profileName!
          : characterName?.isNotEmpty == true
              ? characterName!
              : normalizedCharacterId;
      if (resolvedName.isNotEmpty) {
        result[normalizedRoleKey] = resolvedName;
      }
    }

    for (final swap in mapping.roleSwaps) {
      record(swap.sourceRoleId, swap.targetCharacterId);
    }
    for (final replacement in mapping.rolePromptReplacements) {
      record(
        replacement.sourceRoleId,
        replacement.targetCharacterId,
        profileId: replacement.activeMappingProfileId,
      );
    }
    for (final assembly in mapping.roleAssemblies) {
      for (final stage in assembly.stages) {
        record(
          '${assembly.sourceRoleId}/${stage.id}',
          stage.targetCharacterId,
        );
      }
    }
    return Map.unmodifiable(result);
  }

  List<ScriptPromptReplacementTerm> roleMappingProfileAvailableTerms(
    String sourceRoleId,
  ) {
    final replacement = _roleReplacementById(sourceRoleId);
    if (replacement == null) return const [];
    return List.unmodifiable([
      for (final rule in replacement.rules)
        for (final term in rule.sourceTerms)
          if (!rule.excludedTermIds.contains(term.id)) term,
    ]);
  }

  Future<RoleMappingProfile> createRoleMappingProfile({
    required String name,
    required String sourceRoleId,
  }) async {
    final repository = _requireRoleMappingProfileRepository();
    final replacement = _requireRoleReplacement(sourceRoleId);
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('全局角色档案名称不能为空。');
    }
    final characterName = replacement.targetCharacterId == null
        ? ''
        : _characterById(replacement.targetCharacterId!)?.name ?? '';
    final profile = _profileForRoleMappingApplication(
      roleMappingProfileService.createProfile(
        id: const Uuid().v4(),
        name: normalizedName,
        replacement: replacement,
        targetCharacterNameSnapshot: characterName,
        now: DateTime.now().toUtc(),
        assembly: _roleAssemblyById(sourceRoleId),
      ),
    );
    final library = await repository.update(
      (current) => current.copyWith(
        profiles: List.unmodifiable([...current.profiles, profile]),
      ),
    );
    if (_disposed) return profile;
    _setRoleMappingProfileLibrary(library);
    roleMappingProfileError = null;
    roleMappingProfileStatus = '已创建全局角色档案：${profile.name}（当前角色未开启同步）';
    notifyListeners();
    _scheduleCurrentCacheSave();
    return profile;
  }

  Future<RoleMappingProfile> updateRoleMappingProfile(
    RoleMappingProfile profile,
  ) async {
    final repository = _requireRoleMappingProfileRepository();
    final normalized = _normalizedRoleMappingProfile(
      _profileForRoleMappingApplication(
        profile.copyWith(updatedAt: DateTime.now().toUtc()),
      ),
    );
    final library = await repository.update((current) {
      if (!current.profiles.any((entry) => entry.id == normalized.id)) {
        throw StateError('全局角色档案已不存在：${normalized.id}');
      }
      return current.copyWith(
        profiles: List.unmodifiable([
          for (final entry in current.profiles)
            if (entry.id == normalized.id) normalized else entry,
        ]),
      );
    });
    if (!_disposed) {
      _setRoleMappingProfileLibrary(library);
      roleMappingProfileError = null;
      roleMappingProfileStatus = '已保存：${normalized.name}';
      notifyListeners();
    }
    return normalized;
  }

  Future<RoleMappingProfile> duplicateRoleMappingProfile(
    String profileId, {
    String? name,
  }) async {
    final source = roleMappingProfileById(profileId);
    if (source == null) {
      throw StateError('全局角色档案已不存在：$profileId');
    }
    final repository = _requireRoleMappingProfileRepository();
    final now = DateTime.now().toUtc();
    late RoleMappingProfile duplicate;
    final library = await repository.update((current) {
      final nextName = name?.trim().isNotEmpty == true
          ? name!.trim()
          : _uniqueRoleMappingProfileCopyName(source.name, current.profiles);
      duplicate = source.copyWith(
        id: const Uuid().v4(),
        name: nextName,
        createdAt: now,
        updatedAt: now,
      );
      return current.copyWith(
        profiles: List.unmodifiable([...current.profiles, duplicate]),
      );
    });
    if (!_disposed) {
      _setRoleMappingProfileLibrary(library);
      roleMappingProfileStatus = '已复制：${duplicate.name}';
      notifyListeners();
    }
    return duplicate;
  }

  Future<void> deleteRoleMappingProfile(String profileId) async {
    final repository = _requireRoleMappingProfileRepository();
    final profile = roleMappingProfileById(profileId);
    final library = await repository.update(
      (current) => current.copyWith(
        profiles: List.unmodifiable([
          for (final entry in current.profiles)
            if (entry.id != profileId) entry,
        ]),
      ),
    );
    if (_disposed) return;
    _setRoleMappingProfileLibrary(library);
    _detachRoleMappingProfile(profileId);
    roleMappingProfileStatus =
        profile == null ? '全局角色档案已删除' : '已删除：${profile.name}';
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void stopRoleMappingProfileRecording(String sourceRoleId) {
    if (!_setRoleReplacementActiveProfile(sourceRoleId, null)) return;
    roleMappingProfileStatus = '已断开当前角色与全局角色档案的同步';
    _refreshReplacementMappings();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  RoleMappingApplyPreview previewRoleMappingProfile({
    required String profileId,
    required String sourceRoleId,
  }) {
    final profile = roleMappingProfileById(profileId);
    if (profile == null) {
      throw StateError('全局角色档案已不存在：$profileId');
    }
    return roleMappingProfileService.buildPreview(
      profile: _profileForRoleMappingApplication(profile),
      replacement: _requireRoleReplacement(sourceRoleId),
      assembly: _roleAssemblyById(sourceRoleId),
    );
  }

  Future<bool> quickApplyRoleMappingProfile({
    required String profileId,
    required String sourceRoleId,
  }) async {
    final preview = previewRoleMappingProfile(
      profileId: profileId,
      sourceRoleId: sourceRoleId,
    );
    final selections = [
      for (final entry in preview.entries)
        if (entry.selectedByDefault && entry.selectedTermIds.isNotEmpty)
          RoleMappingProfileApplySelection(
            blockId: entry.block.id,
            termIds: entry.selectedTermIds,
          ),
    ];
    return applyRoleMappingProfile(
      profileId: profileId,
      sourceRoleId: sourceRoleId,
      selections: selections,
      applyIdentity: true,
    );
  }

  Future<bool> applyRoleMappingProfile({
    required String profileId,
    required String sourceRoleId,
    required List<RoleMappingProfileApplySelection> selections,
    bool applyIdentity = true,
    bool linkProfile = false,
    List<RoleMappingProfileLayerApplySelection> layerSelections = const [],
  }) async {
    final repository = _requireRoleMappingProfileRepository();
    final profile = roleMappingProfileById(profileId);
    if (profile == null) {
      throw StateError('全局角色档案已不存在：$profileId');
    }
    final before = _requireRoleReplacement(sourceRoleId);
    final library = await repository.update((current) {
      final latest =
          current.profiles.where((entry) => entry.id == profileId).firstOrNull;
      if (latest == null) {
        throw StateError('全局角色档案已不存在：$profileId');
      }
      final latestForTarget = _profileForRoleMappingApplication(latest);
      final learned = roleMappingProfileService.withAppliedCompanionTerms(
        profile: latestForTarget,
        sourceReplacement: before,
        selections: selections,
        now: DateTime.now().toUtc(),
      );
      return current.copyWith(
        profiles: List.unmodifiable([
          for (final entry in current.profiles)
            if (entry.id == profileId) learned else entry,
        ]),
      );
    });
    if (_disposed) return false;
    _setRoleMappingProfileLibrary(library);
    final latestProfile = roleMappingProfileById(profileId)!;
    final applicableProfile = latestProfile.targetCharacterId != null &&
            _characterById(latestProfile.targetCharacterId!) == null
        ? latestProfile.copyWith(targetCharacterId: null)
        : latestProfile;
    final applied = roleMappingProfileService.applySelections(
      profile: applicableProfile,
      replacement: before,
      selections: selections,
      applyIdentity: applyIdentity,
      linkProfile: linkProfile,
      layerSelections: layerSelections,
      assembly: _roleAssemblyById(sourceRoleId),
    );
    final identityChanged =
        applied.targetCharacterId != before.targetCharacterId ||
            applied.targetIdentityPrompt != before.targetIdentityPrompt;
    final mappingChanged = jsonEncode([
              for (final rule in applied.rules) rule.toJson(),
            ]) !=
            jsonEncode([
              for (final rule in before.rules) rule.toJson(),
            ]) ||
        jsonEncode([
              for (final override in applied.layerOverrides) override.toJson(),
            ]) !=
            jsonEncode([
              for (final override in before.layerOverrides) override.toJson(),
            ]);
    final syncChanged =
        applied.activeMappingProfileId != before.activeMappingProfileId;
    if (!identityChanged && !mappingChanged && !syncChanged) {
      roleMappingProfileStatus = '未复制：没有选中可写入的映射组，身份标签和同步设置也未变化';
      notifyListeners();
      return false;
    }
    _updateRoleReplacement(
      sourceRoleId,
      (_) => applied,
      learnProfile: false,
    );
    if (linkProfile) {
      _setRoleReplacementActiveProfile(sourceRoleId, profileId);
    }
    _refreshReplacementEditPreview();
    roleMappingProfileStatus = '已更新当前角色：'
        '${mappingChanged ? '映射规则已更新' : '映射规则未写入'} · '
        '${identityChanged ? '身份标签已更新' : '身份标签未变化'} · '
        '${linkProfile ? '持续同步已开启' : '保持本剧本独立'}';
    notifyListeners();
    await _saveCurrentCache();
    return true;
  }

  Future<void> resolveRoleMappingProfileDeletion({
    required bool deleteFromProfile,
  }) async {
    if (_pendingRoleMappingProfileDeletions.isEmpty) return;
    final prompt = _pendingRoleMappingProfileDeletions.removeAt(0);
    if (!deleteFromProfile) {
      if (!_disposed) notifyListeners();
      return;
    }
    final repository = _requireRoleMappingProfileRepository();
    final library = await repository.update((current) {
      final profile = current.profiles
          .where((entry) => entry.id == prompt.profileId)
          .firstOrNull;
      if (profile == null) return current;
      final updated = roleMappingProfileService.resolveDeletion(
        profile: profile,
        prompt: prompt,
        now: DateTime.now().toUtc(),
      );
      return current.copyWith(
        profiles: List.unmodifiable([
          for (final entry in current.profiles)
            if (entry.id == updated.id) updated else entry,
        ]),
      );
    });
    if (_disposed) return;
    _setRoleMappingProfileLibrary(library);
    roleMappingProfileStatus = '已从缓存删除：${prompt.label}';
    notifyListeners();
  }

  Future<RecastMappingVariant> saveCurrentMappingAsVariant(String name) async {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      throw StateError('请先打开剧本再保存映射版本。');
    }
    if (!canPersistMappingVariants) {
      throw StateError('当前工作区未配置剧本缓存保存。');
    }

    final now = DateTime.now().toUtc();
    final normalizedMapping = _mappingForCurrentScript(script, mapping);
    final nextCache = mappingVariantService.capture(
      cache: _cacheDraftForScript(
        script,
        mapping: normalizedMapping,
        updatedAt: now,
      ),
      id: const Uuid().v4(),
      name: name,
      capturedAt: now,
      targetCharacterNamesByRoleId:
          _targetCharacterNamesByRoleId(normalizedMapping),
    );
    final previousMapping = _mapping;
    final previousVariants = _mappingVariants;
    final previousActiveVariantId = _activeMappingVariantId;
    _mapping = nextCache.mapping;
    _mappingVariants = nextCache.mappingVariants;
    _activeMappingVariantId = nextCache.activeMappingVariantId;
    mappingVariantStatus = '正在保存映射版本…';
    notifyListeners();
    try {
      await _saveCurrentCache();
    } catch (_) {
      _mapping = previousMapping;
      _mappingVariants = previousVariants;
      _activeMappingVariantId = previousActiveVariantId;
      mappingVariantStatus = '映射版本保存失败，已回退';
      notifyListeners();
      rethrow;
    }
    final variant = _mappingVariants
        .where((entry) => entry.id == nextCache.activeMappingVariantId)
        .first;
    mappingVariantStatus = '已保存映射版本：${variant.name}';
    notifyListeners();
    return variant;
  }

  Future<void> activateMappingVariant(String variantId) async {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      throw StateError('请先打开剧本再切换映射版本。');
    }
    if (!canPersistMappingVariants) {
      throw StateError('当前工作区未配置剧本缓存保存。');
    }

    final now = DateTime.now().toUtc();
    final sourceFingerprint = cacheRestoreService.sourceFingerprint(script);
    final sourceContentFingerprint =
        cacheRestoreService.sourceContentFingerprint(script);
    final nextCache = mappingVariantService.activate(
      cache: _cacheDraftForScript(
        script,
        mapping: _mappingForCurrentScript(script, mapping),
        updatedAt: now,
      ),
      variantId: variantId,
      expectedScriptId: script.id,
      expectedSourceFingerprint: sourceFingerprint,
      expectedSourceContentFingerprint: sourceContentFingerprint,
      activatedAt: now,
    );
    final previousMapping = _mapping;
    final previousVariants = _mappingVariants;
    final previousActiveVariantId = _activeMappingVariantId;
    _mappingVariants = nextCache.mappingVariants;
    _activeMappingVariantId = nextCache.activeMappingVariantId;
    _applyScript(script, mappingOverride: nextCache.mapping);
    mappingVariantStatus = '正在切换映射版本…';
    notifyListeners();
    try {
      await _saveCurrentCache();
    } catch (_) {
      _mappingVariants = previousVariants;
      _activeMappingVariantId = previousActiveVariantId;
      _applyScript(script, mappingOverride: previousMapping);
      mappingVariantStatus = '映射版本切换失败，已回退';
      notifyListeners();
      rethrow;
    }
    final active = _mappingVariants
        .where((entry) => entry.id == _activeMappingVariantId)
        .first;
    mappingVariantStatus = '已切换映射版本：${active.name}';
    cacheStatus = '已切换并保存整套剧本映射';
    notifyListeners();
  }

  Future<void> activateMappingVariantForRole({
    required String variantId,
    required String sourceRoleId,
  }) async {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      throw StateError('请先打开剧本再切换角色映射缓存。');
    }
    if (!canPersistMappingVariants) {
      throw StateError('当前工作区未配置剧本缓存保存。');
    }

    final now = DateTime.now().toUtc();
    final sourceFingerprint = cacheRestoreService.sourceFingerprint(script);
    final sourceContentFingerprint =
        cacheRestoreService.sourceContentFingerprint(script);
    final nextCache = mappingVariantService.activateRole(
      cache: _cacheDraftForScript(
        script,
        mapping: _mappingForCurrentScript(script, mapping),
        updatedAt: now,
      ),
      variantId: variantId,
      sourceRoleId: sourceRoleId,
      expectedScriptId: script.id,
      expectedSourceFingerprint: sourceFingerprint,
      expectedSourceContentFingerprint: sourceContentFingerprint,
      activatedAt: now,
    );
    final previousMapping = _mapping;
    mappingVariantStatus = '正在切换当前角色映射…';
    _applyScript(script, mappingOverride: nextCache.mapping);
    notifyListeners();
    try {
      await _saveCurrentCache();
    } catch (_) {
      _applyScript(script, mappingOverride: previousMapping);
      mappingVariantStatus = '当前角色映射切换失败，已回退';
      notifyListeners();
      rethrow;
    }
    final active = nextCache.mappingVariants
        .where((entry) => entry.id == variantId)
        .firstOrNull;
    mappingVariantStatus =
        active == null ? '已切换当前角色的剧本缓存' : '已切换当前角色的剧本缓存：${active.name}';
    cacheStatus = '已切换并保存当前角色映射';
    notifyListeners();
  }

  void _scheduleCurrentMappingVariantsRefresh() {
    if (_disposed || _script == null || loadRecastCacheByScriptId == null) {
      return;
    }
    _recastCacheRefreshTimer?.cancel();
    _recastCacheRefreshTimer = Timer(recastCacheRefreshDebounce, () {
      _recastCacheRefreshTimer = null;
      unawaited(refreshCurrentScriptMappingVariantsFromCache());
    });
  }

  /// 只从磁盘刷新当前剧本的版本列表，不覆盖当前页面尚未保存的工作映射。
  Future<bool> refreshCurrentScriptMappingVariantsFromCache() async {
    final script = _script;
    final loader = loadRecastCacheByScriptId;
    if (_disposed || script == null || loader == null) {
      return false;
    }
    final refreshGeneration = ++_mappingVariantRefreshGeneration;
    try {
      final cache = await loader(script.id);
      if (_disposed ||
          refreshGeneration != _mappingVariantRefreshGeneration ||
          _script?.id != script.id ||
          cache == null) {
        return false;
      }
      final sourceFingerprint =
          cacheRestoreService.sourceFingerprint(script).trim();
      if (!cacheRestoreService.cacheBelongsToScript(cache, script) ||
          cache.sourceFingerprint.trim() != sourceFingerprint) {
        return false;
      }

      final nextVariants = _validMappingVariantsForCache(cache, script);
      if (_sameMappingVariantLists(_mappingVariants, nextVariants)) {
        return false;
      }
      final previousActiveVariantId = _activeMappingVariantId;
      _mappingVariants = List.unmodifiable(nextVariants);
      _activeMappingVariantId = nextVariants.any(
        (variant) => variant.id == previousActiveVariantId,
      )
          ? previousActiveVariantId
          : null;
      final ignoredCount = cache.mappingVariants.length - nextVariants.length;
      mappingVariantStatus = ignoredCount == 0
          ? '已从外部缓存刷新剧本级版本（共 ${nextVariants.length} 个）'
          : '已从外部缓存刷新剧本级版本（共 ${nextVariants.length} 个，'
              '忽略 $ignoredCount 个不匹配版本）';
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      if (!_disposed && refreshGeneration == _mappingVariantRefreshGeneration) {
        debugPrint(
          'Failed to refresh open script mapping variants: '
          '$error\n$stackTrace',
        );
      }
      return false;
    }
  }

  Future<int> ensureRequiredScriptMappingVariants() async {
    final script = _script;
    final currentMapping = _mapping;
    if (script == null ||
        currentMapping == null ||
        currentMapping.rolePromptReplacements.isEmpty ||
        !canPersistMappingVariants) {
      return 0;
    }
    await ensureRoleMappingProfilesLoaded(force: true);
    if (_disposed ||
        _script?.id != script.id ||
        _mapping == null ||
        roleMappingProfileRepository == null) {
      return 0;
    }
    final baseMapping = _mappingForCurrentScript(script, currentMapping);

    final requiredProfiles = [
      for (final profile in _requiredScriptMappingProfiles())
        // A global profile is linked per source role; its mere presence in
        // the library must never imply whole-script replacement.
        if (_canGenerateScriptMappingVariant(profile) &&
            _mappingUsesRoleMappingProfile(baseMapping, profile.id))
          profile,
    ];
    final previousVariants = _mappingVariants;
    final previousActiveVariantId = _activeMappingVariantId;
    final now = DateTime.now().toUtc();
    final sourceFingerprint = cacheRestoreService.sourceFingerprint(script);
    final sourceContentFingerprint =
        cacheRestoreService.sourceContentFingerprint(script);
    final generated = <RecastMappingVariant>[];
    for (final (index, profile) in requiredProfiles.indexed) {
      final mapping = _mappingWithRoleProfileApplied(
        baseMapping,
        profile,
      );
      final targetName = profile.targetCharacterNameSnapshot.trim().isEmpty
          ? profile.name.trim()
          : profile.targetCharacterNameSnapshot.trim();
      generated.add(
        RecastMappingVariant(
          id: 'auto-global-profile-${profile.id}',
          name: targetName,
          scriptId: script.id,
          sourceFingerprint: sourceFingerprint,
          sourceContentFingerprint: sourceContentFingerprint,
          capturedAt: now.subtract(Duration(microseconds: index)),
          mapping: RecastMapping.fromJson(
            Map<String, dynamic>.from(mapping.toJson()),
          ),
          targetCharacterNamesByRoleId: _targetCharacterNamesByRoleId(mapping),
        ),
      );
    }

    final existingById = {
      for (final variant in _mappingVariants) variant.id: variant,
    };
    final generatedChangedCount = generated.where((candidate) {
      final existing = existingById[candidate.id];
      return existing == null ||
          !_sameMappingVariantContent(existing, candidate);
    }).length;

    final generatedById = {
      for (final variant in generated) variant.id: variant,
    };
    final nextVariants = <RecastMappingVariant>[];
    var removedStaleAutoVariantCount = 0;
    for (final variant in _mappingVariants) {
      final replacement = generatedById.remove(variant.id);
      if (replacement != null) {
        nextVariants.add(replacement);
      } else if (variant.id.startsWith(_autoGlobalProfileVariantIdPrefix) &&
          !_isAllowedScriptMappingVariant(variant)) {
        removedStaleAutoVariantCount += 1;
      } else {
        nextVariants.add(variant);
      }
    }
    nextVariants.addAll(generatedById.values);
    final changedCount = generatedChangedCount + removedStaleAutoVariantCount;
    if (changedCount == 0) {
      return 0;
    }

    _mappingVariants = List.unmodifiable(nextVariants);
    _activeMappingVariantId = nextVariants.any(
      (variant) => variant.id == previousActiveVariantId,
    )
        ? previousActiveVariantId
        : null;
    mappingVariantStatus =
        '已刷新 $changedCount 个剧本级版本（共 ${_mappingVariants.length} 个）';
    notifyListeners();
    try {
      await _saveCurrentCache();
    } catch (error) {
      _mappingVariants = previousVariants;
      _activeMappingVariantId = previousActiveVariantId;
      mappingVariantStatus = '自动补齐剧本级版本失败，已回退：$error';
      notifyListeners();
      return 0;
    }
    return changedCount;
  }

  bool _sameMappingVariantContent(
    RecastMappingVariant left,
    RecastMappingVariant right,
  ) {
    return left.id == right.id &&
        left.name == right.name &&
        left.scriptId == right.scriptId &&
        left.sourceFingerprint == right.sourceFingerprint &&
        left.sourceContentFingerprint == right.sourceContentFingerprint &&
        mapEquals(
          left.targetCharacterNamesByRoleId,
          right.targetCharacterNamesByRoleId,
        ) &&
        mappingVariantService.sameMapping(left.mapping, right.mapping);
  }

  bool _canGenerateScriptMappingVariant(RoleMappingProfile profile) {
    return profile.targetIdentityPrompt.trim().isNotEmpty &&
        profile.effectiveLayers.any(
          (layer) => layer.blocks.any((block) => block.hasEffect),
        );
  }

  bool _mappingUsesRoleMappingProfile(
    RecastMapping mapping,
    String profileId,
  ) {
    final normalizedProfileId = profileId.trim();
    if (normalizedProfileId.isEmpty) return false;
    return mapping.rolePromptReplacements.any(
      (replacement) =>
          replacement.activeMappingProfileId?.trim() == normalizedProfileId,
    );
  }

  List<RoleMappingProfile> _requiredScriptMappingProfiles() {
    final profiles = <RoleMappingProfile>[];
    for (final requiredName in _requiredScriptMappingProfileNames) {
      for (final profile in roleMappingProfiles) {
        if (profile.name.trim() == requiredName) {
          profiles.add(profile);
          break;
        }
      }
    }
    return profiles;
  }

  bool _isAllowedScriptMappingVariant(RecastMappingVariant variant) {
    final variantId = variant.id.trim();
    return !variantId.startsWith(_autoGlobalProfileVariantIdPrefix) ||
        _requiredScriptMappingProfileNames.contains(variant.name.trim());
  }

  RecastMapping _mappingWithRoleProfileApplied(
    RecastMapping mapping,
    RoleMappingProfile profile,
  ) {
    final applicableProfile = profile.targetCharacterId != null &&
            _characterById(profile.targetCharacterId!) == null
        ? profile.copyWith(targetCharacterId: null)
        : profile;
    // Keep the snapshot's other source roles byte-for-byte unchanged. The
    // previous implementation applied one profile to every replacement.
    final linkedRoleIds = {
      for (final replacement in mapping.rolePromptReplacements)
        if (replacement.activeMappingProfileId?.trim() == profile.id.trim())
          replacement.sourceRoleId,
    };
    if (linkedRoleIds.isEmpty) return mapping;
    final assemblyByRoleId = {
      for (final assembly in mapping.roleAssemblies)
        assembly.sourceRoleId: assembly,
    };
    return mapping.copyWith(
      rolePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.rolePromptReplacements)
          if (linkedRoleIds.contains(replacement.sourceRoleId))
            _replacementWithRoleProfileApplied(
              replacement: replacement,
              profile: applicableProfile,
              assembly: assemblyByRoleId[replacement.sourceRoleId],
            )
          else
            replacement,
      ]),
    );
  }

  ScriptRolePromptReplacement _replacementWithRoleProfileApplied({
    required ScriptRolePromptReplacement replacement,
    required RoleMappingProfile profile,
    RoleAssembly? assembly,
  }) {
    final preview = roleMappingProfileService.buildPreview(
      profile: profile,
      replacement: replacement,
      assembly: assembly,
    );
    final selections = [
      for (final entry in preview.entries)
        if (entry.selectedByDefault && entry.selectedTermIds.isNotEmpty)
          RoleMappingProfileApplySelection(
            blockId: entry.block.id,
            termIds: entry.selectedTermIds,
          ),
    ];
    final applied = roleMappingProfileService.applySelections(
      profile: profile,
      replacement: replacement,
      selections: selections,
      applyIdentity: true,
      linkProfile: true,
      assembly: assembly,
    );
    return roleMappingProfileService.deduplicateTargetOutputs(
      roleMappingProfileService.materializeTargetIdentityReplacement(applied),
      forbiddenTarget: profile.name.trim() == '果宝' ? '果宝' : '',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _aiOperationGeneration++;
    _scriptOpenGeneration++;
    _productionSendGeneration++;
    _deferredAssetRefreshGeneration++;
    _mappingVariantRefreshGeneration++;
    _aiRoleExtractionStreamNotifyTimer?.cancel();
    _recastCacheRefreshTimer?.cancel();
    final recastCacheChangesSubscription = _recastCacheChangesSubscription;
    if (recastCacheChangesSubscription != null) {
      unawaited(recastCacheChangesSubscription.cancel());
    }
    if (_cacheSaveDebounceTimer != null) {
      unawaited(_saveCurrentCache());
    }
    super.dispose();
  }

  Future<void> importScriptFolder() async {
    if (_disposed) return;
    try {
      final path = await pickScriptDirectory?.call();
      if (_disposed) return;
      if (path == null || path.trim().isEmpty) {
        return;
      }
      await importScriptPath(path);
    } catch (error, stackTrace) {
      if (!_disposed) {
        _recordImportFailure(error, stackTrace);
      }
    }
  }

  Future<void> openScriptFromExhibition({
    required String scriptId,
    required String sourceFolder,
    int? frameIndex,
  }) async {
    if (_disposed) return;
    final timingStopwatch = Stopwatch()..start();
    const timingOperation = 'script-exhibition-open';
    final normalizedScriptId = scriptId.trim();
    final normalizedSourceFolder = sourceFolder.trim();
    if (_currentScriptMatches(
      scriptId: normalizedScriptId,
      sourceFolder: normalizedSourceFolder,
    )) {
      _selectFrameIfAvailable(frameIndex);
      _recordOpenTiming(
        operation: timingOperation,
        stage: 'already-open',
        stopwatch: timingStopwatch,
        cacheHit: true,
      );
      return;
    }

    final openGeneration = _beginScriptOpenOperation();
    _setImportProgress('正在打开剧本工作台...', value: 0.02);
    await _yieldImportProgressFrame();
    if (!_isCurrentScriptOpenOperation(openGeneration)) return;
    final restoreSnapshotByScriptId = restoreRecastCacheSnapshotByScriptId;
    final restoreImportPath =
        normalizedSourceFolder.isEmpty ? null : normalizedSourceFolder;
    if (normalizedScriptId.isNotEmpty && restoreSnapshotByScriptId != null) {
      try {
        _setImportProgress(importProgressLabel, value: 0.12);
        await _yieldImportProgressFrame();
        if (!_isCurrentScriptOpenOperation(openGeneration)) return;
        _setImportProgress(importProgressLabel, value: 0.28);
        await _yieldImportProgressFrame();
        if (!_isCurrentScriptOpenOperation(openGeneration)) return;
        final restored = await restoreSnapshotByScriptId(
          scriptId: normalizedScriptId,
          importPath: restoreImportPath,
        );
        _recordOpenTiming(
          operation: timingOperation,
          stage: 'load-cache',
          stopwatch: timingStopwatch,
          cacheHit: restored != null,
        );
        if (!_isCurrentScriptOpenOperation(openGeneration)) return;
        if (restored != null) {
          _recordOpenTiming(
            operation: timingOperation,
            stage: 'hydrate-cache-snapshot',
            stopwatch: timingStopwatch,
            cacheHit: true,
          );
          if (await _applyHydratedCachedScriptSnapshot(
            cache: restored.cache,
            script: restored.script,
            loadAssetsBeforeApply: false,
            reportProgress: true,
            shouldContinue: () => _isCurrentScriptOpenOperation(openGeneration),
            timingOperation: timingOperation,
            timingStopwatch: timingStopwatch,
          )) {
            if (!_isCurrentScriptOpenOperation(openGeneration)) return;
            _setImportProgress(importProgressLabel, value: 0.96);
            await _yieldImportProgressFrame();
            if (!_isCurrentScriptOpenOperation(openGeneration)) return;
            _clearImportProgress();
            notifyListeners();
            _selectFrameIfAvailable(frameIndex);
            _scheduleDeferredAssetRefresh(normalizedScriptId);
            _recordOpenTiming(
              operation: timingOperation,
              stage: 'complete-cache-hit',
              stopwatch: timingStopwatch,
              cacheHit: true,
            );
            return;
          }
        }
      } catch (error, stackTrace) {
        if (!_isCurrentScriptOpenOperation(openGeneration)) return;
        debugPrint(
          'Failed to restore exhibition script cache directly: '
          '$error\n$stackTrace',
        );
      }
    }
    if (!_isCurrentScriptOpenOperation(openGeneration)) return;
    final targetedLoader = loadRecastCacheByScriptId;
    if (normalizedScriptId.isNotEmpty && targetedLoader != null) {
      try {
        _setImportProgress('正在读取剧本缓存...', value: 0.12);
        await _yieldImportProgressFrame();
        if (!_isCurrentScriptOpenOperation(openGeneration)) return;
        final cache = await targetedLoader(normalizedScriptId);
        _recordOpenTiming(
          operation: timingOperation,
          stage: 'load-cache',
          stopwatch: timingStopwatch,
          cacheHit: cache != null,
        );
        if (!_isCurrentScriptOpenOperation(openGeneration)) return;
        if (cache != null &&
            cacheRestoreService.cacheSnapshotHasFrames(cache.scriptSnapshot) &&
            await _restoreCachedScriptSnapshot(
              cache,
              importPath: normalizedSourceFolder.isEmpty
                  ? null
                  : normalizedSourceFolder,
              loadAssetsBeforeApply: false,
              reportProgress: true,
              shouldContinue: () =>
                  _isCurrentScriptOpenOperation(openGeneration),
              timingOperation: timingOperation,
              timingStopwatch: timingStopwatch,
            )) {
          if (!_isCurrentScriptOpenOperation(openGeneration)) return;
          _setImportProgress('正在完成剧本工作台...', value: 0.96);
          await _yieldImportProgressFrame();
          if (!_isCurrentScriptOpenOperation(openGeneration)) return;
          _clearImportProgress();
          notifyListeners();
          _selectFrameIfAvailable(frameIndex);
          _scheduleDeferredAssetRefresh(normalizedScriptId);
          _recordOpenTiming(
            operation: timingOperation,
            stage: 'complete-cache-hit',
            stopwatch: timingStopwatch,
            cacheHit: true,
          );
          return;
        }
      } catch (error, stackTrace) {
        if (!_isCurrentScriptOpenOperation(openGeneration)) return;
        debugPrint(
          'Failed to restore exhibition script cache: $error\n$stackTrace',
        );
      }
    }

    if (!_isCurrentScriptOpenOperation(openGeneration)) return;
    if (normalizedSourceFolder.isEmpty) {
      _clearImportProgress();
      notifyListeners();
      _recordOpenTiming(
        operation: timingOperation,
        stage: 'empty-source-folder',
        stopwatch: timingStopwatch,
      );
      return;
    }
    _setImportProgress('未命中缓存，正在扫描原目录...', value: 0.2);
    await _yieldImportProgressFrame();
    if (!_isCurrentScriptOpenOperation(openGeneration)) return;
    await _importScriptPath(normalizedSourceFolder, openGeneration);
    if (!_isCurrentScriptOpenOperation(openGeneration)) return;
    _selectFrameIfAvailable(frameIndex);
    _recordOpenTiming(
      operation: timingOperation,
      stage: 'complete-fallback-import',
      stopwatch: timingStopwatch,
    );
  }

  void _recordOpenTiming({
    required String? operation,
    required String stage,
    Stopwatch? stopwatch,
    bool cacheHit = false,
  }) {
    if (operation == null) {
      return;
    }
    final timing = StudioScriptOpenTiming(
      operation: operation,
      stage: stage,
      elapsed: stopwatch?.elapsed ?? Duration.zero,
      cacheHit: cacheHit,
    );
    openTimingSink?.call(timing);
    if (kDebugMode) {
      debugPrint(
        '[StudioScriptOpen] ${timing.operation}/${timing.stage} '
        '${timing.elapsed.inMilliseconds}ms '
        '${timing.cacheHit ? 'cache-hit' : 'cache-miss'}',
      );
    }
  }

  bool _currentScriptMatches({
    required String scriptId,
    required String sourceFolder,
  }) {
    final script = _script;
    if (script == null) {
      return false;
    }
    if (scriptId.isNotEmpty && script.id == scriptId) {
      return true;
    }
    return sourceFolder.isNotEmpty &&
        _normalizePathForComparison(script.rootPath) ==
            _normalizePathForComparison(sourceFolder);
  }

  String _normalizePathForComparison(String path) {
    return path.trim().replaceAll('\\', '/').toLowerCase();
  }

  void _selectFrameIfAvailable(int? frameIndex) {
    if (frameIndex != null) {
      selectFrame(frameIndex);
    }
  }

  Future<void> collapseAiRoleExtractionDraft() async {
    if (_aiRoleExtractionDraftDismissed) {}
    _aiRoleExtractionDraftDismissed = true;
    notifyListeners();
    await _saveCurrentCache();
  }

  Future<void> expandAiRoleExtractionDraft() async {
    if (!_aiRoleExtractionDraftDismissed && !_aiRoleExtractionDraftSuppressed) {
      return;
    }
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionDraftDismissed = false;
    notifyListeners();
    await _saveCurrentCache();
  }

  Future<void> setReviewTagCategory(
    String tag,
    StudioScriptTokenCategory category, {
    required bool negative,
  }) async {
    final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
    if (clean.isEmpty) {
      return;
    }
    classificationCache.setCategory(
      clean,
      _promptCategoryForReviewCategory(category),
      source: 'manual',
      negative: negative,
    );
    _refreshRecastPlan();
    notifyListeners();
    await _saveClassificationCacheBestEffort();
  }

  Future<void> clearReviewTagCategory(
    String tag, {
    required bool negative,
  }) async {
    final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
    if (clean.isEmpty) {
      return;
    }
    classificationCache.clearCategory(clean, negative: negative);
    _refreshRecastPlan();
    notifyListeners();
    await _saveClassificationCacheBestEffort();
  }

  void refreshReviewTagCategories() {
    _refreshRecastPlan();
    notifyListeners();
  }

  void suppressPromptTagWarningForCurrentScript(String tag) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (key.isEmpty) {
      return;
    }
    final mapping = _mapping;
    if (mapping == null ||
        mapping.suppressedPromptTagWarningKeys.contains(key)) {
      return;
    }
    _mapping = mapping.copyWith(
      suppressedPromptTagWarningKeys: {
        ...mapping.suppressedPromptTagWarningKeys,
        key,
      },
    );
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  Map<String, PromptTagCategory> reviewTagClassificationOverrides({
    required bool negative,
  }) {
    if (!aiRoleExtraction.isReady || aiRoleExtraction.artistChains.isEmpty) {
      return const {};
    }
    final category =
        negative ? PromptTagCategory.negativeArtist : PromptTagCategory.artist;
    final result = <String, PromptTagCategory>{};
    for (final term in _aiArtistEvidenceTerms()) {
      final clean = PromptTagProcessor.cleanTagDisplay(term).trim();
      if (clean.isNotEmpty) {
        result[clean] = category;
      }
    }
    return Map.unmodifiable(result);
  }

  Future<void> importScriptPath(String path) {
    if (_disposed) return Future<void>.value();
    return _importScriptPath(path, _beginScriptOpenOperation());
  }

  Future<void> _importScriptPath(String path, int openGeneration) async {
    bool shouldContinue() => _isCurrentScriptOpenOperation(openGeneration);

    try {
      _deferredAssetRefreshGeneration += 1;
      await _flushPendingCurrentCacheSaveBeforeImport();
      if (!shouldContinue()) return;
      _setImportProgress('正在检查剧本缓存...');
      final hasCacheLoader =
          loadRecastCacheByScriptId != null || loadRecastCaches != null;
      final directoryContainsPng =
          !hasCacheLoader ? false : await _scriptDirectoryContainsPng(path);
      if (!shouldContinue()) return;
      if (await _restoreCachedScriptSnapshotForPath(
        path,
        directoryContainsPng: directoryContainsPng,
        shouldContinue: shouldContinue,
      )) {
        if (!shouldContinue()) return;
        _clearImportProgress();
        notifyListeners();
        return;
      }
      if (!shouldContinue()) return;
      _setImportProgress('正在扫描剧本目录...');
      final script = await parserService.parseDirectory(
        Directory(path),
        onProgress: (progress) {
          if (shouldContinue()) {
            _handleParseProgress(progress);
          }
        },
      );
      if (!shouldContinue()) return;
      _setImportProgress('正在加载素材库...');
      await _loadAssets();
      if (!shouldContinue()) return;
      _ensureTemporaryArtistChainFromScript(script);
      _setImportProgress('正在整理角色映射...');
      _script = script;
      _sourceTermFrameIndex = null;
      sentToProduction = false;
      isSendingToProduction = false;
      lastProductionPlanId = null;
      lastProductionPlanName = null;
      scriptBlockWords = '';
      _aiOperationGeneration++;
      aiRoleExtraction = const ScriptAiRoleExtraction();
      aiRoleExtractionRequestPreview = const {};
      aiRoleExtractionReasoningContent = '';
      aiRoleExtractionStreamingContent = '';
      aiRoleExtractionTraceEvents = const [];
      aiRoleExtractionChunks = const [];
      aiRoleExtractionRequestCount = 0;
      _aiRoleExtractionDraftDismissed = false;
      _aiRoleExtractionDraftSuppressed = false;
      _aiRoleExtractionFinalized = false;
      isApplyingAiRoleExtraction = false;
      analysisStatus = '尚未分析角色';
      aiStatus = '尚未进行 AI 分析';
      _artistSourceLabelOverride = null;
      _clearAiProgress();
      _changedSourceCache = null;
      _mappingVariants = const [];
      _activeMappingVariantId = null;
      mappingVariantStatus = '';
      _applyScript(script);
      _setImportProgress('正在恢复当前缓存...');
      await _restoreExactCurrentSourceCache(
        script,
        shouldContinue: shouldContinue,
      );
      if (!shouldContinue()) return;
      await ensureRequiredScriptMappingVariants();
      if (!shouldContinue()) return;
      await _saveParsedSnapshotAfterImportIfUseful(
        directoryContainsPng,
        shouldContinue: shouldContinue,
      );
      if (!shouldContinue()) return;
      _clearImportProgress();
      notifyListeners();
    } catch (error, stackTrace) {
      if (shouldContinue()) {
        _recordImportFailure(error, stackTrace);
      }
    }
  }

  Future<void> _flushPendingCurrentCacheSaveBeforeImport() async {
    try {
      if (_cacheSaveDebounceTimer != null) {
        await _saveCurrentCache();
        return;
      }
      final pendingSave = _cacheSaveTail;
      if (pendingSave != null) {
        await pendingSave;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to flush pending script cache before import: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<bool> _restoreCachedScriptSnapshotForPath(
    String path, {
    bool? directoryContainsPng,
    required bool Function() shouldContinue,
  }) async {
    final targetedLoader = loadRecastCacheByScriptId;
    final bulkLoader = loadRecastCaches;
    if (targetedLoader == null && bulkLoader == null) {
      return false;
    }
    final hasPng =
        directoryContainsPng ?? await _scriptDirectoryContainsPng(path);
    if (!shouldContinue() || !hasPng) {
      return false;
    }
    var allowBulkFallback = targetedLoader == null;
    var allowNameFallback = false;
    if (targetedLoader != null) {
      final scriptId = ScriptRecastParserService.scriptIdForDirectory(
        Directory(path),
      );
      final restoreSnapshotByScriptId = restoreRecastCacheSnapshotByScriptId;
      if (restoreSnapshotByScriptId != null) {
        final restored = await restoreSnapshotByScriptId(
          scriptId: scriptId,
          importPath: path,
        );
        if (!shouldContinue()) return false;
        if (restored != null &&
            cacheRestoreService.cacheMatchesImportPath(restored.cache, path) &&
            await _applyHydratedCachedScriptSnapshot(
              cache: restored.cache,
              script: restored.script,
              shouldContinue: shouldContinue,
            )) {
          return true;
        }
      }
      final cache = await targetedLoader(scriptId);
      if (!shouldContinue()) return false;
      if (cache != null &&
          cacheRestoreService.cacheMatchesImportPath(cache, path)) {
        if (cacheRestoreService.cacheSnapshotHasFrames(cache.scriptSnapshot)) {
          final bestCache = await _bestImportCacheForCurrentPath(
            path: path,
            primaryCache: cache,
          );
          if (!shouldContinue()) return false;
          if (await _restoreCachedScriptSnapshot(
            bestCache,
            importPath: path,
            shouldContinue: shouldContinue,
          )) {
            return true;
          }
        }
        allowBulkFallback = true;
        allowNameFallback = true;
      } else if (cache == null &&
          cacheRestoreService.pathMayNeedAliasCacheFallback(path)) {
        allowBulkFallback = true;
        allowNameFallback = true;
      } else {
        allowBulkFallback = false;
      }
      if (bulkLoader == null) {
        return false;
      }
    }

    if (!allowBulkFallback) {
      return false;
    }
    final allCaches = await bulkLoader!();
    if (!shouldContinue()) return false;
    final pathCaches = [
      for (final cache in allCaches)
        if (cacheRestoreService.cacheSnapshotHasFrames(cache.scriptSnapshot) &&
            cacheRestoreService.cacheMatchesImportPath(cache, path))
          cache,
    ];
    final bestPathCache = cacheRestoreService.bestExactCache(pathCaches);
    if (bestPathCache != null &&
        await _restoreCachedScriptSnapshot(
          bestPathCache,
          importPath: path,
          shouldContinue: shouldContinue,
        )) {
      return true;
    }

    if (!allowNameFallback) {
      return false;
    }
    final namedCaches = [
      for (final cache in allCaches)
        if (cacheRestoreService.cacheSnapshotHasFrames(cache.scriptSnapshot) &&
            cacheRestoreService.cacheNameMatchesImportPath(cache, path))
          cache,
    ];
    final bestCache = cacheRestoreService.bestExactCache(namedCaches);
    if (bestCache == null) {
      return false;
    }

    return _restoreCachedScriptSnapshot(
      bestCache,
      importPath: path,
      shouldContinue: shouldContinue,
    );
  }

  Future<RecastScriptCache> _bestImportCacheForCurrentPath({
    required String path,
    required RecastScriptCache primaryCache,
  }) async {
    final bulkLoader = loadRecastCaches;
    if (bulkLoader == null ||
        cacheRestoreService.cacheUserMappingScore(primaryCache) > 0) {
      return primaryCache;
    }
    final contentFingerprint =
        cacheRestoreService.sourceContentFingerprintFromSnapshot(
      primaryCache.scriptSnapshot,
    );
    final allCaches = await bulkLoader();
    final candidates = <RecastScriptCache>[
      primaryCache,
      for (final cache in allCaches)
        if (cacheRestoreService.cacheSnapshotHasFrames(cache.scriptSnapshot) &&
            (cacheRestoreService.cacheMatchesImportPath(cache, path) ||
                cacheRestoreService.cacheNameMatchesImportPath(cache, path) ||
                cacheRestoreService.cacheHasSourceContentFingerprint(
                  cache,
                  contentFingerprint,
                )))
          cache,
    ];
    return cacheRestoreService.bestExactCache(candidates) ?? primaryCache;
  }

  Future<bool> _restoreCachedScriptSnapshot(
    RecastScriptCache cache, {
    String? importPath,
    bool loadAssetsBeforeApply = true,
    bool reportProgress = false,
    bool Function()? shouldContinue,
    String? timingOperation,
    Stopwatch? timingStopwatch,
  }) async {
    if (reportProgress) {
      _setImportProgress('正在恢复剧本快照...', value: 0.28);
      await _yieldImportProgressFrame();
      if (shouldContinue?.call() == false) return false;
    }
    final script = await hydrateCachedScriptSnapshot(
      scriptSnapshot: cache.scriptSnapshot,
      importPath: importPath,
    );
    if (shouldContinue?.call() == false) return false;
    _recordOpenTiming(
      operation: timingOperation,
      stage: 'hydrate-cache-snapshot',
      stopwatch: timingStopwatch,
      cacheHit: true,
    );
    return _applyHydratedCachedScriptSnapshot(
      cache: cache,
      script: script,
      loadAssetsBeforeApply: loadAssetsBeforeApply,
      reportProgress: reportProgress,
      shouldContinue: shouldContinue,
      timingOperation: timingOperation,
      timingStopwatch: timingStopwatch,
    );
  }

  Future<bool> _applyHydratedCachedScriptSnapshot({
    required RecastScriptCache cache,
    required Script script,
    bool loadAssetsBeforeApply = true,
    bool reportProgress = false,
    bool Function()? shouldContinue,
    String? timingOperation,
    Stopwatch? timingStopwatch,
  }) async {
    if (script.frames.isEmpty) {
      return false;
    }
    if (loadAssetsBeforeApply) {
      if (reportProgress) {
        _setImportProgress('正在加载素材索引...', value: 0.42);
        await _yieldImportProgressFrame();
        if (shouldContinue?.call() == false) return false;
      }
      await _loadAssets();
      if (shouldContinue?.call() == false) return false;
      _recordOpenTiming(
        operation: timingOperation,
        stage: 'load-assets',
        stopwatch: timingStopwatch,
        cacheHit: true,
      );
    }
    if (reportProgress) {
      _setImportProgress('正在整理剧本结构...', value: 0.56);
      await _yieldImportProgressFrame();
      if (shouldContinue?.call() == false) return false;
    }
    _ensureTemporaryArtistChainFromScript(script);
    _script = script;
    _sourceTermFrameIndex = null;
    sentToProduction = false;
    isSendingToProduction = false;
    lastProductionPlanId = null;
    lastProductionPlanName = null;
    scriptBlockWords = '';
    _aiOperationGeneration++;
    aiRoleExtraction = const ScriptAiRoleExtraction();
    aiRoleExtractionRequestPreview = const {};
    aiRoleExtractionReasoningContent = '';
    aiRoleExtractionStreamingContent = '';
    aiRoleExtractionTraceEvents = const [];
    aiRoleExtractionChunks = const [];
    aiRoleExtractionRequestCount = 0;
    _aiRoleExtractionDraftDismissed = false;
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionFinalized = false;
    isApplyingAiRoleExtraction = false;
    analysisStatus = '尚未分析角色';
    aiStatus = '尚未进行 AI 分析';
    _artistSourceLabelOverride = null;
    _clearAiProgress();
    _changedSourceCache = null;
    _applyCache(cache, refreshPreview: false);
    _recordOpenTiming(
      operation: timingOperation,
      stage: 'apply-cache',
      stopwatch: timingStopwatch,
      cacheHit: true,
    );
    _applyScript(script, mappingOverride: _mapping);
    if (shouldContinue?.call() == false) return false;
    await ensureRequiredScriptMappingVariants();
    if (shouldContinue?.call() == false) return false;
    if (reportProgress) {
      _setImportProgress('正在生成工作台草稿...', value: 0.72);
      await _yieldImportProgressFrame();
      if (shouldContinue?.call() == false) return false;
    }
    _recordOpenTiming(
      operation: timingOperation,
      stage: 'apply-script',
      stopwatch: timingStopwatch,
      cacheHit: true,
    );
    if (reportProgress) {
      _setImportProgress('正在恢复剧本级映射...', value: 0.84);
      await _yieldImportProgressFrame();
      if (shouldContinue?.call() == false) return false;
    }
    cacheStatus = '已从缓存快速恢复本剧本';
    return true;
  }

  void _scheduleDeferredAssetRefresh(String scriptId) {
    final normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.isEmpty || _assetsLoaded) return;
    _deferredAssetRefreshGeneration += 1;
    final generation = _deferredAssetRefreshGeneration;
    unawaited(_refreshAssetsAfterFastOpen(
      scriptId: normalizedScriptId,
      generation: generation,
    ));
  }

  Future<void> _refreshAssetsAfterFastOpen({
    required String scriptId,
    required int generation,
  }) async {
    try {
      await _loadAssets();
      final script = _script;
      if (script == null ||
          script.id != scriptId ||
          generation != _deferredAssetRefreshGeneration) {
        return;
      }
      _ensureTemporaryArtistChainFromScript(script);
      final mapping = _mapping;
      if (mapping == null) {
        return;
      }
      _applyScript(script, mappingOverride: mapping);
      await ensureRequiredScriptMappingVariants();
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to refresh script assets after exhibition fast open: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<bool> _scriptDirectoryContainsPng(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      return false;
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        return true;
      }
      if (entity is Directory &&
          entity.path
              .replaceAll('\\', '/')
              .split('/')
              .last
              .toLowerCase()
              .contains('png')) {
        await for (final nested in entity.list(followLinks: false)) {
          if (nested is File && nested.path.toLowerCase().endsWith('.png')) {
            return true;
          }
        }
      }
    }
    return false;
  }

  void _recordImportFailure(Object error, StackTrace stackTrace) {
    debugPrint('Failed to import script: $error\n$stackTrace');
    final message = _importErrorMessage(error);
    _script = null;
    _sourceTermFrameIndex = null;
    _mapping = null;
    _mappingVariants = const [];
    _activeMappingVariantId = null;
    mappingVariantStatus = '';
    _changedSourceCache = null;
    _previewResult = null;
    _selectedFrameIndex = null;
    _selectedRoleReplacementRuleIdsByRole.clear();
    _selectedSceneReplacementRuleIdsByGroup.clear();
    _aiOperationGeneration++;
    sentToProduction = false;
    isSendingToProduction = false;
    _clearImportProgress();
    lastProductionPlanId = null;
    lastProductionPlanName = null;
    scriptBlockWords = '';
    folderStatus = '导入失败：$message';
    importOperationStatus = OperationStatus.failure(
      code: OperationStatusCode.importFailed,
      message: folderStatus,
      recoverable: true,
    );
    frameCount = 0;
    parsedCount = 0;
    warningCount = 1;
    roleCount = 0;
    schemaLabel = 'unknown';
    analysisStatus = '请先导入剧本';
    cacheStatus = '未加载缓存';
    aiStatus = '导入失败，AI 分析已停止';
    cacheOperationStatus = OperationStatus.failure(
      code: OperationStatusCode.cacheRestore,
      message: cacheStatus,
      recoverable: true,
    );
    aiOperationStatus = OperationStatus.failure(
      code: OperationStatusCode.aiExtraction,
      message: aiStatus,
      recoverable: true,
    );
    roles = const [];
    artistChains = const [];
    aiRoleExtraction = const ScriptAiRoleExtraction();
    aiRoleExtractionRequestPreview = const {};
    aiRoleExtractionReasoningContent = '';
    aiRoleExtractionStreamingContent = '';
    aiRoleExtractionTraceEvents = const [];
    aiRoleExtractionChunks = const [];
    aiRoleExtractionRequestCount = 0;
    _aiRoleExtractionDraftDismissed = false;
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionFinalized = false;
    isExtractingAiRoleEvidence = false;
    isApplyingAiRoleExtraction = false;
    roleMappings = const [];
    roleReplacementMappings = const [];
    sceneReplacementMappings = const [];
    artistMappings = const [];
    promptBlockMappings = const [];
    _artistSourceLabelOverride = null;
    warnings = ['导入失败：$message'];
    timeline = const [];
    selectedFrameTagGroups = const [];
    selectedFramePreviews = const [];
    diff = const StudioScriptDiff(original: '', recast: '');
    recastPlan = const StudioScriptRecastPlan();
    _frameResultStatuses = const {};
    _clearAiProgress();
    notifyListeners();
  }

  String _importErrorMessage(Object error) {
    if (error is FormatException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return error.toString();
  }

  Future<void> ensureAssetsLoaded({bool forceRefresh = false}) async {
    if (_assetsLoaded && !forceRefresh) {
      return;
    }
    await _loadAssets();
    notifyListeners();
  }

  void _clearAiProgress() {
    aiProgressTitle = '';
    aiProgressSteps = const [];
    _aiProgressIndex = -1;
  }

  void _setImportProgress(String label, {double? value}) {
    isImportingScript = true;
    importProgressLabel = label;
    importProgressValue = value;
    importOperationStatus = OperationStatus.running(
      code: OperationStatusCode.importScript,
      message: label,
    );
    notifyListeners();
  }

  int _beginScriptOpenOperation() {
    _scriptOpenGeneration += 1;
    _productionSendGeneration += 1;
    isSendingToProduction = false;
    return _scriptOpenGeneration;
  }

  bool _isCurrentScriptOpenOperation(int generation) {
    return !_disposed && generation == _scriptOpenGeneration;
  }

  Future<void> _yieldImportProgressFrame() {
    return Future<void>.delayed(Duration.zero);
  }

  void _clearImportProgress() {
    isImportingScript = false;
    importProgressLabel = '';
    importProgressValue = null;
    importOperationStatus = const OperationStatus.idle();
  }

  void _handleParseProgress(ScriptRecastParseProgress progress) {
    _setImportProgress(
      _importProgressLabel(progress),
      value: progress.fraction,
    );
  }

  String _importProgressLabel(ScriptRecastParseProgress progress) {
    final total = progress.totalSources;
    final fileSuffix =
        progress.fileName == null ? '' : ' · ${progress.fileName}';
    return switch (progress.phase) {
      ScriptRecastParseProgressPhase.scanning => '正在扫描剧本目录...',
      ScriptRecastParseProgressPhase.sourcesDiscovered =>
        total > 0 ? '发现 $total 个候选帧，开始解析...' : '没有发现可解析帧',
      ScriptRecastParseProgressPhase.sourceParsing => total > 0
          ? '正在解析剧本帧 ${progress.visitedSources + 1}/$total$fileSuffix'
          : '正在解析剧本帧$fileSuffix',
      ScriptRecastParseProgressPhase.sourceParsed => total > 0
          ? '正在解析剧本帧 ${progress.visitedSources}/$total$fileSuffix'
          : '正在解析剧本帧$fileSuffix',
      ScriptRecastParseProgressPhase.complete =>
        total > 0 ? '解析完成：${progress.parsedFrames}/$total 帧' : '解析完成：0 帧',
    };
  }

  int _beginAiOperation() {
    _aiOperationGeneration++;
    return _aiOperationGeneration;
  }

  bool _isCurrentAiOperation(int operationId) =>
      operationId == _aiOperationGeneration;

  void stopAiProcessing() {
    if (!isAiBusy) {
      return;
    }
    _aiOperationGeneration++;
    isExtractingAiRoleEvidence = false;
    isApplyingAiRoleExtraction = false;
    _aiRoleExtractionStreamNotifyTimer?.cancel();
    _aiRoleExtractionStreamNotifyTimer = null;
    _pendingAiRoleExtractionStreamChars = 0;
    _failAiProgress('AI 处理已停止');
  }

  void _startAiProgress({
    required String title,
    required List<String> steps,
    required String status,
  }) {
    aiProgressTitle = title;
    _aiProgressIndex = steps.isEmpty ? -1 : 0;
    aiProgressSteps = List.unmodifiable([
      for (final (index, label) in steps.indexed)
        StudioScriptAiProgressStep(
          label: label,
          state: index == _aiProgressIndex
              ? StudioScriptAiProgressStepState.active
              : StudioScriptAiProgressStepState.waiting,
        ),
    ]);
    aiStatus = status;
    aiOperationStatus = OperationStatus.running(
      code: OperationStatusCode.aiExtraction,
      message: status,
    );
    notifyListeners();
  }

  void _setAiProgressStep(int index, String status) {
    if (aiProgressSteps.isEmpty) {
      aiStatus = status;
      aiOperationStatus = OperationStatus.running(
        code: OperationStatusCode.aiExtraction,
        message: status,
      );
      notifyListeners();
      return;
    }
    final clamped = index.clamp(0, aiProgressSteps.length - 1);
    _aiProgressIndex = clamped;
    aiProgressSteps = List.unmodifiable([
      for (final (stepIndex, step) in aiProgressSteps.indexed)
        step.copyWith(
          state: stepIndex < clamped
              ? StudioScriptAiProgressStepState.done
              : stepIndex == clamped
                  ? StudioScriptAiProgressStepState.active
                  : StudioScriptAiProgressStepState.waiting,
        ),
    ]);
    aiStatus = status;
    aiOperationStatus = OperationStatus.running(
      code: OperationStatusCode.aiExtraction,
      message: status,
    );
    notifyListeners();
  }

  void _completeAiProgress(String status) {
    aiProgressSteps = List.unmodifiable([
      for (final step in aiProgressSteps)
        step.copyWith(state: StudioScriptAiProgressStepState.done),
    ]);
    _aiProgressIndex = aiProgressSteps.length - 1;
    aiStatus = status;
    aiOperationStatus = OperationStatus.success(
      code: OperationStatusCode.aiExtraction,
      message: status,
    );
    notifyListeners();
  }

  void _failAiProgress(String status) {
    if (aiProgressSteps.isNotEmpty) {
      final failedIndex = _aiProgressIndex.clamp(0, aiProgressSteps.length - 1);
      aiProgressSteps = List.unmodifiable([
        for (final (stepIndex, step) in aiProgressSteps.indexed)
          step.copyWith(
            state: stepIndex < failedIndex
                ? StudioScriptAiProgressStepState.done
                : stepIndex == failedIndex
                    ? StudioScriptAiProgressStepState.failed
                    : StudioScriptAiProgressStepState.waiting,
          ),
      ]);
    }
    aiStatus = status;
    aiOperationStatus = OperationStatus.failure(
      code: OperationStatusCode.aiExtraction,
      message: status,
      recoverable: true,
    );
    notifyListeners();
  }

  void _clearAiRoleExtractionLiveOutput() {
    aiRoleExtractionReasoningContent = '';
    aiRoleExtractionStreamingContent = '';
    aiRoleExtractionTraceEvents = const [];
    _lastAiRoleExtractionStreamNotifyAt = null;
    _pendingAiRoleExtractionStreamChars = 0;
    _aiRoleExtractionStreamNotifyTimer?.cancel();
    _aiRoleExtractionStreamNotifyTimer = null;
  }

  void _pushAiRoleExtractionTrace({
    required StudioScriptAiTraceEventKind kind,
    required String title,
    required String detail,
  }) {
    final trimmedDetail = detail.trim();
    if (trimmedDetail.isEmpty) {
      return;
    }
    final next = [
      ...aiRoleExtractionTraceEvents,
      StudioScriptAiTraceEvent(
        kind: kind,
        at: DateTime.now(),
        title: title,
        detail: trimmedDetail,
      ),
    ];
    aiRoleExtractionTraceEvents = List.unmodifiable(
      next.length > 80 ? next.sublist(next.length - 80) : next,
    );
  }

  void _handleAiRoleExtractionStreamDelta(
    ScriptAiRoleExtractionStreamDelta delta,
  ) {
    final reasoningDelta = delta.reasoningContentDelta;
    final contentDelta = delta.contentDelta;
    if (reasoningDelta.isNotEmpty) {
      aiRoleExtractionReasoningContent += reasoningDelta;
    }
    if (contentDelta.isNotEmpty) {
      aiRoleExtractionStreamingContent += contentDelta;
    }
    if (reasoningDelta.isNotEmpty || contentDelta.isNotEmpty) {
      _notifyAiRoleExtractionStreamDelta(
        reasoningDelta.length + contentDelta.length,
      );
    }
  }

  void _notifyAiRoleExtractionStreamDelta(int charCount) {
    _pendingAiRoleExtractionStreamChars += charCount;
    final now = DateTime.now();
    final previous = _lastAiRoleExtractionStreamNotifyAt;
    final shouldNotify = previous == null ||
        now.difference(previous) >= const Duration(milliseconds: 120) ||
        _pendingAiRoleExtractionStreamChars >= 240;
    if (!shouldNotify) {
      _aiRoleExtractionStreamNotifyTimer ??= Timer(
        const Duration(milliseconds: 120),
        _flushAiRoleExtractionStreamNotify,
      );
      return;
    }
    _flushAiRoleExtractionStreamNotify(now);
  }

  void _flushAiRoleExtractionStreamNotify([DateTime? at]) {
    if (_pendingAiRoleExtractionStreamChars <= 0) {
      _aiRoleExtractionStreamNotifyTimer?.cancel();
      _aiRoleExtractionStreamNotifyTimer = null;
      return;
    }
    _aiRoleExtractionStreamNotifyTimer?.cancel();
    _aiRoleExtractionStreamNotifyTimer = null;
    _lastAiRoleExtractionStreamNotifyAt = at ?? DateTime.now();
    _pendingAiRoleExtractionStreamChars = 0;
    notifyListeners();
  }

  String _aiRoleExtractionRequestTraceLine(
    Map<String, dynamic> requestPreview,
  ) {
    final parts = <String>[];
    final kind = requestPreview['request_kind']?.toString().trim();
    final chunkId = requestPreview['chunk_id']?.toString().trim();
    final script = requestPreview['script'];
    final sources = requestPreview['sources'];
    final chunk = requestPreview['chunk'];
    if (kind != null && kind.isNotEmpty) {
      parts.add(kind);
    }
    if (chunkId != null && chunkId.isNotEmpty) {
      parts.add(chunkId);
    }
    if (script is Map && script['name'] != null) {
      parts.add(script['name'].toString());
    }
    if (chunk is Map) {
      final start = chunk['start_frame_index'];
      final end = chunk['end_frame_index'];
      if (start != null || end != null) {
        parts.add('frames ${start ?? '?'}-${end ?? '?'}');
      }
    }
    if (sources is List) {
      parts.add('${sources.length} evidence sources');
    }
    return parts.isEmpty ? 'AI request started' : parts.join(' · ');
  }

  Future<void> generateAiRoleExtraction() async {
    if (isAiBusy) {
      return;
    }
    final script = _script;
    if (script == null) {
      aiStatus = '请先导入剧本';
      notifyListeners();
      return;
    }
    if (!_hasParsedScriptFrames(script)) {
      _recordEmptyAiRoleExtractionFailure();
      notifyListeners();
      return;
    }
    final service = scriptAiRoleExtractionService;
    if (service == null) {
      aiStatus = 'Script AI 角色字段提取服务未配置';
      notifyListeners();
      return;
    }
    final baseUrl = scriptAiBaseUrlProvider?.call().trim() ?? '';
    final token = scriptAiTokenProvider?.call().trim() ?? '';
    final model = scriptAiModelProvider?.call().trim() ?? '';
    final reasoningEffort =
        scriptAiReasoningEffortProvider?.call().trim() ?? '';
    if (baseUrl.isEmpty || token.isEmpty || model.isEmpty) {
      aiStatus = '请先配置 Script AI 地址、Token 和模型';
      notifyListeners();
      return;
    }

    final operationId = _beginAiOperation();
    _aiRoleExtractionDraftDismissed = false;
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionFinalized = false;
    isExtractingAiRoleEvidence = true;
    _startAiProgress(
      title: 'AI 整理角色字段',
      steps: const [
        '检查导入剧本',
        '压缩原始标签证据',
        '准备 AI 请求',
        '请求 AI 角色字段',
        '解析角色与服装阶段',
        '整理画师串和强过滤词',
        '写入草稿缓存',
      ],
      status: '正在启动角色字段整理',
    );
    try {
      _setAiProgressStep(0, '正在检查导入剧本...');
      _setAiProgressStep(1, '正在压缩原始 script tag 证据...');
      _setAiProgressStep(2, '正在准备 AI 请求...');
      await _deleteCurrentScriptCache(script);
      _resetAiRoleExtractionForFreshRun();
      _setAiProgressStep(3, '正在请求 AI 提取角色字段...');
      _clearAiRoleExtractionLiveOutput();
      final result = await service.extractRoles(
        request: ScriptAiRoleExtractionServiceRequest(
          baseUrl: baseUrl,
          token: token,
          model: model,
          reasoningEffort: reasoningEffort,
          proxy: scriptAiProxyProvider?.call().trim() ?? '',
          script: script,
          completedChunkExtractions: aiRoleExtractionChunks,
          translationCache: translationCache,
          classificationCache: classificationCache,
          saveTranslationCache: saveTranslationCache,
          saveClassificationCache: saveClassificationCache,
          onRequestStarted: (requestPreview) {
            if (!_isCurrentAiOperation(operationId)) {
              return;
            }
            aiRoleExtractionRequestCount += 1;
            aiRoleExtractionRequestPreview = Map<String, dynamic>.unmodifiable(
              requestPreview,
            );
            _pushAiRoleExtractionTrace(
              kind: StudioScriptAiTraceEventKind.input,
              title: '输入请求',
              detail: _aiRoleExtractionRequestTraceLine(requestPreview),
            );
            notifyListeners();
          },
          onStreamDelta: (delta) {
            if (_isCurrentAiOperation(operationId)) {
              _handleAiRoleExtractionStreamDelta(delta);
            }
          },
          onChunkCompleted: (extraction, requestPreview) async {
            if (!_isCurrentAiOperation(operationId)) {
              return;
            }
            aiRoleExtractionChunks = List.unmodifiable(
              _mergeAiRoleExtractionChunks(aiRoleExtractionChunks, [
                extraction,
              ]),
            );
            aiRoleExtractionRequestPreview = Map<String, dynamic>.unmodifiable(
              requestPreview,
            );
            _pushAiRoleExtractionTrace(
              kind: StudioScriptAiTraceEventKind.result,
              title: 'Chunk checkpoint',
              detail: 'Saved ${extraction.chunkId ?? 'chunk'} for resume.',
            );
            await _saveCurrentStateForScript(script);
            notifyListeners();
          },
        ),
      );
      if (!_isCurrentAiOperation(operationId)) {
        return;
      }

      _setAiProgressStep(4, '正在解析角色数量、服装阶段和五字段...');
      _pushAiRoleExtractionTrace(
        kind: StudioScriptAiTraceEventKind.parse,
        title: '解析返回',
        detail: '正在解析 AI JSON、角色、服装阶段和五字段',
      );
      aiRoleExtraction = _roleExtractionWithMaterializedNonRoleFields(
        extraction: result.extraction,
        script: script,
      );
      aiRoleExtractionRequestPreview = Map<String, dynamic>.unmodifiable(
        result.requestPreview,
      );
      if (result.reasoningContent.trim().isNotEmpty) {
        aiRoleExtractionReasoningContent = result.reasoningContent;
      }
      if (result.extraction.rawResponse.trim().isNotEmpty) {
        aiRoleExtractionStreamingContent = result.extraction.rawResponse;
      }
      aiRoleExtractionRequestCount = result.aiRequestCount;
      _refreshArtistMappings();
      _setAiProgressStep(5, '正在整理画师串证据和马赛克/审查强过滤词...');
      _refreshRecastPlan();
      _pushAiRoleExtractionTrace(
        kind: result.extraction.isFailed
            ? StudioScriptAiTraceEventKind.error
            : StudioScriptAiTraceEventKind.result,
        title: result.extraction.isFailed ? '解析失败' : '解析完成',
        detail:
            '${result.extraction.roles.length} 个角色，${result.extraction.artistChains.length} 条画师证据，${result.extraction.strongFilterKeywords.length} 个强过滤词',
      );
      _setAiProgressStep(6, '正在写入角色字段草稿和缓存...');
      await _saveCurrentStateForScript(script);
      if (result.extraction.isFailed) {
        _failAiProgress(_aiRoleExtractionFailureStatus(result.extraction));
      } else {
        _completeAiProgress('AI 角色字段草稿已生成');
      }
    } catch (error) {
      if (!_isCurrentAiOperation(operationId)) {
        return;
      }
      aiRoleExtraction = ScriptAiRoleExtraction.failure(
        message: error.toString(),
        rawResponse: '',
      );
      _pushAiRoleExtractionTrace(
        kind: StudioScriptAiTraceEventKind.error,
        title: '请求失败',
        detail: error.toString(),
      );
      _refreshRecastPlan();
      await _saveCurrentStateForScript(script);
      _failAiProgress('AI 角色字段整理失败：$error');
    } finally {
      if (_isCurrentAiOperation(operationId)) {
        isExtractingAiRoleEvidence = false;
        notifyListeners();
      }
    }
  }

  bool _hasParsedScriptFrames(Script script) {
    return script.frames.any(
      (frame) => frame.parseStatus == ScriptFrameParseStatus.parsed,
    );
  }

  Future<void> _deleteCurrentScriptCache(Script script) async {
    final saver = saveRecastCaches;
    final loader = loadRecastCaches;
    if (saver == null || loader == null) {
      return;
    }
    final existing = await loader();
    await saver([
      for (final entry in existing)
        if (!cacheRestoreService.cacheBelongsToScript(entry, script)) entry,
    ]);
  }

  void _resetAiRoleExtractionForFreshRun() {
    aiRoleExtraction = const ScriptAiRoleExtraction();
    aiRoleExtractionRequestPreview = const {};
    aiRoleExtractionReasoningContent = '';
    aiRoleExtractionStreamingContent = '';
    aiRoleExtractionTraceEvents = const [];
    aiRoleExtractionChunks = const [];
    aiRoleExtractionRequestCount = 0;
    _aiRoleExtractionDraftDismissed = false;
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionFinalized = false;
  }

  void _recordEmptyAiRoleExtractionFailure() {
    const message =
        '当前导入目录没有可解析的剧本帧。请导入包含提示词 metadata 的 JSON 或 PNG 文件后再整理角色字段。';
    _clearAiProgress();
    _clearAiRoleExtractionLiveOutput();
    _aiRoleExtractionDraftDismissed = false;
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionFinalized = false;
    aiRoleExtractionRequestPreview = const {};
    aiRoleExtractionChunks = const [];
    aiRoleExtractionRequestCount = 0;
    aiRoleExtraction = const ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.failed,
      attentionItems: [
        ScriptAiExtractionAttentionItem(
          id: 'ai-role-extraction-no-parsed-frames',
          kind: 'no_parsed_frames',
          message: message,
          blocking: true,
        ),
      ],
    );
    aiStatus = message;
  }

  String _aiRoleExtractionFailureStatus(ScriptAiRoleExtraction extraction) {
    String? first;
    for (final item in extraction.attentionItems) {
      final message = item.message.trim();
      if (message.isEmpty) {
        continue;
      }
      first ??= message;
      if (item.blocking) {
        return message;
      }
    }
    return first ?? 'AI 角色字段整理失败';
  }

  void setAiRoleExtractionStageField({
    required String sourceRoleId,
    required String stageId,
    required StudioScriptRolePart part,
    required String value,
  }) {
    final extraction = aiRoleExtraction;
    if (!extraction.isReady) {
      return;
    }
    final beforeParts = _aiExtractionStageParts(
      extraction: extraction,
      sourceRoleId: sourceRoleId,
      stageId: stageId,
    );
    var changed = false;
    aiRoleExtraction = ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: extraction.status,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      artistChains: extraction.artistChains,
      strongFilterKeywords: extraction.strongFilterKeywords,
      attentionItems: extraction.attentionItems,
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      sceneTerms: extraction.sceneTerms,
      termCacheSuggestions: extraction.termCacheSuggestions,
      rawResponse: extraction.rawResponse,
      roles: List.unmodifiable([
        for (final role in extraction.roles)
          if (role.sourceRoleId == sourceRoleId)
            _extractedRoleWithEditedStageField(
              role: role,
              stageId: stageId,
              part: part,
              value: value,
              onChanged: () => changed = true,
            )
          else
            role,
      ]),
    );
    aiRoleExtraction = _extractionWithVisibleRolePromptTerms(aiRoleExtraction);
    if (!changed) {
      return;
    }
    final afterParts = _aiExtractionStageParts(
      extraction: aiRoleExtraction,
      sourceRoleId: sourceRoleId,
      stageId: stageId,
    );
    if (beforeParts != null && afterParts != null) {
      _recordManualRoleFieldOverride(
        beforeParts: beforeParts,
        afterParts: afterParts,
        editedPart: part,
      );
    }
    _aiRoleExtractionDraftDismissed = false;
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionFinalized = false;
    _refreshRecastPlan();
    unawaited(_saveCurrentCache());
    notifyListeners();
  }

  ScriptAiExtractedRole _extractedRoleWithEditedStageField({
    required ScriptAiExtractedRole role,
    required String stageId,
    required StudioScriptRolePart part,
    required String value,
    required VoidCallback onChanged,
  }) {
    return ScriptAiExtractedRole(
      sourceRoleId: role.sourceRoleId,
      sourceKind: role.sourceKind,
      displayName: role.displayName,
      roleReason: role.roleReason,
      canonicalName: role.canonicalName,
      franchise: role.franchise,
      rawIdentityTags: role.rawIdentityTags,
      variantTags: role.variantTags,
      mergeWithRoleId: role.mergeWithRoleId,
      confidence: role.confidence,
      frameIndexes: role.frameIndexes,
      appearances: role.appearances,
      evidenceTerms: role.evidenceTerms,
      warnings: role.warnings,
      unassignedTerms: role.unassignedTerms,
      promptTerms: role.promptTerms,
      stages: List.unmodifiable([
        for (final stage in role.stages)
          if (stage.stageId == stageId)
            _extractedStageWithEditedField(
              stage: stage,
              part: part,
              value: value,
              onChanged: onChanged,
            )
          else
            stage,
      ]),
    );
  }

  ScriptAiExtractedStage _extractedStageWithEditedField({
    required ScriptAiExtractedStage stage,
    required StudioScriptRolePart part,
    required String value,
    required VoidCallback onChanged,
  }) {
    final current = switch (part) {
      StudioScriptRolePart.identity => stage.identity,
      StudioScriptRolePart.upperBody => stage.upperBody,
      StudioScriptRolePart.lowerBody => stage.lowerBody,
      StudioScriptRolePart.upperClothing => stage.upperClothing,
      StudioScriptRolePart.lowerClothing => stage.lowerClothing,
      StudioScriptRolePart.nonRole => stage.nonRole,
    };
    if (current == value) {
      return stage;
    }
    onChanged();
    return ScriptAiExtractedStage(
      stageId: stage.stageId,
      label: stage.label,
      appearanceGroupId: stage.appearanceGroupId,
      mergeWithStageIds: stage.mergeWithStageIds,
      fieldReasons: stage.fieldReasons,
      confidence: stage.confidence,
      frameIndexes: stage.frameIndexes,
      identity: part == StudioScriptRolePart.identity ? value : stage.identity,
      upperBody:
          part == StudioScriptRolePart.upperBody ? value : stage.upperBody,
      lowerBody:
          part == StudioScriptRolePart.lowerBody ? value : stage.lowerBody,
      upperClothing: part == StudioScriptRolePart.upperClothing
          ? value
          : stage.upperClothing,
      lowerClothing: part == StudioScriptRolePart.lowerClothing
          ? value
          : stage.lowerClothing,
      nonRole: part == StudioScriptRolePart.nonRole ? value : stage.nonRole,
      nonRoleMaterialized: part == StudioScriptRolePart.nonRole
          ? true
          : stage.nonRoleMaterialized,
      evidenceTerms: stage.evidenceTerms,
      missingFields: stage.missingFields,
      warnings: stage.warnings,
    );
  }

  Future<void> applyHighConfidenceAiRoleExtraction() => applyAiRoleExtraction();

  Future<void> applyAiRoleExtraction() async {
    if (isApplyingAiRoleExtraction) {
      return;
    }
    final operationId = _beginAiOperation();
    isApplyingAiRoleExtraction = true;
    notifyListeners();
    try {
      final script = _script;
      final mapping = _mapping;
      final extraction =
          _extractionWithVisibleRolePromptTerms(aiRoleExtraction);
      aiRoleExtraction = extraction;
      if (script == null || mapping == null || !extraction.isReady) {
        aiStatus = '没有可应用的 AI 角色字段草稿';
        notifyListeners();
        return;
      }

      final strongFilterTerms = [
        for (final keyword in extraction.strongFilterKeywords)
          if (keyword.term.trim().isNotEmpty) keyword.term,
      ];
      if (strongFilterTerms.isNotEmpty) {
        await addTagsToFilterRulesLibrary(
          strongFilterTerms,
          PromptTagFilterRuleTarget.strongFilterKeywords,
        );
        if (!_isCurrentAiOperation(operationId)) {
          return;
        }
      }

      final application = _mappingWithAppliedAiRoleExtraction(
        script: script,
        mapping: mapping,
        extraction: extraction,
      );
      final changed = application.changed;
      _aiRoleExtractionFinalized =
          extraction.roles.isNotEmpty || extraction.sceneTerms.isNotEmpty;

      if (changed) {
        _mapping = application.mapping;
        _refreshPreview();
        _aiRoleExtractionDraftDismissed = true;
        _clearAiProgress();
        aiStatus = '已应用 AI 源角色字段';
      } else {
        aiStatus =
            strongFilterTerms.isEmpty ? '没有可应用的 AI 源角色字段' : '已应用 AI 强过滤关键词';
        _aiRoleExtractionDraftDismissed = true;
        _clearAiProgress();
        _refreshRecastPlan();
      }
      await _saveCurrentCache();
      if (!_isCurrentAiOperation(operationId)) {
        return;
      }
      notifyListeners();
    } finally {
      if (_isCurrentAiOperation(operationId)) {
        isApplyingAiRoleExtraction = false;
        notifyListeners();
      }
    }
  }

  ({RecastMapping mapping, bool changed}) _mappingWithAppliedAiRoleExtraction({
    required Script script,
    required RecastMapping mapping,
    required ScriptAiRoleExtraction extraction,
  }) {
    final recoveredExtraction =
        _extractionWithRecoveredReplacementTermsIfNeeded(extraction);
    if (!recoveredExtraction.isReady ||
        (recoveredExtraction.roles.isEmpty &&
            recoveredExtraction.sceneTerms.isEmpty)) {
      return (mapping: mapping, changed: false);
    }

    final application = const ScriptAiRoleAssemblyApplication().apply(
      mapping: _mappingWithRoleAssemblies(script, mapping),
      extraction: recoveredExtraction,
      stageLabelFor: (stage, index) => _aiOutfitStageDisplayLabel(
        stage,
        fallback: 'AI field ${index + 1}',
        index: index,
        translationCache: translationCache,
      ),
    );
    return (
      mapping: application.mapping,
      changed: application.changed,
    );
  }

  List<ScriptAiRoleExtraction> _mergeAiRoleExtractionChunks(
    List<ScriptAiRoleExtraction> current,
    List<ScriptAiRoleExtraction> next,
  ) {
    final byChunkId = <String, ScriptAiRoleExtraction>{};
    final order = <String>[];

    void add(ScriptAiRoleExtraction extraction) {
      final chunkId = extraction.chunkId?.trim();
      if (chunkId == null || chunkId.isEmpty || !extraction.isReady) {
        return;
      }
      if (!byChunkId.containsKey(chunkId)) {
        order.add(chunkId);
      }
      byChunkId[chunkId] = extraction;
    }

    for (final extraction in current) {
      add(extraction);
    }
    for (final extraction in next) {
      add(extraction);
    }

    return [
      for (final chunkId in order)
        if (byChunkId[chunkId] != null) byChunkId[chunkId]!,
    ];
  }

  bool _isUserAuthoredStage(RoleAssemblyStage stage) {
    return stage.targetCharacterId != null ||
        stage.targetUpperOutfitId != null ||
        stage.targetLowerOutfitId != null ||
        !stage.manualParts.isEmpty;
  }

  String? _selectedStageIdForRole(String sourceRoleId, RoleAssembly assembly) {
    final manualStageId = _manualSelectedStageIdsByRole[sourceRoleId];
    if (manualStageId != null &&
        assembly.stages.any((stage) => stage.id == manualStageId)) {
      return manualStageId;
    }
    final selectedFrameIndex = _selectedFrameIndex;
    if (selectedFrameIndex != null) {
      final frameStage = assembly.stages
          .where((stage) => stage.frameIndexes.contains(selectedFrameIndex))
          .firstOrNull;
      if (frameStage != null) {
        return frameStage.id;
      }
    }
    final previous = roleMappings
        .where((item) => item.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final previousStageId = previous?.selectedStageId;
    if (previousStageId != null &&
        assembly.stages.any((stage) => stage.id == previousStageId)) {
      return previousStageId;
    }
    final selectedStageId = previous?.selectedStage?.id;
    if (selectedStageId != null &&
        assembly.stages.any((stage) => stage.id == selectedStageId)) {
      return selectedStageId;
    }
    return assembly.stages.firstOrNull?.id;
  }

  RecastPromptParts _fillEmptyPromptParts(
    RecastPromptParts current,
    RecastPromptParts fallback,
  ) {
    return current.copyWith(
      identity: _fillIfEmpty(current.identity, fallback.identity),
      upperBody: _fillIfEmpty(current.upperBody, fallback.upperBody),
      lowerBody: _fillIfEmpty(current.lowerBody, fallback.lowerBody),
      upperClothing: _fillIfEmpty(
        current.upperClothing,
        fallback.upperClothing,
      ),
      lowerClothing: _fillIfEmpty(
        current.lowerClothing,
        fallback.lowerClothing,
      ),
    );
  }

  bool _promptPartsEqual(RecastPromptParts left, RecastPromptParts right) {
    return left.identity == right.identity &&
        left.upperBody == right.upperBody &&
        left.lowerBody == right.lowerBody &&
        left.upperClothing == right.upperClothing &&
        left.lowerClothing == right.lowerClothing;
  }

  bool _roleAssemblyStagesEqual(
    List<RoleAssemblyStage> left,
    List<RoleAssemblyStage> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftStage = left[index];
      final rightStage = right[index];
      if (leftStage.id != rightStage.id ||
          leftStage.label != rightStage.label ||
          leftStage.sourceSummary != rightStage.sourceSummary ||
          !_promptPartsEqual(leftStage.sourceParts, rightStage.sourceParts) ||
          leftStage.targetCharacterId != rightStage.targetCharacterId ||
          leftStage.targetUpperOutfitId != rightStage.targetUpperOutfitId ||
          leftStage.targetLowerOutfitId != rightStage.targetLowerOutfitId ||
          !setEquals(leftStage.omittedParts, rightStage.omittedParts) ||
          !setEquals(leftStage.preservedParts, rightStage.preservedParts) ||
          !listEquals(leftStage.frameIndexes, rightStage.frameIndexes) ||
          !_promptPartsEqual(leftStage.manualParts, rightStage.manualParts)) {
        return false;
      }
    }
    return true;
  }

  Future<void> useFreshParseForChangedSource() async {
    if (_script == null) {
      return;
    }
    _changedSourceCache = null;
    cacheStatus = '已重新解析当前源';
    await _saveCurrentCache();
    notifyListeners();
  }

  Future<void> restoreChangedSourceCache() async {
    final cache = _changedSourceCache;
    if (cache == null) {
      return;
    }
    _applyCache(cache);
    _changedSourceCache = null;
    cacheStatus = '已沿用旧缓存复现';
    await _saveCurrentCache();
    notifyListeners();
  }

  void selectFrame(int frameIndex) {
    if (_selectedFrameIndex == frameIndex) {
      return;
    }
    _selectedFrameIndex = frameIndex;
    _manualSelectedStageIdsByRole.clear();
    _refreshSelectedFramePreview();
    notifyListeners();
  }

  void applyFrameResults(List<FrameResult> results) {
    _frameResultStatuses = {
      ..._frameResultStatuses,
      for (final result in results) result.frameIndex: result.status,
    };
    _refreshTimeline();
    notifyListeners();
  }

  Future<void> saveGlobalBlockWords(String value) async {
    final normalized = _normalizeBlockWords(value);
    globalBlockWords = normalized;
    globalBlockWordsStatus = normalized.isEmpty
        ? '未设置全局屏蔽词'
        : '全局屏蔽词 ${_blockWordCount(normalized)} 个';
    final saver = saveFilterRules;
    if (saver != null) {
      final current = loadFilterRules == null
          ? <String, dynamic>{}
          : await loadFilterRules!();
      await saver({...current, 'delete_keywords': normalized});
    }
    _refreshPreview();
    notifyListeners();
  }

  Future<void> saveScriptBlockWords(String value) async {
    final normalized = _normalizeBlockWords(value);
    scriptBlockWords = normalized;
    _refreshPreview();
    _scheduleCurrentCacheSave();
    notifyListeners();
  }

  Future<void> addTagsToScriptBlockWords(List<String> tags) async {
    final incoming = _normalizeFilterRuleTags(tags);
    if (incoming.isEmpty) {
      return;
    }
    final merged = mergeFilterRuleWords(scriptBlockWords, incoming);
    await saveScriptBlockWords(merged);
  }

  void setGlobalPromptPrefix(String value) {
    final normalized = value.trim();
    if (globalPromptPrefix == normalized) {
      return;
    }
    globalPromptPrefix = normalized;
    _refreshPreview();
    unawaited(
      _saveGlobalPromptPrefix(normalized).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          'Failed to save script global prompt prefix: $error\n$stackTrace',
        );
      }),
    );
    notifyListeners();
  }

  Future<void> _saveGlobalPromptPrefix(String normalized) async {
    final saver = saveFilterRules;
    if (saver == null) {
      return;
    }
    final current = loadFilterRules == null
        ? <String, dynamic>{}
        : await loadFilterRules!();
    await saver({...current, 'global_prompt_prefix': normalized});
  }

  Future<FilterRuleConfig> loadFilterRuleConfig() async {
    final loader = loadFilterRules;
    if (loader == null) {
      final config = _filterRuleConfig.copyWith(
        deleteKeywords: globalBlockWords,
        globalPromptPrefix: globalPromptPrefix,
      );
      _filterRuleConfig = config;
      return config;
    }
    final config = FilterRuleConfig.fromMap(await loader());
    _filterRuleConfig = config;
    _applyGlobalBlockWords(config.deleteKeywords);
    _applyGlobalPromptPrefix(config.globalPromptPrefix);
    return config;
  }

  Future<void> saveFilterRuleConfig(FilterRuleConfig config) async {
    final normalized = FilterRuleConfig(
      deleteKeywords: _normalizeBlockWords(config.deleteKeywords),
      strongFilterKeywords: config.strongFilterKeywords.trim(),
      replaceRules: config.replaceRules.trim(),
      globalPromptPrefix: config.globalPromptPrefix.trim(),
      removeWeights: config.removeWeights,
      exactMatch: config.exactMatch,
      deleteArtistTags: config.deleteArtistTags,
    );
    _filterRuleConfig = normalized;
    _applyGlobalBlockWords(normalized.deleteKeywords);
    _applyGlobalPromptPrefix(normalized.globalPromptPrefix);
    final saver = saveFilterRules;
    if (saver != null) {
      final current = loadFilterRules == null
          ? <String, dynamic>{}
          : await loadFilterRules!();
      await saver({...current, ...normalized.toMap()});
    }
    _refreshPreview();
    notifyListeners();
  }

  Future<void> addTagsToFilterRulesLibrary(
    List<String> tags, [
    PromptTagFilterRuleTarget target = PromptTagFilterRuleTarget.deleteKeywords,
  ]) async {
    if (target == PromptTagFilterRuleTarget.scriptScopedBlockWords) {
      await addTagsToScriptBlockWords(tags);
      return;
    }
    final incoming = _normalizeFilterRuleTags(tags);
    if (incoming.isEmpty) {
      return;
    }
    final config = await loadFilterRuleConfig();
    final updated = addTagsToFilterRuleConfig(config, incoming, target);
    await saveFilterRuleConfig(updated);
  }

  void setRoleCharacter(String sourceRoleId, String? characterId) {
    final mapping = _editableRoleAssemblyMapping(_mapping);
    if (mapping == null) {
      return;
    }
    final character = characterId == null ? null : _characterById(characterId);
    final defaultOutfitId =
        characterId == null ? null : character?.defaultOutfitId;
    _mapping = _mappingWithVisibleSourceIdentityParts(
      mapping.copyWith(
        roleSwaps: _roleSwapsAfterTargetCharacterEdit(
          mapping,
          sourceRoleId: sourceRoleId,
          characterId: characterId,
          outfitId: defaultOutfitId,
        ),
        roleAssemblies: [
          for (final assembly in mapping.roleAssemblies)
            if (assembly.sourceRoleId == sourceRoleId)
              _assemblyWithCharacter(assembly, character, defaultOutfitId)
            else
              assembly,
        ],
      ),
    );
    _refreshRoleEditPreview(sourceRoleId);
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleOutfit(String sourceRoleId, String? outfitId) {
    final mapping = _editableRoleAssemblyMapping(_mapping);
    if (mapping == null) {
      return;
    }
    _mapping = _mappingWithVisibleSourceIdentityParts(
      mapping.copyWith(
        roleSwaps: _roleSwapsAfterTargetOutfitEdit(
          mapping,
          sourceRoleId: sourceRoleId,
          outfitId: outfitId,
        ),
        roleAssemblies: [
          for (final assembly in mapping.roleAssemblies)
            if (assembly.sourceRoleId == sourceRoleId)
              _assemblyWithOutfit(assembly, outfitId)
            else
              assembly,
        ],
      ),
    );
    _refreshRoleEditPreview(sourceRoleId);
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void applyRoleOutfitDrop({
    required String sourceRoleId,
    required String characterId,
    required String outfitId,
  }) {
    final mapping = _editableRoleAssemblyMapping(_mapping);
    if (mapping == null) {
      return;
    }
    final character = _characterById(characterId);
    final outfit = _outfitById(character, outfitId);
    if (character == null || outfit == null) {
      return;
    }
    _mapping = _mappingWithVisibleSourceIdentityParts(
      mapping.copyWith(
        roleSwaps: _roleSwapsAfterTargetCharacterEdit(
          mapping,
          sourceRoleId: sourceRoleId,
          characterId: characterId,
          outfitId: outfitId,
        ),
        roleAssemblies: [
          for (final assembly in mapping.roleAssemblies)
            if (assembly.sourceRoleId == sourceRoleId)
              _assemblyWithDroppedOutfit(
                assembly,
                character: character,
                outfitId: outfitId,
                outfit: outfit,
              )
            else
              assembly,
        ],
      ),
    );
    _refreshRoleEditPreview(sourceRoleId);
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleReplacementTargetCharacter(
    String sourceRoleId,
    String characterId, {
    String? outfitId,
  }) {
    final character = _characterById(characterId);
    if (character == null) {
      return;
    }
    final targetIdentityPrompt = _roleReplacementCandidatePrompt(
      character,
      outfitId: outfitId,
    );
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) {
        // Dropping a character card edits the target identity only.  It must
        // not erase already-confirmed source -> target rules; users can use
        // “重置本组” when they explicitly want to clear those rules.
        final targetIdentityChanged =
            replacement.targetCharacterId != character.id ||
                replacement.targetIdentityPrompt.trim() !=
                    targetIdentityPrompt.trim();
        return replacement.copyWith(
          targetCharacterId: character.id,
          targetIdentityPrompt: targetIdentityPrompt,
          activeMappingProfileId:
              targetIdentityChanged ? null : replacement.activeMappingProfileId,
        );
      },
      learnProfile: false,
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleReplacementIdentityPrompt(String sourceRoleId, String value) {
    final nextValue = value.trim().isEmpty ? '' : value;
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) => replacement.copyWith(targetIdentityPrompt: nextValue),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void appendRoleReplacementPendingPrompt(String sourceRoleId, String value) {
    final nextValue = value.trim();
    if (nextValue.isEmpty) {
      return;
    }
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) => replacement.copyWith(
        targetIdentityPrompt: _joinPromptTags([
          replacement.targetIdentityPrompt,
          nextValue,
        ]),
      ),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleReplacementRuleTarget(
    String sourceRoleId,
    String ruleId,
    String value,
  ) {
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => _ruleWithTarget(rule, value),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleReplacementRuleSource(
    String sourceRoleId,
    String ruleId,
    String value,
  ) {
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => _ruleWithSourcePrompt(rule, value),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void appendRoleReplacementRuleTargetTags(
    String sourceRoleId,
    String ruleId,
    Iterable<String> tags,
  ) {
    final incoming = [
      for (final tag in tags)
        if (tag.trim().isNotEmpty) tag.trim(),
    ];
    if (incoming.isEmpty) {
      return;
    }
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => _ruleWithTarget(
        rule,
        _joinPromptTags([
          rule.targetPrompt,
          ...incoming,
        ]),
      ),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  bool get hasSingleSelectedReplacementRule {
    return _selectedReplacementRuleTarget() != null;
  }

  bool addFrameReviewTermsToSelectedReplacementRule({
    required int frameIndex,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    final target = _selectedReplacementRuleTarget();
    if (target == null) {
      return false;
    }
    return switch (target) {
      _SelectedRoleReplacementRuleTarget() =>
        addFrameReviewTermsToRoleReplacementRule(
          sourceRoleId: target.sourceRoleId,
          ruleId: target.ruleId,
          frameIndex: frameIndex,
          sourceLocation: sourceLocation,
          terms: terms,
        ),
      _SelectedSceneReplacementRuleTarget() =>
        addFrameReviewTermsToSceneReplacementRule(
          groupId: target.groupId,
          ruleId: target.ruleId,
          frameIndex: frameIndex,
          sourceLocation: sourceLocation,
          terms: terms,
        ),
    };
  }

  bool addSelectedFramePreviewTermsToSelectedReplacementRule({
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    return addFrameReviewTermsToSelectedReplacementRule(
      frameIndex: _selectedFrameIndex ?? 0,
      sourceLocation: sourceLocation,
      terms: terms,
    );
  }

  bool addSelectedFramePreviewTermsToReplacementArea({
    required String sourceGroupId,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    return addFrameReviewTermsToReplacementArea(
      frameIndex: _selectedFrameIndex ?? 0,
      sourceGroupId: _selectedFramePreviewSourceGroupId(sourceGroupId),
      sourceLocation: sourceLocation,
      terms: terms,
    );
  }

  bool addFrameReviewTermsToReplacementArea({
    required int frameIndex,
    required String sourceGroupId,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return false;
    }
    final roleReplacement = _roleReplacementForFrameGroup(
      mapping,
      frameIndex: frameIndex,
      sourceGroupId: sourceGroupId,
    );
    if (roleReplacement != null) {
      final incoming = _frameReviewReplacementTerms(
        frameIndex: frameIndex,
        sourceLocation: sourceLocation,
        terms: terms,
        scope: 'role',
        ownerId: roleReplacement.sourceRoleId,
        sourceGroupId: sourceGroupId,
      );
      if (incoming.isEmpty) {
        return false;
      }
      return _addFrameReviewReplacementTermsToRole(
        mapping: mapping,
        sourceRoleId: roleReplacement.sourceRoleId,
        sourceTerms: incoming,
      );
    }

    final sceneGroupId = _frameReviewSceneReplacementGroupId(sourceGroupId);
    final incoming = _frameReviewReplacementTerms(
      frameIndex: frameIndex,
      sourceLocation: sourceLocation,
      terms: terms,
      scope: 'scene',
      ownerId: sceneGroupId,
      sourceGroupId: sourceGroupId,
    );
    if (incoming.isEmpty) {
      return false;
    }
    return _addFrameReviewReplacementTermsToScene(
      mapping: mapping,
      sceneGroupId: sceneGroupId,
      sourceLocation: sourceLocation,
      sourceTerms: incoming,
    );
  }

  bool addFrameReviewTermsToRoleReplacementArea({
    required String sourceRoleId,
    required int frameIndex,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return false;
    }
    final incoming = _frameReviewReplacementTerms(
      frameIndex: frameIndex,
      sourceLocation: sourceLocation,
      terms: terms,
      scope: 'role',
      ownerId: sourceRoleId,
    );
    if (incoming.isEmpty) {
      return false;
    }
    return _addFrameReviewReplacementTermsToRole(
      mapping: mapping,
      sourceRoleId: sourceRoleId,
      sourceTerms: incoming,
    );
  }

  bool addSelectedFramePreviewTermsToRoleReplacementArea({
    required String sourceRoleId,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    return addFrameReviewTermsToRoleReplacementArea(
      sourceRoleId: sourceRoleId,
      frameIndex: _selectedFrameIndex ?? 0,
      sourceLocation: sourceLocation,
      terms: terms,
    );
  }

  bool addFrameReviewTermsToSceneReplacementArea({
    required String groupId,
    required int frameIndex,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return false;
    }
    final incoming = _frameReviewReplacementTerms(
      frameIndex: frameIndex,
      sourceLocation: sourceLocation,
      terms: terms,
      scope: 'scene',
      ownerId: groupId,
    );
    if (incoming.isEmpty) {
      return false;
    }
    return _addFrameReviewReplacementTermsToSceneGroup(
      mapping: mapping,
      groupId: groupId,
      label: sourceLocation,
      sourceTerms: incoming,
    );
  }

  bool addSelectedFramePreviewTermsToSceneReplacementArea({
    required String groupId,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    return addFrameReviewTermsToSceneReplacementArea(
      groupId: groupId,
      frameIndex: _selectedFrameIndex ?? 0,
      sourceLocation: sourceLocation,
      terms: terms,
    );
  }

  bool _addFrameReviewReplacementTermsToRole({
    required RecastMapping mapping,
    required String sourceRoleId,
    required List<ScriptPromptReplacementTerm> sourceTerms,
  }) {
    final roleReplacement = mapping.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (roleReplacement == null) {
      return false;
    }
    final nextRules = _replacementRulesWithAddedFrameReviewRule(
      rules: roleReplacement.rules,
      scope: 'role',
      ownerId: roleReplacement.sourceRoleId,
      sourceTerms: sourceTerms,
    );
    if (nextRules == null) {
      return false;
    }
    _selectedRoleReplacementRuleIdsByRole[roleReplacement.sourceRoleId] = {
      nextRules.selectedRuleId,
    };
    _mapping = mapping.copyWith(
      rolePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.rolePromptReplacements)
          if (replacement.sourceRoleId == roleReplacement.sourceRoleId)
            replacement.copyWith(rules: nextRules.rules)
          else
            replacement,
      ]),
    );
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
    return true;
  }

  bool _addFrameReviewReplacementTermsToScene({
    required RecastMapping mapping,
    required String sceneGroupId,
    required String sourceLocation,
    required List<ScriptPromptReplacementTerm> sourceTerms,
  }) {
    return _addFrameReviewReplacementTermsToSceneGroup(
      mapping: mapping,
      groupId: sceneGroupId,
      label: sourceLocation.trim().isEmpty ? 'Frame source' : sourceLocation,
      sourceTerms: sourceTerms,
    );
  }

  bool _addFrameReviewReplacementTermsToSceneGroup({
    required RecastMapping mapping,
    required String groupId,
    required String label,
    required List<ScriptPromptReplacementTerm> sourceTerms,
  }) {
    final sceneReplacement = mapping.scenePromptReplacements
            .where((replacement) => replacement.id == groupId)
            .firstOrNull ??
        ScriptScenePromptReplacement(
          id: groupId,
          label: label.trim().isEmpty ? 'Frame source' : label,
        );
    final nextRules = _replacementRulesWithAddedFrameReviewRule(
      rules: sceneReplacement.rules,
      scope: 'scene',
      ownerId: sceneReplacement.id,
      sourceTerms: sourceTerms,
    );
    if (nextRules == null) {
      return false;
    }
    _selectedSceneReplacementRuleIdsByGroup[sceneReplacement.id] = {
      nextRules.selectedRuleId,
    };
    var replaced = false;
    _mapping = mapping.copyWith(
      scenePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.scenePromptReplacements)
          if (replacement.id == sceneReplacement.id)
            _markChanged(
              replacement.copyWith(rules: nextRules.rules),
              () => replaced = true,
            )
          else
            replacement,
        if (!replaced) sceneReplacement.copyWith(rules: nextRules.rules),
      ]),
    );
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
    return true;
  }

  bool addFrameReviewTermsToRoleReplacementRule({
    required String sourceRoleId,
    required String ruleId,
    required int frameIndex,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    final incoming = _frameReviewReplacementTerms(
      frameIndex: frameIndex,
      sourceLocation: sourceLocation,
      terms: terms,
      scope: 'role',
      ownerId: sourceRoleId,
    );
    if (incoming.isEmpty) {
      return false;
    }
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => rule.copyWith(
        sourceTerms: _replacementTermsWithAdded(rule.sourceTerms, incoming),
      ),
    )) {
      return false;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
    return true;
  }

  bool addFrameReviewTermsToSceneReplacementRule({
    required String groupId,
    required String ruleId,
    required int frameIndex,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
  }) {
    final incoming = _frameReviewReplacementTerms(
      frameIndex: frameIndex,
      sourceLocation: sourceLocation,
      terms: terms,
      scope: 'scene',
      ownerId: groupId,
    );
    if (incoming.isEmpty) {
      return false;
    }
    if (!_updateSceneReplacementRule(
      groupId: groupId,
      ruleId: ruleId,
      update: (rule) => rule.copyWith(
        sourceTerms: _replacementTermsWithAdded(rule.sourceTerms, incoming),
      ),
    )) {
      return false;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
    return true;
  }

  _SelectedReplacementRuleTarget? _selectedReplacementRuleTarget() {
    final roleTargets = <_SelectedRoleReplacementRuleTarget>[];
    for (final entry in _selectedRoleReplacementRuleIdsByRole.entries) {
      for (final ruleId in entry.value) {
        roleTargets.add(
          _SelectedRoleReplacementRuleTarget(
            sourceRoleId: entry.key,
            ruleId: ruleId,
          ),
        );
      }
    }
    final sceneTargets = <_SelectedSceneReplacementRuleTarget>[];
    for (final entry in _selectedSceneReplacementRuleIdsByGroup.entries) {
      for (final ruleId in entry.value) {
        sceneTargets.add(
          _SelectedSceneReplacementRuleTarget(
            groupId: entry.key,
            ruleId: ruleId,
          ),
        );
      }
    }
    if (roleTargets.length + sceneTargets.length != 1) {
      return null;
    }
    if (roleTargets.isNotEmpty) {
      return roleTargets.single;
    }
    return sceneTargets.single;
  }

  ScriptRolePromptReplacement? _roleReplacementForFrameGroup(
    RecastMapping mapping, {
    required int frameIndex,
    required String sourceGroupId,
  }) {
    final slotIndex = _roleSlotIndexForFrameReviewGroup(sourceGroupId);
    if (slotIndex == null) {
      return null;
    }
    final slotRoleId = 'slot-$slotIndex';
    final replacementsBySourceRoleId = {
      for (final replacement in mapping.rolePromptReplacements)
        replacement.sourceRoleId: replacement,
    };
    final direct = replacementsBySourceRoleId[slotRoleId];
    if (direct != null) {
      return direct;
    }
    for (final assembly in mapping.roleAssemblies) {
      if (!_roleAssemblyTargetsFrameSlot(
        assembly,
        slotRoleId: slotRoleId,
        frameIndex: frameIndex,
      )) {
        continue;
      }
      final replacement = replacementsBySourceRoleId[assembly.sourceRoleId];
      if (replacement != null) {
        return replacement;
      }
    }
    final replacementIndex = slotIndex;
    if (replacementIndex >= 0 &&
        replacementIndex < mapping.rolePromptReplacements.length) {
      return mapping.rolePromptReplacements[replacementIndex];
    }
    if (mapping.rolePromptReplacements.length == 1) {
      return mapping.rolePromptReplacements.single;
    }
    return null;
  }

  int? _roleSlotIndexForFrameReviewGroup(String sourceGroupId) {
    final match = RegExp(r'^role-(\d+)$').firstMatch(sourceGroupId.trim());
    final number = int.tryParse(match?.group(1) ?? '');
    if (number == null || number <= 0) {
      return null;
    }
    return number - 1;
  }

  bool _roleAssemblyTargetsFrameSlot(
    RoleAssembly assembly, {
    required String slotRoleId,
    required int frameIndex,
  }) {
    if (assembly.sourceRoleId.trim() == slotRoleId) {
      return true;
    }
    for (final appearance in assembly.sourceAppearances) {
      if (appearance.frameIndexes.isNotEmpty &&
          !appearance.frameIndexes.contains(frameIndex)) {
        continue;
      }
      final sourceKind = appearance.sourceKind.trim();
      if (sourceKind.isNotEmpty && sourceKind != 'slot') {
        continue;
      }
      if (appearance.sourceId.trim() == slotRoleId) {
        return true;
      }
    }
    return false;
  }

  String _selectedFramePreviewSourceGroupId(String sourceGroupId) {
    final trimmed = sourceGroupId.trim();
    if (trimmed.startsWith('before-')) {
      return trimmed.substring('before-'.length);
    }
    return trimmed;
  }

  String _frameReviewSceneReplacementGroupId(String sourceGroupId) {
    final normalized = PromptTagProcessor.normalizeMatchKey(sourceGroupId);
    if (normalized.isEmpty || normalized == 'base') {
      return 'frame-scene';
    }
    return stableIdFromText(
      prefix: 'frame-scene',
      text: normalized,
      label: sourceGroupId,
    );
  }

  List<ScriptPromptReplacementTerm> _frameReviewReplacementTerms({
    required int frameIndex,
    required String sourceLocation,
    required Iterable<StudioScriptReplacementSourceTermDraft> terms,
    String? scope,
    String? ownerId,
    String? sourceGroupId,
  }) {
    final result = <ScriptPromptReplacementTerm>[];
    final seenKeys = <String>{};
    for (final term in terms) {
      final text = term.text.trim();
      final key = PromptTagProcessor.normalizeMatchKey(text);
      if (text.isEmpty || key.isEmpty || !seenKeys.add(key)) {
        continue;
      }
      result.add(
        ScriptPromptReplacementTerm(
          id: stableIdFromText(
            prefix: 'frame-term',
            text: '$frameIndex|$sourceLocation|${term.category.name}|$text',
            label: text,
          ),
          text: text,
          category: term.category,
          sourceLocation: sourceLocation.trim(),
          frameIndexes: _expandedFrameIndexesForFrameReviewTerm(
            frameIndex: frameIndex,
            text: text,
            scope: scope,
            ownerId: ownerId,
            sourceGroupId: sourceGroupId,
            sourceLocation: sourceLocation,
          ),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  List<int> _expandedFrameIndexesForFrameReviewTerm({
    required int frameIndex,
    required String text,
    String? scope,
    String? ownerId,
    String? sourceGroupId,
    String? sourceLocation,
  }) {
    final script = _script;
    final key = _promptTagMatchKey(text);
    final frames = <int>{};
    if (script != null && key.isNotEmpty) {
      for (final frame in script.frames) {
        if (frame.parseStatus != ScriptFrameParseStatus.parsed) {
          continue;
        }
        if (_frameReviewSourceCaptionsForFrame(
          frame: frame,
          scope: scope,
          ownerId: ownerId,
          sourceGroupId: sourceGroupId,
          sourceLocation: sourceLocation,
        ).any((caption) => _captionHasPromptTag(caption, key))) {
          frames.add(frame.index);
        }
      }
    }
    if (frames.isEmpty && frameIndex > 0) {
      frames.add(frameIndex);
    }
    final sorted = frames.toList()..sort();
    return List.unmodifiable(sorted);
  }

  List<String> _frameReviewSourceCaptionsForFrame({
    required ScriptFrame frame,
    String? scope,
    String? ownerId,
    String? sourceGroupId,
    String? sourceLocation,
  }) {
    if (scope == 'role') {
      return _roleSourceCaptionsForFrame(
        frame: frame,
        ownerId: ownerId,
        sourceGroupId: sourceGroupId,
        sourceLocation: sourceLocation,
      );
    }
    if (scope == 'scene') {
      return [frame.parsed.baseCaption];
    }
    return [
      frame.parsed.baseCaption,
      ...frame.parsed.charCaptions,
    ];
  }

  List<String> _roleSourceCaptionsForFrame({
    required ScriptFrame frame,
    String? ownerId,
    String? sourceGroupId,
    String? sourceLocation,
  }) {
    final slotIndexes = _roleSourceSlotIndexes(
      ownerId: ownerId,
      sourceGroupId: sourceGroupId,
      sourceLocation: sourceLocation,
    );
    if (slotIndexes.isEmpty) {
      return frame.parsed.charCaptions;
    }
    return [
      for (final slotIndex in slotIndexes)
        if (slotIndex >= 0 && slotIndex < frame.parsed.charCaptions.length)
          frame.parsed.charCaptions[slotIndex],
    ];
  }

  Set<int> _roleSourceSlotIndexes({
    String? ownerId,
    String? sourceGroupId,
    String? sourceLocation,
  }) {
    final result = <int>{};
    void addFromRoleGroup(String? value) {
      final match = RegExp(r'^role-(\d+)$').firstMatch(value?.trim() ?? '');
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > 0) {
        result.add(number - 1);
      }
    }

    void addFromSlotId(String? value) {
      final match = RegExp(r'^slot-(\d+)$').firstMatch(value?.trim() ?? '');
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number >= 0) {
        result.add(number);
      }
    }

    void addFromLocation(String? value) {
      final match = RegExp(r'(?:角色|Role)\s*(\d+)', caseSensitive: false)
          .firstMatch(value?.trim() ?? '');
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > 0) {
        result.add(number - 1);
      }
    }

    addFromRoleGroup(sourceGroupId);
    addFromSlotId(ownerId);
    addFromLocation(sourceLocation);

    final mapping = _mapping;
    if (result.isEmpty && mapping != null && ownerId != null) {
      for (final assembly in mapping.roleAssemblies) {
        if (assembly.sourceRoleId != ownerId) {
          continue;
        }
        for (final appearance in assembly.sourceAppearances) {
          if (appearance.sourceKind == 'slot') {
            addFromSlotId(appearance.sourceId);
          }
        }
      }
    }
    return Set.unmodifiable(result);
  }

  bool _captionHasPromptTag(String caption, String targetKey) {
    if (targetKey.isEmpty) {
      return false;
    }
    for (final tag in PromptTagProcessor.splitWorkshopTags(caption)) {
      if (_promptTagMatchKey(tag) == targetKey) {
        return true;
      }
    }
    return false;
  }

  String _promptTagMatchKey(String tag) {
    return PromptTagProcessor.normalizeMatchKey(
      PromptTagProcessor.cleanTagDisplay(tag),
    );
  }

  _AddedFrameReviewRuleResult? _replacementRulesWithAddedFrameReviewRule({
    required List<ScriptPromptReplacementRule> rules,
    required String scope,
    required String ownerId,
    required List<ScriptPromptReplacementTerm> sourceTerms,
  }) {
    final keys = [
      for (final term in sourceTerms)
        PromptTagProcessor.normalizeMatchKey(term.text),
    ]..removeWhere((key) => key.isEmpty);
    if (keys.isEmpty) {
      return null;
    }
    final wantedKeys = keys.toSet();
    for (final rule in rules) {
      final ruleKeys = {
        for (final term in rule.sourceTerms)
          if (PromptTagProcessor.normalizeMatchKey(term.text).isNotEmpty)
            PromptTagProcessor.normalizeMatchKey(term.text),
      };
      if (ruleKeys.length == wantedKeys.length &&
          ruleKeys.containsAll(wantedKeys)) {
        return _AddedFrameReviewRuleResult(
          rules: rules,
          selectedRuleId: rule.id,
        );
      }
    }
    final existingIds = {for (final rule in rules) rule.id};
    final baseId = stableIdFromText(
      prefix: 'frame-rule',
      text: '$scope|$ownerId|${keys.join('|')}',
      label: sourceTerms.map((term) => term.text).join(' '),
    );
    var ruleId = baseId;
    var suffix = 2;
    while (existingIds.contains(ruleId)) {
      ruleId = '$baseId-$suffix';
      suffix += 1;
    }
    return _AddedFrameReviewRuleResult(
      rules: List.unmodifiable([
        ...rules,
        ScriptPromptReplacementRule(
          id: ruleId,
          sourceTerms: List.unmodifiable(sourceTerms),
          anchorTermId: sourceTerms.first.id,
        ),
      ]),
      selectedRuleId: ruleId,
    );
  }

  List<ScriptPromptReplacementTerm> _replacementTermsWithAdded(
    List<ScriptPromptReplacementTerm> current,
    List<ScriptPromptReplacementTerm> incoming,
  ) {
    final seenKeys = {
      for (final term in current)
        if (PromptTagProcessor.normalizeMatchKey(term.text).isNotEmpty)
          PromptTagProcessor.normalizeMatchKey(term.text),
    };
    return List.unmodifiable([
      ...current,
      for (final term in incoming)
        if (seenKeys.add(PromptTagProcessor.normalizeMatchKey(term.text))) term,
    ]);
  }

  void scaleRoleReplacementRuleWeight(
    String sourceRoleId,
    String ruleId,
    double multiplier,
  ) {
    if (!_isValidPromptWeightMultiplier(multiplier)) {
      return;
    }
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => _ruleWithWeightMultiplier(rule, multiplier),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void mergeRoleReplacementSourceTerms({
    required String sourceRoleId,
    required String sourceRuleId,
    required String targetRuleId,
    required Iterable<String> tags,
  }) {
    mergeRoleReplacementSourceTermsFromRules(
      sourceRoleId: sourceRoleId,
      sourceRuleIds: {sourceRuleId},
      targetRuleId: targetRuleId,
      tags: tags,
    );
  }

  void mergeRoleReplacementSourceTermsFromRules({
    required String sourceRoleId,
    required Iterable<String> sourceRuleIds,
    required String targetRuleId,
    required Iterable<String> tags,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final replacement = mapping.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (replacement == null) {
      return;
    }
    final involvedRuleIds = {
      ...sourceRuleIds,
      targetRuleId,
    };
    if (!_rulesShareReplacementLayer(
      replacement: replacement,
      ruleIds: involvedRuleIds,
    )) {
      return;
    }
    final nextRules = _replacementRulesWithMovedSourceTerms(
      rules: replacement.rules,
      sourceRuleIds: sourceRuleIds,
      targetRuleId: targetRuleId,
      tags: tags,
    );
    if (nextRules == null) {
      return;
    }
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) => replacement.copyWith(
        rules: List.unmodifiable(nextRules),
        layerOverrides: _layerOverridesRetainingRules(
          replacement.layerOverrides,
          {for (final rule in nextRules) rule.id},
        ),
      ),
    )) {
      return;
    }
    _selectedRoleReplacementRuleIdsByRole[sourceRoleId] = {targetRuleId};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void splitRoleReplacementSourceTerms({
    required String sourceRoleId,
    required String sourceRuleId,
    required Iterable<String> tags,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final replacement = mapping.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (replacement == null) {
      return;
    }
    final split = _replacementRulesWithSplitSourceTerms(
      rules: replacement.rules,
      sourceRuleId: sourceRuleId,
      tags: tags,
    );
    if (split == null) {
      return;
    }
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) => replacement.copyWith(
        rules: List.unmodifiable(split.rules),
        layerOverrides: _layerOverridesAfterRuleSplit(
          replacement.layerOverrides,
          sourceRuleId: sourceRuleId,
          newRuleId: split.newRuleId,
        ),
      ),
    )) {
      return;
    }
    _selectedRoleReplacementRuleIdsByRole[sourceRoleId] = {split.newRuleId};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void mergeRoleReplacementRules({
    required String sourceRoleId,
    required String sourceRuleId,
    required String targetRuleId,
  }) {
    final mapping = _mapping;
    if (mapping == null || sourceRuleId == targetRuleId) {
      return;
    }
    final replacement = mapping.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (replacement == null) {
      return;
    }
    if (!_rulesShareReplacementLayer(
      replacement: replacement,
      ruleIds: {sourceRuleId, targetRuleId},
    )) {
      return;
    }
    final nextRules = _replacementRulesWithMergedSourceRule(
      rules: replacement.rules,
      sourceRuleId: sourceRuleId,
      targetRuleId: targetRuleId,
    );
    if (nextRules == null) {
      return;
    }
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) => replacement.copyWith(
        rules: List.unmodifiable(nextRules),
        layerOverrides: _layerOverridesAfterRuleMerge(
          replacement.layerOverrides,
          mergedRuleIds: {sourceRuleId, targetRuleId},
          survivingRuleId: targetRuleId,
          survivingRuleIds: {for (final rule in nextRules) rule.id},
        ),
      ),
    )) {
      return;
    }
    _selectedRoleReplacementRuleIdsByRole[sourceRoleId] = {targetRuleId};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void setRoleReplacementRuleDeleted(
    String sourceRoleId,
    String ruleId,
    bool deleted,
  ) {
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => _ruleWithDeleted(rule, deleted),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void removeRoleReplacementRule(String sourceRoleId, String ruleId) {
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) {
        final nextRules = [
          for (final rule in replacement.rules)
            if (rule.id != ruleId) rule,
        ];
        if (nextRules.length == replacement.rules.length) {
          return replacement;
        }
        return replacement.copyWith(
          rules: List.unmodifiable(nextRules),
          layerOverrides: _layerOverridesRetainingRules(
            replacement.layerOverrides,
            {for (final rule in nextRules) rule.id},
          ),
        );
      },
    )) {
      return;
    }
    _removeReplacementSelection(
      _selectedRoleReplacementRuleIdsByRole,
      sourceRoleId,
      ruleId,
    );
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleReplacementRuleMatchMode(
    String sourceRoleId,
    String ruleId,
    ScriptPromptReplacementMatchMode mode,
  ) {
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => rule.copyWith(matchMode: mode),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleReplacementRuleTermExcluded(
    String sourceRoleId,
    String ruleId,
    String termId,
    bool excluded,
  ) {
    if (!_updateRoleReplacementRule(
      sourceRoleId: sourceRoleId,
      ruleId: ruleId,
      update: (rule) => rule.copyWith(
        excludedTermIds: _replacementExcludedTermIds(
          rule.excludedTermIds,
          termId,
          excluded,
        ),
      ),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setRoleReplacementRuleSelected(
    String sourceRoleId,
    String ruleId,
    bool selected,
  ) {
    _setReplacementSelection(
      _selectedRoleReplacementRuleIdsByRole,
      sourceRoleId,
      ruleId,
      selected,
    );
    _refreshReplacementMappings();
    notifyListeners();
  }

  void clearRoleReplacementRuleSelection(String sourceRoleId) {
    final removed = _selectedRoleReplacementRuleIdsByRole.remove(sourceRoleId);
    if (removed == null || removed.isEmpty) {
      return;
    }
    _refreshReplacementMappings();
    notifyListeners();
  }

  void assignRoleReplacementRulesToLayer({
    required String sourceRoleId,
    required Iterable<String> ruleIds,
    required ScriptRoleReplacementRuleLayerKind kind,
    String stageId = '',
  }) {
    final normalizedRuleIds = {
      for (final ruleId in ruleIds)
        if (ruleId.trim().isNotEmpty) ruleId.trim(),
    };
    if (normalizedRuleIds.isEmpty) {
      return;
    }
    if (kind == ScriptRoleReplacementRuleLayerKind.stage &&
        !_roleHasStage(sourceRoleId, stageId)) {
      return;
    }
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) {
        final existingRuleIds = {
          for (final rule in replacement.rules) rule.id,
        };
        final applicableRuleIds =
            normalizedRuleIds.intersection(existingRuleIds);
        if (applicableRuleIds.isEmpty) {
          return replacement;
        }
        return replacement.copyWith(
          layerOverrides: _layerOverridesWithAssignment(
            replacement.layerOverrides,
            ruleIds: applicableRuleIds,
            kind: kind,
            stageId: stageId,
          ),
        );
      },
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void assignRoleReplacementRulesToCategory({
    required String sourceRoleId,
    required Iterable<String> ruleIds,
    required PromptTagCategory category,
  }) {
    final normalizedRuleIds = {
      for (final ruleId in ruleIds)
        if (ruleId.trim().isNotEmpty) ruleId.trim(),
    };
    if (normalizedRuleIds.isEmpty ||
        !_updateRoleReplacement(
          sourceRoleId,
          (replacement) {
            final nextRules = _replacementRulesAssignedToCategory(
              replacement.rules,
              ruleIds: normalizedRuleIds,
              category: category,
            );
            return identical(nextRules, replacement.rules)
                ? replacement
                : replacement.copyWith(rules: nextRules);
          },
          learnProfile: false,
        )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void assignRoleReplacementSourceTermsToCategory({
    required String sourceRoleId,
    required Iterable<String> sourceRuleIds,
    required Iterable<String> tags,
    required PromptTagCategory category,
  }) {
    final normalizedRuleIds = {
      for (final ruleId in sourceRuleIds)
        if (ruleId.trim().isNotEmpty) ruleId.trim(),
    };
    final wantedKeys = {
      for (final tag in tags) PromptTagProcessor.normalizeMatchKey(tag),
    }..removeWhere((key) => key.isEmpty);
    if (normalizedRuleIds.isEmpty || wantedKeys.isEmpty) {
      return;
    }
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) {
        var replacementChanged = false;
        final nextRules = [
          for (final rule in replacement.rules)
            if (normalizedRuleIds.contains(rule.id))
              () {
                var ruleChanged = false;
                final nextTerms = [
                  for (final term in rule.sourceTerms)
                    if (wantedKeys.contains(
                          PromptTagProcessor.normalizeMatchKey(term.text),
                        ) &&
                        term.category != category)
                      _markChanged(
                        term.copyWith(category: category),
                        () {
                          ruleChanged = true;
                          replacementChanged = true;
                        },
                      )
                    else
                      term,
                ];
                return ruleChanged
                    ? rule.copyWith(sourceTerms: List.unmodifiable(nextTerms))
                    : rule;
              }()
            else
              rule,
        ];
        return replacementChanged
            ? replacement.copyWith(rules: List.unmodifiable(nextRules))
            : replacement;
      },
      learnProfile: false,
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void assignSelectedRoleReplacementRulesToLayer({
    required String sourceRoleId,
    required ScriptRoleReplacementRuleLayerKind kind,
    String stageId = '',
  }) {
    assignRoleReplacementRulesToLayer(
      sourceRoleId: sourceRoleId,
      ruleIds: _selectedRoleReplacementRuleIdsByRole[sourceRoleId] ?? const {},
      kind: kind,
      stageId: stageId,
    );
  }

  void restoreAutomaticRoleReplacementLayer({
    required String sourceRoleId,
    required Iterable<String> ruleIds,
  }) {
    final normalizedRuleIds = ruleIds.toSet();
    if (normalizedRuleIds.isEmpty ||
        !_updateRoleReplacement(
          sourceRoleId,
          (replacement) {
            final nextOverrides = [
              for (final override in replacement.layerOverrides)
                if (!normalizedRuleIds.contains(override.ruleId)) override,
            ];
            return nextOverrides.length == replacement.layerOverrides.length
                ? replacement
                : replacement.copyWith(
                    layerOverrides: List.unmodifiable(nextOverrides),
                  );
          },
        )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void restoreAllAutomaticRoleReplacementLayers(String sourceRoleId) {
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) => replacement.layerOverrides.isEmpty
          ? replacement
          : replacement.copyWith(layerOverrides: const []),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void mergeSelectedRoleReplacementRules(String sourceRoleId) {
    final selectedIds = _selectedRoleReplacementRuleIdsByRole[sourceRoleId];
    if (selectedIds == null || selectedIds.length < 2) {
      return;
    }
    String? keptRuleId;
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) {
        final selectedRules = [
          for (final rule in replacement.rules)
            if (selectedIds.contains(rule.id)) rule,
        ];
        if (selectedRules.length < 2) {
          return replacement;
        }
        if (!_rulesShareReplacementLayer(
          replacement: replacement,
          ruleIds: selectedIds,
        )) {
          return replacement;
        }
        keptRuleId = selectedRules.first.id;
        final nextRules = _mergedReplacementRules(
          rules: replacement.rules,
          selectedIds: selectedIds,
        );
        return replacement.copyWith(
          rules: nextRules,
          layerOverrides: _layerOverridesAfterRuleMerge(
            replacement.layerOverrides,
            mergedRuleIds: selectedIds,
            survivingRuleId: keptRuleId!,
            survivingRuleIds: {for (final rule in nextRules) rule.id},
          ),
        );
      },
    )) {
      return;
    }
    if (keptRuleId == null) {
      return;
    }
    _selectedRoleReplacementRuleIdsByRole[sourceRoleId] = {keptRuleId!};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void syncRoleReplacementTargetToSelectedRules(String sourceRoleId) {
    final selectedIds = _selectedRoleReplacementRuleIdsByRole[sourceRoleId];
    if (selectedIds == null || selectedIds.isEmpty) {
      return;
    }
    final targetIdentityPrompt = _mapping?.rolePromptReplacements
            .where((replacement) => replacement.sourceRoleId == sourceRoleId)
            .firstOrNull
            ?.targetIdentityPrompt ??
        '';
    if (targetIdentityPrompt.trim().isEmpty) {
      return;
    }
    if (!_updateRoleReplacement(
      sourceRoleId,
      (replacement) => replacement.copyWith(
        rules: [
          for (final rule in replacement.rules)
            if (selectedIds.contains(rule.id))
              rule.copyWith(
                targetPrompt: targetIdentityPrompt,
                targetWeightMultiplier: null,
                action: ScriptPromptReplacementAction.replace,
              )
            else
              rule,
        ],
      ),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void resetRoleReplacementGroup(String sourceRoleId) {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      return;
    }
    final strippedMapping = mapping.copyWith(
      rolePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.rolePromptReplacements)
          if (replacement.sourceRoleId != sourceRoleId) replacement,
      ]),
    );
    final resetApplication = _mappingWithAppliedAiRoleExtraction(
      script: script,
      mapping: strippedMapping,
      extraction: aiRoleExtraction,
    );
    final resetReplacement = resetApplication.mapping.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final nextReplacements = _rolePromptReplacementsWithResetGroup(
      current: mapping.rolePromptReplacements,
      sourceRoleId: sourceRoleId,
      resetReplacement: resetReplacement,
    );
    if (identical(nextReplacements, mapping.rolePromptReplacements)) {
      return;
    }
    _mapping = mapping.copyWith(rolePromptReplacements: nextReplacements);
    _selectedRoleReplacementRuleIdsByRole.remove(sourceRoleId);
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void setSceneReplacementRuleTarget(
    String groupId,
    String ruleId,
    String value,
  ) {
    if (!_updateSceneReplacementRule(
      groupId: groupId,
      ruleId: ruleId,
      update: (rule) => _ruleWithTarget(rule, value),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setSceneReplacementRuleSource(
    String groupId,
    String ruleId,
    String value,
  ) {
    if (!_updateSceneReplacementRule(
      groupId: groupId,
      ruleId: ruleId,
      update: (rule) => _ruleWithSourcePrompt(rule, value),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void scaleSceneReplacementRuleWeight(
    String groupId,
    String ruleId,
    double multiplier,
  ) {
    if (!_isValidPromptWeightMultiplier(multiplier)) {
      return;
    }
    if (!_updateSceneReplacementRule(
      groupId: groupId,
      ruleId: ruleId,
      update: (rule) => _ruleWithWeightMultiplier(rule, multiplier),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setSceneReplacementRuleDeleted(
    String groupId,
    String ruleId,
    bool deleted,
  ) {
    if (!_updateSceneReplacementRule(
      groupId: groupId,
      ruleId: ruleId,
      update: (rule) => _ruleWithDeleted(rule, deleted),
    )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setSceneReplacementRuleSelected(
    String groupId,
    String ruleId,
    bool selected,
  ) {
    _setReplacementSelection(
      _selectedSceneReplacementRuleIdsByGroup,
      groupId,
      ruleId,
      selected,
    );
    _refreshReplacementMappings();
    notifyListeners();
  }

  void clearSceneReplacementRuleSelection(String groupId) {
    final removed = _selectedSceneReplacementRuleIdsByGroup.remove(groupId);
    if (removed == null || removed.isEmpty) {
      return;
    }
    _refreshReplacementMappings();
    notifyListeners();
  }

  void assignSceneReplacementRulesToCategory({
    required String groupId,
    required Iterable<String> ruleIds,
    required PromptTagCategory category,
  }) {
    final normalizedRuleIds = {
      for (final ruleId in ruleIds)
        if (ruleId.trim().isNotEmpty) ruleId.trim(),
    };
    if (normalizedRuleIds.isEmpty ||
        !_updateSceneReplacement(
          groupId,
          (replacement) {
            final nextRules = _replacementRulesAssignedToCategory(
              replacement.rules,
              ruleIds: normalizedRuleIds,
              category: category,
            );
            return identical(nextRules, replacement.rules)
                ? replacement
                : replacement.copyWith(rules: nextRules);
          },
        )) {
      return;
    }
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void mergeSelectedSceneReplacementRules(String groupId) {
    final selectedIds = _selectedSceneReplacementRuleIdsByGroup[groupId];
    if (selectedIds == null || selectedIds.length < 2) {
      return;
    }
    String? keptRuleId;
    if (!_updateSceneReplacement(
      groupId,
      (replacement) {
        final selectedRules = [
          for (final rule in replacement.rules)
            if (selectedIds.contains(rule.id)) rule,
        ];
        if (selectedRules.length < 2) {
          return replacement;
        }
        keptRuleId = selectedRules.first.id;
        return replacement.copyWith(
          rules: _mergedReplacementRules(
            rules: replacement.rules,
            selectedIds: selectedIds,
          ),
        );
      },
    )) {
      return;
    }
    if (keptRuleId == null) {
      return;
    }
    _selectedSceneReplacementRuleIdsByGroup[groupId] = {keptRuleId!};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void mergeSceneReplacementRules({
    required String groupId,
    required String sourceRuleId,
    required String targetRuleId,
  }) {
    final mapping = _mapping;
    if (mapping == null || sourceRuleId == targetRuleId) {
      return;
    }
    final replacement = mapping.scenePromptReplacements
        .where((replacement) => replacement.id == groupId)
        .firstOrNull;
    if (replacement == null) {
      return;
    }
    final nextRules = _replacementRulesWithMergedSourceRule(
      rules: replacement.rules,
      sourceRuleId: sourceRuleId,
      targetRuleId: targetRuleId,
    );
    if (nextRules == null) {
      return;
    }
    if (!_updateSceneReplacement(
      groupId,
      (replacement) => replacement.copyWith(
        rules: List.unmodifiable(nextRules),
      ),
    )) {
      return;
    }
    _selectedSceneReplacementRuleIdsByGroup[groupId] = {targetRuleId};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void removeSceneReplacementRule(String groupId, String ruleId) {
    if (!_updateSceneReplacement(
      groupId,
      (replacement) {
        final nextRules = [
          for (final rule in replacement.rules)
            if (rule.id != ruleId) rule,
        ];
        if (nextRules.length == replacement.rules.length) {
          return replacement;
        }
        return replacement.copyWith(rules: List.unmodifiable(nextRules));
      },
    )) {
      return;
    }
    _removeReplacementSelection(
      _selectedSceneReplacementRuleIdsByGroup,
      groupId,
      ruleId,
    );
    _refreshReplacementEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void resetSceneReplacementGroup(String groupId) {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      return;
    }
    final strippedMapping = mapping.copyWith(
      scenePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.scenePromptReplacements)
          if (replacement.id != groupId) replacement,
      ]),
    );
    final resetApplication = _mappingWithAppliedAiRoleExtraction(
      script: script,
      mapping: strippedMapping,
      extraction: aiRoleExtraction,
    );
    final resetReplacement = resetApplication.mapping.scenePromptReplacements
        .where((replacement) => replacement.id == groupId)
        .firstOrNull;
    final nextReplacements = _scenePromptReplacementsWithResetGroup(
      current: mapping.scenePromptReplacements,
      groupId: groupId,
      resetReplacement: resetReplacement,
    );
    if (identical(nextReplacements, mapping.scenePromptReplacements)) {
      return;
    }
    _mapping = mapping.copyWith(scenePromptReplacements: nextReplacements);
    _selectedSceneReplacementRuleIdsByGroup.remove(groupId);
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void mergeSceneReplacementSourceTerms({
    required String groupId,
    required String sourceRuleId,
    required String targetRuleId,
    required Iterable<String> tags,
  }) {
    mergeSceneReplacementSourceTermsFromRules(
      groupId: groupId,
      sourceRuleIds: {sourceRuleId},
      targetRuleId: targetRuleId,
      tags: tags,
    );
  }

  void mergeSceneReplacementSourceTermsFromRules({
    required String groupId,
    required Iterable<String> sourceRuleIds,
    required String targetRuleId,
    required Iterable<String> tags,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final replacement = mapping.scenePromptReplacements
        .where((replacement) => replacement.id == groupId)
        .firstOrNull;
    if (replacement == null) {
      return;
    }
    final nextRules = _replacementRulesWithMovedSourceTerms(
      rules: replacement.rules,
      sourceRuleIds: sourceRuleIds,
      targetRuleId: targetRuleId,
      tags: tags,
    );
    if (nextRules == null) {
      return;
    }
    if (!_updateSceneReplacement(
      groupId,
      (replacement) => replacement.copyWith(
        rules: List.unmodifiable(nextRules),
      ),
    )) {
      return;
    }
    _selectedSceneReplacementRuleIdsByGroup[groupId] = {targetRuleId};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  void splitSceneReplacementSourceTerms({
    required String groupId,
    required String sourceRuleId,
    required Iterable<String> tags,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final replacement = mapping.scenePromptReplacements
        .where((replacement) => replacement.id == groupId)
        .firstOrNull;
    if (replacement == null) {
      return;
    }
    final split = _replacementRulesWithSplitSourceTerms(
      rules: replacement.rules,
      sourceRuleId: sourceRuleId,
      tags: tags,
    );
    if (split == null) {
      return;
    }
    if (!_updateSceneReplacement(
      groupId,
      (replacement) => replacement.copyWith(
        rules: List.unmodifiable(split.rules),
      ),
    )) {
      return;
    }
    _selectedSceneReplacementRuleIdsByGroup[groupId] = {split.newRuleId};
    _refreshReplacementEditPreview();
    notifyListeners();
    unawaited(_saveCurrentCache());
  }

  ScriptPromptReplacementRule _ruleWithTarget(
    ScriptPromptReplacementRule rule,
    String value,
  ) {
    final targetPrompt = value.trim().isEmpty ? '' : value;
    final action = targetPrompt.trim().isNotEmpty
        ? ScriptPromptReplacementAction.replace
        : rule.action == ScriptPromptReplacementAction.delete
            ? ScriptPromptReplacementAction.delete
            : ScriptPromptReplacementAction.none;
    return rule.copyWith(
      targetPrompt: targetPrompt,
      targetWeightMultiplier:
          targetPrompt.trim().isEmpty ? null : rule.targetWeightMultiplier,
      action: action,
    );
  }

  ScriptPromptReplacementRule _ruleWithSourcePrompt(
    ScriptPromptReplacementRule rule,
    String value,
  ) {
    final editedTags = PromptTagProcessor.splitWorkshopTags(value)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final editableTerms = rule.sourceTerms
        .where((term) => term.text.trim().isNotEmpty)
        .toList(growable: false);
    if (editedTags.length != editableTerms.length) {
      return rule;
    }
    var editedIndex = 0;
    return rule.copyWith(
      sourceTerms: List.unmodifiable([
        for (final term in rule.sourceTerms)
          if (term.text.trim().isEmpty)
            term
          else
            term.copyWith(text: editedTags[editedIndex++]),
      ]),
    );
  }

  List<ScriptRolePromptReplacement> _rolePromptReplacementsWithResetGroup({
    required List<ScriptRolePromptReplacement> current,
    required String sourceRoleId,
    required ScriptRolePromptReplacement? resetReplacement,
  }) {
    final currentReplacement = current
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final replacementWithPreservedLayers =
        resetReplacement == null || currentReplacement == null
            ? resetReplacement
            : resetReplacement.copyWith(
                layerOverrides: _layerOverridesRetainingRules(
                  currentReplacement.layerOverrides,
                  {for (final rule in resetReplacement.rules) rule.id},
                ),
              );
    final next = <ScriptRolePromptReplacement>[];
    var removedExisting = false;
    var insertedReset = false;
    for (final replacement in current) {
      if (replacement.sourceRoleId == sourceRoleId) {
        removedExisting = true;
        if (!insertedReset && replacementWithPreservedLayers != null) {
          next.add(replacementWithPreservedLayers);
          insertedReset = true;
        }
        continue;
      }
      next.add(replacement);
    }
    if (!insertedReset && replacementWithPreservedLayers != null) {
      next.add(replacementWithPreservedLayers);
      insertedReset = true;
    }
    if (!removedExisting && !insertedReset) {
      return current;
    }
    return List.unmodifiable(next);
  }

  List<ScriptScenePromptReplacement> _scenePromptReplacementsWithResetGroup({
    required List<ScriptScenePromptReplacement> current,
    required String groupId,
    required ScriptScenePromptReplacement? resetReplacement,
  }) {
    final next = <ScriptScenePromptReplacement>[];
    var removedExisting = false;
    var insertedReset = false;
    for (final replacement in current) {
      if (replacement.id == groupId) {
        removedExisting = true;
        if (!insertedReset && resetReplacement != null) {
          next.add(resetReplacement);
          insertedReset = true;
        }
        continue;
      }
      next.add(replacement);
    }
    if (!insertedReset && resetReplacement != null) {
      next.add(resetReplacement);
      insertedReset = true;
    }
    if (!removedExisting && !insertedReset) {
      return current;
    }
    return List.unmodifiable(next);
  }

  ScriptPromptReplacementRule _ruleWithWeightMultiplier(
    ScriptPromptReplacementRule rule,
    double multiplier,
  ) {
    if (rule.action == ScriptPromptReplacementAction.delete) {
      return rule;
    }
    return rule.copyWith(
      targetWeightMultiplier: _targetWeightMultiplierOrNull(multiplier),
    );
  }

  bool _isValidPromptWeightMultiplier(double multiplier) {
    return multiplier.isFinite && multiplier > 0;
  }

  double? _targetWeightMultiplierOrNull(double multiplier) {
    if ((multiplier - 1.0).abs() < 0.000001) {
      return null;
    }
    return multiplier;
  }

  ScriptPromptReplacementRule _ruleWithDeleted(
    ScriptPromptReplacementRule rule,
    bool deleted,
  ) {
    if (deleted) {
      return rule.copyWith(action: ScriptPromptReplacementAction.delete);
    }
    final hasReplacement = rule.targetPrompt.trim().isNotEmpty;
    return rule.copyWith(
      action: hasReplacement
          ? ScriptPromptReplacementAction.replace
          : ScriptPromptReplacementAction.none,
    );
  }

  RoleMappingProfileRepository _requireRoleMappingProfileRepository() {
    final repository = roleMappingProfileRepository;
    if (repository == null) {
      throw StateError('全局角色档案仓库未配置。');
    }
    return repository;
  }

  ScriptRolePromptReplacement? _roleReplacementById(String sourceRoleId) {
    return _mapping?.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
  }

  RoleAssembly? _roleAssemblyById(String sourceRoleId) {
    return _mapping?.roleAssemblies
        .where((assembly) => assembly.sourceRoleId == sourceRoleId)
        .firstOrNull;
  }

  ScriptRolePromptReplacement _requireRoleReplacement(String sourceRoleId) {
    final replacement = _roleReplacementById(sourceRoleId);
    if (replacement == null) {
      throw StateError('当前角色替换组已不存在：$sourceRoleId');
    }
    return replacement;
  }

  void _setRoleMappingProfileLibrary(RoleMappingProfileLibrary library) {
    roleMappingProfiles = List.unmodifiable(
      library.profiles.toList()
        ..sort((left, right) {
          final byUpdated = right.updatedAt.compareTo(left.updatedAt);
          return byUpdated != 0
              ? byUpdated
              : left.name.toLowerCase().compareTo(right.name.toLowerCase());
        }),
    );
  }

  RoleMappingProfile _profileForRoleMappingApplication(
    RoleMappingProfile profile,
  ) {
    final targetCharacterId = profile.targetCharacterId;
    if (targetCharacterId == null || targetCharacterId.trim().isEmpty) {
      return profile;
    }
    final targetCharacter = _characterById(targetCharacterId);
    if (targetCharacter == null) {
      return profile;
    }
    final reconciled = roleMappingProfileService.reconcileTargetCharacter(
      profile: profile,
      targetCharacter: targetCharacter,
      characterCatalog: _characters,
      fallbackIdentityPrompt: _roleReplacementCandidatePrompt(targetCharacter),
    );
    return reconciled.copyWith(
      targetCharacterNameSnapshot: targetCharacter.name,
    );
  }

  RoleMappingProfile _normalizedRoleMappingProfile(
    RoleMappingProfile profile,
  ) {
    final name = profile.name.trim();
    if (name.isEmpty) {
      throw const FormatException('全局角色档案名称不能为空。');
    }
    RoleMappingProfileBlock normalizeBlock(RoleMappingProfileBlock block) {
      return block.copyWith(
        terms: List.unmodifiable([
          for (final term in block.terms)
            if (term.text.trim().isNotEmpty)
              term.copyWith(
                text: term.text.trim(),
                normalizedKey: normalizeRoleMappingProfileTerm(term.text),
              ),
        ]),
        anchorTermKey: normalizeRoleMappingProfileTerm(block.anchorTermKey),
        targetPrompt: block.targetPrompt.trim(),
      );
    }

    final layers = [
      for (final layer in profile.effectiveLayers)
        () {
          final blocks = [
            for (final block in layer.blocks) normalizeBlock(block),
          ];
          final signature = <String>{
            for (final block in blocks)
              for (final term in block.terms)
                if (term.autoDetect && term.normalizedKey.isNotEmpty)
                  term.normalizedKey,
          }.toList()
            ..sort();
          return layer.copyWith(
            displayName: layer.displayName.trim().isEmpty
                ? '未命名分层'
                : layer.displayName.trim(),
            recognitionSignature: List.unmodifiable(signature),
            blocks: List.unmodifiable(blocks),
          );
        }(),
    ];
    final blocks = [
      for (final layer in layers) ...layer.blocks,
    ];
    for (final block in blocks) {
      if (block.terms.isEmpty) {
        throw const FormatException('映射组至少需要一个源标签。');
      }
      if (block.matchMode == ScriptPromptReplacementMatchMode.anchor &&
          !block.normalizedTermKeys.contains(block.anchorTermKey)) {
        throw const FormatException('锚点必须来自当前映射组的源标签。');
      }
    }
    final normalized = profile.copyWith(
      name: name,
      targetCharacterNameSnapshot: profile.targetCharacterNameSnapshot.trim(),
      targetIdentityPrompt: profile.targetIdentityPrompt.trim(),
      layers: List.unmodifiable(layers),
    );
    return RoleMappingProfile.fromJson(normalized.toJson());
  }

  String _uniqueRoleMappingProfileCopyName(
    String sourceName,
    Iterable<RoleMappingProfile> profiles,
  ) {
    final names = {
      for (final profile in profiles) profile.name.trim().toLowerCase(),
    };
    final base = '${sourceName.trim()} 副本';
    if (!names.contains(base.toLowerCase())) return base;
    for (var index = 2;; index += 1) {
      final candidate = '$base $index';
      if (!names.contains(candidate.toLowerCase())) return candidate;
    }
  }

  bool _setRoleReplacementActiveProfile(
    String sourceRoleId,
    String? profileId,
  ) {
    final mapping = _mapping;
    if (mapping == null) return false;
    final normalizedProfileId = profileId?.trim();
    final shouldLink = normalizedProfileId?.isNotEmpty ?? false;
    if (!mapping.rolePromptReplacements.any(
      (replacement) => replacement.sourceRoleId == sourceRoleId,
    )) {
      return false;
    }
    var changed = false;
    final replacements = [
      for (final replacement in mapping.rolePromptReplacements)
        if (replacement.sourceRoleId == sourceRoleId)
          _markChanged(
            replacement.copyWith(
              activeMappingProfileId: shouldLink ? normalizedProfileId : null,
            ),
            () => changed = true,
          )
        else if (shouldLink &&
            replacement.activeMappingProfileId?.trim() == normalizedProfileId)
          // A profile is a mutable global record. Within one script it may be
          // linked to the current role only; otherwise editing that role
          // silently edits every other role sharing the same profile.
          _markChanged(
            replacement.copyWith(activeMappingProfileId: null),
            () => changed = true,
          )
        else
          replacement,
    ];
    if (changed) {
      _mapping = mapping.copyWith(
        rolePromptReplacements: List.unmodifiable(replacements),
      );
    }
    if (changed) {
      _refreshReplacementMappings();
    }
    return changed;
  }

  void _detachRoleMappingProfile(String profileId) {
    final mapping = _mapping;
    if (mapping == null) return;
    var changed = false;
    final replacements = [
      for (final replacement in mapping.rolePromptReplacements)
        if (replacement.activeMappingProfileId == profileId)
          _markChanged(
            replacement.copyWith(activeMappingProfileId: null),
            () => changed = true,
          )
        else
          replacement,
    ];
    if (!changed) return;
    _mapping = mapping.copyWith(
      rolePromptReplacements: List.unmodifiable(replacements),
    );
    _refreshReplacementMappings();
  }

  RecastMapping _withoutRoleMappingProfileLinks(RecastMapping mapping) {
    return mapping.copyWith(
      rolePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.rolePromptReplacements)
          replacement.copyWith(activeMappingProfileId: null),
      ]),
    );
  }

  RecastMapping _withRoleScopedMappingProfileLinks(RecastMapping mapping) {
    final linkedProfileIds = <String>{};
    var changed = false;
    final replacements = [
      for (final replacement in mapping.rolePromptReplacements)
        () {
          final profileId = replacement.activeMappingProfileId?.trim();
          if (profileId == null || profileId.isEmpty) {
            if (replacement.activeMappingProfileId == null) {
              return replacement;
            }
            changed = true;
            return replacement.copyWith(activeMappingProfileId: null);
          }
          if (linkedProfileIds.add(profileId)) {
            return replacement;
          }
          // Keep the visible target/rules, but turn a duplicate link into a
          // one-time local copy. This repairs caches written by the old
          // whole-script sync path without guessing which role's mapping to
          // overwrite.
          changed = true;
          return replacement.copyWith(activeMappingProfileId: null);
        }(),
    ];
    return changed
        ? mapping.copyWith(
            rolePromptReplacements: List.unmodifiable(replacements))
        : mapping;
  }

  Future<void> _learnActiveRoleMappingProfile(
    ScriptRolePromptReplacement before,
    ScriptRolePromptReplacement after, {
    RoleAssembly? beforeAssembly,
    RoleAssembly? afterAssembly,
  }) async {
    final profileId =
        after.activeMappingProfileId ?? before.activeMappingProfileId;
    final repository = roleMappingProfileRepository;
    if (profileId == null || repository == null || _disposed) return;
    try {
      final library = await repository.update((current) {
        final profile = current.profiles
            .where((entry) => entry.id == profileId)
            .firstOrNull;
        if (profile == null) return current;
        final prompts = roleMappingProfileService.deletionPrompts(
          profile: profile,
          before: before,
          after: after,
          beforeAssembly:
              beforeAssembly ?? _roleAssemblyById(before.sourceRoleId),
          afterAssembly: afterAssembly ?? _roleAssemblyById(after.sourceRoleId),
        );
        for (final prompt in prompts) {
          final duplicate = _pendingRoleMappingProfileDeletions.any(
            (entry) =>
                entry.profileId == prompt.profileId &&
                entry.kind == prompt.kind &&
                entry.blockId == prompt.blockId,
          );
          if (!duplicate) {
            _pendingRoleMappingProfileDeletions.add(prompt);
          }
        }
        final characterName = after.targetCharacterId == null
            ? ''
            : _characterById(after.targetCharacterId!)?.name ?? '';
        final learned = roleMappingProfileService.learnReplacement(
          profile: profile,
          before: before,
          after: after,
          targetCharacterNameSnapshot: characterName,
          now: DateTime.now().toUtc(),
          assembly: afterAssembly ?? _roleAssemblyById(after.sourceRoleId),
        );
        return current.copyWith(
          profiles: List.unmodifiable([
            for (final entry in current.profiles)
              if (entry.id == learned.id) learned else entry,
          ]),
        );
      });
      if (_disposed) return;
      _setRoleMappingProfileLibrary(library);
      final profile = roleMappingProfileById(profileId);
      if (profile != null) {
        roleMappingProfileStatus = '已自动更新：${profile.name}';
      }
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      roleMappingProfileError = error;
      roleMappingProfileStatus = '自动更新全局角色档案失败';
      notifyListeners();
    }
  }

  bool _updateRoleReplacement(
    String sourceRoleId,
    ScriptRolePromptReplacement Function(ScriptRolePromptReplacement) update, {
    bool learnProfile = true,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return false;
    }
    var changed = false;
    ScriptRolePromptReplacement? before;
    ScriptRolePromptReplacement? after;
    final next = [
      for (final replacement in mapping.rolePromptReplacements)
        if (replacement.sourceRoleId == sourceRoleId)
          _markChanged(
            after = _normalizedRoleReplacement(
              update(before = replacement),
            ),
            () => changed = true,
          )
        else
          replacement,
    ];
    if (!changed) {
      return false;
    }
    _mapping =
        mapping.copyWith(rolePromptReplacements: List.unmodifiable(next));
    if (learnProfile && before != null && after != null) {
      unawaited(_learnActiveRoleMappingProfile(before, after));
    }
    return true;
  }

  bool _updateRoleReplacementRule({
    required String sourceRoleId,
    required String ruleId,
    required ScriptPromptReplacementRule Function(ScriptPromptReplacementRule)
        update,
  }) {
    return _updateRoleReplacement(
      sourceRoleId,
      (replacement) {
        var changed = false;
        final nextRules = [
          for (final rule in replacement.rules)
            if (rule.id == ruleId)
              _markChanged(update(rule), () => changed = true)
            else
              rule,
        ];
        return changed
            ? replacement.copyWith(rules: List.unmodifiable(nextRules))
            : replacement;
      },
    );
  }

  bool _updateSceneReplacement(
    String groupId,
    ScriptScenePromptReplacement Function(ScriptScenePromptReplacement) update,
  ) {
    final mapping = _mapping;
    if (mapping == null) {
      return false;
    }
    var changed = false;
    final next = [
      for (final replacement in mapping.scenePromptReplacements)
        if (replacement.id == groupId)
          _markChanged(update(replacement), () => changed = true)
        else
          replacement,
    ];
    if (!changed) {
      return false;
    }
    _mapping =
        mapping.copyWith(scenePromptReplacements: List.unmodifiable(next));
    return true;
  }

  bool _updateSceneReplacementRule({
    required String groupId,
    required String ruleId,
    required ScriptPromptReplacementRule Function(ScriptPromptReplacementRule)
        update,
  }) {
    return _updateSceneReplacement(
      groupId,
      (replacement) {
        var changed = false;
        final nextRules = [
          for (final rule in replacement.rules)
            if (rule.id == ruleId)
              _markChanged(update(rule), () => changed = true)
            else
              rule,
        ];
        return changed
            ? replacement.copyWith(rules: List.unmodifiable(nextRules))
            : replacement;
      },
    );
  }

  T _markChanged<T>(T value, VoidCallback markChanged) {
    markChanged();
    return value;
  }

  List<ScriptPromptReplacementRule> _replacementRulesAssignedToCategory(
    List<ScriptPromptReplacementRule> rules, {
    required Set<String> ruleIds,
    required PromptTagCategory category,
  }) {
    var changed = false;
    final next = [
      for (final rule in rules)
        if (ruleIds.contains(rule.id) &&
            rule.sourceTerms.any((term) => term.category != category))
          _markChanged(
            rule.copyWith(
              sourceTerms: List.unmodifiable([
                for (final term in rule.sourceTerms)
                  term.copyWith(category: category),
              ]),
            ),
            () => changed = true,
          )
        else
          rule,
    ];
    return changed ? List.unmodifiable(next) : rules;
  }

  List<String> _replacementExcludedTermIds(
    List<String> current,
    String termId,
    bool excluded,
  ) {
    if (termId.trim().isEmpty) {
      return current;
    }
    if (!excluded) {
      return [
        for (final id in current)
          if (id != termId) id,
      ];
    }
    if (current.contains(termId)) {
      return current;
    }
    return [...current, termId];
  }

  void _setReplacementSelection(
    Map<String, Set<String>> selectedByGroup,
    String groupId,
    String ruleId,
    bool selected,
  ) {
    final next = {...?selectedByGroup[groupId]};
    if (selected) {
      next.add(ruleId);
    } else {
      next.remove(ruleId);
    }
    if (next.isEmpty) {
      selectedByGroup.remove(groupId);
    } else {
      selectedByGroup[groupId] = next;
    }
  }

  void _removeReplacementSelection(
    Map<String, Set<String>> selectedByGroup,
    String groupId,
    String ruleId,
  ) {
    final next = {...?selectedByGroup[groupId]}..remove(ruleId);
    if (next.isEmpty) {
      selectedByGroup.remove(groupId);
    } else {
      selectedByGroup[groupId] = next;
    }
  }

  bool _roleHasStage(String sourceRoleId, String stageId) {
    if (stageId.trim().isEmpty) {
      return false;
    }
    return _mapping?.roleAssemblies.any(
          (assembly) =>
              assembly.sourceRoleId == sourceRoleId &&
              assembly.stages.any((stage) => stage.id == stageId),
        ) ??
        false;
  }

  bool _rulesShareReplacementLayer({
    required ScriptRolePromptReplacement replacement,
    required Iterable<String> ruleIds,
  }) {
    final existingRuleIds = {for (final rule in replacement.rules) rule.id};
    final normalizedRuleIds = ruleIds.toSet().intersection(existingRuleIds);
    if (normalizedRuleIds.length < 2) {
      return false;
    }
    final assembly = _mapping?.roleAssemblies
        .where(
          (assembly) => assembly.sourceRoleId == replacement.sourceRoleId,
        )
        .firstOrNull;
    final result = roleReplacementLayerService.resolve(
      replacement: replacement,
      assembly: assembly,
    );
    final layerIds = {
      for (final ruleId in normalizedRuleIds)
        if (result.assignmentForRule(ruleId) != null)
          result.assignmentForRule(ruleId)!.layerId,
    };
    return layerIds.length == 1;
  }

  List<ScriptRoleReplacementRuleLayerOverride> _layerOverridesWithAssignment(
    List<ScriptRoleReplacementRuleLayerOverride> current, {
    required Set<String> ruleIds,
    required ScriptRoleReplacementRuleLayerKind kind,
    required String stageId,
  }) {
    final normalizedStageId = stageId.trim();
    final normalizedKind = kind == ScriptRoleReplacementRuleLayerKind.stage &&
            normalizedStageId.isEmpty
        ? ScriptRoleReplacementRuleLayerKind.pending
        : kind;
    return List.unmodifiable([
      for (final override in current)
        if (!ruleIds.contains(override.ruleId)) override,
      for (final ruleId in ruleIds)
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: ruleId,
          kind: normalizedKind,
          stageId: normalizedKind == ScriptRoleReplacementRuleLayerKind.stage
              ? normalizedStageId
              : '',
        ),
    ]);
  }

  List<ScriptRoleReplacementRuleLayerOverride> _layerOverridesAfterRuleSplit(
    List<ScriptRoleReplacementRuleLayerOverride> current, {
    required String sourceRuleId,
    required String newRuleId,
  }) {
    final sourceOverride =
        current.where((override) => override.ruleId == sourceRuleId).lastOrNull;
    if (sourceOverride == null) {
      return current;
    }
    return List.unmodifiable([
      ...current,
      sourceOverride.copyWith(ruleId: newRuleId),
    ]);
  }

  List<ScriptRoleReplacementRuleLayerOverride> _layerOverridesAfterRuleMerge(
    List<ScriptRoleReplacementRuleLayerOverride> current, {
    required Set<String> mergedRuleIds,
    required String survivingRuleId,
    required Set<String> survivingRuleIds,
  }) {
    final byRuleId = <String, ScriptRoleReplacementRuleLayerOverride>{
      for (final override in current) override.ruleId: override,
    };
    final survivingOverride = byRuleId[survivingRuleId];
    return List.unmodifiable([
      for (final override in current)
        if (survivingRuleIds.contains(override.ruleId) &&
            !mergedRuleIds.contains(override.ruleId))
          override,
      if (survivingOverride != null)
        survivingOverride.copyWith(ruleId: survivingRuleId),
    ]);
  }

  List<ScriptRoleReplacementRuleLayerOverride> _layerOverridesRetainingRules(
    List<ScriptRoleReplacementRuleLayerOverride> current,
    Set<String> survivingRuleIds,
  ) {
    return List.unmodifiable([
      for (final override in current)
        if (survivingRuleIds.contains(override.ruleId)) override,
    ]);
  }

  ScriptRolePromptReplacement _normalizedRoleReplacement(
    ScriptRolePromptReplacement replacement,
  ) {
    final ruleIds = {for (final rule in replacement.rules) rule.id};
    final byRuleId = <String, ScriptRoleReplacementRuleLayerOverride>{};
    for (final override in replacement.layerOverrides) {
      if (!ruleIds.contains(override.ruleId)) {
        continue;
      }
      if (override.kind == ScriptRoleReplacementRuleLayerKind.stage &&
          override.stageId.trim().isEmpty) {
        byRuleId[override.ruleId] = ScriptRoleReplacementRuleLayerOverride(
          ruleId: override.ruleId,
          kind: ScriptRoleReplacementRuleLayerKind.pending,
        );
        continue;
      }
      byRuleId[override.ruleId] = override;
    }
    return replacement.copyWith(
      layerOverrides: List.unmodifiable(byRuleId.values),
    );
  }

  List<ScriptPromptReplacementRule> _mergedReplacementRules({
    required List<ScriptPromptReplacementRule> rules,
    required Set<String> selectedIds,
  }) {
    final selectedRules = [
      for (final rule in rules)
        if (selectedIds.contains(rule.id)) rule,
    ];
    final first = selectedRules.first;
    final sourceTerms = <ScriptPromptReplacementTerm>[];
    final seenTermIds = <String>{};
    final excludedTermIds = <String>[];
    final seenExcludedIds = <String>{};
    for (final rule in selectedRules) {
      for (final term in rule.sourceTerms) {
        if (seenTermIds.add(term.id)) {
          sourceTerms.add(term);
        }
      }
      for (final id in rule.excludedTermIds) {
        if (seenExcludedIds.add(id)) {
          excludedTermIds.add(id);
        }
      }
    }
    final merged = _replacementRuleWithMergedSemantics(
      survivor: first,
      mergedRules: selectedRules,
      sourceTerms: List.unmodifiable(sourceTerms),
      excludedTermIds: List.unmodifiable(excludedTermIds),
    );
    return [
      for (final rule in rules)
        if (rule.id == first.id)
          merged
        else if (!selectedIds.contains(rule.id))
          rule,
    ];
  }

  ScriptPromptReplacementRule _replacementRuleWithMergedSemantics({
    required ScriptPromptReplacementRule survivor,
    required List<ScriptPromptReplacementRule> mergedRules,
    required List<ScriptPromptReplacementTerm> sourceTerms,
    required List<String> excludedTermIds,
  }) {
    final targetPrompt = _joinPromptTags([
      for (final rule in mergedRules)
        if (rule.effectiveAction == ScriptPromptReplacementAction.replace)
          _materializedReplacementRuleOutputForMerge(rule),
    ]);
    final hasDelete = mergedRules.any(
      (rule) => rule.effectiveAction == ScriptPromptReplacementAction.delete,
    );
    final sourceWeightMultiplier = targetPrompt.trim().isEmpty && !hasDelete
        ? _commonSourceWeightMultiplierForMerge(mergedRules)
        : null;
    final action =
        targetPrompt.trim().isNotEmpty || sourceWeightMultiplier != null
            ? ScriptPromptReplacementAction.replace
            : hasDelete
                ? ScriptPromptReplacementAction.delete
                : ScriptPromptReplacementAction.none;
    return survivor.copyWith(
      sourceTerms: sourceTerms,
      excludedTermIds: excludedTermIds,
      action: action,
      matchMode: ScriptPromptReplacementMatchMode.any,
      targetPrompt: targetPrompt,
      targetWeightMultiplier: sourceWeightMultiplier,
      manualPhrase: '',
      anchorTermId: '',
    );
  }

  String _materializedReplacementRuleOutputForMerge(
    ScriptPromptReplacementRule rule,
  ) {
    final output = rule.manualPhrase.trim().isNotEmpty
        ? rule.manualPhrase
        : rule.targetPrompt;
    if (output.trim().isEmpty) {
      return '';
    }
    final multiplier = rule.targetWeightMultiplier;
    final tags = _splitDisplayTags(output);
    if (multiplier == null || (multiplier - 1.0).abs() < 0.000001) {
      return _joinPromptTags(tags);
    }
    return _joinPromptTags([
      for (final tag in tags) _promptTagWithScaledWeight(tag, multiplier),
    ]);
  }

  String _promptTagWithScaledWeight(String rawTag, double multiplier) {
    final analyses = PromptTagProcessor.analyzeWorkshopTags(rawTag);
    if (analyses.isEmpty) {
      return rawTag.trim();
    }
    final analysis = analyses.first;
    final displayText = analysis.displayText.trim();
    if (displayText.isEmpty) {
      return rawTag.trim();
    }
    final weight = (analysis.weight ?? 1.0) * multiplier;
    if ((weight - 1.0).abs() < 0.000001) {
      return displayText;
    }
    return PromptTagProcessor.formatInlineWeightTag(displayText, weight);
  }

  double? _commonSourceWeightMultiplierForMerge(
    List<ScriptPromptReplacementRule> rules,
  ) {
    double? common;
    for (final rule in rules) {
      if (rule.effectiveAction == ScriptPromptReplacementAction.none) {
        continue;
      }
      final multiplier = rule.targetWeightMultiplier;
      final hasOutput = rule.targetPrompt.trim().isNotEmpty ||
          rule.manualPhrase.trim().isNotEmpty;
      if (rule.effectiveAction != ScriptPromptReplacementAction.replace ||
          hasOutput ||
          multiplier == null) {
        return null;
      }
      if (common == null) {
        common = multiplier;
        continue;
      }
      if ((common - multiplier).abs() >= 0.000001) {
        return null;
      }
    }
    return common;
  }

  List<ScriptPromptReplacementRule>? _replacementRulesWithMergedSourceRule({
    required List<ScriptPromptReplacementRule> rules,
    required String sourceRuleId,
    required String targetRuleId,
  }) {
    final sourceRule =
        rules.where((rule) => rule.id == sourceRuleId).firstOrNull;
    if (sourceRule == null || sourceRule.sourceTerms.isEmpty) {
      return null;
    }
    final targetRule =
        rules.where((rule) => rule.id == targetRuleId).firstOrNull;
    if (targetRule == null) {
      return null;
    }
    final nextRules = _replacementRulesWithMovedSourceTerms(
      rules: rules,
      sourceRuleIds: {sourceRuleId},
      targetRuleId: targetRuleId,
      tags: sourceRule.sourceTerms.map((term) => term.text),
    );
    if (nextRules == null) {
      return null;
    }
    final mergedTarget =
        nextRules.where((rule) => rule.id == targetRuleId).firstOrNull;
    if (mergedTarget == null) {
      return null;
    }
    final merged = _replacementRuleWithMergedSemantics(
      survivor: mergedTarget,
      mergedRules: [targetRule, sourceRule],
      sourceTerms: mergedTarget.sourceTerms,
      excludedTermIds: mergedTarget.excludedTermIds,
    );
    return List.unmodifiable([
      for (final rule in nextRules)
        if (rule.id == targetRuleId) merged else rule,
    ]);
  }

  _ReplacementRuleSplitResult? _replacementRulesWithSplitSourceTerms({
    required List<ScriptPromptReplacementRule> rules,
    required String sourceRuleId,
    required Iterable<String> tags,
  }) {
    final wantedKeys = {
      for (final tag in tags)
        if (tag.trim().isNotEmpty)
          PromptTagProcessor.normalizeMatchKey(tag.trim()),
    }..removeWhere((key) => key.isEmpty);
    if (wantedKeys.isEmpty) {
      return null;
    }
    final sourceRule =
        rules.where((rule) => rule.id == sourceRuleId).firstOrNull;
    if (sourceRule == null || sourceRule.sourceTerms.length < 2) {
      return null;
    }
    final movingTerms = [
      for (final term in sourceRule.sourceTerms)
        if (wantedKeys.contains(
          PromptTagProcessor.normalizeMatchKey(term.text),
        ))
          term,
    ];
    if (movingTerms.isEmpty ||
        movingTerms.length == sourceRule.sourceTerms.length) {
      return null;
    }
    final movingTermIds = {for (final term in movingTerms) term.id};
    final remainingSourceTerms = [
      for (final term in sourceRule.sourceTerms)
        if (!movingTermIds.contains(term.id)) term,
    ];
    final remainingSourceTermIds = {
      for (final term in remainingSourceTerms) term.id,
    };
    final remainingExcludedIds = [
      for (final id in sourceRule.excludedTermIds)
        if (remainingSourceTermIds.contains(id)) id,
    ];
    final movingExcludedIds = [
      for (final id in sourceRule.excludedTermIds)
        if (movingTermIds.contains(id)) id,
    ];
    final newRuleId = _splitReplacementRuleId(
      sourceRuleId: sourceRuleId,
      movingTerms: movingTerms,
      rules: rules,
    );
    final newRule = ScriptPromptReplacementRule(
      id: newRuleId,
      sourceTerms: List.unmodifiable(movingTerms),
      excludedTermIds: List.unmodifiable(movingExcludedIds),
      anchorTermId: movingTermIds.contains(sourceRule.anchorTermId)
          ? sourceRule.anchorTermId
          : '',
    );
    final nextSourceAnchorTermId =
        remainingSourceTermIds.contains(sourceRule.anchorTermId)
            ? sourceRule.anchorTermId
            : '';
    final nextRules = <ScriptPromptReplacementRule>[];
    for (final rule in rules) {
      if (rule.id == sourceRuleId) {
        nextRules
          ..add(
            sourceRule.copyWith(
              sourceTerms: List.unmodifiable(remainingSourceTerms),
              excludedTermIds: List.unmodifiable(remainingExcludedIds),
              anchorTermId: nextSourceAnchorTermId,
            ),
          )
          ..add(newRule);
        continue;
      }
      nextRules.add(rule);
    }
    return _ReplacementRuleSplitResult(
      rules: List.unmodifiable(nextRules),
      newRuleId: newRuleId,
    );
  }

  String _splitReplacementRuleId({
    required String sourceRuleId,
    required List<ScriptPromptReplacementTerm> movingTerms,
    required List<ScriptPromptReplacementRule> rules,
  }) {
    final existingIds = {for (final rule in rules) rule.id};
    final baseId = stableIdFromText(
      prefix: '$sourceRuleId-split',
      text: movingTerms.map((term) => term.id).join('|'),
      label: movingTerms.map((term) => term.text).join(' '),
    );
    if (!existingIds.contains(baseId)) {
      return baseId;
    }
    var suffix = 2;
    while (existingIds.contains('$baseId-$suffix')) {
      suffix += 1;
    }
    return '$baseId-$suffix';
  }

  List<ScriptPromptReplacementRule>? _replacementRulesWithMovedSourceTerms({
    required List<ScriptPromptReplacementRule> rules,
    required Iterable<String> sourceRuleIds,
    required String targetRuleId,
    required Iterable<String> tags,
  }) {
    final wantedKeys = {
      for (final tag in tags)
        if (tag.trim().isNotEmpty)
          PromptTagProcessor.normalizeMatchKey(tag.trim()),
    }..removeWhere((key) => key.isEmpty);
    final normalizedSourceRuleIds = {
      for (final id in sourceRuleIds)
        if (id.trim().isNotEmpty && id != targetRuleId) id,
    };
    if (wantedKeys.isEmpty || normalizedSourceRuleIds.isEmpty) {
      return null;
    }
    final targetRule =
        rules.where((rule) => rule.id == targetRuleId).firstOrNull;
    if (targetRule == null) {
      return null;
    }
    final sourceRules = [
      for (final rule in rules)
        if (normalizedSourceRuleIds.contains(rule.id)) rule,
    ];
    final movingTermsBySourceRuleId =
        <String, List<ScriptPromptReplacementTerm>>{};
    final movingTerms = <ScriptPromptReplacementTerm>[];
    for (final sourceRule in sourceRules) {
      final sourceMovingTerms = [
        for (final term in sourceRule.sourceTerms)
          if (wantedKeys.contains(
            PromptTagProcessor.normalizeMatchKey(term.text),
          ))
            term,
      ];
      if (sourceMovingTerms.isEmpty) {
        continue;
      }
      movingTermsBySourceRuleId[sourceRule.id] =
          List.unmodifiable(sourceMovingTerms);
      movingTerms.addAll(sourceMovingTerms);
    }
    if (movingTerms.isEmpty) {
      return null;
    }
    final movingTermIds = {for (final term in movingTerms) term.id};
    final targetTermIds = {for (final term in targetRule.sourceTerms) term.id};
    final nextTargetTerms = [
      ...targetRule.sourceTerms,
      for (final term in movingTerms)
        if (targetTermIds.add(term.id)) term,
    ];
    final nextTargetExcludedIds = <String>[];
    final seenTargetExcludedIds = <String>{};
    void addTargetExcluded(String id) {
      if (seenTargetExcludedIds.add(id)) {
        nextTargetExcludedIds.add(id);
      }
    }

    for (final id in targetRule.excludedTermIds) {
      addTargetExcluded(id);
    }
    for (final sourceRule in sourceRules) {
      for (final id in sourceRule.excludedTermIds) {
        if (movingTermIds.contains(id)) {
          addTargetExcluded(id);
        }
      }
    }

    final nextRules = <ScriptPromptReplacementRule>[];
    for (final rule in rules) {
      if (rule.id == targetRuleId) {
        nextRules.add(
          targetRule.copyWith(
            sourceTerms: List.unmodifiable(nextTargetTerms),
            excludedTermIds: List.unmodifiable(nextTargetExcludedIds),
          ),
        );
        continue;
      }
      final sourceMovingTerms = movingTermsBySourceRuleId[rule.id];
      if (sourceMovingTerms != null) {
        final sourceMovingTermIds = {
          for (final term in sourceMovingTerms) term.id,
        };
        final remainingSourceTerms = [
          for (final term in rule.sourceTerms)
            if (!sourceMovingTermIds.contains(term.id)) term,
        ];
        if (remainingSourceTerms.isNotEmpty) {
          final remainingSourceTermIds = {
            for (final term in remainingSourceTerms) term.id,
          };
          final remainingExcludedIds = [
            for (final id in rule.excludedTermIds)
              if (remainingSourceTermIds.contains(id)) id,
          ];
          final nextSourceAnchorTermId =
              remainingSourceTermIds.contains(rule.anchorTermId)
                  ? rule.anchorTermId
                  : '';
          nextRules.add(
            rule.copyWith(
              sourceTerms: List.unmodifiable(remainingSourceTerms),
              excludedTermIds: List.unmodifiable(remainingExcludedIds),
              anchorTermId: nextSourceAnchorTermId,
            ),
          );
        }
        continue;
      }
      nextRules.add(rule);
    }
    return List.unmodifiable(nextRules);
  }

  List<RoleSwap> _roleSwapsAfterTargetCharacterEdit(
    RecastMapping mapping, {
    required String sourceRoleId,
    required String? characterId,
    required String? outfitId,
  }) {
    final withoutRole = [
      for (final swap in mapping.roleSwaps)
        if (swap.sourceRoleId != sourceRoleId) swap,
    ];
    if (mapping.roleAssemblies.isNotEmpty ||
        characterId == null ||
        characterId.trim().isEmpty) {
      return List.unmodifiable(withoutRole);
    }
    return List.unmodifiable([
      ...withoutRole,
      RoleSwap(
        sourceRoleId: sourceRoleId,
        targetCharacterId: characterId,
        targetOutfitId: outfitId,
      ),
    ]);
  }

  List<RoleSwap> _roleSwapsAfterTargetOutfitEdit(
    RecastMapping mapping, {
    required String sourceRoleId,
    required String? outfitId,
  }) {
    if (mapping.roleAssemblies.isNotEmpty) {
      return List.unmodifiable([
        for (final swap in mapping.roleSwaps)
          if (swap.sourceRoleId != sourceRoleId) swap,
      ]);
    }
    return List.unmodifiable([
      for (final swap in mapping.roleSwaps)
        if (swap.sourceRoleId == sourceRoleId)
          RoleSwap(
            sourceRoleId: swap.sourceRoleId,
            targetCharacterId: swap.targetCharacterId,
            targetOutfitId: outfitId,
          )
        else
          swap,
    ]);
  }

  void selectRoleStage(String sourceRoleId, String stageId) {
    _manualSelectedStageIdsByRole[sourceRoleId] = stageId;
    roleMappings = [
      for (final item in roleMappings)
        if (item.sourceRoleId == sourceRoleId)
          item.copyWith(selectedStageId: stageId)
        else
          item,
    ];
    _refreshRecastPlan();
    notifyListeners();
  }

  String? roleStageExistingOverlapMessage(String sourceRoleId) {
    final assembly = _mapping?.roleAssemblies
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (assembly == null) {
      return null;
    }
    final overlaps = <String>[];
    for (var firstIndex = 0;
        firstIndex < assembly.stages.length;
        firstIndex += 1) {
      final first = assembly.stages[firstIndex];
      final firstFrames = first.frameIndexes.toSet();
      for (var secondIndex = firstIndex + 1;
          secondIndex < assembly.stages.length;
          secondIndex += 1) {
        final second = assembly.stages[secondIndex];
        final sharedFrames = firstFrames
            .intersection(second.frameIndexes.toSet())
            .toList()
          ..sort();
        if (sharedFrames.isEmpty) {
          continue;
        }
        overlaps.add(
          '${first.label} / ${second.label}：${_compressedFrameIndexes(sharedFrames)}',
        );
      }
    }
    return overlaps.isEmpty ? null : '已有阶段帧重叠：${overlaps.join('；')}';
  }

  String? roleStageFrameOverlapMessage({
    required String sourceRoleId,
    String? stageId,
    required Iterable<int> frameIndexes,
  }) {
    final assembly = _mapping?.roleAssemblies
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (assembly == null) {
      return stageId == null ? null : '找不到角色阶段。';
    }
    final proposed = _normalizedRoleStageFrameIndexes(frameIndexes).toSet();
    final current = stageId == null
        ? const <int>{}
        : assembly.stages
                .where((stage) => stage.id == stageId)
                .firstOrNull
                ?.frameIndexes
                .toSet() ??
            const <int>{};
    final conflicts = <String>[];
    for (final stage in assembly.stages) {
      if (stage.id == stageId) {
        continue;
      }
      final otherFrames = stage.frameIndexes.toSet();
      final newlyOverlapping = proposed
          .intersection(otherFrames)
          .difference(current.intersection(otherFrames))
          .toList()
        ..sort();
      if (newlyOverlapping.isNotEmpty) {
        conflicts.add(
          '${stage.label}：${_compressedFrameIndexes(newlyOverlapping)}',
        );
      }
    }
    return conflicts.isEmpty ? null : '这些帧会与已有阶段重叠：${conflicts.join('；')}';
  }

  String? addRoleStage({
    required String sourceRoleId,
    required String label,
    List<int> frameIndexes = const [],
  }) {
    final mapping = _mapping;
    final assembly = mapping?.roleAssemblies
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final replacement = mapping?.rolePromptReplacements
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (mapping == null || (assembly == null && replacement == null)) {
      return null;
    }
    final normalizedFrames = _normalizedRoleStageFrameIndexes(frameIndexes);
    if (roleStageFrameOverlapMessage(
          sourceRoleId: sourceRoleId,
          frameIndexes: normalizedFrames,
        ) !=
        null) {
      return null;
    }
    final normalizedLabel = label.trim().isEmpty
        ? '服装阶段 ${(assembly?.stages.length ?? 0) + 1}'
        : label.trim();
    var stageId = '$sourceRoleId-stage-${const Uuid().v4()}';
    final existingIds = {
      for (final stage in assembly?.stages ?? const <RoleAssemblyStage>[])
        stage.id,
    };
    while (existingIds.contains(stageId)) {
      stageId = '$sourceRoleId-stage-${const Uuid().v4()}';
    }
    _mapping = mapping.copyWith(
      roleAssemblies: List.unmodifiable([
        for (final candidate in mapping.roleAssemblies)
          if (candidate.sourceRoleId == sourceRoleId)
            candidate.copyWith(
              stages: List.unmodifiable([
                ...candidate.stages,
                RoleAssemblyStage(
                  id: stageId,
                  label: normalizedLabel,
                  frameIndexes: normalizedFrames,
                ),
              ]),
            )
          else
            candidate,
        if (assembly == null)
          RoleAssembly(
            sourceRoleId: sourceRoleId,
            displayLabel: replacement!.displayLabel.trim().isEmpty
                ? sourceRoleId
                : replacement.displayLabel.trim(),
            sourceName: replacement.displayLabel.trim(),
            stages: [
              RoleAssemblyStage(
                id: stageId,
                label: normalizedLabel,
                frameIndexes: normalizedFrames,
              ),
            ],
          ),
      ]),
    );
    _manualSelectedStageIdsByRole[sourceRoleId] = stageId;
    _learnRoleMappingProfileAfterStageStructureChange(
      beforeMapping: mapping,
      sourceRoleId: sourceRoleId,
    );
    _commitRoleStageEdit(sourceRoleId);
    return stageId;
  }

  String? splitRoleStage({
    required String sourceRoleId,
    required String stageId,
    required String label,
    required Iterable<int> frameIndexes,
  }) {
    final mapping = _mapping;
    final assembly = mapping?.roleAssemblies
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final sourceStage =
        assembly?.stages.where((stage) => stage.id == stageId).firstOrNull;
    if (mapping == null || assembly == null || sourceStage == null) {
      return null;
    }
    final movedFrames = _normalizedRoleStageFrameIndexes(frameIndexes)
        .where(sourceStage.frameIndexes.contains)
        .toList(growable: false);
    if (movedFrames.isEmpty ||
        movedFrames.length == sourceStage.frameIndexes.toSet().length) {
      return null;
    }
    final movedFrameSet = movedFrames.toSet();
    final remainingFrames = [
      for (final frameIndex in sourceStage.frameIndexes)
        if (!movedFrameSet.contains(frameIndex)) frameIndex,
    ];
    final newStageId = '$sourceRoleId-stage-${const Uuid().v4()}';
    final normalizedLabel =
        label.trim().isEmpty ? '${sourceStage.label} 2' : label.trim();
    _mapping = mapping.copyWith(
      roleAssemblies: List.unmodifiable([
        for (final candidate in mapping.roleAssemblies)
          if (candidate.sourceRoleId == sourceRoleId)
            candidate.copyWith(
              stages: List.unmodifiable([
                for (final stage in candidate.stages)
                  if (stage.id == stageId)
                    stage.copyWith(
                      frameIndexes:
                          _normalizedRoleStageFrameIndexes(remainingFrames),
                    )
                  else
                    stage,
                sourceStage.copyWith(
                  id: newStageId,
                  label: normalizedLabel,
                  frameIndexes: _normalizedRoleStageFrameIndexes(movedFrames),
                ),
              ]),
            )
          else
            candidate,
      ]),
    );
    _manualSelectedStageIdsByRole[sourceRoleId] = newStageId;
    _learnRoleMappingProfileAfterStageStructureChange(
      beforeMapping: mapping,
      sourceRoleId: sourceRoleId,
    );
    _commitRoleStageEdit(sourceRoleId);
    return newStageId;
  }

  bool mergeRoleStages({
    required String sourceRoleId,
    required String sourceStageId,
    required String targetStageId,
  }) {
    if (sourceStageId == targetStageId) {
      return false;
    }
    final mapping = _mapping;
    final assembly = mapping?.roleAssemblies
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final sourceStage = assembly?.stages
        .where((stage) => stage.id == sourceStageId)
        .firstOrNull;
    final targetStage = assembly?.stages
        .where((stage) => stage.id == targetStageId)
        .firstOrNull;
    if (mapping == null ||
        assembly == null ||
        sourceStage == null ||
        targetStage == null) {
      return false;
    }
    final mergedFrames = _normalizedRoleStageFrameIndexes([
      ...targetStage.frameIndexes,
      ...sourceStage.frameIndexes,
    ]);
    _mapping = mapping.copyWith(
      roleAssemblies: List.unmodifiable([
        for (final candidate in mapping.roleAssemblies)
          if (candidate.sourceRoleId == sourceRoleId)
            candidate.copyWith(
              stages: List.unmodifiable([
                for (final stage in candidate.stages)
                  if (stage.id == targetStageId)
                    stage.copyWith(frameIndexes: mergedFrames)
                  else if (stage.id != sourceStageId)
                    stage,
              ]),
            )
          else
            candidate,
      ]),
      rolePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.rolePromptReplacements)
          if (replacement.sourceRoleId == sourceRoleId)
            replacement.copyWith(
              layerOverrides: List.unmodifiable([
                for (final override in replacement.layerOverrides)
                  if (override.kind ==
                          ScriptRoleReplacementRuleLayerKind.stage &&
                      override.stageId == sourceStageId)
                    override.copyWith(stageId: targetStageId)
                  else
                    override,
              ]),
            )
          else
            replacement,
      ]),
    );
    if (_manualSelectedStageIdsByRole[sourceRoleId] == sourceStageId) {
      _manualSelectedStageIdsByRole[sourceRoleId] = targetStageId;
    }
    _learnRoleMappingProfileAfterStageStructureChange(
      beforeMapping: mapping,
      sourceRoleId: sourceRoleId,
    );
    _commitRoleStageEdit(sourceRoleId);
    return true;
  }

  bool restoreAiRoleStageLayers(String sourceRoleId) {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null || !aiRoleExtraction.isReady) {
      return false;
    }
    final currentAssembly = mapping.roleAssemblies
        .where((assembly) => assembly.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final withoutRoleAssembly = mapping.copyWith(
      roleAssemblies: List.unmodifiable([
        for (final assembly in mapping.roleAssemblies)
          if (assembly.sourceRoleId != sourceRoleId) assembly,
      ]),
    );
    final application = _mappingWithAppliedAiRoleExtraction(
      script: script,
      mapping: withoutRoleAssembly,
      extraction: aiRoleExtraction,
    );
    final aiAssembly = application.mapping.roleAssemblies
        .where((assembly) => assembly.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (aiAssembly == null || aiAssembly.stages.isEmpty) {
      return false;
    }
    final currentStageById = {
      for (final stage
          in currentAssembly?.stages ?? const <RoleAssemblyStage>[])
        stage.id: stage,
    };
    final restoredStages = [
      for (final aiStage in aiAssembly.stages)
        () {
          final current = currentStageById[aiStage.id];
          if (current == null) {
            return aiStage;
          }
          return aiStage.copyWith(
            targetCharacterId: current.targetCharacterId,
            targetUpperOutfitId: current.targetUpperOutfitId,
            targetLowerOutfitId: current.targetLowerOutfitId,
            omittedParts: current.omittedParts,
            preservedParts: current.preservedParts,
            manualParts: current.manualParts,
          );
        }(),
    ];
    _mapping = mapping.copyWith(
      roleAssemblies: List.unmodifiable([
        for (final assembly in mapping.roleAssemblies)
          if (assembly.sourceRoleId == sourceRoleId)
            assembly.copyWith(stages: List.unmodifiable(restoredStages))
          else
            assembly,
        if (currentAssembly == null)
          aiAssembly.copyWith(stages: List.unmodifiable(restoredStages)),
      ]),
      rolePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.rolePromptReplacements)
          if (replacement.sourceRoleId == sourceRoleId)
            replacement.copyWith(layerOverrides: const [])
          else
            replacement,
      ]),
    );
    _manualSelectedStageIdsByRole.remove(sourceRoleId);
    _learnRoleMappingProfileAfterStageStructureChange(
      beforeMapping: mapping,
      sourceRoleId: sourceRoleId,
    );
    _commitRoleStageEdit(sourceRoleId);
    return true;
  }

  void clearRoleStageTarget({
    required String sourceRoleId,
    required String stageId,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    _mapping = mapping.copyWith(
      roleSwaps: [
        for (final swap in mapping.roleSwaps)
          if (swap.sourceRoleId != sourceRoleId) swap,
      ],
      roleAssemblies: [
        for (final assembly in mapping.roleAssemblies)
          if (assembly.sourceRoleId == sourceRoleId)
            assembly.copyWith(
              stages: [
                for (final stage in assembly.stages)
                  if (stage.id == stageId)
                    stage.copyWith(
                      targetCharacterId: null,
                      targetUpperOutfitId: null,
                      targetLowerOutfitId: null,
                      omittedParts: Set.unmodifiable(RecastPromptPart.values),
                      preservedParts: const {},
                      manualParts: const RecastPromptParts(),
                    )
                  else
                    stage,
              ],
            )
          else
            assembly,
      ],
    );
    _refreshRoleEditPreview(sourceRoleId);
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void deleteRoleStage({
    required String sourceRoleId,
    required String stageId,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final targetAssembly = mapping.roleAssemblies
        .where((assembly) => assembly.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (targetAssembly == null) {
      return;
    }
    var changed = false;
    final nextAssemblies = <RoleAssembly>[];
    for (final assembly in mapping.roleAssemblies) {
      if (assembly.sourceRoleId != sourceRoleId) {
        nextAssemblies.add(assembly);
        continue;
      }
      final nextStages = [
        for (final stage in assembly.stages)
          if (stage.id != stageId) stage,
      ];
      if (nextStages.length == assembly.stages.length) {
        nextAssemblies.add(assembly);
        continue;
      }
      changed = true;
      if (nextStages.isNotEmpty) {
        nextAssemblies.add(
          assembly.copyWith(stages: List.unmodifiable(nextStages)),
        );
      }
    }
    if (!changed) {
      return;
    }
    _mapping = mapping.copyWith(
      roleAssemblies: List.unmodifiable(nextAssemblies),
      rolePromptReplacements: List.unmodifiable([
        for (final replacement in mapping.rolePromptReplacements)
          if (replacement.sourceRoleId == sourceRoleId)
            replacement.copyWith(
              layerOverrides: List.unmodifiable([
                for (final override in replacement.layerOverrides)
                  if (override.kind ==
                          ScriptRoleReplacementRuleLayerKind.stage &&
                      override.stageId == stageId)
                    override.copyWith(
                      kind: ScriptRoleReplacementRuleLayerKind.pending,
                    )
                  else
                    override,
              ]),
            )
          else
            replacement,
      ]),
    );
    if (_manualSelectedStageIdsByRole[sourceRoleId] == stageId) {
      final fallbackStage = targetAssembly.stages
          .where((stage) => stage.id != stageId)
          .firstOrNull;
      if (fallbackStage == null) {
        _manualSelectedStageIdsByRole.remove(sourceRoleId);
      } else {
        _manualSelectedStageIdsByRole[sourceRoleId] = fallbackStage.id;
      }
    }
    _learnRoleMappingProfileAfterStageStructureChange(
      beforeMapping: mapping,
      sourceRoleId: sourceRoleId,
    );
    _commitRoleStageEdit(sourceRoleId);
  }

  void renameRoleStage({
    required String sourceRoleId,
    required String stageId,
    required String label,
  }) {
    final normalized = label.trim();
    if (normalized.isEmpty) {
      return;
    }
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
      learnReplacementProfile: true,
      update: (stage, _) => stage.copyWith(label: normalized),
    );
  }

  void setRoleStageFrameIndexes({
    required String sourceRoleId,
    required String stageId,
    required List<int> frameIndexes,
  }) {
    if (roleStageFrameOverlapMessage(
          sourceRoleId: sourceRoleId,
          stageId: stageId,
          frameIndexes: frameIndexes,
        ) !=
        null) {
      return;
    }
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
      learnReplacementProfile: true,
      update: (stage, _) => stage.copyWith(
        frameIndexes: _normalizedRoleStageFrameIndexes(frameIndexes),
      ),
    );
  }

  void setRoleUpperOutfit(
    String sourceRoleId,
    String stageId,
    String? outfitId,
  ) {
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
      materializeSourceIdentity: true,
      update: (stage, character) {
        final nextParts = _fillEmptyOutfitParts(
          stage.manualParts,
          _outfitById(character, outfitId),
          includeUpper: true,
          includeLower: false,
        );
        return stage.copyWith(
          targetUpperOutfitId: outfitId,
          omittedParts: _omittedPartsAfterPartFill(
            stage.omittedParts,
            RecastPromptPart.upperClothing,
            nextParts.upperClothing,
          ),
          preservedParts: _preservedPartsAfterPartFill(
            stage.preservedParts,
            RecastPromptPart.upperClothing,
            nextParts.upperClothing,
          ),
          manualParts: nextParts,
        );
      },
    );
  }

  void setRoleLowerOutfit(
    String sourceRoleId,
    String stageId,
    String? outfitId,
  ) {
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
      materializeSourceIdentity: true,
      update: (stage, character) {
        final nextParts = _fillEmptyOutfitParts(
          stage.manualParts,
          _outfitById(character, outfitId),
          includeUpper: false,
          includeLower: true,
        );
        return stage.copyWith(
          targetLowerOutfitId: outfitId,
          omittedParts: _omittedPartsAfterPartFill(
            stage.omittedParts,
            RecastPromptPart.lowerClothing,
            nextParts.lowerClothing,
          ),
          preservedParts: _preservedPartsAfterPartFill(
            stage.preservedParts,
            RecastPromptPart.lowerClothing,
            nextParts.lowerClothing,
          ),
          manualParts: nextParts,
        );
      },
    );
  }

  void setRoleStagePart({
    required String sourceRoleId,
    required String stageId,
    required StudioScriptRolePart part,
    required String value,
  }) {
    if (part == StudioScriptRolePart.nonRole) {
      return;
    }
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
      materializeSourceIdentity: part == StudioScriptRolePart.identity,
      update: (stage, _) {
        final recastPart = _recastPromptPartFor(part);
        final nextManualParts = switch (part) {
          StudioScriptRolePart.identity => stage.manualParts.copyWith(
              identity: value,
            ),
          StudioScriptRolePart.upperBody => stage.manualParts.copyWith(
              upperBody: value,
            ),
          StudioScriptRolePart.lowerBody => stage.manualParts.copyWith(
              lowerBody: value,
            ),
          StudioScriptRolePart.upperClothing => stage.manualParts.copyWith(
              upperClothing: value,
            ),
          StudioScriptRolePart.lowerClothing => stage.manualParts.copyWith(
              lowerClothing: value,
            ),
          StudioScriptRolePart.nonRole => stage.manualParts,
        };
        final nextStage = stage.copyWith(
          omittedParts: _omittedPartsAfterEdit(stage.omittedParts, recastPart),
          preservedParts: _preservedPartsAfterEdit(
            stage.preservedParts,
            recastPart,
            value,
          ),
          manualParts: nextManualParts,
        );
        _recordManualRoleFieldOverride(
          beforeParts: _AiRoleDraftParts.fromPromptParts(
            _combinedStageParts(stage),
          ),
          afterParts: _AiRoleDraftParts.fromPromptParts(
            _combinedStageParts(nextStage),
          ),
          editedPart: part,
        );
        return nextStage;
      },
    );
  }

  void batchRoleStageEdits(VoidCallback edit) {
    _roleStageEditBatchDepth += 1;
    try {
      edit();
    } finally {
      _roleStageEditBatchDepth -= 1;
      if (_roleStageEditBatchDepth == 0) {
        _flushBatchedRoleStageEdits();
      }
    }
  }

  void setRoleStagePartDeleted({
    required String sourceRoleId,
    required String stageId,
    required StudioScriptRolePart part,
    required bool deleted,
  }) {
    if (part == StudioScriptRolePart.nonRole) {
      return;
    }
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
      update: (stage, _) {
        final recastPart = _recastPromptPartFor(part);
        final nextOmitted = {...stage.omittedParts};
        final nextPreserved = {...stage.preservedParts};
        final nextManualParts = deleted
            ? _promptPartsWithPartValue(stage.manualParts, part, '')
            : stage.manualParts;
        if (deleted) {
          nextOmitted.add(recastPart);
          nextPreserved.remove(recastPart);
        } else {
          nextOmitted.remove(recastPart);
          if (_promptPartValue(nextManualParts, part).trim().isEmpty) {
            nextPreserved.add(recastPart);
          }
        }
        return stage.copyWith(
          omittedParts: Set.unmodifiable(nextOmitted),
          preservedParts: Set.unmodifiable(nextPreserved),
          manualParts: nextManualParts,
        );
      },
    );
  }

  void setRoleStageSourcePart({
    required String sourceRoleId,
    required String stageId,
    required StudioScriptRolePart part,
    required String value,
  }) {
    if (part == StudioScriptRolePart.nonRole) {
      return;
    }
    if (part == StudioScriptRolePart.identity) {
      final mapping = _mapping;
      if (mapping == null) {
        return;
      }
      _mapping = mapping.copyWith(
        roleAssemblies: [
          for (final assembly in mapping.roleAssemblies)
            if (assembly.sourceRoleId == sourceRoleId)
              assembly.copyWith(
                sourceName: value,
                stages: [
                  for (final stage in assembly.stages)
                    if (stage.id == stageId)
                      (() {
                        final nextStage = stage.copyWith(
                          sourceParts: stage.sourceParts.copyWith(
                            identity: value,
                          ),
                        );
                        _recordManualRoleFieldOverride(
                          beforeParts: _AiRoleDraftParts.fromPromptParts(
                            _combinedStageParts(stage),
                          ),
                          afterParts: _AiRoleDraftParts.fromPromptParts(
                            _combinedStageParts(nextStage),
                          ),
                          editedPart: part,
                        );
                        return nextStage;
                      })()
                    else
                      stage,
                ],
              )
            else
              assembly,
        ],
      );
      _commitRoleStageEdit(sourceRoleId);
      return;
    }
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
      update: (stage, _) {
        final sourceParts = switch (part) {
          StudioScriptRolePart.identity => stage.sourceParts.copyWith(
              identity: value,
            ),
          StudioScriptRolePart.upperBody => stage.sourceParts.copyWith(
              upperBody: value,
            ),
          StudioScriptRolePart.lowerBody => stage.sourceParts.copyWith(
              lowerBody: value,
            ),
          StudioScriptRolePart.upperClothing => stage.sourceParts.copyWith(
              upperClothing: value,
            ),
          StudioScriptRolePart.lowerClothing => stage.sourceParts.copyWith(
              lowerClothing: value,
            ),
          StudioScriptRolePart.nonRole => stage.sourceParts,
        };
        final nextStage = stage.copyWith(
          sourceSummary: _summaryFromPromptParts(sourceParts),
          sourceParts: sourceParts,
        );
        _recordManualRoleFieldOverride(
          beforeParts: _AiRoleDraftParts.fromPromptParts(
            _combinedStageParts(stage),
          ),
          afterParts: _AiRoleDraftParts.fromPromptParts(
            _combinedStageParts(nextStage),
          ),
          editedPart: part,
        );
        return nextStage;
      },
    );
  }

  void copyRoleStageTargetToAllOutfits({
    required String sourceRoleId,
    required String stageId,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final assembly = mapping.roleAssemblies
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final template =
        assembly?.stages.where((stage) => stage.id == stageId).firstOrNull;
    if (assembly == null || template == null) {
      return;
    }
    _mapping = _mappingWithVisibleSourceIdentityParts(
      mapping.copyWith(
        roleAssemblies: [
          for (final candidate in mapping.roleAssemblies)
            if (candidate.sourceRoleId == sourceRoleId)
              candidate.copyWith(
                stages: [
                  for (final stage in candidate.stages)
                    _stageWithCopiedTarget(template: template, target: stage),
                ],
              )
            else
              candidate,
        ],
      ),
    );
    _commitRoleStageEdit(sourceRoleId);
  }

  void copyRoleStageTargetToStage({
    required String sourceRoleId,
    required String templateStageId,
    required String targetStageId,
  }) {
    if (templateStageId == targetStageId) {
      return;
    }
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final assembly = mapping.roleAssemblies
        .where((entry) => entry.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final template = assembly?.stages
        .where((stage) => stage.id == templateStageId)
        .firstOrNull;
    final target = assembly?.stages
        .where((stage) => stage.id == targetStageId)
        .firstOrNull;
    if (assembly == null || template == null || target == null) {
      return;
    }
    _mapping = _mappingWithVisibleSourceIdentityParts(
      mapping.copyWith(
        roleAssemblies: [
          for (final candidate in mapping.roleAssemblies)
            if (candidate.sourceRoleId == sourceRoleId)
              candidate.copyWith(
                stages: [
                  for (final stage in candidate.stages)
                    if (stage.id == targetStageId)
                      _stageWithCopiedTarget(template: template, target: stage)
                    else
                      stage,
                ],
              )
            else
              candidate,
        ],
      ),
    );
    _commitRoleStageEdit(sourceRoleId);
  }

  RoleAssemblyStage _stageWithCopiedTarget({
    required RoleAssemblyStage template,
    required RoleAssemblyStage target,
  }) {
    return target.copyWith(
      targetCharacterId: template.targetCharacterId,
      targetUpperOutfitId: template.targetUpperOutfitId,
      targetLowerOutfitId: template.targetLowerOutfitId,
      omittedParts: Set.unmodifiable(template.omittedParts),
      preservedParts: Set.unmodifiable(template.preservedParts),
      manualParts: template.manualParts,
    );
  }

  void _commitRoleStageEdit(String sourceRoleId) {
    if (_roleStageEditBatchDepth > 0) {
      _batchedRoleEditSourceRoleIds.add(sourceRoleId);
      _batchedRoleEditNeedsCacheSave = true;
      return;
    }
    _refreshRoleEditPreview(sourceRoleId);
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void _learnRoleMappingProfileAfterStageStructureChange({
    required RecastMapping beforeMapping,
    required String sourceRoleId,
  }) {
    final afterMapping = _mapping;
    if (afterMapping == null) {
      return;
    }
    final beforeReplacement = beforeMapping.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final afterReplacement = afterMapping.rolePromptReplacements
        .where((replacement) => replacement.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (beforeReplacement == null || afterReplacement == null) {
      return;
    }
    final beforeAssembly = beforeMapping.roleAssemblies
        .where((assembly) => assembly.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final afterAssembly = afterMapping.roleAssemblies
        .where((assembly) => assembly.sourceRoleId == sourceRoleId)
        .firstOrNull;
    unawaited(
      _learnActiveRoleMappingProfile(
        beforeReplacement,
        afterReplacement,
        beforeAssembly: beforeAssembly,
        afterAssembly: afterAssembly,
      ),
    );
  }

  void _flushBatchedRoleStageEdits() {
    if (_batchedRoleEditSourceRoleIds.isEmpty) {
      return;
    }
    final sourceRoleIds = _batchedRoleEditSourceRoleIds.toList(
      growable: false,
    );
    final needsCacheSave = _batchedRoleEditNeedsCacheSave;
    _batchedRoleEditSourceRoleIds.clear();
    _batchedRoleEditNeedsCacheSave = false;
    for (final sourceRoleId in sourceRoleIds) {
      _refreshRoleEditPreview(sourceRoleId);
    }
    notifyListeners();
    if (needsCacheSave) {
      _scheduleCurrentCacheSave();
    }
  }

  void _updateRoleStage({
    required String sourceRoleId,
    required String stageId,
    required RoleAssemblyStage Function(
      RoleAssemblyStage stage,
      CharacterEntry? character,
    ) update,
    bool materializeSourceIdentity = false,
    bool learnReplacementProfile = false,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final nextMapping = mapping.copyWith(
      roleAssemblies: [
        for (final assembly in mapping.roleAssemblies)
          if (assembly.sourceRoleId == sourceRoleId)
            assembly.copyWith(
              stages: [
                for (final stage in assembly.stages)
                  if (stage.id == stageId)
                    update(
                      stage,
                      stage.targetCharacterId == null
                          ? null
                          : _characterById(stage.targetCharacterId!),
                    )
                  else
                    stage,
              ],
            )
          else
            assembly,
      ],
    );
    _mapping = materializeSourceIdentity
        ? _mappingWithVisibleSourceIdentityParts(nextMapping)
        : nextMapping;
    if (learnReplacementProfile) {
      _learnRoleMappingProfileAfterStageStructureChange(
        beforeMapping: mapping,
        sourceRoleId: sourceRoleId,
      );
    }
    _commitRoleStageEdit(sourceRoleId);
  }

  List<int> _normalizedRoleStageFrameIndexes(Iterable<int> frameIndexes) {
    final result = frameIndexes.where((index) => index >= 0).toSet().toList()
      ..sort();
    return List.unmodifiable(result);
  }

  String _compressedFrameIndexes(Iterable<int> frameIndexes) {
    final values = _normalizedRoleStageFrameIndexes(frameIndexes);
    if (values.isEmpty) {
      return '无';
    }
    final ranges = <String>[];
    var start = values.first;
    var end = values.first;
    for (final value in values.skip(1)) {
      if (value == end + 1) {
        end = value;
        continue;
      }
      ranges.add(start == end ? '$start' : '$start–$end');
      start = value;
      end = value;
    }
    ranges.add(start == end ? '$start' : '$start–$end');
    return ranges.join('、');
  }

  void setArtistChain(String? artistChainId) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final hasArtistChain = artistChainId != null && artistChainId.isNotEmpty;
    final artistChain = hasArtistChain
        ? _availableArtistChains
            .where((candidate) => candidate.id == artistChainId)
            .firstOrNull
        : null;
    final sourceArtistPrompt = _currentArtistSourceLabel();
    _mapping = mapping.copyWith(
      artistSwap: hasArtistChain
          ? ArtistSwap(
              targetArtistChainId: artistChainId,
              sourceArtistPrompt: sourceArtistPrompt,
            )
          : null,
      clearArtistSwap: !hasArtistChain,
      manualVibeRefs: hasArtistChain
          ? List.unmodifiable(
              _mergeVibeReferences(
                mapping.manualVibeRefs,
                artistChain?.vibeRefs.where(
                      (vibe) => vibe.vibeB64.trim().isNotEmpty,
                    ) ??
                    const [],
              ),
            )
          : mapping.manualVibeRefs,
    );
    artistMappings = [
      for (final item in artistMappings)
        StudioScriptArtistMappingItem(
          sourceLabel: item.sourceLabel,
          selectedArtistChainId: hasArtistChain ? artistChainId : null,
          manualPrompt: '',
          deleteSource: false,
        ),
    ];
    _refreshArtistEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setTargetGenerationModel(String model) {
    final mapping = _mapping;
    final normalized = model.trim();
    if (mapping == null ||
        normalized == mapping.targetGenerationModel ||
        !studioTargetGenerationModels.contains(normalized)) {
      return;
    }
    _mapping = mapping.copyWith(targetGenerationModel: normalized);
    _refreshPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setManualArtistPrompt(String value) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final prompt = value.trim();
    final sourceArtistPrompt = _currentArtistSourceLabel();
    final deleteSource = mapping.artistSwap?.deleteSource ?? false;
    final nextSwap = prompt.isEmpty && !deleteSource
        ? null
        : ArtistSwap(
            targetArtistChainId: '',
            manualPrompt: prompt,
            sourceArtistPrompt: sourceArtistPrompt,
            deleteSource: deleteSource,
          );
    _mapping = mapping.copyWith(
      artistSwap: nextSwap,
      clearArtistSwap: nextSwap == null,
    );
    artistMappings = [
      for (final item in artistMappings)
        StudioScriptArtistMappingItem(
          sourceLabel: item.sourceLabel,
          selectedArtistChainId: null,
          manualPrompt: prompt,
          deleteSource: deleteSource,
        ),
    ];
    _refreshArtistEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setArtistSourceLabel(String value) {
    _artistSourceLabelOverride = value.trim();
    final mapping = _mapping;
    final artistSwap = mapping?.artistSwap;
    if (mapping != null && artistSwap != null) {
      _mapping = mapping.copyWith(
        artistSwap: artistSwap.copyWith(
          sourceArtistPrompt: _artistSourceLabelOverride,
        ),
      );
    }
    artistMappings = [
      for (final item in artistMappings)
        StudioScriptArtistMappingItem(
          sourceLabel: _artistSourceLabelOverride ?? item.sourceLabel,
          selectedArtistChainId: item.selectedArtistChainId,
          manualPrompt: item.manualPrompt,
          deleteSource: item.deleteSource,
        ),
    ];
    _refreshRecastPlan();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setArtistSourceDeleted(bool deleted) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final sourceArtistPrompt = _currentArtistSourceLabel();
    final current = mapping.artistSwap;
    final targetArtistChainId = current?.targetArtistChainId.trim() ?? '';
    final manualPrompt = current?.manualPrompt.trim() ?? '';
    final nextSwap =
        !deleted && targetArtistChainId.isEmpty && manualPrompt.isEmpty
            ? null
            : ArtistSwap(
                targetArtistChainId: targetArtistChainId,
                manualPrompt: manualPrompt,
                sourceArtistPrompt: sourceArtistPrompt,
                deleteSource: deleted,
              );
    _mapping = mapping.copyWith(
      artistSwap: nextSwap,
      clearArtistSwap: nextSwap == null,
    );
    artistMappings = [
      for (final item in artistMappings)
        StudioScriptArtistMappingItem(
          sourceLabel: item.sourceLabel,
          selectedArtistChainId:
              targetArtistChainId.isEmpty ? null : targetArtistChainId,
          manualPrompt: manualPrompt,
          deleteSource: deleted,
        ),
    ];
    _refreshArtistEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setPromptBlockSource(String block, String value) {
    _updatePromptBlockSwap(block: block, sourcePrompt: value.trim());
  }

  void setPromptBlockManualPrompt(String block, String value) {
    _updatePromptBlockSwap(block: block, manualPrompt: value.trim());
  }

  void appendPromptBlockManualPrompt(String block, String value) {
    final normalizedBlock = block.trim();
    final nextValue = value.trim();
    if (normalizedBlock.isEmpty || nextValue.isEmpty) {
      return;
    }
    final current = promptBlockMappings
        .where((entry) => entry.block == normalizedBlock)
        .firstOrNull;
    _updatePromptBlockSwap(
      block: normalizedBlock,
      manualPrompt: _joinPromptTags([
        current?.manualPrompt ?? '',
        nextValue,
      ]),
    );
  }

  void setPromptBlockDeleted(String block, bool deleted) {
    _updatePromptBlockSwap(block: block, deleteSource: deleted);
  }

  void _updatePromptBlockSwap({
    required String block,
    String? sourcePrompt,
    String? manualPrompt,
    bool? deleteSource,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final normalizedBlock = block.trim();
    final current = mapping.promptBlockSwaps
        .where((swap) => swap.block == normalizedBlock)
        .firstOrNull;
    final item = promptBlockMappings
        .where((entry) => entry.block == normalizedBlock)
        .firstOrNull;
    final next = PromptBlockSwap(
      block: normalizedBlock,
      sourcePrompt:
          sourcePrompt ?? current?.sourcePrompt ?? item?.sourcePrompt ?? '',
      manualPrompt: manualPrompt ?? current?.manualPrompt ?? '',
      deleteSource: deleteSource ?? current?.deleteSource ?? false,
    );
    final keepSwap = next.sourcePrompt.trim().isNotEmpty ||
        next.manualPrompt.trim().isNotEmpty ||
        next.deleteSource;
    _mapping = mapping.copyWith(
      promptBlockSwaps: List.unmodifiable([
        for (final swap in mapping.promptBlockSwaps)
          if (swap.block != normalizedBlock) swap,
        if (keepSwap) next,
      ]),
    );
    _refreshPromptBlockEditPreview();
    notifyListeners();
    _scheduleCurrentCacheSave();
  }

  void setManualVibe(String vibeId, bool selected, {bool notify = true}) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    if (!selected) {
      _mapping = mapping.copyWith(
        manualVibeRefs: List.unmodifiable([
          for (final existing in mapping.manualVibeRefs)
            if (existing.id != vibeId) existing,
        ]),
      );
      if (notify) {
        notifyListeners();
      }
      _scheduleCurrentCacheSave();
      return;
    }
    if (mapping.manualVibeRefs.any((existing) => existing.id == vibeId)) {
      return;
    }
    final vibe = _manualVibeCandidateById(vibeId);
    if (vibe == null) {
      return;
    }
    final next = [
      for (final existing in mapping.manualVibeRefs)
        if (existing.id != vibeId) existing,
      vibe,
    ];
    _mapping = mapping.copyWith(manualVibeRefs: List.unmodifiable(next));
    if (notify) {
      notifyListeners();
    }
    _scheduleCurrentCacheSave();
  }

  WorkspaceVibeReference? _manualVibeCandidateById(String vibeId) {
    for (final vibe in sourceVibeOptions) {
      if (vibe.id == vibeId) {
        return vibe;
      }
    }
    for (final vibe in _availableVibes) {
      if (vibe.id == vibeId) {
        return vibe;
      }
    }
    return null;
  }

  void setManualVibeStrength(
    String vibeId,
    double strength, {
    bool notify = true,
  }) {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final nextStrength = strength.clamp(0.0, 1.0).toDouble();
    var changed = false;
    final nextManualVibes = [
      for (final vibe in mapping.manualVibeRefs)
        if (vibe.id == vibeId)
          () {
            changed = true;
            return vibe.copyWith(referenceStrength: nextStrength);
          }()
        else
          vibe,
    ];
    if (!changed) {
      return;
    }
    _mapping = mapping.copyWith(
      manualVibeRefs: List.unmodifiable(nextManualVibes),
    );
    _availableVibes = List.unmodifiable([
      for (final vibe in _availableVibes)
        if (vibe.id == vibeId)
          vibe.copyWith(referenceStrength: nextStrength)
        else
          vibe,
    ]);
    if (notify) {
      notifyListeners();
    }
    _scheduleCurrentCacheSave();
  }

  Future<List<WorkspaceVibeReference>> importManualVibes() async {
    final importer = importVibes;
    if (importer == null) {
      return const [];
    }
    final imported = (await importer())
        .where((vibe) => vibe.vibeB64.trim().isNotEmpty)
        .toList(growable: false);
    if (imported.isEmpty) {
      return const [];
    }

    _availableVibes = List.unmodifiable(
      _mergeVibeReferences(_availableVibes, imported),
    );
    final mapping = _mapping;
    if (mapping != null) {
      _mapping = mapping.copyWith(
        manualVibeRefs: List.unmodifiable(
          _mergeVibeReferences(mapping.manualVibeRefs, imported),
        ),
      );
    }
    notifyListeners();
    _scheduleCurrentCacheSave();
    return imported;
  }

  Future<bool> sendToProduction() async {
    final script = _script;
    final service = productionService;
    if (script == null || service == null) {
      return false;
    }
    if (isSendingToProduction) {
      return false;
    }

    final sendGeneration = ++_productionSendGeneration;
    final scriptOpenGeneration = _scriptOpenGeneration;
    bool isCurrentSend() =>
        sendGeneration == _productionSendGeneration &&
        scriptOpenGeneration == _scriptOpenGeneration &&
        _script?.id == script.id;

    isSendingToProduction = true;
    notifyListeners();

    try {
      await Future<void>.delayed(Duration.zero);
      if (!isCurrentSend()) return false;
      final mapping = _mapping ?? RecastMapping.defaults(script.id);
      final productionMapping = _mappingForProductionSend(mapping);
      if (!identical(productionMapping, mapping)) {
        _mapping = productionMapping;
        _refreshPreview();
      }
      final resolvedResult = await recastEngine.resolvePayloadsAsync(
        script: script,
        mapping: productionMapping,
        characters: _characters,
        artistChains: _availableArtistChains,
        globalBlockWords: _effectiveBlockWords(),
        globalPromptPrefix: globalPromptPrefix,
        filterRuleConfig: _blockWordConfig(),
      );
      final result = resolvedResult.copyWith(
        targetGenerationModel: studioTargetGenerationModelFor(
          productionMapping.targetGenerationModel,
        ),
      );
      if (!isCurrentSend()) return false;
      final planId = _productionPlanId(script);
      final planName = '${script.name} Recast';
      final plan = await service.enqueueRecastResult(
        result: result,
        planId: planId,
        planName: planName,
        recastRunId: '$planId-run',
        scriptName: script.name,
        scriptPath: script.rootPath,
      );
      if (!isCurrentSend()) return false;

      final shouldConfirmAiDraft =
          aiRoleExtraction.isReady && !_aiRoleExtractionDraftDismissed;
      if (shouldConfirmAiDraft) {
        _aiRoleExtractionDraftDismissed = true;
      }
      if (shouldConfirmAiDraft) {
        await _saveCurrentCache();
        if (!isCurrentSend()) return false;
      }
      sentToProduction = true;
      lastProductionPlanId = plan.id;
      lastProductionPlanName = plan.name;
      _frameResultStatuses = {
        for (final frame in result.frames)
          frame.frameIndex: FrameResultStatus.completed,
      };
      _refreshTimeline();
      return true;
    } finally {
      if (isCurrentSend()) {
        isSendingToProduction = false;
        notifyListeners();
      }
    }
  }

  RecastMapping _mappingForProductionSend(RecastMapping mapping) {
    final replacementSourceRoleIds = {
      for (final replacement in mapping.rolePromptReplacements)
        if (replacement.sourceRoleId.trim().isNotEmpty)
          replacement.sourceRoleId.trim(),
    };
    final productionAssemblies = <RoleAssembly>[];
    for (final assembly in mapping.roleAssemblies) {
      final userAuthoredStages = [
        for (final stage in assembly.stages)
          if (_isUserAuthoredStage(stage)) stage,
      ];
      if (userAuthoredStages.isNotEmpty) {
        productionAssemblies.add(
          assembly.copyWith(stages: List.unmodifiable(userAuthoredStages)),
        );
        continue;
      }
      if (replacementSourceRoleIds.contains(assembly.sourceRoleId.trim()) &&
          assembly.sourceAppearances.isNotEmpty) {
        productionAssemblies.add(
          assembly.copyWith(stages: const []),
        );
      }
    }
    if (productionAssemblies.length == mapping.roleAssemblies.length &&
        productionAssemblies.indexed.every(
          (entry) =>
              identical(entry.$2, mapping.roleAssemblies[entry.$1]) ||
              _roleAssemblyStagesEqual(
                entry.$2.stages,
                mapping.roleAssemblies[entry.$1].stages,
              ),
        )) {
      return mapping;
    }
    return mapping.copyWith(
      roleAssemblies: List.unmodifiable(productionAssemblies),
    );
  }

  Future<List<CharacterEntry>> _loadCharacters() async {
    final loader = loadCharacters;
    if (loader == null) {
      return const [];
    }
    return loader();
  }

  Future<List<ArtistChain>> _loadArtistChains() async {
    final loader = loadArtistChains;
    if (loader == null) {
      return const [];
    }
    return loader();
  }

  Future<List<WorkspaceVibeReference>> _loadVibes() async {
    final loader = loadVibes;
    if (loader == null) {
      return const [];
    }
    return loader();
  }

  Future<List<Recipe>> _loadRecipes() async {
    final loader = loadRecipes;
    if (loader == null) {
      return const [];
    }
    return loader();
  }

  Future<List<TagEntry>> _loadTags() async {
    final loader = loadTags;
    if (loader == null) {
      return const [];
    }
    return loader();
  }

  Future<List<PromptAssetCategory>> _loadPromptAssetCategories() async {
    final loader = loadPromptAssetCategories;
    if (loader == null) {
      return const [];
    }
    return loader();
  }

  Future<void> _loadAssets() async {
    await ensureRoleMappingProfilesLoaded();
    final assetContextLoader = loadAssetContext;
    if (assetContextLoader != null) {
      final context = await assetContextLoader();
      _characters = context.characters;
      _availableArtistChains = List.unmodifiable(context.artistChains);
      _characterPreviewPaths = context.characterPreviewPaths;
      _outfitPreviewPaths = context.outfitPreviewPaths;
      _artistChainPreviewPaths = context.artistChainPreviewPaths;
      _availableRecipes = List.unmodifiable(await _loadRecipes());
      _availableTags = List.unmodifiable(await _loadTags());
      _promptAssetCategories =
          List.unmodifiable(await _loadPromptAssetCategories());
      _availableVibes = List.unmodifiable(await _loadVibes());
      _filterRuleConfig = context.filterRules;
      _applyGlobalBlockWords(context.filterRules.deleteKeywords);
      _applyGlobalPromptPrefix(context.filterRules.globalPromptPrefix);
      _assetsLoaded = true;
      return;
    }
    _characters = await _loadCharacters();
    _availableArtistChains = List.unmodifiable(await _loadArtistChains());
    _availableRecipes = List.unmodifiable(await _loadRecipes());
    _availableTags = List.unmodifiable(await _loadTags());
    _promptAssetCategories =
        List.unmodifiable(await _loadPromptAssetCategories());
    _availableVibes = List.unmodifiable(await _loadVibes());
    _characterPreviewPaths = const {};
    _outfitPreviewPaths = const {};
    _artistChainPreviewPaths = const {};
    await _loadGlobalBlockWords();
    _assetsLoaded = true;
  }

  void _ensureTemporaryArtistChainFromScript(Script script) {
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    if (_availableArtistChains.isEmpty) {
      final temporaryChain = _temporaryArtistChain(script, parsedFrames);
      _availableArtistChains =
          temporaryChain == null ? const [] : [temporaryChain];
    }
  }

  ArtistChain? _temporaryArtistChain(Script script, List<ScriptFrame> frames) {
    final artists = _artistSourceLabels(frames);
    if (artists.isEmpty) {
      return null;
    }
    return ArtistChain(
      id: 'temp-artist-${_slug(script.name)}',
      name: '源画师串',
      prompt: artists.join(', '),
      tags: const ['script-recast-temporary'],
      source: const SourceRef(type: 'script_recast_temporary'),
      note: '从当前剧本临时提取，确认后再写入素材库。',
    );
  }

  CharacterEntry? _characterById(String id) {
    for (final character in _characters) {
      if (character.id == id) {
        return character;
      }
    }
    return null;
  }

  WorkspaceOutfit? _outfitById(CharacterEntry? character, String? outfitId) {
    if (character == null || outfitId == null) {
      return null;
    }
    for (final outfit in character.outfits) {
      if (outfit.id == outfitId) {
        return outfit;
      }
    }
    return null;
  }

  RoleAssembly _assemblyWithCharacter(
    RoleAssembly assembly,
    CharacterEntry? character,
    String? outfitId,
  ) {
    final outfit = _outfitById(character, outfitId);
    return assembly.copyWith(
      stages: [
        for (final stage in assembly.stages)
          _stageWithCharacterAndOutfit(stage, character, outfitId, outfit),
      ],
    );
  }

  RoleAssembly _assemblyWithTargetIds(
    RoleAssembly assembly, {
    required String targetCharacterId,
    String? targetOutfitId,
  }) {
    return assembly.copyWith(
      stages: [
        for (final stage in assembly.stages)
          stage.copyWith(
            targetCharacterId: targetCharacterId,
            targetUpperOutfitId: targetOutfitId,
            targetLowerOutfitId: targetOutfitId,
          ),
      ],
    );
  }

  RoleAssembly _assemblyWithOutfit(RoleAssembly assembly, String? outfitId) {
    return assembly.copyWith(
      stages: [
        for (final stage in assembly.stages) _stageWithOutfit(stage, outfitId),
      ],
    );
  }

  RoleAssembly _assemblyWithDroppedOutfit(
    RoleAssembly assembly, {
    required CharacterEntry character,
    required String outfitId,
    required WorkspaceOutfit outfit,
  }) {
    return assembly.copyWith(
      stages: [
        for (final stage in assembly.stages)
          _stageWithDroppedOutfit(
            stage,
            character: character,
            outfitId: outfitId,
            outfit: outfit,
          ),
      ],
    );
  }

  RoleAssemblyStage _stageWithCharacterAndOutfit(
    RoleAssemblyStage stage,
    CharacterEntry? character,
    String? outfitId,
    WorkspaceOutfit? outfit,
  ) {
    final resolvedParts = _resolvedCharacterOutfitParts(
      character: character,
      upperOutfit: outfit,
      lowerOutfit: outfit,
      includeUpper: true,
      includeLower: true,
    );
    final filledParts = _fillEmptyPromptParts(stage.manualParts, resolvedParts);
    final outfitIdentity = deriveSelectedOutfitIdentityPrompt(outfit, outfit);
    final characterChanged = stage.targetCharacterId != character?.id;
    final nextParts = characterChanged || outfitIdentity.trim().isNotEmpty
        ? filledParts.copyWith(identity: resolvedParts.identity)
        : filledParts;
    return stage.copyWith(
      targetCharacterId: character?.id,
      targetUpperOutfitId: outfitId,
      targetLowerOutfitId: outfitId,
      omittedParts: _omittedPartsAfterPartsFill(
        stage.omittedParts,
        nextParts,
        includeUpper: true,
        includeLower: true,
      ),
      preservedParts: _preservedPartsAfterPartsFill(
        stage.preservedParts,
        nextParts,
        includeUpper: true,
        includeLower: true,
      ),
      manualParts: nextParts,
    );
  }

  RoleAssemblyStage _stageWithDroppedOutfit(
    RoleAssemblyStage stage, {
    required CharacterEntry character,
    required String outfitId,
    required WorkspaceOutfit outfit,
  }) {
    final replacement = _resolvedCharacterOutfitParts(
      character: character,
      upperOutfit: outfit,
      lowerOutfit: outfit,
      includeUpper: true,
      includeLower: true,
    );
    final hasTargetCharacterParts = _stageHasTargetCharacterParts(stage);
    final nextParts = hasTargetCharacterParts
        ? stage.manualParts.copyWith(
            upperClothing: replacement.upperClothing,
            lowerClothing: replacement.lowerClothing,
          )
        : _replaceOutfitParts(
            stage.manualParts,
            replacement,
            includeUpper: true,
            includeLower: true,
          );
    final outfitIdentity = deriveOutfitIdentityPrompt(outfit);
    final resolvedParts = outfitIdentity.trim().isEmpty
        ? nextParts
        : nextParts.copyWith(
            identity: mergeBaseAndOutfitIdentity(
              nextParts.identity,
              outfitIdentity,
            ),
          );
    return stage.copyWith(
      targetCharacterId: character.id,
      targetUpperOutfitId: outfitId,
      targetLowerOutfitId: outfitId,
      omittedParts: _omittedPartsAfterPartsFill(
        stage.omittedParts,
        resolvedParts,
        includeUpper: true,
        includeLower: true,
      ),
      preservedParts: _preservedPartsAfterPartsFill(
        stage.preservedParts,
        resolvedParts,
        includeUpper: true,
        includeLower: true,
      ),
      manualParts: resolvedParts,
    );
  }

  bool _stageHasTargetCharacterParts(RoleAssemblyStage stage) {
    return _hasVisibleTargetPart(
          stage,
          RecastPromptPart.identity,
          stage.manualParts.identity,
        ) ||
        _hasVisibleTargetPart(
          stage,
          RecastPromptPart.upperBody,
          stage.manualParts.upperBody,
        ) ||
        _hasVisibleTargetPart(
          stage,
          RecastPromptPart.lowerBody,
          stage.manualParts.lowerBody,
        );
  }

  bool _hasVisibleTargetPart(
    RoleAssemblyStage stage,
    RecastPromptPart part,
    String value,
  ) {
    return value.trim().isNotEmpty && !stage.omittedParts.contains(part);
  }

  RoleAssemblyStage _stageWithOutfit(
    RoleAssemblyStage stage,
    String? outfitId,
  ) {
    final character = stage.targetCharacterId == null
        ? null
        : _characterById(stage.targetCharacterId!);
    final outfit = _outfitById(character, outfitId);
    final resolvedParts = outfit == null
        ? null
        : _resolvedCharacterOutfitParts(
            character: character,
            upperOutfit: outfit,
            lowerOutfit: outfit,
            includeUpper: true,
            includeLower: true,
          );
    final nextParts = resolvedParts == null
        ? stage.manualParts
        : _replaceOutfitParts(
            stage.manualParts,
            resolvedParts,
            includeUpper: true,
            includeLower: true,
          );
    final outfitIdentity = deriveSelectedOutfitIdentityPrompt(outfit, outfit);
    final resolvedNextParts = outfitIdentity.trim().isEmpty
        ? nextParts
        : nextParts.copyWith(
            identity: mergeBaseAndOutfitIdentity(
              nextParts.identity,
              outfitIdentity,
            ),
          );
    return stage.copyWith(
      targetUpperOutfitId: outfitId,
      targetLowerOutfitId: outfitId,
      omittedParts: _omittedPartsAfterPartsFill(
        stage.omittedParts,
        resolvedNextParts,
        includeUpper: true,
        includeLower: true,
      ),
      preservedParts: _preservedPartsAfterPartsFill(
        stage.preservedParts,
        resolvedNextParts,
        includeUpper: true,
        includeLower: true,
      ),
      manualParts: resolvedNextParts,
    );
  }

  RecastPromptParts _resolvedCharacterOutfitParts({
    required CharacterEntry? character,
    required WorkspaceOutfit? upperOutfit,
    required WorkspaceOutfit? lowerOutfit,
    required bool includeUpper,
    required bool includeLower,
  }) {
    final parts = RecastPromptParts(
      upperBody: includeUpper
          ? _firstNonEmptyPrompt([
              _joinPromptTags(upperOutfit?.partTags.upperBodyTags ?? const []),
              character?.traits.frontUpper ?? '',
            ])
          : '',
      lowerBody: includeLower
          ? _firstNonEmptyPrompt([
              _joinPromptTags(lowerOutfit?.partTags.lowerBodyTags ?? const []),
              character?.traits.frontLower ?? '',
            ])
          : '',
      upperClothing: includeUpper && upperOutfit != null
          ? _upperOutfitPrompt(upperOutfit)
          : '',
      lowerClothing: includeLower && lowerOutfit != null
          ? _lowerOutfitPrompt(lowerOutfit)
          : '',
    );
    if (character == null) {
      return parts;
    }
    final outfitIdentity = deriveSelectedOutfitIdentityPrompt(
      upperOutfit,
      lowerOutfit,
    );
    return parts.copyWith(
      identity: outfitIdentity.trim().isEmpty
          ? _characterIdentityPromptExcluding(character, parts)
          : mergeBaseAndOutfitIdentity(
              _characterIdentityPromptExcluding(character, parts),
              outfitIdentity,
            ),
    );
  }

  RecastPromptParts _fillEmptyOutfitParts(
    RecastPromptParts current,
    WorkspaceOutfit? outfit, {
    required bool includeUpper,
    required bool includeLower,
  }) {
    if (outfit == null) {
      return current;
    }
    return current.copyWith(
      upperBody: includeUpper
          ? _fillIfEmpty(
              current.upperBody,
              _joinPromptTags(outfit.partTags.upperBodyTags),
            )
          : current.upperBody,
      lowerBody: includeLower
          ? _fillIfEmpty(
              current.lowerBody,
              _joinPromptTags(outfit.partTags.lowerBodyTags),
            )
          : current.lowerBody,
      upperClothing: includeUpper
          ? _fillIfEmpty(current.upperClothing, _upperOutfitPrompt(outfit))
          : current.upperClothing,
      lowerClothing: includeLower
          ? _fillIfEmpty(current.lowerClothing, _lowerOutfitPrompt(outfit))
          : current.lowerClothing,
    );
  }

  String _characterIdentityPromptExcluding(
    CharacterEntry character,
    RecastPromptParts usedParts,
  ) {
    return deriveCharacterIdentityPromptExcluding(character, usedParts);
  }

  String _upperOutfitPrompt(WorkspaceOutfit outfit) {
    return _joinPromptTags(outfit.partTags.upperClothingTags);
  }

  String _lowerOutfitPrompt(WorkspaceOutfit outfit) {
    return _joinPromptTags(outfit.partTags.lowerClothingTags);
  }

  RecastPromptParts _replaceOutfitParts(
    RecastPromptParts current,
    RecastPromptParts replacement, {
    required bool includeUpper,
    required bool includeLower,
  }) {
    return current.copyWith(
      identity: _fillIfEmpty(current.identity, replacement.identity),
      upperBody: includeUpper ? replacement.upperBody : current.upperBody,
      lowerBody: includeLower ? replacement.lowerBody : current.lowerBody,
      upperClothing:
          includeUpper ? replacement.upperClothing : current.upperClothing,
      lowerClothing:
          includeLower ? replacement.lowerClothing : current.lowerClothing,
    );
  }

  String _fillIfEmpty(String current, String fallback) {
    return current.trim().isEmpty ? fallback : current;
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

  RecastPromptPart _recastPromptPartFor(StudioScriptRolePart part) {
    return switch (part) {
      StudioScriptRolePart.identity => RecastPromptPart.identity,
      StudioScriptRolePart.upperBody => RecastPromptPart.upperBody,
      StudioScriptRolePart.lowerBody => RecastPromptPart.lowerBody,
      StudioScriptRolePart.upperClothing => RecastPromptPart.upperClothing,
      StudioScriptRolePart.lowerClothing => RecastPromptPart.lowerClothing,
      StudioScriptRolePart.nonRole => throw StateError(
          'Non-role prompt tags do not map to recast output parts.',
        ),
    };
  }

  Set<RecastPromptPart> _omittedPartsAfterEdit(
    Set<RecastPromptPart> current,
    RecastPromptPart part,
  ) {
    if (!current.contains(part)) {
      return current;
    }
    final next = {...current}..remove(part);
    return Set.unmodifiable(next);
  }

  Set<RecastPromptPart> _preservedPartsAfterEdit(
    Set<RecastPromptPart> current,
    RecastPromptPart part,
    String value,
  ) {
    final next = {...current};
    if (value.trim().isEmpty) {
      next.add(part);
    } else {
      next.remove(part);
    }
    return Set.unmodifiable(next);
  }

  RecastPromptParts _promptPartsWithPartValue(
    RecastPromptParts parts,
    StudioScriptRolePart part,
    String value,
  ) {
    return switch (part) {
      StudioScriptRolePart.identity => parts.copyWith(identity: value),
      StudioScriptRolePart.upperBody => parts.copyWith(upperBody: value),
      StudioScriptRolePart.lowerBody => parts.copyWith(lowerBody: value),
      StudioScriptRolePart.upperClothing => parts.copyWith(
          upperClothing: value,
        ),
      StudioScriptRolePart.lowerClothing => parts.copyWith(
          lowerClothing: value,
        ),
      StudioScriptRolePart.nonRole => parts,
    };
  }

  String _promptPartValue(RecastPromptParts parts, StudioScriptRolePart part) {
    return switch (part) {
      StudioScriptRolePart.identity => parts.identity,
      StudioScriptRolePart.upperBody => parts.upperBody,
      StudioScriptRolePart.lowerBody => parts.lowerBody,
      StudioScriptRolePart.upperClothing => parts.upperClothing,
      StudioScriptRolePart.lowerClothing => parts.lowerClothing,
      StudioScriptRolePart.nonRole => '',
    };
  }

  Set<RecastPromptPart> _omittedPartsAfterPartsFill(
    Set<RecastPromptPart> current,
    RecastPromptParts parts, {
    required bool includeUpper,
    required bool includeLower,
  }) {
    var next = current;
    next = _omittedPartsAfterPartFill(
      next,
      RecastPromptPart.identity,
      parts.identity,
    );
    next = _omittedPartsAfterPartFill(
      next,
      RecastPromptPart.upperBody,
      parts.upperBody,
    );
    next = _omittedPartsAfterPartFill(
      next,
      RecastPromptPart.lowerBody,
      parts.lowerBody,
    );
    if (includeUpper) {
      next = _omittedPartsAfterPartFill(
        next,
        RecastPromptPart.upperClothing,
        parts.upperClothing,
      );
    }
    if (includeLower) {
      next = _omittedPartsAfterPartFill(
        next,
        RecastPromptPart.lowerClothing,
        parts.lowerClothing,
      );
    }
    return next;
  }

  Set<RecastPromptPart> _preservedPartsAfterPartsFill(
    Set<RecastPromptPart> current,
    RecastPromptParts parts, {
    required bool includeUpper,
    required bool includeLower,
  }) {
    var next = current;
    next = _preservedPartsAfterPartFill(
      next,
      RecastPromptPart.identity,
      parts.identity,
    );
    next = _preservedPartsAfterPartFill(
      next,
      RecastPromptPart.upperBody,
      parts.upperBody,
    );
    next = _preservedPartsAfterPartFill(
      next,
      RecastPromptPart.lowerBody,
      parts.lowerBody,
    );
    if (includeUpper) {
      next = _preservedPartsAfterPartFill(
        next,
        RecastPromptPart.upperClothing,
        parts.upperClothing,
      );
    }
    if (includeLower) {
      next = _preservedPartsAfterPartFill(
        next,
        RecastPromptPart.lowerClothing,
        parts.lowerClothing,
      );
    }
    return next;
  }

  Set<RecastPromptPart> _omittedPartsAfterPartFill(
    Set<RecastPromptPart> current,
    RecastPromptPart part,
    String value,
  ) {
    if (value.trim().isEmpty || !current.contains(part)) {
      return current;
    }
    final next = {...current}..remove(part);
    return Set.unmodifiable(next);
  }

  Set<RecastPromptPart> _preservedPartsAfterPartFill(
    Set<RecastPromptPart> current,
    RecastPromptPart part,
    String value,
  ) {
    if (value.trim().isEmpty || !current.contains(part)) {
      return current;
    }
    final next = {...current}..remove(part);
    return Set.unmodifiable(next);
  }

  String _roleReplacementCandidatePrompt(
    CharacterEntry character, {
    String? outfitId,
  }) {
    final selectedOutfit = _outfitById(
      character,
      outfitId ?? character.defaultOutfitId,
    );
    final outfits = selectedOutfit == null
        ? outfitId == null &&
                character.defaultOutfitId == null &&
                character.outfits.length == 1
            ? <WorkspaceOutfit>[character.outfits.single]
            : const <WorkspaceOutfit>[]
        : <WorkspaceOutfit>[selectedOutfit];
    return _joinPromptTags([
      ...character.anchorTags,
      ...character.identityTags,
      ..._viewVariantPromptTerms(character.traits),
      for (final outfit in outfits) ..._outfitCandidatePromptTerms(outfit),
    ]);
  }

  Iterable<String> _outfitCandidatePromptTerms(WorkspaceOutfit outfit) sync* {
    yield* _viewVariantPromptTerms(outfit.tags);
    yield* outfit.partTags.upperBodyTags;
    yield* outfit.partTags.upperClothingTags;
    yield* outfit.partTags.lowerBodyTags;
    yield* outfit.partTags.lowerClothingTags;
    yield* outfit.partTags.weaponTags;
  }

  Iterable<String> _viewVariantPromptTerms(ViewVariantTexts texts) sync* {
    yield texts.frontFull;
    if (texts.frontCowboy != null) yield texts.frontCowboy!;
    if (texts.frontUpper != null) yield texts.frontUpper!;
    if (texts.frontLower != null) yield texts.frontLower!;
    if (texts.backFull != null) yield texts.backFull!;
    if (texts.backCowboy != null) yield texts.backCowboy!;
    if (texts.backUpper != null) yield texts.backUpper!;
    if (texts.backLower != null) yield texts.backLower!;
  }

  String _joinPromptTags(Iterable<String> tags) {
    return _uniqueTags([
      for (final tag in tags) ..._splitDisplayTags(tag),
    ]).join(', ');
  }

  RecastScriptCache _cacheWithScopedScriptMappingVariants(
    RecastScriptCache cache,
  ) {
    final scopedVariants = [
      for (final variant in cache.mappingVariants)
        if (_isAllowedScriptMappingVariant(variant)) variant,
    ];
    final activeVariantId = scopedVariants.any(
      (variant) => variant.id == cache.activeMappingVariantId,
    )
        ? cache.activeMappingVariantId
        : null;
    if (scopedVariants.length == cache.mappingVariants.length &&
        activeVariantId == cache.activeMappingVariantId) {
      return cache;
    }
    return cache.copyWith(
      mappingVariants: List.unmodifiable(scopedVariants),
      activeMappingVariantId: activeVariantId,
    );
  }

  Future<void> _loadGlobalBlockWords() async {
    final loader = loadFilterRules;
    if (loader == null) {
      _applyGlobalBlockWords('');
      _applyGlobalPromptPrefix('');
      return;
    }
    final config = FilterRuleConfig.fromMap(await loader());
    _filterRuleConfig = config;
    _applyGlobalBlockWords(config.deleteKeywords);
    _applyGlobalPromptPrefix(config.globalPromptPrefix);
  }

  void _applyGlobalBlockWords(String value) {
    final normalized = _normalizeBlockWords(value);
    globalBlockWords = normalized;
    globalBlockWordsStatus = normalized.isEmpty
        ? '未设置全局屏蔽词'
        : '全局屏蔽词 ${_blockWordCount(normalized)} 个';
  }

  void _applyGlobalPromptPrefix(String value) {
    globalPromptPrefix = value.trim();
    _refreshPreview();
  }

  RecastScriptCache _cacheDraftForScript(
    Script script, {
    required RecastMapping mapping,
    DateTime? updatedAt,
  }) {
    final cacheMapping = _mappingForCurrentScript(script, mapping);
    return RecastScriptCache(
      scriptId: script.id,
      scriptName: script.name,
      sourceRootPath: script.rootPath,
      sourceFingerprint: cacheRestoreService.sourceFingerprint(script),
      sourceContentFingerprint:
          cacheRestoreService.sourceContentFingerprint(script),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      mapping: cacheMapping,
      aiRoleExtraction: aiRoleExtraction,
      aiRoleExtractionChunks: aiRoleExtractionChunks,
      aiRoleExtractionDraftCollapsed: _aiRoleExtractionDraftDismissed,
      aiRoleExtractionFinalized: _aiRoleExtractionFinalized,
      scriptBlockWords: scriptBlockWords,
      scriptSnapshot: script.toJson(),
      knowledgeSnapshot: const {},
      mappingVariants: _mappingVariants,
      activeMappingVariantId: _activeMappingVariantId,
    );
  }

  Future<void> _saveCurrentStateForScript(Script script) async {
    final mapping = _mapping;
    if (mapping == null) {
      cacheStatus = '缓存未配置';
      return;
    }
    await _saveCache(
      script,
      cache: _cacheDraftForScript(script, mapping: mapping),
    );
  }

  Future<void> _saveCache(
    Script script, {
    required RecastScriptCache cache,
  }) async {
    final singleSaver = saveRecastCache;
    if (singleSaver != null) {
      final existingExact = await _loadExistingExactCacheForSave(
        script: script,
        sourceFingerprint: cache.sourceFingerprint,
      );
      final mergedCache = _cacheWithScopedScriptMappingVariants(
        cacheRestoreService.cachePreservingExistingAiDraft(
          cache,
          existingExact,
        ),
      );
      await singleSaver(
        mergedCache,
      );
      cacheStatus = '已保存本剧本缓存';
      return;
    }

    final saver = saveRecastCaches;
    final loader = loadRecastCaches;
    if (saver == null || loader == null) {
      cacheStatus = '缓存未配置';
      return;
    }
    final existing = await loader();
    final cacheToSave = _cacheWithScopedScriptMappingVariants(
      cacheRestoreService.cachePreservingExistingAiDraft(
        cache,
        cacheRestoreService.bestExactCacheForScript(
          existing,
          script: script,
          sourceFingerprint: cache.sourceFingerprint,
        ),
      ),
    );
    await saver([
      for (final entry in existing)
        if (!cacheRestoreService.cacheBelongsToScript(entry, script)) entry,
      cacheToSave,
    ]);
    cacheStatus = '已保存本剧本缓存';
  }

  RecastMapping _mappingForCurrentScript(Script script, RecastMapping mapping) {
    final mappingId = 'mapping-${script.id}';
    if (mapping.scriptId == script.id && mapping.id == mappingId) {
      return mapping;
    }
    return mapping.copyWith(id: mappingId, scriptId: script.id);
  }

  Future<RecastScriptCache?> _loadExistingExactCacheForSave({
    required Script script,
    required String sourceFingerprint,
  }) async {
    final candidates = <RecastScriptCache>[];
    final targetedLoader = loadRecastCacheByScriptId;
    if (targetedLoader != null) {
      final cache = await targetedLoader(script.id);
      if (cache != null &&
          cacheRestoreService.cacheBelongsToScript(cache, script) &&
          cache.sourceFingerprint == sourceFingerprint) {
        candidates.add(cache);
      }
      // Keep single-script saves on the single-file cache path.
      return cacheRestoreService.bestExactCache(candidates);
    }
    final loader = loadRecastCaches;
    if (loader != null) {
      try {
        candidates.addAll([
          for (final cache in await loader())
            if (cacheRestoreService.cacheBelongsToScript(cache, script) &&
                cache.sourceFingerprint == sourceFingerprint)
              cache,
        ]);
      } catch (_) {
        // Existing-cache lookup is only a preservation guard.
      }
    }
    return cacheRestoreService.bestExactCache(candidates);
  }

  Future<void> _saveCurrentCache() async {
    _cacheSaveDebounceTimer?.cancel();
    _cacheSaveDebounceTimer = null;
    await _enqueueCurrentCacheSave();
  }

  Future<void> _saveParsedSnapshotAfterImportIfUseful(
    bool directoryContainsPng, {
    bool Function()? shouldContinue,
  }) async {
    final canSaveCache = saveRecastCache != null ||
        (loadRecastCaches != null && saveRecastCaches != null);
    final script = _script;
    if (!directoryContainsPng ||
        !canSaveCache ||
        script == null ||
        script.frames.isEmpty) {
      return;
    }
    if (shouldContinue?.call() == false) return;
    _setImportProgress('正在保存解析快照...');
    try {
      await _saveCurrentCache();
      if (shouldContinue?.call() == false) return;
    } catch (error, stackTrace) {
      debugPrint('Failed to save parsed script snapshot: $error\n$stackTrace');
    }
  }

  void _scheduleCurrentCacheSave() {
    final canSaveCache = saveRecastCache != null ||
        (loadRecastCaches != null && saveRecastCaches != null);
    if (_script == null || !canSaveCache) {
      return;
    }
    _cacheSaveDebounceTimer?.cancel();
    _cacheSaveDebounceTimer = Timer(const Duration(milliseconds: 450), () {
      _cacheSaveDebounceTimer = null;
      unawaited(_enqueueCurrentCacheSave());
    });
  }

  Future<void> _enqueueCurrentCacheSave() async {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      return;
    }
    final cacheSnapshot = _cacheDraftForScript(
      script,
      mapping: mapping,
    );
    final previous = _cacheSaveTail;
    final next = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // A failed earlier save must not permanently block later saves.
        }
      }
      await _saveCache(script, cache: cacheSnapshot);
    }();
    _cacheSaveTail = next;
    try {
      await next;
    } finally {
      if (identical(_cacheSaveTail, next)) {
        _cacheSaveTail = null;
      }
    }
  }

  Future<void> _saveClassificationCacheBestEffort() async {
    final saver = saveClassificationCache;
    if (saver == null) {
      return;
    }
    try {
      await saver(classificationCache);
    } catch (_) {
      // Manual category changes are already reflected in memory; persistence is
      // best-effort so the review UI stays responsive.
    }
  }

  _AiRoleDraftParts? _aiExtractionStageParts({
    required ScriptAiRoleExtraction extraction,
    required String sourceRoleId,
    required String stageId,
  }) {
    for (final role in extraction.roles) {
      if (role.sourceRoleId != sourceRoleId) {
        continue;
      }
      for (final stage in role.stages) {
        if (stage.stageId == stageId) {
          return _AiRoleDraftParts.fromStage(stage);
        }
      }
    }
    return null;
  }

  void _recordManualRoleFieldOverride({
    required _AiRoleDraftParts beforeParts,
    required _AiRoleDraftParts afterParts,
    required StudioScriptRolePart editedPart,
  }) {
    final before = _tagMapForText(beforeParts.textFor(editedPart));
    final after = _tagMapForText(afterParts.textFor(editedPart));
    var changed = false;

    for (final entry in after.entries) {
      if (before.containsKey(entry.key)) {
        continue;
      }
      changed = _setManualRoleClassification(
            entry.value,
            _promptCategoryForRolePart(editedPart),
            source: editedPart == StudioScriptRolePart.nonRole
                ? 'manual-role-omit'
                : 'manual-role-field',
          ) ||
          changed;
    }

    for (final entry in before.entries) {
      if (after.containsKey(entry.key) || afterParts.containsTag(entry.value)) {
        continue;
      }
      changed = _setManualRoleClassification(
            entry.value,
            PromptTagCategory.other,
            source: 'manual-role-omit',
          ) ||
          changed;
    }

    if (changed) {
      unawaited(_saveClassificationCacheBestEffort());
    }
  }

  bool _setManualRoleClassification(
    String tag,
    PromptTagCategory category, {
    required String source,
  }) {
    final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
    if (clean.isEmpty) {
      return false;
    }
    final current = classificationCache.entryFor(clean);
    if (current != null &&
        current.category == category &&
        current.source == source) {
      return false;
    }
    classificationCache.setCategory(clean, category, source: source);
    return true;
  }

  RecastPromptParts _combinedStageParts(RoleAssemblyStage stage) {
    return _combinePromptParts(stage.sourceParts, stage.manualParts);
  }

  RecastPromptParts _combinePromptParts(
    RecastPromptParts left,
    RecastPromptParts right,
  ) {
    return RecastPromptParts(
      identity: _joinPromptTags([left.identity, right.identity]),
      upperBody: _joinPromptTags([left.upperBody, right.upperBody]),
      lowerBody: _joinPromptTags([left.lowerBody, right.lowerBody]),
      upperClothing: _joinPromptTags([left.upperClothing, right.upperClothing]),
      lowerClothing: _joinPromptTags([left.lowerClothing, right.lowerClothing]),
    );
  }

  Map<String, String> _tagMapForText(String text) {
    final result = <String, String>{};
    for (final tag in PromptTagProcessor.splitWorkshopTags(text)) {
      final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
      final key = PromptTagProcessor.normalizeMatchKey(clean);
      if (key.isEmpty) {
        continue;
      }
      result.putIfAbsent(key, () => clean);
    }
    return result;
  }

  PromptTagCategory _promptCategoryForRolePart(StudioScriptRolePart part) {
    return switch (part) {
      StudioScriptRolePart.identity => PromptTagCategory.character,
      StudioScriptRolePart.upperBody => PromptTagCategory.upperBody,
      StudioScriptRolePart.lowerBody => PromptTagCategory.lowerBody,
      StudioScriptRolePart.upperClothing => PromptTagCategory.upperClothing,
      StudioScriptRolePart.lowerClothing => PromptTagCategory.lowerClothing,
      StudioScriptRolePart.nonRole => PromptTagCategory.other,
    };
  }

  StudioScriptRolePart? _rolePartForPromptCategory(PromptTagCategory category) {
    return switch (category) {
      PromptTagCategory.character => StudioScriptRolePart.identity,
      PromptTagCategory.upperBody => StudioScriptRolePart.upperBody,
      PromptTagCategory.lowerBody => StudioScriptRolePart.lowerBody,
      PromptTagCategory.upperClothing => StudioScriptRolePart.upperClothing,
      PromptTagCategory.lowerClothing => StudioScriptRolePart.lowerClothing,
      PromptTagCategory.accessory => StudioScriptRolePart.upperBody,
      PromptTagCategory.clothingState => StudioScriptRolePart.upperClothing,
      PromptTagCategory.clothing => StudioScriptRolePart.upperClothing,
      _ => null,
    };
  }

  bool get hasAiRoleExtractionCacheAdjustments {
    final extraction = aiRoleExtraction;
    if (!extraction.isReady || extraction.roles.isEmpty) {
      return false;
    }
    for (final role in extraction.roles) {
      for (final stage in role.stages) {
        final adjusted = _stageWithCacheAdjustment(stage);
        if (!_stageDraftEqual(stage, adjusted)) {
          return true;
        }
      }
    }
    return false;
  }

  PromptTagClassificationCacheEntry? manualRoleCacheEntryForTag(String tag) {
    return _manualRoleClassificationEntryFor(tag);
  }

  Future<void> applyAiRoleExtractionCacheAdjustment() async {
    final extraction = aiRoleExtraction;
    if (!extraction.isReady || extraction.roles.isEmpty) {
      return;
    }
    var changed = false;
    final roles = [
      for (final role in extraction.roles)
        ScriptAiExtractedRole(
          sourceRoleId: role.sourceRoleId,
          sourceKind: role.sourceKind,
          displayName: role.displayName,
          roleReason: role.roleReason,
          canonicalName: role.canonicalName,
          franchise: role.franchise,
          rawIdentityTags: role.rawIdentityTags,
          variantTags: role.variantTags,
          mergeWithRoleId: role.mergeWithRoleId,
          confidence: role.confidence,
          frameIndexes: role.frameIndexes,
          appearances: role.appearances,
          evidenceTerms: role.evidenceTerms,
          warnings: role.warnings,
          unassignedTerms: role.unassignedTerms,
          promptTerms: role.promptTerms,
          stages: List.unmodifiable([
            for (final stage in role.stages)
              (() {
                final adjusted = _stageWithCacheAdjustment(stage);
                if (!_stageDraftEqual(stage, adjusted)) {
                  changed = true;
                }
                return adjusted;
              })(),
          ]),
        ),
    ];
    if (!changed) {
      return;
    }
    aiRoleExtraction = ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: extraction.status,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      roles: List.unmodifiable(roles),
      artistChains: extraction.artistChains,
      strongFilterKeywords: extraction.strongFilterKeywords,
      attentionItems: extraction.attentionItems,
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      sceneTerms: extraction.sceneTerms,
      termCacheSuggestions: extraction.termCacheSuggestions,
      rawResponse: extraction.rawResponse,
    ).collapseEquivalentStages();
    aiRoleExtraction = _extractionWithVisibleRolePromptTerms(aiRoleExtraction);
    _aiRoleExtractionDraftDismissed = false;
    _aiRoleExtractionDraftSuppressed = false;
    _aiRoleExtractionFinalized = false;
    _refreshRecastPlan();
    await _saveCurrentCache();
    notifyListeners();
  }

  ScriptAiRoleExtraction _extractionWithVisibleRolePromptTerms(
    ScriptAiRoleExtraction extraction,
  ) {
    if (!extraction.isReady || extraction.roles.isEmpty) {
      return extraction;
    }
    var changed = false;
    final roles = [
      for (final role in extraction.roles)
        _roleWithVisiblePromptTerms(
          role,
          onChanged: () => changed = true,
        ),
    ];
    if (!changed) {
      return extraction;
    }
    return ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: extraction.status,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      roles: List.unmodifiable(roles),
      artistChains: extraction.artistChains,
      strongFilterKeywords: extraction.strongFilterKeywords,
      attentionItems: extraction.attentionItems,
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      sceneTerms: extraction.sceneTerms,
      termCacheSuggestions: extraction.termCacheSuggestions,
      rawResponse: extraction.rawResponse,
    );
  }

  ScriptAiExtractedRole _roleWithVisiblePromptTerms(
    ScriptAiExtractedRole role, {
    required VoidCallback onChanged,
  }) {
    final visibleTerms = _visibleRolePromptTerms(role);
    if (visibleTerms.isEmpty && role.stages.isEmpty) {
      return role;
    }

    final existingTermsByTextKey =
        <String, List<ScriptAiExtractedPromptTerm>>{};
    for (final term in role.promptTerms) {
      final textKey = _promptTermTextKey(term.text);
      if (textKey.isNotEmpty) {
        (existingTermsByTextKey[textKey] ??= []).add(term);
      }
    }

    final visibleTextKeys = <String>{};
    final seenKeys = <String>{};
    final nextTerms = <ScriptAiExtractedPromptTerm>[];

    bool addPromptTerm(ScriptAiExtractedPromptTerm term) {
      final key = _promptTermIdentityKey(term.category, term.text);
      if (key.isEmpty || !seenKeys.add(key)) {
        return false;
      }
      nextTerms.add(term);
      return true;
    }

    for (final term in visibleTerms) {
      final textKey = _promptTermTextKey(term.text);
      if (textKey.isNotEmpty) {
        visibleTextKeys.add(textKey);
      }
      final preferredExistingTerms = [
        for (final existing in existingTermsByTextKey[textKey] ?? const [])
          if (_shouldPreferExistingPromptTermForVisibleTerm(existing, term))
            existing,
      ];
      if (preferredExistingTerms.isNotEmpty) {
        for (final existing in preferredExistingTerms) {
          addPromptTerm(existing);
        }
      } else {
        addPromptTerm(term);
      }
    }

    for (final term in role.promptTerms) {
      final textKey = _promptTermTextKey(term.text);
      if (textKey.isNotEmpty && visibleTextKeys.contains(textKey)) {
        continue;
      }
      if (_isVisibleRoleStagePromptCategory(term.category)) {
        continue;
      }
      addPromptTerm(term);
    }
    if (_promptTermsEqual(role.promptTerms, nextTerms)) {
      return role;
    }
    onChanged();
    return ScriptAiExtractedRole(
      sourceRoleId: role.sourceRoleId,
      sourceKind: role.sourceKind,
      displayName: role.displayName,
      roleReason: role.roleReason,
      canonicalName: role.canonicalName,
      franchise: role.franchise,
      rawIdentityTags: role.rawIdentityTags,
      variantTags: role.variantTags,
      mergeWithRoleId: role.mergeWithRoleId,
      confidence: role.confidence,
      frameIndexes: role.frameIndexes,
      appearances: role.appearances,
      evidenceTerms: role.evidenceTerms,
      warnings: role.warnings,
      stages: role.stages,
      unassignedTerms: role.unassignedTerms,
      promptTerms: List.unmodifiable(nextTerms),
    );
  }

  List<ScriptAiExtractedPromptTerm> _visibleRolePromptTerms(
    ScriptAiExtractedRole role,
  ) {
    if (role.stages.isEmpty) {
      return List.unmodifiable([
        for (final term in role.promptTerms)
          if (term.text.trim().isNotEmpty) term,
      ]);
    }

    final existingByKey = <String, ScriptAiExtractedPromptTerm>{};
    for (final term in role.promptTerms) {
      final key = _promptTermIdentityKey(term.category, term.text);
      if (key.isNotEmpty && !existingByKey.containsKey(key)) {
        existingByKey[key] = term;
      }
    }

    final orderedKeys = <String>[];
    final accumulated = <String, ScriptAiExtractedPromptTerm>{};

    void addVisiblePart({
      required ScriptAiExtractedStage stage,
      required StudioScriptRolePart part,
      required String value,
    }) {
      final phrase = value.trim();
      if (phrase.isEmpty) {
        return;
      }
      final category = _promptCategoryForRolePart(part);
      final stageFrames = _normalizedPromptTermFrameIndexes(stage.frameIndexes);
      final sourceLocation = _visibleRolePromptSourceLocation(
        role: role,
        stage: stage,
        part: part,
      );
      for (final rawTag in _splitDisplayTags(value)) {
        final clean = _cleanDisplayTag(rawTag);
        final display = _displayTagPreservingWeights(rawTag);
        final key = _promptTermIdentityKey(category, clean);
        if (key.isEmpty) {
          continue;
        }
        final existing = existingByKey[key];
        final current = accumulated[key];
        final existingFrames = _normalizedPromptTermFrameIndexes(
          existing?.frameIndexes ?? const [],
        );
        final nextFrames = current == null
            ? (existingFrames.isNotEmpty ? existingFrames : stageFrames)
            : (existingFrames.isNotEmpty
                ? current.frameIndexes
                : _mergedFrameIndexes(current.frameIndexes, stageFrames));
        final existingText = existing?.text.trim() ?? '';
        final nextTerm = ScriptAiExtractedPromptTerm(
          id: existing?.id ??
              stableIdFromText(
                prefix: 'prompt-term',
                text:
                    '${role.sourceRoleId}|${stage.stageId}|${part.name}|$clean',
                label: clean,
              ),
          text: _promptTermTextPreservingWeight(existingText, display),
          category: category,
          sourcePhrase: existing?.sourcePhrase.trim().isNotEmpty == true
              ? existing!.sourcePhrase
              : phrase,
          sourceLocation: existing?.sourceLocation.trim().isNotEmpty == true
              ? existing!.sourceLocation
              : sourceLocation,
          frameIndexes: List.unmodifiable(nextFrames),
        );
        if (current == null) {
          orderedKeys.add(key);
        }
        accumulated[key] = nextTerm;
      }
    }

    for (final stage in role.stages) {
      addVisiblePart(
        stage: stage,
        part: StudioScriptRolePart.identity,
        value: stage.identity,
      );
      addVisiblePart(
        stage: stage,
        part: StudioScriptRolePart.upperBody,
        value: stage.upperBody,
      );
      addVisiblePart(
        stage: stage,
        part: StudioScriptRolePart.lowerBody,
        value: stage.lowerBody,
      );
      addVisiblePart(
        stage: stage,
        part: StudioScriptRolePart.upperClothing,
        value: stage.upperClothing,
      );
      addVisiblePart(
        stage: stage,
        part: StudioScriptRolePart.lowerClothing,
        value: stage.lowerClothing,
      );
    }

    return List.unmodifiable([
      for (final key in orderedKeys)
        if (accumulated[key] case final term?) term,
    ]);
  }

  String _visibleRolePromptSourceLocation({
    required ScriptAiExtractedRole role,
    required ScriptAiExtractedStage stage,
    required StudioScriptRolePart part,
  }) {
    final parts = <String>[
      if (role.sourceRoleId.trim().isNotEmpty) role.sourceRoleId.trim(),
      if (stage.stageId.trim().isNotEmpty) stage.stageId.trim(),
      part.name,
    ];
    return parts.join(' / ');
  }

  String _promptTermTextKey(String text) {
    return PromptTagProcessor.normalizeMatchKey(text);
  }

  String _promptTermIdentityKey(PromptTagCategory category, String text) {
    final key = PromptTagProcessor.normalizeMatchKey(text);
    if (key.isEmpty) {
      return '';
    }
    return '${category.name}|$key';
  }

  bool _shouldPreferExistingPromptTermForVisibleTerm(
    ScriptAiExtractedPromptTerm existing,
    ScriptAiExtractedPromptTerm visible,
  ) {
    if (existing.category == visible.category) {
      return false;
    }
    if (_isVisibleRoleStagePromptCategory(existing.category)) {
      return false;
    }
    if (existing.category == PromptTagCategory.clothing) {
      return false;
    }
    return true;
  }

  bool _isVisibleRoleStagePromptCategory(PromptTagCategory category) {
    return category == PromptTagCategory.character ||
        category == PromptTagCategory.upperBody ||
        category == PromptTagCategory.lowerBody ||
        category == PromptTagCategory.upperClothing ||
        category == PromptTagCategory.lowerClothing;
  }

  List<int> _mergedFrameIndexes(
    List<int> left,
    List<int> right,
  ) {
    return _normalizedPromptTermFrameIndexes([
      ...left,
      ...right,
    ]);
  }

  List<int> _normalizedPromptTermFrameIndexes(Iterable<int> frameIndexes) {
    final normalized = <int>{};
    for (final frameIndex in frameIndexes) {
      if (frameIndex >= 0) {
        normalized.add(frameIndex);
      }
    }
    return normalized.toList(growable: false)..sort();
  }

  bool _promptTermsEqual(
    List<ScriptAiExtractedPromptTerm> left,
    List<ScriptAiExtractedPromptTerm> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftTerm = left[index];
      final rightTerm = right[index];
      if (leftTerm.id != rightTerm.id ||
          leftTerm.text != rightTerm.text ||
          leftTerm.category != rightTerm.category ||
          leftTerm.sourcePhrase != rightTerm.sourcePhrase ||
          leftTerm.sourceLocation != rightTerm.sourceLocation ||
          !_intListsEqual(leftTerm.frameIndexes, rightTerm.frameIndexes)) {
        return false;
      }
    }
    return true;
  }

  bool _intListsEqual(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  ScriptAiRoleExtraction _extractionWithRecoveredReplacementTermsIfNeeded(
    ScriptAiRoleExtraction extraction,
  ) {
    if (!extraction.isReady || extraction.rawResponse.trim().isEmpty) {
      return extraction;
    }
    final needsRolePromptTerms = extraction.roles.any(
      (role) => role.promptTerms.isEmpty,
    );
    final needsSceneTerms = extraction.sceneTerms.isEmpty;
    if (!needsRolePromptTerms && !needsSceneTerms) {
      return extraction;
    }
    final reparsed =
        const ScriptAiRoleExtractionParser().parse(extraction.rawResponse);
    if (!reparsed.isReady) {
      return extraction;
    }

    var changed = false;
    final reparsedRolesBySourceId = <String, ScriptAiExtractedRole>{};
    for (final role in reparsed.roles) {
      final sourceRoleId = role.sourceRoleId.trim();
      if (sourceRoleId.isNotEmpty &&
          !reparsedRolesBySourceId.containsKey(sourceRoleId)) {
        reparsedRolesBySourceId[sourceRoleId] = role;
      }
    }

    final nextRoles = [
      for (final (index, role) in extraction.roles.indexed)
        () {
          if (role.promptTerms.isNotEmpty) {
            return role;
          }
          final recoveredRole = reparsedRolesBySourceId[role.sourceRoleId] ??
              (index < reparsed.roles.length ? reparsed.roles[index] : null);
          final recoveredPromptTerms = recoveredRole == null
              ? const <ScriptAiExtractedPromptTerm>[]
              : [
                  for (final term in recoveredRole.promptTerms)
                    if (term.text.trim().isNotEmpty) term,
                ];
          if (recoveredPromptTerms.isNotEmpty) {
            changed = true;
          }
          return ScriptAiExtractedRole(
            sourceRoleId: role.sourceRoleId,
            sourceKind: role.sourceKind,
            displayName: role.displayName,
            roleReason: role.roleReason,
            canonicalName: role.canonicalName,
            franchise: role.franchise,
            rawIdentityTags: role.rawIdentityTags,
            variantTags: role.variantTags,
            mergeWithRoleId: role.mergeWithRoleId,
            confidence: role.confidence,
            frameIndexes: role.frameIndexes,
            appearances: role.appearances,
            evidenceTerms: role.evidenceTerms,
            warnings: role.warnings,
            stages: role.stages,
            unassignedTerms: role.unassignedTerms,
            promptTerms: List.unmodifiable(recoveredPromptTerms),
          );
        }(),
    ];

    final nextSceneTerms = extraction.sceneTerms.isNotEmpty
        ? extraction.sceneTerms
        : [
            for (final term in reparsed.sceneTerms)
              if (term.text.trim().isNotEmpty) term,
          ];
    if (extraction.sceneTerms.isEmpty && nextSceneTerms.isNotEmpty) {
      changed = true;
    }
    if (!changed) {
      return extraction;
    }

    return ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: extraction.status,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      roles: List.unmodifiable(nextRoles),
      artistChains: extraction.artistChains,
      strongFilterKeywords: extraction.strongFilterKeywords,
      attentionItems: extraction.attentionItems,
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      sceneTerms: List.unmodifiable(nextSceneTerms),
      termCacheSuggestions: extraction.termCacheSuggestions,
      rawResponse: extraction.rawResponse,
    );
  }

  ScriptAiRoleExtraction _roleExtractionWithMaterializedNonRoleFields({
    required ScriptAiRoleExtraction extraction,
    required Script script,
  }) {
    final recoveredExtraction =
        _extractionWithRecoveredReplacementTermsIfNeeded(extraction);
    if (!recoveredExtraction.isReady || recoveredExtraction.roles.isEmpty) {
      return recoveredExtraction;
    }
    var changed = false;
    final roles = [
      for (final role in recoveredExtraction.roles)
        ScriptAiExtractedRole(
          sourceRoleId: role.sourceRoleId,
          sourceKind: role.sourceKind,
          displayName: role.displayName,
          roleReason: role.roleReason,
          canonicalName: role.canonicalName,
          franchise: role.franchise,
          rawIdentityTags: role.rawIdentityTags,
          variantTags: role.variantTags,
          mergeWithRoleId: role.mergeWithRoleId,
          confidence: role.confidence,
          frameIndexes: role.frameIndexes,
          appearances: role.appearances,
          evidenceTerms: role.evidenceTerms,
          warnings: role.warnings,
          unassignedTerms: role.unassignedTerms,
          promptTerms: role.promptTerms,
          stages: List.unmodifiable([
            for (final stage in role.stages)
              _stageWithMaterializedNonRole(
                stage: stage,
                script: script,
                role: role,
                onChanged: () => changed = true,
              ),
          ]),
        ),
    ];
    if (!changed) {
      return _extractionWithVisibleRolePromptTerms(
        recoveredExtraction.collapseEquivalentStages(),
      );
    }
    return _extractionWithVisibleRolePromptTerms(
      ScriptAiRoleExtraction(
        schemaVersion: recoveredExtraction.schemaVersion,
        status: recoveredExtraction.status,
        chunkId: recoveredExtraction.chunkId,
        confidence: recoveredExtraction.confidence,
        roles: List.unmodifiable(roles),
        artistChains: recoveredExtraction.artistChains,
        strongFilterKeywords: recoveredExtraction.strongFilterKeywords,
        attentionItems: recoveredExtraction.attentionItems,
        unassignedTerms: recoveredExtraction.unassignedTerms,
        evidenceRequests: recoveredExtraction.evidenceRequests,
        sceneTerms: recoveredExtraction.sceneTerms,
        termCacheSuggestions: recoveredExtraction.termCacheSuggestions,
        rawResponse: recoveredExtraction.rawResponse,
      ).collapseEquivalentStages(),
    );
  }

  ScriptAiExtractedStage _stageWithMaterializedNonRole({
    required ScriptAiExtractedStage stage,
    required Script script,
    required ScriptAiExtractedRole role,
    required VoidCallback onChanged,
  }) {
    final visible = _AiRoleDraftParts.fromStage(stage);
    var upperBody = _sanitizeAutoMaterializedRoleField(stage.upperBody);
    var lowerBody = _sanitizeAutoMaterializedRoleField(stage.lowerBody);
    var upperClothing = _sanitizeAutoMaterializedRoleField(stage.upperClothing);
    var lowerClothing = _sanitizeAutoMaterializedRoleField(stage.lowerClothing);
    final aiProvidedParts = RecastPromptParts(
      upperBody: upperBody,
      lowerBody: lowerBody,
      upperClothing: upperClothing,
      lowerClothing: lowerClothing,
    );
    final evidenceTerms = [
      for (final term in stage.evidenceTerms)
        if (!_isSuppressedAutoPendingRoleTag(term)) term,
    ];
    final nonRoleTerms = <String>[];

    void routeCandidate(String tag) {
      final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
      if (clean.isEmpty || _isSuppressedAutoPendingRoleTag(clean)) {
        return;
      }
      final rolePart = _autoMaterializedRolePartForTag(clean);
      switch (rolePart) {
        case StudioScriptRolePart.upperClothing:
          upperClothing = _joinPromptTags([upperClothing, clean]);
          return;
        case StudioScriptRolePart.lowerClothing:
          lowerClothing = _joinPromptTags([lowerClothing, clean]);
          return;
        case null:
          if (_shouldAutoMaterializePendingTag(clean)) {
            nonRoleTerms.add(clean);
          }
          return;
        default:
          return;
      }
    }

    for (final tag in PromptTagProcessor.splitWorkshopTags(stage.nonRole)) {
      routeCandidate(tag);
    }
    if (!stage.nonRoleMaterialized) {
      for (final tag in _stageFramePositiveTags(
        script: script,
        frameIndexes: stage.frameIndexes,
        role: role,
        stage: stage,
        excluded: visible,
      )) {
        routeCandidate(tag);
      }
    }
    upperClothing = _normalizeAutoUpperClothingOrder(upperClothing);
    final supported = _stageStablePartsSupportedByFrameEvidence(
      script: script,
      role: role,
      stage: stage,
      parts: RecastPromptParts(
        identity: stage.identity,
        upperBody: upperBody,
        lowerBody: lowerBody,
        upperClothing: upperClothing,
        lowerClothing: lowerClothing,
      ),
      protectedParts: aiProvidedParts,
    );
    upperBody = supported.parts.upperBody;
    lowerBody = supported.parts.lowerBody;
    upperClothing = supported.parts.upperClothing;
    lowerClothing = supported.parts.lowerClothing;
    nonRoleTerms.addAll(supported.demotedTerms);
    final nonRole = _joinPromptTags(nonRoleTerms);
    final changed = upperBody != stage.upperBody ||
        lowerBody != stage.lowerBody ||
        upperClothing != stage.upperClothing ||
        lowerClothing != stage.lowerClothing ||
        nonRole != stage.nonRole ||
        !stage.nonRoleMaterialized ||
        evidenceTerms.length != stage.evidenceTerms.length;
    if (!changed) {
      return stage;
    }
    onChanged();
    return ScriptAiExtractedStage(
      stageId: stage.stageId,
      label: stage.label,
      appearanceGroupId: stage.appearanceGroupId,
      mergeWithStageIds: stage.mergeWithStageIds,
      fieldReasons: stage.fieldReasons,
      confidence: stage.confidence,
      frameIndexes: stage.frameIndexes,
      identity: stage.identity,
      upperBody: upperBody,
      lowerBody: lowerBody,
      upperClothing: upperClothing,
      lowerClothing: lowerClothing,
      nonRole: nonRole,
      nonRoleMaterialized: true,
      evidenceTerms: List.unmodifiable(evidenceTerms),
      missingFields: stage.missingFields,
      warnings: stage.warnings,
    );
  }

  String _sanitizeAutoMaterializedRoleField(String value) {
    return _joinPromptTags([
      for (final tag in PromptTagProcessor.splitWorkshopTags(value))
        if (!_isSuppressedAutoPendingRoleTag(tag)) tag,
    ]);
  }

  String _normalizeAutoUpperClothingOrder(String value) {
    final base = <String>[];
    final details = <String>[];
    for (final tag in PromptTagProcessor.splitWorkshopTags(value)) {
      final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
      if (clean.isEmpty) {
        continue;
      }
      if (_isUpperClothingDetailTag(clean)) {
        details.add(clean);
      } else {
        base.add(clean);
      }
    }
    return _joinPromptTags([...base, ...details]);
  }

  bool _isUpperClothingDetailTag(String tag) {
    final normalized = PromptTagProcessor.normalizeMatchKey(tag);
    return normalized.contains('sleeve') || normalized.contains('glove');
  }

  List<String> _stageFramePositiveTags({
    required Script script,
    required List<int> frameIndexes,
    required ScriptAiExtractedRole role,
    required ScriptAiExtractedStage stage,
    required _AiRoleDraftParts excluded,
  }) {
    final wanted = frameIndexes.toSet();
    final seen = <String>{};
    final result = <String>[];
    for (final frame in script.frames) {
      if (frame.parseStatus != ScriptFrameParseStatus.parsed ||
          !wanted.contains(frame.index)) {
        continue;
      }
      final captions = _positiveCaptionsForAiRoleStageFrame(
        frame: frame,
        role: role,
        stage: stage,
      );
      for (final caption in captions) {
        for (final rawTag in PromptTagProcessor.splitWorkshopTags(caption)) {
          final clean = PromptTagProcessor.cleanTagDisplay(rawTag).trim();
          final key = PromptTagProcessor.normalizeMatchKey(clean);
          if (key.isEmpty || excluded.containsTag(clean) || !seen.add(key)) {
            continue;
          }
          result.add(clean);
        }
      }
    }
    return List.unmodifiable(result);
  }

  ({RecastPromptParts parts, List<String> demotedTerms})
      _stageStablePartsSupportedByFrameEvidence({
    required Script script,
    required ScriptAiExtractedRole role,
    required ScriptAiExtractedStage stage,
    required RecastPromptParts parts,
    required RecastPromptParts protectedParts,
  }) {
    final frameIndexes = stage.frameIndexes.toSet();
    if (frameIndexes.isEmpty) {
      return (parts: parts, demotedTerms: const []);
    }
    final evidenceByFrame = <Map<String, String>>[];
    for (final frame in script.frames) {
      if (frame.parseStatus != ScriptFrameParseStatus.parsed ||
          !frameIndexes.contains(frame.index)) {
        continue;
      }
      final captions = _positiveCaptionsForAiRoleStageFrame(
        frame: frame,
        role: role,
        stage: stage,
      );
      if (captions.isEmpty) {
        return (parts: parts, demotedTerms: const []);
      }
      evidenceByFrame.add(_evidenceTagsByKey(captions));
    }
    if (evidenceByFrame.isEmpty) {
      return (parts: parts, demotedTerms: const []);
    }

    final demotedTerms = <String>[];
    String stableField(String value, String protectedValue) {
      final protectedKeys = {
        for (final rawTerm in PromptTagProcessor.splitWorkshopTags(
          protectedValue,
        ))
          PromptTagProcessor.normalizeMatchKey(
            PromptTagProcessor.cleanTagDisplay(rawTerm),
          ),
      }..remove('');
      final kept = <String>[];
      for (final rawTerm in PromptTagProcessor.splitWorkshopTags(value)) {
        final clean = PromptTagProcessor.cleanTagDisplay(rawTerm).trim();
        if (clean.isEmpty) {
          continue;
        }
        final key = PromptTagProcessor.normalizeMatchKey(clean);
        if (protectedKeys.contains(key)) {
          kept.add(clean);
          continue;
        }
        final supported = evidenceByFrame.every(
          (evidence) => _supportedEvidenceTagForTerm(clean, evidence) != null,
        );
        if (supported) {
          kept.add(clean);
        } else {
          demotedTerms.add(clean);
        }
      }
      return _joinPromptTags(kept);
    }

    final nextParts = parts.copyWith(
      upperBody: stableField(parts.upperBody, protectedParts.upperBody),
      lowerBody: stableField(parts.lowerBody, protectedParts.lowerBody),
      upperClothing: stableField(
        parts.upperClothing,
        protectedParts.upperClothing,
      ),
      lowerClothing: stableField(
        parts.lowerClothing,
        protectedParts.lowerClothing,
      ),
    );
    return (parts: nextParts, demotedTerms: List.unmodifiable(demotedTerms));
  }

  StudioScriptRolePart? _autoMaterializedRolePartForTag(String tag) {
    final category = PromptTagClassifier.classify(
      tag,
      cache: classificationCache,
    ).category;
    return switch (category) {
      PromptTagCategory.upperClothing ||
      PromptTagCategory.clothingState ||
      PromptTagCategory.clothing =>
        StudioScriptRolePart.upperClothing,
      PromptTagCategory.lowerClothing => StudioScriptRolePart.lowerClothing,
      _ => null,
    };
  }

  bool _shouldAutoMaterializePendingTag(String tag) {
    if (_isSuppressedAutoPendingRoleTag(tag)) {
      return false;
    }
    if (_isAllowedAutoPendingExpressionTag(tag)) {
      return true;
    }
    final category = PromptTagClassifier.classify(
      tag,
      cache: classificationCache,
    ).category;
    return switch (category) {
      PromptTagCategory.action ||
      PromptTagCategory.scene ||
      PromptTagCategory.camera =>
        true,
      _ => false,
    };
  }

  bool _isAllowedAutoPendingExpressionTag(String tag) {
    final normalized = PromptTagProcessor.normalizeMatchKey(tag);
    return normalized == 'smile' || normalized == 'smiling';
  }

  bool _isSuppressedAutoPendingRoleTag(String tag) {
    final normalized = PromptTagProcessor.normalizeMatchKey(
      tag,
    ).replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return true;
    }
    if (_isStandaloneBodyPartAutoPendingTag(normalized)) {
      return true;
    }
    return RegExp(
      r'(^|[^a-z0-9])('
      r'pussy|penis|vaginal|anal|ass|butt|nipples?|areola|cleft of venus|'
      r'cum|semen|orgasm|ejaculat(?:e|ing|ion)|saliva|bukkake|'
      r'sex|intercourse|masturbat(?:e|ing|ion)|fellatio|paizuri|gangbang|'
      r'fingering|penetrat(?:e|ing|ion)|spread legs|legs spread|'
      r'wet|wet hair|sweaty|sweat|stained|torn|ripped|damaged|'
      r'nude|naked|topless|open shirt|open clothes|clothes lift|'
      r'clothes pull|clothes tug|undressing|taking off|panties aside|'
      r'no panties|panties around one leg'
      r')([^a-z0-9]|$)',
    ).hasMatch(normalized);
  }

  bool _isStandaloneBodyPartAutoPendingTag(String normalized) {
    const standaloneBodyParts = {
      'arm',
      'arms',
      'hand',
      'hands',
      'wrist',
      'wrists',
      'torso',
      'shoulder',
      'shoulders',
      'breast',
      'breasts',
      'body',
      'navel',
      'stomach',
      'leg',
      'legs',
      'thigh',
      'thighs',
      'foot',
      'feet',
      'hip',
      'hips',
      'tail',
    };
    return standaloneBodyParts.contains(normalized);
  }

  List<String> _positiveCaptionsForSourceRole(
    ScriptFrame frame,
    String sourceRoleId,
  ) {
    final slotIndex = _slotIndexForRole(sourceRoleId);
    if (slotIndex != null) {
      if (slotIndex < 0 || slotIndex >= frame.parsed.charCaptions.length) {
        return const [];
      }
      return [frame.parsed.charCaptions[slotIndex]];
    }

    if (!_isBaseSourceRoleId(sourceRoleId)) {
      return const [];
    }
    return [frame.parsed.baseCaption];
  }

  List<String> _positiveCaptionsForAiRoleStageFrame({
    required ScriptFrame frame,
    required ScriptAiExtractedRole role,
    required ScriptAiExtractedStage stage,
  }) {
    final captions = <String>[];
    final seen = <String>{};
    void add(String value) {
      if (value.trim().isEmpty || !seen.add(value)) {
        return;
      }
      captions.add(value);
    }

    for (final appearance in role.appearances) {
      if (appearance.frameIndexes.isNotEmpty &&
          !appearance.frameIndexes.contains(frame.index)) {
        continue;
      }
      for (final caption in _captionsForSourceRef(
        frame: frame,
        sourceId: appearance.sourceId,
        sourceKind: appearance.sourceKind,
      )) {
        add(caption);
      }
    }
    if (captions.isNotEmpty) {
      return List.unmodifiable(captions);
    }

    for (final caption in _positiveCaptionsForSourceRole(
      frame,
      role.sourceRoleId,
    )) {
      add(caption);
    }
    if (captions.isNotEmpty) {
      return List.unmodifiable(captions);
    }

    return _captionsMatchingIdentity(
      frame: frame,
      identityTexts: [role.displayName, role.canonicalName, stage.identity],
    );
  }

  List<String> _captionsForSourceRef({
    required ScriptFrame frame,
    required String sourceId,
    required String sourceKind,
  }) {
    final sourceIdKey = sourceId.trim().toLowerCase();
    final sourceKindKey = sourceKind.trim().toLowerCase();
    final slotIndex = _slotIndexForRole(sourceIdKey);
    if (slotIndex != null) {
      if (slotIndex < 0 || slotIndex >= frame.parsed.charCaptions.length) {
        return const [];
      }
      return [frame.parsed.charCaptions[slotIndex]];
    }
    if (_isBaseSourceRoleId(sourceIdKey) ||
        _isBaseSourceRoleId(sourceKindKey)) {
      return [frame.parsed.baseCaption];
    }
    return const [];
  }

  List<String> _captionsMatchingIdentity({
    required ScriptFrame frame,
    required Iterable<String> identityTexts,
  }) {
    final identityKeys = _identityKeysForTexts(identityTexts);
    if (identityKeys.isEmpty) {
      return const [];
    }
    final scored = <({String caption, int score})>[];
    for (final caption in frame.parsed.charCaptions) {
      final keys = _evidenceTagsByKey([caption]).keys.toSet();
      var score = 0;
      for (final identityKey in identityKeys) {
        if (keys.contains(identityKey) ||
            (identityKey.length > 3 &&
                keys.any(
                  (key) =>
                      key.contains(identityKey) || identityKey.contains(key),
                ))) {
          score += 1;
        }
      }
      if (score > 0) {
        scored.add((caption: caption, score: score));
      }
    }
    if (scored.isEmpty) {
      return const [];
    }
    scored.sort((left, right) => right.score.compareTo(left.score));
    final bestScore = scored.first.score;
    return List.unmodifiable([
      for (final item in scored)
        if (item.score == bestScore) item.caption,
    ]);
  }

  Set<String> _identityKeysForTexts(Iterable<String> texts) {
    return {
      for (final text in texts)
        for (final tag in PromptTagProcessor.splitWorkshopTags(text))
          if (PromptTagProcessor.normalizeMatchKey(
            PromptTagProcessor.cleanTagDisplay(tag),
          ).isNotEmpty)
            PromptTagProcessor.normalizeMatchKey(
              PromptTagProcessor.cleanTagDisplay(tag),
            ),
    };
  }

  Map<String, String> _evidenceTagsByKey(Iterable<String> captions) {
    final result = <String, String>{};
    for (final caption in captions) {
      for (final rawTag in PromptTagProcessor.splitWorkshopTags(caption)) {
        final clean = PromptTagProcessor.cleanTagDisplay(rawTag).trim();
        final key = PromptTagProcessor.normalizeMatchKey(clean);
        if (key.isEmpty) {
          continue;
        }
        result.putIfAbsent(key, () => clean);
      }
    }
    return result;
  }

  String? _supportedEvidenceTagForTerm(
    String term,
    Map<String, String> evidence,
  ) {
    for (final key in _evidenceKeyCandidatesForTerm(term)) {
      final supported = evidence[key];
      if (supported != null) {
        return supported;
      }
    }
    return null;
  }

  List<String> _evidenceKeyCandidatesForTerm(String term) {
    final normalized = PromptTagProcessor.normalizeMatchKey(
      term,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final candidates = <String>[normalized];
    String stripPattern(String value, Pattern pattern) {
      return value.replaceFirst(pattern, '').trim();
    }

    for (final pattern in [
      RegExp(r'\s+(often|sometimes|occasionally) present$'),
      RegExp(r'\s+in some( early| later)? frames$'),
      RegExp(r'\s+only in some.*$'),
      RegExp(r'\s+when visible$'),
      RegExp(r'\s+if visible$'),
      RegExp(r'\s+when tagged$'),
      RegExp(r'\s+if tagged$'),
      RegExp(r'\s+depending( on)? frame$'),
      RegExp(r'\s+not consistently tagged$'),
      RegExp(r'\s+not always tagged$'),
      RegExp(r'\s+varies by frame$'),
      RegExp(r'\s+or no .*$'),
    ]) {
      final stripped = stripPattern(normalized, pattern);
      if (stripped.isNotEmpty && stripped != normalized) {
        candidates.add(stripped);
      }
    }
    return List.unmodifiable(candidates.toSet());
  }

  bool _isBaseSourceRoleId(String value) {
    final key = value.trim().toLowerCase();
    return key == 'base' ||
        key == 'global' ||
        key.startsWith('base-') ||
        key.startsWith('global-');
  }

  ScriptAiExtractedStage _stageWithCacheAdjustment(
    ScriptAiExtractedStage stage,
  ) {
    final fields = <StudioScriptRolePart, List<String>>{
      for (final part in StudioScriptRolePart.values) part: <String>[],
    };
    final seen = <StudioScriptRolePart, Set<String>>{
      for (final part in StudioScriptRolePart.values) part: <String>{},
    };

    void add(StudioScriptRolePart part, String tag) {
      final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
      final key = PromptTagProcessor.normalizeMatchKey(clean);
      if (key.isEmpty || !seen[part]!.add(key)) {
        return;
      }
      fields[part]!.add(clean);
    }

    void route(StudioScriptRolePart originalPart, String text) {
      for (final tag in PromptTagProcessor.splitWorkshopTags(text)) {
        final entry = _manualRoleClassificationEntryFor(tag);
        final targetPart = entry == null
            ? null
            : _rolePartForCacheAdjustment(
                entry.category,
                originalPart: originalPart,
              );
        add(targetPart ?? originalPart, tag);
      }
    }

    route(StudioScriptRolePart.identity, stage.identity);
    route(StudioScriptRolePart.upperBody, stage.upperBody);
    route(StudioScriptRolePart.lowerBody, stage.lowerBody);
    route(StudioScriptRolePart.upperClothing, stage.upperClothing);
    route(StudioScriptRolePart.lowerClothing, stage.lowerClothing);
    route(StudioScriptRolePart.nonRole, stage.nonRole);

    final nextParts = RecastPromptParts(
      identity: fields[StudioScriptRolePart.identity]!.join(', '),
      upperBody: fields[StudioScriptRolePart.upperBody]!.join(', '),
      lowerBody: fields[StudioScriptRolePart.lowerBody]!.join(', '),
      upperClothing: fields[StudioScriptRolePart.upperClothing]!.join(', '),
      lowerClothing: fields[StudioScriptRolePart.lowerClothing]!.join(', '),
    );
    return ScriptAiExtractedStage(
      stageId: stage.stageId,
      label: stage.label,
      appearanceGroupId: stage.appearanceGroupId,
      mergeWithStageIds: stage.mergeWithStageIds,
      fieldReasons: stage.fieldReasons,
      confidence: stage.confidence,
      frameIndexes: stage.frameIndexes,
      identity: nextParts.identity,
      upperBody: nextParts.upperBody,
      lowerBody: nextParts.lowerBody,
      upperClothing: nextParts.upperClothing,
      lowerClothing: nextParts.lowerClothing,
      nonRole: fields[StudioScriptRolePart.nonRole]!.join(', '),
      nonRoleMaterialized: true,
      evidenceTerms: stage.evidenceTerms,
      missingFields: _missingFieldsForPromptParts(
        stage.missingFields,
        nextParts,
      ),
      warnings: stage.warnings,
    );
  }

  StudioScriptRolePart? _rolePartForCacheAdjustment(
    PromptTagCategory category, {
    required StudioScriptRolePart originalPart,
  }) {
    return switch (category) {
      PromptTagCategory.character => StudioScriptRolePart.identity,
      PromptTagCategory.upperBody => StudioScriptRolePart.upperBody,
      PromptTagCategory.lowerBody => StudioScriptRolePart.lowerBody,
      PromptTagCategory.upperClothing => StudioScriptRolePart.upperClothing,
      PromptTagCategory.lowerClothing => StudioScriptRolePart.lowerClothing,
      PromptTagCategory.accessory => StudioScriptRolePart.upperBody,
      PromptTagCategory.clothingState => StudioScriptRolePart.upperClothing,
      PromptTagCategory.clothing =>
        originalPart == StudioScriptRolePart.lowerClothing
            ? StudioScriptRolePart.lowerClothing
            : StudioScriptRolePart.upperClothing,
      _ => StudioScriptRolePart.nonRole,
    };
  }

  bool _stageDraftEqual(
    ScriptAiExtractedStage left,
    ScriptAiExtractedStage right,
  ) {
    return left.identity == right.identity &&
        left.upperBody == right.upperBody &&
        left.lowerBody == right.lowerBody &&
        left.upperClothing == right.upperClothing &&
        left.lowerClothing == right.lowerClothing &&
        left.nonRole == right.nonRole &&
        left.nonRoleMaterialized == right.nonRoleMaterialized;
  }

  RecastPromptParts _promptPartsWithManualClassificationOverrides(
    RecastPromptParts parts,
  ) {
    final fields = <StudioScriptRolePart, List<String>>{
      for (final part in StudioScriptRolePart.values) part: <String>[],
    };
    final seen = <StudioScriptRolePart, Set<String>>{
      for (final part in StudioScriptRolePart.values) part: <String>{},
    };

    void add(StudioScriptRolePart part, String tag) {
      final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
      final key = PromptTagProcessor.normalizeMatchKey(clean);
      if (key.isEmpty || !seen[part]!.add(key)) {
        return;
      }
      fields[part]!.add(clean);
    }

    void route(StudioScriptRolePart originalPart, String text) {
      for (final tag in PromptTagProcessor.splitWorkshopTags(text)) {
        final entry = _manualRoleClassificationEntryFor(tag);
        if (entry == null) {
          add(originalPart, tag);
          continue;
        }
        final targetPart = _rolePartForPromptCategory(entry.category);
        if (targetPart != null) {
          add(targetPart, tag);
        }
      }
    }

    route(StudioScriptRolePart.identity, parts.identity);
    route(StudioScriptRolePart.upperBody, parts.upperBody);
    route(StudioScriptRolePart.lowerBody, parts.lowerBody);
    route(StudioScriptRolePart.upperClothing, parts.upperClothing);
    route(StudioScriptRolePart.lowerClothing, parts.lowerClothing);

    return RecastPromptParts(
      identity: fields[StudioScriptRolePart.identity]!.join(', '),
      upperBody: fields[StudioScriptRolePart.upperBody]!.join(', '),
      lowerBody: fields[StudioScriptRolePart.lowerBody]!.join(', '),
      upperClothing: fields[StudioScriptRolePart.upperClothing]!.join(', '),
      lowerClothing: fields[StudioScriptRolePart.lowerClothing]!.join(', '),
    );
  }

  PromptTagClassificationCacheEntry? _manualRoleClassificationEntryFor(
    String tag,
  ) {
    final entry = classificationCache.entryFor(tag);
    if (entry == null) {
      return null;
    }
    if (entry.source == 'manual' || entry.source.startsWith('manual-role')) {
      return entry;
    }
    return null;
  }

  List<RoleAssembly> _assembliesWithManualClassificationSourceParts(
    List<RoleAssembly> assemblies,
  ) {
    var changed = false;
    final nextAssemblies = [
      for (final assembly in assemblies)
        assembly.copyWith(
          stages: List.unmodifiable([
            for (final stage in assembly.stages)
              _stageWithManualClassificationSourceParts(
                stage,
                onChanged: () => changed = true,
              ),
          ]),
        ),
    ];
    return changed ? List.unmodifiable(nextAssemblies) : assemblies;
  }

  RoleAssemblyStage _stageWithManualClassificationSourceParts(
    RoleAssemblyStage stage, {
    required VoidCallback onChanged,
  }) {
    final nextParts = stage.sourceParts.isEmpty
        ? _manualClassifiedPromptPartsFromText(stage.sourceSummary)
        : _promptPartsWithManualClassificationOverrides(stage.sourceParts);
    if (_promptPartsEqual(stage.sourceParts, nextParts)) {
      return stage;
    }
    onChanged();
    return stage.copyWith(
      sourceParts: nextParts,
      sourceSummary: stage.sourceSummary.trim().isEmpty
          ? _summaryFromPromptParts(nextParts)
          : stage.sourceSummary,
    );
  }

  RecastPromptParts _manualClassifiedPromptPartsFromText(String text) {
    final fields = <StudioScriptRolePart, List<String>>{
      for (final part in StudioScriptRolePart.values) part: <String>[],
    };
    final seen = <StudioScriptRolePart, Set<String>>{
      for (final part in StudioScriptRolePart.values) part: <String>{},
    };

    for (final tag in PromptTagProcessor.splitWorkshopTags(text)) {
      final entry = _manualRoleClassificationEntryFor(tag);
      if (entry == null) {
        continue;
      }
      final part = _rolePartForPromptCategory(entry.category);
      if (part == null) {
        continue;
      }
      final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
      final key = PromptTagProcessor.normalizeMatchKey(clean);
      if (key.isEmpty || !seen[part]!.add(key)) {
        continue;
      }
      fields[part]!.add(clean);
    }

    return RecastPromptParts(
      identity: fields[StudioScriptRolePart.identity]!.join(', '),
      upperBody: fields[StudioScriptRolePart.upperBody]!.join(', '),
      lowerBody: fields[StudioScriptRolePart.lowerBody]!.join(', '),
      upperClothing: fields[StudioScriptRolePart.upperClothing]!.join(', '),
      lowerClothing: fields[StudioScriptRolePart.lowerClothing]!.join(', '),
    );
  }

  List<String> _missingFieldsForPromptParts(
    List<String> current,
    RecastPromptParts parts,
  ) {
    final result = <String>[];
    final seen = <String>{};
    for (final field in current) {
      if (field == 'missing_identity' ||
          field == 'missing_upper_body' ||
          field == 'missing_lower_body' ||
          field == 'missing_upper_clothing' ||
          field == 'missing_lower_clothing') {
        continue;
      }
      if (seen.add(field)) {
        result.add(field);
      }
    }
    void addIf(bool missing, String field) {
      if (missing && seen.add(field)) {
        result.add(field);
      }
    }

    addIf(parts.identity.trim().isEmpty, 'missing_identity');
    addIf(parts.upperBody.trim().isEmpty, 'missing_upper_body');
    addIf(parts.lowerBody.trim().isEmpty, 'missing_lower_body');
    addIf(parts.upperClothing.trim().isEmpty, 'missing_upper_clothing');
    addIf(parts.lowerClothing.trim().isEmpty, 'missing_lower_clothing');
    return List.unmodifiable(result);
  }

  RecastMapping _mappingWithRoleAssemblies(
    Script script,
    RecastMapping mapping,
  ) {
    final visibleMapping = _mappingWithFallbackRoleStages(
      script,
      _mappingWithDerivedGenericStageLabels(
        _mappingWithoutStaleLocalDefaultStages(mapping),
      ),
    );
    if (visibleMapping.roleAssemblies.isNotEmpty &&
        !_hasOnlyAutomaticRoleAssemblies(visibleMapping.roleAssemblies)) {
      return _mappingWithVisibleSourceIdentityParts(visibleMapping);
    }
    var assemblies = visibleMapping.roleAssemblies;
    if (assemblies.isEmpty || assemblies.every(_isEmptyAutomaticSlotAssembly)) {
      assemblies = _localDefaultRoleAssembliesForScript(
        script,
        sourceRoleIds: {
          for (final swap in visibleMapping.roleSwaps) swap.sourceRoleId,
        },
      );
    }
    for (final swap in visibleMapping.roleSwaps) {
      final character = _characterById(swap.targetCharacterId);
      assemblies = [
        for (final assembly in assemblies)
          if (assembly.sourceRoleId == swap.sourceRoleId)
            character == null
                ? _assemblyWithTargetIds(
                    assembly,
                    targetCharacterId: swap.targetCharacterId,
                    targetOutfitId: swap.targetOutfitId,
                  )
                : _assemblyWithCharacter(
                    assembly,
                    character,
                    swap.targetOutfitId ?? character.defaultOutfitId,
                  )
          else
            assembly,
      ];
    }
    return _mappingWithVisibleSourceIdentityParts(
      visibleMapping.copyWith(
        roleAssemblies: _assembliesWithManualClassificationSourceParts(
          assemblies,
        ),
      ),
    );
  }

  RecastMapping? _editableRoleAssemblyMapping(RecastMapping? mapping) {
    final script = _script;
    if (mapping == null ||
        script == null ||
        mapping.roleAssemblies.isNotEmpty) {
      return mapping;
    }
    final sourceRoleIds = _localDefaultSourceRoleIdsForScript(script);
    if (sourceRoleIds.isEmpty) {
      return mapping;
    }
    return mapping.copyWith(
      roleAssemblies: _localDefaultRoleAssembliesForScript(
        script,
        sourceRoleIds: sourceRoleIds,
      ),
    );
  }

  Set<String> _localDefaultSourceRoleIdsForScript(Script script) {
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    final maxSlots = parsedFrames.fold<int>(
      0,
      (count, frame) => frame.parsed.charCaptions.length > count
          ? frame.parsed.charCaptions.length
          : count,
    );
    return Set.unmodifiable([
      for (var index = 0; index < maxSlots; index += 1) 'slot-$index',
    ]);
  }

  List<RoleAssembly> _localDefaultRoleAssembliesForScript(
    Script script, {
    Set<String> sourceRoleIds = const {},
  }) {
    if (sourceRoleIds.isEmpty) {
      return const [];
    }
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    final maxSlots = parsedFrames.fold<int>(
      0,
      (count, frame) => frame.parsed.charCaptions.length > count
          ? frame.parsed.charCaptions.length
          : count,
    );
    return List.unmodifiable([
      for (var index = 0; index < maxSlots; index += 1)
        if (sourceRoleIds.contains('slot-$index'))
          _localDefaultRoleAssemblyForSlot(parsedFrames, index),
    ]);
  }

  RoleAssembly _localDefaultRoleAssemblyForSlot(
    List<ScriptFrame> frames,
    int slotIndex,
  ) {
    final sourceRoleId = 'slot-$slotIndex';
    final frameIndexes = [
      for (final frame in frames)
        if (slotIndex < frame.parsed.charCaptions.length) frame.index,
    ];
    final label = '角色 ${slotIndex + 1}';
    return RoleAssembly(
      sourceRoleId: sourceRoleId,
      displayLabel: label,
      stages: [
        RoleAssemblyStage(
          id: '$sourceRoleId-stage-1',
          label: label,
          frameIndexes: List.unmodifiable(frameIndexes),
        ),
      ],
    );
  }

  RecastMapping _mappingWithFallbackRoleStages(
    Script script,
    RecastMapping mapping,
  ) {
    var changed = false;
    final nextAssemblies = [
      for (final assembly in mapping.roleAssemblies)
        () {
          if (assembly.stages.isNotEmpty) {
            return assembly;
          }
          final sourceIdentity = assembly.sourceName.trim();
          if (sourceIdentity.isEmpty && assembly.sourceAppearances.isEmpty) {
            return assembly;
          }
          changed = true;
          final label = sourceIdentity.isNotEmpty
              ? sourceIdentity
              : assembly.displayLabel.trim().isNotEmpty
                  ? assembly.displayLabel.trim()
                  : '源角色';
          return assembly.copyWith(
            stages: [
              RoleAssemblyStage(
                id: '${assembly.sourceRoleId}-source-stage',
                label: label,
                frameIndexes: _fallbackFrameIndexesForAssembly(
                  script,
                  assembly,
                ),
                sourceSummary: label,
                sourceParts: RecastPromptParts(identity: label),
              ),
            ],
          );
        }(),
    ];
    if (!changed) {
      return mapping;
    }
    return mapping.copyWith(roleAssemblies: List.unmodifiable(nextAssemblies));
  }

  List<int> _fallbackFrameIndexesForAssembly(
    Script script,
    RoleAssembly assembly,
  ) {
    final indexes = <int>{};
    for (final appearance in assembly.sourceAppearances) {
      indexes.addAll(appearance.frameIndexes);
    }
    if (indexes.isNotEmpty) {
      return List.unmodifiable(indexes.toList()..sort());
    }

    final slotMatch = RegExp(r'^slot-(\d+)$').firstMatch(
      assembly.sourceRoleId.trim(),
    );
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    if (slotMatch != null) {
      final slotIndex = int.tryParse(slotMatch.group(1) ?? '');
      if (slotIndex != null) {
        for (final frame in parsedFrames) {
          if (slotIndex < frame.parsed.charCaptions.length) {
            indexes.add(frame.index);
          }
        }
      }
    }
    if (indexes.isEmpty) {
      indexes.addAll(parsedFrames.map((frame) => frame.index));
    }
    return List.unmodifiable(indexes.toList()..sort());
  }

  RecastMapping _mappingWithDerivedGenericStageLabels(RecastMapping mapping) {
    var changed = false;
    final nextAssemblies = [
      for (final assembly in mapping.roleAssemblies)
        assembly.copyWith(
          stages: List.unmodifiable([
            for (final stage in assembly.stages)
              () {
                final label = _derivedRoleAssemblyStageLabel(stage);
                if (label == null || label == stage.label) {
                  return stage;
                }
                changed = true;
                return stage.copyWith(label: label);
              }(),
          ]),
        ),
    ];
    if (!changed) {
      return mapping;
    }
    return mapping.copyWith(roleAssemblies: List.unmodifiable(nextAssemblies));
  }

  String? _derivedRoleAssemblyStageLabel(RoleAssemblyStage stage) {
    final current = stage.label.trim();
    if (current.isNotEmpty && !_isGenericAiOutfitStageLabel(current)) {
      return _localizedGeneratedAiOutfitLabel(
        current,
        translationCache: translationCache,
      );
    }
    return _derivedAiOutfitStageLabelFromParts(
      stage.sourceParts,
      translationCache: translationCache,
    );
  }

  RecastMapping _mappingWithoutStaleLocalDefaultStages(RecastMapping mapping) {
    var changed = false;
    var nextAssemblies = [
      for (final assembly in mapping.roleAssemblies)
        () {
          final nextStages = [
            for (final stage in assembly.stages)
              if (!_isStaleLocalDefaultStage(assembly, stage)) stage,
          ];
          changed = changed || nextStages.length != assembly.stages.length;
          return assembly.copyWith(stages: List.unmodifiable(nextStages));
        }(),
    ];
    if (nextAssemblies.any(_hasMaterializedRoleAssembly)) {
      final prunedAssemblies = [
        for (final assembly in nextAssemblies)
          if (!_isEmptyAutomaticSlotAssembly(assembly)) assembly,
      ];
      changed = changed || prunedAssemblies.length != nextAssemblies.length;
      nextAssemblies = prunedAssemblies;
    }
    if (!changed) {
      return mapping;
    }
    return mapping.copyWith(roleAssemblies: List.unmodifiable(nextAssemblies));
  }

  bool _hasMaterializedRoleAssembly(RoleAssembly assembly) {
    return assembly.stages.isNotEmpty;
  }

  bool _isEmptyAutomaticSlotAssembly(RoleAssembly assembly) {
    return RegExp(r'^slot-\d+$').hasMatch(assembly.sourceRoleId.trim()) &&
        assembly.sourceName.trim().isEmpty &&
        assembly.sourceAppearances.isEmpty &&
        assembly.stages.isEmpty;
  }

  bool _isStaleLocalDefaultStage(
    RoleAssembly assembly,
    RoleAssemblyStage stage,
  ) {
    if (_isUserAuthoredStage(stage)) {
      return false;
    }
    if (!_isAutomaticStage(stage)) {
      return false;
    }
    return RegExp(
      '^${RegExp.escape(assembly.sourceRoleId)}-stage-\\d+\$',
    ).hasMatch(stage.id.trim());
  }

  RecastMapping _mappingWithVisibleSourceIdentityParts(RecastMapping mapping) {
    var changed = false;
    final nextAssemblies = [
      for (final assembly in mapping.roleAssemblies)
        () {
          final sourceIdentity = assembly.sourceName.trim();
          if (sourceIdentity.isEmpty) {
            return assembly;
          }
          final nextStages = [
            for (final stage in assembly.stages)
              if (stage.sourceParts.identity.trim().isEmpty)
                () {
                  changed = true;
                  return stage.copyWith(
                    sourceParts: stage.sourceParts.copyWith(
                      identity: sourceIdentity,
                    ),
                    sourceSummary: stage.sourceSummary.trim().isEmpty
                        ? sourceIdentity
                        : stage.sourceSummary,
                  );
                }()
              else
                stage,
          ];
          return assembly.copyWith(stages: List.unmodifiable(nextStages));
        }(),
    ];
    if (!changed) {
      return mapping;
    }
    return mapping.copyWith(roleAssemblies: List.unmodifiable(nextAssemblies));
  }

  bool _hasOnlyAutomaticRoleAssemblies(List<RoleAssembly> assemblies) {
    return assemblies.every(
      (assembly) => assembly.stages.indexed.every((entry) {
        final index = entry.$1;
        final stage = entry.$2;
        return _isAutomaticStage(stage) &&
            stage.id == '${assembly.sourceRoleId}-stage-${index + 1}';
      }),
    );
  }

  bool _isAutomaticStage(RoleAssemblyStage stage) {
    return stage.targetCharacterId == null &&
        stage.targetUpperOutfitId == null &&
        stage.targetLowerOutfitId == null &&
        stage.omittedParts.isEmpty &&
        stage.preservedParts.isEmpty &&
        stage.sourceSummary.trim().isEmpty &&
        stage.sourceParts.isEmpty &&
        stage.manualParts.isEmpty;
  }

  void _applyScript(Script script, {RecastMapping? mappingOverride}) {
    _manualSelectedStageIdsByRole.clear();
    _selectedRoleReplacementRuleIdsByRole.clear();
    _selectedSceneReplacementRuleIdsByGroup.clear();
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    var mapping = _mappingWithRoleAssemblies(
      script,
      mappingOverride ?? RecastMapping.defaults(script.id),
    );
    _mapping = mapping;
    _selectedFrameIndex = parsedFrames.isNotEmpty
        ? parsedFrames.first.index
        : script.frames.isNotEmpty
            ? script.frames.first.index
            : null;
    _previewResult = _resolveSelectedFramePreview(script, mapping);

    folderStatus = '已导入 ${script.name}';
    frameCount = script.frames.length;
    parsedCount = parsedFrames.length;
    warningCount = script.parseWarnings.length;
    warnings = [
      ...script.parseWarnings,
      for (final frame in script.frames)
        for (final warning in frame.warnings) '${frame.fileName}: $warning',
    ];
    schemaLabel = script.detectedSchema.name;
    roles = _roleSummary(parsedFrames, mapping);
    roleCount = roles.length;
    artistChains = _artistSummary(parsedFrames);
    roleMappings = _roleMappingItems(parsedFrames, mapping);
    roleReplacementMappings = _roleReplacementItems(mapping);
    sceneReplacementMappings = _sceneReplacementItems(mapping);
    artistMappings = _artistMappingItems(parsedFrames, mapping);
    promptBlockMappings = _promptBlockMappingItems(parsedFrames, mapping);
    _refreshTimeline();
    _refreshSelectedFrameTagGroups();
    diff = _diffFor(parsedFrames);
    _refreshRecastPlan();
  }

  Future<void> _restoreExactCurrentSourceCache(
    Script script, {
    bool Function()? shouldContinue,
  }) async {
    final currentFingerprint = cacheRestoreService.sourceFingerprint(script);
    final currentContentFingerprint =
        cacheRestoreService.sourceContentFingerprint(script);
    final targetedLoader = loadRecastCacheByScriptId;
    if (targetedLoader != null) {
      final cache = await targetedLoader(script.id);
      if (shouldContinue?.call() == false) return;
      if (cache != null &&
          cacheRestoreService.cacheBelongsToScript(cache, script) &&
          cache.sourceFingerprint == currentFingerprint) {
        _applyCache(cache);
        cacheStatus = '已恢复本剧本缓存';
        return;
      }
      return;
    }

    final loader = loadRecastCaches;
    if (loader == null) {
      return;
    }
    final exactCaches = [
      for (final cache in await loader())
        if ((cacheRestoreService.cacheBelongsToScript(cache, script) &&
                cache.sourceFingerprint == currentFingerprint) ||
            cacheRestoreService.cacheHasSourceContentFingerprint(
              cache,
              currentContentFingerprint,
            ))
          cache,
    ];
    if (shouldContinue?.call() == false) return;
    final bestCache = cacheRestoreService.bestExactCache(exactCaches);
    if (bestCache == null) {
      return;
    }
    _applyCache(bestCache);
    cacheStatus = '已恢复本剧本缓存';
  }

  List<RecastMappingVariant> _validMappingVariantsForCache(
    RecastScriptCache cache,
    Script? script,
  ) {
    final expectedScriptId = script?.id.trim() ?? cache.scriptId.trim();
    final expectedSourceFingerprint = script == null
        ? cache.sourceFingerprint.trim()
        : cacheRestoreService.sourceFingerprint(script).trim();
    return [
      for (final variant in cache.mappingVariants)
        if (variant.scriptId.trim() == expectedScriptId &&
            variant.mapping.scriptId.trim() == expectedScriptId &&
            variant.sourceFingerprint.trim() == expectedSourceFingerprint &&
            _isAllowedScriptMappingVariant(variant))
          variant,
    ];
  }

  bool _sameMappingVariantLists(
    List<RecastMappingVariant> left,
    List<RecastMappingVariant> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      final leftVariant = left[index];
      final rightVariant = right[index];
      if (leftVariant.id != rightVariant.id ||
          leftVariant.name != rightVariant.name ||
          leftVariant.scriptId != rightVariant.scriptId ||
          leftVariant.sourceFingerprint != rightVariant.sourceFingerprint ||
          leftVariant.sourceContentFingerprint !=
              rightVariant.sourceContentFingerprint ||
          leftVariant.capturedAt != rightVariant.capturedAt ||
          !mapEquals(
            leftVariant.targetCharacterNamesByRoleId,
            rightVariant.targetCharacterNamesByRoleId,
          ) ||
          !mappingVariantService.sameMapping(
            leftVariant.mapping,
            rightVariant.mapping,
          )) {
        return false;
      }
    }
    return true;
  }

  void _applyCache(
    RecastScriptCache cache, {
    bool refreshPreview = true,
  }) {
    _manualSelectedStageIdsByRole.clear();
    _selectedRoleReplacementRuleIdsByRole.clear();
    _selectedSceneReplacementRuleIdsByGroup.clear();
    final script = _script;
    final legacyImplicitRoleMappingSync = cache.roleMappingProfileSyncVersion <
        RecastScriptCache.currentRoleMappingProfileSyncVersion;
    final validMappingVariants = [
      for (final variant in _validMappingVariantsForCache(cache, script))
        variant.copyWith(
          mapping: legacyImplicitRoleMappingSync
              ? _withoutRoleMappingProfileLinks(variant.mapping)
              : _withRoleScopedMappingProfileLinks(variant.mapping),
        ),
    ];
    _mappingVariants = List.unmodifiable(validMappingVariants);
    _activeMappingVariantId = validMappingVariants.any(
      (variant) => variant.id == cache.activeMappingVariantId,
    )
        ? cache.activeMappingVariantId
        : null;
    mappingVariantStatus =
        validMappingVariants.length == cache.mappingVariants.length
            ? ''
            : '已忽略与当前剧本或来源指纹不匹配的映射版本';
    final restoredMapping = script == null
        ? cache.mapping
        : _mappingWithRoleAssemblies(script, cache.mapping);
    final restoredMappingWithoutImplicitSync = legacyImplicitRoleMappingSync
        ? _withoutRoleMappingProfileLinks(restoredMapping)
        : _withRoleScopedMappingProfileLinks(restoredMapping);
    final materializedExtraction = script == null
        ? cache.aiRoleExtraction
        : _roleExtractionWithMaterializedNonRoleFields(
            extraction: cache.aiRoleExtraction,
            script: script,
          );
    final extractionFrameRepair = script == null
        ? (extraction: materializedExtraction, changed: false)
        : _roleExtractionWithSourceTermFrameEvidence(
            script: script,
            extraction: materializedExtraction,
          );
    final sourceRepairedExtraction = extractionFrameRepair.extraction;
    final restoredExtraction =
        sourceRepairedExtraction.collapseEquivalentStages();
    final extractionNormalizationChanged =
        !identical(restoredExtraction, sourceRepairedExtraction);
    final explicitlyFinalized = cache.aiRoleExtractionFinalized &&
        restoredExtraction.isReady &&
        (restoredExtraction.roles.isNotEmpty ||
            restoredExtraction.sceneTerms.isNotEmpty) &&
        !restoredExtraction.attentionItems.any((item) => item.blocking);
    final shouldApplyExtractionMapping =
        !explicitlyFinalized || extractionNormalizationChanged;
    final appliedExtractionMapping =
        script == null || !shouldApplyExtractionMapping
            ? null
            : _mappingWithAppliedAiRoleExtraction(
                script: script,
                mapping: restoredMappingWithoutImplicitSync,
                extraction: sourceRepairedExtraction,
              );
    final mapped =
        appliedExtractionMapping?.mapping ?? restoredMappingWithoutImplicitSync;
    final mappingFrameRepair = script == null
        ? (mapping: mapped, changed: false)
        : _mappingWithSourceTermFrameEvidence(script: script, mapping: mapped);
    _mapping = mappingFrameRepair.mapping;
    aiRoleExtraction = restoredExtraction;
    aiRoleExtractionChunks = cache.aiRoleExtractionChunks;
    _aiRoleExtractionDraftDismissed = cache.aiRoleExtractionDraftCollapsed;
    final inferredFinalized = restoredExtraction.isReady &&
        (restoredExtraction.roles.isNotEmpty ||
            restoredExtraction.sceneTerms.isNotEmpty) &&
        !restoredExtraction.attentionItems.any((item) => item.blocking) &&
        appliedExtractionMapping != null &&
        !appliedExtractionMapping.changed;
    _aiRoleExtractionFinalized = explicitlyFinalized || inferredFinalized;
    _aiRoleExtractionDraftSuppressed = _aiRoleExtractionFinalized;
    scriptBlockWords = _normalizeBlockWords(cache.scriptBlockWords);
    aiRoleExtractionReasoningContent = '';
    aiRoleExtractionRequestCount = 0;
    if (aiRoleExtraction.status != ScriptAiRoleExtractionStatus.idle) {
      aiStatus = _aiRoleExtractionDraftSuppressed
          ? '已从缓存恢复已应用角色字段'
          : '已从缓存恢复 AI 角色字段草稿';
      aiOperationStatus = OperationStatus.success(
        code: OperationStatusCode.aiExtraction,
        message: aiStatus,
      );
    }
    analysisStatus = '已从缓存恢复映射';
    cacheOperationStatus = OperationStatus.success(
      code: OperationStatusCode.cacheRestore,
      message: analysisStatus,
    );
    if (refreshPreview) {
      _refreshPreview();
    }
    if ((appliedExtractionMapping?.changed ?? false) ||
        extractionNormalizationChanged ||
        extractionFrameRepair.changed ||
        mappingFrameRepair.changed ||
        legacyImplicitRoleMappingSync) {
      if (legacyImplicitRoleMappingSync) {
        roleMappingProfileStatus = '已清理旧版默认全局同步，当前剧本保持独立映射';
      }
      _scheduleCurrentCacheSave();
    }
  }

  ({ScriptAiRoleExtraction extraction, bool changed})
      _roleExtractionWithSourceTermFrameEvidence({
    required Script script,
    required ScriptAiRoleExtraction extraction,
  }) {
    var changed = false;
    final roles = [
      for (final role in extraction.roles)
        () {
          final terms = _aiPromptTermsWithSourceTermFrameEvidence(
            script: script,
            terms: role.promptTerms,
            sourceRoleId: role.sourceRoleId,
            sceneScope: false,
          );
          if (!terms.changed) {
            return role;
          }
          changed = true;
          return ScriptAiExtractedRole(
            sourceRoleId: role.sourceRoleId,
            sourceKind: role.sourceKind,
            displayName: role.displayName,
            roleReason: role.roleReason,
            canonicalName: role.canonicalName,
            franchise: role.franchise,
            rawIdentityTags: role.rawIdentityTags,
            variantTags: role.variantTags,
            mergeWithRoleId: role.mergeWithRoleId,
            confidence: role.confidence,
            frameIndexes: role.frameIndexes,
            appearances: role.appearances,
            evidenceTerms: role.evidenceTerms,
            warnings: role.warnings,
            stages: role.stages,
            unassignedTerms: role.unassignedTerms,
            promptTerms: terms.terms,
          );
        }(),
    ];
    final sceneTerms = _aiPromptTermsWithSourceTermFrameEvidence(
      script: script,
      terms: extraction.sceneTerms,
      sourceRoleId: '',
      sceneScope: true,
    );
    if (sceneTerms.changed) {
      changed = true;
    }
    if (!changed) {
      return (extraction: extraction, changed: false);
    }
    return (
      extraction: ScriptAiRoleExtraction(
        schemaVersion: extraction.schemaVersion,
        status: extraction.status,
        chunkId: extraction.chunkId,
        confidence: extraction.confidence,
        roles: List.unmodifiable(roles),
        artistChains: extraction.artistChains,
        strongFilterKeywords: extraction.strongFilterKeywords,
        attentionItems: extraction.attentionItems,
        unassignedTerms: extraction.unassignedTerms,
        evidenceRequests: extraction.evidenceRequests,
        sceneTerms: sceneTerms.terms,
        termCacheSuggestions: extraction.termCacheSuggestions,
        rawResponse: extraction.rawResponse,
      ),
      changed: true,
    );
  }

  ({RecastMapping mapping, bool changed}) _mappingWithSourceTermFrameEvidence({
    required Script script,
    required RecastMapping mapping,
  }) {
    var changed = false;
    final roleReplacements = [
      for (final replacement in mapping.rolePromptReplacements)
        () {
          final rules = _replacementRulesWithSourceTermFrameEvidence(
            script: script,
            rules: replacement.rules,
            sourceRoleId: replacement.sourceRoleId,
            sceneScope: false,
          );
          if (!rules.changed) {
            return replacement;
          }
          changed = true;
          return replacement.copyWith(rules: rules.rules);
        }(),
    ];
    final sceneReplacements = [
      for (final replacement in mapping.scenePromptReplacements)
        () {
          final rules = _replacementRulesWithSourceTermFrameEvidence(
            script: script,
            rules: replacement.rules,
            sourceRoleId: '',
            sceneScope: true,
          );
          if (!rules.changed) {
            return replacement;
          }
          changed = true;
          return replacement.copyWith(rules: rules.rules);
        }(),
    ];
    if (!changed) {
      return (mapping: mapping, changed: false);
    }
    return (
      mapping: mapping.copyWith(
        rolePromptReplacements: List.unmodifiable(roleReplacements),
        scenePromptReplacements: List.unmodifiable(sceneReplacements),
      ),
      changed: true,
    );
  }

  ({List<ScriptAiExtractedPromptTerm> terms, bool changed})
      _aiPromptTermsWithSourceTermFrameEvidence({
    required Script script,
    required List<ScriptAiExtractedPromptTerm> terms,
    required String sourceRoleId,
    required bool sceneScope,
  }) {
    var changed = false;
    final nextTerms = [
      for (final term in terms)
        () {
          final sourceFrames = _sourceFrameIndexesForPromptTerm(
            script: script,
            termText: term.text,
            sourceRoleId: sourceRoleId,
            sceneScope: sceneScope,
          );
          if (sourceFrames.isEmpty ||
              _intListsEqual(sourceFrames, term.frameIndexes)) {
            return term;
          }
          changed = true;
          return term.copyWith(frameIndexes: sourceFrames);
        }(),
    ];
    return (
      terms: changed ? List.unmodifiable(nextTerms) : terms,
      changed: changed,
    );
  }

  ({List<ScriptPromptReplacementRule> rules, bool changed})
      _replacementRulesWithSourceTermFrameEvidence({
    required Script script,
    required List<ScriptPromptReplacementRule> rules,
    required String sourceRoleId,
    required bool sceneScope,
  }) {
    var changed = false;
    final nextRules = [
      for (final rule in rules)
        () {
          var ruleChanged = false;
          final terms = [
            for (final term in rule.sourceTerms)
              () {
                final sourceFrames = _sourceFrameIndexesForPromptTerm(
                  script: script,
                  termText: term.text,
                  sourceRoleId: sourceRoleId,
                  sceneScope: sceneScope,
                );
                if (sourceFrames.isEmpty ||
                    _intListsEqual(sourceFrames, term.frameIndexes)) {
                  return term;
                }
                ruleChanged = true;
                return term.copyWith(frameIndexes: sourceFrames);
              }(),
          ];
          if (!ruleChanged) {
            return rule;
          }
          changed = true;
          return rule.copyWith(sourceTerms: List.unmodifiable(terms));
        }(),
    ];
    return (
      rules: changed ? List.unmodifiable(nextRules) : rules,
      changed: changed,
    );
  }

  List<int> _sourceFrameIndexesForPromptTerm({
    required Script script,
    required String termText,
    required String sourceRoleId,
    required bool sceneScope,
  }) {
    final termKey = PromptTagProcessor.normalizeMatchKey(
      PromptTagProcessor.cleanTagDisplay(termText),
    );
    if (termKey.isEmpty) {
      return const [];
    }
    return _sourceTermFrameIndexFor(script).lookup(
      termKey: termKey,
      slotIndex: sceneScope ? null : _slotIndexForRole(sourceRoleId),
      baseScope: !sceneScope && _isBaseSourceRoleId(sourceRoleId),
      sceneScope: sceneScope,
    );
  }

  _ScriptSourceTermFrameIndex _sourceTermFrameIndexFor(Script script) {
    final current = _sourceTermFrameIndex;
    if (current != null && identical(current.script, script)) {
      return current;
    }

    final tagsByCaption = <String, Set<String>>{};
    Set<String> tagsForCaption(String caption) {
      return tagsByCaption.putIfAbsent(caption, () {
        final tags = <String>{};
        for (final rawTag in PromptTagProcessor.splitWorkshopTags(caption)) {
          final key = PromptTagProcessor.normalizeMatchKey(
            PromptTagProcessor.cleanTagDisplay(rawTag),
          );
          if (key.isNotEmpty) {
            tags.add(key);
          }
        }
        return Set.unmodifiable(tags);
      });
    }

    final indexedFrames = <_ScriptSourceTermFrameTags>[];
    for (final frame in script.frames) {
      if (frame.parseStatus != ScriptFrameParseStatus.parsed) {
        continue;
      }
      final characterTags = [
        for (final caption in frame.parsed.charCaptions)
          tagsForCaption(caption),
      ];
      final allCharacterTags = <String>{
        for (final tags in characterTags) ...tags,
      };
      final sceneTags = <String>{
        ...tagsForCaption(_frameBaseCaption(frame)),
        ...allCharacterTags,
      };
      indexedFrames.add(
        _ScriptSourceTermFrameTags(
          frameIndex: frame.index,
          baseRoleTags: tagsForCaption(frame.parsed.baseCaption),
          characterTags: List.unmodifiable(characterTags),
          allCharacterTags: Set.unmodifiable(allCharacterTags),
          sceneTags: Set.unmodifiable(sceneTags),
        ),
      );
    }
    final index = _ScriptSourceTermFrameIndex(
      script: script,
      frames: List.unmodifiable(indexedFrames),
    );
    _sourceTermFrameIndex = index;
    return index;
  }

  void _refreshPreview() {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      roleReplacementMappings = const [];
      sceneReplacementMappings = const [];
      _refreshRecastPlan();
      return;
    }
    _previewResult = _resolveSelectedFramePreview(script, mapping);
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    roleMappings = _roleMappingItems(parsedFrames, mapping);
    roleReplacementMappings = _roleReplacementItems(mapping);
    sceneReplacementMappings = _sceneReplacementItems(mapping);
    artistMappings = _artistMappingItems(parsedFrames, mapping);
    promptBlockMappings = _promptBlockMappingItems(parsedFrames, mapping);
    _refreshTimeline();
    _refreshSelectedFrameTagGroups();
    diff = _diffFor(parsedFrames);
    _refreshRecastPlan();
  }

  void _refreshRoleEditPreview(String sourceRoleId) {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      _refreshRecastPlan();
      return;
    }
    _previewResult = _resolveSelectedFramePreview(script, mapping);
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    _refreshReplacementMappings();
    _refreshRoleMappingItem(parsedFrames, mapping, sourceRoleId);
    _refreshSelectedFrameTagGroups();
    diff = _diffFor(parsedFrames);
    _refreshRecastPlan();
  }

  void _refreshArtistEditPreview() {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      _refreshRecastPlan();
      return;
    }
    _previewResult = _resolveSelectedFramePreview(script, mapping);
    final parsedFrames = _parsedFramesFor(script);
    _refreshReplacementMappings();
    artistMappings = _artistMappingItems(parsedFrames, mapping);
    _refreshSelectedFrameTagGroups();
    diff = _diffFor(parsedFrames);
    _refreshRecastPlan();
  }

  void _refreshPromptBlockEditPreview() {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      _refreshRecastPlan();
      return;
    }
    _previewResult = _resolveSelectedFramePreview(script, mapping);
    final parsedFrames = _parsedFramesFor(script);
    _refreshReplacementMappings();
    promptBlockMappings = _promptBlockMappingItems(parsedFrames, mapping);
    _refreshSelectedFrameTagGroups();
    diff = _diffFor(parsedFrames);
    _refreshRecastPlan();
  }

  void _refreshReplacementEditPreview() {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      roleReplacementMappings = const [];
      sceneReplacementMappings = const [];
      _refreshRecastPlan();
      return;
    }
    _previewResult = _resolveSelectedFramePreview(script, mapping);
    final parsedFrames = _parsedFramesFor(script);
    _refreshReplacementMappings();
    _refreshSelectedFrameTagGroups();
    diff = _diffFor(parsedFrames);
    _refreshRecastPlan();
  }

  void _refreshReplacementMappings() {
    final mapping = _mapping;
    if (mapping == null) {
      roleReplacementMappings = const [];
      sceneReplacementMappings = const [];
      return;
    }
    roleReplacementMappings = _roleReplacementItems(mapping);
    sceneReplacementMappings = _sceneReplacementItems(mapping);
  }

  void _refreshRoleMappingItem(
    List<ScriptFrame> parsedFrames,
    RecastMapping mapping,
    String sourceRoleId,
  ) {
    if (mapping.roleAssemblies.isEmpty) {
      roleMappings = _roleMappingItems(parsedFrames, mapping);
      return;
    }
    final assembly = mapping.roleAssemblies
        .where((candidate) => candidate.sourceRoleId == sourceRoleId)
        .firstOrNull;
    if (assembly == null) {
      roleMappings = _roleMappingItems(parsedFrames, mapping);
      return;
    }
    final nextItem = _roleMappingItemFromAssembly(parsedFrames, assembly);
    var replaced = false;
    final nextItems = <StudioScriptRoleMappingItem>[];
    for (final item in roleMappings) {
      if (item.sourceRoleId == sourceRoleId) {
        nextItems.add(nextItem);
        replaced = true;
      } else {
        nextItems.add(item);
      }
    }
    if (!replaced) {
      roleMappings = _roleMappingItems(parsedFrames, mapping);
      return;
    }
    roleMappings = List.unmodifiable(nextItems);
  }

  void _refreshSelectedFramePreview() {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      _previewResult = null;
      roleReplacementMappings = const [];
      sceneReplacementMappings = const [];
      _refreshTimeline();
      _refreshSelectedFrameTagGroups();
      _refreshRecastPlan();
      return;
    }
    _previewResult = _resolveSelectedFramePreview(script, mapping);
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    roleMappings = _roleMappingItems(parsedFrames, mapping);
    roleReplacementMappings = _roleReplacementItems(mapping);
    sceneReplacementMappings = _sceneReplacementItems(mapping);
    _refreshTimeline();
    _refreshSelectedFrameTagGroups();
    diff = _diffFor(parsedFrames);
    _refreshRecastPlan();
  }

  ScriptRecastResult _resolveSelectedFramePreview(
    Script script,
    RecastMapping mapping,
  ) {
    final frame = _selectedParsedFrame(script);
    if (frame == null) {
      return ScriptRecastResult(
        scriptId: script.id,
        mappingId: mapping.id,
        frames: const [],
        configFingerprint: '',
      );
    }
    final payload = recastEngine.resolveFramePayload(
      script: script,
      frame: frame,
      mapping: mapping,
      characters: _characters,
      artistChains: _availableArtistChains,
      globalBlockWords: _effectiveBlockWords(),
      globalPromptPrefix: globalPromptPrefix,
      filterRuleConfig: _blockWordConfig(),
    );
    return ScriptRecastResult(
      scriptId: script.id,
      mappingId: mapping.id,
      frames: [payload],
      configFingerprint: payload.payloadFingerprint,
    );
  }

  ScriptFrame? _selectedParsedFrame(Script script) {
    final parsedFrames = _parsedFramesFor(script);
    if (parsedFrames.isEmpty) {
      return null;
    }
    return parsedFrames
            .where((frame) => frame.index == _selectedFrameIndex)
            .firstOrNull ??
        parsedFrames.first;
  }

  void _refreshArtistMappings() {
    final script = _script;
    final mapping = _mapping;
    if (script == null || mapping == null) {
      artistMappings = const [];
      return;
    }
    final parsedFrames = _parsedFramesFor(script);
    artistMappings = _artistMappingItems(parsedFrames, mapping);
  }

  List<ScriptFrame> _parsedFramesFor(Script script) {
    return script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
  }

  void _refreshRecastPlan() {
    recastPlan = StudioScriptRecastPlan(
      roles: [
        for (final role in roleMappings)
          StudioScriptPlanRole(
            sourceRoleId: role.sourceRoleId,
            label: role.sourceLabel,
            sourceName: role.sourcePreview,
            selectedCharacterId: role.selectedCharacterId,
            selectedStageLabel: role.selectedStage?.label ?? '',
            statusLabel: 'mapping',
            confidence: 0,
          ),
      ],
      artist: artistMappings.isEmpty
          ? const StudioScriptPlanArtist()
          : StudioScriptPlanArtist(
              sourceLabel: artistMappings.first.sourceLabel,
              selectedArtistChainId: artistMappings.first.selectedArtistChainId,
              manualPrompt: artistMappings.first.manualPrompt,
            ),
      issues: const [],
      frameReviews: _frameReviews(),
      hasAiBackedPlan: aiRoleExtraction.isReady,
    );
  }

  List<StudioScriptFrameReview> _frameReviews() {
    final script = _script;
    if (script == null) {
      return const [];
    }
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    if (parsedFrames.isEmpty) {
      return const [];
    }
    final frame = parsedFrames
            .where((candidate) => candidate.index == _selectedFrameIndex)
            .firstOrNull ??
        parsedFrames.first;
    final positiveGroups = _reviewTokenGroupsFromCaptions(
      baseCaption: _frameBaseCaption(frame),
      charCaptions: frame.parsed.charCaptions,
      negative: false,
    );
    final negativeGroups = _reviewTokenGroupsFromCaptions(
      baseCaption: frame.parsed.negativeBase,
      charCaptions: frame.parsed.negativeCharCaptions,
      negative: true,
    );
    return [
      StudioScriptFrameReview(
        frameIndex: frame.index,
        title: 'Frame ${frame.index}',
        positiveTokens: [for (final group in positiveGroups) ...group.tokens],
        negativeTokens: [for (final group in negativeGroups) ...group.tokens],
        positiveTokenGroups: positiveGroups,
        negativeTokenGroups: negativeGroups,
      ),
    ];
  }

  List<StudioScriptReviewTokenGroup> _reviewTokenGroupsFromCaptions({
    required String baseCaption,
    required List<String> charCaptions,
    required bool negative,
  }) {
    final groups = <StudioScriptReviewTokenGroup>[
      for (final (index, caption) in charCaptions.indexed)
        _reviewTokenGroupForText(
          id: 'role-${index + 1}',
          label: negative ? '负面角色 ${index + 1}' : '角色 ${index + 1}',
          text: caption,
          negative: negative,
        ),
      _reviewTokenGroupForText(
        id: negative ? 'negative-base' : 'base',
        label: negative ? '负面基础' : '基础源词',
        text: baseCaption,
        negative: negative,
      ),
    ];
    return List.unmodifiable(groups.where((group) => group.tokens.isNotEmpty));
  }

  StudioScriptReviewTokenGroup _reviewTokenGroupForText({
    required String id,
    required String label,
    required String text,
    required bool negative,
  }) {
    return StudioScriptReviewTokenGroup(
      id: id,
      label: label,
      tokens: _reviewTokensForText(text, negative: negative),
      negative: negative,
    );
  }

  List<StudioScriptReviewToken> _reviewTokensForText(
    String text, {
    required bool negative,
  }) {
    return [
      for (final tag in PromptTagProcessor.splitWorkshopTags(text))
        if (_cleanDisplayTag(tag).isNotEmpty)
          StudioScriptReviewToken(
            source: _displayTagPreservingWeights(tag),
            translation: translationCache.translate(_cleanDisplayTag(tag)).text,
            category: _reviewCategoryForTag(
              _cleanDisplayTag(tag),
              negative: negative,
            ),
            emphasis: _reviewEmphasisForTag(_cleanDisplayTag(tag)),
          ),
    ];
  }

  StudioScriptTokenCategory _reviewCategoryForTag(
    String tag, {
    required bool negative,
  }) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    final manualCategory = _manualReviewCategoryForTag(tag, negative: negative);
    if (manualCategory != null) {
      return manualCategory;
    }
    if (_aiArtistEvidenceMentionsTag(tag)) {
      return negative
          ? StudioScriptTokenCategory.negativeArtist
          : StudioScriptTokenCategory.artistChain;
    }
    final cachedCategory = _cachedReviewCategoryForTag(tag, negative: negative);
    if (cachedCategory != null) {
      return cachedCategory;
    }
    if (negative) {
      if (key.contains('artist:') || key.startsWith('artist ')) {
        return StudioScriptTokenCategory.negativeArtist;
      }
      if (_containsAny(key, const [
        'hand',
        'body',
        'anatomy',
        'finger',
        'limb',
        'arm',
        'leg',
      ])) {
        return StudioScriptTokenCategory.negativeBody;
      }
      if (_containsAny(key, const [
        'lowres',
        'quality',
        'worst',
        'bad',
        'blurry',
      ])) {
        return StudioScriptTokenCategory.negativeQuality;
      }
      return StudioScriptTokenCategory.negativeContent;
    }
    if (key.contains('artist:') || key.startsWith('artist ')) {
      return StudioScriptTokenCategory.artistChain;
    }
    if (RegExp(r'^\d+(girl|girls|boy|boys)$').hasMatch(key)) {
      return StudioScriptTokenCategory.character;
    }
    if (_looksLikeUpperOutfitTag(tag)) {
      return StudioScriptTokenCategory.upperClothing;
    }
    if (_looksLikeLowerOutfitTag(tag)) {
      return StudioScriptTokenCategory.lowerClothing;
    }
    if (_containsAny(key, const [
      'realistic',
      'anime',
      'official style',
      'flat color',
      'monochrome',
      'muted color',
      'coloring',
      'aesthetic',
    ])) {
      return StudioScriptTokenCategory.style;
    }
    if (_containsAny(key, const [
      'standing',
      'sitting',
      'running',
      'looking',
      'smile',
    ])) {
      return StudioScriptTokenCategory.action;
    }
    if (_containsAny(key, const [
      'background',
      'city',
      'room',
      'train',
      'platform',
      'rain',
      'forest',
      'sky',
    ])) {
      return StudioScriptTokenCategory.scene;
    }
    if (_containsAny(key, const ['camera', 'view', 'close-up', 'from'])) {
      return StudioScriptTokenCategory.camera;
    }
    if (_containsAny(key, const ['quality', 'masterpiece', 'highres'])) {
      return StudioScriptTokenCategory.quality;
    }
    return StudioScriptTokenCategory.other;
  }

  StudioScriptTokenCategory? _cachedReviewCategoryForTag(
    String tag, {
    required bool negative,
  }) {
    final entry = classificationCache.entryFor(tag, negative: negative);
    if (entry == null) {
      return null;
    }
    return _reviewCategoryForPromptCategory(entry.category, negative: negative);
  }

  StudioScriptTokenCategory? _manualReviewCategoryForTag(
    String tag, {
    required bool negative,
  }) {
    final entry = classificationCache.entryFor(tag, negative: negative);
    if (entry == null || !entry.source.startsWith('manual')) {
      return null;
    }
    return _reviewCategoryForPromptCategory(entry.category, negative: negative);
  }

  bool _aiArtistEvidenceMentionsTag(String tag) {
    if (!aiRoleExtraction.isReady || aiRoleExtraction.artistChains.isEmpty) {
      return false;
    }
    return _aiArtistEvidenceTerms().any((term) => _sameReviewTagKey(term, tag));
  }

  Iterable<String> _aiArtistEvidenceTerms() sync* {
    for (final chain in aiRoleExtraction.artistChains) {
      yield chain.label;
      yield* chain.terms;
      yield* chain.evidenceTerms;
    }
  }

  StudioScriptTokenEmphasis _reviewEmphasisForTag(String tag) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (key.isEmpty) {
      return StudioScriptTokenEmphasis.normal;
    }
    for (final role in roleMappings) {
      if (role.selectedCharacterId != null &&
          PromptTagProcessor.normalizeMatchKey(role.sourcePreview) == key) {
        return StudioScriptTokenEmphasis.replacementAffected;
      }
      for (final stage in role.stageItems) {
        if ((stage.selectedCharacterId != null ||
                stage.selectedUpperOutfitId != null ||
                stage.selectedLowerOutfitId != null) &&
            _promptPartsMentionTag(stage.parts, key)) {
          return StudioScriptTokenEmphasis.replacementAffected;
        }
      }
    }
    return StudioScriptTokenEmphasis.normal;
  }

  bool _promptPartsMentionTag(RecastPromptParts parts, String key) {
    return [
      parts.identity,
      parts.upperBody,
      parts.lowerBody,
      parts.upperClothing,
      parts.lowerClothing,
    ].any((text) => _textMentionsReviewTag(text, key));
  }

  bool _textMentionsReviewTag(String text, String key) {
    if (text.trim().isEmpty) {
      return false;
    }
    for (final tag in PromptTagProcessor.splitWorkshopTags(text)) {
      if (PromptTagProcessor.normalizeMatchKey(tag) == key) {
        return true;
      }
    }
    return PromptTagProcessor.normalizeMatchKey(text) == key;
  }

  bool _containsAny(String key, List<String> needles) {
    return needles.any(key.contains);
  }

  List<String> _roleSummary(List<ScriptFrame> frames, RecastMapping mapping) {
    if (mapping.roleAssemblies.isNotEmpty) {
      return [
        for (final assembly in mapping.roleAssemblies)
          '${assembly.displayLabel} -> ${assembly.sourceName.isEmpty ? 'unknown' : assembly.sourceName}',
      ];
    }
    final maxSlots = frames.fold<int>(
      0,
      (count, frame) => frame.parsed.charCaptions.length > count
          ? frame.parsed.charCaptions.length
          : count,
    );
    return [
      for (var index = 0; index < maxSlots; index += 1)
        '角色 ${index + 1} -> unknown',
    ];
  }

  List<StudioScriptRoleMappingItem> _roleMappingItems(
    List<ScriptFrame> frames,
    RecastMapping mapping,
  ) {
    if (mapping.roleAssemblies.isNotEmpty) {
      return [
        for (final assembly in mapping.roleAssemblies)
          _roleMappingItemFromAssembly(frames, assembly),
      ];
    }
    final selectedByRole = {
      for (final swap in mapping.roleSwaps) swap.sourceRoleId: swap,
    };
    final outfitByRole = {
      for (final item in roleMappings) item.sourceRoleId: item.selectedOutfitId,
    };
    final maxSlots = frames.fold<int>(
      0,
      (count, frame) => frame.parsed.charCaptions.length > count
          ? frame.parsed.charCaptions.length
          : count,
    );
    return [
      for (var index = 0; index < maxSlots; index += 1)
        StudioScriptRoleMappingItem(
          sourceRoleId: 'slot-$index',
          sourceLabel: '角色 ${index + 1}',
          sourcePreview: 'unknown',
          selectedCharacterId: selectedByRole['slot-$index']?.targetCharacterId,
          selectedOutfitId: outfitByRole['slot-$index'],
          stageItems: const [],
        ),
    ];
  }

  StudioScriptRoleMappingItem _roleMappingItemFromAssembly(
    List<ScriptFrame> frames,
    RoleAssembly assembly,
  ) {
    final selectedStageId = _selectedStageIdForRole(
      assembly.sourceRoleId,
      assembly,
    );
    final stages = [
      for (final stage in assembly.stages)
        StudioScriptRoleStageItem(
          id: stage.id,
          label: _roleAssemblyStageDisplayLabel(stage),
          frameIndexes: stage.frameIndexes,
          sourceSummary: stage.sourceSummary,
          sourceParts: stage.sourceParts,
          currentFrameSourceParts: _currentFrameSourcePartsForStage(
            frames: frames,
            assembly: assembly,
            stage: stage,
          ),
          parts: stage.manualParts,
          selectedCharacterId: stage.targetCharacterId,
          selectedUpperOutfitId: stage.targetUpperOutfitId,
          selectedLowerOutfitId: stage.targetLowerOutfitId,
          omittedParts: stage.omittedParts,
        ),
    ];
    final firstStage = assembly.stages.firstOrNull;
    final firstOutfit =
        firstStage?.targetUpperOutfitId == firstStage?.targetLowerOutfitId
            ? firstStage?.targetUpperOutfitId
            : firstStage?.targetUpperOutfitId;
    return StudioScriptRoleMappingItem(
      sourceRoleId: assembly.sourceRoleId,
      sourceLabel: assembly.displayLabel,
      sourcePreview: _sourcePreviewForAssembly(frames, assembly),
      selectedCharacterId: firstStage?.targetCharacterId,
      selectedOutfitId: firstOutfit,
      stageItems: List.unmodifiable(stages),
      selectedStageId: selectedStageId,
    );
  }

  List<StudioScriptRoleReplacementItem> _roleReplacementItems(
    RecastMapping mapping,
  ) {
    final result = <StudioScriptRoleReplacementItem>[];
    for (final replacement in mapping.rolePromptReplacements) {
      final assembly = mapping.roleAssemblies
          .where(
            (assembly) => assembly.sourceRoleId == replacement.sourceRoleId,
          )
          .firstOrNull;
      final layerResult = roleReplacementLayerService.resolve(
        replacement: replacement,
        assembly: assembly,
      );
      final ruleItemsById = <String, StudioScriptReplacementRuleItem>{};
      for (final rule in replacement.rules) {
        final assignment = layerResult.assignmentForRule(rule.id);
        ruleItemsById[rule.id] = _replacementRuleItem(
          rule,
          selected:
              _selectedRoleReplacementRuleIdsByRole[replacement.sourceRoleId]
                      ?.contains(rule.id) ??
                  false,
          assignment: assignment,
        );
      }
      final rules = List<StudioScriptReplacementRuleItem>.unmodifiable([
        for (final rule in replacement.rules) ruleItemsById[rule.id]!,
      ]);
      result.add(
        StudioScriptRoleReplacementItem(
          sourceRoleId: replacement.sourceRoleId,
          sourceLabel: replacement.displayLabel,
          sourcePreview: replacement.sourcePreview,
          targetCharacterId: replacement.targetCharacterId,
          targetIdentityPrompt: replacement.targetIdentityPrompt,
          activeMappingProfileId: replacement.activeMappingProfileId,
          rules: rules,
          layers: List.unmodifiable([
            for (final layer in layerResult.layers)
              StudioScriptRoleReplacementLayerItem(
                id: layer.id,
                label: layer.label,
                kind: layer.kind,
                stageId: layer.stageId,
                frameIndexes: layer.frameIndexes,
                rules: List.unmodifiable([
                  for (final ruleId in layer.ruleIds) ruleItemsById[ruleId]!,
                ]),
                mappedRuleCount: layer.mappedRuleCount,
              ),
          ]),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  List<StudioScriptSceneReplacementItem> _sceneReplacementItems(
    RecastMapping mapping,
  ) {
    return List.unmodifiable([
      for (final replacement in mapping.scenePromptReplacements)
        StudioScriptSceneReplacementItem(
          id: replacement.id,
          label: replacement.label,
          rules: List.unmodifiable([
            for (final rule in replacement.rules)
              _replacementRuleItem(
                rule,
                selected:
                    _selectedSceneReplacementRuleIdsByGroup[replacement.id]
                            ?.contains(rule.id) ??
                        false,
              ),
          ]),
        ),
    ]);
  }

  StudioScriptReplacementRuleItem _replacementRuleItem(
    ScriptPromptReplacementRule rule, {
    required bool selected,
    ScriptRoleReplacementLayerAssignment? assignment,
  }) {
    return StudioScriptReplacementRuleItem(
      id: rule.id,
      sourceTerms: List.unmodifiable([
        for (final term in rule.sourceTerms)
          term.copyWith(frameIndexes: List.unmodifiable(term.frameIndexes)),
      ]),
      excludedTermIds: List.unmodifiable(rule.excludedTermIds),
      action: rule.action,
      matchMode: rule.matchMode,
      targetPrompt: rule.targetPrompt,
      targetWeightMultiplier: rule.targetWeightMultiplier,
      manualPhrase: rule.manualPhrase,
      anchorTermId: rule.anchorTermId,
      selected: selected,
      layerKind: assignment?.kind ?? ScriptRoleReplacementRuleLayerKind.pending,
      layerStageId: assignment?.stageId ?? '',
      manuallyLayered: assignment?.isManual ?? false,
      hasStaleLayerOverride: assignment?.hasStaleOverride ?? false,
    );
  }

  RecastPromptParts? _currentFrameSourcePartsForStage({
    required List<ScriptFrame> frames,
    required RoleAssembly assembly,
    required RoleAssemblyStage stage,
  }) {
    final selectedFrameIndex = _selectedFrameIndex;
    if (selectedFrameIndex == null ||
        (stage.frameIndexes.isNotEmpty &&
            !stage.frameIndexes.contains(selectedFrameIndex))) {
      return null;
    }
    final frame = frames
        .where((candidate) => candidate.index == selectedFrameIndex)
        .firstOrNull;
    if (frame == null) {
      return null;
    }
    final captions = _positiveCaptionsForAssemblyStageFrame(
      frame: frame,
      assembly: assembly,
      stage: stage,
    );
    if (captions.isEmpty) {
      return null;
    }
    final evidence = _evidenceTagsByKey(captions);
    final scopedParts = RecastPromptParts(
      identity: _sourcePartsSupportedByEvidence(
        stage.sourceParts.identity,
        evidence,
      ),
      upperBody: _sourcePartsSupportedByEvidence(
        stage.sourceParts.upperBody,
        evidence,
      ),
      lowerBody: _sourcePartsSupportedByEvidence(
        stage.sourceParts.lowerBody,
        evidence,
      ),
      upperClothing: _sourcePartsSupportedByEvidence(
        stage.sourceParts.upperClothing,
        evidence,
      ),
      lowerClothing: _sourcePartsSupportedByEvidence(
        stage.sourceParts.lowerClothing,
        evidence,
      ),
    );
    if (_promptPartsEqual(stage.sourceParts, scopedParts)) {
      return null;
    }
    return scopedParts;
  }

  String _sourcePartsSupportedByEvidence(
    String value,
    Map<String, String> evidence,
  ) {
    final supported = <String>[];
    final seen = <String>{};
    for (final rawTag in PromptTagProcessor.splitWorkshopTags(value)) {
      final clean = PromptTagProcessor.cleanTagDisplay(rawTag).trim();
      final evidenceTag = _supportedEvidenceTagForTerm(clean, evidence);
      if (evidenceTag == null) {
        continue;
      }
      final key = PromptTagProcessor.normalizeMatchKey(evidenceTag);
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      supported.add(evidenceTag);
    }
    return _joinPromptTags(supported);
  }

  List<String> _positiveCaptionsForAssemblyStageFrame({
    required ScriptFrame frame,
    required RoleAssembly assembly,
    required RoleAssemblyStage stage,
  }) {
    final captions = <String>[];
    final seen = <String>{};
    void add(String value) {
      if (value.trim().isEmpty || !seen.add(value)) {
        return;
      }
      captions.add(value);
    }

    for (final appearance in assembly.sourceAppearances) {
      if (appearance.frameIndexes.isNotEmpty &&
          !appearance.frameIndexes.contains(frame.index)) {
        continue;
      }
      for (final caption in _captionsForSourceRef(
        frame: frame,
        sourceId: appearance.sourceId,
        sourceKind: appearance.sourceKind,
      )) {
        add(caption);
      }
    }
    if (captions.isNotEmpty) {
      return List.unmodifiable(captions);
    }

    for (final caption in _positiveCaptionsForSourceRole(
      frame,
      assembly.sourceRoleId,
    )) {
      add(caption);
    }
    if (captions.isNotEmpty) {
      return List.unmodifiable(captions);
    }

    return _captionsMatchingIdentity(
      frame: frame,
      identityTexts: [
        assembly.sourceName,
        assembly.displayLabel,
        stage.sourceParts.identity,
      ],
    );
  }

  String _roleAssemblyStageDisplayLabel(RoleAssemblyStage stage) {
    final current = stage.label.trim();
    if (current.isEmpty || _isGenericAiOutfitStageLabel(current)) {
      return _derivedAiOutfitStageLabelFromParts(
            stage.sourceParts,
            translationCache: translationCache,
          ) ??
          stage.label;
    }
    return _localizedOrCachedAiOutfitLabel(
          current,
          translationCache: translationCache,
        ) ??
        stage.label;
  }

  String _sourcePreviewForAssembly(
    List<ScriptFrame> frames,
    RoleAssembly assembly,
  ) {
    if (assembly.sourceName.trim().isNotEmpty) {
      return assembly.sourceName;
    }
    return 'unknown';
  }

  List<StudioScriptArtistMappingItem> _artistMappingItems(
    List<ScriptFrame> frames,
    RecastMapping mapping,
  ) {
    final sources = _uniqueTags([
      ..._artistSourceLabels(frames),
      ..._aiArtistSourceLabels(),
    ]);
    final artistSwap = mapping.artistSwap;
    final storedSourceLabel = artistSwap?.sourceArtistPrompt.trim() ?? '';
    final sourceLabel = _artistSourceLabelOverride ??
        (storedSourceLabel.isNotEmpty
            ? storedSourceLabel
            : sources.isEmpty
                ? 'source unchanged'
                : sources.join(', '));
    final selectedArtistChainId = artistSwap?.targetArtistChainId.trim() ?? '';
    return [
      StudioScriptArtistMappingItem(
        sourceLabel: sourceLabel,
        selectedArtistChainId:
            selectedArtistChainId.isEmpty ? null : selectedArtistChainId,
        manualPrompt: artistSwap?.manualPrompt.trim() ?? '',
        deleteSource: artistSwap?.deleteSource ?? false,
      ),
    ];
  }

  List<StudioScriptPromptBlockMappingItem> _promptBlockMappingItems(
    List<ScriptFrame> frames,
    RecastMapping mapping,
  ) {
    return [
      _promptBlockMappingItem(
        frames: frames,
        mapping: mapping,
        block: 'style',
        label: '风格',
      ),
      _promptBlockMappingItem(
        frames: frames,
        mapping: mapping,
        block: 'quality',
        label: '质量词',
      ),
    ];
  }

  StudioScriptPromptBlockMappingItem _promptBlockMappingItem({
    required List<ScriptFrame> frames,
    required RecastMapping mapping,
    required String block,
    required String label,
  }) {
    final swap = mapping.promptBlockSwaps
        .where((candidate) => candidate.block == block)
        .firstOrNull;
    final detectedSource = _promptBlockSourceLabels(frames, block).join(', ');
    final sourcePrompt = swap?.sourcePrompt.trim().isNotEmpty == true
        ? swap!.sourcePrompt.trim()
        : detectedSource;
    return StudioScriptPromptBlockMappingItem(
      block: block,
      label: label,
      sourcePrompt: sourcePrompt,
      manualPrompt: swap?.manualPrompt.trim() ?? '',
      deleteSource: swap?.deleteSource ?? false,
    );
  }

  List<String> _promptBlockSourceLabels(
    List<ScriptFrame> frames,
    String block,
  ) {
    final tags = <String>[];
    for (final frame in frames) {
      final buckets = PromptTagProcessor.heuristicSplit(
        _frameBaseCaption(frame),
        config: _blockWordConfig(),
      );
      tags.addAll(switch (block) {
        'style' => buckets.style,
        'quality' => buckets.quality,
        _ => const <String>[],
      });
    }
    return _uniqueTags(tags);
  }

  String _currentArtistSourceLabel() {
    final current =
        artistMappings.isEmpty ? '' : artistMappings.first.sourceLabel.trim();
    if (current.isNotEmpty && current != 'source unchanged') {
      return current;
    }
    final script = _script;
    if (script == null) {
      return '';
    }
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    return _artistSourceLabels(parsedFrames).join(', ');
  }

  List<String> _aiArtistSourceLabels() {
    final extraction = aiRoleExtraction;
    if (!extraction.isReady || extraction.artistChains.isEmpty) {
      return const [];
    }
    final labels = <String>[];
    for (final chain in extraction.artistChains) {
      if (chain.terms.isNotEmpty) {
        labels.addAll(chain.terms);
      } else if (chain.label.trim().isNotEmpty) {
        labels.add(chain.label);
      } else {
        labels.addAll(chain.evidenceTerms);
      }
    }
    return _uniqueTags(labels);
  }

  void _refreshTimeline() {
    final script = _script;
    if (script == null) {
      timeline = const [];
      return;
    }
    timeline = [for (final frame in script.frames) _timelineItemFor(frame)];
  }

  void _refreshSelectedFrameTagGroups() {
    final script = _script;
    if (script == null || script.frames.isEmpty) {
      selectedFrameTagGroups = const [];
      selectedFramePreviews = const [];
      return;
    }
    final frame = script.frames
            .where((candidate) => candidate.index == _selectedFrameIndex)
            .firstOrNull ??
        script.frames.first;
    if (frame.parseStatus != ScriptFrameParseStatus.parsed) {
      selectedFrameTagGroups = [
        StudioScriptFrameTagGroup(
          id: 'frame-${frame.index}-status',
          label: '场景',
          tags: frame.warnings.isEmpty ? const ['解析失败'] : frame.warnings,
        ),
      ];
      selectedFramePreviews = [
        StudioScriptFrameSplitPreview(
          id: 'before',
          title: '处理前',
          groups: selectedFrameTagGroups,
        ),
        StudioScriptFrameSplitPreview(
          id: 'after',
          title: '处理后',
          groups: selectedFrameTagGroups,
        ),
      ];
      return;
    }

    final beforeGroups = _frameTagGroupsFromCaptions(
      idPrefix: 'before-',
      baseCaption: _frameBaseCaption(frame),
      charCaptions: frame.parsed.charCaptions,
    );
    final afterParts = _selectedFrameRecastCaptionParts(frame);
    final afterGroups = _frameTagGroupsFromCaptions(
      idPrefix: 'after-',
      baseCaption: afterParts.$1,
      charCaptions: afterParts.$2,
    );
    selectedFramePreviews = [
      StudioScriptFrameSplitPreview(
        id: 'before',
        title: '处理前',
        groups: beforeGroups,
      ),
      StudioScriptFrameSplitPreview(
        id: 'after',
        title: '处理后',
        groups: afterGroups,
      ),
    ];
    selectedFrameTagGroups = [
      for (final group in afterGroups)
        StudioScriptFrameTagGroup(
          id: group.id.replaceFirst('after-', ''),
          label: group.label,
          tags: group.tags,
        ),
    ];
  }

  List<StudioScriptFrameTagGroup> _frameTagGroupsFromCaptions({
    required String idPrefix,
    required String baseCaption,
    required List<String> charCaptions,
  }) {
    final baseBuckets = PromptTagProcessor.heuristicSplit(
      baseCaption,
      config: _blockWordConfig(),
    );
    return [
      for (final (index, caption) in charCaptions.indexed)
        StudioScriptFrameTagGroup(
          id: '${idPrefix}role-${index + 1}',
          label: '角色 ${index + 1}',
          tags: _tagsOrEmpty(_splitDisplayTags(caption)),
        ),
      StudioScriptFrameTagGroup(
        id: '${idPrefix}artist-chain',
        label: '画师串',
        tags: _tagsOrEmpty(baseBuckets.artist),
      ),
      StudioScriptFrameTagGroup(
        id: '${idPrefix}quality',
        label: '质量词',
        tags: _tagsOrEmpty(baseBuckets.quality),
      ),
      StudioScriptFrameTagGroup(
        id: '${idPrefix}scene',
        label: '场景',
        tags: _tagsOrEmpty([
          ...baseBuckets.scene,
          ...baseBuckets.style,
          ...baseBuckets.character,
        ]),
      ),
    ];
  }

  (String, List<String>) _selectedFrameRecastCaptionParts(ScriptFrame frame) {
    final recastFrame = _previewResult?.frames.firstWhere(
      (payload) => payload.frameIndex == frame.index,
      orElse: () => _previewResult!.frames.first,
    );
    return _payloadCaptionParts(recastFrame?.payload) ??
        (_frameBaseCaption(frame), frame.parsed.charCaptions);
  }

  StudioScriptTimelineItem _timelineItemFor(ScriptFrame frame) {
    final statuses = <StudioScriptTimelineStatus>[];
    if (frame.parseStatus == ScriptFrameParseStatus.error) {
      statuses.add(StudioScriptTimelineStatus.error);
    } else if (frame.warnings.isNotEmpty) {
      statuses.add(StudioScriptTimelineStatus.warning);
    }
    switch (_frameResultStatuses[frame.index]) {
      case FrameResultStatus.completed:
        statuses.add(StudioScriptTimelineStatus.sent);
      case FrameResultStatus.failed:
        statuses.add(StudioScriptTimelineStatus.failed);
      case FrameResultStatus.queued:
      case FrameResultStatus.running:
      case FrameResultStatus.skipped:
      case null:
        break;
    }
    return StudioScriptTimelineItem(
      frameIndex: frame.index,
      label: '${frame.index}帧',
      selected: frame.index == _selectedFrameIndex,
      warning: statuses.contains(StudioScriptTimelineStatus.warning) ||
          statuses.contains(StudioScriptTimelineStatus.error),
      statuses: List.unmodifiable(statuses),
    );
  }

  int? _slotIndexForRole(String sourceRoleId) {
    final match = RegExp(r'^slot-(\d+)$').firstMatch(sourceRoleId);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  List<String> _artistSummary(List<ScriptFrame> frames) {
    final artists = _artistSourceLabels(frames);
    if (artists.isEmpty) {
      return const ['source unchanged -> target unchanged'];
    }
    return ['source ${artists.join(', ')} -> target unchanged'];
  }

  List<String> _artistSourceLabels(List<ScriptFrame> frames) {
    final artists = <String>{};
    for (final frame in frames) {
      for (final tag in PromptTagProcessor.splitWorkshopTags(
        _frameBaseCaption(frame),
      )) {
        final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
        if (clean.isEmpty) {
          continue;
        }
        if (_reviewCategoryForTag(clean, negative: false) ==
            StudioScriptTokenCategory.artistChain) {
          artists.add(clean);
        }
      }
    }
    return artists.toList(growable: false);
  }

  StudioScriptDiff _diffFor(List<ScriptFrame> frames) {
    if (frames.isEmpty) {
      return const StudioScriptDiff(original: '', recast: '');
    }
    final frame = frames
            .where((candidate) => candidate.index == _selectedFrameIndex)
            .firstOrNull ??
        frames.first;
    final recastFrame = _previewResult?.frames.firstWhere(
      (payload) => payload.frameIndex == frame.index,
      orElse: () => _previewResult!.frames.first,
    );
    final originalCaption = _frameCaptionSummary(frame);
    final recastCaption = _payloadCaptionSummary(recastFrame?.payload);
    return StudioScriptDiff(
      original: originalCaption,
      recast: recastCaption ?? originalCaption,
    );
  }

  String _frameCaptionSummary(ScriptFrame frame) {
    return _captionSummary(
      baseCaption: _frameBaseCaption(frame),
      charCaptions: frame.parsed.charCaptions,
    );
  }

  String _frameBaseCaption(ScriptFrame frame) {
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

  String? _payloadCaptionSummary(Map<String, dynamic>? payload) {
    final parts = _payloadCaptionParts(payload);
    if (parts == null) {
      return null;
    }
    return _captionSummary(baseCaption: parts.$1, charCaptions: parts.$2);
  }

  (String, List<String>)? _payloadCaptionParts(Map<String, dynamic>? payload) {
    final comment = payload?['Comment'];
    if (comment is! Map) {
      return null;
    }
    final prompt = comment['v4_prompt'];
    if (prompt is! Map) {
      return null;
    }
    final caption = prompt['caption'];
    if (caption is! Map) {
      return null;
    }
    final baseCaption = caption['base_caption'];
    if (baseCaption is! String) {
      return null;
    }
    final charCaptions = <String>[];
    final rawCharCaptions = caption['char_captions'];
    if (rawCharCaptions is List) {
      for (final item in rawCharCaptions) {
        if (item is! Map) {
          continue;
        }
        final charCaption = item['char_caption'];
        if (charCaption is String && charCaption.trim().isNotEmpty) {
          charCaptions.add(charCaption);
        }
      }
    }
    return (baseCaption, charCaptions);
  }

  String _captionSummary({
    required String baseCaption,
    required List<String> charCaptions,
  }) {
    final parts = [
      baseCaption,
      for (final (index, caption) in charCaptions.indexed)
        if (caption.trim().isNotEmpty) '角色${index + 1}: $caption',
    ];
    return parts.where((part) => part.trim().isNotEmpty).join('\n');
  }

  List<String> _splitDisplayTags(String text) {
    return PromptTagProcessor.splitWorkshopTags(text)
        .map(_displayTagPreservingWeights)
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  String _cleanDisplayTag(String tag) {
    return PromptTagProcessor.cleanTagDisplay(tag).trim();
  }

  String _displayTagPreservingWeights(String tag) {
    return PromptTagProcessor.cleanTagDisplay(tag, removeWeights: false).trim();
  }

  String _promptTermTextPreservingWeight(
    String existingText,
    String displayText,
  ) {
    final display = displayText.trim();
    if (existingText.trim().isEmpty) {
      return display;
    }
    if (_hasPromptWeight(display) && !_hasPromptWeight(existingText)) {
      return display;
    }
    return existingText.trim();
  }

  bool _hasPromptWeight(String text) {
    return PromptTagProcessor.analyzeWorkshopTags(text)
        .any((tag) => tag.weight != null);
  }

  List<String> _tagsOrEmpty(List<String> tags) {
    return tags.isEmpty ? const ['未检测'] : List.unmodifiable(tags);
  }

  String _effectiveBlockWords() {
    return mergeFilterRuleWords(
      globalBlockWords,
      PromptTagProcessor.splitWorkshopTags(scriptBlockWords),
    );
  }

  FilterRuleConfig _blockWordConfig() {
    return _filterRuleConfig.copyWith(
      deleteKeywords: _effectiveBlockWords(),
      exactMatch: false,
      removeWeights: false,
    );
  }

  String _productionPlanId(Script script) {
    final nameSlug = _slugOrEmpty(script.name);
    if (nameSlug.isNotEmpty) {
      return 'script-recast-$nameSlug';
    }
    return 'script-recast-${_slug(script.id)}';
  }

  String _slug(String value) {
    final slug = _slugOrEmpty(value);
    return slug.isEmpty ? 'script' : slug;
  }

  String _slugOrEmpty(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
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
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }
    return List.unmodifiable(result);
  }

  bool _looksLikeUpperOutfitTag(String tag) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    return const [
      'shirt',
      'blouse',
      'jacket',
      'coat',
      'top',
      'crop top',
      'armor',
      'dress',
      'ribbon',
      'collar',
      'gloves',
      'sleeves',
      'hat',
      'hair',
    ].any(key.contains);
  }

  bool _looksLikeLowerOutfitTag(String tag) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    return const [
      'skirt',
      'shorts',
      'pants',
      'boots',
      'shoes',
      'socks',
      'thighhighs',
      'pantyhose',
      'belt',
      'leg',
      'tail',
    ].any(key.contains);
  }
}

PromptTagCategory _promptCategoryForReviewCategory(
  StudioScriptTokenCategory category,
) {
  return switch (category) {
    StudioScriptTokenCategory.character => PromptTagCategory.character,
    StudioScriptTokenCategory.upperBody => PromptTagCategory.upperBody,
    StudioScriptTokenCategory.lowerBody => PromptTagCategory.lowerBody,
    StudioScriptTokenCategory.upperClothing => PromptTagCategory.upperClothing,
    StudioScriptTokenCategory.lowerClothing => PromptTagCategory.lowerClothing,
    StudioScriptTokenCategory.action => PromptTagCategory.action,
    StudioScriptTokenCategory.scene => PromptTagCategory.scene,
    StudioScriptTokenCategory.camera => PromptTagCategory.camera,
    StudioScriptTokenCategory.artistChain => PromptTagCategory.artist,
    StudioScriptTokenCategory.style => PromptTagCategory.style,
    StudioScriptTokenCategory.quality => PromptTagCategory.quality,
    StudioScriptTokenCategory.negativeQuality =>
      PromptTagCategory.negativeQuality,
    StudioScriptTokenCategory.negativeBody => PromptTagCategory.negativeBody,
    StudioScriptTokenCategory.negativeArtist =>
      PromptTagCategory.negativeArtist,
    StudioScriptTokenCategory.negativeContent =>
      PromptTagCategory.negativeContent,
    StudioScriptTokenCategory.other => PromptTagCategory.other,
  };
}

StudioScriptTokenCategory _reviewCategoryForPromptCategory(
  PromptTagCategory category, {
  required bool negative,
}) {
  return switch (category) {
    PromptTagCategory.character => StudioScriptTokenCategory.character,
    PromptTagCategory.upperBody => StudioScriptTokenCategory.upperBody,
    PromptTagCategory.lowerBody => StudioScriptTokenCategory.lowerBody,
    PromptTagCategory.upperClothing => StudioScriptTokenCategory.upperClothing,
    PromptTagCategory.lowerClothing => StudioScriptTokenCategory.lowerClothing,
    PromptTagCategory.accessory => StudioScriptTokenCategory.upperBody,
    PromptTagCategory.clothingState => StudioScriptTokenCategory.upperClothing,
    PromptTagCategory.clothing => StudioScriptTokenCategory.upperClothing,
    PromptTagCategory.action => StudioScriptTokenCategory.action,
    PromptTagCategory.scene => StudioScriptTokenCategory.scene,
    PromptTagCategory.camera => StudioScriptTokenCategory.camera,
    PromptTagCategory.artist => negative
        ? StudioScriptTokenCategory.negativeArtist
        : StudioScriptTokenCategory.artistChain,
    PromptTagCategory.style => StudioScriptTokenCategory.style,
    PromptTagCategory.quality => StudioScriptTokenCategory.quality,
    PromptTagCategory.negativeQuality =>
      StudioScriptTokenCategory.negativeQuality,
    PromptTagCategory.negativeBody => StudioScriptTokenCategory.negativeBody,
    PromptTagCategory.negativeArtist =>
      StudioScriptTokenCategory.negativeArtist,
    PromptTagCategory.negativeContent =>
      StudioScriptTokenCategory.negativeContent,
    PromptTagCategory.promptSyntax => StudioScriptTokenCategory.other,
    PromptTagCategory.other => StudioScriptTokenCategory.other,
  };
}

bool _sameReviewTagKey(String left, String right) {
  final leftKey = PromptTagProcessor.normalizeMatchKey(left);
  final rightKey = PromptTagProcessor.normalizeMatchKey(right);
  if (leftKey.isEmpty || rightKey.isEmpty) {
    return false;
  }
  if (leftKey == rightKey) {
    return true;
  }
  final leftArtistKey = _stripArtistPrefix(leftKey);
  final rightArtistKey = _stripArtistPrefix(rightKey);
  return leftArtistKey.isNotEmpty && leftArtistKey == rightArtistKey;
}

String _stripArtistPrefix(String key) {
  return key.replaceFirst(RegExp(r'^artist\s*[: ]\s*'), '').trim();
}

String? _firstPreviewPath(List<String> paths) =>
    paths.isEmpty ? null : paths.first;

List<String> _previewPathsForAsset(String? preferredPath, List<String> refs) {
  final paths = <String>[];
  void addPath(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty || paths.contains(trimmed)) {
      return;
    }
    paths.add(trimmed);
  }

  addPath(preferredPath);
  for (final path in _existingImagePaths(refs)) {
    addPath(path);
  }
  return List.unmodifiable(paths);
}

List<String> _existingImagePaths(List<String> refs) {
  final paths = <String>[];
  for (final ref in refs) {
    final trimmed = ref.trim();
    if (trimmed.isEmpty) continue;
    final file = File(trimmed);
    if (file.isAbsolute && file.existsSync()) {
      final path = file.path;
      if (!paths.contains(path)) {
        paths.add(path);
      }
    }
  }
  return List.unmodifiable(paths);
}

String _normalizeBlockWords(String value) {
  return value
      .split(RegExp(r'[,，\n]'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .join(', ');
}

List<String> _normalizeFilterRuleTags(List<String> tags) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in tags) {
    for (final tag in PromptTagProcessor.splitWorkshopTags(raw)) {
      final trimmed = tag.trim();
      final key = PromptTagProcessor.normalizeMatchKey(trimmed);
      if (trimmed.isEmpty || key.isEmpty || !seen.add(key)) {
        continue;
      }
      result.add(trimmed);
    }
  }
  return result;
}

int _blockWordCount(String value) {
  if (value.trim().isEmpty) {
    return 0;
  }
  return value
      .split(RegExp(r'[,，\n]'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .length;
}

String _summaryFromPromptParts(RecastPromptParts parts) {
  return [
    parts.upperClothing,
    parts.lowerClothing,
    parts.upperBody,
    parts.lowerBody,
  ].where((part) => part.trim().isNotEmpty).join(', ');
}

String _aiOutfitStageLabel(
  String label, {
  required String fallback,
  TranslationCache? translationCache,
}) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }
  return _localizedOrCachedAiOutfitLabel(
        trimmed,
        translationCache: translationCache,
      ) ??
      trimmed;
}

String _aiOutfitStageDisplayLabel(
  ScriptAiExtractedStage stage, {
  required String fallback,
  required int index,
  TranslationCache? translationCache,
}) {
  final label = _aiOutfitStageLabel(
    stage.label,
    fallback: '',
    translationCache: translationCache,
  ).trim();
  if (label.isNotEmpty && !_isGenericAiOutfitStageLabel(label)) {
    return label;
  }
  final derived = _derivedAiOutfitStageLabel(
    stage,
    translationCache: translationCache,
  );
  if (derived != null) {
    return derived;
  }
  if (label.isNotEmpty) {
    return label;
  }
  final trimmedFallback = fallback.trim();
  return trimmedFallback.isEmpty ? 'AI 服装 ${index + 1}' : trimmedFallback;
}

String? _derivedAiOutfitStageLabel(
  ScriptAiExtractedStage stage, {
  TranslationCache? translationCache,
}) {
  return _derivedAiOutfitStageLabelFromParts(
    RecastPromptParts(
      upperClothing: stage.upperClothing,
      lowerClothing: stage.lowerClothing,
    ),
    translationCache: translationCache,
  );
}

String? _derivedAiOutfitStageLabelFromParts(
  RecastPromptParts parts, {
  TranslationCache? translationCache,
}) {
  final tags = <String>[];
  void addField(String value) {
    for (final tag in PromptTagProcessor.splitWorkshopTags(value)) {
      final display = PromptTagProcessor.cleanTagDisplay(tag);
      if (display.trim().isNotEmpty) {
        tags.add(display.trim());
      }
    }
  }

  addField(parts.upperClothing);
  addField(parts.lowerClothing);
  final selected = _uniqueAiOutfitLabelTags(tags).take(3).toList();
  if (selected.isEmpty) {
    return null;
  }
  return selected
      .map(
        (tag) =>
            _aiOutfitTagDisplayLabel(tag, translationCache: translationCache),
      )
      .join(' / ');
}

List<String> _uniqueAiOutfitLabelTags(Iterable<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final tag in tags) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (key.isEmpty || _isNoisyAiOutfitLabelKey(key)) {
      continue;
    }
    if (seen.add(key)) {
      result.add(tag);
    }
  }
  return List.unmodifiable(result);
}

bool _isGenericAiOutfitStageLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return true;
  }
  if (RegExp(r'^(?:AI\s*)?服装\s*\d+$').hasMatch(trimmed)) {
    return true;
  }
  final key = trimmed
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return RegExp(r'^(?:ai )?(?:outfit|clothing|costume) \d+$').hasMatch(key) ||
      RegExp(r'^(?:ai )?stage(?: \d+)+$').hasMatch(key);
}

const _noisyAiOutfitLabelKeys = {
  'clothes',
  'clothing',
  'outfit',
  'costume',
  'wearing',
  'clothed',
};

bool _isNoisyAiOutfitLabelKey(String key) {
  return _noisyAiOutfitLabelKeys.contains(key) ||
      RegExp(
        r'(^| )(sex|cum|semen|penis|pussy|vagina|clitoris|orgasm|'
        r'masturbat|ejaculat|saliva|drool|blush|embarrassed|standing|'
        r'sitting|kneeling|lying|pov|close up|from behind)( |$)',
      ).hasMatch(key);
}

String _aiOutfitTagDisplayLabel(
  String tag, {
  TranslationCache? translationCache,
}) {
  final trimmed = tag.trim();
  if (trimmed.isEmpty || RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed)) {
    return trimmed;
  }
  return _localizedOrCachedAiOutfitLabel(
        trimmed,
        translationCache: translationCache,
      ) ??
      trimmed;
}

String? _localizedGeneratedAiOutfitLabel(
  String label, {
  TranslationCache? translationCache,
}) {
  final trimmed = label.trim();
  if (trimmed.isEmpty || RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed)) {
    return null;
  }
  if (!trimmed.contains('/')) {
    return null;
  }
  return _localizedOrCachedAiOutfitLabel(
    trimmed,
    translationCache: translationCache,
  );
}

String? _localizedOrCachedAiOutfitLabel(
  String label, {
  TranslationCache? translationCache,
}) {
  final trimmed = label.trim();
  if (trimmed.isEmpty || RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed)) {
    return null;
  }
  final local = _localizedAiOutfitLabel(trimmed);
  if (local != null && local.trim().isNotEmpty) {
    return local.trim();
  }
  final cached = _cachedAiOutfitTranslation(
    trimmed,
    translationCache: translationCache,
  );
  if (cached != null) {
    return cached;
  }
  return _localizedSlashSeparatedAiOutfitLabel(
    trimmed,
    translationCache: translationCache,
  );
}

String? _localizedSlashSeparatedAiOutfitLabel(
  String label, {
  TranslationCache? translationCache,
}) {
  final parts = label
      .split(RegExp(r'\s*/\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) {
    return null;
  }
  var changed = false;
  final translated = [
    for (final part in parts)
      () {
        final local = _localizedAiOutfitLabel(part);
        final cached = local ??
            _cachedAiOutfitTranslation(
              part,
              translationCache: translationCache,
            );
        if (cached != null && cached.trim().isNotEmpty) {
          changed = true;
          return cached.trim();
        }
        return part;
      }(),
  ];
  return changed ? translated.join(' / ') : null;
}

String? _cachedAiOutfitTranslation(
  String label, {
  TranslationCache? translationCache,
}) {
  final translated = translationCache?.translate(label).text.trim();
  if (translated == null || translated.isEmpty || translated == label.trim()) {
    return null;
  }
  return translated;
}

String? _localizedAiOutfitLabel(String label) {
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(label)) {
    return null;
  }
  final key = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (key.isEmpty) {
    return null;
  }
  final numbered = RegExp(
    r'^(?:outfit|clothing|costume) (\d+)$',
  ).firstMatch(key);
  if (numbered != null) {
    return '服装 ${numbered.group(1)}';
  }
  if (key.contains('nude')) {
    if (key.contains('choker') || key.contains('collar')) {
      return '裸体（项圈）';
    }
    if (key.contains('beach') && key.contains('oil')) {
      return '裸体（海边/涂油）';
    }
    if (key.contains('oil')) {
      return '裸体（涂油）';
    }
    return '裸体';
  }
  if (key == 'casual outfit' || key == 'casual clothes') {
    return '休闲服';
  }
  if (key == 'kimono' || key == 'yukata') {
    return '和服';
  }
  if (key == 'school uniform') {
    return '校服';
  }
  if (key == 'nightgown') {
    return '睡裙';
  }
  if (key == 'china dress' || key == 'chinese dress') {
    return '旗袍';
  }
  if ((key.contains('tanktop') || key.contains('tank top')) &&
      key.contains('bottomless')) {
    if (key.contains('white')) {
      return '白色背心（下身无装）';
    }
    return '背心（下身无装）';
  }
  if (key.contains('bikini') || key.contains('swimsuit')) {
    final parts = <String>[];
    if (key.contains('white')) {
      parts.add('白色');
    }
    if (key.contains('string')) {
      parts.add('细带');
    }
    if (key.contains('bikini')) {
      parts.add('比基尼');
    }
    parts.add('泳装');
    return parts.join();
  }
  return null;
}

List<WorkspaceVibeReference> _mergeVibeReferences(
  Iterable<WorkspaceVibeReference> existing,
  Iterable<WorkspaceVibeReference> additions,
) {
  final seen = <String>{};
  final result = <WorkspaceVibeReference>[];
  for (final vibe in [...existing, ...additions]) {
    final key = _vibeReferenceKey(vibe);
    if (key.trim().isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(vibe);
  }
  return result;
}

String _vibeReferenceKey(WorkspaceVibeReference vibe) {
  final encoding = vibe.vibeB64.trim();
  return encoding.isEmpty ? vibe.id : encoding;
}

List<WorkspaceVibeReference> _sourceVibesFromScript(
  Script? script,
  List<WorkspaceVibeReference> availableVibes,
) {
  if (script == null) {
    return const [];
  }
  final availableByEncoding = {
    for (final vibe in availableVibes)
      if (vibe.vibeB64.trim().isNotEmpty) vibe.vibeB64.trim(): vibe,
  };
  final seen = <String>{};
  final result = <WorkspaceVibeReference>[];
  for (final frame in script.frames) {
    if (frame.parseStatus != ScriptFrameParseStatus.parsed) {
      continue;
    }
    final params = frame.parsed.generationParams;
    final images = _dynamicList(params['reference_image_multiple']);
    if (images.isEmpty) {
      continue;
    }
    final strengths = _dynamicList(params['reference_strength_multiple']);
    final infoExtracted = _dynamicList(
      params['reference_information_extracted_multiple'],
    );
    for (var index = 0; index < images.length; index += 1) {
      final encoding = (images[index] as String?)?.trim();
      if (encoding == null || encoding.isEmpty || !seen.add(encoding)) {
        continue;
      }
      final matched = availableByEncoding[encoding];
      result.add(
        WorkspaceVibeReference(
          id: matched?.id ??
              stableIdFromText(
                prefix: 'script-source-vibe',
                text: encoding,
                label: 'source-vibe-${result.length + 1}',
              ),
          name: matched?.name ?? '剧本 Vibe ${result.length + 1}',
          vibeB64: encoding,
          referenceStrength: _doubleAt(strengths, index, fallback: 0.6),
          infoExtracted: _doubleAt(infoExtracted, index, fallback: 1.0),
          source: const SourceRef(type: 'script'),
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

List<dynamic> _dynamicList(dynamic value) {
  return value is List ? value : const [];
}

double _doubleAt(List<dynamic> values, int index, {required double fallback}) {
  if (index < 0 || index >= values.length) {
    return fallback;
  }
  final value = values[index];
  if (value is num) {
    return value.toDouble().clamp(0.0, 1.0);
  }
  return fallback;
}

class _ScriptSourceTermFrameIndex {
  final Script script;
  final List<_ScriptSourceTermFrameTags> frames;
  final Map<
      ({
        String termKey,
        int? slotIndex,
        bool baseScope,
        bool sceneScope,
      }),
      List<int>> _lookupCache = {};

  _ScriptSourceTermFrameIndex({
    required this.script,
    required this.frames,
  });

  List<int> lookup({
    required String termKey,
    required int? slotIndex,
    required bool baseScope,
    required bool sceneScope,
  }) {
    final lookupKey = (
      termKey: termKey,
      slotIndex: slotIndex,
      baseScope: baseScope,
      sceneScope: sceneScope,
    );
    return _lookupCache.putIfAbsent(lookupKey, () {
      return List.unmodifiable([
        for (final frame in frames)
          if (frame
              .tagsFor(
                slotIndex: slotIndex,
                baseScope: baseScope,
                sceneScope: sceneScope,
              )
              .contains(termKey))
            frame.frameIndex,
      ]);
    });
  }
}

class _ScriptSourceTermFrameTags {
  final int frameIndex;
  final Set<String> baseRoleTags;
  final List<Set<String>> characterTags;
  final Set<String> allCharacterTags;
  final Set<String> sceneTags;

  const _ScriptSourceTermFrameTags({
    required this.frameIndex,
    required this.baseRoleTags,
    required this.characterTags,
    required this.allCharacterTags,
    required this.sceneTags,
  });

  Set<String> tagsFor({
    required int? slotIndex,
    required bool baseScope,
    required bool sceneScope,
  }) {
    if (sceneScope) {
      return sceneTags;
    }
    if (slotIndex != null) {
      if (slotIndex >= 0 && slotIndex < characterTags.length) {
        return characterTags[slotIndex];
      }
      return allCharacterTags;
    }
    return baseScope ? baseRoleTags : allCharacterTags;
  }
}
