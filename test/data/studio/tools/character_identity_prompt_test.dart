import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/tools/character_identity_prompt.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

void main() {
  group('deriveCharacterIdentityPromptExcluding', () {
    test('does not infer identity from frontFull without explicit tags', () {
      const character = CharacterEntry(
        id: 'papyrus',
        name: '莎草',
        traits: ViewVariantTexts(
          frontFull: 'girl, papyrus_(arknights), animal_ears, cat_ears, '
              'green_eyes, orange_hair, tail_ornament',
          frontUpper: 'animal_ears, cat_ears, green_eyes, orange_hair',
          frontLower: 'tail_ornament',
        ),
        outfits: [
          WorkspaceOutfit(
            id: 'pink',
            name: '粉色睡衣',
            tags: ViewVariantTexts(
              frontFull: 'girl, papyrus_(arknights), pink_pajamas, dress',
              frontUpper: 'pink_pajamas, dress',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['pink_pajamas', 'dress'],
            ),
          ),
        ],
      );

      final identity = deriveCharacterIdentityPromptExcluding(
        character,
        const RecastPromptParts(
          upperBody: 'animal_ears, cat_ears, green_eyes, orange_hair',
          lowerBody: 'tail_ornament',
          upperClothing: 'pink_pajamas, dress',
        ),
      );

      expect(identity, isEmpty);
    });

    test('does not infer identity repeated in outfit frontFull', () {
      const character = CharacterEntry(
        id: 'papyrus',
        name: 'Papyrus',
        traits: ViewVariantTexts(
          frontFull: 'girl, papyrus_(arknights), animal ears, cat ears, '
              'green eyes, orange hair, tail ornament',
          frontUpper: 'animal ears, cat ears, green eyes, orange hair',
          frontLower: 'tail ornament',
        ),
        outfits: [
          WorkspaceOutfit(
            id: 'pink',
            name: 'Pink Pajamas',
            tags: ViewVariantTexts(
              frontFull: 'girl, papyrus_(arknights), pink pajamas, dress',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['pink pajamas', 'dress'],
            ),
          ),
        ],
      );

      final identity = deriveCharacterIdentityPromptExcluding(
        character,
        const RecastPromptParts(
          upperBody: 'animal ears, cat ears, green eyes, orange hair',
          lowerBody: 'tail ornament',
          upperClothing: 'pink pajamas, dress',
          lowerClothing: 'girl, papyrus_(arknights), pink pajamas, dress',
        ),
      );

      expect(identity, isEmpty);
    });

    test('keeps explicit anchor tags repeated in outfit full prompt', () {
      const character = CharacterEntry(
        id: 'papyrus',
        name: 'Papyrus',
        traits: ViewVariantTexts(frontFull: 'papyrus_(arknights)'),
        anchorTags: ['papyrus_(arknights)'],
      );

      final identity = deriveCharacterIdentityPromptExcluding(
        character,
        const RecastPromptParts(
          lowerClothing: 'girl, papyrus_(arknights), pink pajamas, dress',
        ),
      );

      expect(identity, 'papyrus_(arknights)');
    });

    test('leaves identity blank when explicit identity tags are missing', () {
      const character = CharacterEntry(
        id: 'pepe',
        name: 'Pepe',
        traits: ViewVariantTexts(
          frontFull: 'girl, 2::loli::, pepe_(arknights), cat_ears, '
              'long_hair, cat_tail, animal_ear_hood, black_jacket',
          frontUpper: 'cat_ears, long_hair',
          frontLower: 'cat_tail',
        ),
        outfits: [
          WorkspaceOutfit(
            id: 'default',
            name: 'Default',
            tags: ViewVariantTexts(frontFull: 'animal_ear_hood, black_jacket'),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['animal_ear_hood', 'black_jacket'],
            ),
          ),
        ],
      );

      final identity = deriveCharacterIdentityPromptExcluding(
        character,
        const RecastPromptParts(
          upperBody: 'cat_ears, long_hair',
          lowerBody: 'cat_tail',
          upperClothing: 'animal_ear_hood, black_jacket',
        ),
      );

      expect(identity, isEmpty);
    });

    test('uses explicit identity tags only', () {
      const character = CharacterEntry(
        id: 'custom',
        name: 'Custom',
        traits: ViewVariantTexts(frontFull: 'green_eyes, long_hair'),
        anchorTags: ['custom_hero'],
        identityTags: ['green_eyes'],
      );

      final identity = deriveCharacterIdentityPromptExcluding(
        character,
        const RecastPromptParts(upperBody: 'green_eyes'),
      );

      expect(identity, 'custom_hero');
    });

    test('drops skin aliases when the base character anchor is present', () {
      const character = CharacterEntry(
        id: 'papyrus',
        name: 'Papyrus',
        traits: ViewVariantTexts(frontFull: 'papyrus_(arknights)'),
        anchorTags: [
          'papyrus_(arknights)',
          'papyrus_(the_next_side_quest)_(arknights)',
        ],
        identityTags: [
          'papyrus_(arknights)',
          'papyrus_(the_next_side_quest)_(arknights)',
        ],
      );

      final identity = deriveCharacterIdentityPromptExcluding(
        character,
        const RecastPromptParts(),
      );

      expect(identity, 'papyrus_(arknights)');
    });
  });
}
