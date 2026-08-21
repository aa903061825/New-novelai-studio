import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_executor_service.dart';
import 'package:novel_studio/data/studio/services/production_nai_adapter_service.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService workspaceService;
  late ProductionQueueService queueService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'production-executor-service-test-',
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

  test('failed frame does not block later queued frames', () async {
    final requestedInputs = <String>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        if (payload['input'] == 'bad frame') {
          throw StateError('boom');
        }
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(_planWithThreeTasks(), maxRetries: 1);

    expect(requestedInputs, ['good frame 1', 'bad frame', 'good frame 3']);
    expect(result.tasks[0].status, ProductionTaskStatus.completed);
    expect(result.tasks[0].attempts, 1);
    expect(result.tasks[1].status, ProductionTaskStatus.failed);
    expect(result.tasks[1].attempts, 1);
    expect(result.tasks[1].error, contains('boom'));
    expect(result.tasks[2].status, ProductionTaskStatus.completed);
    expect(result.tasks[2].attempts, 1);
  });

  test('runPlan retries a failed task within the same execution', () async {
    final requestedInputs = <String>[];
    var attempts = 0;
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        attempts += 1;
        if (attempts < 3) {
          throw StateError('temporary failure $attempts');
        }
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-flaky', frameIndex: 1, input: 'flaky frame'),
      ]),
      maxRetries: 3,
    );

    expect(requestedInputs, ['flaky frame', 'flaky frame', 'flaky frame']);
    expect(result.tasks.single.status, ProductionTaskStatus.completed);
    expect(result.tasks.single.attempts, 3);
    expect(result.tasks.single.error, isNull);
    expect(result.tasks.single.outputImagePath, 'C:/out/nai_1.png');
  });

  test('queue-dismissed tasks stay out of scheduling and queue retry',
      () async {
    final dismissedAt = DateTime.utc(2026, 6, 2, 9);
    final plan = _plan([
      _scriptTask(
        id: 'dismissed-queued',
        frameIndex: 1,
        input: 'dismissed queued',
      ).copyWith(queueDismissedAt: dismissedAt),
      _scriptTask(
        id: 'dismissed-failed',
        frameIndex: 2,
        input: 'dismissed failed',
        status: ProductionTaskStatus.failed,
      ).copyWith(queueDismissedAt: dismissedAt),
      _scriptTask(
        id: 'visible-queued',
        frameIndex: 3,
        input: 'visible queued',
      ),
      _scriptTask(
        id: 'visible-failed',
        frameIndex: 4,
        input: 'visible failed',
        status: ProductionTaskStatus.failed,
      ),
    ]);
    await queueService.savePlans([plan]);
    final requestedInputs = <String>[];
    final executor = ProductionExecutorService(
      queueService: queueService,
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 6, 2, 10),
    );

    final scheduled = await executor.runPlan(plan);
    expect(requestedInputs, ['visible queued']);
    expect(scheduled.tasks[0].isQueueDismissed, isTrue);
    expect(scheduled.tasks[1].isQueueDismissed, isTrue);

    final retried = await executor.retryFailed('plan-1');
    expect(requestedInputs, ['visible queued', 'visible failed']);
    expect(retried.tasks[0].isQueueDismissed, isTrue);
    expect(retried.tasks[1].isQueueDismissed, isTrue);
  });

  test('explicit rerun clears queue dismissal before persisting the result',
      () async {
    final dismissed = _scriptTask(
      id: 'dismissed-task',
      frameIndex: 1,
      input: 'dismissed task',
      status: ProductionTaskStatus.completed,
      outputImagePath: 'C:/old/dismissed-task.png',
    ).copyWith(queueDismissedAt: DateTime.utc(2026, 6, 2, 9));
    await queueService.savePlans([
      _plan([dismissed])
    ]);
    final executor = ProductionExecutorService(
      queueService: queueService,
      requestImage: (payload) async => _fakePngBytes,
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 6, 2, 10),
    );

    final result = await executor.rerunTask(
      'plan-1',
      taskId: dismissed.id,
    );

    expect(result.plan.tasks.single.isQueueDismissed, isFalse);
    expect(
      (await queueService.loadPlansReadOnly())
          .single
          .tasks
          .single
          .isQueueDismissed,
      isFalse,
    );
    expect(result.plan.tasks.single.outputImagePath, 'C:/out/nai_1.png');
  });

  test('runPlan saves generated images with production plan scope', () async {
    final scopedSaves = <String>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async => _fakePngBytes,
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      savePlanImage: (bytes, fileName, plan, task) async {
        scopedSaves.add(
          '${plan.name}|${task.source.scriptName}|${task.source.frameIndex}|'
          '$fileName|${bytes.length}',
        );
        return 'C:/out/${plan.id}/$fileName';
      },
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-1', frameIndex: 1, input: 'frame one'),
      ]),
      maxRetries: 1,
    );

    expect(scopedSaves, ['Script Recast|Pilot Script|1|nai_1.png|4']);
    expect(result.tasks.single.outputImagePath, 'C:/out/plan-1/nai_1.png');
  });

  test('completed task update failures do not become generation failures',
      () async {
    final observedStatuses = <ProductionTaskStatus>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async => _fakePngBytes,
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-1', frameIndex: 1, input: 'frame 1'),
      ]),
      maxRetries: 1,
      onTaskUpdate: (task) async {
        observedStatuses.add(task.status);
        if (task.status == ProductionTaskStatus.completed) {
          throw const FileSystemException(
            'Cannot rename file',
            r'C:\workspace\production\deterministic_plans\plan-1.json',
            OSError('Access is denied.', 5),
          );
        }
      },
    );

    expect(observedStatuses, [
      ProductionTaskStatus.running,
      ProductionTaskStatus.completed,
    ]);
    expect(result.tasks.single.status, ProductionTaskStatus.completed);
    expect(result.tasks.single.outputImagePath, 'C:/out/nai_1.png');
    expect(result.tasks.single.error, isNull);
  });

  test('runPlan expands shared reference parameters before requesting image',
      () async {
    Map<String, dynamic>? requestedPayload;
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedPayload = payload;
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );
    final plan = _plan([
      _scriptTask(id: 'task-1', frameIndex: 1, input: 'frame one'),
    ]).copyWith(
      sharedPayloadParameters: const {
        'reference_image_multiple': ['encoded-shared-vibe'],
        'reference_strength_multiple': [0.45],
        'reference_information_extracted_multiple': [1.0],
      },
    );

    await executor.runPlan(plan, maxRetries: 1);

    final parameters = requestedPayload?['parameters'] as Map?;
    expect(parameters?['seed'], 1);
    expect(parameters?['reference_image_multiple'], ['encoded-shared-vibe']);
    expect(parameters?['reference_strength_multiple'], [0.45]);
    expect(parameters?['reference_information_extracted_multiple'], [1.0]);
    expect(
      plan.tasks.single.payload['parameters'],
      isNot(contains('reference_image_multiple')),
    );
  });

  test('runPlan passes explicit plan output directory to scoped save',
      () async {
    final scopedSaves = <String>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async => _fakePngBytes,
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      savePlanImage: (bytes, fileName, plan, task) async {
        final outputDirectory = plan.executionSettings?.outputDirectory;
        scopedSaves.add(
          '${plan.id}|$outputDirectory|${task.source.scriptName}|$fileName',
        );
        return '$outputDirectory/$fileName';
      },
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-1', frameIndex: 1, input: 'frame one'),
      ]).copyWith(
        executionSettings: const ProductionPlanExecutionSettings(
          outputDirectory: r'D:\batch-output',
        ),
      ),
      maxRetries: 1,
    );

    expect(scopedSaves, [r'plan-1|D:\batch-output|Pilot Script|nai_1.png']);
    expect(result.tasks.single.outputImagePath, r'D:\batch-output/nai_1.png');
  });

  test('runPlan can retry indefinitely until a task succeeds', () async {
    final requestedInputs = <String>[];
    var attempts = 0;
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        attempts += 1;
        if (attempts < 5) {
          throw StateError('still busy $attempts');
        }
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-flaky', frameIndex: 1, input: 'flaky frame'),
      ]),
      maxRetries: 1,
      retryIndefinitely: true,
    );

    expect(requestedInputs, [
      'flaky frame',
      'flaky frame',
      'flaky frame',
      'flaky frame',
      'flaky frame',
    ]);
    expect(result.tasks.single.status, ProductionTaskStatus.completed);
    expect(result.tasks.single.attempts, 5);
  });

  test('runPlan caps infinite retry for NAI server errors', () async {
    final requestedInputs = <String>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        throw const ProductionNaiApiException(
          statusCode: 500,
          message: '{"statusCode":500,"message":"Internal Server Error"}',
        );
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-bad', frameIndex: 1, input: 'bad frame'),
      ]),
      maxRetries: 2,
      retryIndefinitely: true,
      shouldContinue: () => requestedInputs.length < 3,
    );

    expect(requestedInputs, ['bad frame', 'bad frame']);
    expect(result.tasks.single.status, ProductionTaskStatus.failed);
    expect(result.tasks.single.attempts, 2);
    expect(result.tasks.single.error, contains('Internal Server Error'));
  });

  test('runPlan waits the configured 429 delay before retrying the task',
      () async {
    final requestedInputs = <String>[];
    final delays = <Duration>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        if (requestedInputs.length == 1) {
          throw const ProductionNaiApiException(
            statusCode: 429,
            message: '{"statusCode":429,"message":"Concurrent generation"}',
          );
        }
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
      delay: (duration) async {
        delays.add(duration);
      },
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-429', frameIndex: 1, input: 'locked frame'),
      ]),
      maxRetries: 2,
      retryOn429Delay: const Duration(seconds: 17),
    );

    expect(requestedInputs, ['locked frame', 'locked frame']);
    expect(delays, [const Duration(seconds: 17)]);
    expect(result.tasks.single.status, ProductionTaskStatus.completed);
    expect(result.tasks.single.attempts, 2);
  });

  test('runPlan stops infinite retry after shouldContinue turns false',
      () async {
    final requestedInputs = <String>[];
    var canContinue = true;
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        canContinue = false;
        throw StateError('not yet');
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-flaky', frameIndex: 1, input: 'flaky frame'),
      ]),
      maxRetries: 1,
      retryIndefinitely: true,
      shouldContinue: () => canContinue,
    );

    expect(requestedInputs, ['flaky frame']);
    expect(result.tasks.single.status, ProductionTaskStatus.queued);
    expect(result.tasks.single.attempts, 1);
    expect(result.tasks.single.error, contains('not yet'));
  });

  test('runPlan does not save a request that completed after cancellation',
      () async {
    final requestStarted = Completer<void>();
    final requestResult = Completer<Uint8List>();
    var canContinue = true;
    var saveCount = 0;
    final executor = ProductionExecutorService(
      requestImage: (payload) {
        requestStarted.complete();
        return requestResult.future;
      },
      saveImage: (bytes, fileName) async {
        saveCount += 1;
        return 'C:/out/$fileName';
      },
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final run = executor.runPlan(
      _plan([
        _scriptTask(id: 'task-stopped', frameIndex: 1, input: 'stale frame'),
      ]),
      shouldContinue: () => canContinue,
    );
    await requestStarted.future;
    canContinue = false;
    requestResult.complete(_fakePngBytes);

    final result = await run;

    expect(saveCount, 0);
    expect(result.tasks.single.status, ProductionTaskStatus.queued);
    expect(result.tasks.single.outputImagePath, isNull);
  });

  test('runPlan waits the configured interval between sequential requests',
      () async {
    final requestedInputs = <String>[];
    final delays = <Duration>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
      delay: (duration) async {
        delays.add(duration);
      },
    );

    final result = await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-1', frameIndex: 1, input: 'frame 1'),
        _scriptTask(id: 'task-2', frameIndex: 2, input: 'frame 2'),
        _scriptTask(id: 'task-3', frameIndex: 3, input: 'frame 3'),
      ]),
      maxRetries: 1,
      requestInterval: const Duration(seconds: 55),
    );

    expect(requestedInputs, ['frame 1', 'frame 2', 'frame 3']);
    expect(delays, [
      const Duration(seconds: 55),
      const Duration(seconds: 55),
    ]);
    expect(
      result.tasks.map((task) => task.status),
      everyElement(ProductionTaskStatus.completed),
    );
  });

  test('runPlan adds a random interval range to each sequential delay',
      () async {
    final delays = <Duration>[];
    final randomUpperBounds = <int>[];
    var nextRandom = 0;
    final executor = ProductionExecutorService(
      requestImage: (payload) async => _fakePngBytes,
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
      delay: (duration) async {
        delays.add(duration);
      },
      randomInt: (upperBound) {
        randomUpperBounds.add(upperBound);
        return nextRandom++ == 0 ? 7 : 20;
      },
    );

    await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-1', frameIndex: 1, input: 'frame 1'),
        _scriptTask(id: 'task-2', frameIndex: 2, input: 'frame 2'),
        _scriptTask(id: 'task-3', frameIndex: 3, input: 'frame 3'),
      ]),
      maxRetries: 1,
      requestInterval: const Duration(seconds: 55),
      requestIntervalRandomRange: const Duration(seconds: 20),
    );

    expect(randomUpperBounds, [21, 21]);
    expect(delays, [
      const Duration(seconds: 62),
      const Duration(seconds: 75),
    ]);
  });

  test('runPlan treats execution seed -1 as per-task random seed', () async {
    final requestedSeeds = <int>[];
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedSeeds.add((payload['parameters'] as Map)['seed'] as int);
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
      randomInt: (_) => requestedSeeds.isEmpty ? 101 : 202,
    );

    await executor.runPlan(
      _plan([
        _scriptTask(id: 'task-1', frameIndex: 1, input: 'frame 1'),
        _scriptTask(id: 'task-2', frameIndex: 2, input: 'frame 2'),
      ]).copyWith(
        executionSettings: const ProductionPlanExecutionSettings(seed: -1),
      ),
      maxRetries: 1,
    );

    expect(requestedSeeds, [101, 202]);
  });

  test('retryFailed executes only failed tasks', () async {
    final requestedInputs = <String>[];
    final failedTask = _scriptTask(
      id: 'task-2',
      frameIndex: 2,
      input: 'retry me',
      status: ProductionTaskStatus.failed,
      attempts: 1,
      error: 'previous failure',
    );
    final completedTask = _scriptTask(
      id: 'task-1',
      frameIndex: 1,
      input: 'already done',
      status: ProductionTaskStatus.completed,
      attempts: 1,
      outputImagePath: 'C:/out/task-1.png',
    );
    final queuedTask = _scriptTask(
      id: 'task-3',
      frameIndex: 3,
      input: 'leave queued alone',
    );
    final plan = _plan([completedTask, failedTask, queuedTask]);
    await queueService.savePlans([plan]);
    final executor = ProductionExecutorService(
      queueService: queueService,
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.retryFailed('plan-1', maxRetries: 1);

    expect(requestedInputs, ['retry me']);
    expect(result.tasks[0].status, ProductionTaskStatus.completed);
    expect(result.tasks[0].attempts, 1);
    expect(result.tasks[1].status, ProductionTaskStatus.completed);
    expect(result.tasks[1].attempts, 2);
    expect(result.tasks[1].error, isNull);
    expect(result.tasks[2].status, ProductionTaskStatus.queued);
    final saved = await queueService.loadPlans();
    expect(saved.single.tasks[1].status, ProductionTaskStatus.completed);
  });

  test('rerunAbnormalTasksInPlan executes failed and errored queued tasks',
      () async {
    final requestedInputs = <String>[];
    final plan = _plan([
      _scriptTask(
        id: 'task-1',
        frameIndex: 1,
        input: 'already done',
        status: ProductionTaskStatus.completed,
        attempts: 1,
        outputImagePath: 'C:/out/task-1.png',
      ),
      _scriptTask(
        id: 'task-2',
        frameIndex: 2,
        input: 'failed frame',
        status: ProductionTaskStatus.failed,
        attempts: 1,
        error: 'HTTP 500',
      ),
      _scriptTask(
        id: 'task-3',
        frameIndex: 3,
        input: 'errored queued frame',
        status: ProductionTaskStatus.queued,
        attempts: 1,
        error: 'HandshakeException',
      ),
      _scriptTask(
        id: 'task-4',
        frameIndex: 4,
        input: 'normal queued frame',
      ),
    ]);
    final executor = ProductionExecutorService(
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.rerunAbnormalTasksInPlan(plan);

    expect(requestedInputs, ['failed frame', 'errored queued frame']);
    expect(result.changedTaskIds, ['task-2', 'task-3']);
    expect(result.plan.tasks[0].attempts, 1);
    expect(result.plan.tasks[1].status, ProductionTaskStatus.completed);
    expect(result.plan.tasks[1].attempts, 2);
    expect(result.plan.tasks[1].error, isNull);
    expect(result.plan.tasks[2].status, ProductionTaskStatus.completed);
    expect(result.plan.tasks[2].attempts, 2);
    expect(result.plan.tasks[2].error, isNull);
    expect(result.plan.tasks[3].status, ProductionTaskStatus.queued);
    expect(result.plan.tasks[3].attempts, 0);
  });

  test('rerunFrame executes only the selected script recast frame task',
      () async {
    final requestedInputs = <String>[];
    final plan = _plan([
      _scriptTask(
        id: 'task-1',
        frameIndex: 1,
        input: 'frame 1',
        status: ProductionTaskStatus.completed,
        attempts: 1,
      ),
      _scriptTask(
        id: 'task-2',
        frameIndex: 2,
        input: 'frame 2',
        status: ProductionTaskStatus.completed,
        attempts: 1,
      ),
      ProductionTask.manualSingleFrame(
        id: 'task-manual',
        planId: 'plan-1',
        title: 'Manual',
        payload: const {'input': 'manual frame'},
        status: ProductionTaskStatus.completed,
        attempts: 1,
        createdAt: _createdAt,
        updatedAt: _createdAt,
      ),
    ]);
    await queueService.savePlans([plan]);
    final executor = ProductionExecutorService(
      queueService: queueService,
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.rerunFrame('plan-1', frameIndex: 2);

    expect(requestedInputs, ['frame 2']);
    expect(result.changedTaskIds, ['task-2']);
    expect(result.plan.tasks[0].status, ProductionTaskStatus.completed);
    expect(result.plan.tasks[0].attempts, 1);
    expect(result.plan.tasks[1].status, ProductionTaskStatus.completed);
    expect(result.plan.tasks[1].attempts, 2);
    expect(result.plan.tasks[2].status, ProductionTaskStatus.completed);
    expect(result.plan.tasks[2].attempts, 1);
  });

  test('rerunTask executes only the selected task id when frame numbers repeat',
      () async {
    final requestedInputs = <String>[];
    final plan = _plan([
      _scriptTask(
        id: 'task-run-a',
        frameIndex: 1,
        input: 'run a frame 1',
        status: ProductionTaskStatus.completed,
        attempts: 1,
      ),
      _scriptTask(
        id: 'task-run-b',
        frameIndex: 1,
        input: 'run b frame 1',
        status: ProductionTaskStatus.completed,
        attempts: 1,
      ),
    ]);
    await queueService.savePlans([plan]);
    final executor = ProductionExecutorService(
      queueService: queueService,
      requestImage: (payload) async {
        requestedInputs.add(payload['input'] as String);
        return _fakePngBytes;
      },
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    final result = await executor.rerunTask('plan-1', taskId: 'task-run-b');

    expect(requestedInputs, ['run b frame 1']);
    expect(result.changedTaskIds, ['task-run-b']);
    expect(result.plan.tasks[0].attempts, 1);
    expect(result.plan.tasks[1].attempts, 2);
  });

  test('resume validates production plan, recast run and fingerprint',
      () async {
    final plan = _plan([
      _scriptTask(
        id: 'task-1',
        frameIndex: 1,
        input: 'frame 1',
        status: ProductionTaskStatus.completed,
        attempts: 1,
      ),
      _scriptTask(id: 'task-2', frameIndex: 2, input: 'frame 2'),
    ]);
    await queueService.savePlans([plan]);
    final executor = ProductionExecutorService(
      queueService: queueService,
      requestImage: (payload) async => _fakePngBytes,
      saveImage: (bytes, fileName) async => 'C:/out/$fileName',
      now: () => DateTime.utc(2026, 5, 25, 12),
    );

    expect(
      () => executor.resumePlan(
        productionPlanId: 'plan-1',
        recastRunId: 'run-1',
        planFingerprint: 'stale-fingerprint',
      ),
      throwsA(isA<ProductionResumeMismatch>()),
    );
  });
}

final _fakePngBytes = Uint8List.fromList([137, 80, 78, 71]);
final _createdAt = DateTime.utc(2026, 5, 25);

ProductionPlan _planWithThreeTasks() {
  return _plan([
    _scriptTask(id: 'task-1', frameIndex: 1, input: 'good frame 1'),
    _scriptTask(id: 'task-2', frameIndex: 2, input: 'bad frame'),
    _scriptTask(id: 'task-3', frameIndex: 3, input: 'good frame 3'),
  ]);
}

ProductionPlan _plan(List<ProductionTask> tasks) {
  return ProductionPlan(
    id: 'plan-1',
    name: 'Script Recast',
    tasks: tasks,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

ProductionTask _scriptTask({
  required String id,
  required int frameIndex,
  required String input,
  ProductionTaskStatus status = ProductionTaskStatus.queued,
  int attempts = 0,
  String? outputImagePath,
  String? error,
}) {
  return ProductionTask.scriptRecastFrame(
    id: id,
    planId: 'plan-1',
    title: 'Frame $frameIndex',
    scriptId: 'script-1',
    scriptName: 'Pilot Script',
    scriptPath: r'C:\scripts\pilot',
    recastRunId: 'run-1',
    frameIndex: frameIndex,
    sourceFileName: 'nai_$frameIndex.json',
    payload: {
      'input': input,
      'parameters': {'seed': frameIndex},
    },
    suggestedFileName: 'nai_$frameIndex.png',
    status: status,
    attempts: attempts,
    outputImagePath: outputImagePath,
    error: error,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}
