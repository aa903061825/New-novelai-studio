import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';

void main() {
  test('ProductionTask preserves complete payload and stable fingerprint', () {
    final task = ProductionTask.scriptRecastFrame(
      id: 'task-1',
      planId: 'plan-1',
      title: 'nai_1',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 1,
      sourceFileName: 'nai_1.json',
      payload: const {
        'input': 'city lights',
        'parameters': {
          'seed': 123456,
          'width': 1216,
          'height': 832,
          'sampler': 'k_euler',
        },
        'extra': [
          {'role': 'heroine', 'x': 0.25, 'y': 0.55},
        ],
      },
      suggestedFileName: 'nai_1.png',
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );

    final restored = ProductionTask.fromJson(task.toJson());

    expect(restored.payload, task.payload);
    expect(restored.payloadFingerprint, task.payloadFingerprint);
    expect(restored.suggestedFileName, 'nai_1.png');
    expect(restored.status, ProductionTaskStatus.queued);
    expect(restored.attempts, 0);
    expect(restored.source.scriptId, 'script-1');
    expect(restored.source.recastRunId, 'run-1');
    expect(restored.source.frameIndex, 1);
    expect(restored.source.sourceFileName, 'nai_1.json');
  });

  test('ProductionTask persists reviewer rating metadata', () {
    final ratedAt = DateTime.utc(2026, 5, 28, 10, 30);
    final task = ProductionTask.manualSingleFrame(
      id: 'task-rated',
      planId: 'plan-1',
      title: 'Rated frame',
      payload: const {
        'input': 'keeper prompt',
      },
      rating: 5,
      ratedAt: ratedAt,
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );

    final restored = ProductionTask.fromJson(task.toJson());

    expect(restored.rating, 5);
    expect(restored.ratedAt, ratedAt);
    expect(restored.copyWith(rating: 3).rating, 3);
  });

  test('ProductionTask payload fingerprint ignores map insertion order', () {
    final first = ProductionTask.manualSingleFrame(
      id: 'task-a',
      planId: 'plan-1',
      title: 'Manual',
      payload: const {
        'parameters': {'height': 832, 'width': 1216, 'seed': 7},
        'input': 'same prompt',
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final second = ProductionTask.manualSingleFrame(
      id: 'task-b',
      planId: 'plan-1',
      title: 'Manual',
      payload: const {
        'input': 'same prompt',
        'parameters': {'seed': 7, 'width': 1216, 'height': 832},
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );

    expect(second.payloadFingerprint, first.payloadFingerprint);
    expect(
      ProductionTask.fromJson(first.toJson()).payloadFingerprint,
      first.payloadFingerprint,
    );
  });

  test('ProductionPlan derives stable fingerprint from task fingerprints', () {
    final task1 = ProductionTask.manualSingleFrame(
      id: 'task-1',
      planId: 'plan-1',
      title: 'Frame 1',
      payload: const {
        'input': 'first',
        'parameters': {'seed': 1}
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final task2 = ProductionTask.scriptRecastFrame(
      id: 'task-2',
      planId: 'plan-1',
      title: 'Frame 2',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 2,
      sourceFileName: 'nai_2.json',
      payload: const {
        'input': 'second',
        'parameters': {'seed': 2}
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Script Recast',
      tasks: [task1, task2],
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final reorderedPayloadPlan = ProductionPlan.fromJson(plan.toJson());

    expect(reorderedPayloadPlan.planFingerprint, plan.planFingerprint);
    expect(
      plan.planFingerprint,
      isNot(ProductionPlan(
        id: 'plan-1',
        name: 'Script Recast',
        tasks: [task2, task1],
        createdAt: DateTime.utc(2026, 5, 25),
        updatedAt: DateTime.utc(2026, 5, 25),
      ).planFingerprint),
    );
  });

  test(
      'ProductionPlan persists batch execution settings without fingerprint noise',
      () {
    final task = ProductionTask.manualSingleFrame(
      id: 'task-1',
      planId: 'plan-1',
      title: 'Frame 1',
      payload: const {
        'input': 'first',
        'parameters': {'seed': 1}
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Script Recast',
      tasks: [task],
      executionSettings: const ProductionPlanExecutionSettings(
        model: 'nai-diffusion-4-5-full',
        sampler: 'k_euler_ancestral',
        width: 832,
        height: 1216,
        steps: 28,
        scale: 4.5,
        cfgRescale: 0.4,
        noiseSchedule: 'karras',
        sm: false,
        smDyn: false,
        dynamicThresholding: true,
        varietyPlus: true,
        autoPosition: true,
        legacyUc: true,
        useOriginalSampler: true,
        useOriginalNoiseSchedule: true,
        seed: 777,
        useOriginalSeed: false,
        requestIntervalSeconds: 15,
        requestIntervalRandomRangeSeconds: 20,
        retryCount: 2,
        retryIndefinitely: true,
        retryOn429DelaySeconds: 17,
        outputDirectory: r'C:\outputs',
      ),
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );

    final restored = ProductionPlan.fromJson(plan.toJson());

    expect(restored.planFingerprint, plan.planFingerprint);
    expect(restored.executionSettings?.model, 'nai-diffusion-4-5-full');
    expect(restored.executionSettings?.sampler, 'k_euler_ancestral');
    expect(restored.executionSettings?.width, 832);
    expect(restored.executionSettings?.height, 1216);
    expect(restored.executionSettings?.steps, 28);
    expect(restored.executionSettings?.scale, 4.5);
    expect(restored.executionSettings?.cfgRescale, 0.4);
    expect(restored.executionSettings?.noiseSchedule, 'karras');
    expect(restored.executionSettings?.sm, isFalse);
    expect(restored.executionSettings?.smDyn, isFalse);
    expect(restored.executionSettings?.dynamicThresholding, isTrue);
    expect(restored.executionSettings?.varietyPlus, isTrue);
    expect(restored.executionSettings?.autoPosition, isTrue);
    expect(restored.executionSettings?.legacyUc, isTrue);
    expect(restored.executionSettings?.useOriginalSampler, isTrue);
    expect(restored.executionSettings?.useOriginalNoiseSchedule, isTrue);
    expect(restored.executionSettings?.seed, 777);
    expect(restored.executionSettings?.useOriginalSeed, isFalse);
    expect(restored.executionSettings?.requestIntervalSeconds, 15);
    expect(restored.executionSettings?.requestIntervalRandomRangeSeconds, 20);
    expect(restored.executionSettings?.retryCount, 2);
    expect(restored.executionSettings?.retryIndefinitely, isTrue);
    expect(restored.executionSettings?.retryOn429DelaySeconds, 17);
    expect(restored.executionSettings?.outputDirectory, r'C:\outputs');
  });

  test('legacy batch settings preserve newly supported parameters', () {
    final restored = ProductionPlanExecutionSettings.fromJson(const {
      'model': 'nai-diffusion-4-5-full',
      'sampler': 'k_euler_ancestral',
      'steps': 28,
      'scale': 4.0,
      'width': 832,
      'height': 1216,
      'seed': -1,
    });

    expect(restored.useOriginalCfgRescale, isTrue);
    expect(restored.useOriginalNoiseSchedule, isTrue);
    expect(restored.useOriginalSm, isTrue);
    expect(restored.useOriginalSmDyn, isTrue);
    expect(restored.useOriginalDynamicThresholding, isTrue);
    expect(restored.useOriginalVarietyPlus, isTrue);
    expect(restored.useOriginalAutoPosition, isTrue);
    expect(restored.useOriginalLegacyUc, isTrue);
  });

  test('ProductionPlan compacts repeated shared reference payload parameters',
      () {
    final task1 = ProductionTask.scriptRecastFrame(
      id: 'task-1',
      planId: 'plan-1',
      title: 'Frame 1',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 1,
      sourceFileName: 'nai_1.json',
      payload: const {
        'input': 'first prompt',
        'parameters': {
          'seed': 1,
          'reference_image_multiple': ['encoded-shared-vibe'],
          'reference_strength_multiple': [0.45],
          'reference_information_extracted_multiple': [1.0],
        },
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final task2 = ProductionTask.scriptRecastFrame(
      id: 'task-2',
      planId: 'plan-1',
      title: 'Frame 2',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 2,
      sourceFileName: 'nai_2.json',
      payload: const {
        'input': 'second prompt',
        'parameters': {
          'seed': 2,
          'reference_image_multiple': ['encoded-shared-vibe'],
          'reference_strength_multiple': [0.45],
          'reference_information_extracted_multiple': [1.0],
        },
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Script Recast',
      tasks: [task1, task2],
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );

    final compacted = plan.compactSharedPayloadParameters();
    final firstParameters =
        compacted.tasks.first.payload['parameters'] as Map<String, dynamic>;
    final requestParameters =
        compacted.requestPayloadForTask(compacted.tasks.first)['parameters']
            as Map<String, dynamic>;
    final normalizedTask = compacted.tasks.first.copyWith(
      payload: {
        ...compacted.tasks.first.payload,
        'parameters': const {
          'seed': 1,
          'reference_image_multiple': [],
          'reference_strength_multiple': [],
          'reference_information_extracted_multiple': [],
        },
      },
    );
    final normalizedRequestParameters =
        compacted.requestPayloadForTask(normalizedTask)['parameters']
            as Map<String, dynamic>;

    expect(compacted.planFingerprint, plan.planFingerprint);
    expect(compacted.tasks.first.payloadFingerprint, task1.payloadFingerprint);
    expect(compacted.sharedPayloadParameters, {
      'reference_image_multiple': ['encoded-shared-vibe'],
      'reference_strength_multiple': [0.45],
      'reference_information_extracted_multiple': [1.0],
    });
    expect(firstParameters, isNot(contains('reference_image_multiple')));
    expect(firstParameters['seed'], 1);
    expect(requestParameters['reference_image_multiple'], [
      'encoded-shared-vibe',
    ]);
    expect(requestParameters['seed'], 1);
    expect(normalizedRequestParameters['reference_image_multiple'], [
      'encoded-shared-vibe',
    ]);
    expect(
      ProductionPlan.fromJson(compacted.toJson()).toJson(),
      compacted.toJson(),
    );
  });

  test('ProductionTask persists queue dismissal without fingerprint noise', () {
    final updatedAt = DateTime.utc(2026, 6, 1, 10);
    final dismissedAt = DateTime.utc(2026, 6, 2, 11);
    final task = ProductionTask.scriptRecastFrame(
      id: 'task-dismissed',
      planId: 'plan-1',
      title: 'Frame 1',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 1,
      sourceFileName: 'frame-1.json',
      payload: const {'input': 'same payload'},
      status: ProductionTaskStatus.completed,
      outputImagePath: 'C:/output/frame-1.png',
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
    final dismissed = task.copyWith(queueDismissedAt: dismissedAt);
    final restored = ProductionTask.fromJson(dismissed.toJson());
    final legacy = ProductionTask.fromJson(
      Map<String, dynamic>.from(task.toJson())..remove('queueDismissedAt'),
    );

    expect(dismissed.isQueueDismissed, isTrue);
    expect(restored.queueDismissedAt, dismissedAt);
    expect(restored.payloadFingerprint, task.payloadFingerprint);
    expect(restored.updatedAt, updatedAt);
    expect(legacy.queueDismissedAt, isNull);
    expect(dismissed.copyWith(clearQueueDismissedAt: true).isQueueDismissed,
        isFalse);
  });
}
