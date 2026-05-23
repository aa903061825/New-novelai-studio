import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_batch_plan_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig:
        PromptConfig(strs: const ['base prompt'], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({
      'api_key': 'local-key',
      'proxy': '127.0.0.1:7890',
      'output_folder': r'C:\outputs',
      'batch_count': 10,
      'batch_interval': 20,
      'number_of_requests': 9,
    }),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  late Directory tempDir;
  late WorkspaceService workspaceService;
  late StudioBatchPlanService service;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('studio-batch-service-test-');
    workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    service = StudioBatchPlanService(workspaceService: workspaceService);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loadQueuePlans normalizes batch plan items for UI consumption',
      () async {
    await workspaceService.saveBatchPlans([
      BatchPlan(
        id: 'batch-1',
        name: 'Night Queue',
        items: const [
          {
            'recipe': 'style-1',
            'prompt': 'rainy alley, neon puddles',
            'paramsOverride': {'width': 1024, 'height': 1024},
          },
          {
            'title': 'Named shot',
            'prompt': 'soft light',
          },
        ],
        createdAt: DateTime.parse('2026-05-23T00:00:00Z'),
        updatedAt: DateTime.parse('2026-05-23T00:00:00Z'),
      ),
    ]);

    final plans = await service.loadQueuePlans();

    expect(plans, hasLength(1));
    expect(plans.single.plan.id, 'batch-1');
    expect(
        plans.single.items.map((item) => item.id), ['batch-1:0', 'batch-1:1']);
    expect(plans.single.items.first.title, 'rainy alley, neon puddles');
    expect(plans.single.items.first.summary, contains('paramsOverride'));
    expect(plans.single.items.last.title, 'Named shot');
    expect(
      () => plans.single.items.first.raw['prompt'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test('applyQueueItem updates prompt params and batch settings safely',
      () async {
    final payload = _payload();
    final item = StudioBatchQueueItem(
      id: 'batch-1:0',
      planId: 'batch-1',
      planName: 'Night Queue',
      index: 0,
      title: 'City shot',
      summary: 'summary',
      raw: const {
        'prompt': ['rainy alley', 'neon puddles'],
        'negativePrompt': 'bad anatomy',
        'paramsOverride': {'width': 1024, 'height': 1024},
        'params': {'scale': 5.5, 'sampler': 'k_euler'},
        'settingsOverride': {
          'batch_count': 0,
          'batch_interval_jitter_min': -2,
          'retry_on_429_delay_sec': 0,
          'api_key': 'pst-should-not-apply',
        },
        'settings': {
          'numberOfRequests': 3,
          'retryOn429Enabled': true,
          'proxy': '10.0.0.1:9999',
          'output_folder': r'D:\leak',
        },
      },
    );

    final result = service.applyQueueItem(item: item, target: payload);

    expect(result.positivePrompt, 'rainy alley, neon puddles');
    expect(result.negativePrompt, 'bad anatomy');
    expect(result.paramChangeCount, 4);
    expect(result.batchSettingChangeCount, 5);
    expect(payload.overridePrompt, 'rainy alley, neon puddles');
    expect(payload.useOverridePrompt, isTrue);
    expect(payload.paramConfig.negativePrompt, 'bad anatomy');
    expect(payload.paramConfig.sizes.single.width, 1024);
    expect(payload.paramConfig.sizes.single.height, 1024);
    expect(payload.paramConfig.scale, 5.5);
    expect(payload.paramConfig.sampler, 'k_euler');
    expect(payload.settings.batchCount, 1);
    expect(payload.settings.batchIntervalJitterMinSec, 0);
    expect(payload.settings.retryOn429DelaySec, 1);
    expect(payload.settings.retryOn429Enabled, isTrue);
    expect(payload.settings.numberOfRequests, 3);
    expect(payload.settings.apiKey, 'local-key');
    expect(payload.settings.proxy, '127.0.0.1:7890');
    expect(payload.settings.outputFolderPath, r'C:\outputs');
  });

  test('applyQueueItem supports direct override fields', () {
    final payload = _payload();
    final item = StudioBatchQueueItem(
      id: 'batch-2:0',
      planId: 'batch-2',
      planName: 'Direct Queue',
      index: 0,
      title: 'Direct',
      summary: '',
      raw: const {
        'input': 'direct prompt',
        'uc': 'direct uc',
        'width': 832,
        'height': 1216,
        'steps': 24,
        'batchCount': 2,
        'batchIntervalSec': -5,
        'number_of_requests': -9,
      },
    );

    final result = service.applyQueueItem(item: item, target: payload);

    expect(result.paramChangeCount, 4);
    expect(result.batchSettingChangeCount, 3);
    expect(payload.overridePrompt, 'direct prompt');
    expect(payload.paramConfig.negativePrompt, 'direct uc');
    expect(payload.paramConfig.sizes.single.width, 832);
    expect(payload.paramConfig.sizes.single.height, 1216);
    expect(payload.paramConfig.steps, 24);
    expect(payload.settings.batchCount, 2);
    expect(payload.settings.batchIntervalSec, 0);
    expect(payload.settings.numberOfRequests, 0);
  });
}
