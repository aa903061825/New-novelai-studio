import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/data/studio/services/tokenizer_script_service.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService workspaceService;
  late TokenizerScriptService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tokenizer-script-test-');
    workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    service = TokenizerScriptService(workspaceService: workspaceService);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates a structured draft with one image task per source', () {
    final script = service.createDraftFromSources(
      name: 'Folder draft',
      sourceFolder: r'C:\shots',
      sources: const [
        TokenizerScriptDraftSource(
          fileName: '001.json',
          path: r'C:\shots\001.json',
          kind: TokenizerScriptSourceKind.json,
          payload: {
            'Description': 'artist:foo, classroom',
            'width': 1024,
            'height': 1536,
            'v4_prompt': {
              'caption': {
                'char_captions': [
                  {
                    'char_caption':
                        'shamare (arknights), white hair, red eyes, black dress, holding book',
                  },
                ],
              },
            },
          },
        ),
        TokenizerScriptDraftSource(
          fileName: '002.json',
          path: r'C:\shots\002.json',
          kind: TokenizerScriptSourceKind.json,
          payload: {
            'Description': '1girl, red eyes, black dress',
            'resolution': '832x1216',
          },
        ),
      ],
    );

    expect(script.imageTasks, hasLength(2));
    expect(script.sourceFiles, hasLength(2));
    expect(
      script.characterIdentities.single.explicitNames,
      contains('shamare (arknights)'),
    );
    expect(script.globalArtistPlaceholder, '[画师串]');
    expect(script.imageTasks.first.finalPrompt, contains('[画师串]'));
    expect(
      script.imageTasks.first.finalPrompt,
      contains('shamare (arknights)'),
    );
    expect(script.imageTasks.first.generationParams['width'], 1024);
    expect(
      (script.imageTasks.first.generationParams['v4_prompt'] as Map)['caption'],
      isA<Map>(),
    );
    expect(
      script.imageTasks.last.reviewStatus,
      TokenizerTaskReviewStatus.needsReview,
    );
    expect(script.status, TokenizerScriptStatus.needsReview);
  });

  test(
    'saving a draft for the same source folder replaces previous script',
    () async {
      final first = service.createDraftFromSources(
        name: 'First folder draft',
        sourceFolder: r'C:\shots',
        sources: const [
          TokenizerScriptDraftSource(
            fileName: '001.json',
            path: r'C:\shots\001.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:first_a, first import'},
          ),
        ],
      );
      await service.saveScript(first);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final second = service.createDraftFromSources(
        name: 'Second folder draft',
        sourceFolder: r'C:/shots/',
        sources: const [
          TokenizerScriptDraftSource(
            fileName: '001.json',
            path: r'C:/shots/001.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:second_a, second import'},
          ),
        ],
      );
      await service.saveScript(second);

      final loaded = await service.loadScripts();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Second folder draft');
      expect(loaded.single.sourceFolder, r'C:/shots/');
      expect(
        loaded.single.imageTasks.single.finalPrompt,
        contains('second import'),
      );
    },
  );

  test(
    'loadScripts prunes legacy duplicates for the same source folder',
    () async {
      final older = service
          .createDraftFromSources(
            name: 'Older folder draft',
            sourceFolder: r'C:\shots',
            sources: const [
              TokenizerScriptDraftSource(
                fileName: '001.json',
                path: r'C:\shots\001.json',
                kind: TokenizerScriptSourceKind.json,
                payload: {'Description': 'artist:older_a, older import'},
              ),
            ],
          )
          .copyWith(
            scriptId: 'legacy-script-old',
            updatedAt: DateTime.parse('2026-06-01T08:00:00Z'),
          );
      final newer = service
          .createDraftFromSources(
            name: 'Newer folder draft',
            sourceFolder: r'C:/shots/',
            sources: const [
              TokenizerScriptDraftSource(
                fileName: '001.json',
                path: r'C:/shots/001.json',
                kind: TokenizerScriptSourceKind.json,
                payload: {'Description': 'artist:newer_a, newer import'},
              ),
            ],
          )
          .copyWith(
            scriptId: 'legacy-script-new',
            updatedAt: DateTime.parse('2026-06-02T08:00:00Z'),
          );
      await workspaceService.saveTokenizerScripts([older, newer]);

      final loaded = await service.loadScripts();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Newer folder draft');
      expect(
        loaded.single.imageTasks.single.finalPrompt,
        contains('newer import'),
      );

      final persisted = await workspaceService.loadTokenizerScripts();
      expect(persisted, hasLength(1));
      expect(persisted.single.scriptId, 'legacy-script-new');
    },
  );

  test(
    'saves reopens and sends draft to production queue with source prompt',
    () async {
      await service.createDemoDraft();

      final loaded = await service.loadScripts();
      expect(loaded, hasLength(1));
      expect(loaded.single.imageTasks, hasLength(3));

      final sent = await service.sendToProductionQueue(loaded.single);
      expect(sent.status, TokenizerScriptStatus.sent);
      expect(sent.sendRecords.single.taskCount, 3);

      final plans = await workspaceService.loadBatchPlans();
      expect(plans.single.items, hasLength(3));
      expect(plans.single.items.first['prompt'], contains('artist:demo_a'));
      expect(plans.single.items.first['prompt'], isNot(contains('[')));
      expect(plans.single.items.first['placeholderMappings'], isA<List>());
    },
  );

  test(
    'sends production handoff scopes from service-side task selection',
    () async {
      final script = _scriptWithReviewStatuses(
        service.createDraftFromSources(
          name: 'Scoped draft',
          sourceFolder: r'C:\shots',
          sources: _threeSources(),
        ),
        const [
          TokenizerTaskReviewStatus.auto,
          TokenizerTaskReviewStatus.confirmed,
          TokenizerTaskReviewStatus.failed,
        ],
      );
      await service.saveScript(script);

      final confirmed = await service.sendToProductionQueue(
        script,
        scope: 'confirmed',
      );
      expect(confirmed.sendRecords.single.scope, 'confirmed');
      expect(confirmed.sendRecords.single.taskCount, 1);

      final afterConfirmed = await workspaceService.loadBatchPlans();
      expect(afterConfirmed.single.items, hasLength(1));
      expect(
        afterConfirmed.single.items.single['taskId'],
        script.imageTasks[1].taskId,
      );

      await service.sendToProductionQueue(
        script,
        scope: 'selected',
        taskIds: [script.imageTasks[2].taskId, script.imageTasks[0].taskId],
      );
      final afterSelected = await workspaceService.loadBatchPlans();
      expect(afterSelected.last.items, hasLength(1));
      expect(
        afterSelected.last.items.single['taskId'],
        script.imageTasks[0].taskId,
      );

      await service.sendToProductionQueue(
        script,
        scope: 'current',
        taskIds: [script.imageTasks[1].taskId, script.imageTasks[0].taskId],
      );
      final afterCurrent = await workspaceService.loadBatchPlans();
      expect(afterCurrent.last.items.map((item) => item['taskId']), [
        script.imageTasks[0].taskId,
        script.imageTasks[1].taskId,
      ]);
    },
  );

  test('exports sanitized script document and imports it back', () {
    final script = service
        .createDraftFromSources(
          name: 'Export draft',
          sourceFolder: r'C:\secret\shots',
          sources: _threeSources(),
        )
        .copyWith(
          pipelineExportConfig: const {
            'handoff': 'oneImageOneTask',
            'apiKey': 'sk-secret-key',
            'nested': {'Authorization': 'Bearer secret-token', 'safe': 'kept'},
          },
          legacyExportConfig: const {
            'password': 'hunter2',
            'endpoint': 'https://example.invalid',
          },
        );

    final document = service.exportScriptDocument(script);
    final encoded = document.toString();

    expect(document['documentType'], 'naiTokenizerScript');
    expect(document['includeSourceFiles'], isFalse);
    expect((document['script'] as Map)['sourceFiles'], isEmpty);
    expect(encoded, isNot(contains('sk-secret-key')));
    expect(encoded, isNot(contains('secret-token')));
    expect(encoded, isNot(contains('hunter2')));
    expect(encoded, isNot(contains('apiKey')));
    expect(encoded, isNot(contains('Authorization')));
    expect(encoded, contains('oneImageOneTask'));
    expect(encoded, contains('https://example.invalid'));

    final imported = service.importScriptDocument(document);

    expect(imported.name, script.name);
    expect(imported.imageTasks, hasLength(script.imageTasks.length));
    expect(imported.sourceFiles, isEmpty);
    expect(imported.imageTasks.first.sourceFile.path, isEmpty);
    expect(imported.pipelineExportConfig['handoff'], 'oneImageOneTask');
  });

  test(
    'scanDirectory reads json and image files with failures summary',
    () async {
      final sourceDir = await Directory('${tempDir.path}/sources').create();
      await File('${sourceDir.path}/002.json').writeAsString(
        jsonEncode({
          'Description': 'artist:json_a, lantern room',
          'width': 640,
          'height': 960,
        }),
      );
      await File('${sourceDir.path}/001.png').writeAsBytes(
        _pngWithTextChunk({
          'Description': 'artist:png_a, rainy street',
          'width': 832,
          'height': 1216,
        }),
      );
      await File('${sourceDir.path}/broken.json').writeAsString('{broken');
      await File('${sourceDir.path}/ignored.txt').writeAsString('ignore me');

      final result = await service.scanDirectory(sourceDir);

      expect(result.sources.map((source) => source.fileName), [
        '001.png',
        '002.json',
      ]);
      expect(result.totalFilesSeen, 4);
      expect(result.supportedFilesSeen, 3);
      expect(result.jsonCount, 1);
      expect(result.imageCount, 1);
      expect(result.failureCount, 1);
      expect(result.failures.single.fileName, 'broken.json');
      expect(result.warnings, isNotEmpty);
      expect(result.sources.first.kind, TokenizerScriptSourceKind.image);
      expect(result.sources.first.payload, isA<Map<String, dynamic>>());
      expect(
        result.sources.first.payload.toString(),
        isNot(contains('imageBytes')),
      );
    },
  );

  test(
    'image draft sources preserve metadata and parse image metadata',
    () async {
      final sourceDir = await Directory('${tempDir.path}/images').create();
      final imageFile = File('${sourceDir.path}/001.png');
      await imageFile.writeAsBytes(
        _pngWithTextChunk({
          'Description': 'artist:png_a, city bridge',
          'width': 832,
          'height': 1216,
          'v4_prompt': {
            'caption': {
              'char_captions': [
                {
                  'char_caption':
                      'amiya (arknights), brown hair, blue eyes, black coat',
                },
              ],
            },
          },
        }),
      );

      final sources = await service.sourcesFromDirectory(sourceDir);
      final script = service.createDraftFromSources(
        name: 'Image folder',
        sourceFolder: sourceDir.path,
        sources: sources,
      );

      expect(sources.single.payload, isA<Map<String, dynamic>>());
      expect(sources.single.payload.toString(), isNot(contains('imageBytes')));
      expect(script.imageTasks.single.parseStatus, 'parsed');
      expect(script.imageTasks.single.artistEvidence, contains('artist:png_a'));
      expect(script.imageTasks.single.resolution, '832x1216');
      expect(
        script.characterIdentities.single.explicitNames,
        contains('amiya (arknights)'),
      );
    },
  );

  test(
    'pairs same-basename images with json sources as default frame images',
    () {
      final script = service.createDraftFromSources(
        name: 'Paired folder',
        sourceFolder: r'C:\shots',
        sources: const [
          TokenizerScriptDraftSource(
            fileName: 'p000.json',
            path: r'C:\shots\p000.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:json_a, lantern room'},
          ),
          TokenizerScriptDraftSource(
            fileName: 'p000.png',
            path: r'C:\shots\p000.png',
            kind: TokenizerScriptSourceKind.image,
            payload: {'Description': 'artist:png_a, should be preview only'},
          ),
          TokenizerScriptDraftSource(
            fileName: 'p001.json',
            path: r'C:\shots\p001.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:json_b, library'},
          ),
        ],
      );

      expect(script.imageTasks, hasLength(2));
      expect(script.sourceFiles.map((source) => source.fileName), [
        'p000.json',
        'p001.json',
      ]);
      expect(script.sourceFiles.first.defaultImagePath, r'C:\shots\p000.png');
      expect(
        script.imageTasks.first.sourceFile.defaultImagePath,
        r'C:\shots\p000.png',
      );
      expect(script.imageTasks.first.finalPrompt, contains('lantern room'));
      expect(
        script.imageTasks.first.finalPrompt,
        isNot(contains('preview only')),
      );
    },
  );

  test('pairs json and images by numeric sequence when stems differ', () {
    final script = service.createDraftFromSources(
      name: 'Numeric paired folder',
      sourceFolder: r'C:\shots',
      sources: const [
        TokenizerScriptDraftSource(
          fileName: 'scene_001.json',
          path: r'C:\shots\scene_001.json',
          kind: TokenizerScriptSourceKind.json,
          payload: {'Description': 'artist:json_a, first scene'},
        ),
        TokenizerScriptDraftSource(
          fileName: 'render_001.png',
          path: r'C:\shots\render_001.png',
          kind: TokenizerScriptSourceKind.image,
          payload: {'Description': 'artist:png_a, should be preview only'},
        ),
        TokenizerScriptDraftSource(
          fileName: 'scene_002.json',
          path: r'C:\shots\scene_002.json',
          kind: TokenizerScriptSourceKind.json,
          payload: {'Description': 'artist:json_b, second scene'},
        ),
        TokenizerScriptDraftSource(
          fileName: 'render_002.png',
          path: r'C:\shots\render_002.png',
          kind: TokenizerScriptSourceKind.image,
          payload: {'Description': 'artist:png_b, should also be preview only'},
        ),
      ],
    );

    expect(script.imageTasks, hasLength(2));
    expect(script.sourceFiles.map((source) => source.fileName), [
      'scene_001.json',
      'scene_002.json',
    ]);
    expect(script.sourceFiles.map((source) => source.defaultImagePath), [
      r'C:\shots\render_001.png',
      r'C:\shots\render_002.png',
    ]);
    expect(script.imageTasks.first.finalPrompt, contains('first scene'));
    expect(
      script.imageTasks.first.finalPrompt,
      isNot(contains('preview only')),
    );
  });

  test(
    'pairs remaining json and images by natural order when counts match',
    () {
      final script = service.createDraftFromSources(
        name: 'Ordered fallback folder',
        sourceFolder: r'C:\shots',
        sources: const [
          TokenizerScriptDraftSource(
            fileName: 'alpha.json',
            path: r'C:\shots\alpha.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:json_a, alpha scene'},
          ),
          TokenizerScriptDraftSource(
            fileName: 'cover-a.png',
            path: r'C:\shots\cover-a.png',
            kind: TokenizerScriptSourceKind.image,
            payload: {'Description': 'artist:png_a, should be preview only'},
          ),
          TokenizerScriptDraftSource(
            fileName: 'beta.json',
            path: r'C:\shots\beta.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:json_b, beta scene'},
          ),
          TokenizerScriptDraftSource(
            fileName: 'cover-b.png',
            path: r'C:\shots\cover-b.png',
            kind: TokenizerScriptSourceKind.image,
            payload: {
              'Description': 'artist:png_b, should also be preview only',
            },
          ),
        ],
      );

      expect(script.imageTasks, hasLength(2));
      expect(script.sourceFiles.map((source) => source.fileName), [
        'alpha.json',
        'beta.json',
      ]);
      expect(script.sourceFiles.map((source) => source.defaultImagePath), [
        r'C:\shots\cover-a.png',
        r'C:\shots\cover-b.png',
      ]);
    },
  );

  test('loadScripts refreshes saved source file existence', () async {
    final sourceDir = await Directory('${tempDir.path}/existing').create();
    final sourceFile = File('${sourceDir.path}/001.json');
    await sourceFile.writeAsString(
      jsonEncode({'Description': 'artist:exists_a, rooftop'}),
    );
    final sources = await service.sourcesFromDirectory(sourceDir);
    final script = service.createDraftFromSources(
      name: 'Exists check',
      sourceFolder: sourceDir.path,
      sources: sources,
    );
    await service.saveScript(script);

    await sourceFile.delete();
    final loaded = await service.loadScripts();

    expect(loaded.single.sourceFiles.single.exists, isFalse);
    expect(loaded.single.imageTasks.single.sourceFile.exists, isFalse);
  });

  test(
    'adds renames removes and serializes script-scoped image attachments',
    () {
      final now = DateTime.parse('2026-06-03T10:00:00Z');
      final script = service.createDraftFromSources(
        name: 'Attachment script',
        sourceFolder: r'C:\shots',
        sources: const [
          TokenizerScriptDraftSource(
            fileName: 'scene_001.json',
            path: r'C:\shots\scene_001.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:json_a, first scene'},
          ),
          TokenizerScriptDraftSource(
            fileName: 'scene_002.json',
            path: r'C:\shots\scene_002.json',
            kind: TokenizerScriptSourceKind.json,
            payload: {'Description': 'artist:json_b, second scene'},
          ),
        ],
      );

      final attached = service.addImageAttachments(
        script,
        imagePaths: const [
          r'C:\shots\render_001.png',
          r'C:\shots\render_002.png',
        ],
        createdAt: now,
        labelPrefix: 'Default ',
      );

      expect(attached.imageAttachments, hasLength(2));
      expect(attached.imageAttachments.map((attachment) => attachment.label), [
        'Default 1',
        'Default 2',
      ]);
      expect(
        attached.imageAttachments.map((attachment) => attachment.frameIndex),
        [1, 2],
      );
      expect(
        attached.imageAttachments.map(
          (attachment) => attachment.sourceFileName,
        ),
        ['scene_001.json', 'scene_002.json'],
      );

      final renamed = service.renameImageAttachment(
        attached,
        attachmentId: attached.imageAttachments.last.attachmentId,
        label: 'Role swap 2',
      );
      expect(renamed.imageAttachments.last.label, 'Role swap 2');

      final restored = TokenizerScript.fromJson(renamed.toJson());
      expect(restored.imageAttachments.last.label, 'Role swap 2');
      expect(
        restored.imageAttachments.last.imagePath,
        r'C:\shots\render_002.png',
      );

      final removed = service.removeImageAttachment(
        restored,
        attachmentId: restored.imageAttachments.first.attachmentId,
      );
      expect(removed.imageAttachments.map((attachment) => attachment.label), [
        'Role swap 2',
      ]);
    },
  );

  test(
    'review workflow confirms tasks candidates mappings and style stages',
    () {
      final script = _scriptWithReviewStatuses(
        service.createDraftFromSources(
          name: 'Review draft',
          sourceFolder: r'C:\shots',
          sources: const [
            TokenizerScriptDraftSource(
              fileName: '001.json',
              path: r'C:\shots\001.json',
              kind: TokenizerScriptSourceKind.json,
              payload: {
                'Description': 'artist:foo, classroom',
                'v4_prompt': {
                  'caption': {
                    'char_captions': [
                      {
                        'char_caption':
                            '1girl, white hair, red eyes, black dress',
                      },
                    ],
                  },
                },
              },
            ),
            TokenizerScriptDraftSource(
              fileName: '002.json',
              path: r'C:\shots\002.json',
              kind: TokenizerScriptSourceKind.json,
              payload: {'Description': 'artist:bar, library'},
            ),
            TokenizerScriptDraftSource(
              fileName: '003.json',
              path: r'C:\shots\003.json',
              kind: TokenizerScriptSourceKind.json,
              payload: {'Description': 'artist:baz, garden'},
            ),
          ],
        ),
        const [
          TokenizerTaskReviewStatus.needsReview,
          TokenizerTaskReviewStatus.auto,
          TokenizerTaskReviewStatus.auto,
        ],
      );
      final firstTask = script.imageTasks.first;
      final firstMapping = firstTask.placeholderMappings.first;
      final identity = script.characterIdentities.first;

      final confirmed = service.confirmReviewItems(
        script,
        taskIds: [firstTask.taskId],
        candidateIds: [script.knowledgeCandidates.first.candidateId],
      );
      expect(
        confirmed.imageTasks.first.reviewStatus,
        TokenizerTaskReviewStatus.confirmed,
      );
      expect(confirmed.knowledgeCandidates.first.confirmed, isTrue);

      final renamed = service.renameCharacterIdentity(
        confirmed,
        identityId: identity.identityId,
        displayName: 'Amiya',
      );
      expect(renamed.characterIdentities.first.displayName, 'Amiya');
      expect(renamed.characterIdentities.first.placeholder, '[Amiya]');
      expect(renamed.imageTasks.first.finalPrompt, contains('[Amiya上身]'));

      final remapped = service.updateTaskPlaceholderMapping(
        renamed,
        taskId: firstTask.taskId,
        oldPlaceholder: firstMapping.placeholder,
        newPlaceholder: '[AmiyaIdentity]',
        category: 'characterIdentity',
        originalTags: firstMapping.originalTags,
      );
      expect(
        remapped.imageTasks.first.placeholderMappings.any(
          (mapping) => mapping.placeholder == '[AmiyaIdentity]',
        ),
        isTrue,
      );
      expect(
        remapped.imageTasks.first.reviewStatus,
        TokenizerTaskReviewStatus.adjusted,
      );

      final staged = service.addStyleStage(
        remapped,
        identityId: identity.identityId,
        name: 'black dress',
        taskIds: [firstTask.taskId],
        evidenceTags: const ['black dress'],
      );
      expect(staged.styleStages.single.name, 'black dress');
      expect(
        staged.imageTasks.first.styleStageRefs,
        contains(staged.styleStages.single.stageId),
      );
    },
  );

  test('builds prompt workshop preview with tag translations', () async {
    final script = service.createDraftFromSources(
      name: 'Translated script',
      sourceFolder: r'C:\shots',
      sources: const [
        TokenizerScriptDraftSource(
          fileName: '001.json',
          path: r'C:\shots\001.json',
          kind: TokenizerScriptSourceKind.json,
          payload: {'prompt': '1girl, blue eyes, unknown tag'},
        ),
      ],
    );

    final preview = service.buildPromptWorkshopPreview(
      script.imageTasks.single,
    );

    expect(preview.tags.map((tag) => tag.text), [
      '1girl',
      'blue eyes',
      'unknown tag',
    ]);
    expect(preview.tags.map((tag) => tag.translation), ['1个女孩', '蓝眼', '']);
    expect(preview.missingTranslations, ['unknown tag']);
  });

  test('builds prompt workshop preview with missing comma warnings', () {
    const task = TokenizerImageTask(
      taskId: 'task-1',
      sourceFile: TokenizerSourceFile(
        fileId: 'source-1',
        fileName: '001.json',
        path: r'C:\shots\001.json',
        kind: TokenizerScriptSourceKind.json,
      ),
      parseStatus: 'parsed',
      originalPrompt: '1::nose blush:: 2::close-up, male blush, blue eyes',
      promptMode: TokenizerScriptPromptMode.tag,
      parsedPrompt: '',
      finalPrompt: '',
      artistEvidence: [],
      characterSlotMatches: [],
      confidence: 1,
      reviewStatus: TokenizerTaskReviewStatus.auto,
      details: TokenizerParseDetails(),
    );

    final preview = service.buildPromptWorkshopPreview(task);

    expect(preview.tags.map((tag) => tag.text), [
      '1::nose blush::',
      '2::close-up',
      'male blush',
      'blue eyes',
    ]);
    expect(preview.tags[2].warning, WorkshopTagWarning.suspectedMissingComma);
    expect(preview.tags[2].suggestedParts, ['male', 'blush']);
    expect(preview.tags[3].warning, WorkshopTagWarning.none);
  });
}

List<TokenizerScriptDraftSource> _threeSources() {
  return const [
    TokenizerScriptDraftSource(
      fileName: '001.json',
      path: r'C:\shots\001.json',
      kind: TokenizerScriptSourceKind.json,
      payload: {
        'Description': 'artist:foo, classroom',
        'width': 1024,
        'height': 1536,
      },
    ),
    TokenizerScriptDraftSource(
      fileName: '002.json',
      path: r'C:\shots\002.json',
      kind: TokenizerScriptSourceKind.json,
      payload: {
        'Description': 'artist:bar, library',
        'width': 832,
        'height': 1216,
      },
    ),
    TokenizerScriptDraftSource(
      fileName: '003.json',
      path: r'C:\shots\003.json',
      kind: TokenizerScriptSourceKind.json,
      payload: {
        'Description': 'artist:baz, garden',
        'width': 640,
        'height': 960,
      },
    ),
  ];
}

TokenizerScript _scriptWithReviewStatuses(
  TokenizerScript script,
  List<TokenizerTaskReviewStatus> statuses,
) {
  return script.copyWith(
    imageTasks: [
      for (final (index, task) in script.imageTasks.indexed)
        _taskWithReviewStatus(task, statuses[index]),
    ],
  );
}

TokenizerImageTask _taskWithReviewStatus(
  TokenizerImageTask task,
  TokenizerTaskReviewStatus reviewStatus,
) {
  return TokenizerImageTask(
    taskId: task.taskId,
    sourceFile: task.sourceFile,
    parseStatus: task.parseStatus,
    originalPrompt: task.originalPrompt,
    promptMode: task.promptMode,
    parsedPrompt: task.parsedPrompt,
    finalPrompt: task.finalPrompt,
    artistEvidence: task.artistEvidence,
    characterSlotMatches: task.characterSlotMatches,
    resolution: task.resolution,
    coords: task.coords,
    generationParams: task.generationParams,
    confidence: task.confidence,
    warnings: task.warnings,
    reviewStatus: reviewStatus,
    placeholderMappings: task.placeholderMappings,
    styleStageRefs: task.styleStageRefs,
    details: task.details,
  );
}

Uint8List _pngWithTextChunk(Map<String, dynamic> metadata) {
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lhQ3pwAAAABJRU5ErkJggg==',
    ),
  );
  final iendOffset = png.length - 12;
  final keyword = utf8.encode('Comment');
  final text = utf8.encode(jsonEncode(metadata));
  final data = Uint8List.fromList([...keyword, 0, ...text]);
  final type = ascii.encode('tEXt');
  final chunk = BytesBuilder()
    ..add(_uint32(data.length))
    ..add(type)
    ..add(data)
    ..add(_uint32(_crc32([...type, ...data])));
  return Uint8List.fromList([
    ...png.sublist(0, iendOffset),
    ...chunk.toBytes(),
    ...png.sublist(iendOffset),
  ]);
}

Uint8List _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value);
  return data.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
