import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_executor_service.dart';
import 'package:novel_studio/data/studio/services/production_nai_adapter_service.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/studio_batch/view_models/production_queue_viewmodel.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService workspaceService;
  late ProductionQueueService queueService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'production-queue-viewmodel-test-',
    );
    workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    queueService = ProductionQueueService(workspaceService: workspaceService);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load reads deterministic production plans from workspace', () async {
    await queueService.savePlans([
      _plan([_scriptTask(id: 'task-1')])
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: queueService,
    );

    await viewModel.load();

    expect(viewModel.plans, hasLength(1));
    expect(viewModel.selectedPlan?.id, 'plan-1');
    expect(viewModel.selectedTask?.id, 'task-1');
    expect(viewModel.totalTasks, 1);
  });

  test('load selects the first plan task when a newer plan is prepended',
      () async {
    final oldPlan = _plan(
      [
        _scriptTask(
          id: 'old-task',
          payload: const {
            'input': 'old prompt',
            'parameters': {'seed': 1},
          },
        ),
      ],
      id: 'old-plan',
      name: 'Old Recast',
    );
    final newPlan = _plan(
      [
        _scriptTask(
          id: 'new-task',
          planId: 'new-plan',
          payload: const {
            'input': 'current preview prompt',
            'parameters': {'seed': 2},
          },
        ),
      ],
      id: 'new-plan',
      name: 'Current Recast',
    );
    await queueService.savePlans([oldPlan]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
    );
    expect(viewModel.selectedTask?.id, 'old-task');

    await queueService.savePlans([newPlan, oldPlan]);
    await viewModel.load();

    expect(viewModel.selectedPlan?.id, 'new-plan');
    expect(viewModel.selectedTask?.id, 'new-task');
    expect(viewModel.selectedTask?.payload['input'], 'current preview prompt');
  });

  test('selectPlan switches the viewed queue without reordering plans', () {
    final firstPlan = _plan(
      [_scriptTask(id: 'first-task')],
      id: 'first-plan',
      name: 'First',
    );
    final secondPlan = _plan(
      [
        _scriptTask(
          id: 'second-task',
          planId: 'second-plan',
        ),
      ],
      id: 'second-plan',
      name: 'Second',
    );
    final viewModel = ProductionQueueViewModel(
      plans: [firstPlan, secondPlan],
    );

    final selected = viewModel.selectPlan(secondPlan.id);

    expect(selected, isTrue);
    expect(viewModel.selectedPlan?.id, secondPlan.id);
    expect(viewModel.selectedTask?.id, 'second-task');
    expect(viewModel.plans.map((plan) => plan.id), [
      firstPlan.id,
      secondPlan.id,
    ]);
  });

  test('focusProductionTask selects its queue tab without reordering plans',
      () {
    final firstPlan = _plan(
      [_scriptTask(id: 'first-task')],
      id: 'first-plan',
      name: 'First',
    );
    final secondPlan = _plan(
      [
        _scriptTask(
          id: 'second-task',
          planId: 'second-plan',
        ),
      ],
      id: 'second-plan',
      name: 'Second',
    );
    final viewModel = ProductionQueueViewModel(
      plans: [firstPlan, secondPlan],
    );

    final focused = viewModel.focusProductionTask(
      planId: secondPlan.id,
      taskId: 'second-task',
    );

    expect(focused, isTrue);
    expect(viewModel.selectedPlan?.id, secondPlan.id);
    expect(viewModel.selectedTask?.id, 'second-task');
    expect(viewModel.plans.map((plan) => plan.id), [
      firstPlan.id,
      secondPlan.id,
    ]);
  });

  test('load focuses a preferred newly sent plan while idle', () async {
    final oldPlan = _plan(
      [_scriptTask(id: 'old-task')],
      id: 'old-plan',
      name: 'Old',
    );
    final newPlan = _plan(
      [
        _scriptTask(
          id: 'new-task',
          planId: 'new-plan',
        ),
      ],
      id: 'new-plan',
      name: 'New',
      updatedAt: DateTime.utc(2027),
    );
    await queueService.savePlans([oldPlan, newPlan]);
    final viewModel = ProductionQueueViewModel(
      plans: [oldPlan],
      queueService: queueService,
    );

    await viewModel.load(preferredPlanId: newPlan.id);

    expect(viewModel.selectedPlan?.id, newPlan.id);
    expect(viewModel.selectedTask?.id, 'new-task');
  });

  test('applies persisted task deletions without reloading production plans',
      () {
    final targetPlan = _plan([
      _scriptTask(id: 'task-delete'),
      _scriptTask(id: 'task-kept', frameIndex: 2),
    ]);
    final siblingPlan = _plan(
      [
        _scriptTask(
          id: 'task-sibling',
          planId: 'plan-2',
        ),
      ],
      id: 'plan-2',
      name: 'Sibling',
    );
    final viewModel = ProductionQueueViewModel(
      plans: [targetPlan, siblingPlan],
    );
    final deletedAt = DateTime.utc(2026, 7, 24, 9);
    var notifications = 0;
    viewModel.addListener(() {
      notifications += 1;
    });

    viewModel.applyPersistedTaskDeletions(
      taskIdsByPlanId: const {
        'plan-1': {'task-delete'},
      },
      updatedAt: deletedAt,
    );

    expect(notifications, 1);
    expect(viewModel.plans, hasLength(2));
    expect(viewModel.plans.first.tasks.map((task) => task.id), ['task-kept']);
    expect(viewModel.plans.first.updatedAt, deletedAt);
    expect(identical(viewModel.plans.last, siblingPlan), isTrue);
    expect(viewModel.selectedTask?.id, 'task-kept');

    viewModel.applyPersistedTaskDeletions(
      taskIdsByPlanId: const {
        'plan-1': {'task-kept'},
      },
      updatedAt: deletedAt.add(const Duration(minutes: 1)),
    );

    expect(notifications, 2);
    expect(viewModel.plans.map((plan) => plan.id), ['plan-2']);
    expect(viewModel.selectedTask?.id, 'task-sibling');
  });

  test('start runs queued tasks and saves the updated plan', () async {
    await queueService.savePlans([
      _plan([_scriptTask(id: 'task-1')])
    ]);
    final requestedInputs = <String>[];
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) async {
          requestedInputs.add(payload['input'] as String);
          return _fakePngBytes;
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      ),
    );

    await viewModel.start();

    expect(requestedInputs, ['frame 1']);
    expect(viewModel.completedTasks, 1);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.outputImagePath, 'C:/out/task-1.png');
    final saved = await queueService.loadPlans();
    expect(saved.single.tasks.single.status, ProductionTaskStatus.completed);
    expect(saved.single.tasks.single.outputImagePath, 'C:/out/task-1.png');
  });

  test('start passes request interval to the sequential executor', () async {
    final delays = <Duration>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(id: 'task-1'),
          _scriptTask(id: 'task-2', frameIndex: 2),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        requestIntervalSeconds: 55,
      ),
      executorService: _executor(
        delay: (duration) async {
          delays.add(duration);
        },
      ),
    );

    await viewModel.start();

    expect(delays, [const Duration(seconds: 55)]);
    expect(viewModel.completedTasks, 2);
  });

  test('start adds the configured random interval range to queue delays',
      () async {
    final delays = <Duration>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(id: 'task-1'),
          _scriptTask(id: 'task-2', frameIndex: 2),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        requestIntervalSeconds: 55,
        requestIntervalRandomRangeSeconds: 20,
      ),
      executorService: _executor(
        delay: (duration) async {
          delays.add(duration);
        },
        randomInt: (_) => 7,
      ),
    );

    await viewModel.start();

    expect(delays, [const Duration(seconds: 62)]);
    expect(viewModel.completedTasks, 2);
  });

  test('setRequestIntervalRandomRangeText clamps invalid ranges to zero', () {
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      settings: const ProductionQueueExecutionSettings(
        requestIntervalRandomRangeSeconds: 12,
      ),
    );

    viewModel.setRequestIntervalRandomRangeText('-5');

    expect(viewModel.requestIntervalRandomRangeSeconds, 0);
  });

  test('setRetryOn429DelaySecondsText clamps invalid values to one', () {
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      settings: const ProductionQueueExecutionSettings(
        retryOn429DelaySeconds: 12,
      ),
    );

    viewModel.setRetryOn429DelaySecondsText('0');

    expect(viewModel.retryOn429DelaySeconds, 1);
  });

  test('start passes 429 retry delay to the executor', () async {
    final delays = <Duration>[];
    var attempts = 0;
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      settings: const ProductionQueueExecutionSettings(
        retryCount: 2,
        retryOn429DelaySeconds: 23,
      ),
      executorService: _executor(
        requestImage: (_) async {
          attempts += 1;
          if (attempts == 1) {
            throw const ProductionNaiApiException(
              statusCode: 429,
              message: '{"statusCode":429,"message":"Concurrent generation"}',
            );
          }
          return _fakePngBytes;
        },
        delay: (duration) async {
          delays.add(duration);
        },
      ),
    );

    await viewModel.start();

    expect(delays, [const Duration(seconds: 23)]);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.attempts, 2);
  });

  test('pending execution settings save does not overwrite newer numeric edits',
      () async {
    final blockingQueueService = _BlockingExecutionSettingsQueueService(
      workspaceService: workspaceService,
    );
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      queueService: blockingQueueService,
    );

    viewModel.setRequestIntervalSecondsText('3');
    await blockingQueueService.firstSaveStarted.future;

    viewModel.setRequestIntervalSecondsText('30');
    viewModel.setRequestIntervalRandomRangeText('45');
    viewModel.setRetryOn429DelaySecondsText('90');

    blockingQueueService.releaseFirstSave();
    await viewModel.flushPendingExecutionSettingsSaves();

    expect(viewModel.requestIntervalSeconds, 30);
    expect(viewModel.requestIntervalRandomRangeSeconds, 45);
    expect(
      viewModel.selectedPlan?.executionSettings?.requestIntervalSeconds,
      30,
    );
    expect(
      viewModel
          .selectedPlan?.executionSettings?.requestIntervalRandomRangeSeconds,
      45,
    );
    expect(
        viewModel.selectedPlan?.executionSettings?.retryOn429DelaySeconds, 90);
  });

  test('pickOutputDirectory updates the editable output path', () async {
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      settings: const ProductionQueueExecutionSettings(
        outputDirectory: r'C:\old-output',
      ),
      pickOutputDirectory: () async => r'D:\picked-output',
    );

    await viewModel.pickOutputDirectory();

    expect(viewModel.outputDirectory, r'D:\picked-output');
  });

  test('setRetryIndefinitely toggles infinite retry mode', () {
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      settings: const ProductionQueueExecutionSettings(
        retryCount: 2,
        retryIndefinitely: false,
      ),
    );

    viewModel.setRetryIndefinitely(true);

    expect(viewModel.retryIndefinitely, isTrue);
    expect(viewModel.retryCount, 2);
  });

  test('start passes infinite retry mode to the executor', () async {
    var attempts = 0;
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      settings: const ProductionQueueExecutionSettings(
        retryCount: 1,
        retryIndefinitely: true,
      ),
      executorService: _executor(
        requestImage: (_) async {
          attempts += 1;
          if (attempts < 3) {
            throw StateError('temporary $attempts');
          }
          return _fakePngBytes;
        },
      ),
    );

    await viewModel.start();

    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.attempts, 3);
  });

  test('start applies configured generation settings before requesting image',
      () async {
    final requestedPayloads = <Map<String, dynamic>>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(
            id: 'task-1',
            model: 'nai-diffusion-3',
            width: 704,
            height: 1472,
            steps: 18,
            scale: 4.0,
            sampler: 'k_euler',
          ),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        model: 'nai-diffusion-4-5-full',
        width: 832,
        height: 1216,
        steps: 28,
        scale: 6.5,
        sampler: 'k_euler_ancestral',
      ),
      executorService: _executor(
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return _fakePngBytes;
        },
      ),
    );

    await viewModel.start();

    final payload = requestedPayloads.single;
    final parameters = payload['parameters'] as Map;
    expect(payload['model'], 'nai-diffusion-4-5-full');
    expect(parameters['width'], 832);
    expect(parameters['height'], 1216);
    expect(parameters['steps'], 28);
    expect(parameters['scale'], 6.5);
    expect(parameters['sampler'], 'k_euler_ancestral');
    expect(viewModel.selectedTask?.payload['model'], 'nai-diffusion-4-5-full');
  });

  test('start applies advanced generation settings and normalizes companions',
      () async {
    final requestedPayloads = <Map<String, dynamic>>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(
            id: 'task-1',
            model: 'nai-diffusion-3',
            width: 704,
            height: 1472,
            sampler: 'k_euler',
          ).copyWith(
            payload: const {
              'input': 'frame 1',
              'model': 'nai-diffusion-3',
              'action': 'generate',
              'parameters': {
                'width': 704,
                'height': 1472,
                'sampler': 'k_euler',
                'cfg_rescale': 0.1,
                'noise_schedule': 'native',
                'sm': true,
                'sm_dyn': true,
                'dynamic_thresholding': false,
                'v4_prompt': {
                  'caption': {
                    'base_caption': 'frame 1',
                    'char_captions': [],
                  },
                  'use_coords': true,
                },
                'v4_negative_prompt': {
                  'caption': {
                    'base_caption': '',
                    'char_captions': [],
                  },
                  'legacy_uc': false,
                },
                'seed': 1,
              },
            },
          ),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        model: 'nai-diffusion-4-5-full',
        width: 832,
        height: 1216,
        sampler: 'k_euler_ancestral',
        cfgRescale: 0.4,
        noiseSchedule: 'exponential',
        sm: true,
        smDyn: true,
        dynamicThresholding: true,
        varietyPlus: true,
        autoPosition: true,
        legacyUc: true,
      ),
      executorService: _executor(
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return _fakePngBytes;
        },
      ),
    );

    await viewModel.start();

    final payload = requestedPayloads.single;
    final parameters = payload['parameters'] as Map<String, dynamic>;
    expect(payload['model'], 'nai-diffusion-4-5-full');
    expect(parameters['cfg_rescale'], 0.4);
    expect(parameters['noise_schedule'], 'exponential');
    expect(parameters, isNot(contains('sm')));
    expect(parameters, isNot(contains('sm_dyn')));
    expect(parameters['dynamic_thresholding'], isTrue);
    expect(parameters['skip_cfg_above_sigma'], closeTo(19.0, 0.001));
    expect(parameters['prefer_brownian'], isTrue);
    expect(parameters['deliberate_euler_ancestral_bug'], isFalse);
    expect(parameters['legacy_uc'], isTrue);
    expect(
      (parameters['v4_prompt'] as Map<String, dynamic>)['use_coords'],
      isFalse,
    );
    expect(
      (parameters['v4_negative_prompt'] as Map<String, dynamic>)['legacy_uc'],
      isTrue,
    );
  });

  test('empty batch defaults leave existing companion parameters untouched',
      () async {
    final requestedPayloads = <Map<String, dynamic>>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(id: 'task-1').copyWith(
            payload: const {
              'input': 'frame 1',
              'model': 'nai-diffusion-3',
              'action': 'generate',
              'parameters': {
                'sampler': 'k_euler',
                'noise_schedule': 'native',
                'sm': true,
                'sm_dyn': true,
                'prefer_brownian': true,
                'deliberate_euler_ancestral_bug': true,
                'seed': 1,
              },
            },
          ),
        ])
      ],
      executorService: _executor(
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return _fakePngBytes;
        },
      ),
    );

    await viewModel.start();

    final parameters =
        requestedPayloads.single['parameters'] as Map<String, dynamic>;
    expect(parameters['sm'], isTrue);
    expect(parameters['sm_dyn'], isTrue);
    expect(parameters['prefer_brownian'], isTrue);
    expect(parameters['deliberate_euler_ancestral_bug'], isTrue);
  });

  test('start can preserve original generation settings when enabled',
      () async {
    final requestedPayloads = <Map<String, dynamic>>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(
            id: 'task-1',
            model: 'nai-diffusion-3',
            width: 704,
            height: 1472,
            steps: 18,
            scale: 4.0,
            sampler: 'k_euler',
          ),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        model: 'nai-diffusion-4-5-full',
        width: 832,
        height: 1216,
        steps: 28,
        scale: 6.5,
        sampler: 'k_euler_ancestral',
      ),
      executorService: _executor(
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return _fakePngBytes;
        },
      ),
    );
    viewModel.setUseOriginalGenerationSettings(true);

    await viewModel.start();

    final payload = requestedPayloads.single;
    final parameters = payload['parameters'] as Map;
    expect(payload['model'], 'nai-diffusion-3');
    expect(parameters['width'], 704);
    expect(parameters['height'], 1472);
    expect(parameters['steps'], 18);
    expect(parameters['scale'], 4.0);
    expect(parameters['sampler'], 'k_euler');
  });

  test('start normalizes edit requests even when preserving original settings',
      () async {
    final requestedPayloads = <Map<String, dynamic>>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(
            id: 'task-1',
            payload: const {
              'input': 'frame 1',
              'model': 'nai-diffusion-4-5-full',
              'action': 'generate',
              'parameters': {
                'request_type': 'NativeInfillingRequest',
                'add_original_image': false,
                'img2img': 'source-image',
                'mask': 'mask-image',
                'v4_prompt': {
                  'use_coords': true,
                  'caption': {
                    'base_caption': 'scene prompt',
                    'char_captions': [
                      {'char_caption': 'first character'},
                    ],
                  },
                },
                'seed': 1,
              },
            },
          ),
        ])
      ],
      executorService: _executor(
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return _fakePngBytes;
        },
      ),
    );
    viewModel.setUseOriginalGenerationSettings(true);

    await viewModel.start();

    final parameters = requestedPayloads.single['parameters'] as Map;
    expect(parameters['request_type'], 'PromptGenerateRequest');
    expect(parameters, isNot(contains('add_original_image')));
    expect(parameters, isNot(contains('img2img')));
    expect(parameters, isNot(contains('mask')));
    final prompt = parameters['v4_prompt'] as Map;
    expect(prompt['use_coords'], isFalse);
    final caption = prompt['caption'] as Map;
    final charCaptions = caption['char_captions'] as List;
    expect((charCaptions.single as Map)['centers'], [
      {'x': 0.5, 'y': 0.5},
    ]);
    expect(parameters['seed'], 1);
  });

  test('start merges the batch default into the outgoing negative prompt',
      () async {
    final requestedPayloads = <Map<String, dynamic>>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(
            id: 'task-1',
            payload: const {
              'input': 'frame 1',
              'parameters': {
                'negative_prompt': 'source negative',
                'v4_negative_prompt': {
                  'caption': {
                    'base_caption': 'source negative',
                    'char_captions': [],
                  },
                },
                'seed': 1,
              },
            },
          ),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        useOriginalGenerationSettings: true,
      ),
      executorService: _executor(
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return _fakePngBytes;
        },
      ),
    );

    await viewModel.start();

    final parameters =
        requestedPayloads.single['parameters'] as Map<String, dynamic>;
    final expected = '$defaultBatchNegativePrompt, source negative';
    expect(parameters['negative_prompt'], expected);
    final negative = parameters['v4_negative_prompt'] as Map<String, dynamic>;
    final caption = negative['caption'] as Map<String, dynamic>;
    expect(caption['base_caption'], expected);
  });

  test('start can mix original and custom generation settings', () async {
    final requestedPayloads = <Map<String, dynamic>>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(
            id: 'task-1',
            model: 'nai-diffusion-3',
            width: 704,
            height: 1472,
            steps: 18,
            scale: 4.0,
            sampler: 'k_euler',
          ),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        model: 'nai-diffusion-4-5-full',
        width: 832,
        height: 1216,
        steps: 28,
        scale: 6.5,
        sampler: 'k_euler_ancestral',
      ),
      executorService: _executor(
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return _fakePngBytes;
        },
      ),
    );
    viewModel.setUseOriginalSampler(true);
    viewModel.setBatchScaleText('7.25');

    await viewModel.start();

    final payload = requestedPayloads.single;
    final parameters = payload['parameters'] as Map;
    expect(payload['model'], 'nai-diffusion-4-5-full');
    expect(parameters['width'], 832);
    expect(parameters['height'], 1216);
    expect(parameters['steps'], 28);
    expect(parameters['scale'], 7.25);
    expect(parameters['sampler'], 'k_euler');
  });

  test('start randomizes seed per task when seed is -1', () async {
    final requestedSeeds = <int>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(id: 'task-1'),
          _scriptTask(id: 'task-2', frameIndex: 2),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        useOriginalGenerationSettings: true,
      ),
      executorService: _executor(
        randomInt: (upperBound) => requestedSeeds.isEmpty ? 101 : 202,
        requestImage: (payload) async {
          requestedSeeds.add((payload['parameters'] as Map)['seed'] as int);
          return _fakePngBytes;
        },
      ),
    );
    viewModel.setUseOriginalSeed(false);
    viewModel.setBatchSeedText('-1');

    await viewModel.start();

    expect(requestedSeeds, [101, 202]);
  });

  test('seed text parser keeps -1 as the editable random sentinel', () {
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
    );

    expect(viewModel.batchSeed, -1);

    viewModel.setBatchSeedText('777');
    expect(viewModel.batchSeed, 777);

    viewModel.setBatchSeedText('');
    expect(viewModel.batchSeed, -1);

    viewModel.setBatchSeedText('-2');
    expect(viewModel.batchSeed, -1);
  });

  test('start applies configured fixed seed to every task', () async {
    final requestedSeeds = <int>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([
          _scriptTask(id: 'task-1'),
          _scriptTask(id: 'task-2', frameIndex: 2),
        ])
      ],
      settings: const ProductionQueueExecutionSettings(
        useOriginalGenerationSettings: true,
      ),
      executorService: _executor(
        requestImage: (payload) async {
          requestedSeeds.add((payload['parameters'] as Map)['seed'] as int);
          return _fakePngBytes;
        },
      ),
    );
    viewModel.setUseOriginalSeed(false);
    viewModel.setBatchSeedText('777');

    await viewModel.start();

    expect(requestedSeeds, [777, 777]);
  });

  test('load restores persisted execution settings from the selected plan',
      () async {
    await queueService.savePlans([
      _plan(
        [_scriptTask(id: 'task-1')],
        executionSettings: const ProductionPlanExecutionSettings(
          model: 'nai-diffusion-4-5-full',
          sampler: 'k_euler_ancestral',
          width: 832,
          height: 1216,
          steps: 28,
          scale: 4,
          useOriginalSampler: true,
          requestIntervalSeconds: 15,
          requestIntervalRandomRangeSeconds: 20,
          retryCount: 2,
          retryIndefinitely: true,
          outputDirectory: r'C:\outputs',
        ),
      ),
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: queueService,
      settings: const ProductionQueueExecutionSettings(
        model: 'global-model',
        sampler: 'global-sampler',
        width: 512,
        height: 768,
        steps: 12,
        scale: 2,
        requestIntervalSeconds: 3,
        outputDirectory: r'C:\global',
      ),
    );

    await viewModel.load();

    expect(viewModel.batchModel, 'nai-diffusion-4-5-full');
    expect(viewModel.batchSampler, 'k_euler_ancestral');
    expect(viewModel.batchWidth, 832);
    expect(viewModel.batchHeight, 1216);
    expect(viewModel.batchSteps, 28);
    expect(viewModel.batchScale, 4);
    expect(viewModel.useOriginalSampler, isTrue);
    expect(viewModel.requestIntervalSeconds, 15);
    expect(viewModel.requestIntervalRandomRangeSeconds, 20);
    expect(viewModel.retryCount, 2);
    expect(viewModel.retryIndefinitely, isTrue);
    expect(viewModel.outputDirectory, r'C:\outputs');
  });

  test('load falls back to the latest persisted execution settings', () async {
    await queueService.savePlans([
      _plan(
        [_scriptTask(id: 'task-current', planId: 'plan-current')],
        id: 'plan-current',
        updatedAt: DateTime.utc(2026, 6, 3),
      ),
      _plan(
        [_scriptTask(id: 'task-older', planId: 'plan-older')],
        id: 'plan-older',
        updatedAt: DateTime.utc(2026, 5, 30),
        executionSettings: const ProductionPlanExecutionSettings(
          model: 'older-model',
          requestIntervalSeconds: 5,
        ),
      ),
      _plan(
        [_scriptTask(id: 'task-latest', planId: 'plan-latest')],
        id: 'plan-latest',
        updatedAt: DateTime.utc(2026, 6, 2),
        executionSettings: const ProductionPlanExecutionSettings(
          model: 'latest-model',
          sampler: 'latest-sampler',
          width: 832,
          height: 1216,
          steps: 28,
          scale: 7,
          requestIntervalSeconds: 21,
          retryCount: 3,
          outputDirectory: r'D:\latest-output',
        ),
      ),
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: queueService,
      settings: const ProductionQueueExecutionSettings(
        model: 'default-model',
        sampler: 'default-sampler',
        requestIntervalSeconds: 1,
      ),
    );

    await viewModel.load();

    expect(viewModel.selectedPlan?.id, 'plan-current');
    expect(viewModel.batchModel, 'latest-model');
    expect(viewModel.batchSampler, 'latest-sampler');
    expect(viewModel.batchWidth, 832);
    expect(viewModel.batchHeight, 1216);
    expect(viewModel.batchSteps, 28);
    expect(viewModel.batchScale, 7);
    expect(viewModel.requestIntervalSeconds, 21);
    expect(viewModel.retryCount, 3);
    expect(viewModel.outputDirectory, r'D:\latest-output');
  });

  test('editing execution settings persists them on the selected plan',
      () async {
    await queueService.savePlans([
      _plan([_scriptTask(id: 'task-1')])
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
    );

    viewModel.setBatchModel('nai-diffusion-4-5-full');
    viewModel.setBatchSampler('k_euler_ancestral');
    viewModel.setBatchWidthText('832');
    viewModel.setBatchHeightText('1216');
    viewModel.setBatchStepsText('28');
    viewModel.setBatchScaleText('4');
    viewModel.setUseOriginalSampler(true);
    viewModel.setRequestIntervalSecondsText('15');
    viewModel.setRequestIntervalRandomRangeText('20');
    viewModel.setRetryCountText('2');
    viewModel.setRetryIndefinitely(true);
    viewModel.setOutputDirectory(r'C:\outputs');
    await viewModel.flushPendingExecutionSettingsSaves();

    final saved = await queueService.loadPlans();
    final executionSettings = saved.single.executionSettings;
    expect(executionSettings?.model, 'nai-diffusion-4-5-full');
    expect(executionSettings?.sampler, 'k_euler_ancestral');
    expect(executionSettings?.width, 832);
    expect(executionSettings?.height, 1216);
    expect(executionSettings?.steps, 28);
    expect(executionSettings?.scale, 4);
    expect(executionSettings?.useOriginalSampler, isTrue);
    expect(executionSettings?.requestIntervalSeconds, 15);
    expect(executionSettings?.requestIntervalRandomRangeSeconds, 20);
    expect(executionSettings?.retryCount, 2);
    expect(executionSettings?.retryIndefinitely, isTrue);
    expect(executionSettings?.outputDirectory, r'C:\outputs');
  });

  test('editing execution settings persists last-used settings without a plan',
      () async {
    final viewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: queueService,
      settings: const ProductionQueueExecutionSettings(
        model: 'default-model',
        sampler: 'default-sampler',
        requestIntervalSeconds: 1,
      ),
    );

    viewModel.setBatchModel('nai-diffusion-4-5-full');
    viewModel.setBatchSampler('k_euler_ancestral');
    viewModel.setBatchWidthText('832');
    viewModel.setBatchHeightText('1216');
    viewModel.setBatchStepsText('28');
    viewModel.setBatchScaleText('4');
    viewModel.setUseOriginalSampler(true);
    viewModel.setRequestIntervalSecondsText('15');
    viewModel.setRequestIntervalRandomRangeText('20');
    viewModel.setRetryCountText('2');
    viewModel.setRetryIndefinitely(true);
    viewModel.setOutputDirectory(r'C:\outputs');
    await viewModel.flushPendingExecutionSettingsSaves();

    final lastUsed = await queueService.loadLastExecutionSettings();
    expect(lastUsed?.model, 'nai-diffusion-4-5-full');
    expect(lastUsed?.sampler, 'k_euler_ancestral');
    expect(lastUsed?.width, 832);
    expect(lastUsed?.height, 1216);
    expect(lastUsed?.steps, 28);
    expect(lastUsed?.scale, 4);
    expect(lastUsed?.useOriginalSampler, isTrue);
    expect(lastUsed?.requestIntervalSeconds, 15);
    expect(lastUsed?.requestIntervalRandomRangeSeconds, 20);
    expect(lastUsed?.retryCount, 2);
    expect(lastUsed?.retryIndefinitely, isTrue);
    expect(lastUsed?.outputDirectory, r'C:\outputs');
  });

  test('start exposes running task state while the image request is in flight',
      () async {
    await queueService.savePlans([
      _plan([_scriptTask(id: 'task-1')])
    ]);
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      ),
    );

    final startFuture = viewModel.start();
    await requestStarted.future;

    expect(viewModel.runningTasks, 1);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.running);
    expect(viewModel.selectedTask?.attempts, 1);

    final savedDuringRun = await queueService.loadPlans();
    expect(savedDuringRun.single.tasks.single.status,
        ProductionTaskStatus.running);

    requestCompleter.complete(_fakePngBytes);
    await startFuture;

    expect(viewModel.completedTasks, 1);
  });

  test(
      'loading a newly enqueued plan while running keeps the active plan in control',
      () async {
    final activePlan = _plan(
      [
        _scriptTask(id: 'active-task-1'),
        _scriptTask(id: 'active-task-2', frameIndex: 2),
      ],
      executionSettings: const ProductionPlanExecutionSettings(
        width: 832,
        height: 1216,
      ),
    );
    await queueService.savePlans([activePlan]);
    final requestedInputs = <String>[];
    final firstRequestStarted = Completer<void>();
    final firstRequestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) {
          final input = payload['input'] as String;
          requestedInputs.add(input);
          if (!firstRequestStarted.isCompleted) {
            firstRequestStarted.complete();
            return firstRequestCompleter.future;
          }
          return Future.value(_fakePngBytes);
        },
      ),
    );

    final startFuture = viewModel.start();
    await firstRequestStarted.future;

    final newlyEnqueuedPlan = _plan(
      [
        _scriptTask(
          id: 'new-task',
          planId: 'new-plan',
          payload: const {
            'input': 'new plan frame',
            'parameters': {'seed': 3},
          },
        ),
      ],
      id: 'new-plan',
      name: 'Newly Enqueued',
      updatedAt: DateTime.utc(2027),
    );
    await queueService.savePlanChanges(
      updatedPlans: [newlyEnqueuedPlan],
      deletedPlanIds: const [],
    );
    await viewModel.load(preferredPlanId: newlyEnqueuedPlan.id);

    expect(viewModel.isExecuting, isTrue);
    expect(viewModel.selectedPlan?.id, activePlan.id);
    expect(viewModel.plans.map((plan) => plan.id), [
      activePlan.id,
      newlyEnqueuedPlan.id,
    ]);

    firstRequestCompleter.complete(_fakePngBytes);
    await startFuture;

    expect(requestedInputs, ['frame 1', 'frame 2']);
    expect(viewModel.isExecuting, isFalse);
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == activePlan.id)
          .tasks
          .map((task) => task.status),
      [ProductionTaskStatus.completed, ProductionTaskStatus.completed],
    );
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == newlyEnqueuedPlan.id)
          .tasks
          .single
          .status,
      ProductionTaskStatus.queued,
    );
    final savedPlans = await queueService.loadPlansReadOnly();
    expect(
        savedPlans.map((plan) => plan.id),
        containsAll([
          activePlan.id,
          newlyEnqueuedPlan.id,
        ]));
  });

  test('switching queue tabs while running does not switch execution plans',
      () async {
    final activePlan = _plan(
      [
        _scriptTask(id: 'active-task-1'),
        _scriptTask(id: 'active-task-2', frameIndex: 2),
      ],
      executionSettings: const ProductionPlanExecutionSettings(
        width: 832,
        height: 1216,
      ),
    );
    final waitingPlan = _plan(
      [
        _scriptTask(
          id: 'waiting-task',
          planId: 'waiting-plan',
          payload: const {
            'input': 'waiting frame',
            'parameters': {'seed': 9},
          },
        ),
      ],
      id: 'waiting-plan',
      name: 'Waiting',
      executionSettings: const ProductionPlanExecutionSettings(
        width: 1024,
        height: 1024,
      ),
    );
    final requestedInputs = <String>[];
    final requestedWidths = <int?>[];
    final firstRequestStarted = Completer<void>();
    final firstRequestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: [activePlan, waitingPlan],
      settings: const ProductionQueueExecutionSettings(
        width: 832,
        height: 1216,
      ),
      executorService: _executor(
        requestImage: (payload) {
          final input = payload['input'] as String;
          requestedInputs.add(input);
          final parameters = payload['parameters'] as Map;
          requestedWidths.add(parameters['width'] as int?);
          if (!firstRequestStarted.isCompleted) {
            firstRequestStarted.complete();
            return firstRequestCompleter.future;
          }
          return Future.value(_fakePngBytes);
        },
      ),
    );

    final startFuture = viewModel.start();
    await firstRequestStarted.future;

    expect(viewModel.selectPlan(waitingPlan.id), isTrue);
    expect(viewModel.selectedPlan?.id, waitingPlan.id);
    expect(viewModel.activePlan?.id, activePlan.id);
    expect(viewModel.isViewingActivePlan, isFalse);
    expect(viewModel.canEditSelectedPlanSettings, isFalse);

    firstRequestCompleter.complete(_fakePngBytes);
    await startFuture;

    expect(requestedInputs, ['frame 1', 'frame 2']);
    expect(requestedWidths, [832, 832]);
    expect(viewModel.selectedPlan?.id, waitingPlan.id);
    expect(viewModel.activePlan, isNull);
    expect(viewModel.canEditSelectedPlanSettings, isTrue);
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == waitingPlan.id)
          .tasks
          .single
          .status,
      ProductionTaskStatus.queued,
    );
  });

  test('task completion does not overwrite a concurrently enqueued plan',
      () async {
    final activePlan = _plan([_scriptTask(id: 'active-task')]);
    await queueService.savePlans([activePlan]);
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final startFuture = viewModel.start();
    await requestStarted.future;

    final newlyEnqueuedPlan = _plan(
      [
        _scriptTask(
          id: 'new-task',
          planId: 'new-plan',
        ),
      ],
      id: 'new-plan',
      name: 'Newly Enqueued',
      updatedAt: DateTime.utc(2027),
    );
    await queueService.savePlanChanges(
      updatedPlans: [newlyEnqueuedPlan],
      deletedPlanIds: const [],
    );

    requestCompleter.complete(_fakePngBytes);
    await startFuture;

    final savedPlans = await queueService.loadPlansReadOnly();
    expect(
        savedPlans.map((plan) => plan.id),
        containsAll([
          activePlan.id,
          newlyEnqueuedPlan.id,
        ]));
    expect(
      savedPlans
          .singleWhere((plan) => plan.id == activePlan.id)
          .tasks
          .single
          .status,
      ProductionTaskStatus.completed,
    );
    expect(
      savedPlans
          .singleWhere((plan) => plan.id == newlyEnqueuedPlan.id)
          .tasks
          .single
          .status,
      ProductionTaskStatus.queued,
    );
  });

  test('pause requests halt after current task and exposes resume state',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(id: 'task-1'),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final firstRequestStarted = Completer<void>();
    final firstRequestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (_) {
          firstRequestStarted.complete();
          return firstRequestCompleter.future;
        },
      ),
    );

    final startFuture = viewModel.start();
    await firstRequestStarted.future;

    expect(viewModel.isExecuting, isTrue);
    expect(viewModel.canPause, isTrue);

    viewModel.pause();

    expect(viewModel.pauseRequested, isTrue);
    expect(viewModel.canPause, isFalse);

    firstRequestCompleter.complete(_fakePngBytes);
    await startFuture;

    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.pauseRequested, isFalse);
    expect(viewModel.canResume, isTrue);
    expect(viewModel.selectedPlan?.tasks[0].status,
        ProductionTaskStatus.completed);
    expect(
        viewModel.selectedPlan?.tasks[1].status, ProductionTaskStatus.queued);
  });

  test('stop resets the queue so the next start begins from the first task',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(
          id: 'task-1',
          status: ProductionTaskStatus.completed,
          attempts: 1,
          outputImagePath: 'C:/old/task-1.png',
        ),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final firstRequestStarted = Completer<void>();
    final staleRequestCompleter = Completer<Uint8List>();
    final requestedInputs = <String>[];
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) {
          final input = payload['input'] as String;
          requestedInputs.add(input);
          if (!firstRequestStarted.isCompleted) {
            firstRequestStarted.complete();
            return staleRequestCompleter.future;
          }
          return Future.value(_fakePngBytes);
        },
      ),
    );

    final staleStart = viewModel.start();
    await firstRequestStarted.future;

    await viewModel.stop();

    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.isPaused, isFalse);
    expect(viewModel.selectedPlan?.tasks.map((task) => task.status), [
      ProductionTaskStatus.queued,
      ProductionTaskStatus.queued,
    ]);
    expect(viewModel.selectedPlan?.tasks.first.attempts, 0);
    expect(viewModel.selectedPlan?.tasks.first.outputImagePath, isNull);

    staleRequestCompleter.complete(_fakePngBytes);
    await staleStart;

    await viewModel.start();

    expect(requestedInputs, ['frame 2', 'frame 1', 'frame 2']);
    expect(viewModel.completedTasks, 2);
  });

  test('pause stops after the current task and resume continues queued work',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(id: 'task-1'),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final requestedInputs = <String>[];
    final firstRequestStarted = Completer<void>();
    final firstRequestCompleter = Completer<Uint8List>();
    final secondRequestStarted = Completer<void>();
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) {
          final input = payload['input'] as String;
          requestedInputs.add(input);
          if (input == 'frame 1') {
            firstRequestStarted.complete();
            return firstRequestCompleter.future;
          }
          secondRequestStarted.complete();
          return Future.value(_fakePngBytes);
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      ),
    );

    final startFuture = viewModel.start();
    await firstRequestStarted.future;

    viewModel.pause();
    firstRequestCompleter.complete(_fakePngBytes);
    await startFuture;

    expect(requestedInputs, ['frame 1']);
    expect(viewModel.completedTasks, 1);
    expect(
        viewModel.selectedPlan?.tasks[1].status, ProductionTaskStatus.queued);

    await viewModel.resume();

    expect(requestedInputs, ['frame 1', 'frame 2']);
    expect(secondRequestStarted.isCompleted, isTrue);
    expect(viewModel.completedTasks, 2);
    expect(
      viewModel.selectedPlan?.tasks[1].status,
      ProductionTaskStatus.completed,
    );
  });

  test('running queue applies execution setting edits to subsequent tasks',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(id: 'task-1'),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final requestedWidths = <int?>[];
    final requestedHeights = <int?>[];
    final firstRequestStarted = Completer<void>();
    final firstRequestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      settings: const ProductionQueueExecutionSettings(
        width: 832,
        height: 1216,
      ),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) {
          final parameters = payload['parameters'] as Map;
          requestedWidths.add(parameters['width'] as int?);
          requestedHeights.add(parameters['height'] as int?);
          if (!firstRequestStarted.isCompleted) {
            firstRequestStarted.complete();
            return firstRequestCompleter.future;
          }
          return Future.value(_fakePngBytes);
        },
      ),
    );

    final startFuture = viewModel.start();
    await firstRequestStarted.future;

    viewModel.setBatchWidthText('960');
    viewModel.setBatchHeightText('1280');
    firstRequestCompleter.complete(_fakePngBytes);
    await startFuture;

    expect(requestedWidths, [832, 960]);
    expect(requestedHeights, [1216, 1280]);
    expect(viewModel.selectedPlan?.tasks[1].payload['parameters'],
        containsPair('width', 960));
  });

  test('quick rerun inserts a queued clone after the running task', () async {
    final completed = _scriptTask(
      id: 'task-done',
      frameIndex: 9,
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-done.png',
      suggestedFileName: 'old-task-done.png',
    );
    await queueService.savePlans([
      _plan([
        completed,
        _scriptTask(id: 'task-1'),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final requestedInputs = <String>[];
    final firstRequestStarted = Completer<void>();
    final firstRequestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) {
          final input = payload['input'] as String;
          requestedInputs.add(input);
          if (!firstRequestStarted.isCompleted) {
            firstRequestStarted.complete();
            return firstRequestCompleter.future;
          }
          return Future.value(_fakePngBytes);
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      ),
    );

    final startFuture = viewModel.start();
    await firstRequestStarted.future;

    final clone = await viewModel.queueRerunTask(completed);
    firstRequestCompleter.complete(_fakePngBytes);
    await startFuture;

    expect(clone?.id, 'task-done-rerun');
    expect(requestedInputs, ['frame 1', 'frame 9', 'frame 2']);
    expect(viewModel.selectedPlan?.tasks.map((task) => task.id), [
      'task-done',
      'task-1',
      'task-done-rerun',
      'task-2',
    ]);
    final rerun = viewModel.selectedPlan?.tasks[2];
    expect(rerun?.status, ProductionTaskStatus.completed);
    expect(rerun?.attempts, 1);
    expect(rerun?.outputImagePath, 'C:/out/task-done-rerun.png');
    expect(rerun?.suggestedFileName, 'task-done-rerun.png');
  });

  test('queueRerunTask keeps multiple inserted reruns in request order',
      () async {
    final completedA = _scriptTask(
      id: 'task-done-a',
      frameIndex: 9,
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-done-a.png',
    );
    final completedB = _scriptTask(
      id: 'task-done-b',
      frameIndex: 10,
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-done-b.png',
    );
    await queueService.savePlans([
      _plan([
        completedA,
        completedB,
        _scriptTask(id: 'task-next', frameIndex: 11),
      ])
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
    );

    await viewModel.queueRerunTask(completedA);
    await viewModel.queueRerunTask(completedB);

    expect(viewModel.selectedPlan?.tasks.map((task) => task.id), [
      'task-done-a',
      'task-done-a-rerun',
      'task-done-b',
      'task-done-b-rerun',
      'task-next',
    ]);
  });

  test('queueRerunTask serializes concurrent saves so reruns are not lost',
      () async {
    final completedA = _scriptTask(
      id: 'task-done-a',
      frameIndex: 9,
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-done-a.png',
    );
    final completedB = _scriptTask(
      id: 'task-done-b',
      frameIndex: 10,
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-done-b.png',
    );
    final blockingQueueService = _BlockingPlanSaveQueueService(
      workspaceService: workspaceService,
      initialPlans: [
        _plan([completedA, completedB])
      ],
    );
    final viewModel = ProductionQueueViewModel(
      plans: await blockingQueueService.loadPlans(),
      queueService: blockingQueueService,
    );

    final firstQueue = viewModel.queueRerunTask(completedA);
    await blockingQueueService.firstSaveStarted.future;
    final secondQueue = viewModel.queueRerunTask(completedB);
    await Future<void>.delayed(Duration.zero);
    blockingQueueService.releaseFirstSave();

    final clones = await Future.wait([firstQueue, secondQueue]);

    expect(clones.map((task) => task?.id), [
      'task-done-a-rerun',
      'task-done-b-rerun',
    ]);
    expect(viewModel.selectedPlan?.tasks.map((task) => task.id), [
      'task-done-a',
      'task-done-a-rerun',
      'task-done-b',
      'task-done-b-rerun',
    ]);
  });

  test('restored partial queues expose resume before an in-memory pause',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(
          id: 'task-1',
          status: ProductionTaskStatus.completed,
          attempts: 1,
          outputImagePath: 'C:/out/task-1.png',
        ),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final requestedInputs = <String>[];
    final viewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) async {
          requestedInputs.add(payload['input'] as String);
          return _fakePngBytes;
        },
        saveImage: (bytes, fileName) async => 'C:/resume/$fileName',
      ),
    );

    await viewModel.load();

    expect(viewModel.isPaused, isTrue);
    expect(viewModel.canResume, isTrue);

    await viewModel.resume();

    expect(requestedInputs, ['frame 2']);
    expect(viewModel.completedTasks, 2);
    expect(viewModel.selectedPlan?.tasks[1].outputImagePath,
        'C:/resume/task-2.png');
  });

  test('restored running tasks are requeued before continuing unfinished work',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(
          id: 'task-1',
          status: ProductionTaskStatus.running,
          attempts: 1,
        ),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final requestedInputs = <String>[];
    final viewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) async {
          requestedInputs.add(payload['input'] as String);
          return _fakePngBytes;
        },
      ),
    );

    await viewModel.load();

    expect(viewModel.isPaused, isTrue);
    expect(viewModel.selectedPlan?.tasks.first.status,
        ProductionTaskStatus.queued);

    await viewModel.resume();

    expect(requestedInputs, ['frame 1', 'frame 2']);
    expect(viewModel.completedTasks, 2);
  });

  test('retryFailed refreshes selected task and persisted failed task',
      () async {
    final failed = _scriptTask(
      id: 'task-1',
      status: ProductionTaskStatus.failed,
      attempts: 1,
      error: 'previous failure',
    );
    await queueService.savePlans([
      _plan([failed])
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        saveImage: (bytes, fileName) async => 'C:/retry/$fileName',
      ),
    );

    await viewModel.retryFailed();

    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.attempts, 2);
    expect(viewModel.selectedTask?.error, isNull);
    expect(viewModel.selectedTask?.outputImagePath, 'C:/retry/task-1.png');
    final saved = await queueService.loadPlans();
    expect(saved.single.tasks.single.status, ProductionTaskStatus.completed);
    expect(saved.single.tasks.single.attempts, 2);
  });

  test(
      'rerunAbnormalTasks reruns failed and errored queued tasks with overrides',
      () async {
    final completed = _scriptTask(
      id: 'task-1',
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-1.png',
    );
    final failed = _scriptTask(
      id: 'task-2',
      frameIndex: 2,
      status: ProductionTaskStatus.failed,
      attempts: 1,
      error: 'HTTP 500',
    );
    final erroredQueued = _scriptTask(
      id: 'task-3',
      frameIndex: 3,
      status: ProductionTaskStatus.queued,
      attempts: 1,
      error: 'HandshakeException',
    );
    final normalQueued = _scriptTask(id: 'task-4', frameIndex: 4);
    await queueService.savePlans([
      _plan([completed, failed, erroredQueued, normalQueued])
    ]);
    final requestedInputs = <String>[];
    final requestedModels = <String?>[];
    final requestedWidths = <int?>[];
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      settings: const ProductionQueueExecutionSettings(
        model: 'override-model',
        width: 832,
        height: 1216,
      ),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) async {
          requestedInputs.add(payload['input'] as String);
          requestedModels.add(payload['model'] as String?);
          requestedWidths.add((payload['parameters'] as Map)['width'] as int?);
          return _fakePngBytes;
        },
        saveImage: (bytes, fileName) async => 'C:/rerun/$fileName',
      ),
    );

    await viewModel.rerunAbnormalTasks();

    expect(requestedInputs, ['frame 2', 'frame 3']);
    expect(requestedModels, ['override-model', 'override-model']);
    expect(requestedWidths, [832, 832]);
    expect(viewModel.selectedTask?.id, 'task-2');
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedPlan?.tasks[0].attempts, 1);
    expect(viewModel.selectedPlan?.tasks[1].attempts, 2);
    expect(viewModel.selectedPlan?.tasks[2].attempts, 2);
    expect(
        viewModel.selectedPlan?.tasks[3].status, ProductionTaskStatus.queued);
    expect(viewModel.selectedPlan?.tasks[3].attempts, 0);
    final saved = await queueService.loadPlans();
    expect(saved.single.tasks[1].status, ProductionTaskStatus.completed);
    expect(saved.single.tasks[2].status, ProductionTaskStatus.completed);
    expect(saved.single.tasks[3].status, ProductionTaskStatus.queued);
  });

  test('rerunAbnormalTasks does not revive a dismissed abnormal row', () async {
    final dismissedFailed = _scriptTask(
      id: 'dismissed-failed',
      status: ProductionTaskStatus.failed,
      error: 'old error',
    ).copyWith(queueDismissedAt: DateTime.utc(2026, 6, 2, 11));
    final plan = _plan([dismissedFailed]);
    await queueService.savePlans([plan]);
    final requestedInputs = <String>[];
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlansReadOnly(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) async {
          requestedInputs.add(payload['input'] as String);
          return _fakePngBytes;
        },
        saveImage: (bytes, fileName) async => 'C:/retry/$fileName',
      ),
    );

    expect(viewModel.hasAbnormalTasks, isFalse);
    await viewModel.rerunAbnormalTasks();

    expect(requestedInputs, isEmpty);
    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.plans.single.tasks.single.isQueueDismissed, isTrue);
    expect(viewModel.plans.single.tasks.single.status,
        ProductionTaskStatus.failed);
    final saved = await queueService.loadPlansReadOnly();
    expect(saved.single.tasks.single.isQueueDismissed, isTrue);
    expect(saved.single.tasks.single.status, ProductionTaskStatus.failed);
  });

  test('rerunTask reruns only the selected script frame and refreshes state',
      () async {
    final task1 = _scriptTask(
      id: 'task-1',
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-1.png',
    );
    final task2 = _scriptTask(
      id: 'task-2',
      frameIndex: 2,
      status: ProductionTaskStatus.failed,
      attempts: 2,
      error: 'old error',
    );
    await queueService.savePlans([
      _plan([task1, task2])
    ]);
    final requestedInputs = <String>[];
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (payload) async {
          requestedInputs.add(payload['input'] as String);
          return _fakePngBytes;
        },
        saveImage: (bytes, fileName) async => 'C:/rerun/$fileName',
      ),
    );
    viewModel.selectTask(viewModel.selectedPlan!.tasks[1]);

    await viewModel.rerunTask(viewModel.selectedTask!);

    expect(requestedInputs, ['frame 2']);
    expect(viewModel.selectedTask?.id, 'task-2');
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.attempts, 3);
    expect(viewModel.selectedTask?.error, isNull);
    expect(viewModel.selectedTask?.outputImagePath, 'C:/rerun/task-2.png');
    expect(viewModel.selectedPlan?.tasks.first.attempts, 1);
    final saved = await queueService.loadPlans();
    expect(saved.single.tasks[1].attempts, 3);
  });

  test('rerunTask uses the current plan and exposes running state', () async {
    final completed = _scriptTask(
      id: 'task-1',
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/old/task-1.png',
    );
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([completed])
      ],
      executorService: _executor(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
        saveImage: (bytes, fileName) async => 'C:/rerun/$fileName',
      ),
    );

    final rerunFuture = viewModel.rerunTask(viewModel.selectedTask!);
    await requestStarted.future;

    expect(viewModel.isExecuting, isTrue);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.running);
    expect(viewModel.selectedTask?.attempts, 2);
    expect(viewModel.selectedTask?.outputImagePath, 'C:/old/task-1.png');

    requestCompleter.complete(_fakePngBytes);
    await rerunFuture;

    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.attempts, 2);
    expect(viewModel.selectedTask?.outputImagePath, 'C:/rerun/task-1.png');
  });

  test('exportSelectedTaskJson sends the selected task payload as JSON',
      () async {
    final exports = <String>[];
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      exporter: (content, fileName) async {
        exports.add(content);
        exports.add(fileName);
        return true;
      },
    );

    final exported = await viewModel.exportSelectedTaskJson();

    expect(exported, isTrue);
    expect(jsonDecode(exports[0]), {
      'input': 'frame 1',
      'parameters': {'seed': 1},
    });
    expect(exports[1], 'task-1-payload.json');
  });

  test('exportSelectedTaskJson returns false when export is cancelled',
      () async {
    final viewModel = ProductionQueueViewModel(
      plans: [
        _plan([_scriptTask(id: 'task-1')])
      ],
      exporter: (content, fileName) async => false,
    );

    final exported = await viewModel.exportSelectedTaskJson();

    expect(exported, isFalse);
  });

  test('clearCurrentPlan removes selected plan tasks and persists the queue',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(id: 'task-1'),
        _scriptTask(id: 'task-2', frameIndex: 2),
      ])
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      now: () => DateTime.utc(2026, 5, 28, 10, 30),
    );

    await viewModel.clearCurrentPlan();

    expect(viewModel.totalTasks, 0);
    expect(viewModel.selectedTask, isNull);
    expect(
        viewModel.selectedPlan?.updatedAt, DateTime.utc(2026, 5, 28, 10, 30));
    final saved = await queueService.loadPlans();
    expect(saved.single.tasks, isEmpty);
  });

  test('clearCompletedTasks hides only discoverable script results and reloads',
      () async {
    final completedScript = _scriptTask(
      id: 'completed-script',
      status: ProductionTaskStatus.completed,
      outputImagePath: 'C:/output/completed-script.png',
    );
    final manualCompleted = ProductionTask.manualSingleFrame(
      id: 'completed-manual',
      planId: 'plan-1',
      title: 'Manual result',
      payload: const {'input': 'manual'},
      status: ProductionTaskStatus.completed,
      outputImagePath: 'C:/output/manual.png',
      createdAt: _createdAt,
      updatedAt: _createdAt,
    );
    final queuedScript = _scriptTask(id: 'queued-script', frameIndex: 2);
    final allCompleted = _scriptTask(
      id: 'all-completed',
      planId: 'plan-all',
      status: ProductionTaskStatus.completed,
      outputImagePath: 'C:/output/all-completed.png',
    );
    final mixedPlan = _plan([
      completedScript,
      manualCompleted,
      queuedScript,
    ]);
    final allCompletedPlan = _plan(
      [allCompleted],
      id: 'plan-all',
      name: 'All completed',
    );
    final mixedFingerprint = mixedPlan.planFingerprint;
    await queueService.savePlans([mixedPlan, allCompletedPlan]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlansReadOnly(),
      queueService: queueService,
      now: () => DateTime.utc(2026, 6, 2, 12),
    );

    expect(viewModel.completedTasksPendingDismissal, 2);
    expect(await viewModel.clearCompletedTasks(), 2);
    expect(await viewModel.clearCompletedTasks(), 0);
    expect(viewModel.completedTasksPendingDismissal, 0);
    expect(viewModel.visiblePlans.map((plan) => plan.id), ['plan-1']);
    expect(
      viewModel
          .visibleTasksForPlan(viewModel.selectedPlan)
          .map((task) => task.id),
      ['completed-manual', 'queued-script'],
    );
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == 'plan-all')
          .tasks
          .single
          .isQueueDismissed,
      isTrue,
    );
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == 'plan-1')
          .planFingerprint,
      mixedFingerprint,
    );

    final reloaded = ProductionQueueViewModel(
      plans: await queueService.loadPlansReadOnly(),
      queueService: queueService,
    );
    expect(reloaded.completedTasksPendingDismissal, 0);
    expect(reloaded.visiblePlans.map((plan) => plan.id), ['plan-1']);
    expect(
      reloaded.plans
          .singleWhere((plan) => plan.id == 'plan-all')
          .tasks
          .single
          .isQueueDismissed,
      isTrue,
    );
  });

  test(
      'clearCompletedTasks dismisses script tasks without requiring an image path',
      () async {
    final completedWithoutPath = _scriptTask(
      id: 'completed-without-path',
      status: ProductionTaskStatus.completed,
    );
    final plan = _plan([completedWithoutPath]);
    await queueService.savePlans([plan]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlansReadOnly(),
      queueService: queueService,
      now: () => DateTime.utc(2026, 6, 2, 12),
    );

    expect(viewModel.completedTasksPendingDismissal, 1);
    expect(await viewModel.clearCompletedTasks(), 1);
    expect(viewModel.visiblePlans, isEmpty);
    expect(viewModel.selectedPlan, isNull);
    expect(
      viewModel.plans.single.tasks.single.isQueueDismissed,
      isTrue,
    );
    final saved = await queueService.loadPlansReadOnly();
    expect(saved.single.tasks.single.isQueueDismissed, isTrue);
  });

  test('clearCompletedTasks clears inactive plans while another is running',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final activePlan = _plan(
      [
        _scriptTask(
          id: 'active-queued',
          planId: 'active-plan',
        ),
      ],
      id: 'active-plan',
      name: 'Active',
    );
    final inactivePlan = _plan(
      [
        _scriptTask(
          id: 'inactive-completed',
          planId: 'inactive-plan',
          status: ProductionTaskStatus.completed,
          outputImagePath: 'C:/out/inactive.png',
        ),
      ],
      id: 'inactive-plan',
      name: 'Inactive',
    );
    final viewModel = ProductionQueueViewModel(
      plans: [activePlan, inactivePlan],
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final startFuture = viewModel.start();
    await requestStarted.future;

    final activeTaskBeforeClear = viewModel.activePlan!.tasks.single;
    expect(activeTaskBeforeClear.status, ProductionTaskStatus.running);
    expect(activeTaskBeforeClear.attempts, 1);
    expect(activeTaskBeforeClear.outputImagePath, isNull);
    expect(viewModel.completedTasksPendingDismissal, 1);
    expect(viewModel.canClearCompletedTasks, isTrue);
    expect(await viewModel.clearCompletedTasks(), 1);
    final activeTaskAfterClear = viewModel.activePlan!.tasks.single;
    expect(activeTaskAfterClear.status, activeTaskBeforeClear.status);
    expect(activeTaskAfterClear.attempts, activeTaskBeforeClear.attempts);
    expect(
      activeTaskAfterClear.outputImagePath,
      activeTaskBeforeClear.outputImagePath,
    );
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == activePlan.id)
          .tasks
          .single
          .isQueueDismissed,
      isFalse,
    );
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == inactivePlan.id)
          .tasks
          .single
          .isQueueDismissed,
      isTrue,
    );

    requestCompleter.complete(_fakePngBytes);
    await startFuture;
    final activeTaskAfterRun = viewModel.plans
        .singleWhere((plan) => plan.id == activePlan.id)
        .tasks
        .single;
    expect(activeTaskAfterRun.status, ProductionTaskStatus.completed);
    expect(activeTaskAfterRun.outputImagePath, 'C:/out/active-queued.png');
    final saved = await queueService.loadPlansReadOnly();
    expect(
      saved
          .singleWhere((plan) => plan.id == inactivePlan.id)
          .tasks
          .single
          .isQueueDismissed,
      isTrue,
    );
  });

  test('clearCompletedTasks stays disabled when only the active plan qualifies',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final activePlan = _plan(
      [
        _scriptTask(
          id: 'active-completed',
          planId: 'active-only-plan',
          status: ProductionTaskStatus.completed,
          outputImagePath: 'C:/out/active.png',
        ),
        _scriptTask(
          id: 'active-queued',
          planId: 'active-only-plan',
          frameIndex: 2,
        ),
      ],
      id: 'active-only-plan',
    );
    final viewModel = ProductionQueueViewModel(
      plans: [activePlan],
      executorService: _executor(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final startFuture = viewModel.start();
    await requestStarted.future;
    viewModel.pause();

    expect(viewModel.completedTasksPendingDismissal, 0);
    expect(viewModel.canClearCompletedTasks, isFalse);
    expect(await viewModel.clearCompletedTasks(), 0);
    expect(viewModel.plans.single.tasks.first.isQueueDismissed, isFalse);

    requestCompleter.complete(_fakePngBytes);
    await startFuture;
  });

  test(
      'clearCompletedTasks clears inactive plans while the active plan is paused',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final activePlan = _plan(
      [
        _scriptTask(id: 'paused-queued-1', planId: 'paused-plan'),
        _scriptTask(
          id: 'paused-queued-2',
          planId: 'paused-plan',
          frameIndex: 2,
        ),
      ],
      id: 'paused-plan',
    );
    final inactivePlan = _plan(
      [
        _scriptTask(
          id: 'paused-inactive-completed',
          planId: 'paused-inactive-plan',
          status: ProductionTaskStatus.completed,
        ),
      ],
      id: 'paused-inactive-plan',
    );
    final viewModel = ProductionQueueViewModel(
      plans: [activePlan, inactivePlan],
      executorService: _executor(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final startFuture = viewModel.start();
    await requestStarted.future;
    viewModel.pause();

    expect(viewModel.completedTasksPendingDismissal, 1);
    expect(viewModel.canClearCompletedTasks, isTrue);
    expect(await viewModel.clearCompletedTasks(), 1);
    expect(viewModel.isPaused, isFalse);
    expect(
      viewModel.plans
          .singleWhere((plan) => plan.id == inactivePlan.id)
          .tasks
          .single
          .isQueueDismissed,
      isTrue,
    );

    requestCompleter.complete(_fakePngBytes);
    await startFuture;
    expect(viewModel.isPaused, isTrue);
    expect(viewModel.completedTasksPendingDismissal, 0);
  });

  test('start then clear serializes activation before clear eligibility',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final plan = _plan([
      _scriptTask(
        id: 'race-completed',
        status: ProductionTaskStatus.completed,
        outputImagePath: 'C:/out/race.png',
      ),
      _scriptTask(id: 'race-queued', frameIndex: 2),
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: [plan],
      executorService: _executor(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final startFuture = viewModel.start();
    final clearFuture = viewModel.clearCompletedTasks();

    expect(await clearFuture, 0);
    expect(viewModel.activePlan?.id, plan.id);
    expect(viewModel.plans.single.tasks.first.isQueueDismissed, isFalse);

    await requestStarted.future;
    requestCompleter.complete(_fakePngBytes);
    await startFuture;
  });

  test('clear then start keeps the pending activation plan untouched',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final plan = _plan([
      _scriptTask(
        id: 'clear-first-completed',
        status: ProductionTaskStatus.completed,
        outputImagePath: 'C:/out/clear-first.png',
      ),
      _scriptTask(id: 'clear-first-queued', frameIndex: 2),
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: [plan],
      executorService: _executor(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final clearFuture = viewModel.clearCompletedTasks();
    final startFuture = viewModel.start();

    expect(await clearFuture, 0);
    expect(viewModel.plans.single.tasks.first.isQueueDismissed, isFalse);
    await requestStarted.future;
    requestCompleter.complete(_fakePngBytes);
    await startFuture;
  });

  test(
      'clear then start with a blocked save does not dismiss the activation plan',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final plan = _plan(
      [
        _scriptTask(
          id: 'blocked-clear-completed',
          status: ProductionTaskStatus.completed,
          outputImagePath: 'C:/out/blocked-clear.png',
        ),
        _scriptTask(id: 'blocked-clear-queued', frameIndex: 2),
      ],
    );
    final blockingQueueService = _BlockingPlanSaveQueueService(
      workspaceService: workspaceService,
      initialPlans: [plan],
    );
    final viewModel = ProductionQueueViewModel(
      plans: [plan],
      queueService: blockingQueueService,
      executorService: _executor(
        queueService: blockingQueueService,
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final clearFuture = viewModel.clearCompletedTasks();
    await blockingQueueService.firstSaveStarted.future;
    final startFuture = viewModel.start();
    expect(viewModel.activePlan, isNull);

    blockingQueueService.releaseFirstSave();
    expect(await clearFuture, 0);
    expect(viewModel.plans.single.tasks.first.isQueueDismissed, isFalse);

    await requestStarted.future;
    expect(viewModel.activePlan?.id, plan.id);
    expect(viewModel.activePlan!.tasks.first.isQueueDismissed, isFalse);
    requestCompleter.complete(_fakePngBytes);
    await startFuture;
  });

  test('start then clear with a blocked save preserves the active execution',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final plan = _plan(
      [
        _scriptTask(
          id: 'blocked-start-completed',
          status: ProductionTaskStatus.completed,
          outputImagePath: 'C:/out/blocked-start.png',
        ),
        _scriptTask(id: 'blocked-start-queued', frameIndex: 2),
      ],
    );
    final blockingQueueService = _BlockingPlanSaveQueueService(
      workspaceService: workspaceService,
      initialPlans: [plan],
    );
    final viewModel = ProductionQueueViewModel(
      plans: [plan],
      queueService: blockingQueueService,
      executorService: _executor(
        queueService: blockingQueueService,
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    final startFuture = viewModel.start();
    await blockingQueueService.firstSaveStarted.future;
    expect(viewModel.activePlan?.id, plan.id);
    expect(viewModel.activePlan!.tasks.first.isQueueDismissed, isFalse);
    expect(viewModel.canClearCompletedTasks, isFalse);

    final clearFuture = viewModel.clearCompletedTasks();
    blockingQueueService.releaseFirstSave();
    expect(await clearFuture, 0);
    expect(viewModel.activePlan?.id, plan.id);
    expect(viewModel.activePlan!.tasks.first.isQueueDismissed, isFalse);

    await requestStarted.future;
    expect(viewModel.activePlan!.tasks[1].status, ProductionTaskStatus.running);
    expect(viewModel.activePlan!.tasks[1].outputImagePath, isNull);
    requestCompleter.complete(_fakePngBytes);
    await startFuture;
    expect(viewModel.activePlan, isNull);
    expect(viewModel.plans.single.tasks.first.isQueueDismissed, isFalse);
    expect(
        viewModel.plans.single.tasks[1].status, ProductionTaskStatus.completed);
    expect(
      viewModel.plans.single.tasks[1].outputImagePath,
      'C:/out/blocked-start-queued.png',
    );
  });

  test('focusProductionTask can target a dismissed plan and rerun clears it',
      () async {
    final dismissedAt = DateTime.utc(2026, 6, 2, 11);
    final dismissedTask = _scriptTask(
      id: 'dismissed-task',
      status: ProductionTaskStatus.completed,
      outputImagePath: 'C:/out/dismissed-task.png',
    ).copyWith(queueDismissedAt: dismissedAt);
    final hiddenPlan = _plan([dismissedTask]);
    final visiblePlan = _plan(
      [_scriptTask(id: 'visible-task', planId: 'visible-plan')],
      id: 'visible-plan',
      name: 'Visible plan',
    );
    await queueService.savePlans([hiddenPlan, visiblePlan]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlansReadOnly(),
      queueService: queueService,
      executorService: _executor(
        queueService: queueService,
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      ),
    );

    expect(viewModel.selectedPlan?.id, visiblePlan.id);
    expect(
      viewModel.focusProductionTask(
        planId: hiddenPlan.id,
        taskId: dismissedTask.id,
      ),
      isTrue,
    );
    expect(viewModel.selectedPlan?.id, hiddenPlan.id);
    expect(viewModel.selectedTask?.id, dismissedTask.id);

    await viewModel.rerunTask(viewModel.selectedTask!);

    expect(viewModel.selectedPlan?.id, hiddenPlan.id);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.isQueueDismissed, isFalse);
    final saved = await queueService.loadPlansReadOnly();
    final savedHiddenPlan =
        saved.singleWhere((plan) => plan.id == hiddenPlan.id);
    expect(savedHiddenPlan.tasks.single.isQueueDismissed, isFalse);
  });

  test('clearCurrentPlan retains dismissed task rows and their outputs',
      () async {
    final dismissedTask = _scriptTask(
      id: 'dismissed-task',
      status: ProductionTaskStatus.completed,
      outputImagePath: 'C:/out/dismissed-task.png',
    ).copyWith(queueDismissedAt: DateTime.utc(2026, 6, 2, 11));
    final queuedTask = _scriptTask(id: 'queued-task', frameIndex: 2);
    final plan = _plan([dismissedTask, queuedTask]);
    await queueService.savePlans([plan]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlansReadOnly(),
      queueService: queueService,
    );

    await viewModel.clearCurrentPlan();

    expect(viewModel.plans.single.tasks.map((task) => task.id),
        ['dismissed-task']);
    expect(viewModel.plans.single.tasks.single.outputImagePath,
        'C:/out/dismissed-task.png');
    expect(viewModel.plans.single.tasks.single.isQueueDismissed, isTrue);
    final saved = await queueService.loadPlansReadOnly();
    expect(saved.single.tasks.map((task) => task.id), ['dismissed-task']);
  });

  test('deletePlan removes one queue and can delete its output images',
      () async {
    final output = File('${tempDir.path}${Platform.pathSeparator}frame.png');
    await output.writeAsBytes(_fakePngBytes);
    final deletedPlan = _plan([
      _scriptTask(
        id: 'delete-task',
        status: ProductionTaskStatus.completed,
        outputImagePath: output.path,
      ),
    ]);
    final keptPlan = _plan(
      [
        _scriptTask(
          id: 'kept-task',
          planId: 'kept-plan',
        ),
      ],
      id: 'kept-plan',
      name: 'Kept',
    );
    await queueService.savePlans([deletedPlan, keptPlan]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
    );
    viewModel.selectPlan(deletedPlan.id);

    final result = await viewModel.deletePlan(
      deletedPlan.id,
      deleteLocalImages: true,
    );

    expect(result.deleted, isTrue);
    expect(result.deletedImageCount, 1);
    expect(result.failedImagePaths, isEmpty);
    expect(await output.exists(), isFalse);
    expect(viewModel.plans.map((plan) => plan.id), [keptPlan.id]);
    expect(viewModel.selectedPlan?.id, keptPlan.id);
    final saved = await queueService.loadPlansReadOnly();
    expect(saved.map((plan) => plan.id), [keptPlan.id]);
  });

  test('deletePlan rejects the running queue', () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final plan = _plan([_scriptTask(id: 'running-task')]);
    final viewModel = ProductionQueueViewModel(
      plans: [plan],
      executorService: _executor(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );
    final startFuture = viewModel.start();
    await requestStarted.future;

    final result = await viewModel.deletePlan(plan.id);

    expect(result.deleted, isFalse);
    expect(viewModel.plans.single.id, plan.id);

    requestCompleter.complete(_fakePngBytes);
    await startFuture;
  });

  test('deletePlan blocks a concurrent start of the deleting plan', () async {
    final plan = _plan([_scriptTask(id: 'deleting-task')]);
    final blockingQueueService = _BlockingPlanSaveQueueService(
      workspaceService: workspaceService,
      initialPlans: [plan],
    );
    final viewModel = ProductionQueueViewModel(
      plans: [plan],
      queueService: blockingQueueService,
      executorService: _executor(queueService: blockingQueueService),
    );

    final deleteFuture = viewModel.deletePlan(plan.id);
    await blockingQueueService.firstSaveStarted.future;

    final startFuture = viewModel.start();
    expect(viewModel.activePlan, isNull);
    await startFuture;

    blockingQueueService.releaseFirstSave();
    final result = await deleteFuture;

    expect(result.deleted, isTrue);
    expect(viewModel.plans, isEmpty);
    expect(await blockingQueueService.loadPlansReadOnly(), isEmpty);
  });

  test('deletePlan removes an inactive queue while another queue is running',
      () async {
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final activePlan = _plan(
      [_scriptTask(id: 'active-task', planId: 'active-plan')],
      id: 'active-plan',
      name: 'Active',
    );
    final waitingPlan = _plan(
      [_scriptTask(id: 'waiting-task', planId: 'waiting-plan')],
      id: 'waiting-plan',
      name: 'Waiting',
    );
    final viewModel = ProductionQueueViewModel(
      plans: [activePlan, waitingPlan],
      executorService: _executor(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
      ),
    );

    expect(viewModel.canDeletePlan(activePlan.id), isTrue);
    expect(viewModel.canDeletePlan(waitingPlan.id), isTrue);

    final startFuture = viewModel.start();
    await requestStarted.future;
    expect(viewModel.canDeletePlan(activePlan.id), isFalse);
    expect(viewModel.canDeletePlan(waitingPlan.id), isTrue);
    final result = await viewModel.deletePlan(waitingPlan.id);

    expect(result.deleted, isTrue);
    expect(viewModel.activePlan?.id, activePlan.id);
    expect(viewModel.plans.map((plan) => plan.id), [activePlan.id]);

    requestCompleter.complete(_fakePngBytes);
    await startFuture;
  });

  test('renameSelectedPlan creates a distinct script exhibition version',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(
          id: 'script-recast-base:frame-1',
          planId: 'script-recast-base',
          suggestedFileName: 'script-recast-base-nai_1.png',
        )
      ], id: 'script-recast-base')
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      now: () => DateTime.utc(2026, 6, 4, 10, 30),
    );

    await viewModel.renameSelectedPlan('Renamed Queue');

    final renamedPlan = viewModel.selectedPlan!;
    final renamedTask = renamedPlan.tasks.single;

    expect(renamedPlan.id, 'script-recast-renamed-queue');
    expect(renamedPlan.name, 'Renamed Queue');
    expect(renamedTask.id, 'script-recast-renamed-queue:frame-1');
    expect(renamedTask.planId, renamedPlan.id);
    expect(renamedTask.source.scriptId, 'script-1');
    expect(
      renamedTask.suggestedFileName,
      'script-recast-renamed-queue-nai_1.png',
    );
    expect(
      renamedPlan.updatedAt,
      DateTime.utc(2026, 6, 4, 10, 30),
    );
    final saved = await queueService.loadPlans();
    expect(saved.single.id, 'script-recast-renamed-queue');
    expect(saved.single.tasks.single.planId, 'script-recast-renamed-queue');
  });

  test('rateTask persists rating and stores high-rated production sample',
      () async {
    await queueService.savePlans([
      _plan([
        _scriptTask(
          id: 'task-1',
          status: ProductionTaskStatus.completed,
          outputImagePath: 'C:/out/task-1.png',
        )
      ])
    ]);
    final viewModel = ProductionQueueViewModel(
      plans: await queueService.loadPlans(),
      queueService: queueService,
      loadRecastKnowledgeBase: workspaceService.loadRecastKnowledgeBase,
      saveRecastKnowledgeBase: workspaceService.saveRecastKnowledgeBase,
      now: () => DateTime.utc(2026, 5, 28, 10, 30),
    );

    await viewModel.rateTask(viewModel.selectedTask!, 5);

    expect(viewModel.selectedTask?.rating, 5);
    expect(viewModel.selectedTask?.ratedAt, DateTime.utc(2026, 5, 28, 10, 30));
    final savedPlans = await queueService.loadPlans();
    expect(savedPlans.single.tasks.single.rating, 5);
    final knowledgeBase = await workspaceService.loadRecastKnowledgeBase();
    final samples = knowledgeBase['productionSamples'] as Map;
    final sample = samples['task-1'] as Map;
    expect(sample['rating'], 5);
    expect(sample['scriptId'], 'script-1');
    expect(sample['frameIndex'], 1);
    expect(sample['outputImagePath'], 'C:/out/task-1.png');
    expect((sample['payload'] as Map)['input'], 'frame 1');
  });
}

final _fakePngBytes = Uint8List.fromList([137, 80, 78, 71]);
final _createdAt = DateTime.utc(2026, 5, 25);

class _BlockingExecutionSettingsQueueService extends ProductionQueueService {
  final Completer<ProductionPlanExecutionSettings> firstSaveStarted =
      Completer<ProductionPlanExecutionSettings>();
  final Completer<void> _firstSaveRelease = Completer<void>();
  var _saveLastExecutionSettingsCalls = 0;

  _BlockingExecutionSettingsQueueService({
    required super.workspaceService,
  });

  @override
  Future<void> saveLastExecutionSettings(
    ProductionPlanExecutionSettings settings,
  ) async {
    _saveLastExecutionSettingsCalls += 1;
    if (_saveLastExecutionSettingsCalls == 1) {
      firstSaveStarted.complete(settings);
      await _firstSaveRelease.future;
    }
    await super.saveLastExecutionSettings(settings);
  }

  void releaseFirstSave() {
    if (!_firstSaveRelease.isCompleted) {
      _firstSaveRelease.complete();
    }
  }
}

class _BlockingPlanSaveQueueService extends ProductionQueueService {
  final Completer<List<ProductionPlan>> firstSaveStarted =
      Completer<List<ProductionPlan>>();
  final Completer<void> _firstSaveRelease = Completer<void>();
  List<ProductionPlan> _plans;
  var _savePlansCalls = 0;

  _BlockingPlanSaveQueueService({
    required super.workspaceService,
    required List<ProductionPlan> initialPlans,
  }) : _plans = List.unmodifiable(initialPlans);

  @override
  Future<List<ProductionPlan>> loadPlans() async {
    return _plans;
  }

  @override
  Future<List<ProductionPlan>> loadPlansReadOnly() async {
    return _plans;
  }

  @override
  Future<void> savePlans(List<ProductionPlan> plans) async {
    await _save(plans);
  }

  @override
  Future<void> savePlanChanges({
    required Iterable<ProductionPlan> updatedPlans,
    required Iterable<String> deletedPlanIds,
  }) async {
    final updates = {
      for (final plan in updatedPlans) plan.id: plan,
    };
    final deletedIds = deletedPlanIds.toSet();
    await _save([
      ...updates.values,
      for (final plan in _plans)
        if (!updates.containsKey(plan.id) && !deletedIds.contains(plan.id))
          plan,
    ]);
  }

  Future<void> _save(List<ProductionPlan> plans) async {
    _savePlansCalls += 1;
    if (_savePlansCalls == 1) {
      firstSaveStarted.complete(plans);
      await _firstSaveRelease.future;
    }
    _plans = List.unmodifiable(plans);
  }

  void releaseFirstSave() {
    if (!_firstSaveRelease.isCompleted) {
      _firstSaveRelease.complete();
    }
  }
}

ProductionExecutorService _executor({
  ProductionQueueService? queueService,
  ProductionImageRequest? requestImage,
  ProductionImageSave? saveImage,
  ProductionDelay? delay,
  ProductionRandomInt? randomInt,
}) {
  return ProductionExecutorService(
    queueService: queueService,
    requestImage: requestImage ?? (payload) async => _fakePngBytes,
    saveImage: saveImage ?? (bytes, fileName) async => 'C:/out/$fileName',
    now: () => DateTime.utc(2026, 5, 25, 12),
    delay: delay,
    randomInt: randomInt,
  );
}

ProductionPlan _plan(
  List<ProductionTask> tasks, {
  String id = 'plan-1',
  String name = 'Script Recast',
  DateTime? updatedAt,
  ProductionPlanExecutionSettings? executionSettings,
}) {
  return ProductionPlan(
    id: id,
    name: name,
    tasks: tasks,
    executionSettings: executionSettings,
    createdAt: _createdAt,
    updatedAt: updatedAt ?? _createdAt,
  );
}

ProductionTask _scriptTask({
  required String id,
  String planId = 'plan-1',
  int frameIndex = 1,
  ProductionTaskStatus status = ProductionTaskStatus.queued,
  int attempts = 0,
  String? outputImagePath,
  String? error,
  String? suggestedFileName,
  String? model,
  int? width,
  int? height,
  int? steps,
  double? scale,
  String? sampler,
  Map<String, dynamic>? payload,
}) {
  return ProductionTask.scriptRecastFrame(
    id: id,
    planId: planId,
    title: 'Frame $frameIndex',
    scriptId: 'script-1',
    recastRunId: 'run-1',
    frameIndex: frameIndex,
    sourceFileName: 'nai_$frameIndex.json',
    payload: payload ??
        {
          'input': 'frame $frameIndex',
          if (model != null) 'model': model,
          'parameters': {
            'seed': frameIndex,
            if (width != null) 'width': width,
            if (height != null) 'height': height,
            if (steps != null) 'steps': steps,
            if (scale != null) 'scale': scale,
            if (sampler != null) 'sampler': sampler,
          },
        },
    suggestedFileName: suggestedFileName,
    status: status,
    attempts: attempts,
    outputImagePath: outputImagePath,
    error: error,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}
