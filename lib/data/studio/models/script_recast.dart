import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

enum ScriptSchema { v4Slotted, baseInline, v4Partial, unknown }

enum ScriptFrameParseStatus { parsed, error }

enum RecastRunStatus { queued, running, completed, failed, canceled }

enum FrameResultStatus { queued, running, completed, failed, skipped }

class RecastPoint {
  final double x;
  final double y;

  const RecastPoint({
    required this.x,
    required this.y,
  });

  factory RecastPoint.fromJson(Map<String, dynamic> json) {
    return RecastPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
      };

  @override
  bool operator ==(Object other) {
    return other is RecastPoint && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'RecastPoint(x: $x, y: $y)';
}

class ParsedFrame {
  final String baseCaption;
  final List<String> charCaptions;
  final String negativeBase;
  final List<String> negativeCharCaptions;
  final List<RecastPoint> coords;
  final Map<String, dynamic> generationParams;
  final Map<String, dynamic> sourcePayload;

  const ParsedFrame({
    this.baseCaption = '',
    this.charCaptions = const [],
    this.negativeBase = '',
    this.negativeCharCaptions = const [],
    this.coords = const [],
    this.generationParams = const {},
    this.sourcePayload = const {},
  });

  factory ParsedFrame.fromJson(Map<String, dynamic> json) {
    return ParsedFrame(
      baseCaption: json['baseCaption'] as String? ?? '',
      charCaptions: [
        for (final value in json['charCaptions'] as List? ?? const [])
          value.toString(),
      ],
      negativeBase: json['negativeBase'] as String? ?? '',
      negativeCharCaptions: [
        for (final value in json['negativeCharCaptions'] as List? ?? const [])
          value.toString(),
      ],
      coords: [
        for (final value in json['coords'] as List? ?? const [])
          if (value is Map) RecastPoint.fromJson(value.cast<String, dynamic>()),
      ],
      generationParams:
          Map<String, dynamic>.from(json['generationParams'] as Map? ?? {}),
      sourcePayload:
          Map<String, dynamic>.from(json['sourcePayload'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'baseCaption': baseCaption,
        'charCaptions': List.unmodifiable(charCaptions),
        'negativeBase': negativeBase,
        'negativeCharCaptions': List.unmodifiable(negativeCharCaptions),
        'coords': coords.map((coord) => coord.toJson()).toList(),
        'generationParams': stableJsonValue(generationParams),
        'sourcePayload': stableJsonValue(sourcePayload),
      };
}

class ScriptFrame {
  final int index;
  final String fileName;
  final String sourcePath;
  final String sourceImagePath;
  final String rawJson;
  final ParsedFrame parsed;
  final ScriptSchema detectedSchema;
  final ScriptFrameParseStatus parseStatus;
  final List<String> warnings;

  const ScriptFrame({
    required this.index,
    required this.fileName,
    required this.sourcePath,
    this.sourceImagePath = '',
    required this.rawJson,
    required this.parsed,
    required this.detectedSchema,
    required this.parseStatus,
    this.warnings = const [],
  });

  factory ScriptFrame.fromJson(Map<String, dynamic> json) {
    return ScriptFrame(
      index: (json['index'] as num?)?.toInt() ?? 0,
      fileName: json['fileName'] as String? ?? '',
      sourcePath: json['sourcePath'] as String? ?? '',
      sourceImagePath: json['sourceImagePath'] as String? ?? '',
      rawJson: json['rawJson'] as String? ?? '',
      parsed: ParsedFrame.fromJson(
        Map<String, dynamic>.from(json['parsed'] as Map? ?? {}),
      ),
      detectedSchema: _enumByNameOr(
        ScriptSchema.values,
        json['detectedSchema'] as String?,
        ScriptSchema.unknown,
      ),
      parseStatus: _enumByNameOr(
        ScriptFrameParseStatus.values,
        json['parseStatus'] as String?,
        ScriptFrameParseStatus.parsed,
      ),
      warnings: [
        for (final value in json['warnings'] as List? ?? const [])
          value.toString(),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'fileName': fileName,
        'sourcePath': sourcePath,
        if (sourceImagePath.isNotEmpty) 'sourceImagePath': sourceImagePath,
        'rawJson': rawJson,
        'parsed': parsed.toJson(),
        'detectedSchema': detectedSchema.name,
        'parseStatus': parseStatus.name,
        'warnings': List.unmodifiable(warnings),
      };
}

class Script {
  final String id;
  final String name;
  final String rootPath;
  final List<ScriptFrame> frames;
  final ScriptSchema detectedSchema;
  final List<String> parseWarnings;
  final Map<String, dynamic> meta;

  const Script({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.frames,
    required this.detectedSchema,
    this.parseWarnings = const [],
    this.meta = const {},
  });

  factory Script.fromJson(Map<String, dynamic> json) {
    return Script(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      rootPath: json['rootPath'] as String? ?? '',
      frames: [
        for (final value in json['frames'] as List? ?? const [])
          if (value is Map) ScriptFrame.fromJson(value.cast<String, dynamic>()),
      ],
      detectedSchema: _enumByNameOr(
        ScriptSchema.values,
        json['detectedSchema'] as String?,
        ScriptSchema.unknown,
      ),
      parseWarnings: [
        for (final value in json['parseWarnings'] as List? ?? const [])
          value.toString(),
      ],
      meta: Map<String, dynamic>.from(json['meta'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootPath': rootPath,
        'frames': frames.map((frame) => frame.toJson()).toList(),
        'detectedSchema': detectedSchema.name,
        'parseWarnings': List.unmodifiable(parseWarnings),
        'meta': stableJsonValue(meta),
      };
}

T _enumByNameOr<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}

dynamic stableJsonValue(dynamic value) {
  if (value is Map) {
    final result = <String, dynamic>{};
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      result[key] = stableJsonValue(value[key]);
    }
    return result;
  }
  if (value is Iterable) {
    return value.map(stableJsonValue).toList();
  }
  return value;
}

class RoleSwap {
  final String sourceRoleId;
  final String targetCharacterId;
  final String? targetOutfitId;

  const RoleSwap({
    required this.sourceRoleId,
    required this.targetCharacterId,
    this.targetOutfitId,
  });

  factory RoleSwap.fromJson(Map<String, dynamic> json) {
    return RoleSwap(
      sourceRoleId: json['sourceRoleId'] as String,
      targetCharacterId: json['targetCharacterId'] as String,
      targetOutfitId: json['targetOutfitId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceRoleId': sourceRoleId,
        'targetCharacterId': targetCharacterId,
        if (targetOutfitId != null) 'targetOutfitId': targetOutfitId,
      };
}

const Object _recastUnset = Object();

enum RecastPromptPart {
  identity,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
}

class RecastPromptParts {
  final String identity;
  final String upperBody;
  final String lowerBody;
  final String upperClothing;
  final String lowerClothing;

  const RecastPromptParts({
    this.identity = '',
    this.upperBody = '',
    this.lowerBody = '',
    this.upperClothing = '',
    this.lowerClothing = '',
  });

  factory RecastPromptParts.fromJson(Map<String, dynamic> json) {
    return RecastPromptParts(
      identity: json['identity'] as String? ?? '',
      upperBody: json['upperBody'] as String? ?? '',
      lowerBody: json['lowerBody'] as String? ?? '',
      upperClothing: json['upperClothing'] as String? ?? '',
      lowerClothing: json['lowerClothing'] as String? ?? '',
    );
  }

  bool get isEmpty =>
      identity.trim().isEmpty &&
      upperBody.trim().isEmpty &&
      lowerBody.trim().isEmpty &&
      upperClothing.trim().isEmpty &&
      lowerClothing.trim().isEmpty;

  RecastPromptParts copyWith({
    String? identity,
    String? upperBody,
    String? lowerBody,
    String? upperClothing,
    String? lowerClothing,
  }) {
    return RecastPromptParts(
      identity: identity ?? this.identity,
      upperBody: upperBody ?? this.upperBody,
      lowerBody: lowerBody ?? this.lowerBody,
      upperClothing: upperClothing ?? this.upperClothing,
      lowerClothing: lowerClothing ?? this.lowerClothing,
    );
  }

  Map<String, dynamic> toJson() => {
        if (identity.trim().isNotEmpty) 'identity': identity,
        if (upperBody.trim().isNotEmpty) 'upperBody': upperBody,
        if (lowerBody.trim().isNotEmpty) 'lowerBody': lowerBody,
        if (upperClothing.trim().isNotEmpty) 'upperClothing': upperClothing,
        if (lowerClothing.trim().isNotEmpty) 'lowerClothing': lowerClothing,
      };
}

class RoleAssemblyStage {
  final String id;
  final String label;
  final List<int> frameIndexes;
  final String sourceSummary;
  final RecastPromptParts sourceParts;
  final String? targetCharacterId;
  final String? targetUpperOutfitId;
  final String? targetLowerOutfitId;
  final Set<RecastPromptPart> omittedParts;
  final Set<RecastPromptPart> preservedParts;
  final RecastPromptParts manualParts;

  const RoleAssemblyStage({
    required this.id,
    required this.label,
    this.frameIndexes = const [],
    this.sourceSummary = '',
    this.sourceParts = const RecastPromptParts(),
    this.targetCharacterId,
    this.targetUpperOutfitId,
    this.targetLowerOutfitId,
    this.omittedParts = const {},
    this.preservedParts = const {},
    this.manualParts = const RecastPromptParts(),
  });

  factory RoleAssemblyStage.fromJson(Map<String, dynamic> json) {
    return RoleAssemblyStage(
      id: json['id'] as String,
      label: json['label'] as String,
      frameIndexes: _listOfDynamic(json['frameIndexes'])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(growable: false),
      sourceSummary: json['sourceSummary'] as String? ?? '',
      sourceParts: json['sourceParts'] == null
          ? const RecastPromptParts()
          : RecastPromptParts.fromJson((json['sourceParts'] as Map).cast()),
      targetCharacterId: json['targetCharacterId'] as String?,
      targetUpperOutfitId: json['targetUpperOutfitId'] as String?,
      targetLowerOutfitId: json['targetLowerOutfitId'] as String?,
      omittedParts: _promptPartSet(json['omittedParts']),
      preservedParts: _promptPartSet(json['preservedParts']),
      manualParts: json['manualParts'] == null
          ? const RecastPromptParts()
          : RecastPromptParts.fromJson((json['manualParts'] as Map).cast()),
    );
  }

  RoleAssemblyStage copyWith({
    String? id,
    String? label,
    List<int>? frameIndexes,
    String? sourceSummary,
    RecastPromptParts? sourceParts,
    Object? targetCharacterId = _recastUnset,
    Object? targetUpperOutfitId = _recastUnset,
    Object? targetLowerOutfitId = _recastUnset,
    Set<RecastPromptPart>? omittedParts,
    Set<RecastPromptPart>? preservedParts,
    RecastPromptParts? manualParts,
  }) {
    return RoleAssemblyStage(
      id: id ?? this.id,
      label: label ?? this.label,
      frameIndexes: frameIndexes ?? this.frameIndexes,
      sourceSummary: sourceSummary ?? this.sourceSummary,
      sourceParts: sourceParts ?? this.sourceParts,
      targetCharacterId: identical(targetCharacterId, _recastUnset)
          ? this.targetCharacterId
          : targetCharacterId as String?,
      targetUpperOutfitId: identical(targetUpperOutfitId, _recastUnset)
          ? this.targetUpperOutfitId
          : targetUpperOutfitId as String?,
      targetLowerOutfitId: identical(targetLowerOutfitId, _recastUnset)
          ? this.targetLowerOutfitId
          : targetLowerOutfitId as String?,
      omittedParts: omittedParts ?? this.omittedParts,
      preservedParts: preservedParts ?? this.preservedParts,
      manualParts: manualParts ?? this.manualParts,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (frameIndexes.isNotEmpty) 'frameIndexes': frameIndexes,
        if (sourceSummary.trim().isNotEmpty) 'sourceSummary': sourceSummary,
        if (!sourceParts.isEmpty) 'sourceParts': sourceParts.toJson(),
        if (targetCharacterId != null) 'targetCharacterId': targetCharacterId,
        if (targetUpperOutfitId != null)
          'targetUpperOutfitId': targetUpperOutfitId,
        if (targetLowerOutfitId != null)
          'targetLowerOutfitId': targetLowerOutfitId,
        if (omittedParts.isNotEmpty)
          'omittedParts': [
            for (final part in omittedParts) part.name,
          ],
        if (preservedParts.isNotEmpty)
          'preservedParts': [
            for (final part in preservedParts) part.name,
          ],
        if (!manualParts.isEmpty) 'manualParts': manualParts.toJson(),
      };
}

class RoleAssemblySourceAppearance {
  final String sourceId;
  final String sourceKind;
  final List<int> frameIndexes;

  const RoleAssemblySourceAppearance({
    this.sourceId = '',
    this.sourceKind = '',
    this.frameIndexes = const [],
  });

  factory RoleAssemblySourceAppearance.fromJson(Map<String, dynamic> json) {
    return RoleAssemblySourceAppearance(
      sourceId:
          (json['sourceId'] as String?) ?? (json['source_id'] as String?) ?? '',
      sourceKind: (json['sourceKind'] as String?) ??
          (json['source_kind'] as String?) ??
          '',
      frameIndexes:
          _listOfDynamic(json['frameIndexes'] ?? json['frame_indexes'])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'sourceKind': sourceKind,
        'frameIndexes': frameIndexes,
      };
}

class RoleAssembly {
  final String sourceRoleId;
  final String displayLabel;
  final String sourceName;
  final List<RoleAssemblySourceAppearance> sourceAppearances;
  final List<RoleAssemblyStage> stages;

  const RoleAssembly({
    required this.sourceRoleId,
    required this.displayLabel,
    this.sourceName = '',
    this.sourceAppearances = const [],
    this.stages = const [],
  });

  factory RoleAssembly.fromJson(Map<String, dynamic> json) {
    return RoleAssembly(
      sourceRoleId: json['sourceRoleId'] as String,
      displayLabel: json['displayLabel'] as String,
      sourceName: json['sourceName'] as String? ?? '',
      sourceAppearances: _listOfMaps(json['sourceAppearances'])
          .map(RoleAssemblySourceAppearance.fromJson)
          .toList(growable: false),
      stages: _listOfMaps(json['stages'])
          .map(RoleAssemblyStage.fromJson)
          .toList(growable: false),
    );
  }

  RoleAssembly copyWith({
    String? sourceRoleId,
    String? displayLabel,
    String? sourceName,
    List<RoleAssemblySourceAppearance>? sourceAppearances,
    List<RoleAssemblyStage>? stages,
  }) {
    return RoleAssembly(
      sourceRoleId: sourceRoleId ?? this.sourceRoleId,
      displayLabel: displayLabel ?? this.displayLabel,
      sourceName: sourceName ?? this.sourceName,
      sourceAppearances: sourceAppearances ?? this.sourceAppearances,
      stages: stages ?? this.stages,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceRoleId': sourceRoleId,
        'displayLabel': displayLabel,
        if (sourceName.trim().isNotEmpty) 'sourceName': sourceName,
        if (sourceAppearances.isNotEmpty)
          'sourceAppearances': sourceAppearances
              .map((appearance) => appearance.toJson())
              .toList(),
        if (stages.isNotEmpty)
          'stages': stages.map((stage) => stage.toJson()).toList(),
      };
}

PromptTagCategory promptTagCategoryFromReplacementValue(
  Object? value, {
  required PromptTagCategory fallback,
}) {
  if (value is! String) {
    return fallback;
  }
  final normalized = value.trim().replaceAll(RegExp(r'[_\s-]+'), '');
  if (normalized.isEmpty) {
    return fallback;
  }
  final key = normalized.toLowerCase();
  switch (key) {
    case 'identity':
      return PromptTagCategory.character;
    case 'body':
      return PromptTagCategory.upperBody;
    case 'clothingstate':
      return PromptTagCategory.clothingState;
    case 'accessory':
      return PromptTagCategory.accessory;
    case 'clothing':
      return PromptTagCategory.clothing;
    case 'scene':
      return PromptTagCategory.scene;
  }
  for (final category in PromptTagCategory.values) {
    final categoryKey =
        category.name.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
    if (categoryKey == key) {
      return category;
    }
  }
  return fallback;
}

enum ScriptPromptReplacementAction { none, replace, delete }

enum ScriptPromptReplacementMatchMode { any, all, anchor }

class ScriptPromptReplacementTerm {
  final String id;
  final String text;
  final PromptTagCategory category;
  final String sourcePhrase;
  final String sourceLocation;
  final List<int> frameIndexes;

  const ScriptPromptReplacementTerm({
    required this.id,
    required this.text,
    required this.category,
    this.sourcePhrase = '',
    this.sourceLocation = '',
    this.frameIndexes = const [],
  });

  factory ScriptPromptReplacementTerm.fromJson(Map<String, dynamic> json) {
    return ScriptPromptReplacementTerm(
      id: json['id'] as String,
      text: json['text'] as String,
      category: promptTagCategoryFromReplacementValue(
        json['category'],
        fallback: PromptTagCategory.character,
      ),
      sourcePhrase: json['sourcePhrase'] as String? ?? '',
      sourceLocation: json['sourceLocation'] as String? ?? '',
      frameIndexes: _listOfDynamic(json['frameIndexes'])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(growable: false),
    );
  }

  ScriptPromptReplacementTerm copyWith({
    String? id,
    String? text,
    PromptTagCategory? category,
    String? sourcePhrase,
    String? sourceLocation,
    List<int>? frameIndexes,
  }) {
    return ScriptPromptReplacementTerm(
      id: id ?? this.id,
      text: text ?? this.text,
      category: category ?? this.category,
      sourcePhrase: sourcePhrase ?? this.sourcePhrase,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      frameIndexes: frameIndexes ?? this.frameIndexes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'category': category.name,
        if (sourcePhrase.trim().isNotEmpty) 'sourcePhrase': sourcePhrase,
        if (sourceLocation.trim().isNotEmpty) 'sourceLocation': sourceLocation,
        if (frameIndexes.isNotEmpty) 'frameIndexes': frameIndexes,
      };
}

class ScriptPromptReplacementRule {
  final String id;
  final List<ScriptPromptReplacementTerm> sourceTerms;
  final List<String> excludedTermIds;
  final ScriptPromptReplacementAction action;
  final ScriptPromptReplacementMatchMode matchMode;
  final String targetPrompt;
  final double? targetWeightMultiplier;
  final String manualPhrase;
  final String anchorTermId;

  const ScriptPromptReplacementRule({
    required this.id,
    this.sourceTerms = const [],
    this.excludedTermIds = const [],
    this.action = ScriptPromptReplacementAction.none,
    this.matchMode = ScriptPromptReplacementMatchMode.any,
    this.targetPrompt = '',
    this.targetWeightMultiplier,
    this.manualPhrase = '',
    this.anchorTermId = '',
  });

  factory ScriptPromptReplacementRule.fromJson(Map<String, dynamic> json) {
    return ScriptPromptReplacementRule(
      id: json['id'] as String,
      sourceTerms: _listOfMaps(json['sourceTerms'])
          .map(ScriptPromptReplacementTerm.fromJson)
          .toList(growable: false),
      excludedTermIds: [
        for (final value in _listOfDynamic(json['excludedTermIds']))
          value.toString(),
      ],
      action: _enumByNameOr(
        ScriptPromptReplacementAction.values,
        json['action'] as String?,
        ScriptPromptReplacementAction.none,
      ),
      matchMode: _enumByNameOr(
        ScriptPromptReplacementMatchMode.values,
        json['matchMode'] as String?,
        ScriptPromptReplacementMatchMode.any,
      ),
      targetPrompt: json['targetPrompt'] as String? ?? '',
      targetWeightMultiplier:
          _positiveFiniteDoubleOrNull(json['targetWeightMultiplier']),
      manualPhrase: json['manualPhrase'] as String? ?? '',
      anchorTermId: json['anchorTermId'] as String? ?? '',
    );
  }

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

  bool get hasEffect => effectiveAction != ScriptPromptReplacementAction.none;

  ScriptPromptReplacementRule copyWith({
    String? id,
    List<ScriptPromptReplacementTerm>? sourceTerms,
    List<String>? excludedTermIds,
    ScriptPromptReplacementAction? action,
    ScriptPromptReplacementMatchMode? matchMode,
    String? targetPrompt,
    Object? targetWeightMultiplier = _unset,
    String? manualPhrase,
    String? anchorTermId,
  }) {
    return ScriptPromptReplacementRule(
      id: id ?? this.id,
      sourceTerms: sourceTerms ?? this.sourceTerms,
      excludedTermIds: excludedTermIds ?? this.excludedTermIds,
      action: action ?? this.action,
      matchMode: matchMode ?? this.matchMode,
      targetPrompt: targetPrompt ?? this.targetPrompt,
      targetWeightMultiplier: identical(targetWeightMultiplier, _unset)
          ? this.targetWeightMultiplier
          : targetWeightMultiplier as double?,
      manualPhrase: manualPhrase ?? this.manualPhrase,
      anchorTermId: anchorTermId ?? this.anchorTermId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (sourceTerms.isNotEmpty)
          'sourceTerms': sourceTerms.map((term) => term.toJson()).toList(),
        if (excludedTermIds.isNotEmpty) 'excludedTermIds': excludedTermIds,
        if (action != ScriptPromptReplacementAction.none) 'action': action.name,
        if (matchMode != ScriptPromptReplacementMatchMode.any)
          'matchMode': matchMode.name,
        if (targetPrompt.trim().isNotEmpty) 'targetPrompt': targetPrompt,
        if (targetWeightMultiplier != null)
          'targetWeightMultiplier': targetWeightMultiplier,
        if (manualPhrase.trim().isNotEmpty) 'manualPhrase': manualPhrase,
        if (anchorTermId.trim().isNotEmpty) 'anchorTermId': anchorTermId,
      };
}

class ScriptRolePromptReplacement {
  final String sourceRoleId;
  final String displayLabel;
  final String sourcePreview;
  final String? targetCharacterId;
  final String targetIdentityPrompt;
  final List<ScriptPromptReplacementRule> rules;

  const ScriptRolePromptReplacement({
    required this.sourceRoleId,
    required this.displayLabel,
    this.sourcePreview = '',
    this.targetCharacterId,
    this.targetIdentityPrompt = '',
    this.rules = const [],
  });

  factory ScriptRolePromptReplacement.fromJson(Map<String, dynamic> json) {
    return ScriptRolePromptReplacement(
      sourceRoleId: json['sourceRoleId'] as String,
      displayLabel: json['displayLabel'] as String,
      sourcePreview: json['sourcePreview'] as String? ?? '',
      targetCharacterId: json['targetCharacterId'] as String?,
      targetIdentityPrompt: json['targetIdentityPrompt'] as String? ?? '',
      rules: _listOfMaps(json['rules'])
          .map(ScriptPromptReplacementRule.fromJson)
          .toList(growable: false),
    );
  }

  ScriptRolePromptReplacement copyWith({
    String? sourceRoleId,
    String? displayLabel,
    String? sourcePreview,
    Object? targetCharacterId = _recastUnset,
    String? targetIdentityPrompt,
    List<ScriptPromptReplacementRule>? rules,
  }) {
    return ScriptRolePromptReplacement(
      sourceRoleId: sourceRoleId ?? this.sourceRoleId,
      displayLabel: displayLabel ?? this.displayLabel,
      sourcePreview: sourcePreview ?? this.sourcePreview,
      targetCharacterId: identical(targetCharacterId, _recastUnset)
          ? this.targetCharacterId
          : targetCharacterId as String?,
      targetIdentityPrompt: targetIdentityPrompt ?? this.targetIdentityPrompt,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceRoleId': sourceRoleId,
        'displayLabel': displayLabel,
        if (sourcePreview.trim().isNotEmpty) 'sourcePreview': sourcePreview,
        if (targetCharacterId != null) 'targetCharacterId': targetCharacterId,
        if (targetIdentityPrompt.trim().isNotEmpty)
          'targetIdentityPrompt': targetIdentityPrompt,
        if (rules.isNotEmpty)
          'rules': rules.map((rule) => rule.toJson()).toList(),
      };
}

class ScriptScenePromptReplacement {
  final String id;
  final String label;
  final List<ScriptPromptReplacementRule> rules;

  const ScriptScenePromptReplacement({
    required this.id,
    required this.label,
    this.rules = const [],
  });

  factory ScriptScenePromptReplacement.fromJson(Map<String, dynamic> json) {
    return ScriptScenePromptReplacement(
      id: json['id'] as String,
      label: json['label'] as String,
      rules: _listOfMaps(json['rules'])
          .map(ScriptPromptReplacementRule.fromJson)
          .toList(growable: false),
    );
  }

  ScriptScenePromptReplacement copyWith({
    String? id,
    String? label,
    List<ScriptPromptReplacementRule>? rules,
  }) {
    return ScriptScenePromptReplacement(
      id: id ?? this.id,
      label: label ?? this.label,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (rules.isNotEmpty)
          'rules': rules.map((rule) => rule.toJson()).toList(),
      };
}

class ArtistSwap {
  final String targetArtistChainId;
  final String manualPrompt;
  final String sourceArtistPrompt;
  final bool deleteSource;

  const ArtistSwap({
    required this.targetArtistChainId,
    this.manualPrompt = '',
    this.sourceArtistPrompt = '',
    this.deleteSource = false,
  });

  factory ArtistSwap.fromJson(Map<String, dynamic> json) {
    return ArtistSwap(
      targetArtistChainId: json['targetArtistChainId'] as String? ?? '',
      manualPrompt: json['manualPrompt'] as String? ?? '',
      sourceArtistPrompt: json['sourceArtistPrompt'] as String? ?? '',
      deleteSource: json['deleteSource'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        if (targetArtistChainId.trim().isNotEmpty)
          'targetArtistChainId': targetArtistChainId,
        if (manualPrompt.trim().isNotEmpty) 'manualPrompt': manualPrompt,
        if (sourceArtistPrompt.trim().isNotEmpty)
          'sourceArtistPrompt': sourceArtistPrompt,
        if (deleteSource) 'deleteSource': true,
      };

  ArtistSwap copyWith({
    String? targetArtistChainId,
    String? manualPrompt,
    String? sourceArtistPrompt,
    bool? deleteSource,
  }) {
    return ArtistSwap(
      targetArtistChainId: targetArtistChainId ?? this.targetArtistChainId,
      manualPrompt: manualPrompt ?? this.manualPrompt,
      sourceArtistPrompt: sourceArtistPrompt ?? this.sourceArtistPrompt,
      deleteSource: deleteSource ?? this.deleteSource,
    );
  }
}

class PromptBlockSwap {
  final String block;
  final String sourcePrompt;
  final String manualPrompt;
  final bool deleteSource;

  const PromptBlockSwap({
    required this.block,
    this.sourcePrompt = '',
    this.manualPrompt = '',
    this.deleteSource = false,
  });

  factory PromptBlockSwap.fromJson(Map<String, dynamic> json) {
    return PromptBlockSwap(
      block: json['block'] as String? ?? '',
      sourcePrompt: json['sourcePrompt'] as String? ?? '',
      manualPrompt: json['manualPrompt'] as String? ?? '',
      deleteSource: json['deleteSource'] as bool? ?? false,
    );
  }

  bool get hasEffect =>
      manualPrompt.trim().isNotEmpty || deleteSource || sourcePrompt.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'block': block,
        if (sourcePrompt.trim().isNotEmpty) 'sourcePrompt': sourcePrompt,
        if (manualPrompt.trim().isNotEmpty) 'manualPrompt': manualPrompt,
        if (deleteSource) 'deleteSource': true,
      };

  PromptBlockSwap copyWith({
    String? block,
    String? sourcePrompt,
    String? manualPrompt,
    bool? deleteSource,
  }) {
    return PromptBlockSwap(
      block: block ?? this.block,
      sourcePrompt: sourcePrompt ?? this.sourcePrompt,
      manualPrompt: manualPrompt ?? this.manualPrompt,
      deleteSource: deleteSource ?? this.deleteSource,
    );
  }
}

class RecastMapping {
  final String id;
  final String scriptId;
  final List<RoleSwap> roleSwaps;
  final List<RoleAssembly> roleAssemblies;
  final List<ScriptRolePromptReplacement> rolePromptReplacements;
  final List<ScriptScenePromptReplacement> scenePromptReplacements;
  final ArtistSwap? artistSwap;
  final List<PromptBlockSwap> promptBlockSwaps;
  final List<WorkspaceVibeReference> manualVibeRefs;
  final Set<String> suppressedPromptTagWarningKeys;
  final String? preservePresetId;
  final String? outputPolicy;

  const RecastMapping({
    required this.id,
    required this.scriptId,
    this.roleSwaps = const [],
    this.roleAssemblies = const [],
    this.rolePromptReplacements = const [],
    this.scenePromptReplacements = const [],
    this.artistSwap,
    this.promptBlockSwaps = const [],
    this.manualVibeRefs = const [],
    this.suppressedPromptTagWarningKeys = const {},
    this.preservePresetId,
    this.outputPolicy,
  });

  factory RecastMapping.defaults(String scriptId) {
    return RecastMapping(
      id: 'mapping-$scriptId',
      scriptId: scriptId,
    );
  }

  factory RecastMapping.fromJson(Map<String, dynamic> json) {
    return RecastMapping(
      id: json['id'] as String,
      scriptId: json['scriptId'] as String,
      roleSwaps: _listOfMaps(json['roleSwaps'])
          .map(RoleSwap.fromJson)
          .toList(growable: false),
      roleAssemblies: _listOfMaps(json['roleAssemblies'])
          .map(RoleAssembly.fromJson)
          .toList(growable: false),
      rolePromptReplacements: _listOfMaps(json['rolePromptReplacements'])
          .map(ScriptRolePromptReplacement.fromJson)
          .toList(growable: false),
      scenePromptReplacements: _listOfMaps(json['scenePromptReplacements'])
          .map(ScriptScenePromptReplacement.fromJson)
          .toList(growable: false),
      artistSwap: json['artistSwap'] == null
          ? null
          : ArtistSwap.fromJson((json['artistSwap'] as Map).cast()),
      promptBlockSwaps: _listOfMaps(json['promptBlockSwaps'])
          .map(PromptBlockSwap.fromJson)
          .toList(growable: false),
      manualVibeRefs: _listOfDynamic(json['manualVibeRefs'])
          .map(WorkspaceVibeReference.fromJson)
          .toList(growable: false),
      suppressedPromptTagWarningKeys: {
        for (final value in _listOfDynamic(
          json['suppressedPromptTagWarningKeys'],
        ))
          if (value.toString().trim().isNotEmpty) value.toString().trim(),
      },
      preservePresetId: json['preservePresetId'] as String?,
      outputPolicy: json['outputPolicy'] as String?,
    );
  }

  RecastMapping copyWith({
    String? id,
    String? scriptId,
    List<RoleSwap>? roleSwaps,
    List<RoleAssembly>? roleAssemblies,
    List<ScriptRolePromptReplacement>? rolePromptReplacements,
    List<ScriptScenePromptReplacement>? scenePromptReplacements,
    ArtistSwap? artistSwap,
    bool clearArtistSwap = false,
    List<PromptBlockSwap>? promptBlockSwaps,
    List<WorkspaceVibeReference>? manualVibeRefs,
    Set<String>? suppressedPromptTagWarningKeys,
    String? preservePresetId,
    bool clearPreservePresetId = false,
    String? outputPolicy,
    bool clearOutputPolicy = false,
  }) {
    return RecastMapping(
      id: id ?? this.id,
      scriptId: scriptId ?? this.scriptId,
      roleSwaps: roleSwaps ?? this.roleSwaps,
      roleAssemblies: roleAssemblies ?? this.roleAssemblies,
      rolePromptReplacements:
          rolePromptReplacements ?? this.rolePromptReplacements,
      scenePromptReplacements:
          scenePromptReplacements ?? this.scenePromptReplacements,
      artistSwap: clearArtistSwap ? null : artistSwap ?? this.artistSwap,
      promptBlockSwaps: promptBlockSwaps ?? this.promptBlockSwaps,
      manualVibeRefs: manualVibeRefs ?? this.manualVibeRefs,
      suppressedPromptTagWarningKeys:
          suppressedPromptTagWarningKeys ?? this.suppressedPromptTagWarningKeys,
      preservePresetId: clearPreservePresetId
          ? null
          : preservePresetId ?? this.preservePresetId,
      outputPolicy:
          clearOutputPolicy ? null : outputPolicy ?? this.outputPolicy,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'scriptId': scriptId,
      'roleSwaps': roleSwaps.map((swap) => swap.toJson()).toList(),
      'artistSwap': artistSwap?.toJson(),
    };
    if (roleAssemblies.isNotEmpty) {
      json['roleAssemblies'] =
          roleAssemblies.map((assembly) => assembly.toJson()).toList();
    }
    if (rolePromptReplacements.isNotEmpty) {
      json['rolePromptReplacements'] = rolePromptReplacements
          .map((replacement) => replacement.toJson())
          .toList();
    }
    if (scenePromptReplacements.isNotEmpty) {
      json['scenePromptReplacements'] = scenePromptReplacements
          .map((replacement) => replacement.toJson())
          .toList();
    }
    if (manualVibeRefs.isNotEmpty) {
      json['manualVibeRefs'] =
          manualVibeRefs.map((vibe) => vibe.toJson()).toList();
    }
    if (promptBlockSwaps.isNotEmpty) {
      json['promptBlockSwaps'] =
          promptBlockSwaps.map((swap) => swap.toJson()).toList();
    }
    if (suppressedPromptTagWarningKeys.isNotEmpty) {
      json['suppressedPromptTagWarningKeys'] =
          (suppressedPromptTagWarningKeys.toList()..sort());
    }
    if (preservePresetId != null) {
      json['preservePresetId'] = preservePresetId;
    }
    if (outputPolicy != null) {
      json['outputPolicy'] = outputPolicy;
    }
    return json;
  }
}

class RecastRun {
  final String id;
  final String scriptId;
  final String mappingId;
  final String productionPlanId;
  final RecastRunStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<FrameResult> frameResults;
  final String configFingerprint;

  const RecastRun({
    required this.id,
    required this.scriptId,
    required this.mappingId,
    required this.productionPlanId,
    required this.status,
    required this.configFingerprint,
    this.startedAt,
    this.finishedAt,
    this.frameResults = const [],
  });

  factory RecastRun.fromJson(Map<String, dynamic> json) {
    return RecastRun(
      id: json['id'] as String,
      scriptId: json['scriptId'] as String,
      mappingId: json['mappingId'] as String,
      productionPlanId: json['productionPlanId'] as String,
      status: _enumByName(RecastRunStatus.values, json['status'] as String),
      startedAt: _dateTimeFromJson(json['startedAt']),
      finishedAt: _dateTimeFromJson(json['finishedAt']),
      frameResults: _listOfMaps(json['frameResults'])
          .map(FrameResult.fromJson)
          .toList(growable: false),
      configFingerprint: json['configFingerprint'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scriptId': scriptId,
        'mappingId': mappingId,
        'productionPlanId': productionPlanId,
        'status': status.name,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'finishedAt': finishedAt?.toUtc().toIso8601String(),
        'frameResults': frameResults.map((result) => result.toJson()).toList(),
        'configFingerprint': configFingerprint,
      };
}

class FrameResult {
  final int frameIndex;
  final String sourceFileName;
  final String taskId;
  final FrameResultStatus status;
  final String payloadFingerprint;
  final String? outputImagePath;
  final String? error;
  final int attempts;
  final DateTime? lastRunAt;

  const FrameResult({
    required this.frameIndex,
    required this.sourceFileName,
    required this.taskId,
    required this.status,
    required this.payloadFingerprint,
    this.outputImagePath,
    this.error,
    this.attempts = 0,
    this.lastRunAt,
  });

  factory FrameResult.fromJson(Map<String, dynamic> json) {
    return FrameResult(
      frameIndex: json['frameIndex'] as int,
      sourceFileName: json['sourceFileName'] as String,
      taskId: json['taskId'] as String,
      status: _enumByName(FrameResultStatus.values, json['status'] as String),
      payloadFingerprint: json['payloadFingerprint'] as String,
      outputImagePath: json['outputImagePath'] as String?,
      error: json['error'] as String?,
      attempts: json['attempts'] as int? ?? 0,
      lastRunAt: _dateTimeFromJson(json['lastRunAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'frameIndex': frameIndex,
        'sourceFileName': sourceFileName,
        'taskId': taskId,
        'status': status.name,
        'payloadFingerprint': payloadFingerprint,
        'outputImagePath': outputImagePath,
        'error': error,
        'attempts': attempts,
        'lastRunAt': lastRunAt?.toUtc().toIso8601String(),
      };
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value == null) {
    return const [];
  }
  return (value as List)
      .map((item) => (item as Map).cast<String, dynamic>())
      .toList();
}

List<dynamic> _listOfDynamic(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is List) {
    return value;
  }
  return const [];
}

const Object _unset = Object();

double? _positiveFiniteDoubleOrNull(Object? value) {
  if (value is! num) {
    return null;
  }
  final parsed = value.toDouble();
  if (!parsed.isFinite || parsed <= 0) {
    return null;
  }
  return parsed;
}

Set<RecastPromptPart> _promptPartSet(Object? value) {
  final parts = <RecastPromptPart>{};
  for (final item in _listOfDynamic(value)) {
    final name = item.toString();
    for (final part in RecastPromptPart.values) {
      if (part.name == name) {
        parts.add(part);
        break;
      }
    }
  }
  return Set.unmodifiable(parts);
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  return values.firstWhere((value) => value.name == name);
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}
