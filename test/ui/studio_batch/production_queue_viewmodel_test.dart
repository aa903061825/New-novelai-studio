import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
