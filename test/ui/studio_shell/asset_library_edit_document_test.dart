import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/ui/studio_shell/services/asset_library_edit_document.dart';

void main() {
  group('AssetLibraryEditDocument', () {
    test('updates character full prompt and derives identity tags', () {
      final updated = AssetLibraryEditDocument.updateCharacterPrompt(
        _character(source: const SourceRef(type: 'imported')),
        'solo, silver hair, blue eyes',
      );

      expect(updated.source.type, 'manual');
      expect(updated.traits.frontFull, 'solo, silver hair, blue eyes');
      expect(updated.identityTags, ['silver hair', 'blue eyes']);
    });

    test('updates character body fields without replacing identity tags', () {
      final updated = AssetLibraryEditDocument.updateCharacterPromptField(
        _character(identityTags: const ['alice']),
        AssetLibraryCharacterPromptField.upperBody,
        '  ',
      );

      expect(updated.traits.frontUpper, isNull);
      expect(updated.identityTags, ['alice']);
    });

    test('updates outfit part field and derives the full outfit prompt', () {
      final updated = AssetLibraryEditDocument.updateOutfitPromptField(
        _outfit(
          tags: const ViewVariantTexts(frontFull: 'white dress, bow'),
        ),
        AssetLibraryOutfitPromptField.upperBody,
        'slim waist',
      );

      expect(updated.partTags.upperBodyTags, ['slim waist']);
      expect(updated.partTags.upperClothingTags, ['white dress', 'bow']);
      expect(updated.tags.frontFull, 'slim waist, white dress, bow');
    });

    test('full outfit edit keeps part tags unchanged', () {
      final outfit = _outfit(
        partTags: const WorkspaceOutfitPartTags(
          upperBodyTags: ['slim waist'],
        ),
      );
      final updated = AssetLibraryEditDocument.updateOutfitPromptField(
        outfit,
        AssetLibraryOutfitPromptField.full,
        'black coat',
      );

      expect(updated.tags.frontFull, 'black coat');
      expect(updated.partTags.upperBodyTags, ['slim waist']);
    });
  });
}

CharacterEntry _character({
  SourceRef source = const SourceRef(type: 'manual'),
  List<String> identityTags = const [],
}) {
  return CharacterEntry(
    id: 'char-1',
    name: 'Alice',
    source: source,
    traits: const ViewVariantTexts(frontFull: 'old prompt'),
    identityTags: identityTags,
  );
}

WorkspaceOutfit _outfit({
  ViewVariantTexts tags = const ViewVariantTexts(frontFull: 'old outfit'),
  WorkspaceOutfitPartTags partTags = const WorkspaceOutfitPartTags(),
}) {
  return WorkspaceOutfit(
    id: 'outfit-1',
    name: 'Default',
    tags: tags,
    partTags: partTags,
  );
}
