import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

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

  test('writes and reads CharacterEntry Recast fields', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path, name: 'Test Studio');

    await service.saveCharacters([
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
        anchorTags: ['vulpisfoglia_(arknights)'],
        identityTags: ['fox_tail'],
        conflictTags: ['cat_tail'],
        defaultCenters: [WorkspacePoint(x: 0.25, y: 0.55)],
        aliases: ['vulpisfoglia'],
        recastNotes: 'source script extraction',
      ),
    ]);

    final characters = await service.loadCharacters();

    expect(characters.single.anchorTags, ['vulpisfoglia_(arknights)']);
    expect(characters.single.identityTags, ['fox_tail']);
    expect(characters.single.conflictTags, ['cat_tail']);
    expect(characters.single.defaultCenters.single.x, 0.25);
    expect(characters.single.defaultCenters.single.y, 0.55);
    expect(characters.single.aliases, ['vulpisfoglia']);
    expect(characters.single.recastNotes, 'source script extraction');
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

  test('writes and reads asset favorite keys', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.saveAssetFavorites({
      'tag:scene/tag-2',
      'character:char-1',
      '',
      '  ',
    });

    final favoriteKeys = await service.loadAssetFavorites();
    final raw = await File(
      '${tempDir.path}${Platform.pathSeparator}library${Platform.pathSeparator}favorites.json',
    ).readAsString();

    expect(favoriteKeys, {'character:char-1', 'tag:scene/tag-2'});
    expect(raw, contains('character:char-1'));
    expect(raw, contains('tag:scene/tag-2'));

    await service.setAssetFavorite('tag:scene/tag-2', false);
    await service.setAssetFavorite('artist:artist-1', true);

    expect(await service.loadAssetFavorites(), {
      'artist:artist-1',
      'character:char-1',
    });
  });

  test('writes and reads script exhibition categories', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final categoriesFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionCategories.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    await categoriesFile.delete();

    expect(await service.loadScriptExhibitionCategories(), isEmpty);

    await service.saveScriptExhibitionCategories([
      'QAQ',
      '  qAq  ',
      '',
      'Story shelf',
    ]);

    expect(await service.loadScriptExhibitionCategories(), [
      'QAQ',
      'Story shelf',
    ]);

    await service.addScriptExhibitionCategory('Empty zone');
    expect(await service.loadScriptExhibitionCategories(), [
      'Empty zone',
      'QAQ',
      'Story shelf',
    ]);

    await service.removeScriptExhibitionCategory('qaq');
    expect(await service.loadScriptExhibitionCategories(), [
      'Empty zone',
      'Story shelf',
    ]);
  });

  test('writes and updates script exhibition category assignments', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    expect(await service.loadScriptExhibitionCategoryAssignments(), isEmpty);

    await service.assignScriptExhibitionCategoryScripts('QAQ', [
      'script-2',
      'script-1',
      'script-1',
      '',
    ]);
    await service.assignScriptExhibitionCategoryScripts(' qAq ', [
      'script-3',
    ]);
    await service.assignScriptExhibitionCategoryScripts('Archive', [
      'script-2',
    ]);

    expect(await service.loadScriptExhibitionCategoryAssignments(), {
      'Archive': ['script-2'],
      'QAQ': ['script-1', 'script-2', 'script-3'],
    });

    await service.removeScriptExhibitionCategoryFromScript('QAQ', 'script-2');
    expect(await service.loadScriptExhibitionCategoryAssignments(), {
      'Archive': ['script-2'],
      'QAQ': ['script-1', 'script-3'],
    });

    await service.removeScriptExhibitionCategoryAssignments('archive');
    expect(await service.loadScriptExhibitionCategoryAssignments(), {
      'QAQ': ['script-1', 'script-3'],
    });
  });

  test('writes and reads codex entries outside regular inspirations', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.saveCodexEntries([
      const InspirationEntry(
        id: 'adult-codex-entry',
        name: 'Adult Codex Entry',
        prompt: 'pov, close-up',
        source: SourceRef(type: 'novalai_codex_adult_docx'),
      ),
      const InspirationEntry(
        id: 'regular-codex-entry',
        name: 'Regular Codex Entry',
        prompt: 'artist:wlop, fantasy',
        source: SourceRef(type: 'legacy_codex'),
      ),
    ]);

    final entries = await service.loadCodexEntries();
    final codexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.codexEntries.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    final lines = (await codexFile.readAsLines())
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);

    expect(entries.map((entry) => entry.id), [
      'adult-codex-entry',
      'regular-codex-entry',
    ]);
    expect(lines, hasLength(2));
    expect(await service.loadInspirations(), isEmpty);
  });

  test('serializes same-path JSON saves in invocation order', () async {
    final initialService = WorkspaceService();
    await initialService.createWorkspace(tempDir.path);

    final firstCommitRelease = Completer<void>();
    final firstCommitStarted = Completer<void>();
    var commitCount = 0;
    final service = WorkspaceService(
      atomicFileCommitter: (source, targetPath) async {
        commitCount += 1;
        if (commitCount == 1) {
          firstCommitStarted.complete();
          await firstCommitRelease.future;
        }
        await source.rename(targetPath);
      },
    );
    await service.openWorkspace(tempDir.path);

    final firstSave = service.saveCharacters([
      const CharacterEntry(
        id: 'first',
        name: 'First',
        traits: ViewVariantTexts(frontFull: ''),
      ),
    ]);
    await firstCommitStarted.future.timeout(const Duration(seconds: 1));
    final secondSave = service.saveCharacters([
      const CharacterEntry(
        id: 'second',
        name: 'Second',
        traits: ViewVariantTexts(frontFull: ''),
      ),
    ]);
    expect(commitCount, 1);

    firstCommitRelease.complete();
    await Future.wait([firstSave, secondSave]);

    expect((await service.loadCharacters()).single.id, 'second');
  });

  test('serializes Codex JSONL saves without changing its newline format',
      () async {
    final initialService = WorkspaceService();
    await initialService.createWorkspace(tempDir.path);
    await initialService.saveCodexEntries(const []);

    final firstCommitRelease = Completer<void>();
    final firstCommitStarted = Completer<void>();
    var commitCount = 0;
    final service = WorkspaceService(
      atomicFileCommitter: (source, targetPath) async {
        commitCount += 1;
        if (commitCount == 1) {
          firstCommitStarted.complete();
          await firstCommitRelease.future;
        }
        await source.rename(targetPath);
      },
    );
    await service.openWorkspace(tempDir.path);

    final firstSave = service.saveCodexEntries([
      const InspirationEntry(id: 'first', name: 'First', prompt: 'first'),
    ]);
    await firstCommitStarted.future.timeout(const Duration(seconds: 1));
    final secondSave = service.saveCodexEntries([
      const InspirationEntry(id: 'second', name: 'Second', prompt: 'second'),
    ]);
    expect(commitCount, 1);

    firstCommitRelease.complete();
    await Future.wait([firstSave, secondSave]);

    final codexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.codexEntries.replaceAll('/', Platform.pathSeparator)}',
    );
    expect((await service.loadCodexEntries()).single.id, 'second');
    expect(await codexFile.readAsString(), endsWith('\n'));
  });

  test('keeps the old JSON file and cleans its temp file when commit fails',
      () async {
    final initialService = WorkspaceService();
    await initialService.createWorkspace(tempDir.path);
    await initialService.saveCharacters([
      const CharacterEntry(
        id: 'old',
        name: 'Old',
        traits: ViewVariantTexts(frontFull: ''),
      ),
    ]);
    final charactersFile = File(
      '${tempDir.path}${Platform.pathSeparator}library'
      '${Platform.pathSeparator}characters.json',
    );
    final oldContents = await charactersFile.readAsString();

    final service = WorkspaceService(
      atomicFileCommitter: (_, targetPath) {
        return Future<void>.error(
          FileSystemException('Injected commit failure', targetPath),
        );
      },
    );
    await service.openWorkspace(tempDir.path);

    await expectLater(
      service.saveCharacters([
        const CharacterEntry(
          id: 'new',
          name: 'New',
          traits: ViewVariantTexts(frontFull: ''),
        ),
      ]),
      throwsA(isA<FileSystemException>()),
    );

    expect(await charactersFile.readAsString(), oldContents);
    final temporaryFiles = await charactersFile.parent
        .list()
        .where(
          (entry) =>
              entry is File &&
              entry.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('characters.json.tmp-'),
        )
        .toList();
    expect(temporaryFiles, isEmpty);
  });

  test('writes and reads ArtistChain structured Recast fields', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.saveArtistChains([
      const ArtistChain(
        id: 'artist-1',
        name: 'Painter Mix',
        artists: [
          ArtistEntry(
            name: 'terasu_mc',
            prefix: 'artist:',
            weight: 0.8,
            groupedWith: 'main',
          ),
        ],
        globalNegatives: [
          WorkspaceWeightedTag(tag: 'artist:collaboration', weight: -6),
        ],
        styleHintsWeighted: [
          WorkspaceWeightedTag(tag: 'year 2024', weight: 1),
        ],
        vibeRefs: [
          WorkspaceVibeReference(
            id: 'qaq-2',
            name: 'QAQ 2',
            vibeB64: 'encoded-vibe',
            referenceStrength: 0.4,
          ),
        ],
      ),
    ]);

    final artistChains = await service.loadArtistChains();

    expect(artistChains.single.artists.single.name, 'terasu_mc');
    expect(artistChains.single.globalNegatives.single.weight, -6);
    expect(artistChains.single.styleHintsWeighted.single.tag, 'year 2024');
    expect(artistChains.single.vibeRefs.single.name, 'QAQ 2');
    expect(artistChains.single.vibeRefs.single.vibeB64, 'encoded-vibe');
  });

  test('writes and reads script recast long-term knowledge', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.saveRecastKnowledgeBase({
      'confirmedOnly': true,
      'scripts': {
        'script-1': {
          'roles': [
            {'displayName': 'Alice'},
          ],
        },
      },
      'nai_token': 'pst-secret-token',
    });

    final knowledge = await service.loadRecastKnowledgeBase();

    expect(knowledge['confirmedOnly'], isTrue);
    expect((knowledge['scripts'] as Map)['script-1']['roles'], hasLength(1));
    expect(knowledge.containsKey('nai_token'), isFalse);
  });

  test('missing script recast knowledge file loads as an empty knowledge base',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final knowledgeFile = File(
      '${tempDir.path}${Platform.pathSeparator}script_recast${Platform.pathSeparator}knowledge.json',
    );
    if (await knowledgeFile.exists()) {
      await knowledgeFile.delete();
    }

    final knowledge = await service.loadRecastKnowledgeBase();

    expect(knowledge, isEmpty);
  });

  test('writes script recast caches with external absolute script ids',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    const externalScriptId = r'E:\NAI的脚本群\作品集\白银ノエル 脱北 中出し';

    await service.saveRecastScriptCaches([
      RecastScriptCache(
        scriptId: externalScriptId,
        scriptName: '白银ノエル',
        sourceRootPath: externalScriptId,
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 5, 30),
        mapping: RecastMapping.defaults(externalScriptId),
      ),
    ]);

    final caches = await service.loadRecastScriptCaches();

    expect(caches.single.scriptId, externalScriptId);
    expect(
      await Directory(
        '${tempDir.path}${Platform.pathSeparator}script_recast'
        '${Platform.pathSeparator}cache',
      )
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.json'))
          .length,
      1,
    );
  });

  test('loads a single script recast cache without scanning sibling files',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    const scriptId = 'script-target-cache';

    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: scriptId,
        scriptName: 'Target Cache',
        sourceRootPath: r'C:\scripts\target',
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 6, 8),
        mapping: RecastMapping.defaults(scriptId),
      ),
    );
    await File(
      '${tempDir.path}${Platform.pathSeparator}script_recast'
      '${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}unrelated-corrupt.json',
    ).writeAsString('{ not json');

    final cache = await service.loadRecastScriptCache(scriptId);

    expect(cache, isNotNull);
    expect(cache!.scriptId, scriptId);
    expect(cache.scriptName, 'Target Cache');
  });

  test('restores a single script snapshot without returning the raw snapshot',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    const scriptId = 'script-direct-snapshot-restore';
    final script = Script(
      id: scriptId,
      name: 'Direct Snapshot Restore',
      rootPath: r'C:\scripts\direct-snapshot',
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: r'C:\scripts\direct-snapshot\001.json',
          rawJson: '{"prompt":"artist:direct"}',
          parsed: const ParsedFrame(baseCaption: 'artist:direct'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      detectedSchema: ScriptSchema.baseInline,
    );
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: scriptId,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 6, 27),
        mapping: RecastMapping.defaults(scriptId),
        scriptSnapshot: script.toJson(),
      ),
    );

    final restored = await service.restoreRecastScriptCacheSnapshot(
      scriptId: scriptId,
    );

    expect(restored, isNotNull);
    expect(restored!.cache.scriptId, scriptId);
    expect(restored.cache.scriptSnapshot, isEmpty);
    expect(restored.script.name, 'Direct Snapshot Restore');
    expect(restored.script.frames.single.parsed.baseCaption, 'artist:direct');
  });

  test('compacts heavy reference payloads when saving script recast caches',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final heavyReference = _heavyReferencePayload();

    await service.saveRecastScriptCache(
      _bloatedRecastScriptCache('script-heavy-save', heavyReference),
    );

    final cacheFile = await Directory(
      '${tempDir.path}${Platform.pathSeparator}script_recast'
      '${Platform.pathSeparator}cache',
    )
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .single;
    final rawText = await cacheFile.readAsString();
    final cache = await service.loadRecastScriptCache('script-heavy-save');
    final frame = Script.fromJson(cache!.scriptSnapshot).frames.single;
    final comment =
        jsonDecode(frame.parsed.sourcePayload['Comment'] as String) as Map;

    expect(rawText.contains(heavyReference), isFalse);
    expect(rawText.contains('reference_image_multiple'), isFalse);
    expect(frame.rawJson.contains(heavyReference), isFalse);
    expect(frame.parsed.generationParams['seed'], 123456);
    expect(frame.parsed.generationParams.containsKey('reference_strength'),
        isFalse);
    expect(comment['prompt'], 'artist:test, scenic lighting');
    expect(comment.containsKey('reference_image_multiple'), isFalse);
  });

  test('compacts legacy heavy script recast cache files while loading',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final heavyReference = _heavyReferencePayload();
    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}script_recast'
      '${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}legacy-heavy.json',
    );
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _bloatedRecastScriptCache(
          'script-heavy-load',
          heavyReference,
        ).toJson(),
      ),
    );
    final beforeBytes = await cacheFile.length();

    final caches = await service.loadRecastScriptCaches();

    final afterBytes = await cacheFile.length();
    final rawText = await cacheFile.readAsString();
    final frame = Script.fromJson(caches.single.scriptSnapshot).frames.single;
    final sourcePayload = frame.parsed.sourcePayload;
    final comment = jsonDecode(sourcePayload['Comment'] as String) as Map;
    expect(afterBytes, lessThan(beforeBytes));
    expect(rawText.contains(heavyReference), isFalse);
    expect(rawText.contains('reference_image_multiple'), isFalse);
    expect(sourcePayload['Description'], 'artist:test, scenic lighting');
    expect(sourcePayload.containsKey('reference_image_multiple'), isFalse);
    expect(comment['seed'], 123456);
    expect(comment.containsKey('reference_strength_multiple'), isFalse);
  });

  test(
      'writes lightweight script exhibition index without heavy frame payloads',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final heavyReference = _heavyReferencePayload();
    await service.saveRecastScriptCache(
      _bloatedRecastScriptCache('script-exhibition-index', heavyReference),
    );

    final scripts = await service.loadRecastExhibitionScripts();

    expect(scripts, hasLength(1));
    final script = scripts.single;
    expect(script.scriptId, 'script-exhibition-index');
    expect(script.frames.single.prompt, 'artist:test, scenic lighting');
    expect(script.frames.single.generationParams['seed'], 123456);
    expect(script.frames.single.generationParams['width'], 832);
    final indexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionIndex.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    expect(await indexFile.exists(), isTrue);
    final rawIndex = await indexFile.readAsString();
    expect(rawIndex, isNot(contains(heavyReference)));
    expect(rawIndex, isNot(contains('rawJson')));
    expect(rawIndex, isNot(contains('sourcePayload')));
    expect(rawIndex, contains('"generationParams"'));
    expect(rawIndex, contains('"seed":123456'));
  });

  test('loads script exhibition summaries without parsing full snapshots',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final heavyReference = _heavyReferencePayload();
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: 'script-exhibition-summary',
        scriptName: 'Summary Recast Cache',
        sourceRootPath: r'C:\scripts\summary',
        sourceFingerprint:
            r'script-exhibition-summary|C:\scripts\summary|1:001.json:C:\scripts\summary\001.json:hash',
        sourceContentFingerprint: 'content-fingerprint',
        updatedAt: DateTime.utc(2026, 6, 10),
        mapping: RecastMapping.defaults('script-exhibition-summary'),
        scriptSnapshot: _bloatedRecastScript(
          'script-exhibition-summary',
          heavyReference,
        ).toJson(),
      ),
    );

    final scripts = await service.loadRecastExhibitionSummaries();

    expect(scripts, hasLength(1));
    final script = scripts.single;
    expect(script.scriptId, 'script-exhibition-summary');
    expect(script.summaryOnly, isTrue);
    expect(script.displayFrameCount, 1);
    expect(script.frames.single.sourcePath, r'C:\scripts\summary\001.json');
    expect(script.frames.single.prompt, isEmpty);
    final indexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionSummaryIndex.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    expect(await indexFile.exists(), isTrue);
    final rawIndex = await indexFile.readAsString();
    expect(rawIndex, isNot(contains(heavyReference)));
    expect(rawIndex, isNot(contains('artist:test, scenic lighting')));
    expect(rawIndex, isNot(contains('rawJson')));
    expect(rawIndex, isNot(contains('scriptSnapshot')));
  });

  test('keeps script exhibition categories in summary indexes', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final heavyReference = _heavyReferencePayload();
    final baseScript = _bloatedRecastScript(
      'script-exhibition-categorized-summary',
      heavyReference,
    );
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: 'script-exhibition-categorized-summary',
        scriptName: 'Categorized Summary Recast Cache',
        sourceRootPath: r'C:\scripts\categorized',
        sourceFingerprint:
            r'script-exhibition-categorized-summary|C:\scripts\categorized|1:001.json:C:\scripts\categorized\001.json:hash',
        sourceContentFingerprint: 'content-fingerprint',
        updatedAt: DateTime.utc(2026, 6, 10),
        mapping: RecastMapping.defaults(
          'script-exhibition-categorized-summary',
        ),
        scriptSnapshot: Script(
          id: baseScript.id,
          name: baseScript.name,
          rootPath: baseScript.rootPath,
          frames: baseScript.frames,
          detectedSchema: baseScript.detectedSchema,
          parseWarnings: baseScript.parseWarnings,
          meta: const {
            'legacyCategoryNames': ['NTR', 'QAQ'],
          },
        ).toJson(),
      ),
    );

    final scripts = await service.loadRecastExhibitionSummaries();

    expect(scripts, hasLength(1));
    expect(scripts.single.categoryNames, ['NTR', 'QAQ']);
    final indexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionSummaryIndex.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    expect(await indexFile.exists(), isTrue);
    final rawIndex = await indexFile.readAsString();
    expect(rawIndex, contains('"categoryNames":["NTR","QAQ"]'));
    expect(rawIndex, isNot(contains('scriptSnapshot')));
  });

  test('batch recast cache updates invalidate exhibition indexes', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: 'batch-cache-a',
        scriptName: 'Batch Cache A',
        sourceRootPath: r'C:\scripts\a',
        sourceFingerprint: 'a',
        updatedAt: DateTime.utc(2026, 6, 10),
        mapping: RecastMapping.defaults('batch-cache-a'),
      ),
    );
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: 'batch-cache-b',
        scriptName: 'Batch Cache B',
        sourceRootPath: r'C:\scripts\b',
        sourceFingerprint: 'b',
        updatedAt: DateTime.utc(2026, 6, 10),
        mapping: RecastMapping.defaults('batch-cache-b'),
      ),
    );
    final indexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionIndex.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    final summaryIndexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionSummaryIndex.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    await indexFile.parent.create(recursive: true);
    await indexFile.writeAsString('stale');
    await summaryIndexFile.writeAsString('stale');

    await service.saveRecastScriptCacheUpdates([
      RecastScriptCache(
        scriptId: 'batch-cache-a',
        scriptName: 'Batch Cache A',
        sourceRootPath: r'C:\scripts\a',
        sourceFingerprint: 'a',
        updatedAt: DateTime.utc(2026, 6, 11),
        mapping: RecastMapping.defaults('batch-cache-a'),
        exhibitionCategoryNames: const ['QAQ'],
      ),
      RecastScriptCache(
        scriptId: 'batch-cache-b',
        scriptName: 'Batch Cache B',
        sourceRootPath: r'C:\scripts\b',
        sourceFingerprint: 'b',
        updatedAt: DateTime.utc(2026, 6, 11),
        mapping: RecastMapping.defaults('batch-cache-b'),
        exhibitionCategoryNames: const ['QAQ'],
      ),
    ]);

    expect(await indexFile.exists(), isFalse);
    expect(await summaryIndexFile.exists(), isFalse);
    expect(
      (await service.loadRecastScriptCache('batch-cache-a'))!
          .exhibitionCategoryNames,
      ['QAQ'],
    );
    expect(
      (await service.loadRecastScriptCache('batch-cache-b'))!
          .exhibitionCategoryNames,
      ['QAQ'],
    );
  });

  test('script exhibition summary index stores resolved first-frame sidecar',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final sourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}source-script',
    );
    await sourceDir.create(recursive: true);
    final sourceJson = File(
      '${sourceDir.path}${Platform.pathSeparator}001.json',
    );
    final sourceImage = File(
      '${sourceDir.path}${Platform.pathSeparator}001.png',
    );
    await sourceJson.writeAsString('{}');
    await sourceImage.writeAsBytes(const [0, 1, 2, 3]);
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: 'script-summary-sidecar',
        scriptName: 'Summary Sidecar Cache',
        sourceRootPath: sourceDir.path,
        sourceFingerprint:
            'script-summary-sidecar|${sourceDir.path}|1:001.json:${sourceJson.path}:hash',
        sourceContentFingerprint: 'content-fingerprint',
        updatedAt: DateTime.utc(2026, 6, 10),
        mapping: RecastMapping.defaults('script-summary-sidecar'),
        scriptSnapshot: const {},
      ),
    );

    final scripts = await service.loadRecastExhibitionSummaries();

    expect(scripts, hasLength(1));
    expect(
      _normalizedTestPath(scripts.single.frames.single.sourcePath),
      _normalizedTestPath(sourceJson.path),
    );
    expect(
      _normalizedTestPath(scripts.single.frames.single.sourceImagePath),
      _normalizedTestPath(sourceImage.path),
    );
    final indexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionSummaryIndex.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    final rawIndex = await indexFile.readAsString();
    expect(rawIndex, contains(sourceImage.path.replaceAll(r'\', r'\\')));
  });

  test('script exhibition summary accepts canonical recast source fingerprint',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final sourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}canonical-source-script',
    );
    await sourceDir.create(recursive: true);
    final sourceJson = File(
      '${sourceDir.path}${Platform.pathSeparator}001.json',
    );
    final sourceImage = File(
      '${sourceDir.path}${Platform.pathSeparator}001.png',
    );
    await sourceJson.writeAsString('{"Description":"artist:test"}');
    await sourceImage.writeAsBytes(const [0, 1, 2, 3]);
    final script = Script(
      id: 'script-canonical-summary',
      name: 'Canonical Summary Cache',
      rootPath: sourceDir.path,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: sourceJson.path,
          rawJson: await sourceJson.readAsString(),
          parsed: const ParsedFrame(baseCaption: 'artist:test'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      detectedSchema: ScriptSchema.baseInline,
    );
    const cacheRestoreService = ScriptRecastCacheRestoreService();
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: cacheRestoreService.sourceFingerprint(script),
        sourceContentFingerprint:
            cacheRestoreService.sourceContentFingerprint(script),
        updatedAt: DateTime.utc(2026, 6, 21),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: script.toJson(),
      ),
    );

    final scripts = await service.loadRecastExhibitionSummaries();

    expect(scripts, hasLength(1));
    expect(
      _normalizedTestPath(scripts.single.frames.single.sourcePath),
      _normalizedTestPath(sourceJson.path),
    );
    expect(
      _normalizedTestPath(scripts.single.frames.single.sourceImagePath),
      _normalizedTestPath(sourceImage.path),
    );
  });

  test(
      'script exhibition summary keeps snapshot source image when fingerprint path is stale',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final currentSourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}current-source-script',
    );
    await currentSourceDir.create(recursive: true);
    final sourceImage = File(
      '${currentSourceDir.path}${Platform.pathSeparator}p000.png',
    );
    await sourceImage.writeAsBytes(const [0, 1, 2, 3]);
    final staleSourcePath = [
      tempDir.path,
      'missing-source-script',
      'p000.json',
    ].join(Platform.pathSeparator);
    final script = Script(
      id: 'script-summary-stale-source-image',
      name: 'Stale Source Image Summary Cache',
      rootPath: currentSourceDir.path,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: 'p000.json',
          sourcePath: staleSourcePath,
          sourceImagePath: sourceImage.path,
          rawJson: '{"Description":"artist:test"}',
          parsed: const ParsedFrame(baseCaption: 'artist:test'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      detectedSchema: ScriptSchema.baseInline,
    );
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath:
            '${tempDir.path}${Platform.pathSeparator}missing-source-script',
        sourceFingerprint:
            '${script.id}|${tempDir.path}${Platform.pathSeparator}missing-source-script|'
            '1:p000.json:$staleSourcePath:hash',
        sourceContentFingerprint: 'content-fingerprint',
        updatedAt: DateTime.utc(2026, 6, 21),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: script.toJson(),
      ),
    );

    final scripts = await service.loadRecastExhibitionSummaries();

    expect(scripts, hasLength(1));
    expect(
      _normalizedTestPath(scripts.single.frames.single.sourceImagePath),
      _normalizedTestPath(sourceImage.path),
    );
  });

  test('script exhibition rebinds moved premium source roots', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    const scriptTitle = '敗北ヒロイン ペコリーヌ (前)_合并5个图集';
    final oldSourceDir = Directory(
      [
        tempDir.path,
        '作品集',
        'NTR故事集',
        scriptTitle,
      ].join(Platform.pathSeparator),
    );
    final currentSourceDir = Directory(
      [
        tempDir.path,
        '作品集',
        '带图精品',
        'NTR故事集',
        scriptTitle,
      ].join(Platform.pathSeparator),
    );
    await currentSourceDir.create(recursive: true);
    final imageName = '${scriptTitle}_p1.png';
    final currentImage = File(
      '${currentSourceDir.path}${Platform.pathSeparator}$imageName',
    );
    await currentImage.writeAsBytes(const [0, 1, 2, 3]);
    final staleImagePath =
        '${oldSourceDir.path}${Platform.pathSeparator}$imageName';
    const scriptId = 'script-moved-premium-root';
    final script = Script(
      id: scriptId,
      name: scriptTitle,
      rootPath: oldSourceDir.path,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: imageName,
          sourcePath: staleImagePath,
          sourceImagePath: staleImagePath,
          rawJson: '',
          parsed: const ParsedFrame(baseCaption: 'artist:test'),
          detectedSchema: ScriptSchema.v4Partial,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      detectedSchema: ScriptSchema.v4Partial,
    );
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: scriptId,
        scriptName: scriptTitle,
        sourceRootPath: oldSourceDir.path,
        sourceFingerprint:
            '$scriptId|${oldSourceDir.path}|1:$imageName:$staleImagePath:hash',
        sourceContentFingerprint: 'content-fingerprint',
        updatedAt: DateTime.utc(2026, 6, 28),
        mapping: RecastMapping.defaults(scriptId),
        scriptSnapshot: script.toJson(),
      ),
    );

    final summaries = await service.loadRecastExhibitionSummaries();
    final summary = summaries.single;

    expect(
      _normalizedTestPath(summary.sourceRootPath),
      _normalizedTestPath(currentSourceDir.path),
    );
    expect(
      _normalizedTestPath(summary.frames.single.sourcePath),
      _normalizedTestPath(currentImage.path),
    );
    expect(
      _normalizedTestPath(summary.frames.single.sourceImagePath),
      _normalizedTestPath(currentImage.path),
    );

    final detail = await service.loadRecastExhibitionScript(scriptId);

    expect(detail, isNotNull);
    expect(
      _normalizedTestPath(detail!.sourceRootPath),
      _normalizedTestPath(currentSourceDir.path),
    );
    expect(
      _normalizedTestPath(detail.frames.single.sourcePath),
      _normalizedTestPath(currentImage.path),
    );
    expect(
      _normalizedTestPath(detail.frames.single.sourceImagePath),
      _normalizedTestPath(currentImage.path),
    );
  });

  test('script exhibition rebinds renamed images inside existing source roots',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    const scriptTitle = 'クルミ - サレンディア 売春_合并4个图集';
    final sourceDir = Directory(
      [
        tempDir.path,
        'NTR故事集',
        scriptTitle,
      ].join(Platform.pathSeparator),
    );
    await sourceDir.create(recursive: true);
    final currentImage = File(
      '${sourceDir.path}${Platform.pathSeparator}クルミ - サレンディア 売春_p1.png',
    );
    await currentImage.writeAsBytes(const [0, 1, 2, 3]);
    final staleImagePath =
        '${sourceDir.path}${Platform.pathSeparator}${scriptTitle}_p1.png';
    const scriptId = 'script-renamed-source-image';
    final script = Script(
      id: scriptId,
      name: scriptTitle,
      rootPath: sourceDir.path,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '${scriptTitle}_p1.png',
          sourcePath: staleImagePath,
          sourceImagePath: staleImagePath,
          rawJson: '',
          parsed: const ParsedFrame(baseCaption: 'artist:test'),
          detectedSchema: ScriptSchema.v4Partial,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      detectedSchema: ScriptSchema.v4Partial,
    );
    await service.saveRecastScriptCache(
      RecastScriptCache(
        scriptId: scriptId,
        scriptName: scriptTitle,
        sourceRootPath: sourceDir.path,
        sourceFingerprint:
            '$scriptId|${sourceDir.path}|1:${scriptTitle}_p1.png:$staleImagePath:hash',
        sourceContentFingerprint: 'content-fingerprint',
        updatedAt: DateTime.utc(2026, 6, 28),
        mapping: RecastMapping.defaults(scriptId),
        scriptSnapshot: script.toJson(),
      ),
    );

    final summary = (await service.loadRecastExhibitionSummaries()).single;

    expect(
      _normalizedTestPath(summary.frames.single.sourcePath),
      _normalizedTestPath(currentImage.path),
    );
    expect(
      _normalizedTestPath(summary.frames.single.sourceImagePath),
      _normalizedTestPath(currentImage.path),
    );
  });

  test('rebuilds stale script exhibition summary index when cache files change',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final heavyReference = _heavyReferencePayload();
    await service.saveRecastScriptCache(
      _bloatedRecastScriptCache('script-summary-stale-a', heavyReference),
    );
    final initialScripts = await service.loadRecastExhibitionSummaries();
    expect(initialScripts.map((script) => script.scriptId), [
      'script-summary-stale-a',
    ]);
    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}script_recast'
      '${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}script-summary-stale-b.json',
    );
    await cacheFile.writeAsString(
      jsonEncode(
        _bloatedRecastScriptCache(
          'script-summary-stale-b',
          heavyReference,
        ).toJson(),
      ),
    );

    final rebuiltScripts = await service.loadRecastExhibitionSummaries();

    expect(rebuiltScripts.map((script) => script.scriptId), [
      'script-summary-stale-a',
      'script-summary-stale-b',
    ]);
    final indexFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.scriptRecastExhibitionSummaryIndex.replaceAll(
        '/',
        Platform.pathSeparator,
      )}',
    );
    final rawIndex = await indexFile.readAsString();
    expect(rawIndex, contains('script-summary-stale-b'));
    expect(rawIndex, isNot(contains(heavyReference)));
  });

  test('quarantines empty script recast cache files while loading', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}script_recast'
      '${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}empty-cache.json',
    );
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString('');

    final caches = await service.loadRecastScriptCaches();

    expect(caches, isEmpty);
    expect(await cacheFile.exists(), isFalse);
    final invalidDirectory = Directory(
      '${tempDir.path}${Platform.pathSeparator}script_recast'
      '${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}_invalid',
    );
    final invalidFiles = await invalidDirectory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
    expect(invalidFiles, hasLength(1));
    expect(invalidFiles.single.path, endsWith('empty-cache.json'));
  });

  test('repairs legacy script recast caches with unescaped backslashes',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}script_recast'
      '${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}legacy-path-cache.json',
    );
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(r'''
{
  "scriptId": "legacy-path-cache",
  "scriptName": "Legacy Path Cache",
  "sourceRootPath": "E:\legacy\bad-path",
  "sourceFingerprint": "E:\legacy\bad-path|1",
  "sourceContentFingerprint": "content-fingerprint",
  "updatedAt": "2026-06-10T00:00:00.000Z",
  "mapping": {
    "id": "mapping-legacy-path-cache",
    "scriptId": "legacy-path-cache"
  },
  "scriptSnapshot": {}
}
''');

    final caches = await service.loadRecastScriptCaches();

    expect(caches, hasLength(1));
    expect(caches.single.sourceRootPath, r'E:\legacy\bad-path');
    final rewritten = jsonDecode(await cacheFile.readAsString()) as Map;
    expect(rewritten['sourceRootPath'], r'E:\legacy\bad-path');
    expect(rewritten['sourceFingerprint'], r'E:\legacy\bad-path|1');
  });

  test('quarantines empty tokenizer script files while loading', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final scriptFile = File(
      '${tempDir.path}${Platform.pathSeparator}tokenizer_scripts'
      '${Platform.pathSeparator}scripts'
      '${Platform.pathSeparator}empty-script.json',
    );
    await scriptFile.parent.create(recursive: true);
    await scriptFile.writeAsString('');

    final scripts = await service.loadTokenizerScripts();

    expect(scripts, isEmpty);
    expect(await scriptFile.exists(), isFalse);
    final invalidDirectory = Directory(
      '${tempDir.path}${Platform.pathSeparator}tokenizer_scripts'
      '${Platform.pathSeparator}scripts'
      '${Platform.pathSeparator}_invalid',
    );
    final invalidFiles = await invalidDirectory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
    expect(invalidFiles, hasLength(1));
    expect(invalidFiles.single.path, endsWith('empty-script.json'));
  });

  test('migrates legacy tokenizer scripts into recast caches and clears them',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final source = TokenizerSourceFile(
      fileId: 'source-1',
      fileName: '001.json',
      path: r'C:\stories\legacy\001.json',
      kind: TokenizerScriptSourceKind.json,
      defaultImagePath: r'C:\stories\legacy\001.png',
      modifiedAt: DateTime.utc(2026, 6, 1),
    );
    await service.saveTokenizerScripts([
      TokenizerScript(
        scriptId: 'legacy-script',
        name: 'Legacy Script',
        sourceFolder: r'C:\stories\legacy',
        sourceMode: TokenizerScriptSourceMode.auto,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 2),
        status: TokenizerScriptStatus.ready,
        sourceFiles: [source],
        sampleFileIds: const ['source-1'],
        characterIdentities: const [],
        styleStages: const [],
        knowledgeCandidates: const [],
        imageTasks: [
          TokenizerImageTask(
            taskId: 'task-1',
            sourceFile: source,
            parseStatus: 'parsed',
            originalPrompt: 'legacy prompt',
            promptMode: TokenizerScriptPromptMode.tag,
            parsedPrompt: 'legacy prompt',
            finalPrompt: 'legacy prompt, [画师串]',
            artistEvidence: const ['artist:ahemaru'],
            characterSlotMatches: const [],
            resolution: '832x1216',
            generationParams: const {'width': 832, 'height': 1216},
            confidence: 0.9,
            reviewStatus: TokenizerTaskReviewStatus.confirmed,
            details: const TokenizerParseDetails(sceneTags: ['rain']),
          ),
        ],
        imageAttachments: [
          TokenizerScriptImageAttachment(
            attachmentId: 'attachment-1',
            imagePath: r'C:\stories\legacy\alt-001.png',
            label: 'Alt frame',
            versionId: 'script-image-version-1',
            versionLabel: 'Imported Image 1',
            frameIndex: 1,
            sourceFileName: '001.json',
            prompt: 'legacy attachment prompt',
            createdAt: DateTime.utc(2026, 6, 2, 1),
          ),
        ],
      ),
    ]);

    final caches = await service.loadRecastScriptCaches();

    expect(caches, hasLength(1));
    final cache = caches.single;
    expect(cache.scriptId, 'legacy-script');
    expect(cache.scriptName, 'Legacy Script');
    expect(cache.sourceRootPath, r'C:\stories\legacy');
    final snapshot = Script.fromJson(cache.scriptSnapshot);
    expect(snapshot.frames.single.sourcePath, r'C:\stories\legacy\001.json');
    expect(
      snapshot.frames.single.sourceImagePath,
      r'C:\stories\legacy\001.png',
    );
    expect(snapshot.frames.single.parsed.baseCaption, 'legacy prompt');
    final attachments = snapshot.meta['legacyImageAttachments'] as List;
    expect(attachments, hasLength(1));
    final attachment = attachments.single as Map;
    expect(attachment['attachmentId'], 'attachment-1');
    expect(attachment['imagePath'], r'C:\stories\legacy\alt-001.png');
    expect(attachment['prompt'], 'legacy attachment prompt');
    expect(await service.loadTokenizerScripts(), isEmpty);
  });

  test('openWorkspace backfills script recast files for legacy workspaces',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final knowledgeFile = File(
      '${tempDir.path}${Platform.pathSeparator}script_recast${Platform.pathSeparator}knowledge.json',
    );
    final cacheDirectory = Directory(
      '${tempDir.path}${Platform.pathSeparator}script_recast${Platform.pathSeparator}cache',
    );
    await knowledgeFile.delete();
    await cacheDirectory.delete(recursive: true);

    final reopened = WorkspaceService();
    await reopened.openWorkspace(tempDir.path);

    expect(await reopened.loadRecastKnowledgeBase(), isEmpty);
    expect(await knowledgeFile.exists(), isTrue);
    expect(await cacheDirectory.exists(), isTrue);
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

  test('writes and reads local prompt chunks', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);

    await service.savePromptChunks([
      const PromptChunkEntry(
        id: 'chunk-1',
        name: 'Hair randomizer',
        prompt: '||red hair|blue hair|green hair||',
        negativePrompt: 'bad hair',
        tags: ['hair', 'randomizer'],
      ),
    ]);

    final chunks = await service.loadPromptChunks();

    expect(chunks, hasLength(1));
    expect(chunks.single.name, 'Hair randomizer');
    expect(chunks.single.prompt, '||red hair|blue hair|green hair||');
    expect(chunks.single.insertIntoPrompt('1girl'),
        '1girl, ||red hair|blue hair|green hair||');
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
        payload: {
          'graph': {'nodes': 4}
        },
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
        payload: {
          'blocks': ['style', 'scene']
        },
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

  test('loads large production directories and quarantines invalid plan files',
      () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path);
    final now = DateTime.parse('2026-06-19T08:00:00Z');
    final older = now.subtract(const Duration(days: 1));
    final recentPlan = ProductionPlan(
      id: 'recent-large',
      name: 'Recent large queue',
      createdAt: now,
      updatedAt: now,
      tasks: [
        for (var index = 0; index < 80; index += 1)
          ProductionTask.scriptRecastFrame(
            id: 'task-$index',
            planId: 'recent-large',
            title: 'Frame $index',
            scriptId: 'script-large',
            scriptName: 'Large Script',
            scriptPath: r'C:\stories\large',
            recastRunId: 'run-large',
            frameIndex: index + 1,
            sourceFileName: 'frame-$index.json',
            payload: {
              'input': 'prompt $index',
              'parameters': {'seed': index},
            },
            status: ProductionTaskStatus.queued,
            createdAt: now,
            updatedAt: now,
          ),
      ],
    );
    final olderPlan = ProductionPlan(
      id: 'older-small',
      name: 'Older queue',
      createdAt: older,
      updatedAt: older,
      tasks: [
        ProductionTask.scriptRecastFrame(
          id: 'old-task',
          planId: 'older-small',
          title: 'Old frame',
          scriptId: 'script-old',
          recastRunId: 'run-old',
          frameIndex: 1,
          sourceFileName: 'old.json',
          payload: const {'input': 'old prompt'},
          status: ProductionTaskStatus.completed,
          createdAt: older,
          updatedAt: older,
        ),
      ],
    );
    await service.saveProductionPlans([olderPlan, recentPlan]);
    final invalidPath = WorkspacePaths.productionPlanFile(
      'broken-plan',
    ).replaceAll('/', Platform.pathSeparator);
    await File(
      '${tempDir.path}${Platform.pathSeparator}$invalidPath',
    ).writeAsString('{broken json');

    final plans = await service.loadProductionPlans();

    expect(plans, hasLength(2));
    expect(plans.first.id, 'older-small');
    expect(plans.last.id, 'recent-large');
    expect(plans.last.tasks, hasLength(80));
    expect(
      File('${tempDir.path}${Platform.pathSeparator}$invalidPath').existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${tempDir.path}${Platform.pathSeparator}'
        '${WorkspacePaths.deterministicPlansDir.replaceAll('/', Platform.pathSeparator)}'
        '${Platform.pathSeparator}_invalid',
      ).listSync().whereType<File>().map((file) => file.path),
      isNotEmpty,
    );
  });

  test(
    'retries production plan replacement while the target file is locked',
    () async {
      final service = WorkspaceService();
      await service.createWorkspace(tempDir.path);
      final now = DateTime.utc(2026, 6, 26, 8);
      final initialPlan = ProductionPlan(
        id: 'locked-plan',
        name: 'Locked plan',
        tasks: [
          ProductionTask.manualSingleFrame(
            id: 'task-1',
            planId: 'locked-plan',
            title: 'Initial',
            payload: const {'input': 'initial prompt'},
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final updatedPlan = ProductionPlan(
        id: 'locked-plan',
        name: 'Locked plan',
        tasks: [
          ProductionTask.manualSingleFrame(
            id: 'task-1',
            planId: 'locked-plan',
            title: 'Updated',
            payload: const {'input': 'updated prompt'},
            createdAt: now,
            updatedAt: now.add(const Duration(seconds: 1)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      await service.saveProductionPlans([initialPlan]);
      final planFile = File(
        '${tempDir.path}${Platform.pathSeparator}'
        '${WorkspacePaths.productionPlanFile('locked-plan').replaceAll(
          '/',
          Platform.pathSeparator,
        )}',
      );
      final locked = await planFile.open(mode: FileMode.write);
      await locked.lock();
      final saveFuture = service.saveProductionPlans([updatedPlan]);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await locked.unlock();
      await locked.close();
      await saveFuture;

      final loaded = await service.loadProductionPlans();
      expect(loaded.single.tasks.single.title, 'Updated');
    },
    skip: !Platform.isWindows
        ? 'Windows-only regression for transient rename access denial.'
        : null,
  );

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

String _heavyReferencePayload() {
  return List.filled(4096, 'abcd').join();
}

String _normalizedTestPath(String path) =>
    path.replaceAll('\\', '/').toLowerCase();

RecastScriptCache _bloatedRecastScriptCache(
  String scriptId,
  String heavyReference,
) {
  return RecastScriptCache(
    scriptId: scriptId,
    scriptName: 'Heavy Recast Cache',
    sourceRootPath: r'C:\scripts\heavy',
    sourceFingerprint: 'fingerprint',
    sourceContentFingerprint: 'content-fingerprint',
    updatedAt: DateTime.utc(2026, 6, 10),
    mapping: RecastMapping.defaults(scriptId),
    scriptSnapshot: _bloatedRecastScript(scriptId, heavyReference).toJson(),
  );
}

Script _bloatedRecastScript(String scriptId, String heavyReference) {
  final sourcePayload = <String, dynamic>{
    'Description': 'artist:test, scenic lighting',
    'Comment': jsonEncode({
      'prompt': 'artist:test, scenic lighting',
      'seed': 123456,
      'reference_image_multiple': [heavyReference],
      'reference_strength_multiple': [0.6],
      'reference_information_extracted_multiple': [1],
    }),
    'height': 1216,
    'parameters': {
      'sampler': 'k_euler',
      'reference_image_multiple': [heavyReference],
      'reference_strength_multiple': [0.6],
      'reference_information_extracted_multiple': [1],
    },
    'reference_image_multiple': [heavyReference],
    'reference_strength': 0.6,
    'seed': 123456,
    'width': 832,
  };
  return Script(
    id: scriptId,
    name: 'Heavy Recast Cache',
    rootPath: r'C:\scripts\heavy',
    frames: [
      ScriptFrame(
        index: 0,
        fileName: '001.json',
        sourcePath: r'C:\scripts\heavy\001.json',
        rawJson: jsonEncode(sourcePayload),
        parsed: ParsedFrame(
          baseCaption: 'artist:test, scenic lighting',
          generationParams: {
            'height': 1216,
            'reference_image_multiple': [heavyReference],
            'reference_strength': 0.6,
            'seed': 123456,
            'width': 832,
          },
          sourcePayload: sourcePayload,
        ),
        detectedSchema: ScriptSchema.baseInline,
        parseStatus: ScriptFrameParseStatus.parsed,
      ),
    ],
    detectedSchema: ScriptSchema.baseInline,
  );
}
