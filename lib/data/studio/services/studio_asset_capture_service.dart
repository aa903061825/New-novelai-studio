import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioAssetCaptureException implements Exception {
  final String message;

  const StudioAssetCaptureException(this.message);

  @override
  String toString() => 'StudioAssetCaptureException: $message';
}

class StudioAssetCaptureService {
  final WorkspaceService workspaceService;

  const StudioAssetCaptureService({required this.workspaceService});

  Future<StudioAssetCapturePlan> previewSave(
    StudioAssetCaptureDraft draft,
  ) async {
    return switch (draft.kind) {
      StudioAssetCaptureKind.artistChain => StudioAssetCapturePlan(
          draft: draft,
          candidates: await _artistChainCandidates(draft),
        ),
      StudioAssetCaptureKind.character => StudioAssetCapturePlan(
          draft: draft,
          candidates: await _characterCandidates(draft),
        ),
      StudioAssetCaptureKind.outfit => StudioAssetCapturePlan(
          draft: draft,
          candidates: await _outfitCandidates(draft),
        ),
    };
  }

  Future<StudioAssetCaptureResult> save(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    bool forceNew = false,
    String? nameOverride,
    String? noteOverride,
  }) async {
    return switch (draft.kind) {
      StudioAssetCaptureKind.artistChain => _saveArtistChain(
          draft,
          targetId: forceNew ? null : targetId,
          nameOverride: nameOverride,
          noteOverride: noteOverride,
        ),
      StudioAssetCaptureKind.character => _saveCharacter(
          draft,
          targetId: forceNew ? null : targetId,
          nameOverride: nameOverride,
          noteOverride: noteOverride,
        ),
      StudioAssetCaptureKind.outfit => _saveOutfit(
          draft,
          targetId: forceNew ? null : targetId,
          nameOverride: nameOverride,
          noteOverride: noteOverride,
        ),
    };
  }

  Future<List<StudioAssetDuplicateCandidate>> _artistChainCandidates(
    StudioAssetCaptureDraft draft,
  ) async {
    final incoming = draft.artistChain;
    if (incoming == null) return const [];

    final incomingTagSignature = _artistCombinedTagSignature(incoming);
    final incomingPromptSignature = _promptSignature(incoming.prompt);
    if (incomingTagSignature.isEmpty && incomingPromptSignature.isEmpty) {
      return const [];
    }

    final candidates = <StudioAssetDuplicateCandidate>[];
    for (final existing in await workspaceService.loadArtistChains()) {
      final tagsMatch = incomingTagSignature.isNotEmpty &&
          incomingTagSignature == _artistCombinedTagSignature(existing);
      final promptMatch = incomingPromptSignature.isNotEmpty &&
          incomingPromptSignature == _promptSignature(existing.prompt);
      if (!tagsMatch && !promptMatch) continue;
      candidates.add(
        StudioAssetDuplicateCandidate(
          kind: StudioAssetCaptureKind.artistChain,
          id: existing.id,
          name: existing.name,
          summary: _joinTags(_mergeTags(existing.tags, existing.styleTags)),
        ),
      );
    }
    return List.unmodifiable(candidates);
  }

  Future<List<StudioAssetDuplicateCandidate>> _characterCandidates(
    StudioAssetCaptureDraft draft,
  ) async {
    final incoming = draft.character;
    if (incoming == null) return const [];

    final incomingName = _normalize(incoming.name);
    final incomingIdentitySignature = _tagSignature(incoming.identityTags);
    final candidates = <StudioAssetDuplicateCandidate>[];
    for (final existing in await workspaceService.loadCharacters()) {
      final nameMatch =
          incomingName.isNotEmpty && incomingName == _normalize(existing.name);
      final identityMatch = incomingIdentitySignature.isNotEmpty &&
          incomingIdentitySignature == _tagSignature(existing.identityTags);
      if (!nameMatch && !identityMatch) continue;
      candidates.add(
        StudioAssetDuplicateCandidate(
          kind: StudioAssetCaptureKind.character,
          id: existing.id,
          name: existing.name,
          summary: _joinTags(existing.identityTags),
        ),
      );
    }
    return List.unmodifiable(candidates);
  }

  Future<List<StudioAssetDuplicateCandidate>> _outfitCandidates(
    StudioAssetCaptureDraft draft,
  ) async {
    final incoming = draft.outfit;
    if (incoming == null) return const [];
    final parentId = draft.parentCharacterId?.trim() ?? '';
    if (parentId.isEmpty) return const [];

    final characters = await workspaceService.loadCharacters();
    final parentIndex = _indexById(characters, parentId);
    if (parentIndex < 0) return const [];

    final incomingName = _normalize(incoming.name);
    final incomingFrontFull = _promptSignature(incoming.tags.frontFull);
    final candidates = <StudioAssetDuplicateCandidate>[];
    for (final existing in characters[parentIndex].outfits) {
      final nameMatch =
          incomingName.isNotEmpty && incomingName == _normalize(existing.name);
      final frontFullMatch = incomingFrontFull.isNotEmpty &&
          incomingFrontFull == _promptSignature(existing.tags.frontFull);
      if (!nameMatch && !frontFullMatch) continue;
      candidates.add(
        StudioAssetDuplicateCandidate(
          kind: StudioAssetCaptureKind.outfit,
          id: existing.id,
          name: existing.name,
          summary: existing.tags.frontFull,
        ),
      );
    }
    return List.unmodifiable(candidates);
  }

  Future<StudioAssetCaptureResult> _saveArtistChain(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    String? nameOverride,
    String? noteOverride,
  }) async {
    final incoming = draft.artistChain;
    if (incoming == null) {
      throw const StudioAssetCaptureException(
        'Artist chain capture draft does not contain an artist chain.',
      );
    }

    final chains = await workspaceService.loadArtistChains();
    final targetIndex = _indexById(chains, targetId);
    if (targetIndex < 0) {
      final saved = incoming.copyWith(
        name: _firstText([nameOverride, incoming.name, draft.name]),
        note: _firstTextAllowEmpty([noteOverride, incoming.note, draft.note]),
      );
      await workspaceService.saveArtistChains([...chains, saved]);
      return StudioAssetCaptureResult(
        kind: StudioAssetCaptureKind.artistChain,
        savedId: saved.id,
        name: saved.name,
        merged: false,
      );
    }

    final existing = chains[targetIndex];
    final merged = existing.copyWith(
      tags: _mergeTags(existing.tags, incoming.tags),
      prompt: _joinTags(_mergeTags(_splitTags(existing.prompt), [
        ..._splitTags(incoming.prompt),
        ...incoming.tags,
        ...incoming.styleTags,
      ])),
      styleTags: _mergeTags(existing.styleTags, incoming.styleTags),
      imageRefs: _mergeTags(existing.imageRefs, incoming.imageRefs),
      note: _mergeNote(
          existing.note,
          _firstTextAllowEmpty([
            noteOverride,
            incoming.note,
            draft.note,
          ])),
      artists: _mergeByKey(
        existing.artists,
        incoming.artists,
        (artist) => artist.name,
      ),
      globalNegatives: _mergeByKey(
        existing.globalNegatives,
        incoming.globalNegatives,
        (tag) => tag.tag,
      ),
      styleHintsWeighted: _mergeByKey(
        existing.styleHintsWeighted,
        incoming.styleHintsWeighted,
        (tag) => tag.tag,
      ),
      vibeRefs: _mergeByKey(
        existing.vibeRefs,
        incoming.vibeRefs,
        (vibe) => vibe.id,
      ),
    );
    final updated = [...chains]..[targetIndex] = merged;
    await workspaceService.saveArtistChains(updated);
    return StudioAssetCaptureResult(
      kind: StudioAssetCaptureKind.artistChain,
      savedId: merged.id,
      name: merged.name,
      merged: true,
    );
  }

  Future<StudioAssetCaptureResult> _saveCharacter(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    String? nameOverride,
    String? noteOverride,
  }) async {
    final incoming = draft.character;
    if (incoming == null) {
      throw const StudioAssetCaptureException(
        'Character capture draft does not contain a character.',
      );
    }

    final characters = await workspaceService.loadCharacters();
    final targetIndex = _indexById(characters, targetId);
    if (targetIndex < 0) {
      final saved = incoming.copyWith(
        name: _firstText([nameOverride, incoming.name, draft.name]),
        note: _firstTextAllowEmpty([noteOverride, incoming.note, draft.note]),
      );
      await workspaceService.saveCharacters([...characters, saved]);
      return StudioAssetCaptureResult(
        kind: StudioAssetCaptureKind.character,
        savedId: saved.id,
        name: saved.name,
        merged: false,
      );
    }

    final existing = characters[targetIndex];
    final merged = _manualizedCharacter(existing.copyWith(
      traits: _mergeViewVariantTexts(existing.traits, incoming.traits),
      outfits: _mergeCharacterOutfits(existing.outfits, incoming.outfits),
      defaultOutfitId: existing.defaultOutfitId ?? incoming.defaultOutfitId,
      imageRefs: _mergeTags(existing.imageRefs, incoming.imageRefs),
      note: _mergeNote(
          existing.note,
          _firstTextAllowEmpty([
            noteOverride,
            incoming.note,
            draft.note,
          ])),
      anchorTags: _mergeTags(existing.anchorTags, incoming.anchorTags),
      identityTags: _mergeTags(existing.identityTags, incoming.identityTags),
      conflictTags: _mergeTags(existing.conflictTags, incoming.conflictTags),
      defaultCenters: _mergeByKey(
        existing.defaultCenters,
        incoming.defaultCenters,
        (center) => '${center.x},${center.y}',
      ),
      aliases: _mergeTags(existing.aliases, incoming.aliases),
      recastNotes: _mergeNote(existing.recastNotes, incoming.recastNotes),
    ));
    final updated = [...characters]..[targetIndex] = merged;
    await workspaceService.saveCharacters(updated);
    return StudioAssetCaptureResult(
      kind: StudioAssetCaptureKind.character,
      savedId: merged.id,
      name: merged.name,
      merged: true,
    );
  }

  Future<StudioAssetCaptureResult> _saveOutfit(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    String? nameOverride,
    String? noteOverride,
  }) async {
    final incoming = draft.outfit;
    if (incoming == null) {
      throw const StudioAssetCaptureException(
        'Outfit capture draft does not contain an outfit.',
      );
    }
    final parentId = draft.parentCharacterId?.trim() ?? '';
    if (parentId.isEmpty) {
      throw const StudioAssetCaptureException(
        'Cannot save outfit without a parent character.',
      );
    }

    final characters = await workspaceService.loadCharacters();
    final parentIndex = _indexById(characters, parentId);
    if (parentIndex < 0) {
      throw StudioAssetCaptureException(
        'Cannot save outfit because parent character "$parentId" was not found.',
      );
    }

    final parent = characters[parentIndex];
    final saved = incoming.copyWith(
      name: _firstText([nameOverride, incoming.name, draft.name]),
      note: _firstTextAllowEmpty([noteOverride, incoming.note, draft.note]),
    );
    final outfitTargetIndex = _indexById(parent.outfits, targetId);
    final outfits = [...parent.outfits];
    final merged = outfitTargetIndex >= 0;
    var savedOutfit = saved;
    if (merged) {
      outfits[outfitTargetIndex] =
          _mergeOutfit(outfits[outfitTargetIndex], saved);
    } else {
      savedOutfit =
          saved.copyWith(id: _nonConflictingOutfitId(outfits, saved.id));
      outfits.add(savedOutfit);
    }

    final updatedParent = _manualizedCharacter(
      parent.copyWith(
        outfits: outfits,
        defaultOutfitId: parent.defaultOutfitId ?? savedOutfit.id,
      ),
    );
    final updatedCharacters = [...characters]..[parentIndex] = updatedParent;
    await workspaceService.saveCharacters(updatedCharacters);
    return StudioAssetCaptureResult(
      kind: StudioAssetCaptureKind.outfit,
      savedId: merged ? outfits[outfitTargetIndex].id : savedOutfit.id,
      name: merged ? outfits[outfitTargetIndex].name : savedOutfit.name,
      merged: merged,
    );
  }
}

extension on WorkspaceOutfit {
  WorkspaceOutfit copyWith({
    String? id,
    String? name,
    ViewVariantTexts? tags,
    WorkspaceOutfitPartTags? partTags,
    List<String>? imageRefs,
    String? note,
  }) {
    return WorkspaceOutfit(
      id: id ?? this.id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      partTags: partTags ?? this.partTags,
      imageRefs: imageRefs ?? this.imageRefs,
      note: note ?? this.note,
    );
  }
}

CharacterEntry _manualizedCharacter(CharacterEntry character) {
  if (character.source.type == 'manual') return character;
  return character.copyWith(source: const SourceRef(type: 'manual'));
}

WorkspaceOutfit _mergeOutfit(
    WorkspaceOutfit existing, WorkspaceOutfit incoming) {
  return existing.copyWith(
    tags: _mergeViewVariantTexts(existing.tags, incoming.tags),
    partTags: WorkspaceOutfitPartTags(
      upperBodyTags: _mergeTags(
        existing.partTags.upperBodyTags,
        incoming.partTags.upperBodyTags,
      ),
      upperClothingTags: _mergeTags(
        existing.partTags.upperClothingTags,
        incoming.partTags.upperClothingTags,
      ),
      lowerBodyTags: _mergeTags(
        existing.partTags.lowerBodyTags,
        incoming.partTags.lowerBodyTags,
      ),
      lowerClothingTags: _mergeTags(
        existing.partTags.lowerClothingTags,
        incoming.partTags.lowerClothingTags,
      ),
      weaponTags: _mergeTags(
        existing.partTags.weaponTags,
        incoming.partTags.weaponTags,
      ),
    ),
    imageRefs: _mergeTags(existing.imageRefs, incoming.imageRefs),
    note: _mergeNote(existing.note, incoming.note),
  );
}

ViewVariantTexts _mergeViewVariantTexts(
  ViewVariantTexts existing,
  ViewVariantTexts incoming,
) {
  return ViewVariantTexts(
    frontFull: _joinTags(_mergeTags(
      _splitTags(existing.frontFull),
      _splitTags(incoming.frontFull),
    )),
    frontCowboy: _mergeNullableText(existing.frontCowboy, incoming.frontCowboy),
    frontUpper: _mergeNullableText(existing.frontUpper, incoming.frontUpper),
    frontLower: _mergeNullableText(existing.frontLower, incoming.frontLower),
    backFull: _mergeNullableText(existing.backFull, incoming.backFull),
    backCowboy: _mergeNullableText(existing.backCowboy, incoming.backCowboy),
    backUpper: _mergeNullableText(existing.backUpper, incoming.backUpper),
    backLower: _mergeNullableText(existing.backLower, incoming.backLower),
  );
}

String? _mergeNullableText(String? existing, String? incoming) {
  final merged = _joinTags(_mergeTags(
    _splitTags(existing ?? ''),
    _splitTags(incoming ?? ''),
  ));
  return merged.isEmpty ? null : merged;
}

String _artistCombinedTagSignature(ArtistChain chain) {
  return _tagSignature([...chain.tags, ...chain.styleTags]);
}

String _promptSignature(String prompt) {
  return _tagSignature(_splitTags(prompt));
}

String _tagSignature(Iterable<String> tags) {
  final normalized = tags
      .map(_normalize)
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false)
    ..sort();
  return normalized.join('\n');
}

List<T> _mergeByKey<T>(
  Iterable<T> existing,
  Iterable<T> incoming,
  String Function(T value) keyOf,
) {
  final seen = <String>{};
  final result = <T>[];
  for (final value in [...existing, ...incoming]) {
    final key = _normalize(keyOf(value));
    if (key.isNotEmpty && !seen.add(key)) continue;
    result.add(value);
  }
  return List.unmodifiable(result);
}

List<WorkspaceOutfit> _mergeCharacterOutfits(
  Iterable<WorkspaceOutfit> existing,
  Iterable<WorkspaceOutfit> incoming,
) {
  final result = existing.toList(growable: true);
  for (final incomingOutfit in incoming) {
    final index = _indexOfMatchingOutfit(result, incomingOutfit);
    if (index < 0) {
      result.add(incomingOutfit);
      continue;
    }
    result[index] = _mergeOutfit(result[index], incomingOutfit);
  }
  return List.unmodifiable(result);
}

int _indexOfMatchingOutfit(
  List<WorkspaceOutfit> outfits,
  WorkspaceOutfit incoming,
) {
  final id = _normalize(incoming.id);
  if (id.isNotEmpty) {
    final index = outfits.indexWhere((outfit) => _normalize(outfit.id) == id);
    if (index >= 0) return index;
  }

  final name = _normalize(incoming.name);
  if (name.isNotEmpty) {
    final index =
        outfits.indexWhere((outfit) => _normalize(outfit.name) == name);
    if (index >= 0) return index;
  }

  final frontFull = _promptSignature(incoming.tags.frontFull);
  if (frontFull.isNotEmpty) {
    final index = outfits.indexWhere(
      (outfit) => _promptSignature(outfit.tags.frontFull) == frontFull,
    );
    if (index >= 0) return index;
  }

  return -1;
}

List<String> _mergeTags(Iterable<String> existing, Iterable<String> incoming) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in [...existing, ...incoming]) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) continue;
    if (!seen.add(_normalize(cleaned))) continue;
    result.add(cleaned);
  }
  return List.unmodifiable(result);
}

String _mergeNote(String existing, String incoming) {
  final existingTrimmed = existing.trim();
  final incomingTrimmed = incoming.trim();
  if (existingTrimmed.isEmpty) return incomingTrimmed;
  if (incomingTrimmed.isEmpty) return existingTrimmed;
  if (_normalize(existingTrimmed) == _normalize(incomingTrimmed)) {
    return existingTrimmed;
  }
  return '$existingTrimmed\n$incomingTrimmed';
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

int _indexById<T>(List<T> values, String? id) {
  final normalizedId = _normalize(id ?? '');
  if (normalizedId.isEmpty) return -1;
  return values.indexWhere((value) {
    return switch (value) {
      final ArtistChain chain => _normalize(chain.id) == normalizedId,
      final CharacterEntry character =>
        _normalize(character.id) == normalizedId,
      final WorkspaceOutfit outfit => _normalize(outfit.id) == normalizedId,
      _ => false,
    };
  });
}

bool _containsId(List<WorkspaceOutfit> outfits, String id) {
  return _indexById(outfits, id) >= 0;
}

String _nonConflictingOutfitId(List<WorkspaceOutfit> outfits, String id) {
  if (!_containsId(outfits, id)) return id;
  final base = id.trim().isEmpty ? 'outfit' : id.trim();
  final firstCopy = '$base-copy';
  if (!_containsId(outfits, firstCopy)) return firstCopy;
  var index = 2;
  while (_containsId(outfits, '$firstCopy-$index')) {
    index += 1;
  }
  return '$firstCopy-$index';
}

String _joinTags(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(', ');
}

String _firstText(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return 'Untitled';
}

String _firstTextAllowEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value == null) continue;
    return value.trim();
  }
  return '';
}

String _normalize(String value) => value.trim().toLowerCase();
