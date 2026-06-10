import 'dart:math';
import 'dart:typed_data';

import 'package:nai_casrand/core/constants/defaults.dart';
import 'package:nai_casrand/data/models/generation_size.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/studio/tools/outfit_identity_prompt.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

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

  Future<String> generateArtistChainPreview(String id) async {
    final chains = await workspaceService.loadArtistChains();
    final chainIndex = _indexById(chains, id);
    if (chainIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Artist chain "$id" was not found.',
      );
    }

    final size = _randomSize();
    final chain = chains[chainIndex];
    final prompt = _artistChainPrompt(chain);
    final outputPath = await _generateAndSave(
      prompt: prompt,
      size: size,
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

  Future<String> generateCharacterPreview(String id) async {
    final characters = await workspaceService.loadCharacters();
    final characterIndex = _indexById(characters, id);
    if (characterIndex < 0) {
      throw StudioAssetPreviewGenerationException(
        'Character "$id" was not found.',
      );
    }

    final character = characters[characterIndex];
    final size = _randomSize();
    final prompt = _characterPrompt(character);
    final outputPath = await _generateAndSave(
      prompt: prompt,
      size: size,
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
      String characterId, String outfitId) async {
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
    final size = _randomSize();
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

  GenerationSize _randomSize() {
    final index = _boundedRandomInt(_previewSizes.length);
    return _previewSizes[index];
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

  String _artistChainPrompt(ArtistChain chain) {
    return _joinPromptParts([
      _qualityTerms,
      chain.prompt,
      ...chain.tags,
      ...chain.styleTags,
      ..._artistChainPreviewCharacterTerms,
      'upper body',
      'waist-up portrait',
      'close-up character portrait',
      'character fills most of the frame',
      'character focus',
      'simple soft background',
    ]);
  }

  String _characterPrompt(CharacterEntry character) {
    return _joinPromptParts([
      _qualityTerms,
      character.name,
      ..._characterTerms(character),
      'pure white background',
      'simple white backdrop',
      'clean character reference sheet',
    ]);
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
        yield part;
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
    yield character.traits.frontFull;
    yield* character.identityTags;
    yield* character.anchorTags;
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
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(RegExp(r'[,\n]'))
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

const _artistChainPreviewCharacterTerms = [
  'suzuran_(arknights)',
  '1girl',
  'solo',
  'single character',
  'one person only',
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
