import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_assembly_application.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_parser.dart';
import 'package:novel_studio/data/studio/services/script_recast_asset_context_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_path_rebinder.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_production_service.dart';
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

typedef StudioScriptDirectoryPicker = Future<String?> Function();
typedef StudioScriptCharactersLoader = Future<List<CharacterEntry>> Function();
typedef StudioScriptArtistChainsLoader = Future<List<ArtistChain>> Function();
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
    );
  }
}

class StudioScriptRoleReplacementItem {
  final String sourceRoleId;
  final String sourceLabel;
  final String sourcePreview;
  final String? targetCharacterId;
  final String targetIdentityPrompt;
  final List<StudioScriptReplacementRuleItem> rules;

  const StudioScriptRoleReplacementItem({
    required this.sourceRoleId,
    required this.sourceLabel,
    required this.sourcePreview,
    this.targetCharacterId,
    this.targetIdentityPrompt = '',
    this.rules = const [],
  });

  StudioScriptRoleReplacementItem copyWith({
    Object? targetCharacterId = _unset,
    String? targetIdentityPrompt,
    List<StudioScriptReplacementRuleItem>? rules,
  }) {
    return StudioScriptRoleReplacementItem(
      sourceRoleId: sourceRoleId,
      sourceLabel: sourceLabel,
      sourcePreview: sourcePreview,
      targetCharacterId: identical(targetCharacterId, _unset)
          ? this.targetCharacterId
          : targetCharacterId as String?,
      targetIdentityPrompt: targetIdentityPrompt ?? this.targetIdentityPrompt,
      rules: rules ?? this.rules,
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
  final StudioScriptDirectoryPicker? pickScriptDirectory;
  final ScriptRecastParserService parserService;
  final ScriptRecastEngine recastEngine;
  final ScriptRecastProductionService? productionService;
  final StudioScriptCharactersLoader? loadCharacters;
  final StudioScriptArtistChainsLoader? loadArtistChains;
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

  Script? _script;
  RecastMapping? _mapping;
  RecastScriptCache? _changedSourceCache;
  ScriptRecastResult? _previewResult;
  List<CharacterEntry> _characters = const [];
  List<ArtistChain> _availableArtistChains = const [];
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
  Future<void> _cacheSaveTail = Future<void>.value();
  int _deferredAssetRefreshGeneration = 0;
  int _scriptOpenGeneration = 0;
  int _productionSendGeneration = 0;
  bool _disposed = false;
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

  List<CharacterEntry> get characterOptions => _characters;

  List<ArtistChain> get artistChainOptions => _availableArtistChains;

  List<WorkspaceVibeReference> get vibeOptions => _availableVibes;

  List<WorkspaceVibeReference> get sourceVibeOptions =>
      _sourceVibesFromScript(_script, _availableVibes);

  List<WorkspaceVibeReference> get selectedManualVibes =>
      _mapping?.manualVibeRefs ?? const [];

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
      _previewPathsForAsset(
        _artistChainPreviewPaths[chain.id],
        chain.imageRefs,
      );

  bool get hasChangedSourceCache => _changedSourceCache != null;
  int? get selectedFrameIndex => _selectedFrameIndex;

  bool get isAiBusy => isExtractingAiRoleEvidence || isApplyingAiRoleExtraction;

  bool get showAiProgressPanel => aiProgressSteps.isNotEmpty;

  bool get showAiRoleExtractionDraftPanel => !_aiRoleExtractionDraftDismissed;

  bool get isAiRoleExtractionDraftCollapsed => _aiRoleExtractionDraftDismissed;

  StudioScriptViewModel({
    this.pickScriptDirectory,
    this.parserService = const ScriptRecastParserService(),
    this.recastEngine = const ScriptRecastEngine(),
    this.productionService,
    this.loadCharacters,
    this.loadArtistChains,
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
  })  : translationCache = translationCache ?? TranslationCache(),
        hydrateCachedScriptSnapshot = hydrateCachedScriptSnapshot ??
            defaultStudioScriptCacheSnapshotHydrator,
        classificationCache =
            classificationCache ?? PromptTagClassificationCache();

  @override
  void dispose() {
    _disposed = true;
    _aiOperationGeneration++;
    _scriptOpenGeneration++;
    _productionSendGeneration++;
    _deferredAssetRefreshGeneration++;
    _aiRoleExtractionStreamNotifyTimer?.cancel();
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
            _scheduleDeferredAssetRefresh(restored.cache, normalizedScriptId);
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
          _scheduleDeferredAssetRefresh(cache, normalizedScriptId);
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
    if (!_aiRoleExtractionDraftDismissed) {
      return;
    }
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
      isApplyingAiRoleExtraction = false;
      analysisStatus = '尚未分析角色';
      aiStatus = '尚未进行 AI 分析';
      _artistSourceLabelOverride = null;
      _clearAiProgress();
      _changedSourceCache = null;
      _applyScript(script);
      _setImportProgress('正在恢复当前缓存...');
      await _restoreExactCurrentSourceCache(
        script,
        shouldContinue: shouldContinue,
      );
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
      await _cacheSaveTail;
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
      _setImportProgress('正在应用缓存映射...', value: 0.84);
      await _yieldImportProgressFrame();
      if (shouldContinue?.call() == false) return false;
    }
    cacheStatus = '已从缓存快速恢复本剧本';
    return true;
  }

  void _scheduleDeferredAssetRefresh(
    RecastScriptCache cache,
    String scriptId,
  ) {
    final normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.isEmpty) return;
    _deferredAssetRefreshGeneration += 1;
    final generation = _deferredAssetRefreshGeneration;
    unawaited(_refreshAssetsAfterFastOpen(
      cache: cache,
      scriptId: normalizedScriptId,
      generation: generation,
    ));
  }

  Future<void> _refreshAssetsAfterFastOpen({
    required RecastScriptCache cache,
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
      _applyCache(cache, refreshPreview: false);
      _applyScript(script, mappingOverride: _mapping);
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
    _mapping = null;
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
            await _saveCache(script);
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
      await _saveCache(script);
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
      await _saveCache(script);
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
  }

  void _recordEmptyAiRoleExtractionFailure() {
    const message =
        '当前导入目录没有可解析的剧本帧。请导入包含提示词 metadata 的 JSON 或 PNG 文件后再整理角色字段。';
    _clearAiProgress();
    _clearAiRoleExtractionLiveOutput();
    _aiRoleExtractionDraftDismissed = false;
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
      (replacement) => replacement.copyWith(
        targetCharacterId: character.id,
        targetIdentityPrompt: targetIdentityPrompt,
      ),
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
        return replacement.copyWith(rules: List.unmodifiable(nextRules));
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

  List<ScriptRolePromptReplacement> _rolePromptReplacementsWithResetGroup({
    required List<ScriptRolePromptReplacement> current,
    required String sourceRoleId,
    required ScriptRolePromptReplacement? resetReplacement,
  }) {
    final next = <ScriptRolePromptReplacement>[];
    var removedExisting = false;
    var insertedReset = false;
    for (final replacement in current) {
      if (replacement.sourceRoleId == sourceRoleId) {
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

  bool _updateRoleReplacement(
    String sourceRoleId,
    ScriptRolePromptReplacement Function(ScriptRolePromptReplacement) update,
  ) {
    final mapping = _mapping;
    if (mapping == null) {
      return false;
    }
    var changed = false;
    final next = [
      for (final replacement in mapping.rolePromptReplacements)
        if (replacement.sourceRoleId == sourceRoleId)
          _markChanged(update(replacement), () => changed = true)
        else
          replacement,
    ];
    if (!changed) {
      return false;
    }
    _mapping =
        mapping.copyWith(rolePromptReplacements: List.unmodifiable(next));
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
    final merged = first.copyWith(
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
    return _replacementRulesWithMovedSourceTerms(
      rules: rules,
      sourceRuleIds: {sourceRuleId},
      targetRuleId: targetRuleId,
      tags: sourceRule.sourceTerms.map((term) => term.text),
    );
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
    var changed = false;
    final nextAssemblies = [
      for (final assembly in mapping.roleAssemblies) ...[
        if (assembly.sourceRoleId != sourceRoleId)
          assembly
        else
          () {
            final nextStages = [
              for (final stage in assembly.stages)
                if (stage.id != stageId) stage,
            ];
            changed = changed || nextStages.length != assembly.stages.length;
            return assembly.copyWith(stages: List.unmodifiable(nextStages));
          }(),
      ],
    ];
    if (!changed) {
      return;
    }
    _mapping = mapping.copyWith(
      roleAssemblies: List.unmodifiable(nextAssemblies),
    );
    _refreshRoleEditPreview(sourceRoleId);
    notifyListeners();
    _scheduleCurrentCacheSave();
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
      update: (stage, _) => stage.copyWith(label: normalized),
    );
  }

  void setRoleStageFrameIndexes({
    required String sourceRoleId,
    required String stageId,
    required List<int> frameIndexes,
  }) {
    _updateRoleStage(
      sourceRoleId: sourceRoleId,
      stageId: stageId,
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
    _commitRoleStageEdit(sourceRoleId);
  }

  List<int> _normalizedRoleStageFrameIndexes(Iterable<int> frameIndexes) {
    final result = frameIndexes.where((index) => index >= 0).toSet().toList()
      ..sort();
    return List.unmodifiable(result);
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
      final result = await recastEngine.resolvePayloadsAsync(
        script: script,
        mapping: productionMapping,
        characters: _characters,
        artistChains: _availableArtistChains,
        globalBlockWords: _effectiveBlockWords(),
        globalPromptPrefix: globalPromptPrefix,
        filterRuleConfig: _blockWordConfig(),
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

  Future<void> _loadAssets() async {
    final assetContextLoader = loadAssetContext;
    if (assetContextLoader != null) {
      final context = await assetContextLoader();
      _characters = context.characters;
      _availableArtistChains = List.unmodifiable(context.artistChains);
      _characterPreviewPaths = context.characterPreviewPaths;
      _outfitPreviewPaths = context.outfitPreviewPaths;
      _artistChainPreviewPaths = context.artistChainPreviewPaths;
      _availableVibes = List.unmodifiable(await _loadVibes());
      _filterRuleConfig = context.filterRules;
      _applyGlobalBlockWords(context.filterRules.deleteKeywords);
      _applyGlobalPromptPrefix(context.filterRules.globalPromptPrefix);
      _assetsLoaded = true;
      return;
    }
    _characters = await _loadCharacters();
    _availableArtistChains = List.unmodifiable(await _loadArtistChains());
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
    final selectedOutfit =
        outfitId == null ? null : _outfitById(character, outfitId);
    final outfits = selectedOutfit == null
        ? character.outfits
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

  Future<void> _saveCache(Script script) async {
    final mapping = _mapping;
    if (mapping == null) {
      cacheStatus = '缓存未配置';
      return;
    }
    final cacheMapping = _mappingForCurrentScript(script, mapping);
    if (!identical(cacheMapping, mapping)) {
      _mapping = cacheMapping;
    }
    final cacheDraft = RecastScriptCache(
      scriptId: script.id,
      scriptName: script.name,
      sourceRootPath: script.rootPath,
      sourceFingerprint: cacheRestoreService.sourceFingerprint(script),
      sourceContentFingerprint:
          cacheRestoreService.sourceContentFingerprint(script),
      updatedAt: DateTime.now().toUtc(),
      mapping: cacheMapping,
      aiRoleExtraction: aiRoleExtraction,
      aiRoleExtractionChunks: aiRoleExtractionChunks,
      aiRoleExtractionDraftCollapsed: _aiRoleExtractionDraftDismissed,
      scriptBlockWords: scriptBlockWords,
      scriptSnapshot: script.toJson(),
    );
    final cache = RecastScriptCache(
      scriptId: cacheDraft.scriptId,
      scriptName: cacheDraft.scriptName,
      sourceRootPath: cacheDraft.sourceRootPath,
      sourceFingerprint: cacheDraft.sourceFingerprint,
      sourceContentFingerprint: cacheDraft.sourceContentFingerprint,
      updatedAt: cacheDraft.updatedAt,
      mapping: cacheDraft.mapping,
      aiRoleExtraction: cacheDraft.aiRoleExtraction,
      aiRoleExtractionChunks: cacheDraft.aiRoleExtractionChunks,
      aiRoleExtractionDraftCollapsed: cacheDraft.aiRoleExtractionDraftCollapsed,
      scriptBlockWords: cacheDraft.scriptBlockWords,
      scriptSnapshot: cacheDraft.scriptSnapshot,
      knowledgeSnapshot: const {},
    );
    final singleSaver = saveRecastCache;
    if (singleSaver != null) {
      final existingExact = await _loadExistingExactCacheForSave(
        script: script,
        sourceFingerprint: cache.sourceFingerprint,
      );
      await singleSaver(
        cacheRestoreService.cachePreservingExistingAiDraft(
          cache,
          existingExact,
        ),
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
    final cacheToSave = cacheRestoreService.cachePreservingExistingAiDraft(
      cache,
      cacheRestoreService.bestExactCacheForScript(
        existing,
        script: script,
        sourceFingerprint: cache.sourceFingerprint,
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

  Future<void> _enqueueCurrentCacheSave() {
    final previous = _cacheSaveTail;
    final next = previous.catchError((_) {}).then((_) async {
      final script = _script;
      if (script == null) {
        return;
      }
      await _saveCache(script);
    });
    _cacheSaveTail = next;
    return next;
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
      rawResponse: extraction.rawResponse,
    ).collapseEquivalentStages();
    aiRoleExtraction = _extractionWithVisibleRolePromptTerms(aiRoleExtraction);
    _aiRoleExtractionDraftDismissed = false;
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

    final seenKeys = <String>{
      for (final term in visibleTerms)
        _promptTermIdentityKey(term.category, term.text),
    };
    final visibleTextKeys = <String>{};
    for (final term in visibleTerms) {
      final textKey = _promptTermTextKey(term.text);
      if (textKey.isNotEmpty) {
        visibleTextKeys.add(textKey);
      }
    }

    bool shouldKeepExistingPromptTerm(ScriptAiExtractedPromptTerm term) {
      final textKey = _promptTermTextKey(term.text);
      if (textKey.isNotEmpty && visibleTextKeys.contains(textKey)) {
        return false;
      }
      return seenKeys.add(_promptTermIdentityKey(term.category, term.text));
    }

    final nextTerms = <ScriptAiExtractedPromptTerm>[
      ...visibleTerms,
      for (final term in role.promptTerms)
        if (shouldKeepExistingPromptTerm(term)) term,
    ];
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
    final mapping = _mappingWithRoleAssemblies(
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

  void _applyCache(
    RecastScriptCache cache, {
    bool refreshPreview = true,
  }) {
    _manualSelectedStageIdsByRole.clear();
    _selectedRoleReplacementRuleIdsByRole.clear();
    _selectedSceneReplacementRuleIdsByGroup.clear();
    final script = _script;
    final restoredMapping = script == null
        ? cache.mapping
        : _mappingWithRoleAssemblies(script, cache.mapping);
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
    final restoredExtraction = extractionFrameRepair.extraction;
    final appliedExtractionMapping = script == null
        ? null
        : _mappingWithAppliedAiRoleExtraction(
            script: script,
            mapping: restoredMapping,
            extraction: restoredExtraction,
          );
    final mapped = appliedExtractionMapping?.mapping ?? restoredMapping;
    final mappingFrameRepair = script == null
        ? (mapping: mapped, changed: false)
        : _mappingWithSourceTermFrameEvidence(script: script, mapping: mapped);
    _mapping = mappingFrameRepair.mapping;
    aiRoleExtraction = restoredExtraction;
    aiRoleExtractionChunks = cache.aiRoleExtractionChunks;
    _aiRoleExtractionDraftDismissed = cache.aiRoleExtractionDraftCollapsed;
    scriptBlockWords = _normalizeBlockWords(cache.scriptBlockWords);
    aiRoleExtractionReasoningContent = '';
    aiRoleExtractionRequestCount = 0;
    if (aiRoleExtraction.status != ScriptAiRoleExtractionStatus.idle) {
      aiStatus = '已从缓存恢复 AI 角色字段草稿';
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
        extractionFrameRepair.changed ||
        mappingFrameRepair.changed) {
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
    final frames = <int>[];
    for (final frame in script.frames) {
      if (frame.parseStatus != ScriptFrameParseStatus.parsed) {
        continue;
      }
      final captions = sceneScope
          ? _positiveCaptionsForSceneReplacementFrame(frame)
          : _positiveCaptionsForReplacementSourceRole(frame, sourceRoleId);
      if (captions.any((caption) => _captionContainsTagKey(caption, termKey))) {
        frames.add(frame.index);
      }
    }
    return List.unmodifiable(frames);
  }

  List<String> _positiveCaptionsForReplacementSourceRole(
    ScriptFrame frame,
    String sourceRoleId,
  ) {
    final scoped = _positiveCaptionsForSourceRole(frame, sourceRoleId);
    if (scoped.isNotEmpty) {
      return scoped;
    }
    if (_isBaseSourceRoleId(sourceRoleId)) {
      return [_frameBaseCaption(frame)];
    }
    return frame.parsed.charCaptions;
  }

  List<String> _positiveCaptionsForSceneReplacementFrame(ScriptFrame frame) {
    return [
      _frameBaseCaption(frame),
      ...frame.parsed.charCaptions,
    ];
  }

  bool _captionContainsTagKey(String caption, String wantedKey) {
    for (final rawTag in PromptTagProcessor.splitWorkshopTags(caption)) {
      final key = PromptTagProcessor.normalizeMatchKey(
        PromptTagProcessor.cleanTagDisplay(rawTag),
      );
      if (key == wantedKey) {
        return true;
      }
    }
    return false;
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
    return List.unmodifiable([
      for (final replacement in mapping.rolePromptReplacements)
        StudioScriptRoleReplacementItem(
          sourceRoleId: replacement.sourceRoleId,
          sourceLabel: replacement.displayLabel,
          sourcePreview: replacement.sourcePreview,
          targetCharacterId: replacement.targetCharacterId,
          targetIdentityPrompt: replacement.targetIdentityPrompt,
          rules: List.unmodifiable([
            for (final rule in replacement.rules)
              _replacementRuleItem(
                rule,
                selected: _selectedRoleReplacementRuleIdsByRole[
                            replacement.sourceRoleId]
                        ?.contains(rule.id) ??
                    false,
              ),
          ]),
        ),
    ]);
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
