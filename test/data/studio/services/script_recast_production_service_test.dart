import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/services/production_queue_service.dart';
import 'package:nai_casrand/data/studio/services/script_recast_engine.dart';
import 'package:nai_casrand/data/studio/services/script_recast_payload_adapter.dart';
import 'package:nai_casrand/data/studio/services/script_recast_production_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService workspaceService;
  late ProductionQueueService queueService;
  late ScriptRecastProductionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'script-recast-production-service-test-',
    );
    workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    queueService = ProductionQueueService(workspaceService: workspaceService);
    service = ScriptRecastProductionService(
      queueService: queueService,
      now: () => DateTime.utc(2026, 5, 25, 12),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('enqueues recast result as deterministic script frame tasks', () async {
    final result = _recastResult();

    final plan = await service.enqueueRecastResult(
      result: result,
      planId: 'plan-recast-1',
      planName: 'v4_slotted_Recast',
      recastRunId: 'run-1',
      scriptName: 'v4_slotted',
      scriptPath: r'C:\scripts\v4_slotted',
    );

    expect(plan.id, 'plan-recast-1');
    expect(plan.name, 'v4_slotted_Recast');
    expect(plan.tasks, hasLength(2));
    expect(plan.createdAt, DateTime.utc(2026, 5, 25, 12));
    expect(plan.updatedAt, DateTime.utc(2026, 5, 25, 12));

    final first = plan.tasks.first;
    expect(first.id, 'plan-recast-1:frame-1');
    expect(first.taskType, ProductionTaskType.scriptRecastFrame);
    expect(first.status, ProductionTaskStatus.queued);
    expect(first.source.scriptId, 'script-1');
    expect(first.source.scriptName, 'v4_slotted');
    expect(first.source.scriptPath, r'C:\scripts\v4_slotted');
    expect(first.source.recastRunId, 'run-1');
    expect(first.source.frameIndex, 1);
    expect(first.source.sourceFileName, 'nai_1.json');
    expect(first.source.mappingConfigFingerprint, 'config-fingerprint');
    expect(first.payload['input'], 'city lights');
    expect(first.payload['action'], 'generate');
    expect(first.payload['parameters'], containsPair('seed', 1));
    expect(first.payloadFingerprint, result.frames.first.payloadFingerprint);
    expect(first.suggestedFileName, 'plan-recast-1-nai_1.png');

    final loaded = await queueService.loadPlans();
    expect(loaded.single.toJson(), plan.toJson());
  });

  test('stores repeated recast reference images once per production plan',
      () async {
    final plan = await service.enqueueRecastResult(
      result: _recastResultWithSharedReferences(),
      planId: 'plan-recast-refs',
      planName: 'Reference Recast',
      recastRunId: 'run-refs',
    );

    final firstParameters =
        plan.tasks.first.payload['parameters'] as Map<String, dynamic>;
    final loaded = await queueService.loadPlans();
    final loadedPlan = loaded.single;
    final requestParameters =
        loadedPlan.requestPayloadForTask(loadedPlan.tasks.first)['parameters']
            as Map<String, dynamic>;
    final encodedOccurrences = RegExp('encoded-shared-vibe')
        .allMatches(jsonEncode(loadedPlan.toJson()))
        .length;

    expect(plan.sharedPayloadParameters['reference_image_multiple'], [
      'encoded-shared-vibe',
    ]);
    expect(firstParameters, isNot(contains('reference_image_multiple')));
    expect(requestParameters['reference_image_multiple'], [
      'encoded-shared-vibe',
    ]);
    expect(requestParameters['seed'], 1);
    expect(encodedOccurrences, 1);
  });

  test('enqueuing many recast frames yields while building production tasks',
      () async {
    final probeAdapter = _YieldProbePayloadAdapter();
    final yieldingService = ScriptRecastProductionService(
      queueService: queueService,
      now: () => DateTime.utc(2026, 5, 25, 12),
      payloadAdapter: probeAdapter,
    );

    await yieldingService.enqueueRecastResult(
      result: _manyFrameRecastResult(16),
      planId: 'plan-recast-many',
      planName: 'Many Recast',
      recastRunId: 'run-many',
    );

    expect(probeAdapter.observedTimerBeforeNinthPayload, isTrue);
  });

  test('enqueuing a recast plan preserves other deterministic plans', () async {
    final existing = ProductionPlan(
      id: 'manual-plan',
      name: 'Manual',
      tasks: [
        ProductionTask.manualSingleFrame(
          id: 'manual-task',
          planId: 'manual-plan',
          title: 'Manual',
          payload: const {'input': 'manual'},
          createdAt: DateTime.utc(2026, 5, 25),
          updatedAt: DateTime.utc(2026, 5, 25),
        ),
      ],
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    await queueService.savePlans([existing]);

    await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'plan-recast-1',
      planName: 'v4_slotted_Recast',
      recastRunId: 'run-1',
    );

    final loaded = await queueService.loadPlans();
    expect(loaded.first.id, 'plan-recast-1');
    expect(loaded.map((plan) => plan.id).toSet(), {
      'manual-plan',
      'plan-recast-1',
    });
    expect(
      loaded.firstWhere((plan) => plan.id == 'manual-plan').toJson(),
      existing.toJson(),
    );
  });

  test('re-enqueuing the same plan id creates a new versioned plan', () async {
    final first = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'plan-recast-1',
      planName: 'v4_slotted_Recast',
      recastRunId: 'plan-recast-1-run',
    );

    final second = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'plan-recast-1',
      planName: 'v4_slotted_Recast',
      recastRunId: 'plan-recast-1-run',
    );

    final loaded = await queueService.loadPlans();
    expect(loaded, hasLength(2));
    expect(first.id, 'plan-recast-1');
    expect(second.id, 'plan-recast-1-2');
    expect(second.tasks.first.id, 'plan-recast-1-2:frame-1');
    expect(second.tasks.first.planId, 'plan-recast-1-2');
    expect(second.tasks.first.source.recastRunId, 'plan-recast-1-2-run');
    expect(second.tasks.first.suggestedFileName, 'plan-recast-1-2-nai_1.png');
    expect(
      loaded.map((plan) => plan.id).toSet(),
      {'plan-recast-1', 'plan-recast-1-2'},
    );
  });

  test('duplicate recast version names use a unique date label', () async {
    final existing = ProductionPlan(
      id: 'existing-version',
      name: 'v4_slotted_Recast',
      tasks: [
        ProductionTask.manualSingleFrame(
          id: 'existing-task',
          planId: 'existing-version',
          title: 'Existing',
          payload: const {'input': 'existing'},
          createdAt: DateTime.utc(2026, 5, 24),
          updatedAt: DateTime.utc(2026, 5, 24),
        ),
      ],
      createdAt: DateTime.utc(2026, 5, 24),
      updatedAt: DateTime.utc(2026, 5, 24),
    );
    final existingDate = existing.copyWith(
      id: 'existing-date-version',
      name: '2026-05-25',
      tasks: [
        existing.tasks.single.copyWith(
          id: 'existing-date-task',
          planId: 'existing-date-version',
        ),
      ],
    );
    await queueService.savePlans([existing, existingDate]);

    final plan = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'plan-recast-1',
      planName: 'v4_slotted_Recast',
      recastRunId: 'plan-recast-1-run',
    );

    expect(plan.id, 'plan-recast-1');
    expect(plan.name, '2026-05-25-2');
    expect(plan.tasks.first.id, 'plan-recast-1:frame-1');
    expect(plan.tasks.first.suggestedFileName, 'plan-recast-1-nai_1.png');

    final loaded = await queueService.loadPlans();
    expect(
      loaded.map((item) => item.name).toSet(),
      {'v4_slotted_Recast', '2026-05-25', '2026-05-25-2'},
    );
  });

  test('different recast plans use distinct output file names for same frames',
      () async {
    final first = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'script-recast-first',
      planName: 'First Recast',
      recastRunId: 'script-recast-first-run',
    );
    final second = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'script-recast-second',
      planName: 'Second Recast',
      recastRunId: 'script-recast-second-run',
    );

    expect(first.tasks.first.source.sourceFileName, 'nai_1.json');
    expect(second.tasks.first.source.sourceFileName, 'nai_1.json');
    expect(first.tasks.first.suggestedFileName,
        isNot(second.tasks.first.suggestedFileName));
  });

  test('re-enqueuing the same plan id preserves batch execution settings',
      () async {
    final existing = ProductionPlan(
      id: 'plan-recast-1',
      name: 'Old Recast',
      tasks: [
        ProductionTask.manualSingleFrame(
          id: 'old-task',
          planId: 'plan-recast-1',
          title: 'Old',
          payload: const {'input': 'old'},
          createdAt: DateTime.utc(2026, 5, 24),
          updatedAt: DateTime.utc(2026, 5, 24),
        ),
      ],
      executionSettings: const ProductionPlanExecutionSettings(
        model: 'nai-diffusion-4-5-full',
        sampler: 'k_euler_ancestral',
        width: 832,
        height: 1216,
        steps: 28,
        scale: 4,
        requestIntervalSeconds: 15,
        requestIntervalRandomRangeSeconds: 20,
        retryCount: 2,
        retryIndefinitely: true,
        outputDirectory: r'C:\outputs',
      ),
      createdAt: DateTime.utc(2026, 5, 24),
      updatedAt: DateTime.utc(2026, 5, 24),
    );
    await queueService.savePlans([existing]);

    final plan = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'plan-recast-1',
      planName: 'v4_slotted_Recast',
      recastRunId: 'run-1',
    );

    expect(plan.id, 'plan-recast-1-2');
    expect(plan.tasks, hasLength(2));
    expect(plan.executionSettings?.model, 'nai-diffusion-4-5-full');
    expect(plan.executionSettings?.sampler, 'k_euler_ancestral');
    expect(plan.executionSettings?.width, 832);
    expect(plan.executionSettings?.height, 1216);
    expect(plan.executionSettings?.steps, 28);
    expect(plan.executionSettings?.scale, 4);
    expect(plan.executionSettings?.requestIntervalSeconds, 15);
    expect(plan.executionSettings?.requestIntervalRandomRangeSeconds, 20);
    expect(plan.executionSettings?.retryCount, 2);
    expect(plan.executionSettings?.retryIndefinitely, isTrue);
    expect(plan.executionSettings?.outputDirectory, r'C:\outputs');

    final loaded = await queueService.loadPlans();
    expect(
      loaded
          .firstWhere((item) => item.id == 'plan-recast-1-2')
          .executionSettings
          ?.toJson(),
      plan.executionSettings?.toJson(),
    );
  });

  test('new recast plans inherit the latest batch execution settings',
      () async {
    final older = ProductionPlan(
      id: 'plan-older',
      name: 'Older Recast',
      tasks: [
        ProductionTask.manualSingleFrame(
          id: 'older-task',
          planId: 'plan-older',
          title: 'Older',
          payload: const {'input': 'older'},
          createdAt: DateTime.utc(2026, 5, 24),
          updatedAt: DateTime.utc(2026, 5, 24),
        ),
      ],
      executionSettings: const ProductionPlanExecutionSettings(
        model: 'older-model',
        requestIntervalSeconds: 5,
      ),
      createdAt: DateTime.utc(2026, 5, 24),
      updatedAt: DateTime.utc(2026, 5, 24),
    );
    final latest = ProductionPlan(
      id: 'plan-latest',
      name: 'Latest Recast',
      tasks: [
        ProductionTask.manualSingleFrame(
          id: 'latest-task',
          planId: 'plan-latest',
          title: 'Latest',
          payload: const {'input': 'latest'},
          createdAt: DateTime.utc(2026, 5, 25),
          updatedAt: DateTime.utc(2026, 5, 25),
        ),
      ],
      executionSettings: const ProductionPlanExecutionSettings(
        model: 'nai-diffusion-4-5-full',
        sampler: 'k_euler_ancestral',
        width: 832,
        height: 1216,
        steps: 28,
        scale: 4,
        requestIntervalSeconds: 15,
        requestIntervalRandomRangeSeconds: 20,
        retryCount: 2,
        retryIndefinitely: true,
        outputDirectory: r'C:\outputs',
      ),
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 26),
    );
    await queueService.savePlans([older, latest]);

    final plan = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'plan-new',
      planName: 'new_Recast',
      recastRunId: 'run-new',
    );

    expect(plan.executionSettings?.model, 'nai-diffusion-4-5-full');
    expect(plan.executionSettings?.sampler, 'k_euler_ancestral');
    expect(plan.executionSettings?.width, 832);
    expect(plan.executionSettings?.height, 1216);
    expect(plan.executionSettings?.steps, 28);
    expect(plan.executionSettings?.scale, 4);
    expect(plan.executionSettings?.requestIntervalSeconds, 15);
    expect(plan.executionSettings?.requestIntervalRandomRangeSeconds, 20);
    expect(plan.executionSettings?.retryCount, 2);
    expect(plan.executionSettings?.retryIndefinitely, isTrue);
    expect(plan.executionSettings?.outputDirectory, r'C:\outputs');
  });

  test('new recast plans inherit durable last-used execution settings',
      () async {
    const settings = ProductionPlanExecutionSettings(
      model: 'nai-diffusion-4-5-full',
      sampler: 'k_euler_ancestral',
      width: 832,
      height: 1216,
      steps: 28,
      scale: 4,
      requestIntervalSeconds: 15,
      requestIntervalRandomRangeSeconds: 20,
      retryCount: 2,
      retryIndefinitely: true,
      outputDirectory: r'C:\outputs',
    );
    await queueService.saveLastExecutionSettings(settings);

    final plan = await service.enqueueRecastResult(
      result: _recastResult(),
      planId: 'plan-new',
      planName: 'new_Recast',
      recastRunId: 'run-new',
    );

    expect(plan.executionSettings?.toJson(), settings.toJson());
    final loaded = await queueService.loadPlans();
    expect(loaded.single.executionSettings?.toJson(), settings.toJson());
  });
}

ScriptRecastResult _recastResult() {
  return const ScriptRecastResult(
    scriptId: 'script-1',
    mappingId: 'mapping-1',
    configFingerprint: 'config-fingerprint',
    frames: [
      ScriptRecastFramePayload(
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payload: {
          'input': 'city lights',
          'parameters': {'seed': 1}
        },
        payloadFingerprint: 'payload-1',
      ),
      ScriptRecastFramePayload(
        frameIndex: 2,
        sourceFileName: 'nai_2.json',
        payload: {
          'input': 'rain room',
          'parameters': {'seed': 2}
        },
        payloadFingerprint: 'payload-2',
      ),
    ],
  );
}

ScriptRecastResult _recastResultWithSharedReferences() {
  return const ScriptRecastResult(
    scriptId: 'script-1',
    mappingId: 'mapping-1',
    configFingerprint: 'config-fingerprint',
    frames: [
      ScriptRecastFramePayload(
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payload: {
          'input': 'city lights',
          'parameters': {
            'seed': 1,
            'reference_image_multiple': ['encoded-shared-vibe'],
            'reference_strength_multiple': [0.45],
            'reference_information_extracted_multiple': [1.0],
          },
        },
        payloadFingerprint: 'payload-1',
      ),
      ScriptRecastFramePayload(
        frameIndex: 2,
        sourceFileName: 'nai_2.json',
        payload: {
          'input': 'rain room',
          'parameters': {
            'seed': 2,
            'reference_image_multiple': ['encoded-shared-vibe'],
            'reference_strength_multiple': [0.45],
            'reference_information_extracted_multiple': [1.0],
          },
        },
        payloadFingerprint: 'payload-2',
      ),
    ],
  );
}

ScriptRecastResult _manyFrameRecastResult(int count) {
  return ScriptRecastResult(
    scriptId: 'script-many',
    mappingId: 'mapping-many',
    configFingerprint: 'config-many',
    frames: [
      for (var index = 1; index <= count; index += 1)
        ScriptRecastFramePayload(
          frameIndex: index,
          sourceFileName: 'nai_$index.json',
          payload: {
            'input': 'prompt $index',
            'parameters': {'seed': index},
          },
          payloadFingerprint: 'payload-$index',
        ),
    ],
  );
}

class _YieldProbePayloadAdapter extends ScriptRecastPayloadAdapter {
  int callCount = 0;
  var timerRan = false;
  var observedTimerBeforeNinthPayload = false;

  @override
  Map<String, dynamic> toNaiRequestPayload(Map<String, dynamic> payload) {
    callCount += 1;
    if (callCount == 8) {
      Timer.run(() {
        timerRan = true;
      });
    }
    if (callCount == 9) {
      observedTimerBeforeNinthPayload = timerRan;
    }
    return super.toNaiRequestPayload(payload);
  }
}
