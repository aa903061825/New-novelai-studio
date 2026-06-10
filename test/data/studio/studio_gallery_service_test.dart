import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

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
}
