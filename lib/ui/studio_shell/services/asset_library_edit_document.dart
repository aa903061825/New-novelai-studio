import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

enum AssetLibraryCharacterPromptField {
  identity,
  upperBody,
  lowerBody,
}

enum AssetLibraryOutfitPromptField {
  full,
  upperBody,
  upperClothing,
  lowerBody,
  lowerClothing,
}

class AssetLibraryEditDocument {
  const AssetLibraryEditDocument._();

  static CharacterEntry updateCharacterPrompt(
    CharacterEntry character,
    String prompt,
  ) {
    final trimmed = prompt.trim();
    return manualizedCharacter(
      character.copyWith(
        traits: ViewVariantTexts(
          frontFull: trimmed,
          frontCowboy: character.traits.frontCowboy,
          frontUpper: character.traits.frontUpper,
          frontLower: character.traits.frontLower,
          backFull: character.traits.backFull,
          backCowboy: character.traits.backCowboy,
          backUpper: character.traits.backUpper,
          backLower: character.traits.backLower,
        ),
        identityTags: identityPromptTags(trimmed),
      ),
    );
  }

  static CharacterEntry updateCharacterPromptField(
    CharacterEntry character,
    AssetLibraryCharacterPromptField field,
    String prompt,
  ) {
    final trimmed = prompt.trim();
    final traits = character.traits;
    final updatedTraits = switch (field) {
      AssetLibraryCharacterPromptField.identity => ViewVariantTexts(
          frontFull: trimmed,
          frontCowboy: traits.frontCowboy,
          frontUpper: traits.frontUpper,
          frontLower: traits.frontLower,
          backFull: traits.backFull,
          backCowboy: traits.backCowboy,
          backUpper: traits.backUpper,
          backLower: traits.backLower,
        ),
      AssetLibraryCharacterPromptField.upperBody => ViewVariantTexts(
          frontFull: traits.frontFull,
          frontCowboy: traits.frontCowboy,
          frontUpper: _blankToNull(trimmed),
          frontLower: traits.frontLower,
          backFull: traits.backFull,
          backCowboy: traits.backCowboy,
          backUpper: traits.backUpper,
          backLower: traits.backLower,
        ),
      AssetLibraryCharacterPromptField.lowerBody => ViewVariantTexts(
          frontFull: traits.frontFull,
          frontCowboy: traits.frontCowboy,
          frontUpper: traits.frontUpper,
          frontLower: _blankToNull(trimmed),
          backFull: traits.backFull,
          backCowboy: traits.backCowboy,
          backUpper: traits.backUpper,
          backLower: traits.backLower,
        ),
    };
    return manualizedCharacter(
      character.copyWith(
        traits: updatedTraits,
        identityTags: field == AssetLibraryCharacterPromptField.identity
            ? identityPromptTags(trimmed)
            : character.identityTags,
      ),
    );
  }

  static WorkspaceOutfit updateOutfitPrompt(
    WorkspaceOutfit outfit,
    String prompt,
  ) {
    final trimmed = prompt.trim();
    return WorkspaceOutfit(
      id: outfit.id,
      name: outfit.name,
      tags: ViewVariantTexts(
        frontFull: trimmed,
        frontCowboy: outfit.tags.frontCowboy,
        frontUpper: outfit.tags.frontUpper,
        frontLower: outfit.tags.frontLower,
        backFull: outfit.tags.backFull,
        backCowboy: outfit.tags.backCowboy,
        backUpper: outfit.tags.backUpper,
        backLower: outfit.tags.backLower,
      ),
      partTags: outfit.partTags,
      imageRefs: outfit.imageRefs,
      negativePrompt: outfit.negativePrompt,
      note: outfit.note,
    );
  }

  static WorkspaceOutfit updateOutfitPromptField(
    WorkspaceOutfit outfit,
    AssetLibraryOutfitPromptField field,
    String prompt,
  ) {
    final trimmed = prompt.trim();
    final tags = promptTagValuesFromValue(trimmed);
    final currentTags = outfit.tags;
    final currentPartTags = outfit.partTags;
    final fallbackUpperBodyTags = currentPartTags.isEmpty
        ? const <String>[]
        : currentPartTags.upperBodyTags;
    final fallbackUpperClothingTags = currentPartTags.isEmpty
        ? promptTagValuesFromValue(currentTags.frontFull)
        : currentPartTags.upperClothingTags;
    final fallbackLowerBodyTags = currentPartTags.isEmpty
        ? const <String>[]
        : currentPartTags.lowerBodyTags;
    final fallbackLowerClothingTags = currentPartTags.isEmpty
        ? const <String>[]
        : currentPartTags.lowerClothingTags;
    final updatedViewTags = switch (field) {
      AssetLibraryOutfitPromptField.full => ViewVariantTexts(
          frontFull: trimmed,
          frontCowboy: currentTags.frontCowboy,
          frontUpper: currentTags.frontUpper,
          frontLower: currentTags.frontLower,
          backFull: currentTags.backFull,
          backCowboy: currentTags.backCowboy,
          backUpper: currentTags.backUpper,
          backLower: currentTags.backLower,
        ),
      AssetLibraryOutfitPromptField.upperClothing => ViewVariantTexts(
          frontFull: currentTags.frontFull,
          frontCowboy: currentTags.frontCowboy,
          frontUpper: _blankToNull(trimmed),
          frontLower: currentTags.frontLower,
          backFull: currentTags.backFull,
          backCowboy: currentTags.backCowboy,
          backUpper: currentTags.backUpper,
          backLower: currentTags.backLower,
        ),
      AssetLibraryOutfitPromptField.lowerClothing => ViewVariantTexts(
          frontFull: currentTags.frontFull,
          frontCowboy: currentTags.frontCowboy,
          frontUpper: currentTags.frontUpper,
          frontLower: _blankToNull(trimmed),
          backFull: currentTags.backFull,
          backCowboy: currentTags.backCowboy,
          backUpper: currentTags.backUpper,
          backLower: currentTags.backLower,
        ),
      _ => currentTags,
    };
    final updatedPartTags = switch (field) {
      AssetLibraryOutfitPromptField.upperBody => WorkspaceOutfitPartTags(
          upperBodyTags: tags,
          upperClothingTags: fallbackUpperClothingTags,
          lowerBodyTags: fallbackLowerBodyTags,
          lowerClothingTags: fallbackLowerClothingTags,
        ),
      AssetLibraryOutfitPromptField.upperClothing => WorkspaceOutfitPartTags(
          upperBodyTags: fallbackUpperBodyTags,
          upperClothingTags: tags,
          lowerBodyTags: fallbackLowerBodyTags,
          lowerClothingTags: fallbackLowerClothingTags,
        ),
      AssetLibraryOutfitPromptField.lowerBody => WorkspaceOutfitPartTags(
          upperBodyTags: fallbackUpperBodyTags,
          upperClothingTags: fallbackUpperClothingTags,
          lowerBodyTags: tags,
          lowerClothingTags: fallbackLowerClothingTags,
        ),
      AssetLibraryOutfitPromptField.lowerClothing => WorkspaceOutfitPartTags(
          upperBodyTags: fallbackUpperBodyTags,
          upperClothingTags: fallbackUpperClothingTags,
          lowerBodyTags: fallbackLowerBodyTags,
          lowerClothingTags: tags,
        ),
      _ => currentPartTags,
    };
    final derivedFullPrompt = promptFromTags(outfitPartTags(updatedPartTags));
    final normalizedViewTags = field == AssetLibraryOutfitPromptField.full
        ? updatedViewTags
        : ViewVariantTexts(
            frontFull: derivedFullPrompt.isEmpty
                ? currentTags.frontFull
                : derivedFullPrompt,
            frontCowboy: updatedViewTags.frontCowboy,
            frontUpper: updatedViewTags.frontUpper,
            frontLower: updatedViewTags.frontLower,
            backFull: updatedViewTags.backFull,
            backCowboy: updatedViewTags.backCowboy,
            backUpper: updatedViewTags.backUpper,
            backLower: updatedViewTags.backLower,
          );
    return WorkspaceOutfit(
      id: outfit.id,
      name: outfit.name,
      tags: normalizedViewTags,
      partTags: updatedPartTags,
      imageRefs: outfit.imageRefs,
      negativePrompt: outfit.negativePrompt,
      note: outfit.note,
    );
  }

  static CharacterEntry manualizedCharacter(CharacterEntry character) {
    if (character.source.type == 'manual') return character;
    return character.copyWith(source: const SourceRef(type: 'manual'));
  }

  static List<String> identityPromptTags(String prompt) {
    return _promptTags(prompt)
        .where((tag) => !_isCharacterCountTag(tag))
        .toList(growable: false);
  }

  static List<String> promptTagValuesFromValue(String value) {
    return PromptTagProcessor.analyzeWorkshopTags(value)
        .map(_promptAnalysisValue)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  static String promptFromTags(Iterable<String> tags) {
    final seen = <String>{};
    final result = <String>[];
    for (final tag in PromptTagProcessor.analyzeWorkshopTags(tags.join(', '))) {
      final display = tag.displayText.trim();
      final key = PromptTagProcessor.normalizeMatchKey(display);
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      result.add(_promptAnalysisValue(tag));
    }
    return result.join(', ');
  }

  static Iterable<String> outfitPartTags(
    WorkspaceOutfitPartTags partTags,
  ) sync* {
    yield* partTags.upperBodyTags;
    yield* partTags.upperClothingTags;
    yield* partTags.lowerBodyTags;
    yield* partTags.lowerClothingTags;
    yield* partTags.weaponTags;
  }
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _promptTags(String prompt) {
  return prompt
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
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

String _promptAnalysisValue(WorkshopTagAnalysis tag) {
  final raw = tag.text.trim();
  final weight = tag.weight;
  if (weight == null ||
      PromptTagProcessor.hasCompleteNonInlineWeightSyntax(raw)) {
    return raw;
  }
  final display = tag.displayText.trim();
  if (display.isEmpty) return raw;
  return PromptTagProcessor.formatInlineWeightTag(display, weight);
}
