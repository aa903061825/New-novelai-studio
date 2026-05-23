import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('novel-workspace-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('createWorkspace creates manifest and expected JSON files', () async {
    final service = WorkspaceService();

    await service.createWorkspace(tempDir.path, name: 'Test Studio');

    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}studio_manifest.json',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}library${Platform.pathSeparator}characters.json',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}library${Platform.pathSeparator}artist_chains.json',
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory(
        '${tempDir.path}${Platform.pathSeparator}configs${Platform.pathSeparator}prompt_configs',
      ).existsSync(),
      isTrue,
    );
    expect(service.currentManifest!.name, 'Test Studio');
  });

  test('writes and reads workspace characters', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path, name: 'Test Studio');

    await service.saveCharacters([
      CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: const ViewVariantTexts(frontFull: 'blue eyes'),
      ),
    ]);

    final characters = await service.loadCharacters();

    expect(characters.single.id, 'char-1');
    expect(characters.single.traits.frontFull, 'blue eyes');
  });

  test('writes and reads artist chains, recipes, and tags', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.saveArtistChains([
      const ArtistChain(id: 'artist-1', name: 'Painter', tags: ['soft light']),
    ]);
    await service.saveRecipes('style', [
      const Recipe(
        id: 'recipe-1',
        name: 'Soft watercolor',
        block: 'style',
        tags: 'watercolor, soft',
      ),
    ]);
    await service.saveTags('style', [
      const TagEntry(id: 'tag-1', tag: 'watercolor', block: 'style'),
    ]);

    final artistChains = await service.loadArtistChains();
    final recipes = await service.loadRecipes('style');
    final tags = await service.loadTags('style');

    expect(artistChains.single.tags, ['soft light']);
    expect(recipes.single.tags, 'watercolor, soft');
    expect(tags.single.tag, 'watercolor');
  });

  test('writes and reads prompt configs and generation profiles by id',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.savePromptConfig(
      const WorkspacePromptConfig(
        id: 'prompt-1',
        name: 'Default Prompt',
        rootConfig: {'enabled': true},
      ),
    );
    await service.saveGenerationProfile(
      const GenerationProfile(
        id: 'profile-1',
        name: 'Default Profile',
        negativePrompt: 'bad anatomy',
        secretRef: 'nai-token',
      ),
    );

    final promptConfig = await service.loadPromptConfig('prompt-1');
    final generationProfile = await service.loadGenerationProfile('profile-1');

    expect(promptConfig.name, 'Default Prompt');
    expect(promptConfig.rootConfig['enabled'], isTrue);
    expect(generationProfile.negativePrompt, 'bad anatomy');
    expect(generationProfile.secretRef, 'nai-token');
  });

  test('writes and reads non-basic asset files and production directories',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.saveInspirations([
      const InspirationEntry(
        id: 'insp-1',
        name: 'Night Alley',
        prompt: 'rainy alley',
      ),
    ]);
    await service.saveLoras([
      const LoraEntry(
        id: 'lora-1',
        name: 'SoftRain',
        triggerWords: ['softrain'],
        defaultStrength: 0.7,
      ),
    ]);
    await service.saveWorkflows([
      const WorkflowEntry(
        id: 'workflow-1',
        name: 'City Stack',
        payload: {'graph': {'nodes': 4}},
      ),
    ]);
    await service.saveBatchPlans([
      BatchPlan(
        id: 'batch-1',
        name: 'Night Queue',
        items: const [
          {'recipe': 'style-1'},
        ],
        createdAt: DateTime.parse('2026-05-23T00:00:00Z'),
        updatedAt: DateTime.parse('2026-05-23T00:00:00Z'),
      ),
    ]);
    await service.saveAssemblyPresets([
      const AssemblyPresetEntry(
        id: 'assembly-1',
        name: 'City Assembly',
        payload: {'blocks': ['style', 'scene']},
      ),
    ]);

    final inspirations = await service.loadInspirations();
    final loras = await service.loadLoras();
    final workflows = await service.loadWorkflows();
    final batchPlans = await service.loadBatchPlans();
    final assemblyPresets = await service.loadAssemblyPresets();

    expect(inspirations.single.prompt, 'rainy alley');
    expect(loras.single.triggerWords, ['softrain']);
    expect(loras.single.defaultStrength, 0.7);
    expect(workflows.single.payload['graph'], {'nodes': 4});
    expect(batchPlans.single.items.single['recipe'], 'style-1');
    expect(
      assemblyPresets.single.payload['blocks'],
      ['style', 'scene'],
    );
  });

  test('writes and reads filter rules without local secrets', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.saveFilterRules({
      'delete_keywords': 'masterpiece, watermark',
      'strong_filter_keywords': 'mosaic',
      'openai_api_key': 'pst-filter-secret',
      'assistant_url': 'https://ai.local/v1',
      'nested': {
        'replace_rules': 'jacket -> coat',
        'private_note': 'pst-nested-secret',
      },
    });

    final rules = await service.loadFilterRules();
    final filterRulesPath = WorkspacePaths.filterRules.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    final raw = await File(
      '${tempDir.path}${Platform.pathSeparator}$filterRulesPath',
    ).readAsString();

    expect(rules['delete_keywords'], 'masterpiece, watermark');
    expect(rules['strong_filter_keywords'], 'mosaic');
    expect(rules.containsKey('openai_api_key'), isFalse);
    expect(rules.containsKey('assistant_url'), isFalse);
    expect(rules['nested'], {'replace_rules': 'jacket -> coat'});
    expect(raw, isNot(contains('pst-filter-secret')));
    expect(raw, isNot(contains('https://ai.local')));
    expect(raw, isNot(contains('pst-nested-secret')));
  });

  test('imports artist studio assets and persists filter rules', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final studioRoot = Directory(
      '${tempDir.path}${Platform.pathSeparator}artist_studio_app',
    );
    final dataDir = Directory(
      '${studioRoot.path}${Platform.pathSeparator}data',
    );
    await dataDir.create(recursive: true);
    await File(
      '${dataDir.path}${Platform.pathSeparator}data.json',
    ).writeAsString(
      jsonEncode({
        'artists': [
          {
            'id': 'artist-1',
            'name': 'Soft Painter',
            'tags': ['soft color'],
          },
        ],
        'characters': [
          {
            'id': 'char-1',
            'name': 'Muse',
            'features': 'green eyes',
          },
        ],
      }),
    );
    await File(
      '${tempDir.path}${Platform.pathSeparator}nai_unified_config.json',
    ).writeAsString(
      jsonEncode({
        'delete_keywords': 'masterpiece, watermark',
        'strong_filter_keywords': 'mosaic',
        'openai_api_key': 'pst-filter-secret',
      }),
    );

    final result = await service.importArtistStudioData(studioRoot.path);
    final artistChains = await service.loadArtistChains();
    final characters = await service.loadCharacters();
    final rules = await service.loadFilterRules();

    expect(result.filterRules['delete_keywords'], 'masterpiece, watermark');
    expect(artistChains.single.name, 'Soft Painter');
    expect(characters.single.name, 'Muse');
    expect(rules['strong_filter_keywords'], 'mosaic');
    expect(rules.containsKey('openai_api_key'), isFalse);
  });

  test('requires an open workspace before file operations', () {
    final service = WorkspaceService();

    expect(service.loadCharacters, throwsStateError);
  });

  test('failed openWorkspace preserves previous workspace state', () async {
    final service = WorkspaceService();
    final workspaceA = Directory(
      '${tempDir.path}${Platform.pathSeparator}workspace_a',
    );
    final workspaceB = Directory(
      '${tempDir.path}${Platform.pathSeparator}workspace_b',
    );

    await service.createWorkspace(workspaceA.path, name: 'Workspace A');
    await service.openWorkspace(workspaceA.path);
    await workspaceB.create(recursive: true);

    await expectLater(
      service.openWorkspace(workspaceB.path),
      throwsA(isA<FileSystemException>()),
    );

    expect(service.root!.path, workspaceA.path);
    expect(service.currentManifest!.name, 'Workspace A');
  });

  test('rejects relative paths that escape the workspace root', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    expect(
      () => service.savePromptConfig(
        const WorkspacePromptConfig(
          id: '../outside',
          name: 'Outside',
          rootConfig: {},
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => service.savePromptConfig(
        const WorkspacePromptConfig(
          id: r'bad\id',
          name: 'Bad ID',
          rootConfig: {},
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => service.loadRecipes('..'),
      throwsArgumentError,
    );
  });
}
