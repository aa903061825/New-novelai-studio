import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  group('StudioAssetCaptureService', () {
    late Directory tempDir;
    late WorkspaceService workspaceService;
    late StudioAssetCaptureService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('asset-capture-test-');
      workspaceService = WorkspaceService();
      await workspaceService.createWorkspace(tempDir.path);
      service = StudioAssetCaptureService(workspaceService: workspaceService);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates a new artist chain when no duplicate exists', () async {
      final draft = StudioAssetCaptureDraft.artistChain(
        artistChain: _artistChain(
          id: 'incoming',
          name: 'Incoming',
          tags: ['artist:bar'],
          prompt: 'artist:bar, ink',
          styleTags: ['ink'],
          note: 'from capture',
        ),
        source: _source,
      );

      final plan = await service.previewSave(draft);
      final result = await service.save(draft);

      expect(plan.candidates, isEmpty);
      expect(result.kind, StudioAssetCaptureKind.artistChain);
      expect(result.savedId, 'incoming');
      expect(result.name, 'Incoming');
      expect(result.merged, isFalse);
      final chains = await workspaceService.loadArtistChains();
      expect(chains, hasLength(1));
      expect(chains.single.id, 'incoming');
      expect(chains.single.prompt, 'artist:bar, ink');
    });

    test(
        'offers and merges duplicate artist chains by normalized tags and prompt',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'existing',
          name: 'Existing',
          tags: ['artist:foo'],
          prompt: 'artist:foo, watercolor',
          styleTags: ['watercolor'],
          note: 'existing note',
        ),
      ]);
      final draft = StudioAssetCaptureDraft.artistChain(
        artistChain: _artistChain(
          id: 'incoming',
          name: 'Incoming',
          tags: ['ARTIST:FOO'],
          prompt: 'ARTIST:FOO, watercolor',
          styleTags: ['Ink', 'watercolor'],
          note: 'incoming note',
        ),
        source: _source,
      );

      final plan = await service.previewSave(draft);
      final result = await service.save(draft, targetId: 'existing');

      expect(plan.candidates.map((candidate) => candidate.id), ['existing']);
      expect(result.savedId, 'existing');
      expect(result.name, 'Existing');
      expect(result.merged, isTrue);
      final chains = await workspaceService.loadArtistChains();
      expect(chains, hasLength(1));
      expect(chains.single.id, 'existing');
      expect(chains.single.name, 'Existing');
      expect(chains.single.tags, ['artist:foo']);
      expect(chains.single.prompt, 'artist:foo, watercolor, Ink');
      expect(chains.single.styleTags, ['watercolor', 'Ink']);
      expect(chains.single.note, 'existing note\nincoming note');
    });

    test('does not offer artist candidates for partial artist-only matches',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'existing',
          name: 'Existing',
          tags: ['artist:foo'],
          prompt: 'artist:foo, watercolor',
          styleTags: ['watercolor'],
        ),
      ]);
      final draft = StudioAssetCaptureDraft.artistChain(
        artistChain: _artistChain(
          id: 'incoming',
          name: 'Incoming',
          tags: ['ARTIST:FOO'],
          prompt: 'ARTIST:FOO, ink',
          styleTags: ['ink'],
        ),
        source: _source,
      );

      final plan = await service.previewSave(draft);

      expect(plan.candidates, isEmpty);
    });

    test('saves duplicate artist candidates as new chains without target id',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'existing',
          name: 'Existing',
          tags: ['artist:foo'],
          prompt: 'artist:foo, watercolor',
          styleTags: ['watercolor'],
        ),
      ]);
      final draft = StudioAssetCaptureDraft.artistChain(
        artistChain: _artistChain(
          id: 'incoming',
          name: 'Incoming',
          tags: ['ARTIST:FOO'],
          prompt: 'ARTIST:FOO, watercolor',
          styleTags: ['WATERCOLOR'],
        ),
        source: _source,
      );

      final plan = await service.previewSave(draft);
      final result = await service.save(draft);

      expect(plan.candidates.map((candidate) => candidate.id), ['existing']);
      expect(result.savedId, 'incoming');
      expect(result.merged, isFalse);
      expect(
        (await workspaceService.loadArtistChains()).map((chain) => chain.id),
        ['existing', 'incoming'],
      );
    });

    test('creates a character using current CharacterEntry fields', () async {
      final draft = StudioAssetCaptureDraft.character(
        character: _character(
          id: 'incoming-character',
          name: 'Mira',
          traits: 'silver hair, green eyes',
          identityTags: ['silver hair', 'green eyes'],
          note: 'new character',
        ),
        source: _source,
      );

      final result = await service.save(draft);

      expect(result.kind, StudioAssetCaptureKind.character);
      expect(result.savedId, 'incoming-character');
      expect(result.merged, isFalse);
      final characters = await workspaceService.loadCharacters();
      expect(characters, hasLength(1));
      expect(characters.single.id, 'incoming-character');
      expect(characters.single.name, 'Mira');
      expect(characters.single.traits.frontFull, 'silver hair, green eyes');
      expect(characters.single.identityTags, ['silver hair', 'green eyes']);
      expect(characters.single.note, 'new character');
    });

    test('offers character candidates by normalized name and identity tags',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'name-match',
          name: 'Mira',
          traits: 'silver hair',
          identityTags: ['silver hair'],
        ),
        _character(
          id: 'identity-match',
          name: 'Other',
          traits: 'green eyes, silver hair',
          identityTags: ['green eyes', 'silver hair'],
        ),
        _character(
          id: 'not-match',
          name: 'Nope',
          traits: 'blue eyes',
          identityTags: ['blue eyes'],
        ),
      ]);
      final draft = StudioAssetCaptureDraft.character(
        character: _character(
          id: 'incoming-character',
          name: ' mira ',
          traits: 'green eyes, silver hair',
          identityTags: ['SILVER HAIR', 'Green Eyes'],
        ),
        source: _source,
      );

      final plan = await service.previewSave(draft);

      expect(
        plan.candidates.map((candidate) => candidate.id),
        ['name-match', 'identity-match'],
      );
    });

    test(
        'merges a character by target id while preserving outfits and adding new ones',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'existing-character',
          name: 'Existing Mira',
          traits: 'silver hair',
          identityTags: ['silver hair'],
          note: 'existing note',
          outfits: [
            _outfit(id: 'school', name: 'School', tags: 'school uniform'),
          ],
          defaultOutfitId: 'school',
        ),
      ]);
      final draft = StudioAssetCaptureDraft.character(
        character: _character(
          id: 'incoming-character',
          name: 'Incoming Mira',
          traits: 'green eyes',
          identityTags: ['Green Eyes', 'silver hair'],
          note: 'incoming note',
          outfits: [
            _outfit(id: 'school', name: 'School duplicate', tags: 'duplicate'),
            _outfit(id: 'casual', name: 'Casual', tags: 'hoodie'),
          ],
        ),
        source: _source,
      );

      final result = await service.save(draft, targetId: 'existing-character');

      expect(result.savedId, 'existing-character');
      expect(result.name, 'Existing Mira');
      expect(result.merged, isTrue);
      final character = (await workspaceService.loadCharacters()).single;
      expect(character.id, 'existing-character');
      expect(character.name, 'Existing Mira');
      expect(
          character.outfits.map((outfit) => outfit.id), ['school', 'casual']);
      expect(character.outfits.first.name, 'School');
      expect(character.defaultOutfitId, 'school');
      expect(character.identityTags, ['silver hair', 'Green Eyes']);
      expect(character.note, 'existing note\nincoming note');
    });

    test(
        'merges matching character outfits and preserves incoming outfit detail',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'existing-character',
          name: 'Existing Mira',
          traits: 'silver hair',
          outfits: [
            _outfit(
              id: 'school',
              name: 'School',
              tags: 'school uniform',
              partTags: const WorkspaceOutfitPartTags(
                upperBodyTags: ['shirt'],
              ),
              imageRefs: ['existing.png'],
              note: 'existing outfit note',
            ),
            _outfit(id: 'casual-existing', name: 'Casual', tags: 'hoodie'),
          ],
        ),
      ]);
      final draft = StudioAssetCaptureDraft.character(
        character: _character(
          id: 'incoming-character',
          name: 'Incoming Mira',
          traits: 'green eyes',
          outfits: [
            _outfit(
              id: 'school',
              name: 'School duplicate',
              tags: 'blazer',
              partTags: const WorkspaceOutfitPartTags(
                upperClothingTags: ['blazer'],
              ),
              imageRefs: ['incoming.png'],
              note: 'incoming outfit note',
            ),
            _outfit(
              id: 'casual-incoming',
              name: 'casual',
              tags: 'sneakers',
              note: 'same name note',
            ),
          ],
        ),
        source: _source,
      );

      await service.save(draft, targetId: 'existing-character');

      final character = (await workspaceService.loadCharacters()).single;
      expect(character.outfits.map((outfit) => outfit.id), [
        'school',
        'casual-existing',
      ]);
      expect(character.outfits.first.name, 'School');
      expect(character.outfits.first.tags.frontFull, 'school uniform, blazer');
      expect(character.outfits.first.partTags.upperBodyTags, ['shirt']);
      expect(character.outfits.first.partTags.upperClothingTags, ['blazer']);
      expect(
          character.outfits.first.imageRefs, ['existing.png', 'incoming.png']);
      expect(
        character.outfits.first.note,
        'existing outfit note\nincoming outfit note',
      );
      expect(character.outfits.last.name, 'Casual');
      expect(character.outfits.last.tags.frontFull, 'hoodie, sneakers');
      expect(character.outfits.last.note, 'same name note');
    });

    test('adds an outfit to its parent and sets default outfit id if absent',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'parent',
          name: 'Parent',
          traits: 'blue eyes',
          identityTags: ['blue eyes'],
        ),
      ]);
      final draft = StudioAssetCaptureDraft.outfit(
        outfit: _outfit(id: 'travel', name: 'Travel', tags: 'coat, boots'),
        parentCharacterId: 'parent',
        source: _source,
      );

      final result = await service.save(draft);

      expect(result.kind, StudioAssetCaptureKind.outfit);
      expect(result.savedId, 'travel');
      expect(result.name, 'Travel');
      expect(result.merged, isFalse);
      final character = (await workspaceService.loadCharacters()).single;
      expect(character.outfits.map((outfit) => outfit.id), ['travel']);
      expect(character.defaultOutfitId, 'travel');
    });

    test(
        'adding an outfit to a legacy imported character preserves it for the asset catalog',
        () async {
      await workspaceService.saveCharacters([
        const CharacterEntry(
          id: 'legacy-parent',
          name: 'Legacy Parent',
          traits: ViewVariantTexts(frontFull: 'blue eyes'),
          source: SourceRef(type: 'legacy_artist_workbook'),
          defaultOutfitId: 'default-outfit',
          outfits: [
            WorkspaceOutfit(
              id: 'default-outfit',
              name: 'Default Outfit',
              tags: ViewVariantTexts(frontFull: 'school uniform'),
            ),
          ],
        ),
      ]);
      final draft = StudioAssetCaptureDraft.outfit(
        outfit: _outfit(id: 'travel', name: 'Travel', tags: 'coat, boots'),
        parentCharacterId: 'legacy-parent',
        source: _source,
      );

      await service.save(draft);

      final character = (await workspaceService.loadCharacters()).single;
      expect(character.source.type, 'manual');
      expect(
        character.outfits.map((outfit) => outfit.id),
        ['default-outfit', 'travel'],
      );

      final snapshot = await StudioAssetCatalogService(
        workspaceService: workspaceService,
      ).loadSnapshot();
      expect(snapshot.summary.outfitCount, 2);
      expect(snapshot.characters.single.outfits, hasLength(2));
    });

    test('offers outfit candidates within parent by name and front full tags',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'parent',
          name: 'Parent',
          traits: 'blue eyes',
          outfits: [
            _outfit(id: 'name-match', name: 'Travel', tags: 'coat'),
            _outfit(id: 'tags-match', name: 'Other', tags: 'boots, cloak'),
            _outfit(id: 'not-match', name: 'Nope', tags: 'hat'),
          ],
        ),
        _character(
          id: 'other-parent',
          name: 'Other Parent',
          traits: 'green eyes',
          outfits: [
            _outfit(id: 'wrong-parent', name: 'Travel', tags: 'boots, cloak'),
          ],
        ),
      ]);
      final draft = StudioAssetCaptureDraft.outfit(
        outfit: _outfit(id: 'incoming', name: ' travel ', tags: 'CLOAK, BOOTS'),
        parentCharacterId: 'parent',
        source: _source,
      );

      final plan = await service.previewSave(draft);

      expect(
        plan.candidates.map((candidate) => candidate.id),
        ['name-match', 'tags-match'],
      );
    });

    test('returns no outfit candidates when preview parent is missing',
        () async {
      final draft = StudioAssetCaptureDraft.outfit(
        outfit: _outfit(id: 'incoming', name: 'Travel', tags: 'coat'),
        parentCharacterId: 'missing',
        source: _source,
      );

      final plan = await service.previewSave(draft);

      expect(plan.candidates, isEmpty);
    });

    test('saves duplicate-id outfits without target id using a copied id',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'parent',
          name: 'Parent',
          traits: 'blue eyes',
          outfits: [
            _outfit(id: 'travel', name: 'Travel', tags: 'coat'),
            _outfit(id: 'travel-copy', name: 'Travel Copy', tags: 'cloak'),
          ],
          defaultOutfitId: 'travel',
        ),
      ]);
      final draft = StudioAssetCaptureDraft.outfit(
        outfit: _outfit(id: 'travel', name: 'Travel Variant', tags: 'boots'),
        parentCharacterId: 'parent',
        source: _source,
      );

      final result = await service.save(draft);

      expect(result.savedId, 'travel-copy-2');
      expect(result.name, 'Travel Variant');
      expect(result.merged, isFalse);
      final character = (await workspaceService.loadCharacters()).single;
      expect(
        character.outfits.map((outfit) => outfit.id),
        ['travel', 'travel-copy', 'travel-copy-2'],
      );
      expect(character.outfits.last.tags.frontFull, 'boots');
      expect(character.defaultOutfitId, 'travel');
    });

    test('throws a clear exception when saving an outfit without a parent',
        () async {
      final draft = StudioAssetCaptureDraft.outfit(
        outfit: _outfit(id: 'orphan', name: 'Orphan', tags: 'cloak'),
        parentCharacterId: 'parent',
        source: _source,
      ).copyWith(parentCharacterId: '');

      expect(
        () => service.save(draft),
        throwsA(
          isA<StudioAssetCaptureException>().having(
            (exception) => exception.message,
            'message',
            contains('parent character'),
          ),
        ),
      );
    });

    test('throws a clear exception when the parent character is missing',
        () async {
      final draft = StudioAssetCaptureDraft.outfit(
        outfit: _outfit(id: 'missing-parent', name: 'Missing', tags: 'cloak'),
        parentCharacterId: 'missing',
        source: _source,
      );

      expect(
        () => service.save(draft),
        throwsA(
          isA<StudioAssetCaptureException>().having(
            (exception) => exception.message,
            'message',
            contains('missing'),
          ),
        ),
      );
    });

    test('forceNew ignores targetId', () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'existing',
          name: 'Existing',
          tags: ['artist:foo'],
          prompt: 'artist:foo',
        ),
      ]);
      final draft = StudioAssetCaptureDraft.artistChain(
        artistChain: _artistChain(
          id: 'incoming',
          name: 'Incoming',
          tags: ['artist:foo'],
          prompt: 'artist:foo, ink',
        ),
        source: _source,
      );

      final result = await service.save(
        draft,
        targetId: 'existing',
        forceNew: true,
      );

      expect(result.savedId, 'incoming');
      expect(result.merged, isFalse);
      expect(
        (await workspaceService.loadArtistChains()).map((chain) => chain.id),
        ['existing', 'incoming'],
      );
    });
  });
}

const _source = StudioAssetCaptureSource(
  surface: 'test',
  label: 'Test source',
  sourceId: 'source-1',
);

ArtistChain _artistChain({
  required String id,
  required String name,
  List<String> tags = const [],
  String prompt = '',
  List<String> styleTags = const [],
  String note = '',
}) {
  return ArtistChain(
    id: id,
    name: name,
    tags: tags,
    prompt: prompt,
    styleTags: styleTags,
    note: note,
    source: _source.toSourceRef(),
  );
}

CharacterEntry _character({
  required String id,
  required String name,
  required String traits,
  List<String> identityTags = const [],
  List<WorkspaceOutfit> outfits = const [],
  String? defaultOutfitId,
  String note = '',
}) {
  return CharacterEntry(
    id: id,
    name: name,
    traits: ViewVariantTexts(frontFull: traits),
    identityTags: identityTags,
    outfits: outfits,
    defaultOutfitId: defaultOutfitId,
    note: note,
    source: _source.toSourceRef(),
  );
}

WorkspaceOutfit _outfit({
  required String id,
  required String name,
  required String tags,
  WorkspaceOutfitPartTags partTags = const WorkspaceOutfitPartTags(),
  List<String> imageRefs = const [],
  String note = '',
}) {
  return WorkspaceOutfit(
    id: id,
    name: name,
    tags: ViewVariantTexts(frontFull: tags),
    partTags: partTags,
    imageRefs: imageRefs,
    note: note,
  );
}
