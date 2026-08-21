import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/workbench_document.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

PayloadConfig _payload({
  required String prompt,
  required String apiKey,
  required String proxy,
}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(steps: 28),
    settings: Settings.fromJson({
      'api_key': apiKey,
      'proxy': proxy,
      'output_folder': r'C:\private-output',
    }),
    overridePrompt: prompt,
    useOverridePrompt: true,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  late Directory tempDir;
  late WorkspaceService workspaceService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('studio-gallery-test-');
    workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saveSnapshot persists a creative record without local settings',
      () async {
    final service = StudioGalleryService(workspaceService: workspaceService);

    final record = await service.saveSnapshot(
      config: _payload(
        prompt: 'rainy glass atelier',
        apiKey: 'pst-secret',
        proxy: '127.0.0.1:7890',
      ),
      title: '20260522-000001.png',
      imagePath: r'C:\outputs\20260522-000001.png',
      info: 'rainy glass atelier',
      additionalInfo: {'seed': 1234},
      createdAt: DateTime.parse('2026-05-22T10:30:00Z'),
      id: 'record-1',
    );

    final reopened = await StudioGalleryService(
      workspaceService: workspaceService,
    ).loadRecords();
    final file = File(
      [
        tempDir.path,
        ...WorkspacePaths.galleryRecords.split('/'),
      ].join(Platform.pathSeparator),
    );
    final rawJson = jsonDecode(await file.readAsString());

    expect(record.id, 'record-1');
    expect(reopened, hasLength(1));
    expect(reopened.single.title, '20260522-000001.png');
    expect(reopened.single.info, 'rainy glass atelier');
    expect(reopened.single.imagePath, r'C:\outputs\20260522-000001.png');
    expect(reopened.single.additionalInfo['seed'], 1234);
    expect(rawJson.toString(), contains('rainy glass atelier'));
    expect(rawJson.toString(), isNot(contains('pst-secret')));
    expect(rawJson.toString(), isNot(contains('private-output')));
  });

  test('removeRecord keeps the gallery image file by default', () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final imageFile = File(
      [tempDir.path, 'kept-gallery-image.png'].join(Platform.pathSeparator),
    );
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
    final record = await service.saveSnapshot(
      config: _payload(prompt: 'kept prompt', apiKey: 'pst-export', proxy: ''),
      title: 'kept-gallery-image.png',
      imagePath: imageFile.path,
      id: 'record-keep-file',
      createdAt: DateTime.parse('2026-05-22T10:45:00Z'),
    );

    await service.removeRecord(record.id);

    expect(await service.loadRecords(), isEmpty);
    expect(await imageFile.exists(), isTrue);
  });

  test('removeRecord deletes the gallery image file when requested', () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final imageFile = File(
      [tempDir.path, 'deleted-gallery-image.png'].join(Platform.pathSeparator),
    );
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
    final record = await service.saveSnapshot(
      config: _payload(
        prompt: 'deleted prompt',
        apiKey: 'pst-export',
        proxy: '',
      ),
      title: 'deleted-gallery-image.png',
      imagePath: imageFile.path,
      id: 'record-delete-file',
      createdAt: DateTime.parse('2026-05-22T10:50:00Z'),
    );

    await service.removeRecord(record.id, deleteImageFile: true);

    expect(await service.loadRecords(), isEmpty);
    expect(await imageFile.exists(), isFalse);
  });

  test('restoreToWorkbench applies creative state and preserves local settings',
      () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final record = await service.saveSnapshot(
      config: _payload(
        prompt: 'imported gallery prompt',
        apiKey: 'pst-export',
        proxy: '',
      ),
      id: 'record-restore',
      createdAt: DateTime.parse('2026-05-22T12:00:00Z'),
    );
    final target = _payload(
      prompt: 'current local prompt',
      apiKey: 'pst-current',
      proxy: '127.0.0.1:7890',
    );

    service.restoreToWorkbench(record, target);

    expect(target.overridePrompt, 'imported gallery prompt');
    expect(target.paramConfig.steps, 28);
    expect(target.settings.apiKey, 'pst-current');
    expect(target.settings.proxy, '127.0.0.1:7890');
  });

  test('saveSnapshot restores the effective generated prompt and UC', () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final record = await service.saveSnapshot(
      config: _payload(
        prompt: 'configured prompt before random selection',
        apiKey: 'pst-export',
        proxy: '',
      ),
      id: 'record-effective-prompt',
      createdAt: DateTime.parse('2026-05-22T12:10:00Z'),
      additionalInfo: const {
        'input': 'artist:actual, 1girl, red dress, blue eyes',
        'negativePrompt': 'lowres, bad anatomy',
      },
    );
    final target = _payload(
      prompt: 'current workbench prompt',
      apiKey: 'pst-current',
      proxy: '127.0.0.1:7890',
    );

    service.restoreToWorkbench(record, target);

    expect(
      record.document.payload['override_prompt'],
      'artist:actual, 1girl, red dress, blue eyes',
    );
    expect(target.overridePrompt, 'artist:actual, 1girl, red dress, blue eyes');
    expect(target.useOverridePrompt, isTrue);
    expect(target.useCharacterPromptWithOverride, isFalse);
    expect(target.paramConfig.negativePrompt, 'lowres, bad anatomy');
  });

  test('restoreToWorkbench repairs legacy records from effective prompt data',
      () {
    final savedConfig = _payload(
      prompt: 'stale configured prompt',
      apiKey: 'pst-export',
      proxy: '',
    );
    final record = StudioGalleryRecord(
      id: 'legacy-effective-prompt',
      createdAt: DateTime.parse('2026-05-22T12:15:00Z'),
      title: 'legacy.png',
      imagePath: null,
      info: 'display-only prompt commentary',
      additionalInfo: const {
        'input': 'legacy actual base, legacy actual character',
        'negativePrompt': 'legacy actual UC',
      },
      document: WorkbenchDocument.fromPayloadConfig(savedConfig),
    );
    final target = _payload(
      prompt: 'current workbench prompt',
      apiKey: 'pst-current',
      proxy: '127.0.0.1:7890',
    );
    final service = StudioGalleryService(workspaceService: workspaceService);

    service.restoreToWorkbench(record, target);

    expect(
      target.overridePrompt,
      'legacy actual base, legacy actual character',
    );
    expect(target.useOverridePrompt, isTrue);
    expect(target.useCharacterPromptWithOverride, isFalse);
    expect(target.paramConfig.negativePrompt, 'legacy actual UC');
  });

  test('useRecordAsI2iSource sets source image without restoring prompt',
      () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final imageFile = File(
      [tempDir.path, 'gallery-source.png'].join(Platform.pathSeparator),
    );
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
    final record = await service.saveSnapshot(
      config: _payload(
        prompt: 'saved gallery prompt',
        apiKey: 'pst-export',
        proxy: '',
      ),
      imagePath: imageFile.path,
      id: 'record-i2i-source',
      createdAt: DateTime.parse('2026-05-22T12:30:00Z'),
    );
    final target = _payload(
      prompt: 'current workbench prompt',
      apiKey: 'pst-current',
      proxy: '',
    );

    await service.useRecordAsI2iSource(record, target);

    expect(target.overridePrompt, 'current workbench prompt');
    expect(target.i2iConfig.imageB64, _tinyPngBase64);
    expect(target.i2iConfig.width, 1);
    expect(target.i2iConfig.height, 1);
  });

  test('useRecordAsI2iSource rejects records without readable images',
      () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final missing = StudioGalleryRecord.fromPayloadConfig(
      config: _payload(
        prompt: 'saved gallery prompt',
        apiKey: 'pst-export',
        proxy: '',
      ),
      id: 'missing-image',
      createdAt: DateTime.parse('2026-05-22T12:30:00Z'),
      imagePath: [tempDir.path, 'missing.png'].join(Platform.pathSeparator),
    );
    final target = _payload(
      prompt: 'current workbench prompt',
      apiKey: 'pst-current',
      proxy: '',
    );

    expect(
      () => service.useRecordAsI2iSource(missing, target),
      throwsA(isA<StateError>()),
    );
    expect(target.i2iConfig.imageB64, isNull);
  });

  test('gallery lineage round trips through saved records', () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final record = await service.saveSnapshot(
      config: _payload(prompt: 'enhanced prompt', apiKey: 'pst', proxy: ''),
      title: 'enhanced.png',
      imagePath: r'C:\outputs\enhanced.png',
      info: 'enhanced prompt',
      id: 'record-enhanced',
      createdAt: DateTime.parse('2026-06-10T08:00:00Z'),
      lineage: const StudioGalleryLineage(
        operation: StudioGalleryOperation.enhance,
        sourceRecordId: 'record-source',
        sourceImagePath: r'C:\outputs\source.png',
        parameters: {'strength': 0.35, 'noise': 0.12},
      ),
    );

    final reopened = await StudioGalleryService(
      workspaceService: workspaceService,
    ).loadRecords();

    expect(record.lineage?.operation, StudioGalleryOperation.enhance);
    expect(reopened.single.lineage?.sourceRecordId, 'record-source');
    expect(reopened.single.lineage?.parameters['strength'], 0.35);
  });

  test('saveOperationSnapshot stores result before the source record',
      () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    await service.saveSnapshot(
      config: _payload(prompt: 'source prompt', apiKey: 'pst', proxy: ''),
      title: 'source.png',
      imagePath: r'C:\outputs\source.png',
      info: 'source prompt',
      id: 'source-record',
      createdAt: DateTime.parse('2026-06-10T08:00:00Z'),
    );

    await service.saveOperationSnapshot(
      config: _payload(prompt: 'enhanced prompt', apiKey: 'pst', proxy: ''),
      sourceRecordId: 'source-record',
      sourceImagePath: r'C:\outputs\source.png',
      operation: StudioGalleryOperation.enhance,
      title: 'enhanced.png',
      imagePath: r'C:\outputs\enhanced.png',
      info: 'enhanced prompt',
      parameters: {'strength': 0.35},
      id: 'enhanced-record',
      createdAt: DateTime.parse('2026-06-10T08:01:00Z'),
    );

    final records = await service.loadRecords();

    expect(records.map((record) => record.id), [
      'enhanced-record',
      'source-record',
    ]);
    expect(records.first.lineage?.operation, StudioGalleryOperation.enhance);
    expect(records.first.lineage?.sourceRecordId, 'source-record');
    expect(records.first.lineage?.sourceImagePath, r'C:\outputs\source.png');
  });

  test('loadRecords treats an older library without gallery data as empty',
      () async {
    final file = File(
      [
        tempDir.path,
        ...WorkspacePaths.galleryRecords.split('/'),
      ].join(Platform.pathSeparator),
    );
    await file.delete();

    final records = await StudioGalleryService(
      workspaceService: workspaceService,
    ).loadRecords();

    expect(records, isEmpty);
  });

  test('old gallery record without provenance still loads', () async {
    final file = File(
      [
        tempDir.path,
        ...WorkspacePaths.galleryRecords.split('/'),
      ].join(Platform.pathSeparator),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([
      {
        'version': 1,
        'id': 'legacy-record',
        'createdAt': '2026-05-22T10:30:00Z',
        'title': 'legacy.png',
        'imagePath': r'C:\outputs\legacy.png',
        'info': 'legacy prompt',
        'additionalInfo': {'seed': 7},
        'document': {
          'kind': 'novel-studio-workbench',
          'version': 1,
          'payload': {
            'prompt_config': {'strs': [], 'prompts': []},
            'character_config': [],
            'saved_config': [],
            'param_config': {},
            'override_prompt': 'legacy prompt',
            'use_override_prompt': true,
            'use_character_prompt_with_override': false,
          },
        },
      },
    ]));

    final records = await StudioGalleryService(
      workspaceService: workspaceService,
    ).loadRecords();

    expect(records.single.id, 'legacy-record');
    expect(records.single.provenance, isNull);
    expect(records.single.additionalInfo['seed'], 7);
  });

  test('loadRecords resolves legacy filename-only image paths', () async {
    final defaultOutputDir = Directory(
      [tempDir.path, 'default-output'].join(Platform.pathSeparator),
    );
    await defaultOutputDir.create();
    final imageFile = File(
      [defaultOutputDir.path, 'legacy.png'].join(Platform.pathSeparator),
    );
    await imageFile.writeAsBytes([1, 2, 3]);
    final file = File(
      [
        tempDir.path,
        ...WorkspacePaths.galleryRecords.split('/'),
      ].join(Platform.pathSeparator),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([
      {
        'version': 1,
        'id': 'legacy-record',
        'createdAt': '2026-05-22T10:30:00Z',
        'title': 'legacy.png',
        'imagePath': 'legacy.png',
        'info': 'legacy prompt',
        'additionalInfo': {'seed': 7},
        'document': {
          'kind': 'novel-studio-workbench',
          'version': 1,
          'payload': {
            'prompt_config': {'strs': [], 'prompts': []},
            'character_config': [],
            'saved_config': [],
            'param_config': {},
            'override_prompt': 'legacy prompt',
            'use_override_prompt': true,
            'use_character_prompt_with_override': false,
          },
        },
      },
    ]));

    final records = await StudioGalleryService(
      workspaceService: workspaceService,
      resolvePictureSavePath: (fileName, saveDir) async {
        expect(saveDir, isEmpty);
        return [defaultOutputDir.path, fileName].join(Platform.pathSeparator);
      },
    ).loadRecords();

    expect(records.single.imagePath, imageFile.path);
  });

  test('recast provenance round trips through gallery metadata', () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    final provenance = StudioRecastProvenance(
      scriptId: 'script-1',
      scriptName: 'Pilot',
      scriptPath: r'C:\scripts\pilot',
      recastRunId: 'run-1',
      productionPlanId: 'plan-1',
      productionPlanFingerprint: 'plan-fingerprint',
      taskId: 'task-1',
      frameIndex: 1,
      sourceFileName: 'nai_1.json',
      payloadFingerprint: 'payload-fingerprint',
      mappingConfigFingerprint: 'mapping-fingerprint',
      outputImagePath: r'C:\outputs\nai_1.png',
    );

    await service.saveRecastFrameSnapshot(
      payload: {
        'input': 'gallery recast prompt',
        'parameters': {'seed': 1234},
      },
      title: 'nai_1.png',
      imagePath: r'C:\outputs\nai_1.png',
      info: 'gallery recast prompt',
      provenance: provenance,
      additionalInfo: {'seed': 1234},
      createdAt: DateTime.parse('2026-05-22T10:30:00Z'),
      id: 'record-recast',
    );

    final reopened = await StudioGalleryService(
      workspaceService: workspaceService,
    ).loadRecords();

    expect(reopened.single.provenance, isNotNull);
    expect(reopened.single.provenance!.scriptId, 'script-1');
    expect(reopened.single.provenance!.mappingConfigFingerprint,
        'mapping-fingerprint');
    expect(reopened.single.additionalInfo['seed'], 1234);
    expect(reopened.single.additionalInfo['provenance']['taskId'], 'task-1');
    expect(reopened.single.document.payload['override_prompt'],
        'gallery recast prompt');
  });

  test('loadCreativeRecords excludes script recast provenance records',
      () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    await service.saveSnapshot(
      config: _payload(
        prompt: 'standalone creative prompt',
        apiKey: 'pst-creative',
        proxy: '',
      ),
      title: 'standalone.png',
      imagePath: r'C:\outputs\standalone.png',
      info: 'standalone creative prompt',
      createdAt: DateTime.parse('2026-05-22T10:30:00Z'),
      id: 'creative-record',
    );
    await service.saveRecastFrameSnapshot(
      payload: {
        'input': 'script recast prompt',
        'parameters': {'seed': 1234},
      },
      title: 'nai_1.png',
      imagePath: r'C:\outputs\nai_1.png',
      info: 'script recast prompt',
      provenance: const StudioRecastProvenance(
        scriptId: 'script-1',
        scriptName: 'Pilot',
        scriptPath: r'C:\scripts\pilot',
        recastRunId: 'run-1',
        productionPlanId: 'plan-1',
        productionPlanFingerprint: 'plan-fingerprint',
        taskId: 'task-1',
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payloadFingerprint: 'payload-fingerprint',
        mappingConfigFingerprint: 'mapping-fingerprint',
        outputImagePath: r'C:\outputs\nai_1.png',
      ),
      createdAt: DateTime.parse('2026-05-22T10:31:00Z'),
      id: 'script-record',
    );

    final allRecords = await service.loadRecords();
    final creativeRecords = await service.loadCreativeRecords();

    expect(allRecords.map((record) => record.id), [
      'script-record',
      'creative-record',
    ]);
    expect(creativeRecords.map((record) => record.id), ['creative-record']);
  });

  test('loadRecastRecords returns only script provenance records', () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    await service.saveSnapshot(
      config: _payload(
        prompt: 'standalone creative prompt',
        apiKey: 'pst-creative',
        proxy: '',
      ),
      title: 'standalone.png',
      imagePath: r'C:\outputs\standalone.png',
      info: 'standalone creative prompt',
      createdAt: DateTime.parse('2026-05-22T10:30:00Z'),
      id: 'creative-record',
    );
    await service.saveRecastFrameSnapshot(
      payload: {
        'input': 'script recast prompt',
        'parameters': {'seed': 1234},
      },
      title: 'nai_1.png',
      imagePath: r'C:\outputs\nai_1.png',
      info: 'script recast prompt',
      provenance: const StudioRecastProvenance(
        scriptId: 'script-1',
        scriptName: 'Pilot',
        scriptPath: r'C:\scripts\pilot',
        recastRunId: 'run-1',
        productionPlanId: 'plan-1',
        productionPlanFingerprint: 'plan-fingerprint',
        taskId: 'task-1',
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payloadFingerprint: 'payload-fingerprint',
        mappingConfigFingerprint: 'mapping-fingerprint',
        outputImagePath: r'C:\outputs\nai_1.png',
      ),
      createdAt: DateTime.parse('2026-05-22T10:31:00Z'),
      id: 'script-record',
    );

    final recastRecords = await service.loadRecastRecords();

    expect(recastRecords.map((record) => record.id), ['script-record']);
    expect(recastRecords.single.provenance?.taskId, 'task-1');
  });

  test('loadRecastRecords hydrates lightweight records without full document',
      () async {
    final recordsFile = File(
      [
        tempDir.path,
        ...WorkspacePaths.galleryRecords.split('/'),
      ].join(Platform.pathSeparator),
    );
    await recordsFile.parent.create(recursive: true);
    await recordsFile.writeAsString(jsonEncode([
      {
        'id': 'creative-record',
        'createdAt': '2026-05-22T10:30:00Z',
        'title': 'standalone.png',
        'info': 'standalone creative prompt',
        'document': {'kind': 'malformed'},
      },
      {
        'id': 'script-record',
        'createdAt': '2026-05-22T10:31:00Z',
        'title': 'nai_1.png',
        'imagePath': r'C:\outputs\nai_1.png',
        'info': 'script recast prompt',
        'provenance': {
          'scriptId': 'script-1',
          'scriptName': 'Pilot',
          'scriptPath': r'C:\scripts\pilot',
          'recastRunId': 'run-1',
          'productionPlanId': 'plan-1',
          'productionPlanFingerprint': 'plan-fingerprint',
          'taskId': 'task-1',
          'frameIndex': 1,
          'sourceFileName': 'nai_1.json',
          'payloadFingerprint': 'payload-fingerprint',
          'mappingConfigFingerprint': 'mapping-fingerprint',
          'outputImagePath': r'C:\outputs\nai_1.png',
        },
        'document': {
          'kind': 'malformed',
          'payload': {
            'i2i_config': 'not needed by script exhibition',
          },
        },
      },
    ]));
    final service = StudioGalleryService(workspaceService: workspaceService);

    final recastRecords = await service.loadRecastRecords();

    expect(recastRecords.map((record) => record.id), ['script-record']);
    expect(recastRecords.single.provenance?.taskId, 'task-1');
    expect(recastRecords.single.document.payload, isEmpty);
  });

  test('loadCreativeRecordSummary counts creative records and limits recent',
      () async {
    final service = StudioGalleryService(workspaceService: workspaceService);
    await service.saveSnapshot(
      config: _payload(prompt: 'old', apiKey: 'pst-export', proxy: ''),
      id: 'creative-old',
      createdAt: DateTime.parse('2026-05-22T10:00:00Z'),
    );
    await service.saveRecastFrameSnapshot(
      payload: {
        'input': 'script recast prompt',
        'parameters': {'seed': 1234},
      },
      title: 'nai_1.png',
      imagePath: r'C:\outputs\nai_1.png',
      info: 'script recast prompt',
      provenance: const StudioRecastProvenance(
        scriptId: 'script-1',
        scriptName: 'Pilot',
        scriptPath: r'C:\scripts\pilot',
        recastRunId: 'run-1',
        productionPlanId: 'plan-1',
        productionPlanFingerprint: 'plan-fingerprint',
        taskId: 'task-1',
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payloadFingerprint: 'payload-fingerprint',
        mappingConfigFingerprint: 'mapping-fingerprint',
        outputImagePath: r'C:\outputs\nai_1.png',
      ),
      id: 'script-record',
      createdAt: DateTime.parse('2026-05-22T10:01:00Z'),
    );
    await service.saveSnapshot(
      config: _payload(prompt: 'middle', apiKey: 'pst-export', proxy: ''),
      id: 'creative-middle',
      createdAt: DateTime.parse('2026-05-22T10:02:00Z'),
    );
    await service.saveSnapshot(
      config: _payload(prompt: 'newest', apiKey: 'pst-export', proxy: ''),
      id: 'creative-newest',
      createdAt: DateTime.parse('2026-05-22T10:03:00Z'),
    );

    final summary = await service.loadCreativeRecordSummary(recentLimit: 2);

    expect(summary.totalCount, 3);
    expect(
      summary.recentRecords.map((record) => record.id),
      ['creative-newest', 'creative-middle'],
    );
  });
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
