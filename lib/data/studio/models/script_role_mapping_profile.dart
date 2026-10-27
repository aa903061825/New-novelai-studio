import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

const int roleMappingProfileLibrarySchemaVersion = 2;

String normalizeRoleMappingProfileTerm(String value) {
  return PromptTagProcessor.normalizeMatchKey(value).replaceAll(' ', '_');
}

class RoleMappingProfileTerm {
  final String id;
  final String text;
  final String normalizedKey;
  final bool autoDetect;

  const RoleMappingProfileTerm({
    required this.id,
    required this.text,
    required this.normalizedKey,
    this.autoDetect = true,
  });

  String get matchKey => normalizeRoleMappingProfileTerm(text);

  factory RoleMappingProfileTerm.fromSourceTerm(
    ScriptPromptReplacementTerm term, {
    bool autoDetect = true,
  }) {
    return RoleMappingProfileTerm(
      id: term.id,
      text: term.text,
      normalizedKey: normalizeRoleMappingProfileTerm(term.text),
      autoDetect: autoDetect,
    );
  }

  factory RoleMappingProfileTerm.fromJson(Map<String, dynamic> json) {
    final text = (json['text'] as String? ?? '').trim();
    final normalized = normalizeRoleMappingProfileTerm(
        json['normalizedKey'] as String? ?? text);
    if (text.isEmpty || normalized.isEmpty) {
      throw const FormatException(
        'Role mapping profile terms require non-empty text.',
      );
    }
    return RoleMappingProfileTerm(
      id: (json['id'] as String? ?? normalized).trim(),
      text: text,
      normalizedKey: normalized,
      autoDetect: json['autoDetect'] != false,
    );
  }

  RoleMappingProfileTerm copyWith({
    String? id,
    String? text,
    String? normalizedKey,
    bool? autoDetect,
  }) {
    final nextText = text ?? this.text;
    return RoleMappingProfileTerm(
      id: id ?? this.id,
      text: nextText,
      normalizedKey: normalizedKey ??
          (text == null
              ? this.normalizedKey
              : normalizeRoleMappingProfileTerm(nextText)),
      autoDetect: autoDetect ?? this.autoDetect,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'normalizedKey': matchKey,
        if (!autoDetect) 'autoDetect': false,
      };
}

class RoleMappingProfileBlock {
  final String id;
  final List<RoleMappingProfileTerm> terms;
  final ScriptPromptReplacementMatchMode matchMode;
  final String anchorTermKey;
  final ScriptPromptReplacementAction action;
  final String targetPrompt;
  final double? targetWeightMultiplier;

  /// Semantic categories emitted by the target block.
  ///
  /// Global profiles used to store only a flat source-term list.  That made a
  /// block containing (for example) a tail and legwear reusable for either
  /// source field.  Keeping the target-side categories in the block lets the
  /// application prefer same-part mappings and only use an untyped block when
  /// no same-part candidate exists.
  final List<PromptTagCategory> targetCategories;

  const RoleMappingProfileBlock({
    required this.id,
    this.terms = const [],
    this.matchMode = ScriptPromptReplacementMatchMode.any,
    this.anchorTermKey = '',
    this.action = ScriptPromptReplacementAction.none,
    this.targetPrompt = '',
    this.targetWeightMultiplier,
    this.targetCategories = const [],
  });

  factory RoleMappingProfileBlock.fromRule(
    ScriptPromptReplacementRule rule, {
    Map<String, bool> autoDetectByNormalizedKey = const {},
  }) {
    return RoleMappingProfileBlock(
      id: rule.id,
      terms: [
        for (final term in rule.sourceTerms)
          RoleMappingProfileTerm.fromSourceTerm(
            term,
            autoDetect: autoDetectByNormalizedKey[
                    normalizeRoleMappingProfileTerm(term.text)] ??
                true,
          ),
      ],
      matchMode: rule.matchMode,
      anchorTermKey: _anchorKeyForRule(rule),
      action: rule.effectiveAction,
      targetPrompt: rule.targetPrompt,
      targetWeightMultiplier: rule.targetWeightMultiplier,
    );
  }

  factory RoleMappingProfileBlock.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) {
      throw const FormatException(
        'Role mapping profile blocks require a non-empty id.',
      );
    }
    final terms = [
      for (final value in json['terms'] as List? ?? const [])
        RoleMappingProfileTerm.fromJson(
          Map<String, dynamic>.from(value as Map),
        ),
    ];
    if (terms.isEmpty) {
      throw const FormatException(
        'Role mapping profile blocks require at least one source term.',
      );
    }
    final matchMode = _enumByName(
      ScriptPromptReplacementMatchMode.values,
      json['matchMode'] as String?,
      ScriptPromptReplacementMatchMode.any,
    );
    final action = _enumByName(
      ScriptPromptReplacementAction.values,
      json['action'] as String?,
      ScriptPromptReplacementAction.none,
    );
    final anchorTermKey = normalizeRoleMappingProfileTerm(
      json['anchorTermKey'] as String? ?? '',
    );
    if (matchMode == ScriptPromptReplacementMatchMode.anchor &&
        anchorTermKey.isEmpty) {
      throw const FormatException(
        'Anchor role mapping profile blocks require an anchor term.',
      );
    }
    if (matchMode == ScriptPromptReplacementMatchMode.anchor &&
        !terms.any((term) => term.matchKey == anchorTermKey)) {
      throw const FormatException(
        'Anchor role mapping profile blocks require an anchor from their terms.',
      );
    }
    return RoleMappingProfileBlock(
      id: id,
      terms: List.unmodifiable(terms),
      matchMode: matchMode,
      anchorTermKey: anchorTermKey,
      action: action,
      targetPrompt: json['targetPrompt'] as String? ?? '',
      targetWeightMultiplier:
          _positiveFiniteDoubleOrNull(json['targetWeightMultiplier']),
      targetCategories: List.unmodifiable([
        for (final value in json['targetCategories'] as List? ?? const [])
          promptTagCategoryFromReplacementValue(
            value,
            fallback: PromptTagCategory.other,
          ),
      ]),
    );
  }

  ScriptPromptReplacementAction get effectiveAction {
    if (action == ScriptPromptReplacementAction.delete) {
      return ScriptPromptReplacementAction.delete;
    }
    if (targetPrompt.trim().isNotEmpty || targetWeightMultiplier != null) {
      return ScriptPromptReplacementAction.replace;
    }
    return ScriptPromptReplacementAction.none;
  }

  bool get hasEffect => effectiveAction != ScriptPromptReplacementAction.none;

  Set<String> get normalizedTermKeys => {
        for (final term in terms)
          if (term.matchKey.isNotEmpty) term.matchKey,
      };

  Set<String> get detectionKeys => {
        for (final term in terms)
          if (term.autoDetect && term.matchKey.isNotEmpty) term.matchKey,
      };

  RoleMappingProfileBlock copyWith({
    String? id,
    List<RoleMappingProfileTerm>? terms,
    ScriptPromptReplacementMatchMode? matchMode,
    String? anchorTermKey,
    ScriptPromptReplacementAction? action,
    String? targetPrompt,
    Object? targetWeightMultiplier = _profileUnset,
    List<PromptTagCategory>? targetCategories,
  }) {
    return RoleMappingProfileBlock(
      id: id ?? this.id,
      terms: terms ?? this.terms,
      matchMode: matchMode ?? this.matchMode,
      anchorTermKey: anchorTermKey ?? this.anchorTermKey,
      action: action ?? this.action,
      targetPrompt: targetPrompt ?? this.targetPrompt,
      targetWeightMultiplier: identical(targetWeightMultiplier, _profileUnset)
          ? this.targetWeightMultiplier
          : targetWeightMultiplier as double?,
      targetCategories: targetCategories ?? this.targetCategories,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'terms': terms.map((term) => term.toJson()).toList(),
        'matchMode': matchMode.name,
        if (anchorTermKey.isNotEmpty) 'anchorTermKey': anchorTermKey,
        'action': effectiveAction.name,
        if (targetPrompt.trim().isNotEmpty) 'targetPrompt': targetPrompt,
        if (targetWeightMultiplier != null)
          'targetWeightMultiplier': targetWeightMultiplier,
        if (targetCategories.isNotEmpty)
          'targetCategories':
              targetCategories.map((category) => category.name).toList(),
      };
}

enum RoleMappingProfileLayerKind { shared, stage, pending }

class RoleMappingProfileLayer {
  final String id;
  final RoleMappingProfileLayerKind kind;
  final String displayName;
  final List<String> recognitionSignature;
  final List<RoleMappingProfileBlock> blocks;

  const RoleMappingProfileLayer({
    required this.id,
    required this.kind,
    required this.displayName,
    this.recognitionSignature = const [],
    this.blocks = const [],
  });

  factory RoleMappingProfileLayer.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final displayName = (json['displayName'] as String? ?? '').trim();
    if (id.isEmpty || displayName.isEmpty) {
      throw const FormatException(
        'Role mapping profile layers require non-empty id and displayName.',
      );
    }
    final signature = <String>{};
    for (final value in json['recognitionSignature'] as List? ?? const []) {
      if (value is! String) {
        throw const FormatException(
          'Role mapping profile layer signatures must be strings.',
        );
      }
      final normalized = normalizeRoleMappingProfileTerm(value);
      if (normalized.isNotEmpty) {
        signature.add(normalized);
      }
    }
    return RoleMappingProfileLayer(
      id: id,
      kind: _enumByName(
        RoleMappingProfileLayerKind.values,
        json['kind'] as String?,
        RoleMappingProfileLayerKind.pending,
      ),
      displayName: displayName,
      recognitionSignature: List.unmodifiable(signature),
      blocks: List.unmodifiable([
        for (final value in json['blocks'] as List? ?? const [])
          RoleMappingProfileBlock.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
      ]),
    );
  }

  factory RoleMappingProfileLayer.legacyShared(
    List<RoleMappingProfileBlock> blocks,
  ) {
    return RoleMappingProfileLayer(
      id: 'legacy-shared',
      kind: RoleMappingProfileLayerKind.shared,
      displayName: '旧缓存',
      recognitionSignature: _recognitionSignatureForBlocks(blocks),
      blocks: List.unmodifiable(blocks),
    );
  }

  RoleMappingProfileLayer copyWith({
    String? id,
    RoleMappingProfileLayerKind? kind,
    String? displayName,
    List<String>? recognitionSignature,
    List<RoleMappingProfileBlock>? blocks,
  }) {
    return RoleMappingProfileLayer(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      recognitionSignature: recognitionSignature ?? this.recognitionSignature,
      blocks: blocks ?? this.blocks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'displayName': displayName,
        'recognitionSignature': recognitionSignature,
        'blocks': blocks.map((block) => block.toJson()).toList(),
      };
}

class RoleMappingProfile {
  final String id;
  final String name;
  final String? targetCharacterId;
  final String targetCharacterNameSnapshot;

  /// Optional exact prompt token used for character-identity replacement.
  ///
  /// This is intentionally separate from the display name. Most profiles keep
  /// it empty because their canonical prompt identity is already represented
  /// by source-faithful tags. A profile may set it when the user explicitly
  /// wants a custom prompt token, such as the Chinese token "果宝".
  final String targetIdentityPromptToken;
  final String targetIdentityPrompt;
  final List<RoleMappingProfileLayer> layers;
  final List<RoleMappingProfileBlock> _legacyBlocks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleMappingProfile({
    required this.id,
    required this.name,
    this.targetCharacterId,
    this.targetCharacterNameSnapshot = '',
    this.targetIdentityPromptToken = '',
    this.targetIdentityPrompt = '',
    this.layers = const [],
    List<RoleMappingProfileBlock> blocks = const [],
    required this.createdAt,
    required this.updatedAt,
  }) : _legacyBlocks = blocks;

  List<RoleMappingProfileBlock> get blocks => List.unmodifiable([
        for (final layer in effectiveLayers) ...layer.blocks,
      ]);

  List<RoleMappingProfileLayer> get effectiveLayers {
    if (layers.isNotEmpty || _legacyBlocks.isEmpty) {
      return layers;
    }
    return List.unmodifiable([
      RoleMappingProfileLayer.legacyShared(_legacyBlocks),
    ]);
  }

  factory RoleMappingProfile.fromJson(
    Map<String, dynamic> json, {
    int sourceSchemaVersion = roleMappingProfileLibrarySchemaVersion,
  }) {
    final id = (json['id'] as String? ?? '').trim();
    final name = (json['name'] as String? ?? '').trim();
    if (id.isEmpty || name.isEmpty) {
      throw const FormatException(
        'Role mapping profiles require non-empty id and name.',
      );
    }
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (createdAt == null || updatedAt == null) {
      throw const FormatException(
        'Role mapping profiles require valid timestamps.',
      );
    }
    final legacyBlocks = List<RoleMappingProfileBlock>.unmodifiable([
      for (final value in json['blocks'] as List? ?? const [])
        RoleMappingProfileBlock.fromJson(
          Map<String, dynamic>.from(value as Map),
        ),
    ]);
    final layers = sourceSchemaVersion <= 1 || json['layers'] == null
        ? legacyBlocks.isEmpty
            ? const <RoleMappingProfileLayer>[]
            : <RoleMappingProfileLayer>[
                RoleMappingProfileLayer.legacyShared(legacyBlocks),
              ]
        : <RoleMappingProfileLayer>[
            for (final value in json['layers'] as List? ?? const [])
              RoleMappingProfileLayer.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
          ];
    return RoleMappingProfile(
      id: id,
      name: name,
      targetCharacterId: _nullableTrimmedString(json['targetCharacterId']),
      targetCharacterNameSnapshot:
          (json['targetCharacterNameSnapshot'] as String? ?? '').trim(),
      targetIdentityPromptToken:
          (json['targetIdentityPromptToken'] as String? ?? '').trim(),
      targetIdentityPrompt: json['targetIdentityPrompt'] as String? ?? '',
      layers: List.unmodifiable(layers),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  RoleMappingProfile copyWith({
    String? id,
    String? name,
    Object? targetCharacterId = _profileUnset,
    String? targetCharacterNameSnapshot,
    String? targetIdentityPromptToken,
    String? targetIdentityPrompt,
    List<RoleMappingProfileBlock>? blocks,
    List<RoleMappingProfileLayer>? layers,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextLayers = layers ??
        (blocks == null
            ? this.layers
            : blocks.isEmpty
                ? const <RoleMappingProfileLayer>[]
                : <RoleMappingProfileLayer>[
                    RoleMappingProfileLayer.legacyShared(blocks),
                  ]);
    return RoleMappingProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      targetCharacterId: identical(targetCharacterId, _profileUnset)
          ? this.targetCharacterId
          : targetCharacterId as String?,
      targetCharacterNameSnapshot:
          targetCharacterNameSnapshot ?? this.targetCharacterNameSnapshot,
      targetIdentityPromptToken:
          targetIdentityPromptToken ?? this.targetIdentityPromptToken,
      targetIdentityPrompt: targetIdentityPrompt ?? this.targetIdentityPrompt,
      layers: List.unmodifiable(nextLayers),
      blocks: nextLayers.isEmpty && blocks == null ? _legacyBlocks : const [],
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (targetCharacterId != null) 'targetCharacterId': targetCharacterId,
        if (targetCharacterNameSnapshot.isNotEmpty)
          'targetCharacterNameSnapshot': targetCharacterNameSnapshot,
        if (targetIdentityPromptToken.trim().isNotEmpty)
          'targetIdentityPromptToken': targetIdentityPromptToken,
        if (targetIdentityPrompt.trim().isNotEmpty)
          'targetIdentityPrompt': targetIdentityPrompt,
        'layers': effectiveLayers.map((layer) => layer.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

class RoleMappingProfileLibrary {
  final int schemaVersion;
  final List<RoleMappingProfile> profiles;

  const RoleMappingProfileLibrary({
    this.schemaVersion = roleMappingProfileLibrarySchemaVersion,
    this.profiles = const [],
  });

  factory RoleMappingProfileLibrary.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    if (schemaVersion < 1) {
      throw FormatException(
        'Unsupported role mapping profile library schema $schemaVersion.',
      );
    }
    if (schemaVersion > roleMappingProfileLibrarySchemaVersion) {
      throw FormatException(
        'Role mapping profile library schema $schemaVersion is newer than '
        'supported schema $roleMappingProfileLibrarySchemaVersion.',
      );
    }
    final profiles = [
      for (final value in json['profiles'] as List? ?? const [])
        RoleMappingProfile.fromJson(
          Map<String, dynamic>.from(value as Map),
          sourceSchemaVersion: schemaVersion,
        ),
    ];
    validateRoleMappingProfileNames(profiles);
    return RoleMappingProfileLibrary(
      schemaVersion: roleMappingProfileLibrarySchemaVersion,
      profiles: List.unmodifiable(profiles),
    );
  }

  RoleMappingProfileLibrary copyWith({
    int? schemaVersion,
    List<RoleMappingProfile>? profiles,
  }) {
    return RoleMappingProfileLibrary(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      profiles: profiles ?? this.profiles,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': roleMappingProfileLibrarySchemaVersion,
        'profiles': profiles.map((profile) => profile.toJson()).toList(),
      };
}

enum RoleMappingApplyPreviewStatus {
  matched,
  same,
  conflict,
  ambiguous,
  unmatched,
}

enum RoleMappingProfileLayerMatchStatus {
  matched,
  ambiguous,
  unmatched,
  conflict,
}

class RoleMappingProfileLayerApplyPreview {
  final RoleMappingProfileLayer layer;
  final RoleMappingProfileLayerMatchStatus status;
  final String matchedCurrentLayerId;
  final List<String> candidateCurrentLayerIds;
  final bool selectedByDefault;

  const RoleMappingProfileLayerApplyPreview({
    required this.layer,
    required this.status,
    this.matchedCurrentLayerId = '',
    this.candidateCurrentLayerIds = const [],
    this.selectedByDefault = false,
  });
}

class RoleMappingApplyPreviewEntry {
  final RoleMappingProfileBlock block;
  final String profileLayerId;
  final RoleMappingApplyPreviewStatus status;
  final List<String> selectedTermIds;
  final List<String> availableTermIds;
  final List<String> affectedRuleIds;
  final List<String> pendingSplitRuleIds;
  final List<String> pendingMergeRuleIds;
  final bool selectedByDefault;

  const RoleMappingApplyPreviewEntry({
    required this.block,
    this.profileLayerId = '',
    required this.status,
    this.selectedTermIds = const [],
    this.availableTermIds = const [],
    this.affectedRuleIds = const [],
    this.pendingSplitRuleIds = const [],
    this.pendingMergeRuleIds = const [],
    this.selectedByDefault = false,
  });

  RoleMappingApplyPreviewEntry copyWith({
    RoleMappingApplyPreviewStatus? status,
    String? profileLayerId,
    List<String>? selectedTermIds,
    List<String>? availableTermIds,
    List<String>? affectedRuleIds,
    List<String>? pendingSplitRuleIds,
    List<String>? pendingMergeRuleIds,
    bool? selectedByDefault,
  }) {
    return RoleMappingApplyPreviewEntry(
      block: block,
      profileLayerId: profileLayerId ?? this.profileLayerId,
      status: status ?? this.status,
      selectedTermIds: selectedTermIds ?? this.selectedTermIds,
      availableTermIds: availableTermIds ?? this.availableTermIds,
      affectedRuleIds: affectedRuleIds ?? this.affectedRuleIds,
      pendingSplitRuleIds: pendingSplitRuleIds ?? this.pendingSplitRuleIds,
      pendingMergeRuleIds: pendingMergeRuleIds ?? this.pendingMergeRuleIds,
      selectedByDefault: selectedByDefault ?? this.selectedByDefault,
    );
  }
}

class RoleMappingApplyPreview {
  final String profileId;
  final String sourceRoleId;
  final List<RoleMappingApplyPreviewEntry> entries;
  final List<RoleMappingProfileLayerApplyPreview> layerEntries;

  const RoleMappingApplyPreview({
    required this.profileId,
    required this.sourceRoleId,
    this.entries = const [],
    this.layerEntries = const [],
  });
}

class RoleMappingProfileApplySelection {
  final String blockId;
  final List<String> termIds;
  final String anchorTermId;

  const RoleMappingProfileApplySelection({
    required this.blockId,
    this.termIds = const [],
    this.anchorTermId = '',
  });
}

class RoleMappingProfileLayerApplySelection {
  final String profileLayerId;
  final ScriptRoleReplacementRuleLayerKind? targetKind;
  final String targetStageId;

  const RoleMappingProfileLayerApplySelection({
    required this.profileLayerId,
    this.targetKind,
    this.targetStageId = '',
  });

  bool get skipped => targetKind == null;
}

enum RoleMappingProfileDeletionKind { identity, block, layerMove }

class RoleMappingProfileDeletionPrompt {
  final String profileId;
  final String profileName;
  final String sourceRoleId;
  final RoleMappingProfileDeletionKind kind;
  final String blockId;
  final String label;

  const RoleMappingProfileDeletionPrompt({
    required this.profileId,
    required this.profileName,
    required this.sourceRoleId,
    required this.kind,
    this.blockId = '',
    required this.label,
  });
}

void validateRoleMappingProfileNames(Iterable<RoleMappingProfile> profiles) {
  final names = <String>{};
  for (final profile in profiles) {
    final normalized = profile.name.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw const FormatException(
        'Role mapping profile names cannot be empty.',
      );
    }
    if (!names.add(normalized)) {
      throw FormatException(
        'Duplicate role mapping profile name: ${profile.name}',
      );
    }
  }
}

String _anchorKeyForRule(ScriptPromptReplacementRule rule) {
  if (rule.anchorTermId.trim().isEmpty) {
    return '';
  }
  for (final term in rule.sourceTerms) {
    if (term.id == rule.anchorTermId) {
      return normalizeRoleMappingProfileTerm(term.text);
    }
  }
  return '';
}

List<String> _recognitionSignatureForBlocks(
  Iterable<RoleMappingProfileBlock> blocks,
) {
  final signature = <String>{};
  for (final block in blocks) {
    signature.addAll(block.detectionKeys);
  }
  final result = signature.toList()..sort();
  return List.unmodifiable(result);
}

T _enumByName<T extends Enum>(
  List<T> values,
  String? name,
  T fallback,
) {
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

double? _positiveFiniteDoubleOrNull(Object? value) {
  if (value is! num) return null;
  final resolved = value.toDouble();
  if (!resolved.isFinite || resolved <= 0) return null;
  return resolved;
}

String? _nullableTrimmedString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

const Object _profileUnset = Object();
