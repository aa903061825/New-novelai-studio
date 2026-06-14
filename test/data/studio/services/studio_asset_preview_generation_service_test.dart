import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/core/constants/defaults.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  group('StudioAssetPreviewGenerationService', () {
    late Directory tempDir;
    late WorkspaceService workspaceService;
    late List<Map<String, dynamic>> requestedPayloads;
    late List<String> savedFileNames;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'asset-preview-generation-test-',
      );
      workspaceService = WorkspaceService();
      await workspaceService.createWorkspace(tempDir.path);
      requestedPayloads = [];
      savedFileNames = [];
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'generates an artist-chain preview with fixed Suzuran character anchor',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'chain-1',
          name: 'Painter Chain',
          tags: ['artist:foo'],
          prompt: 'delicate brushwork',
          styleTags: ['watercolor'],
          imageRefs: ['existing.png'],
          vibeRefs: const [
            WorkspaceVibeReference(
              id: 'soft-style-vibe',
              name: 'Soft Style Vibe',
              vibeB64: 'encoded-soft-style-vibe',
              referenceStrength: 0.72,
              infoExtracted: 0.88,
            ),
          ],
        ),
      ]);
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair, green eyes',
          identityTags: ['mira_(test)', '1girl'],
          anchorTags: ['random-character-anchor'],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 42],
        now: DateTime(2026, 6, 4, 9, 8, 7),
      );

      final path = await service.generateArtistChainPreview('chain-1');

      expect(path, 'generated/preview.png');
      expect(savedFileNames.single,
          'asset-preview-artist-chain-chain-1-20260604-090807.png');
      final chains = await workspaceService.loadArtistChains();
      expect(
          chains.single.imageRefs, ['existing.png', 'generated/preview.png']);

      final payload = requestedPayloads.single;
      expect(payload['input'], isA<String>());
      expect(payload['model'], 'nai-diffusion-4-5-full');
      expect(payload['action'], 'generate');
      final parameters = payload['parameters'] as Map<String, dynamic>;
      expect(parameters['width'], 832);
      expect(parameters['height'], 1216);
      expect(parameters['seed'], 42);
      expect(parameters['negative_prompt'], defaultUC);
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('masterpiece'));
      expect(prompt, contains('artist:foo'));
      expect(prompt, contains('delicate brushwork'));
      expect(prompt, contains('watercolor'));
      expect(prompt, contains('suzuran_(arknights)'));
      expect(prompt, contains('1girl'));
      expect(prompt, contains('solo'));
      expect(prompt, contains('single character'));
      expect(prompt, contains('upper body'));
      expect(prompt, contains('close-up character portrait'));
      expect(prompt, contains('character fills most of the frame'));
      expect(prompt, isNot(contains('silver hair')));
      expect(prompt, isNot(contains('mira_(test)')));
      expect(prompt, isNot(contains('random-character-anchor')));
      expect(prompt, isNot(contains('scenic background')));
      expect(prompt, isNot(contains('full composition')));
      expect(prompt, isNot(contains('pure white background')));
      expect(
          parameters['reference_image_multiple'], ['encoded-soft-style-vibe']);
      expect(parameters['reference_strength_multiple'], [0.72]);
      expect(parameters['reference_information_extracted_multiple'], [0.88]);
      expect(_baseCaption(parameters, 'v4_negative_prompt'), defaultUC);
      expect(_charCaptions(parameters, 'v4_prompt'), isEmpty);
      expect(_v4Prompt(parameters, 'v4_prompt')['use_coords'], isFalse);
      expect(_v4Prompt(parameters, 'v4_prompt')['use_order'], isTrue);
      expect(prompt, payload['input']);
    });

    test('generates a character preview on pure white without scene terms',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair, green eyes',
          identityTags: ['mira_(test)', '1girl'],
          anchorTags: ['fox ears'],
          imageRefs: ['existing.png'],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [2, 123456],
        now: DateTime(2026, 6, 4, 10, 11, 12),
      );

      await service.generateCharacterPreview('char-1');

      expect(savedFileNames.single,
          'asset-preview-character-char-1-20260604-101112.png');
      final characters = await workspaceService.loadCharacters();
      expect(characters.single.imageRefs,
          ['existing.png', 'generated/preview.png']);

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      expect(parameters['width'], 1216);
      expect(parameters['height'], 832);
      expect(parameters['seed'], 123456);
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('masterpiece'));
      expect(prompt, contains('silver hair'));
      expect(prompt, contains('green eyes'));
      expect(prompt, contains('mira_(test)'));
      expect(prompt, contains('fox ears'));
      expect(prompt, contains('pure white background'));
      expect(prompt, isNot(contains('scenic background')));
      expect(prompt, isNot(contains('environment')));
    });

    test('character preview uses base identity for legacy outfit skins',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'legacy-character-sheet-r13',
          name: 'Suzuran',
          traits:
              'suzuran (spring praise) (arknights), fox girl, fox ears, fox tail',
          identityTags: ['suzuran_(spring_praise)_(arknights)'],
          anchorTags: ['suzuran_(spring_praise)_(arknights)'],
          source: const SourceRef(type: 'legacy_artist_workbook'),
          outfits: [
            _outfit(
              id: 'legacy-character-sheet-r13-outfit-3',
              name: 'Yukibare',
              full: 'suzuran (yukibare) (arknights)',
              upper: 'japanese_clothes, kimono',
              lower: 'hakama_skirt, sandals',
            ),
          ],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 2468],
      );

      await service.generateCharacterPreview('legacy-character-sheet-r13');

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('suzuran (arknights)'));
      expect(prompt, contains('suzuran_(arknights)'));
      expect(prompt, isNot(contains('suzuran (spring praise) (arknights)')));
      expect(prompt, isNot(contains('suzuran_(spring_praise)_(arknights)')));
      expect(prompt, contains('fox girl'));
      expect(prompt, contains('fox ears'));
      expect(prompt, contains('fox tail'));
    });

    test('generates an outfit preview from character and outfit terms',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair, fox ears',
          identityTags: ['mira_(test)', '1girl'],
          anchorTags: ['hood_over_head', 'mira_anchor'],
          outfits: [
            _outfit(
              id: 'outfit-1',
              name: 'Rain Coat',
              full: 'yellow raincoat, black boots',
              upper: 'yellow raincoat, hood',
              lower: 'black boots',
              partTags: const WorkspaceOutfitPartTags(
                upperBodyTags: ['fox ears'],
                upperClothingTags: ['yellow raincoat', 'hood'],
                lowerBodyTags: ['fox tail'],
                lowerClothingTags: ['black boots'],
              ),
              negativePrompt: 'hood, hood up',
              imageRefs: ['existing.png'],
            ),
          ],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [1, 321],
        now: DateTime(2026, 6, 4, 13, 14, 15),
      );

      await service.generateOutfitPreview('char-1', 'outfit-1');

      expect(savedFileNames.single,
          'asset-preview-outfit-char-1-outfit-1-20260604-131415.png');
      final characters = await workspaceService.loadCharacters();
      expect(characters.single.imageRefs, isEmpty);
      expect(characters.single.outfits.single.imageRefs,
          ['existing.png', 'generated/preview.png']);

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      expect(parameters['width'], 1024);
      expect(parameters['height'], 1024);
      expect(parameters['seed'], 321);
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('silver hair'));
      expect(prompt, contains('mira_(test)'));
      expect(prompt, contains('mira_anchor'));
      expect(prompt, isNot(contains('hood_over_head')));
      expect(prompt, contains('Rain Coat'));
      expect(prompt, contains('yellow raincoat'));
      expect(prompt, contains('black boots'));
      expect(prompt, contains('fox tail'));
      expect(prompt, contains('pure white background'));
      expect(prompt, contains('clean outfit reference image'));
      expect(prompt, isNot(contains('scenic background')));
      final negativePrompt = _baseCaption(parameters, 'v4_negative_prompt');
      expect(negativePrompt, contains(defaultUC));
      expect(negativePrompt, contains('hood'));
    });

    test('outfit preview includes selected skin identity from outfit frontFull',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'pepe',
          name: 'Pepe',
          traits: 'pepe_(arknights), cat ears, cat tail',
          identityTags: ['pepe_(arknights)'],
          anchorTags: ['pepe_(arknights)'],
          outfits: [
            _outfit(
              id: 'nuit',
              name: 'Nuit of the Nightsky',
              full: 'pepe_(arknights), '
                  'pepe_(nuit_of_the_nightsky)_(arknights), white dress, skirt',
              upper: 'white dress',
              lower: 'skirt',
            ),
          ],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 777],
      );

      await service.generateOutfitPreview('pepe', 'nuit');

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(
        prompt,
        contains('pepe_(nuit_of_the_nightsky)_(arknights)'),
      );
      expect(prompt, contains('pepe_(arknights)'));
      expect(prompt, contains('white dress'));
      expect(prompt, contains('skirt'));
    });

    test('throws when artist chain is missing', () async {
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
      );

      await expectLater(
        service.generateArtistChainPreview('missing'),
        throwsA(
          isA<StudioAssetPreviewGenerationException>().having(
            (exception) => exception.message,
            'message',
            contains('missing'),
          ),
        ),
      );
      expect(requestedPayloads, isEmpty);
      expect(savedFileNames, isEmpty);
    });

    test('throws when outfit is missing', () async {
      await workspaceService.saveCharacters([
        _character(id: 'char-1', name: 'Mira'),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
      );

      await expectLater(
        service.generateOutfitPreview('char-1', 'missing'),
        throwsA(
          isA<StudioAssetPreviewGenerationException>().having(
            (exception) => exception.message,
            'message',
            contains('missing'),
          ),
        ),
      );
      expect(requestedPayloads, isEmpty);
      expect(savedFileNames, isEmpty);
    });

    test('throws when character is missing', () async {
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
      );

      await expectLater(
        service.generateCharacterPreview('missing'),
        throwsA(
          isA<StudioAssetPreviewGenerationException>().having(
            (exception) => exception.message,
            'message',
            contains('missing'),
          ),
        ),
      );
      expect(requestedPayloads, isEmpty);
      expect(savedFileNames, isEmpty);
    });

    test('preserves artist-chain edits saved while image is being written',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'chain-1',
          name: 'Painter Chain',
          imageRefs: ['existing.png'],
        ),
      ]);
      final service = StudioAssetPreviewGenerationService(
        workspaceService: workspaceService,
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return Uint8List.fromList([1, 2, 3]);
        },
        saveImage: (bytes, fileName) async {
          savedFileNames.add(fileName);
          final chains = await workspaceService.loadArtistChains();
          await workspaceService.saveArtistChains([
            chains.single.copyWith(
              name: 'Edited During Save',
              imageRefs: ['existing.png', 'concurrent.png'],
            ),
          ]);
          return 'generated/preview.png';
        },
        randomInt: (_) => 0,
        now: () => DateTime(2026, 6, 4, 12, 0, 0),
      );

      await service.generateArtistChainPreview('chain-1');

      final chain = (await workspaceService.loadArtistChains()).single;
      expect(chain.name, 'Edited During Save');
      expect(chain.imageRefs,
          ['existing.png', 'concurrent.png', 'generated/preview.png']);
    });

    test('preserves character edits saved while image is being written',
        () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          imageRefs: ['existing.png'],
        ),
      ]);
      final service = StudioAssetPreviewGenerationService(
        workspaceService: workspaceService,
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return Uint8List.fromList([1, 2, 3]);
        },
        saveImage: (bytes, fileName) async {
          savedFileNames.add(fileName);
          final characters = await workspaceService.loadCharacters();
          await workspaceService.saveCharacters([
            characters.single.copyWith(
              name: 'Edited During Save',
              imageRefs: ['existing.png', 'concurrent.png'],
            ),
          ]);
          return 'generated/preview.png';
        },
        randomInt: (_) => 0,
        now: () => DateTime(2026, 6, 4, 12, 0, 0),
      );

      await service.generateCharacterPreview('char-1');

      final character = (await workspaceService.loadCharacters()).single;
      expect(character.name, 'Edited During Save');
      expect(character.imageRefs,
          ['existing.png', 'concurrent.png', 'generated/preview.png']);
    });

    test('preserves outfit edits saved while image is being written', () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          outfits: [
            _outfit(
              id: 'outfit-1',
              name: 'Rain Coat',
              imageRefs: ['existing.png'],
            ),
          ],
        ),
      ]);
      final service = StudioAssetPreviewGenerationService(
        workspaceService: workspaceService,
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return Uint8List.fromList([1, 2, 3]);
        },
        saveImage: (bytes, fileName) async {
          savedFileNames.add(fileName);
          final characters = await workspaceService.loadCharacters();
          final character = characters.single;
          final outfit = character.outfits.single;
          await workspaceService.saveCharacters([
            character.copyWith(
              outfits: [
                WorkspaceOutfit(
                  id: outfit.id,
                  name: 'Edited During Save',
                  tags: outfit.tags,
                  partTags: outfit.partTags,
                  imageRefs: ['existing.png', 'concurrent.png'],
                  note: outfit.note,
                ),
              ],
            ),
          ]);
          return 'generated/preview.png';
        },
        randomInt: (_) => 0,
        now: () => DateTime(2026, 6, 4, 12, 0, 0),
      );

      await service.generateOutfitPreview('char-1', 'outfit-1');

      final outfit =
          (await workspaceService.loadCharacters()).single.outfits.single;
      expect(outfit.name, 'Edited During Save');
      expect(outfit.imageRefs,
          ['existing.png', 'concurrent.png', 'generated/preview.png']);
    });

    test('sanitizes entity ids in generated filenames', () async {
      await workspaceService.saveCharacters([
        _character(id: 'bad/id:name', name: 'Mira'),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        now: DateTime(2026, 6, 4, 1, 2, 3),
      );

      await service.generateCharacterPreview('bad/id:name');

      expect(savedFileNames.single,
          'asset-preview-character-bad-id-name-20260604-010203.png');
    });

    test('does not append a duplicate returned artist-chain image path',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'chain-1',
          name: 'Painter Chain',
          imageRefs: ['existing.png', 'generated/preview.png'],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
      );

      await service.generateArtistChainPreview('chain-1');

      final chains = await workspaceService.loadArtistChains();
      expect(
          chains.single.imageRefs, ['existing.png', 'generated/preview.png']);
    });

    test('does not append a duplicate returned character image path', () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          imageRefs: ['existing.png', 'generated/preview.png'],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
      );

      await service.generateCharacterPreview('char-1');

      final characters = await workspaceService.loadCharacters();
      expect(characters.single.imageRefs,
          ['existing.png', 'generated/preview.png']);
    });

    test('discarding a generated character preview removes only that image',
        () async {
      final generatedFile = File(
        '${tempDir.path}${Platform.pathSeparator}generated-character.png',
      )..writeAsBytesSync([1, 2, 3]);
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          imageRefs: [
            'existing.png',
            generatedFile.path,
            'concurrent.png',
          ],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
      );

      await service.discardCharacterPreview('char-1', generatedFile.path);

      final characters = await workspaceService.loadCharacters();
      expect(characters.single.imageRefs, ['existing.png', 'concurrent.png']);
      expect(generatedFile.existsSync(), isFalse);
    });

    test('discarding a generated artist preview removes only that image',
        () async {
      final generatedFile = File(
        '${tempDir.path}${Platform.pathSeparator}generated-artist.png',
      )..writeAsBytesSync([1, 2, 3]);
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'chain-1',
          name: 'Painter Chain',
          imageRefs: [
            'existing.png',
            generatedFile.path,
            'concurrent.png',
          ],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
      );

      await service.discardArtistChainPreview('chain-1', generatedFile.path);

      final chains = await workspaceService.loadArtistChains();
      expect(chains.single.imageRefs, ['existing.png', 'concurrent.png']);
      expect(generatedFile.existsSync(), isFalse);
    });

    test('selects all three preview sizes through deterministic randomInt',
        () async {
      await workspaceService.saveCharacters([
        _character(id: 'char-1', name: 'Mira'),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 7, 1, 8, 2, 9],
      );

      await service.generateCharacterPreview('char-1');
      await service.generateCharacterPreview('char-1');
      await service.generateCharacterPreview('char-1');

      expect(
        requestedPayloads.map((payload) {
          final parameters = payload['parameters'] as Map<String, dynamic>;
          return '${parameters['width']}x${parameters['height']}';
        }),
        ['832x1216', '1024x1024', '1216x832'],
      );
    });

    test('clamps invalid random size values inside the service', () async {
      await workspaceService.saveCharacters([
        _character(id: 'char-1', name: 'Mira'),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [99, 7],
      );

      await service.generateCharacterPreview('char-1');

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      expect('${parameters['width']}x${parameters['height']}', '1216x832');
      expect(parameters['seed'], 7);
    });
  });
}

StudioAssetPreviewGenerationService _service(
  WorkspaceService workspaceService, {
  required List<Map<String, dynamic>> requestedPayloads,
  required List<String> savedFileNames,
  List<int> randomInts = const [0],
  DateTime? now,
}) {
  var randomIndex = 0;
  return StudioAssetPreviewGenerationService(
    workspaceService: workspaceService,
    requestImage: (payload) async {
      requestedPayloads.add(payload);
      return Uint8List.fromList([1, 2, 3]);
    },
    saveImage: (bytes, fileName) async {
      expect(bytes, Uint8List.fromList([1, 2, 3]));
      savedFileNames.add(fileName);
      return 'generated/preview.png';
    },
    randomInt: (max) {
      final value = randomInts[randomIndex % randomInts.length];
      randomIndex += 1;
      return value;
    },
    now: () => now ?? DateTime(2026, 6, 4, 12, 0, 0),
  );
}

Map<String, dynamic> _caption(Map<String, dynamic> parameters, String key) {
  return _v4Prompt(parameters, key)['caption'] as Map<String, dynamic>;
}

Map<String, dynamic> _v4Prompt(Map<String, dynamic> parameters, String key) {
  return parameters[key] as Map<String, dynamic>;
}

String _baseCaption(Map<String, dynamic> parameters, String key) {
  return _caption(parameters, key)['base_caption'] as String;
}

List<dynamic> _charCaptions(Map<String, dynamic> parameters, String key) {
  return _caption(parameters, key)['char_captions'] as List<dynamic>;
}

ArtistChain _artistChain({
  required String id,
  required String name,
  List<String> tags = const [],
  String prompt = '',
  List<String> styleTags = const [],
  List<String> imageRefs = const [],
  List<WorkspaceVibeReference> vibeRefs = const [],
}) {
  return ArtistChain(
    id: id,
    name: name,
    tags: tags,
    prompt: prompt,
    styleTags: styleTags,
    imageRefs: imageRefs,
    vibeRefs: vibeRefs,
  );
}

CharacterEntry _character({
  required String id,
  required String name,
  String traits = '',
  List<String> identityTags = const [],
  List<String> anchorTags = const [],
  List<String> imageRefs = const [],
  List<WorkspaceOutfit> outfits = const [],
  SourceRef source = const SourceRef(type: 'manual'),
}) {
  return CharacterEntry(
    id: id,
    name: name,
    traits: ViewVariantTexts(frontFull: traits),
    outfits: outfits,
    identityTags: identityTags,
    anchorTags: anchorTags,
    imageRefs: imageRefs,
    source: source,
  );
}

WorkspaceOutfit _outfit({
  required String id,
  required String name,
  String full = '',
  String? upper,
  String? lower,
  WorkspaceOutfitPartTags partTags = const WorkspaceOutfitPartTags(),
  List<String> imageRefs = const [],
  String negativePrompt = '',
}) {
  return WorkspaceOutfit(
    id: id,
    name: name,
    tags: ViewVariantTexts(
      frontFull: full,
      frontUpper: upper,
      frontLower: lower,
    ),
    partTags: partTags,
    imageRefs: imageRefs,
    negativePrompt: negativePrompt,
  );
}
