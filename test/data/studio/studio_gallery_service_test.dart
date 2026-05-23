import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
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
}
