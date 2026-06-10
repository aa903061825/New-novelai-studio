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
        'eyjafjalla_(summer_flower)_(arknights)',
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
