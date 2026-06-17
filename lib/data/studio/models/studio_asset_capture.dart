import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/workbench_document.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

enum StudioAssetCaptureKind {
  artistChain,
  character,
  outfit,
}

extension StudioAssetCaptureKindLabel on StudioAssetCaptureKind {
  String get storageKey => switch (this) {
        StudioAssetCaptureKind.artistChain => 'artist-chain',
        StudioAssetCaptureKind.character => 'character',
        StudioAssetCaptureKind.outfit => 'outfit',
      };

  String get label => switch (this) {
        StudioAssetCaptureKind.artistChain => 'artist chain',
        StudioAssetCaptureKind.character => 'character',
        StudioAssetCaptureKind.outfit => 'outfit',
      };
}

class StudioAssetCaptureSource {
  final String surface;
  final String label;
  final String? sourceId;
  final String? path;

  const StudioAssetCaptureSource({
    required this.surface,
    required this.label,
    this.sourceId,
    this.path,
  });

  SourceRef toSourceRef() {
    return SourceRef(
      type: surface.trim().isEmpty ? 'structured_capture' : surface.trim(),
      id: _blankToNull(sourceId),
      path: _blankToNull(path),
    );
  }
}

class StudioAssetDuplicateCandidate {
  final StudioAssetCaptureKind kind;
  final String id;
  final String name;
  final String summary;

  const StudioAssetDuplicateCandidate({
    required this.kind,
    required this.id,
    required this.name,
    required this.summary,
  });
}

class StudioAssetCapturePlan {
  final StudioAssetCaptureDraft draft;
  final List<StudioAssetDuplicateCandidate> candidates;

  const StudioAssetCapturePlan({
    required this.draft,
    this.candidates = const [],
  });

  bool get hasCandidates => candidates.isNotEmpty;
}

class StudioAssetCaptureResult {
  final StudioAssetCaptureKind kind;
  final String savedId;
  final String name;
  final bool merged;

  const StudioAssetCaptureResult({
    required this.kind,
    required this.savedId,
    required this.name,
    required this.merged,
  });
}

class StudioAssetCaptureDraft {
  final StudioAssetCaptureKind kind;
  final String name;
  final String note;
  final StudioAssetCaptureSource source;
  final ArtistChain? artistChain;
  final CharacterEntry? character;
  final WorkspaceOutfit? outfit;
  final String? parentCharacterId;

  const StudioAssetCaptureDraft._({
    required this.kind,
    required this.name,
    required this.note,
    required this.source,
    this.artistChain,
    this.character,
    this.outfit,
    this.parentCharacterId,
  });

  factory StudioAssetCaptureDraft.artistChain({
    required ArtistChain artistChain,
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    return StudioAssetCaptureDraft._(
      kind: StudioAssetCaptureKind.artistChain,
      name: _firstText([name, artistChain.name, 'Artist chain']),
      note: note,
      source: source,
      artistChain: artistChain,
    );
  }

  factory StudioAssetCaptureDraft.character({
    required CharacterEntry character,
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    return StudioAssetCaptureDraft._(
      kind: StudioAssetCaptureKind.character,
      name: _firstText([name, character.name, 'Character']),
      note: note,
      source: source,
      character: character,
    );
  }

  factory StudioAssetCaptureDraft.outfit({
    required WorkspaceOutfit outfit,
    required String parentCharacterId,
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    return StudioAssetCaptureDraft._(
      kind: StudioAssetCaptureKind.outfit,
      name: _firstText([name, outfit.name, 'Outfit']),
      note: note,
      source: source,
      outfit: outfit,
      parentCharacterId: parentCharacterId,
    );
  }

  StudioAssetCaptureDraft copyWith({
    String? name,
    String? note,
    StudioAssetCaptureKind? kind,
    String? parentCharacterId,
  }) {
    final requestedKind = kind ?? this.kind;
    final nextKind =
        availableKinds.contains(requestedKind) ? requestedKind : this.kind;
    return StudioAssetCaptureDraft._(
      kind: nextKind,
      name: name ?? this.name,
      note: note ?? this.note,
      source: source,
      artistChain:
          nextKind == StudioAssetCaptureKind.artistChain ? artistChain : null,
      character:
          nextKind == StudioAssetCaptureKind.character ? character : null,
      outfit: nextKind == StudioAssetCaptureKind.outfit ? outfit : null,
      parentCharacterId: nextKind == StudioAssetCaptureKind.outfit
          ? parentCharacterId ?? this.parentCharacterId
          : null,
    );
  }

  List<StudioAssetCaptureKind> get availableKinds {
    return [
      if (artistChain != null) StudioAssetCaptureKind.artistChain,
      if (character != null) StudioAssetCaptureKind.character,
      if (outfit != null) StudioAssetCaptureKind.outfit,
    ];
  }
}

class StudioAssetCaptureDrafts {
  const StudioAssetCaptureDrafts._();

  static StudioAssetCaptureDraft artistFromAiEvidence(
    ScriptAiArtistChainEvidence evidence, {
    required StudioAssetCaptureSource source,
  }) {
    final tags = _dedupeTags(evidence.terms);
    final artistNames = tags
        .where(_isArtistTag)
        .map(_stripArtistPrefix)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final name = _firstText([
      evidence.label,
      artistNames.join(' + '),
      'Artist chain',
    ]);
    final chain = ArtistChain(
      id: stableIdFromText(
        prefix: 'artist-chain',
        label: name,
        text: 'ai-artist:${source.surface}:${source.sourceId}:$tags',
      ),
      name: name,
      tags: tags,
      prompt: _joinTags(tags),
      styleTags: _dedupeTags(tags.where((tag) => !_isArtistTag(tag))),
      artists: [
        for (final artist in artistNames) ArtistEntry(name: artist),
      ],
      source: source.toSourceRef(),
      note: _joinTags(evidence.evidenceTerms),
    );
    return StudioAssetCaptureDraft.artistChain(
      artistChain: chain,
      source: source,
      name: name,
    );
  }

  static StudioAssetCaptureDraft artistFromPrompt(
    String prompt, {
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    final promptTags = _dedupeTags(
      _splitTags(prompt).map(_cleanPromptTagForCapture),
    );
    final strongArtistIndexes = <int>[];
    final strongArtistTags = <int, String>{};
    for (final (index, tag) in promptTags.indexed) {
      final artistTag = _artistTagForCapture(tag);
      if (artistTag == null) continue;
      strongArtistIndexes.add(index);
      strongArtistTags[index] = artistTag;
    }
    final firstStrongArtistIndex = strongArtistIndexes.isEmpty
        ? null
        : strongArtistIndexes
            .reduce((left, right) => left < right ? left : right);
    final lastStrongArtistIndex = strongArtistIndexes.isEmpty
        ? null
        : strongArtistIndexes
            .reduce((left, right) => left > right ? left : right);
    final artistTags = _dedupeTags([
      for (final (index, tag) in promptTags.indexed)
        if (strongArtistTags[index] case final artistTag?)
          artistTag
        else if (firstStrongArtistIndex != null &&
            lastStrongArtistIndex != null &&
            index > firstStrongArtistIndex &&
            index < lastStrongArtistIndex &&
            _isWeakBareArtistAlias(tag))
          tag,
    ]);
    final artistTagKeys = {
      for (final tag in artistTags) tag.trim().toLowerCase(),
    };
    final styleTags = _dedupeTags(
      promptTags.where(
        (tag) =>
            !artistTagKeys.contains(tag.trim().toLowerCase()) &&
            _isLikelyArtistChainStyleTag(tag),
      ),
    );
    final artistNames =
        artistTags.map(_stripArtistPrefix).toList(growable: false);
    final chainName = _firstText([
      name,
      artistNames.join(' + '),
      source.label,
      'Artist chain',
    ]);
    final chain = ArtistChain(
      id: stableIdFromText(
        prefix: 'artist-chain',
        label: chainName,
        text: 'prompt-artist:${source.surface}:${source.sourceId}:'
            '$artistTags:$styleTags',
      ),
      name: chainName,
      tags: artistTags,
      styleTags: styleTags,
      prompt: _joinTags([...artistTags, ...styleTags]),
      artists: [
        for (final artist in artistNames) ArtistEntry(name: artist),
      ],
      source: source.toSourceRef(),
      note: note,
    );
    return StudioAssetCaptureDraft.artistChain(
      artistChain: chain,
      source: source,
      name: chainName,
      note: note,
    );
  }

  static StudioAssetCaptureDraft artistFromVisibleTags(
    Iterable<String> tags, {
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    final promptTags = _dedupeTags(tags);
    final artistNames = promptTags
        .where(_isArtistTag)
        .map(_stripArtistPrefix)
        .where((artist) => artist.isNotEmpty)
        .toList(growable: false);
    final chainName = _firstText([
      name,
      artistNames.join(' + '),
      source.label,
      'Artist chain',
    ]);
    final chain = ArtistChain(
      id: stableIdFromText(
        prefix: 'artist-chain',
        label: chainName,
        text: 'visible-artist:${source.surface}:${source.sourceId}:'
            '$promptTags',
      ),
      name: chainName,
      tags: promptTags,
      prompt: _joinTags(promptTags),
      artists: [
        for (final artist in artistNames) ArtistEntry(name: artist),
      ],
      source: source.toSourceRef(),
      note: note,
    );
    return StudioAssetCaptureDraft.artistChain(
      artistChain: chain,
      source: source,
      name: chainName,
      note: note,
    );
  }

  static StudioAssetCaptureDraft characterFromVisibleTags(
    Iterable<String> tags, {
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    final identityTags = _dedupeTags(tags).where((tag) {
      return !_isCharacterCountTag(tag);
    }).toList(growable: false);
    final characterName = _firstText([name, source.label, 'Character']);
    final character = CharacterEntry(
      id: stableIdFromText(
        prefix: 'character',
        label: characterName,
        text: 'visible-character:${source.surface}:${source.sourceId}:'
            '$identityTags',
      ),
      name: characterName,
      traits: ViewVariantTexts(frontFull: _joinTags(identityTags)),
      source: source.toSourceRef(),
      note: note,
      identityTags: identityTags,
    );
    return StudioAssetCaptureDraft.character(
      character: character,
      source: source,
      name: characterName,
      note: note,
    );
  }

  static StudioAssetCaptureDraft characterFromAiRole(
    ScriptAiExtractedRole role, {
    required StudioAssetCaptureSource source,
  }) {
    final name = _firstText([role.displayName, role.sourceRoleId, 'Character']);
    final firstStage = role.stages.isEmpty ? null : role.stages.first;
    final identityTags = _dedupeTags([
      if (firstStage != null) ..._splitTags(firstStage.identity),
      ...role.evidenceTerms,
    ]);
    final traits = ViewVariantTexts(
      frontFull: _joinTags(identityTags),
      frontUpper:
          firstStage == null ? null : _emptyToNull(firstStage.upperBody),
      frontLower:
          firstStage == null ? null : _emptyToNull(firstStage.lowerBody),
    );
    final outfits = [
      for (final (index, stage) in role.stages.indexed)
        if (_stageHasOutfitTerms(stage))
          WorkspaceOutfit(
            id: stableIdFromText(
              prefix: 'outfit',
              label: _firstText([stage.label, 'outfit-${index + 1}']),
              text: 'ai-role-outfit:${role.sourceRoleId}:${stage.stageId}:'
                  '${stage.toJson()}',
            ),
            name: _firstText([stage.label, 'Outfit ${index + 1}']),
            tags: ViewVariantTexts(
              frontFull: _joinTags([
                ..._splitTags(stage.upperBody),
                ..._splitTags(stage.lowerBody),
                ..._splitTags(stage.upperClothing),
                ..._splitTags(stage.lowerClothing),
              ]),
              frontUpper: _emptyToNull(_joinTags([
                ..._splitTags(stage.upperBody),
                ..._splitTags(stage.upperClothing),
              ])),
              frontLower: _emptyToNull(_joinTags([
                ..._splitTags(stage.lowerBody),
                ..._splitTags(stage.lowerClothing),
              ])),
            ),
            partTags: WorkspaceOutfitPartTags(
              upperBodyTags: _splitTags(stage.upperBody),
              upperClothingTags: _splitTags(stage.upperClothing),
              lowerBodyTags: _splitTags(stage.lowerBody),
              lowerClothingTags: _splitTags(stage.lowerClothing),
            ),
            note: _joinTags(stage.evidenceTerms),
          ),
    ];
    final character = CharacterEntry(
      id: stableIdFromText(
        prefix: 'character',
        label: name,
        text: 'ai-role:${source.surface}:${source.sourceId}:'
            '${role.sourceRoleId}:${role.toJson()}',
      ),
      name: name,
      traits: traits,
      outfits: List.unmodifiable(outfits),
      defaultOutfitId: outfits.isEmpty ? null : outfits.first.id,
      source: source.toSourceRef(),
      note: _joinTags(role.warnings),
      identityTags: identityTags,
      aliases: _dedupeTags([role.sourceRoleId]),
      recastNotes: _joinTags(role.unassignedTerms.map((term) => term.term)),
    );
    return StudioAssetCaptureDraft.character(
      character: character,
      source: source,
      name: name,
    );
  }

  static List<StudioAssetCaptureDraft> fromWorkbenchDocument(
    WorkbenchDocument document, {
    required StudioAssetCaptureSource source,
  }) {
    final drafts = <StudioAssetCaptureDraft>[];
    final characterJson = document.payload['character_config'];
    if (characterJson is List) {
      for (final (index, item) in characterJson.indexed) {
        if (item is! Map) continue;
        final config = _tryParseCharacterConfig(item);
        if (config == null) continue;
        final rows = _flattenPromptConfig(config.positivePromptConfig);
        if (rows.isEmpty) continue;
        final tags = _dedupeTags(rows.expand(_splitTags));
        final name =
            _firstText([config.name, 'Document character ${index + 1}']);
        final character = CharacterEntry(
          id: stableIdFromText(
            prefix: 'character',
            label: name,
            text: 'workbench-character:${source.sourceId}:$index:'
                '${config.toJson()}',
          ),
          name: name,
          traits: ViewVariantTexts(frontFull: _joinTags(tags)),
          identityTags: tags,
          source: source.toSourceRef(),
          note: config.negativePrompt.trim().isEmpty
              ? ''
              : 'negative: ${config.negativePrompt.trim()}',
        );
        drafts.add(
          StudioAssetCaptureDraft.character(
            character: character,
            source: source,
            name: name,
          ),
        );
      }
    }

    final promptRows = <String>[];
    final rootPromptJson = document.payload['prompt_config'];
    if (rootPromptJson is Map) {
      final rootPrompt = _tryParsePromptConfig(rootPromptJson);
      if (rootPrompt != null) {
        promptRows.addAll(_flattenPromptConfig(rootPrompt));
      }
    }
    final paramJson = document.payload['param_config'];
    if (paramJson is Map) {
      promptRows.addAll(_flattenV4PromptRows(paramJson['v4_prompt']));
    }
    final savedPromptJson = document.payload['saved_config'];
    if (savedPromptJson is List) {
      for (final item in savedPromptJson) {
        if (item is! Map) continue;
        final savedPrompt = _tryParsePromptConfig(item);
        if (savedPrompt == null) continue;
        promptRows.addAll(_flattenPromptConfig(savedPrompt));
      }
    }
    final promptTags = _dedupeTags(promptRows.expand(_splitTags));
    final artistTags = _dedupeTags(promptTags.where(_isArtistTag));
    if (artistTags.isNotEmpty) {
      final styleTags = _dedupeTags(
        promptTags.where(
          (tag) => !_isArtistTag(tag) && _isLikelyArtistChainStyleTag(tag),
        ),
      );
      final artistNames =
          artistTags.map(_stripArtistPrefix).toList(growable: false);
      final name = _firstText([
        artistNames.join(' + '),
        '${source.label} artist chain',
      ]);
      drafts.add(
        StudioAssetCaptureDraft.artistChain(
          source: source,
          name: name,
          artistChain: ArtistChain(
            id: stableIdFromText(
              prefix: 'artist-chain',
              label: name,
              text: 'workbench-artist:${source.sourceId}:'
                  '$artistTags:$styleTags',
            ),
            name: name,
            tags: artistTags,
            styleTags: styleTags,
            prompt: _joinTags([...artistTags, ...styleTags]),
            artists: [
              for (final artist in artistNames) ArtistEntry(name: artist),
            ],
            source: source.toSourceRef(),
          ),
        ),
      );
    }

    return List.unmodifiable(drafts);
  }
}

CharacterConfig? _tryParseCharacterConfig(Map<dynamic, dynamic> item) {
  try {
    return CharacterConfig.fromJson(item.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

PromptConfig? _tryParsePromptConfig(Map<dynamic, dynamic> item) {
  try {
    return PromptConfig.fromJson(item.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

List<String> _flattenPromptConfig(PromptConfig config) {
  if (!config.enabled) return const [];
  final rows = <String>[
    ...PromptConfig.normalizeStrRows(config.strs),
    for (final child in config.prompts) ..._flattenPromptConfig(child),
  ];
  return _dedupeTags(rows);
}

List<String> _flattenV4PromptRows(dynamic value) {
  if (value is! Map) return const [];
  final prompt = value.cast<dynamic, dynamic>();
  final captionJson = prompt['caption'];
  if (captionJson is! Map) return const [];
  final caption = captionJson.cast<dynamic, dynamic>();
  final rows = <String>[
    if (_stringValue(caption['base_caption']) case final base?) base,
    if (_stringValue(caption['baseCaption']) case final base?) base,
    if (_stringValue(caption['prompt']) case final base?) base,
  ];
  final charCaptions = caption['char_captions'];
  if (charCaptions is List) {
    for (final entry in charCaptions) {
      if (entry is! Map) continue;
      final charCaption = _stringValue(entry['char_caption']);
      if (charCaption != null) rows.add(charCaption);
    }
  }
  return _dedupeTags(rows);
}

List<String> _splitTags(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split(RegExp(r'[,\n]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

List<String> _dedupeTags(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) continue;
    final key = cleaned.toLowerCase();
    if (!seen.add(key)) continue;
    result.add(cleaned);
  }
  return List.unmodifiable(result);
}

bool _isArtistTag(String value) {
  return _artistTagForCapture(value) != null;
}

String? _artistTagForCapture(String value) {
  final cleaned = _cleanPromptTagForCapture(value);
  if (cleaned.isEmpty) return null;
  final normalized = cleaned.toLowerCase();
  if (RegExp(r'^artist\s*[:：]\s*').hasMatch(normalized)) {
    return cleaned;
  }
  if (_isLikelyBareArtistAlias(cleaned)) {
    return cleaned;
  }
  return null;
}

String _cleanPromptTagForCapture(String value) {
  final display = PromptTagProcessor.cleanTagDisplay(
    value,
    removeWeights: true,
  ).trim();
  if (display.isNotEmpty) {
    return display;
  }
  return value.trim();
}

bool _isLikelyBareArtistAlias(String value) {
  final normalized = _cleanPromptTagForCapture(value).toLowerCase();
  if (normalized.isEmpty) return false;
  if (normalized.startsWith('artist ')) return false;
  if (_isLikelyPromptSubjectTag(normalized)) return false;
  if (RegExp(r'^\d').hasMatch(normalized)) return false;
  if (normalized.contains('_')) {
    return RegExp(r'[a-z]').hasMatch(normalized);
  }
  if (RegExp(r'^[a-z][a-z0-9.-]*\d[a-z0-9.-]*$').hasMatch(normalized)) {
    return true;
  }
  return RegExp(r'^[a-z0-9_.-]+ \([a-z0-9_. -]+\)$').hasMatch(normalized);
}

bool _isWeakBareArtistAlias(String value) {
  final normalized = _cleanPromptTagForCapture(value).toLowerCase();
  if (normalized.isEmpty) return false;
  if (_isLikelyPromptSubjectTag(normalized)) return false;
  if (normalized.startsWith('artist ')) return false;
  if (_isLikelyWorkbenchStyleTag(normalized)) return false;
  return RegExp(r'^[a-z][a-z0-9.-]{2,}$').hasMatch(normalized);
}

bool _isLikelyPromptSubjectTag(String normalized) {
  if (_promptSubjectTags.contains(normalized)) return true;
  if (RegExp(r'^\d+(girl|boy|girls|boys|male|female)s?$')
      .hasMatch(normalized)) {
    return true;
  }
  return false;
}

const _promptSubjectTags = {
  '1girl',
  '1boy',
  '2girls',
  '2boys',
  'solo',
  'girl',
  'boy',
  'woman',
  'man',
  'female',
  'male',
  'bedroom',
  'indoors',
  'outdoors',
  'street',
  'city',
  'cityscape',
  'school',
  'classroom',
  'office',
  'room',
  'simple background',
  'white background',
};

bool _isLikelyArtistChainStyleTag(String value) {
  final normalized = _cleanPromptTagForCapture(value).toLowerCase();
  if (normalized.isEmpty) return false;
  if (normalized == 'artist collaboration') return true;
  return _isLikelyWorkbenchStyleTag(normalized);
}

bool _isLikelyWorkbenchStyleTag(String value) {
  final normalized = _cleanPromptTagForCapture(value).toLowerCase();
  if (normalized.isEmpty) return false;
  const styleWords = {
    'anime',
    'cartoon',
    'cel',
    'comic',
    'gouache',
    'illustration',
    'impasto',
    'ink',
    'lineart',
    'manga',
    'oil',
    'painterly',
    'painting',
    'pastel',
    'render',
    'shading',
    'sketch',
    'style',
    'watercolor',
  };
  return styleWords.any(normalized.contains);
}

String _stripArtistPrefix(String value) {
  final trimmed = _cleanPromptTagForCapture(value);
  return trimmed
      .replaceFirst(RegExp(r'^artist\s*[:：]\s*', caseSensitive: false), '')
      .trim();
}

String _joinTags(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(', ');
}

bool _isCharacterCountTag(String tag) {
  final value = tag
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_\s]+'), '_')
      .replaceAll(RegExp(r'^-?\d+(?:\.\d+)?::\s*'), '')
      .replaceAll(RegExp(r'\s*::-?\d+(?:\.\d+)?$'), '');
  return RegExp(
    r'^(\d+(?:girls?|boys?|males?|females?)|solo|multiple_girls|multiple_boys)$',
  ).hasMatch(value);
}

String _firstText(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return 'Untitled';
}

String? _stringValue(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

bool _stageHasOutfitTerms(ScriptAiExtractedStage stage) {
  return [
    stage.upperBody,
    stage.lowerBody,
    stage.upperClothing,
    stage.lowerClothing,
  ].any((value) => value.trim().isNotEmpty);
}
