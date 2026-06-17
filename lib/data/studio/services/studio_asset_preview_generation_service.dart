import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/tools/outfit_identity_prompt.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

typedef StudioPreviewImageRequest = Future<Uint8List> Function(
  Map<String, dynamic> payload,
);
typedef StudioPreviewImageSave = Future<String> Function(
  Uint8List bytes,
  String fileName,
);
typedef StudioPreviewRandomInt = int Function(int max);
typedef StudioPreviewClock = DateTime Function();

class StudioAssetPreviewGenerationException implements Exception {
  final String message;

  const StudioAssetPreviewGenerationException(this.message);

  @override
  String toString() => 'StudioAssetPreviewGenerationException: $message';
}

enum StudioPreviewCustomPromptMode { append, replace }

class StudioAssetPreviewGenerationOptions {
  final String? artistChainId;
  final String customPrompt;
  final StudioPreviewCustomPromptMode customPromptMode;
  final GenerationSize? size;

  const StudioAssetPreviewGenerationOptions({
    this.artistChainId,
    this.customPrompt = '',
    this.customPromptMode = StudioPreviewCustomPromptMode.append,
    this.size,
  });

  String get trimmedCustomPrompt => customPrompt.trim();
}

class StudioAssetPreviewGenerationService {
  static const model = 'nai-diffusion-4-5-full';
  static const _seedMaxExclusive = 1 << 32;
  static const _previewSizes = [
    GenerationSize(width: 832, height: 1216),
    GenerationSize(width: 1024, height: 1024),
    GenerationSize(width: 1216, height: 832),
  ];

  final WorkspaceService workspaceService;
  final StudioPreviewImageRequest requestImage;
  final StudioPreviewImageSave saveImage;
  final StudioPreviewRandomInt randomInt;
  final StudioPreviewClock now;

  StudioAssetPreviewGenerationService({
    required this.workspaceService,
    required this.requestImage,
    required this.saveImage,
    StudioPreviewRandomInt? randomInt,
    StudioPreviewClock? now,
  })  : randomInt = randomInt ?? Random().nextInt,
        now = now ?? DateTime.now;

  Future<String> generateArtistChainPreview(
    String id, {
    StudioAssetPreviewGenerationOptions options =
        const StudioAssetPreviewGenerationOptions(),
  }) async {
    final chains = await workspaceService.loadArtistChains();
    final chainIndex = _indexById(chains, id);
    if (chainIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Artist chain "$id" was not found.',
      );
    }

    final size = _sizeFromOptions(options);
    final chain = chains[chainIndex];
    final character = _randomCharacter(await workspaceService.loadCharacters());
    final scenePrompt = await _randomScenePrompt();
    final prompt = _artistChainPrompt(
      chain,
      character: character,
      scenePrompt: scenePrompt,
      options: options,
    );
    final outputPath = await _generateAndSave(
      prompt: prompt,
      size: size,
      negativePrompt: _artistChainNegativePrompt(chain),
      vibeRefs: chain.vibeRefs,
      fileNamePrefix:
          'asset-preview-artist-chain-${_safeFileSegment(chains[chainIndex].id)}',
    );

    final freshChains = await workspaceService.loadArtistChains();
    final freshChainIndex = _indexById(freshChains, id);
    if (freshChainIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Artist chain "$id" was not found after preview generation.',
      );
    }
    final updatedChain = freshChains[freshChainIndex].copyWith(
      imageRefs: _appendUnique(
        freshChains[freshChainIndex].imageRefs,
        outputPath,
      ),
    );
    await workspaceService.saveArtistChains(
      [...freshChains]..[freshChainIndex] = updatedChain,
    );
    return outputPath;
  }

  Future<String> generateCharacterPreview(
    String id, {
    StudioAssetPreviewGenerationOptions options =
        const StudioAssetPreviewGenerationOptions(),
  }) async {
    final characters = await workspaceService.loadCharacters();
    final characterIndex = _indexById(characters, id);
    if (characterIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Character "$id" was not found.',
      );
    }

    final character = characters[characterIndex];
    final size = _sizeFromOptions(options);
    final artistChain = await _artistChainForCharacterPreview(options);
    final prompt = _characterPrompt(
      character,
      artistChain: artistChain,
      options: options,
    );
    final outputPath = await _generateAndSave(
      prompt: prompt,
      size: size,
      negativePrompt: artistChain == null
          ? defaultUC
          : _artistChainNegativePrompt(artistChain),
      vibeRefs: artistChain?.vibeRefs ?? const [],
      fileNamePrefix:
          'asset-preview-character-${_safeFileSegment(character.id)}',
    );

    final freshCharacters = await workspaceService.loadCharacters();
    final freshCharacterIndex = _indexById(freshCharacters, id);
    if (freshCharacterIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Character "$id" was not found after preview generation.',
      );
    }
    final updatedCharacter = freshCharacters[freshCharacterIndex].copyWith(
      imageRefs: _appendUnique(
        freshCharacters[freshCharacterIndex].imageRefs,
        outputPath,
      ),
    );
    await workspaceService.saveCharacters(
      [...freshCharacters]..[freshCharacterIndex] = updatedCharacter,
    );
    return outputPath;
  }

  Future<String> generateOutfitPreview(
    String characterId,
    String outfitId, {
    StudioAssetPreviewGenerationOptions options =
        const StudioAssetPreviewGenerationOptions(),
  }) async {
    final characters = await workspaceService.loadCharacters();
    final characterIndex = _indexById(characters, characterId);
    if (characterIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Character "$characterId" was not found.',
      );
    }
    final character = characters[characterIndex];
    final outfitIndex = _outfitIndexById(character.outfits, outfitId);
    if (outfitIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Outfit "$outfitId" was not found for character "$characterId".',
      );
    }

    final outfit = character.outfits[outfitIndex];
    final size = _sizeFromOptions(options);
    final prompt = _outfitPrompt(character, outfit);
    final outputPath = await _generateAndSave(
      prompt: prompt,
      size: size,
      negativePrompt: _outfitNegativePrompt(outfit),
      fileNamePrefix:
          'asset-preview-outfit-${_safeFileSegment(character.id)}-${_safeFileSegment(outfit.id)}',
    );

    final freshCharacters = await workspaceService.loadCharacters();
    final freshCharacterIndex = _indexById(freshCharacters, characterId);
    if (freshCharacterIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Character "$characterId" was not found after preview generation.',
      );
    }
    final freshCharacter = freshCharacters[freshCharacterIndex];
    final freshOutfitIndex = _outfitIndexById(freshCharacter.outfits, outfitId);
    if (freshOutfitIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Outfit "$outfitId" was not found after preview generation.',
      );
    }
    final freshOutfit = freshCharacter.outfits[freshOutfitIndex];
    final updatedOutfit = _withOutfitImageRefs(
      freshOutfit,
      _appendUnique(freshOutfit.imageRefs, outputPath),
    );
    final updatedOutfits = [...freshCharacter.outfits]..[freshOutfitIndex] =
        updatedOutfit;
    final updatedCharacter = freshCharacter.copyWith(outfits: updatedOutfits);
    await workspaceService.saveCharacters(
      [...freshCharacters]..[freshCharacterIndex] = updatedCharacter,
    );
    return outputPath;
  }

  Future<void> discardArtistChainPreview(
    String id,
    String previewPath,
  ) async {
    final chains = await workspaceService.loadArtistChains();
    final chainIndex = _indexById(chains, id);
    if (chainIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Artist chain "$id" was not found while discarding preview.',
      );
    }
    final chain = chains[chainIndex];
    final updatedChain = chain.copyWith(
      imageRefs: _removePreviewRef(chain.imageRefs, previewPath),
    );
    await workspaceService.saveArtistChains(
      [...chains]..[chainIndex] = updatedChain,
    );
    _deleteLocalPreviewFile(previewPath);
  }

  Future<void> discardCharacterPreview(
    String id,
    String previewPath,
  ) async {
    final characters = await workspaceService.loadCharacters();
    final characterIndex = _indexById(characters, id);
    if (characterIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Character "$id" was not found while discarding preview.',
      );
    }
    final character = characters[characterIndex];
    final updatedCharacter = character.copyWith(
      imageRefs: _removePreviewRef(character.imageRefs, previewPath),
    );
    await workspaceService.saveCharacters(
      [...characters]..[characterIndex] = updatedCharacter,
    );
    _deleteLocalPreviewFile(previewPath);
  }

  Future<void> discardOutfitPreview(
    String characterId,
    String outfitId,
    String previewPath,
  ) async {
    final characters = await workspaceService.loadCharacters();
    final characterIndex = _indexById(characters, characterId);
    if (characterIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Character "$characterId" was not found while discarding preview.',
      );
    }
    final character = characters[characterIndex];
    final outfitIndex = _outfitIndexById(character.outfits, outfitId);
    if (outfitIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Outfit "$outfitId" was not found while discarding preview.',
      );
    }
    final outfits = [...character.outfits];
    final outfit = outfits[outfitIndex];
    outfits[outfitIndex] = _withOutfitImageRefs(
      outfit,
      _removePreviewRef(outfit.imageRefs, previewPath),
    );
    await workspaceService.saveCharacters(
      [...characters]..[characterIndex] = character.copyWith(outfits: outfits),
    );
    _deleteLocalPreviewFile(previewPath);
  }

  GenerationSize _randomSize() {
    final index = _boundedRandomInt(_previewSizes.length);
    return _previewSizes[index];
  }

  GenerationSize _sizeFromOptions(StudioAssetPreviewGenerationOptions options) {
    return options.size ?? _randomSize();
  }

  Future<ArtistChain?> _artistChainForCharacterPreview(
    StudioAssetPreviewGenerationOptions options,
  ) async {
    final chains = await workspaceService.loadArtistChains();
    final selectedId = options.artistChainId?.trim();
    if (selectedId != null && selectedId.isNotEmpty) {
      final selectedIndex = _indexById(chains, selectedId);
      if (selectedIndex < 0) {
        throw StudioAssetPreviewGenerationException(
          'Artist chain "$selectedId" was not found.',
        );
      }
      return chains[selectedIndex];
    }
    if (chains.isEmpty) return null;
    return chains[_boundedRandomInt(chains.length)];
  }

  CharacterEntry? _randomCharacter(List<CharacterEntry> characters) {
    if (characters.isEmpty) return null;
    return characters[_boundedRandomInt(characters.length)];
  }

  Future<String> _randomScenePrompt() async {
    final inspirations = await workspaceService.loadInspirations();
    final sceneEntries = inspirations
        .where(
          (entry) =>
              StudioAssetCatalogService.isCodexSourceType(entry.source.type) &&
              StudioLegacyCodexCategories.matches(
                entry,
                StudioLegacyCodexCategories.scene.key,
              ),
        )
        .toList(growable: false);
    if (sceneEntries.isEmpty) return _fallbackScenePrompt;
    final entry = sceneEntries[_boundedRandomInt(sceneEntries.length)];
    final prompt = entry.prompt.trim();
    if (prompt.isNotEmpty) return prompt;
    return entry.name.trim();
  }

  Future<String> _generateAndSave({
    required String prompt,
    required GenerationSize size,
    required String fileNamePrefix,
    String negativePrompt = defaultUC,
    List<WorkspaceVibeReference> vibeRefs = const [],
  }) async {
    final payload = _payload(
      prompt: prompt,
      size: size,
      negativePrompt: negativePrompt,
      vibeRefs: vibeRefs,
    );
    final bytes = await requestImage(payload);
    return saveImage(bytes, '$fileNamePrefix-${_timestamp(now())}.png');
  }

  Map<String, dynamic> _payload({
    required String prompt,
    required GenerationSize size,
    required String negativePrompt,
    List<WorkspaceVibeReference> vibeRefs = const [],
  }) {
    final seed = _boundedRandomInt(_seedMaxExclusive);
    final parameters = ParamConfig(
      model: model,
      sizes: [size],
      randomSeed: false,
      seed: seed,
      negativePrompt: negativePrompt,
    ).getPayload();
    parameters['v4_prompt'] = _v4Prompt(prompt);
    parameters['v4_negative_prompt'] = _v4Prompt(negativePrompt);
    final activeVibes = vibeRefs
        .where((vibe) => vibe.vibeB64.trim().isNotEmpty)
        .toList(growable: false);
    if (activeVibes.isNotEmpty) {
      parameters['reference_image_multiple'] = [
        for (final vibe in activeVibes) vibe.vibeB64,
      ];
      parameters['reference_strength_multiple'] = [
        for (final vibe in activeVibes) vibe.referenceStrength,
      ];
      parameters['reference_information_extracted_multiple'] = [
        for (final vibe in activeVibes) vibe.infoExtracted,
      ];
    }

    return {
      'input': prompt,
      'model': model,
      'action': 'generate',
      'parameters': parameters,
    };
  }

  Map<String, dynamic> _v4Prompt(String baseCaption) {
    return {
      'caption': {
        'base_caption': baseCaption,
        'char_captions': const [],
      },
      'use_coords': false,
      'use_order': true,
    };
  }

  String _applyCustomPrompt(
    String template,
    StudioAssetPreviewGenerationOptions options,
  ) {
    final custom = options.trimmedCustomPrompt;
    if (custom.isEmpty) return template;
    if (options.customPromptMode == StudioPreviewCustomPromptMode.replace) {
      return custom;
    }
    return _joinPromptParts([template, custom]);
  }

  Iterable<String> _artistChainTerms(ArtistChain chain) sync* {
    if (chain.artists.isNotEmpty) {
      for (final artist in chain.artists) {
        yield _artistEntryTag(artist);
      }
    } else {
      yield* chain.tags;
    }
    yield chain.prompt;
    yield* chain.styleTags;
    for (final tag in chain.styleHintsWeighted) {
      yield _weightedTag(tag);
    }
  }

  String _artistChainNegativePrompt(ArtistChain chain) {
    return _joinPromptParts([
      defaultUC,
      for (final tag in chain.globalNegatives) _weightedTag(tag),
    ]);
  }

  String _artistEntryTag(ArtistEntry artist) {
    final tag = '${artist.prefix}${artist.name}';
    return artist.weight == 1
        ? tag
        : PromptTagProcessor.formatInlineWeightTag(tag, artist.weight);
  }

  String _weightedTag(WorkspaceWeightedTag tag) {
    return tag.weight == 1
        ? tag.tag
        : PromptTagProcessor.formatInlineWeightTag(tag.tag, tag.weight);
  }

  String _artistChainPrompt(
    ArtistChain chain, {
    required CharacterEntry? character,
    required String scenePrompt,
    required StudioAssetPreviewGenerationOptions options,
  }) {
    final template = _joinPromptParts([
      ..._artistChainTerms(chain),
      _qualityTerms,
      if (character != null) character.name,
      if (character != null) ..._characterTerms(character),
      if (character == null) ..._fallbackArtistChainPreviewCharacterTerms,
      '1girl',
      'solo',
      scenePrompt.trim().isEmpty ? _fallbackScenePrompt : scenePrompt,
      'character focus',
      'clean readable pose',
      'appealing character preview',
      'no text',
      'no watermark',
    ]);
    return _applyCustomPrompt(template, options);
  }

  String _characterPrompt(
    CharacterEntry character, {
    required ArtistChain? artistChain,
    required StudioAssetPreviewGenerationOptions options,
  }) {
    final template = _joinPromptParts([
      if (artistChain != null) ..._artistChainTerms(artistChain),
      _qualityTerms,
      character.name,
      ..._characterTerms(character),
      '1girl',
      'solo',
      'solid color background',
      'simple plain background',
      'pure white background',
      'clean character reference sheet',
    ]);
    return _applyCustomPrompt(template, options);
  }

  String _outfitPrompt(CharacterEntry character, WorkspaceOutfit outfit) {
    final hasOutfitIdentity = hasOutfitIdentityPrompt(outfit);
    return _joinPromptParts([
      _qualityTerms,
      if (!hasOutfitIdentity) character.name,
      if (!hasOutfitIdentity) ..._characterTermsForOutfit(character),
      if (hasOutfitIdentity) deriveOutfitIdentityPrompt(outfit),
      ..._outfitTerms(outfit),
      'pure white background',
      'simple white backdrop',
      'clean outfit reference image',
      'full body',
      'head-to-toe',
      'feet visible',
      'single character',
    ]);
  }

  Iterable<String> _characterTermsForOutfit(CharacterEntry character) sync* {
    final normalizeSkinVariants =
        _shouldNormalizeCharacterSkinVariants(character);
    for (final tag in [
      character.name,
      character.traits.frontFull,
      character.traits.frontUpper ?? '',
      character.traits.frontLower ?? '',
      ...character.identityTags,
      ...character.anchorTags,
    ]) {
      for (final part in _splitPrompt(tag)) {
        if (_isOutfitSpecificIdentityLeak(part)) continue;
        yield normalizeSkinVariants
            ? _baseCharacterIdentityForSkinVariant(part)
            : part;
      }
    }
  }

  bool _isOutfitSpecificIdentityLeak(String tag) {
    return RegExp(
      r'(^|[_\s])(hood|hooded|hoodie|wearing_hood|hood_over_head|hood_up|jacket|coat|dress|skirt|shorts|shirt|robe|kimono|swimsuit|bikini|shoes|boots|sandals|socks)($|[_\s])',
      caseSensitive: false,
    ).hasMatch(tag);
  }

  Iterable<String> _characterTerms(CharacterEntry character) sync* {
    final normalizeSkinVariants =
        _shouldNormalizeCharacterSkinVariants(character);
    yield* _characterTermParts(
      character.traits.frontFull,
      normalizeSkinVariants: normalizeSkinVariants,
    );
    for (final tag in character.identityTags) {
      yield* _characterTermParts(
        tag,
        normalizeSkinVariants: normalizeSkinVariants,
      );
    }
    for (final tag in character.anchorTags) {
      yield* _characterTermParts(
        tag,
        normalizeSkinVariants: normalizeSkinVariants,
      );
    }
  }

  bool _shouldNormalizeCharacterSkinVariants(CharacterEntry character) {
    return character.source.type == 'legacy_artist_workbook';
  }

  Iterable<String> _characterTermParts(
    String value, {
    required bool normalizeSkinVariants,
  }) sync* {
    for (final part in _splitPrompt(value)) {
      yield normalizeSkinVariants
          ? _baseCharacterIdentityForSkinVariant(part)
          : part;
    }
  }

  String _baseCharacterIdentityForSkinVariant(String tag) {
    final descriptor = PromptTagProcessor.describeWorkshopTag(tag);
    final value = descriptor.displayText.trim();
    if (value.isEmpty || value.contains(':')) return tag;
    final match = RegExp(r'^(.+?)([_\s])(?:\([^()]+\)[_\s])+\(([^()]+)\)$')
        .firstMatch(value);
    if (match == null) return tag;
    final baseName = match.group(1)?.trim();
    final series = match.group(3)?.trim();
    if (baseName == null ||
        baseName.isEmpty ||
        series == null ||
        series.isEmpty) {
      return tag;
    }
    final separator = match.group(2) == '_' ? '_' : ' ';
    final baseTag = '$baseName$separator($series)';
    final weight = descriptor.weight;
    return weight == null
        ? baseTag
        : PromptTagProcessor.formatInlineWeightTag(baseTag, weight);
  }

  Iterable<String> _outfitTerms(WorkspaceOutfit outfit) sync* {
    yield outfit.name;
    if (outfit.tags.frontUpper != null) yield outfit.tags.frontUpper!;
    if (outfit.tags.frontLower != null) yield outfit.tags.frontLower!;
    yield* outfit.partTags.upperBodyTags;
    yield* outfit.partTags.upperClothingTags;
    yield* outfit.partTags.lowerBodyTags;
    yield* outfit.partTags.lowerClothingTags;
    yield* outfit.partTags.weaponTags;
  }

  WorkspaceOutfit _withOutfitImageRefs(
    WorkspaceOutfit outfit,
    List<String> imageRefs,
  ) {
    return WorkspaceOutfit(
      id: outfit.id,
      name: outfit.name,
      tags: outfit.tags,
      partTags: outfit.partTags,
      imageRefs: imageRefs,
      negativePrompt: outfit.negativePrompt,
      note: outfit.note,
    );
  }

  String _outfitNegativePrompt(WorkspaceOutfit outfit) {
    return _joinPromptParts([defaultUC, outfit.negativePrompt]);
  }

  List<String> _appendUnique(List<String> refs, String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return List.unmodifiable(refs);
    if (refs.any((ref) => ref.trim() == trimmed)) {
      return List.unmodifiable(refs);
    }
    return List.unmodifiable([...refs, trimmed]);
  }

  List<String> _removePreviewRef(List<String> refs, String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return List.unmodifiable(refs);
    return List.unmodifiable([
      for (final ref in refs)
        if (ref.trim() != trimmed) ref,
    ]);
  }

  void _deleteLocalPreviewFile(String previewPath) {
    if (previewPath.trim().isEmpty) return;
    try {
      final file = File(previewPath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Catalog state is authoritative; file cleanup is best effort.
    }
  }

  int _boundedRandomInt(int maxExclusive) {
    if (maxExclusive <= 1) return 0;
    final value = randomInt(maxExclusive);
    if (value < 0) return 0;
    if (value >= maxExclusive) return maxExclusive - 1;
    return value;
  }

  String _joinPromptParts(Iterable<String> parts) {
    final seen = <String>{};
    final result = <String>[];
    for (final part in parts) {
      for (final tag in _splitPrompt(part)) {
        final normalized = tag.toLowerCase();
        if (!seen.add(normalized)) continue;
        result.add(tag);
      }
    }
    return result.join(', ');
  }

  Iterable<String> _splitPrompt(String value) {
    return PromptTagProcessor.splitWorkshopTags(value)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty);
  }

  int _indexById<T>(List<T> values, String id) {
    final normalizedId = id.trim().toLowerCase();
    return values.indexWhere((value) {
      return switch (value) {
        final ArtistChain chain =>
          chain.id.trim().toLowerCase() == normalizedId,
        final CharacterEntry character =>
          character.id.trim().toLowerCase() == normalizedId,
        _ => false,
      };
    });
  }

  int _outfitIndexById(List<WorkspaceOutfit> outfits, String id) {
    final normalizedId = id.trim().toLowerCase();
    return outfits.indexWhere(
      (outfit) => outfit.id.trim().toLowerCase() == normalizedId,
    );
  }

  String _timestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  String _safeFileSegment(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'asset' : sanitized;
  }
}

const _qualityTerms = 'masterpiece, best quality, very aesthetic, highres';

const _fallbackScenePrompt =
    'simple soft background, plain light background, no props';

const _fallbackArtistChainPreviewCharacterTerms = [
  'suzuran_(arknights)',
  '1girl',
  'solo',
  'fox girl',
  'fox ears',
  'fox tail',
  'blonde hair',
  'long hair',
  'green eyes',
  'looking at viewer',
  'upper body',
  'waist-up portrait',
  'close-up character portrait',
  'character fills most of the frame',
  'centered character composition',
];
