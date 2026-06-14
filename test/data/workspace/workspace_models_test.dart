import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/models/workspace_manifest.dart';

void main() {
  test('WorkspaceManifest round trips migration metadata', () {
    final manifest = WorkspaceManifest(
      schemaVersion: 1,
      name: 'Novel Studio',
      currentPromptConfigId: 'prompt-1',
      migrations: [
        WorkspaceMigrationEntry(
          sourceType: 'kamia',
          sourcePath: r'C:\src\kamia',
          importedAt: DateTime.parse('2026-05-21T09:00:00Z'),
          importerVersion: 1,
          counts: const {'recipes': 2, 'tags': 3},
        ),
      ],
    );

    final restored = WorkspaceManifest.fromJson(manifest.toJson());

    expect(restored.schemaVersion, 1);
    expect(restored.name, 'Novel Studio');
    expect(restored.currentPromptConfigId, 'prompt-1');
    expect(restored.migrations.single.sourceType, 'kamia');
    expect(restored.migrations.single.counts['recipes'], 2);
  });

  test('WorkspaceManifest copyWith can clear current prompt config', () {
    final manifest = WorkspaceManifest(
      schemaVersion: 1,
      name: 'Novel Studio',
      currentPromptConfigId: 'prompt-1',
    );

    final restored = manifest.copyWith(currentPromptConfigId: null);

    expect(restored.currentPromptConfigId, isNull);
  });

  test('CharacterEntry uses front_full as the required baseline variant', () {
    final character = CharacterEntry.fromJson({
      'id': 'char-1',
      'name': 'Heroine',
      'traits': {'front_full': 'blue eyes, silver hair'},
      'outfits': [
        {
          'id': 'outfit-1',
          'name': 'Uniform',
          'tags': {'front_full': 'school uniform'}
        }
      ],
      'imageRefs': ['assets/images/heroine.webp'],
      'source': {'type': 'kamia', 'id': 'old-char-1'},
      'note': 'main character',
    });

    expect(character.traits.frontFull, 'blue eyes, silver hair');
    expect(character.outfits.single.tags.frontFull, 'school uniform');
    expect(character.toJson()['id'], 'char-1');
  });

  test('CharacterEntry Recast fields default empty for old JSON', () {
    final character = CharacterEntry.fromJson({
      'id': 'char-1',
      'name': 'Heroine',
      'traits': {'front_full': 'blue eyes'},
    });

    expect(character.anchorTags, isEmpty);
    expect(character.identityTags, isEmpty);
    expect(character.conflictTags, isEmpty);
    expect(character.defaultCenters, isEmpty);
    expect(character.aliases, isEmpty);
    expect(character.recastNotes, '');
  });

  test('CharacterEntry Recast fields round trip', () {
    final character = CharacterEntry.fromJson({
      'id': 'char-1',
      'name': 'Heroine',
      'traits': {'front_full': 'blue eyes'},
      'anchorTags': ['vulpisfoglia_(arknights)'],
      'identityTags': ['fox_tail'],
      'conflictTags': ['cat_tail'],
      'defaultCenters': [
        {'x': 0.25, 'y': 0.55},
      ],
      'aliases': ['vulpisfoglia'],
      'recastNotes': 'source script extraction',
    });

    final restored = CharacterEntry.fromJson(character.toJson());

    expect(restored.anchorTags, ['vulpisfoglia_(arknights)']);
    expect(restored.identityTags, ['fox_tail']);
    expect(restored.conflictTags, ['cat_tail']);
    expect(restored.defaultCenters.single.x, 0.25);
    expect(restored.defaultCenters.single.y, 0.55);
    expect(restored.aliases, ['vulpisfoglia']);
    expect(restored.recastNotes, 'source script extraction');
    expect(restored.toJson(), character.toJson());
  });

  test('WorkspaceOutfit part tags round trip', () {
    final character = CharacterEntry.fromJson({
      'id': 'char-1',
      'name': 'Heroine',
      'traits': {'front_full': 'blue eyes'},
      'outfits': [
        {
          'id': 'outfit-1',
          'name': 'Garden Dress',
          'tags': {
            'front_full': 'white dress, fox_tail',
            'front_upper': 'white dress',
            'front_lower': 'white dress',
          },
          'partTags': {
            'upperBodyTags': ['blue_eyes', 'fox_ears'],
            'upperClothingTags': ['white_dress'],
            'lowerBodyTags': ['fox_tail'],
            'lowerClothingTags': ['white_dress'],
            'weaponTags': ['staff'],
          },
        }
      ],
    });

    final restored = CharacterEntry.fromJson(character.toJson());
    final outfit = restored.outfits.single;

    expect(outfit.partTags.upperBodyTags, ['blue_eyes', 'fox_ears']);
    expect(outfit.partTags.upperClothingTags, ['white_dress']);
    expect(outfit.partTags.lowerBodyTags, ['fox_tail']);
    expect(outfit.partTags.lowerClothingTags, ['white_dress']);
    expect(outfit.partTags.weaponTags, ['staff']);
    expect(restored.toJson(), character.toJson());
  });

  test('ArtistChain structured Recast fields round trip', () {
    final chain = ArtistChain.fromJson({
      'id': 'artist-1',
      'name': 'Painter Mix',
      'artists': [
        {
          'name': 'terasu_mc',
          'prefix': 'artist:',
          'weight': 0.8,
          'groupedWith': 'main',
        }
      ],
      'globalNegatives': [
        {'tag': 'artist:collaboration', 'weight': -6}
      ],
      'styleHintsWeighted': [
        {'tag': 'year 2024', 'weight': 1}
      ],
      'vibeRefs': [
        {
          'id': 'qaq-2',
          'name': 'QAQ 2',
          'vibeB64': 'encoded-vibe',
          'referenceStrength': 0.4,
        }
      ],
    });

    final restored = ArtistChain.fromJson(chain.toJson());

    expect(restored.artists.single.name, 'terasu_mc');
    expect(restored.artists.single.prefix, 'artist:');
    expect(restored.artists.single.weight, 0.8);
    expect(restored.artists.single.groupedWith, 'main');
    expect(restored.globalNegatives.single.weight, -6);
    expect(restored.styleHintsWeighted.single.tag, 'year 2024');
    expect(restored.vibeRefs.single.id, 'qaq-2');
    expect(restored.vibeRefs.single.vibeB64, 'encoded-vibe');
    expect(restored.vibeRefs.single.referenceStrength, 0.4);
    expect(restored.toJson(), chain.toJson());
  });

  test('GenerationProfile keeps secret refs separate from raw secrets', () {
    final profile = GenerationProfile.fromJson({
      'id': 'profile-1',
      'name': 'Default V4.5',
      'api_key': 'pst-ignored-top-level',
      'params': {'model': 'nai-diffusion-4-5-full', 'steps': 28},
      'negativePrompt': 'bad anatomy',
      'secretRef': 'default_nai_token',
    });

    expect(profile.params['steps'], 28);
    expect(profile.secretRef, 'default_nai_token');
    expect(profile.toJson()['api_key'], isNull);
    expect(
        profile.toJson().toString(), isNot(contains('pst-ignored-top-level')));
  });

  test('GenerationProfile sanitizes nested secret-shaped values', () {
    final profile = GenerationProfile.fromJson({
      'id': 'profile-1',
      'name': 'Default V4.5',
      'params': {
        'model': 'nai-diffusion-4-5-full',
        'steps': 28,
        'api_key': 'pst-top-level',
        'nested': {
          'width': 1024,
          'token': 'pst-nested',
          'headers': ['Bearer abc123', 'keep-me'],
        },
      },
      'batchDefaults': {
        'height': 1024,
        'proxy': 'http://localhost:8080',
        'jobs': [
          {'seed': 42, 'secret': 'pst-inside-list'},
        ],
      },
    });

    final json = profile.toJson();
    final params = json['params'] as Map<String, dynamic>;
    final nested = params['nested'] as Map<String, dynamic>;
    final headers = nested['headers'] as List<dynamic>;
    final batchDefaults = json['batchDefaults'] as Map<String, dynamic>;
    final jobs = batchDefaults['jobs'] as List<dynamic>;
    final firstJob = jobs.single as Map<String, dynamic>;

    expect(params['model'], 'nai-diffusion-4-5-full');
    expect(params['steps'], 28);
    expect(params.containsKey('api_key'), isFalse);
    expect(nested['width'], 1024);
    expect(nested.containsKey('token'), isFalse);
    expect(headers, ['keep-me']);
    expect(batchDefaults['height'], 1024);
    expect(batchDefaults.containsKey('proxy'), isFalse);
    expect(firstJob['seed'], 42);
    expect(firstJob.containsKey('secret'), isFalse);
  });

  test('WorkspacePromptConfig sanitizes private blocks and raw secrets', () {
    const promptConfig = WorkspacePromptConfig(
      id: 'prompt-1',
      name: 'Shared Prompt',
      rootConfig: {
        'selectionMethod': 'all',
        'strs': ['safe prompt', 'Bearer local-only-token'],
        'private_block': {
          'strs': ['private prompt']
        },
        'children': [
          {
            'comment': 'camera',
            'strs': ['wide shot']
          },
          {
            'comment': 'token',
            'strs': ['pst-nested-secret']
          },
        ],
      },
      savedBlocks: [
        {
          'comment': 'style',
          'strs': ['soft light', 'pst-saved-secret'],
          'api_key': 'pst-saved-key',
        },
      ],
    );

    final json = promptConfig.toJson();
    final rootConfig = json['rootConfig'] as Map<String, dynamic>;
    final savedBlock =
        (json['savedBlocks'] as List<dynamic>).single as Map<String, dynamic>;
    final encoded = json.toString();

    expect(rootConfig['strs'], ['safe prompt']);
    expect(rootConfig.containsKey('private_block'), isFalse);
    expect(savedBlock['strs'], ['soft light']);
    expect(savedBlock.containsKey('api_key'), isFalse);
    expect(encoded, isNot(contains('Bearer local-only-token')));
    expect(encoded, isNot(contains('private prompt')));
    expect(encoded, isNot(contains('pst-nested-secret')));
    expect(encoded, isNot(contains('pst-saved-secret')));
  });

  test('PromptChunkEntry round trips and inserts local prompt chunks', () {
    const chunk = PromptChunkEntry(
      id: 'chunk-1',
      name: 'Hair randomizer',
      prompt: '||red hair|blue hair|green hair||',
      negativePrompt: 'bad hair',
      tags: ['hair', 'randomizer'],
      note: 'official randomizer syntax',
    );

    final restored = PromptChunkEntry.fromJson(chunk.toJson());

    expect(restored.prompt, '||red hair|blue hair|green hair||');
    expect(restored.negativePrompt, 'bad hair');
    expect(restored.tags, ['hair', 'randomizer']);
    expect(
      restored.insertIntoPrompt('1girl, rain'),
      '1girl, rain, ||red hair|blue hair|green hair||',
    );
    expect(
      restored.insertIntoPrompt('1girl, rain', prepend: true),
      '||red hair|blue hair|green hair||, 1girl, rain',
    );
    expect(restored.insertIntoPrompt(''), '||red hair|blue hair|green hair||');
  });

  test('BatchPlan sanitizes item and status snapshots', () {
    final batchPlan = BatchPlan(
      id: 'batch-1',
      name: 'Shared Batch',
      items: const [
        {
          'prompt': 'safe prompt',
          'api_key': 'pst-item-secret',
          'nested': {'proxy': '127.0.0.1:7890'},
        },
      ],
      statusSnapshot: const {
        'completed': 0,
        'authorization': 'Bearer batch-secret',
      },
      createdAt: DateTime.parse('2026-05-22T09:00:00Z'),
      updatedAt: DateTime.parse('2026-05-22T09:00:00Z'),
    );

    final json = batchPlan.toJson();
    final item =
        (json['items'] as List<dynamic>).single as Map<String, dynamic>;
    final nested = item['nested'] as Map<String, dynamic>;
    final statusSnapshot = json['statusSnapshot'] as Map<String, dynamic>;
    final encoded = json.toString();

    expect(item['prompt'], 'safe prompt');
    expect(item.containsKey('api_key'), isFalse);
    expect(nested.containsKey('proxy'), isFalse);
    expect(statusSnapshot['completed'], 0);
    expect(statusSnapshot.containsKey('authorization'), isFalse);
    expect(encoded, isNot(contains('pst-item-secret')));
    expect(encoded, isNot(contains('Bearer batch-secret')));
  });

  test('Workspace entity parsing rejects wrong nested object types', () {
    expect(
      () => CharacterEntry.fromJson({
        'id': 'char-1',
        'name': 'Heroine',
        'traits': {'front_full': 'blue eyes'},
        'outfits': 'not a list',
      }),
      throwsFormatException,
    );

    expect(
      () => GenerationProfile.fromJson({
        'id': 'profile-1',
        'name': 'Default',
        'params': 'not a map',
      }),
      throwsFormatException,
    );
  });

  test('Workspace date parsing rejects invalid date strings', () {
    expect(
      () => WorkspaceMigrationEntry.fromJson({
        'sourceType': 'kamia',
        'sourcePath': r'C:\src\kamia',
        'importedAt': 'not a date',
        'importerVersion': 1,
      }),
      throwsFormatException,
    );

    expect(
      () => BatchPlan.fromJson({
        'id': 'batch-1',
        'name': 'Batch',
        'createdAt': 'not a date',
        'updatedAt': '2026-05-21T09:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test('Workspace string lists ignore non-string entries', () {
    final tag = TagEntry.fromJson({
      'tag': 'blue eyes',
      'aliases': ['aoi me', 42, null, 'blue_eye'],
    });

    expect(tag.id, 'blue eyes');
    expect(tag.aliases, ['aoi me', 'blue_eye']);
  });
}
