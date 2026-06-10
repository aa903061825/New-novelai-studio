import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';

void main() {
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

  test('falls back to source files when image tasks are not available',
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

    final script = viewModel.snapshot.scripts.single;
    expect(script.versions, hasLength(1));
    expect(script.versions.single.label, '原始剧本');
    expect(script.versions.single.items.single.sourceFileName, '001.json');
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

  test('aggregates script-scoped image attachments as their own version',
      () async {
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

    final attachmentVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere(
            (version) => version.id == ScriptExhibitionVersion.attachmentsId);
    expect(attachmentVersion.label, '剧本图片');
    expect(attachmentVersion.items.single.title, 'Default 1');
    expect(attachmentVersion.items.single.imagePath,
        r'C:\stories\rain\manual_001.png');
    expect(attachmentVersion.items.single.sourceKind,
        ScriptExhibitionItemSourceKind.attachment);
    expect(attachmentVersion.items.single.canDelete, isTrue);
    expect(attachmentVersion.items.single.canRename, isTrue);
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
        .singleWhere(
            (version) => version.id == ScriptExhibitionVersion.attachmentsId)
        .items
        .single;
    expect(importedScripts, ['script-1']);

    await viewModel.renameItem(attachmentItem, 'Role swap 2');
    attachmentItem = viewModel.snapshot.scripts.single.versions
        .singleWhere(
            (version) => version.id == ScriptExhibitionVersion.attachmentsId)
        .items
        .single;
    expect(renamedLabels, ['Role swap 2']);
    expect(attachmentItem.title, 'Role swap 2');

    await viewModel.deleteItem(attachmentItem);
    expect(deletedAttachmentIds, ['attachment-1']);
    expect(
        viewModel.snapshot.scripts.single.versions.any(
            (version) => version.id == ScriptExhibitionVersion.attachmentsId),
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
  final source1 = _source('source-1', '001.json', r'C:\stories\rain\001.json');
  final source2 = _source('source-2', '002.json', r'C:\stories\rain\002.json');
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
        payload: const {
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
