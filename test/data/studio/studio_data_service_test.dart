import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/studio_data_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('studio-data-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('initializeAt creates the internal studio manifest', () async {
    final service = StudioDataService(workspaceService: WorkspaceService());

    await service.initializeAt(tempDir);

    final manifest = File(
      '${tempDir.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    );
    expect(await manifest.exists(), isTrue);
  });

  test('initializeAt auto-loads bundled cache before creating a new studio',
      () async {
    final target = Directory('${tempDir.path}/target');
    final bundledCache = Directory('${tempDir.path}/bundled_cache');
    final bundledStudio = Directory('${bundledCache.path}/novel_studio');
    await File(
      '${bundledStudio.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    ).create(recursive: true).then((file) => file.writeAsString(
          '{"name":"Bundled Studio","schemaVersion":1}',
        ));
    final bundledCharacters = File(
      '${bundledStudio.path}${Platform.pathSeparator}${WorkspacePaths.characters}',
    );
    await bundledCharacters.parent.create(recursive: true);
    await bundledCharacters.writeAsString(
      '[{"id":"bundled","name":"Bundled Character","traits":{}}]',
    );

    final workspaceService = WorkspaceService();
    final service = StudioDataService(
      workspaceService: workspaceService,
      bundledCacheRoot: bundledCache,
    );

    await service.initializeAt(target);

    final characters = await workspaceService.loadCharacters();
    expect(characters.single.name, 'Bundled Character');
  });

  test(
      'initializeAt restores richer legacy workspace and clears stale catalog cache',
      () async {
    final target = Directory('${tempDir.path}/current');
    final legacy = Directory('${tempDir.path}/legacy');
    const previewRef = 'assets/references/characters/peipei.png';
    final legacyWorkspace = WorkspaceService();
    await legacyWorkspace.createWorkspace(legacy.path);
    final previewFile = File(
      '${legacy.path}${Platform.pathSeparator}'
      '${previewRef.replaceAll('/', Platform.pathSeparator)}',
    );
    await previewFile.parent.create(recursive: true);
    await previewFile.writeAsBytes([1, 2, 3, 4]);
    await legacyWorkspace.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character-sheet-r14',
        name: '佩佩',
        traits: ViewVariantTexts(frontFull: 'peipei'),
        imageRefs: [previewRef],
        outfits: [
          WorkspaceOutfit(
            id: 'default-outfit',
            name: '默认服装',
            tags: ViewVariantTexts(frontFull: 'default outfit'),
            imageRefs: [previewRef],
          ),
          WorkspaceOutfit(
            id: 'default-outfit-copy',
            name: '默认服装 Copy',
            tags: ViewVariantTexts(frontFull: 'default outfit copy'),
            imageRefs: [previewRef],
          ),
        ],
      ),
    ]);

    final currentWorkspace = WorkspaceService();
    await currentWorkspace.createWorkspace(target.path);
    await currentWorkspace.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character-sheet-r14',
        name: '佩佩',
        traits: ViewVariantTexts(frontFull: 'peipei'),
        outfits: [
          WorkspaceOutfit(
            id: 'default-outfit',
            name: '默认服装',
            tags: ViewVariantTexts(frontFull: 'default outfit'),
          ),
        ],
      ),
    ]);
    final staleCache = File(
      '${target.path}${Platform.pathSeparator}'
      '${WorkspacePaths.assetCatalogCache}',
    );
    await staleCache.parent.create(recursive: true);
    await staleCache.writeAsString('{"schemaVersion":5,"entries":{}}');

    final workspaceService = WorkspaceService();
    final service = StudioDataService(workspaceService: workspaceService);

    await service.initializeAt(
      target,
      legacyWorkspaceRoots: [legacy],
    );

    final characters = await workspaceService.loadCharacters();
    final peipei = characters.single;
    expect(peipei.imageRefs, [previewRef]);
    expect(
      peipei.outfits.map((outfit) => outfit.id),
      contains('default-outfit-copy'),
    );
    expect(
      await File(
        '${target.path}${Platform.pathSeparator}'
        '${previewRef.replaceAll('/', Platform.pathSeparator)}',
      ).exists(),
      isTrue,
    );
    expect(await staleCache.exists(), isFalse);
  });

  test('initializeAt keeps current workspace when it already has previews',
      () async {
    final target = Directory('${tempDir.path}/current');
    final legacy = Directory('${tempDir.path}/legacy');
    final legacyWorkspace = WorkspaceService();
    await legacyWorkspace.createWorkspace(legacy.path);
    await legacyWorkspace.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character',
        name: 'Legacy',
        traits: ViewVariantTexts(frontFull: 'legacy'),
        imageRefs: ['assets/references/legacy.png'],
      ),
    ]);

    final currentWorkspace = WorkspaceService();
    await currentWorkspace.createWorkspace(target.path);
    await currentWorkspace.saveCharacters([
      const CharacterEntry(
        id: 'current-character',
        name: 'Current',
        traits: ViewVariantTexts(frontFull: 'current'),
        imageRefs: ['assets/references/current.png'],
      ),
    ]);

    final workspaceService = WorkspaceService();
    final service = StudioDataService(workspaceService: workspaceService);

    await service.initializeAt(
      target,
      legacyWorkspaceRoots: [legacy],
    );

    final characters = await workspaceService.loadCharacters();
    expect(characters.single.id, 'current-character');
  });

  test('initializeAt opens existing studio data without clearing characters',
      () async {
    final workspaceService = WorkspaceService();
    final service = StudioDataService(workspaceService: workspaceService);
    await service.initializeAt(tempDir);
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
      ),
    ]);

    final reopenedWorkspaceService = WorkspaceService();
    final reopenedService = StudioDataService(
      workspaceService: reopenedWorkspaceService,
    );
    await reopenedService.initializeAt(tempDir);
    final characters = await reopenedWorkspaceService.loadCharacters();

    expect(characters.single.id, 'char-1');
    expect(characters.single.traits.frontFull, 'blue eyes');
  });

  test('initializeAt seeds legacy artist workbook data into an empty studio',
      () async {
    final workspaceService = WorkspaceService();
    final service = StudioDataService(
      workspaceService: workspaceService,
      legacyArtistSeedLoader: () async => {
        'artistChains': [
          {
            'id': 'legacy-artist-1',
            'name': 'Ink Wash',
            'tags': ['Ink Wash'],
            'prompt': 'artist:nixeu, artist:wlop',
          },
        ],
        'characters': [
          {
            'id': 'legacy-character-1',
            'name': 'Eyjafjalla',
            'traits': {'front_full': 'eyjafjalla_(arknights)'},
            'outfits': [],
          },
        ],
      },
    );

    await service.initializeAt(tempDir);

    final artistChains = await workspaceService.loadArtistChains();
    final characters = await workspaceService.loadCharacters();

    expect(artistChains.single.name, 'Ink Wash');
    expect(artistChains.single.prompt, 'artist:nixeu, artist:wlop');
    expect(characters.single.name, 'Eyjafjalla');
  });

  test('initializeAt does not overwrite non-empty studio assets with seed data',
      () async {
    final workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    await workspaceService.saveArtistChains([
      const ArtistChain(
        id: 'artist-1',
        name: 'Existing Painter',
        prompt: 'artist:existing',
      ),
    ]);

    final service = StudioDataService(
      workspaceService: workspaceService,
      legacyArtistSeedLoader: () async => {
        'artistChains': [
          {
            'id': 'legacy-artist-1',
            'name': 'Ink Wash',
            'prompt': 'artist:nixeu',
          },
        ],
        'characters': [
          {
            'id': 'legacy-character-1',
            'name': 'Eyjafjalla',
            'traits': {'front_full': 'eyjafjalla_(arknights)'},
            'outfits': [],
          },
        ],
      },
    );

    await service.initializeAt(tempDir);

    final artistChains = await workspaceService.loadArtistChains();
    final characters = await workspaceService.loadCharacters();

    expect(artistChains.single.name, 'Existing Painter');
    expect(characters, isEmpty);
  });

  test('initializeAt backfills legacy artist image refs into existing studio',
      () async {
    final workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    await workspaceService.saveArtistChains([
      const ArtistChain(
        id: 'legacy-artist-1',
        name: 'Ink Wash',
        prompt: 'artist:nixeu',
        source: SourceRef(type: 'legacy_artist_workbook'),
      ),
      const ArtistChain(
        id: 'manual-artist',
        name: 'Manual Painter',
        prompt: 'artist:manual',
      ),
    ]);

    final service = StudioDataService(
      workspaceService: workspaceService,
      legacyArtistSeedLoader: () async => {
        'artistChains': [
          {
            'id': 'legacy-artist-1',
            'name': 'Ink Wash',
            'prompt': 'artist:nixeu',
            'imageRefs': ['E:\\legacy\\nixeu.png'],
          },
        ],
        'characters': [],
      },
    );

    await service.initializeAt(tempDir);

    final artistChains = await workspaceService.loadArtistChains();

    expect(artistChains.first.imageRefs, ['E:\\legacy\\nixeu.png']);
    expect(artistChains.last.imageRefs, isEmpty);
  });

  test('initializeAt leaves legacy codex out of workspace inspirations',
      () async {
    final workspaceService = WorkspaceService();
    final service = StudioDataService(
      workspaceService: workspaceService,
      legacyArtistSeedLoader: () async => const {
        'artistChains': [],
        'characters': [],
      },
      legacyCodexSeedLoader: () async => {
        'inspirations': [
          {
            'id': 'legacy-codex-regular-0001',
            'name': 'Fantasy',
            'prompt': 'artist:wlop, dnd, fantasy',
            'tags': ['Codex', 'Regular'],
            'source': {'type': 'legacy_codex', 'id': 'regular.docx#p156'},
          },
        ],
      },
    );

    await service.initializeAt(tempDir);

    final inspirations = await workspaceService.loadInspirations();
    final codexEntries = await service.loadLegacyCodexSeedEntries();

    expect(inspirations, isEmpty);
    expect(codexEntries.single.source.type, 'legacy_codex');
  });

  test('initializeAt removes previously seeded legacy codex entries', () async {
    final workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    await workspaceService.saveInspirations([
      const InspirationEntry(
        id: 'legacy-codex-regular-0001',
        name: 'Fantasy',
        prompt: 'artist:wlop, dnd, fantasy',
        tags: ['Codex', 'Regular'],
        source: SourceRef(type: 'legacy_codex', id: 'regular.docx#p156'),
      ),
    ]);

    final service = StudioDataService(
      workspaceService: workspaceService,
      legacyArtistSeedLoader: () async => const {
        'artistChains': [],
        'characters': [],
      },
      legacyCodexSeedLoader: () async => const {
        'inspirations': [],
      },
    );

    await service.initializeAt(tempDir);

    final inspirations = await workspaceService.loadInspirations();

    expect(inspirations, isEmpty);
  });
}
