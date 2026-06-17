import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';

void main() {
  test('loads original exhibition frames from recast script caches', () async {
    final script = Script(
      id: 'recast-script',
      name: '重铸剧本',
      rootPath: r'C:\stories\recast',
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: r'C:\stories\recast\001.png',
          sourceImagePath: r'C:\stories\recast\001.png',
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'recast prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'recast-script',
          scriptName: '重铸剧本',
          sourceRootPath: r'C:\stories\recast',
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('recast-script'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final exhibitionScript = viewModel.snapshot.scripts.single;
    expect(exhibitionScript.scriptId, 'recast-script');
    expect(exhibitionScript.title, '重铸剧本');
    final item = exhibitionScript.versions.single.items.single;
    expect(item.sourceKind, ScriptExhibitionItemSourceKind.original);
    expect(item.sourceFileName, '001.png');
    expect(item.imagePath, r'C:\stories\recast\001.png');
    expect(item.prompt, 'recast prompt');
  });

  test('uses paired sidecar images for recast cache frames', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-sidecar-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final jsonFile = File('${tempDir.path}${Platform.pathSeparator}001.json');
    final imageFile = File('${tempDir.path}${Platform.pathSeparator}001.png');
    await jsonFile.writeAsString('{}');
    await imageFile.writeAsBytes(const [0, 1, 2, 3]);
    final script = Script(
      id: 'sidecar-script',
      name: 'Sidecar Script',
      rootPath: tempDir.path,
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: jsonFile.path,
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'sidecar prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'sidecar-script',
          scriptName: 'Sidecar Script',
          sourceRootPath: tempDir.path,
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('sidecar-script'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.imagePath, imageFile.path);
    expect(item.prompt, 'sidecar prompt');
  });

  test('loads legacy image attachments from recast script caches', () async {
    final attachmentCreatedAt = DateTime.parse('2026-06-04T11:00:00Z');
    final script = Script(
      id: 'recast-script',
      name: 'Recast Script',
      rootPath: r'C:\stories\recast',
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: r'C:\stories\recast\001.json',
          sourceImagePath: r'C:\stories\recast\001.png',
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'source prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      meta: {
        'legacyImageAttachments': [
          TokenizerScriptImageAttachment(
            attachmentId: 'attachment-1',
            imagePath: r'C:\stories\recast\alt-001.png',
            label: 'Alt frame',
            versionId: 'script-image-version-1',
            versionLabel: 'Imported Image 1',
            frameIndex: 1,
            sourceFileName: '001.json',
            prompt: 'attachment prompt',
            createdAt: attachmentCreatedAt,
          ).toJson(),
        ],
      },
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'recast-script',
          scriptName: 'Recast Script',
          sourceRootPath: r'C:\stories\recast',
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('recast-script'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final exhibitionScript = viewModel.snapshot.scripts.single;
    final attachmentVersion = exhibitionScript.versions.singleWhere(
      (version) => version.id == 'script-image-version-1',
    );
    final item = attachmentVersion.items.single;
    expect(item.sourceKind, ScriptExhibitionItemSourceKind.attachment);
    expect(item.imageAttachmentId, 'attachment-1');
    expect(item.imagePath, r'C:\stories\recast\alt-001.png');
    expect(item.prompt, 'attachment prompt');
    expect(item.versionLabel, 'Imported Image 1');
  });

  test('aggregates scripts, production batches, and gallery records', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => [
        _galleryRecord(
          taskId: 'task-archived-only',
          imagePath: r'C:\gallery\frame-archived-only.png',
        ),
      ],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    expect(snapshot.scripts, hasLength(1));
    expect(snapshot.totalScriptCount, 1);
    expect(snapshot.totalImageCount, 4);
    expect(snapshot.generatedImageCount, 2);
    expect(snapshot.needsActionCount, 1);

    final script = snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.title, '雨夜档案');
    expect(script.sourceFolder, r'C:\stories\rain');
    expect(script.versions.map((version) => version.label), [
      '原始剧本',
      '主角版 A',
      '已收纳',
    ]);

    final original = script.versions[0];
    expect(original.items.map((item) => item.frameIndex), [1, 2]);
    expect(original.items.first.sourceKind,
        ScriptExhibitionItemSourceKind.original);

    final batch = script.versions[1];
    expect(batch.items.map((item) => item.title), [
      '新图: 入口雨幕',
      '旧书架前',
    ]);
    expect(batch.items.first.imagePath, r'C:\out\frame-01.png');
    expect(batch.items.first.versionLabel, '主角版 A');
    expect(batch.items.last.sourceKind, ScriptExhibitionItemSourceKind.failed);

    final archived = script.versions[2];
    expect(archived.items.single.sourceKind,
        ScriptExhibitionItemSourceKind.gallery);
    expect(archived.items.single.frameIndex, 1);
  });

  test('chooses a generated image as the script cover before originals',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final cover = viewModel.snapshot.scripts.single.coverItem;
    expect(cover, isNotNull);
    expect(cover!.sourceKind, ScriptExhibitionItemSourceKind.generated);
    expect(cover.imagePath, r'C:\out\frame-01.png');
  });

  test('uses a saved exhibition cover item before automatic cover ranking',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          exhibitionCoverItemId: 'original-script-1-task-2',
        ),
      ],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final script = viewModel.snapshot.scripts.single;
    expect(script.coverItemId, 'original-script-1-task-2');
    final cover = script.coverItem;
    expect(cover, isNotNull);
    expect(cover!.id, 'original-script-1-task-2');
    expect(cover.sourceKind, ScriptExhibitionItemSourceKind.original);
    expect(cover.imagePath, r'C:\stories\rain\002.png');
  });

  test('sets a script cover item through the persistence callback', () async {
    var scripts = [_script()];
    final persistedItems = <ScriptExhibitionItem>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      setCoverItemRecord: (item) async {
        persistedItems.add(item);
        scripts = [
          for (final script in scripts)
            script.scriptId == item.scriptId
                ? script.copyWith(exhibitionCoverItemId: item.id)
                : script,
        ];
      },
    );

    await viewModel.load();
    final item = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'production-plan-hero-a')
        .items
        .first;

    await viewModel.setCoverItem(item);

    expect(persistedItems.single.id, 'production-plan-hero-a-task-generated-1');
    expect(viewModel.snapshot.scripts.single.coverItem?.id,
        'production-plan-hero-a-task-generated-1');
    expect(
      viewModel.focusedItemId,
      'production-plan-hero-a-task-generated-1',
    );
  });

  test('falls back to an original image when a script has no generated cover',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final cover = viewModel.snapshot.scripts.single.coverItem;
    expect(cover, isNotNull);
    expect(cover!.sourceKind, ScriptExhibitionItemSourceKind.original);
    expect(cover.imagePath, r'C:\stories\rain\001.png');
  });

  test('skips gallery records already represented by production tasks',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => [_galleryRecord()],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    final script = snapshot.scripts.single;
    expect(snapshot.totalImageCount, 3);
    expect(snapshot.generatedImageCount, 1);
    final productionItem = script.versions
        .singleWhere((version) => version.id == 'production-plan-hero-a')
        .items
        .first;
    expect(productionItem.galleryRecord?.id, 'gallery-1');
    expect(productionItem.galleryRecordId, isNull);
    expect(
      script.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isFalse,
    );
  });

  test('strips heavy production reference images from exhibition snapshot',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        _plan(
          generatedPayload: {
            'input': 'library entrance, new heroine',
            'parameters': {
              'reference_image_multiple': [
                List.filled(50000, 'x').join(),
              ],
              'reference_strength_multiple': [0.45],
              'v4_prompt': {
                'caption': {
                  'base_caption': 'library entrance',
                  'char_captions': [
                    {'char_caption': 'new heroine'},
                  ],
                },
              },
              'v4_negative_prompt': {
                'caption': {
                  'base_caption': 'low quality',
                },
              },
              'prompt': 'legacy prompt',
              'uc': 'legacy negative',
            },
          },
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final productionItem = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'production-plan-hero-a')
        .items
        .first;
    final payload = productionItem.assetCapturePayload;
    final parameters = payload?['parameters'] as Map<String, dynamic>?;

    expect(productionItem.prompt, contains('library entrance'));
    expect(parameters, isNotNull);
    expect(parameters, isNot(contains('reference_image_multiple')));
    expect(parameters, isNot(contains('reference_strength_multiple')));
    expect(parameters, contains('v4_prompt'));
    expect(parameters, contains('v4_negative_prompt'));
    expect(parameters, contains('prompt'));
    expect(parameters, contains('uc'));
  });

  test('applies custom exhibition version labels', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          exhibitionVersionLabels: const {
            ScriptExhibitionVersion.galleryId: '精选收纳',
          },
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => [
        _galleryRecord(
          taskId: 'task-archived-only',
          imagePath: r'C:\gallery\frame-archived-only.png',
        ),
      ],
    );

    await viewModel.load();

    final galleryVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere(
            (version) => version.id == ScriptExhibitionVersion.galleryId);
    expect(galleryVersion.label, '精选收纳');
    expect(galleryVersion.items.single.versionLabel, '精选收纳');
  });

  test('keeps exhibition usable when gallery records fail to load', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => throw const FormatException(
        'broken gallery index',
      ),
    );

    await viewModel.load();

    expect(viewModel.loadError, isNull);
    final script = viewModel.snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.generatedImageCount, 1);
    expect(
      script.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isFalse,
    );
  });

  test(
      'keeps gallery records when a reused plan task belongs to another script',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        _plan(
          scriptId: 'script-other',
          scriptName: 'Other Script',
          scriptPath: r'C:\stories\other',
        ),
      ],
      loadGalleryRecords: () async => [_galleryRecord()],
    );

    await viewModel.load();

    final originalScript = viewModel.snapshot.scripts
        .singleWhere((script) => script.scriptId == 'script-1');
    expect(originalScript.generatedImageCount, 1);
    expect(
      originalScript.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isTrue,
    );

    final currentPlanScript = viewModel.snapshot.scripts
        .singleWhere((script) => script.scriptId == 'script-other');
    expect(currentPlanScript.generatedImageCount, 1);
  });

  test('creates a synthetic script bucket for production-only results',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => [_plan(scriptId: 'script-missing')],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final script = viewModel.snapshot.scripts.single;
    expect(script.scriptId, 'script-missing');
    expect(script.title, '雨夜档案');
    expect(script.versions.single.label, '主角版 A');
    expect(script.generatedImageCount, 1);
  });

  test('joins production results by source path when script ids differ',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan(scriptId: 'script-regenerated')],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    expect(snapshot.scripts, hasLength(1));
    final script = snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.sourceFolder, r'C:\stories\rain');
    expect(script.versions.map((version) => version.label), [
      '原始剧本',
      '主角版 A',
    ]);
    expect(script.originalCount, 2);
    expect(script.generatedImageCount, 1);
  });

  test('joins production results by unique title and source frame evidence',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        _plan(
          scriptId: 'script-regenerated',
          scriptPath: r'C:\generated\cover-run',
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    expect(snapshot.scripts, hasLength(1));
    final script = snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.sourceFolder, r'C:\stories\rain');
    expect(script.originalCount, 2);
    expect(script.generatedImageCount, 1);
    expect(script.versions.map((version) => version.id), [
      ScriptExhibitionVersion.originalId,
      'production-plan-hero-a',
    ]);
  });

  test('does not join same-title production results without frame evidence',
      () async {
    final now = DateTime.parse('2026-06-02T08:00:00Z');
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        ProductionPlan(
          id: 'plan-manual',
          name: 'Manual run',
          createdAt: now,
          updatedAt: now,
          tasks: [
            ProductionTask(
              id: 'task-manual',
              planId: 'plan-manual',
              taskType: ProductionTaskType.manualSingleFrame,
              title: 'Manual image',
              source: ProductionTaskSource(
                scriptId: 'script-other',
                scriptName: _script().name,
                scriptPath: r'C:\generated\manual-run',
              ),
              payload: const {'input': 'manual output'},
              status: ProductionTaskStatus.completed,
              outputImagePath: r'C:\out\manual.png',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.snapshot.scripts, hasLength(2));
  });

  test('hides source-only scripts without image paths from exhibition',
      () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-source-only',
          name: '源文件剧本',
          sourceFolder: r'C:\stories\source-only',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.parsed,
          sourceFiles: [
            _source(
              'source-only-1',
              '001.json',
              r'C:\stories\source-only\001.json',
            ),
          ],
          sampleFileIds: const ['source-only-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: const [],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.snapshot.scripts, isEmpty);
    expect(viewModel.snapshot.totalScriptCount, 0);
    expect(viewModel.snapshot.totalImageCount, 0);
  });

  test('uses paired sidecar images for tokenizer source files', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-tokenizer-sidecar-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final jsonFile = File('${tempDir.path}${Platform.pathSeparator}001.json');
    final imageFile = File('${tempDir.path}${Platform.pathSeparator}001.png');
    await jsonFile.writeAsString('{}');
    await imageFile.writeAsBytes(const [0, 1, 2, 3]);
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'tokenizer-sidecar',
          name: 'Tokenizer Sidecar',
          sourceFolder: tempDir.path,
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.parsed,
          sourceFiles: [
            _source('source-sidecar', '001.json', jsonFile.path),
          ],
          sampleFileIds: const ['source-sidecar'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: const [],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.imagePath, imageFile.path);
    expect(item.sourceFileName, '001.json');
  });

  test('uses paired source images as original exhibition images', () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final source = _source(
      'source-paired-1',
      'p000.json',
      r'C:\stories\paired\p000.json',
      defaultImagePath: r'C:\stories\paired\p000.png',
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-paired',
          name: '配图剧本',
          sourceFolder: r'C:\stories\paired',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.ready,
          sourceFiles: [source],
          sampleFileIds: const ['source-paired-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: [
            _task(
              id: 'task-paired-1',
              source: source,
              prompt: 'paired json prompt',
              status: TokenizerTaskReviewStatus.confirmed,
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.sourceFileName, 'p000.json');
    expect(item.imagePath, r'C:\stories\paired\p000.png');
  });

  test('labels image-only imported scripts as the default version', () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final source = _source(
      'source-image-only-1',
      'p000.png',
      r'C:\stories\image-only\p000.png',
      kind: TokenizerScriptSourceKind.image,
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-image-only',
          name: 'Image Only',
          sourceFolder: r'C:\stories\image-only',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.ready,
          sourceFiles: [source],
          sampleFileIds: const ['source-image-only-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: [
            _task(
              id: 'task-image-only-1',
              source: source,
              prompt: 'image metadata prompt',
              status: TokenizerTaskReviewStatus.confirmed,
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final version = viewModel.snapshot.scripts.single.versions.single;
    expect(version.id, ScriptExhibitionVersion.originalId);
    expect(version.label, '默认版本');
    expect(version.items.single.versionLabel, '默认版本');
    expect(version.items.single.imagePath, r'C:\stories\image-only\p000.png');
  });

  test('original exhibition items prefer original prompt over final prompt',
      () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final source = _source(
      'source-original-prompt-1',
      'p000.json',
      r'C:\stories\paired\p000.json',
      defaultImagePath: r'C:\stories\paired\p000.png',
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-original-prompt',
          name: 'Original Prompt',
          sourceFolder: r'C:\stories\paired',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.ready,
          sourceFiles: [source],
          sampleFileIds: const ['source-original-prompt-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: [
            _task(
              id: 'task-original-prompt-1',
              source: source,
              prompt: 'artist:ahemaru, year 2025',
              finalPrompt: '[artist-chain], year 2025, [character-lower-body]',
              status: TokenizerTaskReviewStatus.confirmed,
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.prompt, 'artist:ahemaru, year 2025');
    expect(item.prompt, isNot(contains('[artist-chain]')));
  });

  test('ignores legacy unversioned image attachments', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          imageAttachments: [
            TokenizerScriptImageAttachment(
              attachmentId: 'attachment-1',
              imagePath: r'C:\stories\rain\manual_001.png',
              label: 'Default 1',
              frameIndex: 1,
              sourceFileName: '001.json',
              createdAt: DateTime.parse('2026-06-03T10:00:00Z'),
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(
      viewModel.snapshot.scripts.single.versions.any(
        (version) => version.id == 'attachments',
      ),
      isFalse,
    );
    expect(
      viewModel.snapshot.scripts.single.items.any(
        (item) => item.sourceKind == ScriptExhibitionItemSourceKind.attachment,
      ),
      isFalse,
    );
  });

  test('aggregates imported image sequences as separate JSON-backed versions',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          imageAttachments: [
            TokenizerScriptImageAttachment(
              attachmentId: 'version-a-1',
              imagePath: r'C:\stories\rain\version_a_p1.png',
              label: 'Frame 1',
              versionId: 'script-image-version-a',
              versionLabel: '导入图片 1',
              frameIndex: 1,
              sourceFileName: '001.json',
              prompt: 'artist:a, imported json prompt 1',
              payload: const {
                'input': 'artist:a, imported json prompt 1',
                'parameters': {'width': 832, 'height': 1216},
              },
              createdAt: DateTime.parse('2026-06-10T10:00:00Z'),
            ),
            TokenizerScriptImageAttachment(
              attachmentId: 'version-a-2',
              imagePath: r'C:\stories\rain\version_a_p2.png',
              label: 'Frame 2',
              versionId: 'script-image-version-a',
              versionLabel: '导入图片 1',
              frameIndex: 2,
              sourceFileName: '002.json',
              prompt: 'artist:b, imported json prompt 2',
              payload: const {
                'input': 'artist:b, imported json prompt 2',
                'parameters': {'steps': 28},
              },
              createdAt: DateTime.parse('2026-06-10T10:00:01Z'),
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final importedVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'script-image-version-a');

    expect(importedVersion.label, '导入图片 1');
    expect(importedVersion.items.map((item) => item.title), [
      'Frame 1',
      'Frame 2',
    ]);
    expect(importedVersion.items.first.prompt, contains('imported json'));
    expect(importedVersion.items.first.assetCapturePayload?['parameters'], {
      'width': 832,
      'height': 1216,
    });
  });

  test('keeps the newest load result when concurrent loads finish out of order',
      () async {
    final firstCompleter = Completer<List<TokenizerScript>>();
    var requestCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () {
        requestCount += 1;
        if (requestCount == 1) {
          return firstCompleter.future;
        }
        return Future.value([
          _script().copyWith(
            scriptId: 'script-new',
            name: '新剧本',
          ),
        ]);
      },
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    final firstLoad = viewModel.load();
    await viewModel.load();
    firstCompleter.complete([_script()]);
    await firstLoad;

    expect(viewModel.snapshot.scripts.single.scriptId, 'script-new');
  });

  test('ensureLoaded reuses the loaded snapshot until a forced load', () async {
    var requestCount = 0;
    var scripts = [_script()];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async {
        requestCount += 1;
        return scripts;
      },
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.ensureLoaded();
    await viewModel.ensureLoaded();

    expect(requestCount, 1);
    expect(viewModel.snapshot.scripts.single.scriptId, 'script-1');

    scripts = [
      _script().copyWith(
        scriptId: 'script-2',
        name: 'Second script',
      ),
    ];
    await viewModel.load();

    expect(requestCount, 2);
    expect(viewModel.snapshot.scripts.single.scriptId, 'script-2');
  });

  test('deletes gallery-backed items and reloads the snapshot', () async {
    var records = [_galleryRecord()];
    final deletedItemIds = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => records,
      deleteItemRecord: (item) async {
        deletedItemIds.add(item.id);
        records = records
            .where((record) => record.id != item.galleryRecordId)
            .toList(growable: false);
      },
    );

    await viewModel.load();
    final galleryVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere(
            (version) => version.id == ScriptExhibitionVersion.galleryId);
    final galleryItem = galleryVersion.items.single;

    expect(galleryItem.canDelete, isTrue);
    await viewModel.deleteItem(galleryItem);

    expect(deletedItemIds, ['gallery-gallery-1']);
    expect(
      viewModel.snapshot.scripts.single.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isFalse,
    );
  });

  test('imports renames and deletes script-scoped image attachments', () async {
    var scripts = [_script()];
    final importedScripts = <String>[];
    final renamedLabels = <String>[];
    final deletedAttachmentIds = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      importScriptImages: (script) async {
        importedScripts.add(script.scriptId);
        scripts = [
          scripts.single.copyWith(
            imageAttachments: [
              TokenizerScriptImageAttachment(
                attachmentId: 'attachment-1',
                imagePath: r'C:\stories\rain\manual_001.png',
                label: 'Default 1',
                versionId: 'script-image-version-1',
                versionLabel: '导入图片 1',
                prompt: 'artist:manual, imported json prompt',
                createdAt: DateTime.parse('2026-06-03T10:00:00Z'),
              ),
            ],
          ),
        ];
      },
      renameImageAttachment: (item, label) async {
        renamedLabels.add(label);
        scripts = [
          scripts.single.copyWith(
            imageAttachments: [
              TokenizerScriptImageAttachment(
                attachmentId: item.imageAttachmentId!,
                imagePath: item.imagePath,
                label: label,
                versionId: item.versionId,
                versionLabel: item.versionLabel,
                prompt: item.prompt,
                createdAt: item.updatedAt,
              ),
            ],
          ),
        ];
      },
      deleteItemRecord: (item) async {
        deletedAttachmentIds.add(item.imageAttachmentId!);
        scripts = [scripts.single.copyWith(imageAttachments: const [])];
      },
    );

    await viewModel.load();
    await viewModel.importImagesForScript(viewModel.snapshot.scripts.single);
    var attachmentItem = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'script-image-version-1')
        .items
        .single;
    expect(importedScripts, ['script-1']);
    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, 'script-image-version-1');
    expect(viewModel.selectedVersion?.label, '导入图片 1');
    expect(attachmentItem.prompt, 'artist:manual, imported json prompt');
    expect(viewModel.visibleVersionItems, [attachmentItem]);
    expect(viewModel.focusedItemId, attachmentItem.id);

    await viewModel.renameItem(attachmentItem, 'Role swap 2');
    attachmentItem = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'script-image-version-1')
        .items
        .single;
    expect(renamedLabels, ['Role swap 2']);
    expect(attachmentItem.title, 'Role swap 2');

    await viewModel.deleteItem(attachmentItem);
    expect(deletedAttachmentIds, ['attachment-1']);
    expect(
        viewModel.snapshot.scripts.single.versions
            .any((version) => version.id == 'script-image-version-1'),
        isFalse);
  });

  test('renames scripts and reloads the snapshot', () async {
    var scripts = [_script()];
    final renamedLabels = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (script, label) async {
        renamedLabels.add(label);
        scripts = [
          scripts.single.copyWith(
            name: label,
            updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          ),
        ];
      },
    );

    await viewModel.load();
    await viewModel.renameScript(
      viewModel.snapshot.scripts.single,
      'Renamed Script',
    );

    expect(renamedLabels, ['Renamed Script']);
    expect(viewModel.snapshot.scripts.single.title, 'Renamed Script');
  });

  test('defaults district cards to all and supports custom script districts',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(),
        _script().copyWith(
          scriptId: 'script-2',
          name: '旁支档案',
          sourceFolder: r'C:\stories\branch',
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      customCategories: const [
        ScriptExhibitionUserCategory(
          id: 'favorites',
          title: '收藏馆区',
          description: '手动归入的剧本。',
          tags: ['自由分类'],
        ),
      ],
      customCategoryScriptIds: const {
        'favorites': ['script-1'],
      },
    );

    await viewModel.load();

    expect(viewModel.categories.map((category) => category.title), [
      '全部馆区',
      '收藏馆区',
    ]);
    expect(
      viewModel.categories
          .map((category) => category.id)
          .contains(ScriptExhibitionRoomViewModel.activeCategoryId),
      isFalse,
    );
    expect(
      viewModel.categories
          .map((category) => category.id)
          .contains(ScriptExhibitionRoomViewModel.archivedCategoryId),
      isFalse,
    );
    expect(
      viewModel.categories
          .map((category) => category.id)
          .contains(ScriptExhibitionRoomViewModel.needsActionCategoryId),
      isFalse,
    );

    viewModel.selectCategory('favorites');

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
    ]);
  });

  test('creates custom categories and assigns a single script', () async {
    var scripts = [
      _script(),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
      ),
    ];
    final assigned = <String, String>{};
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) async {
        assigned[script.scriptId] = categoryName;
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(categoryNames: [categoryName])
                : existing,
        ];
      },
    );

    await viewModel.load();
    await viewModel.createCategory('收藏馆区');
    await viewModel.assignScriptToCategory(
      viewModel.snapshot.scripts.firstWhere(
        (script) => script.scriptId == 'script-2',
      ),
      '收藏馆区',
    );

    expect(assigned, {'script-2': '收藏馆区'});
    expect(viewModel.categories.map((category) => category.title), [
      '全部馆区',
      '收藏馆区',
    ]);

    viewModel.selectCategory('custom:收藏馆区');

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-2',
    ]);
  });

  test('assigns multiple selected scripts to a custom category', () async {
    var scripts = [
      _script(),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
      ),
      _script().copyWith(
        scriptId: 'script-3',
        name: '留档档案',
        sourceFolder: r'C:\stories\archive',
      ),
    ];
    final assigned = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) async {
        assigned.add('${script.scriptId}:$categoryName');
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(categoryNames: [
                    ...existing.categoryNames,
                    categoryName,
                  ])
                : existing,
        ];
      },
    );

    await viewModel.load();
    await viewModel.assignScriptsToCategory(
      viewModel.snapshot.scripts.take(2),
      '收藏馆区',
    );

    expect(assigned, ['script-1:收藏馆区', 'script-2:收藏馆区']);
    expect(viewModel.selectedCategoryId, 'custom:收藏馆区');
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
  });

  test('deletes a custom category without deleting scripts', () async {
    var scripts = [
      _script().copyWith(categoryNames: const ['收藏馆区', '备选馆区']),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
        categoryNames: const ['收藏馆区'],
      ),
    ];
    final deletedCategories = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      deleteCategoryRecord: (categoryName) async {
        deletedCategories.add(categoryName);
        scripts = [
          for (final script in scripts)
            script.copyWith(
              categoryNames: script.categoryNames
                  .where(
                    (name) =>
                        name.trim().toLowerCase() !=
                        categoryName.trim().toLowerCase(),
                  )
                  .toList(growable: false),
            ),
        ];
      },
    );

    await viewModel.load();
    final category = viewModel.categories.singleWhere(
      (category) => category.title == '收藏馆区',
    );
    viewModel.selectCategory(category.id);
    await viewModel.deleteCategory(category);

    expect(deletedCategories, ['收藏馆区']);
    expect(viewModel.snapshot.scripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
    expect(
      viewModel.categories.map((category) => category.title),
      isNot(contains('收藏馆区')),
    );
    expect(
      viewModel.categories.map((category) => category.title),
      contains('备选馆区'),
    );
    expect(viewModel.selectedCategoryId,
        ScriptExhibitionRoomViewModel.allCategoryId);
  });

  test('removes one script from the selected custom category', () async {
    var scripts = [
      _script().copyWith(categoryNames: const ['收藏馆区', '备选馆区']),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
        categoryNames: const ['收藏馆区'],
      ),
    ];
    final removed = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      removeScriptCategory: (script, categoryName) async {
        removed.add('${script.scriptId}:$categoryName');
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(
                    categoryNames: existing.categoryNames
                        .where(
                          (name) =>
                              name.trim().toLowerCase() !=
                              categoryName.trim().toLowerCase(),
                        )
                        .toList(growable: false),
                  )
                : existing,
        ];
      },
    );

    await viewModel.load();
    viewModel.selectCategory('custom:收藏馆区');
    await viewModel.removeScriptFromSelectedCategory(
      viewModel.visibleScripts.firstWhere(
        (script) => script.scriptId == 'script-1',
      ),
    );

    expect(removed, ['script-1:收藏馆区']);
    expect(viewModel.selectedCategoryId, 'custom:收藏馆区');
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-2',
    ]);
    expect(viewModel.snapshot.scripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
    expect(
      viewModel.snapshot.scripts
          .singleWhere((script) => script.scriptId == 'script-1')
          .categoryNames,
      ['备选馆区'],
    );
  });

  test('sorts visible scripts by the selected shelf order', () async {
    final scripts = [
      _script().copyWith(
        scriptId: 'script-beta',
        name: 'Beta',
        sourceFolder: r'C:\stories\beta',
        updatedAt: DateTime.parse('2026-06-01T09:00:00Z'),
      ),
      _script().copyWith(
        scriptId: 'script-alpha',
        name: 'Alpha',
        sourceFolder: r'C:\stories\alpha',
        updatedAt: DateTime.parse('2026-06-03T09:00:00Z'),
      ),
      _script().copyWith(
        scriptId: 'script-gamma',
        name: 'Gamma',
        sourceFolder: r'C:\stories\gamma',
        updatedAt: DateTime.parse('2026-05-31T09:00:00Z'),
      ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => [
        _plan(
          scriptId: 'script-gamma',
          scriptName: 'Gamma',
          scriptPath: r'C:\stories\gamma',
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-alpha',
      'script-gamma',
      'script-beta',
    ]);

    viewModel.selectScriptSort(ScriptExhibitionScriptSort.title);

    expect(viewModel.scriptSort, ScriptExhibitionScriptSort.title);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-alpha',
      'script-beta',
      'script-gamma',
    ]);

    viewModel.selectScriptSort(ScriptExhibitionScriptSort.needsAction);

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-gamma',
      'script-alpha',
      'script-beta',
    ]);
  });

  test('coalesces production tasks by strong script identity', () async {
    final now = DateTime.parse('2026-06-02T08:00:00Z');
    final plan = ProductionPlan(
      id: 'large',
      name: 'Large Batch',
      createdAt: now,
      updatedAt: now,
      tasks: [
        for (var index = 1; index <= 4; index++)
          ProductionTask.scriptRecastFrame(
            id: 'task-$index',
            planId: 'large',
            title: 'Frame $index',
            scriptId: 'script-1',
            scriptName: 'Rain Archive',
            scriptPath: r'C:\stories\rain',
            recastRunId: 'run-large',
            frameIndex: index + 100,
            sourceFileName: 'generated-$index.json',
            payload: {'input': 'generated frame $index'},
            status: ProductionTaskStatus.completed,
            outputImagePath: r'C:\out\large.png',
            createdAt: now,
            updatedAt: now,
          ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.snapshot.scripts, hasLength(1));
    final productionVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'production-large');
    expect(productionVersion.items, hasLength(4));
  });

  test('sorts visible version items by the selected detail order', () async {
    final basePlan = _plan();
    final plan = basePlan.copyWith(
      updatedAt: DateTime.parse('2026-06-04T08:00:00Z'),
      tasks: [
        basePlan.tasks[0].copyWith(
          updatedAt: DateTime.parse('2026-06-02T08:00:00Z'),
        ),
        basePlan.tasks[1].copyWith(
          updatedAt: DateTime.parse('2026-06-04T08:00:00Z'),
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');

    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-generated-1',
      'production-plan-hero-a-task-failed-2',
    ]);

    viewModel.selectItemSort(ScriptExhibitionItemSort.recent);

    expect(viewModel.itemSort, ScriptExhibitionItemSort.recent);
    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-failed-2',
      'production-plan-hero-a-task-generated-1',
    ]);

    viewModel.selectItemSort(ScriptExhibitionItemSort.oldest);

    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-generated-1',
      'production-plan-hero-a-task-failed-2',
    ]);
  });

  test('deletes only the selected production version for the current script',
      () async {
    var plans = [_plan()];
    final deletedVersions = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (script, version) async {
        deletedVersions.add('${script.scriptId}:${version.id}');
        plans = [
          for (final plan in plans)
            if (version.id == 'production-${plan.id}')
              plan.copyWith(tasks: const [])
            else
              plan,
        ].where((plan) => plan.tasks.isNotEmpty).toList(growable: false);
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');

    final script = viewModel.selectedScript!;
    final productionVersion = script.versions.singleWhere(
      (version) => version.id == 'production-plan-hero-a',
    );
    expect(viewModel.canDeleteVersion(script, productionVersion), isTrue);

    await viewModel.deleteVersion(script, productionVersion);

    expect(deletedVersions, ['script-1:production-plan-hero-a']);
    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      contains(ScriptExhibitionVersion.originalId),
    );
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      isNot(contains('production-plan-hero-a')),
    );
    expect(viewModel.selectedVersion?.id, ScriptExhibitionVersion.originalId);
  });

  test('does not delete the original source version', () async {
    var deleteCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (script, version) async {
        deleteCount += 1;
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');

    final script = viewModel.selectedScript!;
    final originalVersion = script.versions.singleWhere(
      (version) => version.id == ScriptExhibitionVersion.originalId,
    );
    expect(viewModel.canDeleteVersion(script, originalVersion), isFalse);

    await viewModel.deleteVersion(script, originalVersion);

    expect(deleteCount, 0);
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      contains(ScriptExhibitionVersion.originalId),
    );
  });

  test('jumps to the first production item that needs action', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.jumpToFirstNeedsAction();

    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, 'production-plan-hero-a');
    expect(viewModel.focusedItemId, 'production-plan-hero-a-task-failed-2');
    expect(viewModel.selectedDetailFilterId,
        ScriptExhibitionRoomViewModel.needsActionDetailFilterId);
    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-failed-2',
    ]);
  });
}

TokenizerScript _script() {
  final now = DateTime.parse('2026-06-01T09:00:00Z');
  final source1 = _source(
    'source-1',
    '001.json',
    r'C:\stories\rain\001.json',
    defaultImagePath: r'C:\stories\rain\001.png',
  );
  final source2 = _source(
    'source-2',
    '002.json',
    r'C:\stories\rain\002.json',
    defaultImagePath: r'C:\stories\rain\002.png',
  );
  return TokenizerScript(
    scriptId: 'script-1',
    name: '雨夜档案',
    sourceFolder: r'C:\stories\rain',
    sourceMode: TokenizerScriptSourceMode.auto,
    createdAt: now,
    updatedAt: now,
    status: TokenizerScriptStatus.needsReview,
    sourceFiles: [source1, source2],
    sampleFileIds: const ['source-1'],
    characterIdentities: const [],
    styleStages: const [],
    knowledgeCandidates: const [],
    imageTasks: [
      _task(
        id: 'task-1',
        source: source1,
        prompt: 'library entrance, rainy night',
        status: TokenizerTaskReviewStatus.confirmed,
      ),
      _task(
        id: 'task-2',
        source: source2,
        prompt: 'old book shelf, wet coat',
        status: TokenizerTaskReviewStatus.needsReview,
      ),
    ],
  );
}

TokenizerSourceFile _source(
  String id,
  String fileName,
  String path, {
  String defaultImagePath = '',
  TokenizerScriptSourceKind kind = TokenizerScriptSourceKind.json,
}) {
  return TokenizerSourceFile(
    fileId: id,
    fileName: fileName,
    path: path,
    kind: kind,
    defaultImagePath: defaultImagePath,
  );
}

TokenizerImageTask _task({
  required String id,
  required TokenizerSourceFile source,
  required String prompt,
  String? finalPrompt,
  required TokenizerTaskReviewStatus status,
}) {
  return TokenizerImageTask(
    taskId: id,
    sourceFile: source,
    parseStatus: 'parsed',
    originalPrompt: prompt,
    promptMode: TokenizerScriptPromptMode.tag,
    parsedPrompt: prompt,
    finalPrompt: finalPrompt ?? prompt,
    artistEvidence: const [],
    characterSlotMatches: const [],
    confidence: 0.9,
    reviewStatus: status,
    details: const TokenizerParseDetails(),
  );
}

ProductionPlan _plan({
  String scriptId = 'script-1',
  String scriptName = '雨夜档案',
  String scriptPath = r'C:\stories\rain',
  Map<String, dynamic>? generatedPayload,
}) {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-hero-a',
    name: '主角版 A',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-generated-1',
        planId: 'plan-hero-a',
        title: '入口雨幕',
        scriptId: scriptId,
        scriptName: scriptName,
        scriptPath: scriptPath,
        recastRunId: 'run-hero-a',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: generatedPayload ??
            const {
              'input': 'library entrance, new heroine',
            },
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-01.png',
        createdAt: now,
        updatedAt: now,
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-failed-2',
        planId: 'plan-hero-a',
        title: '旧书架前',
        scriptId: scriptId,
        scriptName: scriptName,
        scriptPath: scriptPath,
        recastRunId: 'run-hero-a',
        frameIndex: 2,
        sourceFileName: '002.json',
        payload: const {
          'input': 'old shelf, failed generation',
        },
        status: ProductionTaskStatus.failed,
        error: 'rate limited',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

StudioGalleryRecord _galleryRecord({
  String taskId = 'task-generated-1',
  String imagePath = r'C:\gallery\frame-01.png',
}) {
  final now = DateTime.parse('2026-06-03T08:00:00Z');
  return StudioGalleryRecord.fromRecastPayload(
    payload: const {
      'input': 'library entrance, archived version',
    },
    id: 'gallery-1',
    createdAt: now,
    title: '收纳: 入口雨幕',
    imagePath: imagePath,
    info: 'archived image prompt',
    provenance: StudioRecastProvenance(
      scriptId: 'script-1',
      scriptName: '雨夜档案',
      scriptPath: r'C:\stories\rain',
      recastRunId: 'run-hero-a',
      productionPlanId: 'plan-hero-a',
      productionPlanFingerprint: 'fingerprint',
      taskId: taskId,
      frameIndex: 1,
      sourceFileName: '001.json',
      payloadFingerprint: 'payload-fingerprint',
      mappingConfigFingerprint: 'mapping-fingerprint',
      outputImagePath: imagePath,
    ),
  );
}
