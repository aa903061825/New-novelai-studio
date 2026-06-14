import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/outfit_identity_prompt.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

void main() {
  group('deriveOutfitIdentityPrompt', () {
    test('uses explicit skin identity from non-default outfit frontFull', () {
      const outfit = WorkspaceOutfit(
        id: 'skin',
        name: 'Nuit of the Nightsky',
        tags: ViewVariantTexts(
          frontFull: 'pepe_(arknights), '
              'pepe_(nuit_of_the_nightsky)_(arknights), white dress, skirt',
        ),
      );

      expect(
        deriveOutfitIdentityPrompt(outfit),
        'pepe_(arknights), pepe_(nuit_of_the_nightsky)_(arknights)',
      );
    });

    test(
        'does not treat a default outfit base character tag as outfit identity',
        () {
      const outfit = WorkspaceOutfit(
        id: 'default',
        name: 'Default',
        tags: ViewVariantTexts(
          frontFull: 'pepe_(arknights), animal ear hood, black jacket',
        ),
      );

      expect(deriveOutfitIdentityPrompt(outfit), isEmpty);
    });

    test('keeps base identity when non-default outfit has no skin identity',
        () {
      const outfit = WorkspaceOutfit(
        id: 'variant',
        name: 'Variant',
        tags: ViewVariantTexts(
          frontFull: 'pepe_(arknights), black jacket',
        ),
      );

      expect(deriveOutfitIdentityPrompt(outfit), 'pepe_(arknights)');
    });

    test('uses standalone legacy underscore skin tag from non-default outfit',
        () {
      const outfit = WorkspaceOutfit(
        id: 'summer',
        name: 'Summer',
        tags: ViewVariantTexts(
          frontFull: 'eyjafjalla_(summer_flower)_(arknights), bikini',
        ),
      );

      expect(
        deriveOutfitIdentityPrompt(outfit),
        'eyjafjalla_(arknights), eyjafjalla_(summer_flower)_(arknights)',
      );
    });

    test('uses base and skin identity from standalone spaced skin tag', () {
      const outfit = WorkspaceOutfit(
        id: 'yukibare',
        name: 'Yukibare',
        tags: ViewVariantTexts(
          frontFull: 'suzuran (yukibare) (arknights), kimono',
        ),
      );

      expect(
        deriveOutfitIdentityPrompt(outfit),
        'suzuran (arknights), suzuran (yukibare) (arknights)',
      );
    });

    test('derives base identity from multi-parenthesized skin tag', () {
      const outfit = WorkspaceOutfit(
        id: 'special',
        name: 'Special',
        tags: ViewVariantTexts(
          frontFull: 'pepe_(event)_(nuit_of_the_nightsky)_(arknights)',
        ),
      );

      expect(
        deriveOutfitIdentityPrompt(outfit),
        'pepe_(arknights), pepe_(event)_(nuit_of_the_nightsky)_(arknights)',
      );
    });

    test('selected outfit identity dedupes upper and lower outfit identity',
        () {
      const outfit = WorkspaceOutfit(
        id: 'skin',
        name: 'Nuit of the Nightsky',
        tags: ViewVariantTexts(
          frontFull: 'pepe_(arknights), '
              'pepe_(nuit_of_the_nightsky)_(arknights), white dress',
        ),
      );

      expect(
        deriveSelectedOutfitIdentityPrompt(outfit, outfit),
        'pepe_(arknights), pepe_(nuit_of_the_nightsky)_(arknights)',
      );
    });

    test('preserves weights on skin identity tags', () {
      const outfit = WorkspaceOutfit(
        id: 'skin',
        name: 'Nuit of the Nightsky',
        tags: ViewVariantTexts(
          frontFull: '1.2::pepe_(arknights)::, '
              '0.8::pepe_(nuit_of_the_nightsky)_(arknights)::, white dress',
        ),
      );

      expect(
        deriveOutfitIdentityPrompt(outfit),
        '1.2:: pepe_(arknights) ::, '
        '0.8:: pepe_(nuit_of_the_nightsky)_(arknights) ::',
      );
    });

    test('merge replaces an older skin identity for the same base character',
        () {
      expect(
        mergeBaseAndOutfitIdentity(
          'pepe_(arknights), pepe_(old_skin)_(arknights)',
          'pepe_(arknights), pepe_(nuit_of_the_nightsky)_(arknights)',
        ),
        'pepe_(arknights), pepe_(nuit_of_the_nightsky)_(arknights)',
      );
    });
  });
}
