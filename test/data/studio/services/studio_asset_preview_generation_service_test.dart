import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

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

    test('generates an artist-chain preview with saved character anchor',
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
      expect(payload['model'], 'nai-diffusion-5-curated');
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
      expect(prompt, contains('Mira'));
      expect(prompt, contains('silver hair'));
      expect(prompt, contains('mira_(test)'));
      expect(prompt, contains('random-character-anchor'));
      expect(prompt, contains('1girl'));
      expect(prompt, contains('solo'));
      expect(prompt, contains('simple soft background'));
      expect(prompt, isNot(contains('single character')));
      expect(prompt, isNot(contains('suzuran_(arknights)')));
      expect(prompt, isNot(contains('scenic background')));
      expect(prompt, isNot(contains('full composition')));
      expect(prompt, isNot(contains('pure white background')));
      expect(parameters['params_version'], 4);
      expect(parameters['reference_image_multiple'], isEmpty);
      expect(parameters['reference_strength_multiple'], isEmpty);
      expect(parameters['reference_information_extracted_multiple'], isEmpty);
      expect(_baseCaption(parameters, 'v4_negative_prompt'), defaultUC);
      expect(_charCaptions(parameters, 'v4_prompt'), isEmpty);
      expect(_v4Prompt(parameters, 'v4_prompt')['use_coords'], isFalse);
      expect(_v4Prompt(parameters, 'v4_prompt')['use_order'], isTrue);
      expect(prompt, payload['input']);
    });

    test('artist-chain preview uses random character and scene codex prompt',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'chain-1',
          name: 'Painter Chain',
          tags: ['artist:foo'],
          prompt: 'delicate brushwork',
          styleTags: ['watercolor'],
        ),
      ]);
      await workspaceService.saveCharacters([
        _character(
          id: 'char-a',
          name: 'Asha',
          traits: 'blue hair',
          identityTags: ['asha_(test)'],
        ),
        _character(
          id: 'char-b',
          name: 'Bela',
          traits: 'red hair',
          identityTags: ['bela_(test)'],
        ),
      ]);
      await workspaceService.saveInspirations([
        _inspiration(
          id: 'scene-1',
          name: 'Moonlit Room',
          prompt: 'moonlit room, window, night',
          source: const SourceRef(type: 'novalai_codex_adult_docx'),
        ),
        _inspiration(
          id: 'clothing-1',
          name: 'Red Dress',
          prompt: 'red dress, ribbon',
          source: const SourceRef(type: 'novalai_codex_adult_docx'),
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 1, 0, 777],
      );

      await service.generateArtistChainPreview(
        'chain-1',
        options: const StudioAssetPreviewGenerationOptions(
          customPrompt: 'extra glow',
        ),
      );

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('artist:foo'));
      expect(prompt, contains('delicate brushwork'));
      expect(prompt, contains('watercolor'));
      expect(prompt, contains('Bela'));
      expect(prompt, contains('red hair'));
      expect(prompt, contains('bela_(test)'));
      expect(prompt, contains('moonlit room'));
      expect(prompt, contains('window'));
      expect(prompt, contains('night'));
      expect(prompt, contains('1girl'));
      expect(prompt, contains('solo'));
      expect(prompt, contains('extra glow'));
      expect(prompt, isNot(contains('red dress')));
      expect(prompt, isNot(contains('single character')));
    });

    test('artist-chain preview preserves structured weighted prompt terms',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'chain-1',
          name: 'Weighted Chain',
          tags: ['artist:legacy_plain'],
          prompt: 'delicate brushwork',
          styleTags: ['line art'],
          artists: const [
            ArtistEntry(name: 'foo_artist', weight: 1.5),
            ArtistEntry(name: 'bar_artist', weight: 0.75),
          ],
          styleHintsWeighted: const [
            WorkspaceWeightedTag(tag: 'soft shading', weight: 1.2),
          ],
          globalNegatives: const [
            WorkspaceWeightedTag(tag: 'flat color', weight: -6),
          ],
        ),
      ]);
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair',
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 123],
      );

      await service.generateArtistChainPreview('chain-1');

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('1.5:: artist:foo_artist ::'));
      expect(prompt, contains('0.75:: artist:bar_artist ::'));
      expect(prompt, contains('1.2:: soft shading ::'));
      expect(prompt, contains('delicate brushwork'));
      expect(prompt, contains('line art'));
      expect(prompt, isNot(contains('artist:legacy_plain')));
      final negativePrompt = _baseCaption(parameters, 'v4_negative_prompt');
      expect(negativePrompt, contains(defaultUC));
      expect(negativePrompt, contains('-6:: flat color ::'));
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

    test('character preview uses selected artist chain and count terms',
        () async {
      await workspaceService.saveArtistChains([
        _artistChain(
          id: 'chain-1',
          name: 'Soft Chain',
          tags: ['artist:soft_foo'],
          prompt: 'delicate watercolor',
          styleTags: ['soft shading'],
          vibeRefs: const [
            WorkspaceVibeReference(
              id: 'soft-vibe',
              name: 'Soft Vibe',
              vibeB64: 'encoded-soft-vibe',
              referenceStrength: 0.44,
              infoExtracted: 0.66,
            ),
          ],
        ),
      ]);
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair, green eyes',
          identityTags: ['mira_(test)'],
          anchorTags: ['fox ears'],
          imageRefs: ['existing.png'],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 123456],
      );

      await service.generateCharacterPreview(
        'char-1',
        options: const StudioAssetPreviewGenerationOptions(
          artistChainId: 'chain-1',
          customPrompt: 'sparkling dust',
        ),
      );

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('artist:soft_foo'));
      expect(prompt, contains('delicate watercolor'));
      expect(prompt, contains('soft shading'));
      expect(prompt, contains('silver hair'));
      expect(prompt, contains('mira_(test)'));
      expect(prompt, contains('1girl'));
      expect(prompt, contains('solo'));
      expect(prompt, contains('solid color background'));
      expect(prompt, contains('sparkling dust'));
      expect(prompt, isNot(contains('single character')));
      expect(parameters['reference_image_multiple'], isEmpty);
      expect(parameters['reference_strength_multiple'], isEmpty);
      expect(parameters['reference_information_extracted_multiple'], isEmpty);
      final characters = await workspaceService.loadCharacters();
      expect(characters.single.imageRefs,
          ['existing.png', 'generated/preview.png']);
    });

    test('custom replacement prompt replaces the generated template', () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair, green eyes',
          identityTags: ['mira_(test)'],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 321],
      );

      await service.generateCharacterPreview(
        'char-1',
        options: const StudioAssetPreviewGenerationOptions(
          customPrompt: 'only custom prompt',
          customPromptMode: StudioPreviewCustomPromptMode.replace,
        ),
      );

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, 'only custom prompt');
      expect(prompt, isNot(contains('silver hair')));
      expect(prompt, isNot(contains('masterpiece')));
    });

    test('custom append prompt preserves weighted groups', () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair',
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [0, 321],
      );

      await service.generateCharacterPreview(
        'char-1',
        options: const StudioAssetPreviewGenerationOptions(
          customPrompt: '1.5:: blue eyes, long hair ::',
        ),
      );

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      final prompt = _baseCaption(parameters, 'v4_prompt');
      expect(prompt, contains('1.5:: blue eyes ::'));
      expect(prompt, contains('1.5:: long hair ::'));
      expect(prompt, isNot(contains('1.5:: blue eyes, long hair ::')));
      expect(prompt, isNot(contains('1.5:: blue eyes, long hair')));
      expect(prompt, isNot(contains('blue eyes, long hair ::')));
    });

    test('character preview uses explicit selected size', () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair, green eyes',
          identityTags: ['mira_(test)'],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [98765],
      );

      await service.generateCharacterPreview(
        'char-1',
        options: StudioAssetPreviewGenerationOptions(
          size: defaultSizes[4],
        ),
      );

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      expect(parameters['width'], 1472);
      expect(parameters['height'], 704);
      expect(parameters['seed'], 98765);
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

    test('outfit preview uses explicit selected size', () async {
      await workspaceService.saveCharacters([
        _character(
          id: 'char-1',
          name: 'Mira',
          traits: 'silver hair',
          outfits: [
            _outfit(
              id: 'outfit-1',
              name: 'Rainwear',
              full: 'yellow raincoat',
            ),
          ],
        ),
      ]);
      final service = _service(
        workspaceService,
        requestedPayloads: requestedPayloads,
        savedFileNames: savedFileNames,
        randomInts: [2468],
      );

      await service.generateOutfitPreview(
        'char-1',
        'outfit-1',
        options: StudioAssetPreviewGenerationOptions(
          size: defaultSizes.first,
        ),
      );

      final parameters =
          requestedPayloads.single['parameters'] as Map<String, dynamic>;
      expect(parameters['width'], 704);
      expect(parameters['height'], 1472);
      expect(parameters['seed'], 2468);
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
  List<ArtistEntry> artists = const [],
  List<WorkspaceWeightedTag> globalNegatives = const [],
  List<WorkspaceWeightedTag> styleHintsWeighted = const [],
}) {
  return ArtistChain(
    id: id,
    name: name,
    tags: tags,
    prompt: prompt,
    styleTags: styleTags,
    imageRefs: imageRefs,
    vibeRefs: vibeRefs,
    artists: artists,
    globalNegatives: globalNegatives,
    styleHintsWeighted: styleHintsWeighted,
  );
}

InspirationEntry _inspiration({
  required String id,
  required String name,
  String prompt = '',
  String negativePrompt = '',
  List<String> tags = const [],
  SourceRef source = const SourceRef(type: 'manual'),
}) {
  return InspirationEntry(
    id: id,
    name: name,
    prompt: prompt,
    negativePrompt: negativePrompt,
    tags: tags,
    source: source,
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
