import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/services/production_queue_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService workspaceService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'production-queue-service-test-',
    );
    workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ProductionQueueService saves and loads deterministic plans', () async {
    final service = ProductionQueueService(workspaceService: workspaceService);
    final task1 = ProductionTask.scriptRecastFrame(
      id: 'task-1',
      planId: 'plan-1',
      title: 'nai_1',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 1,
      sourceFileName: 'nai_1.json',
      payload: const {
        'input': 'city lights',
        'parameters': {'seed': 1}
      },
      suggestedFileName: 'nai_1.png',
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final task2 = ProductionTask.manualSingleFrame(
      id: 'task-2',
      planId: 'plan-1',
      title: 'Manual frame',
      payload: const {
        'input': 'manual',
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

    await service.savePlans([plan]);

    final loaded = await service.loadPlans();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'plan-1');
    expect(loaded.single.tasks, hasLength(2));
    expect(loaded.single.tasks.first.payload, task1.payload);
    expect(
      loaded.single.tasks.first.payloadFingerprint,
      task1.payloadFingerprint,
    );
    expect(loaded.single.planFingerprint, plan.planFingerprint);
    expect(
      File(
        _workspacePath(tempDir, WorkspacePaths.productionPlanFile('plan-1')),
      ).existsSync(),
      isTrue,
    );
  });

  test('deterministic plans do not overwrite legacy batch plans', () async {
    await workspaceService.saveBatchPlans([
      BatchPlan(
        id: 'batch-1',
        name: 'Legacy Queue',
        items: const [
          {'prompt': 'legacy'},
        ],
        createdAt: DateTime.utc(2026, 5, 25),
        updatedAt: DateTime.utc(2026, 5, 25),
      ),
    ]);
    final service = ProductionQueueService(workspaceService: workspaceService);
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Deterministic Queue',
      tasks: [
        ProductionTask.manualSingleFrame(
          id: 'task-1',
          planId: 'plan-1',
          title: 'Manual',
          payload: const {'input': 'manual'},
          createdAt: DateTime.utc(2026, 5, 25),
          updatedAt: DateTime.utc(2026, 5, 25),
        ),
      ],
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );

    await service.savePlans([plan]);

    final legacyPlans = await workspaceService.loadBatchPlans();
    expect(legacyPlans.single.id, 'batch-1');
    expect(legacyPlans.single.items.single['prompt'], 'legacy');
    expect(
      Directory(
        _workspacePath(tempDir, WorkspacePaths.batchPlansDir),
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory(
        _workspacePath(tempDir, WorkspacePaths.deterministicPlansDir),
      ).existsSync(),
      isTrue,
    );
  });

  test('load skips and quarantines invalid deterministic plan files', () async {
    final service = ProductionQueueService(workspaceService: workspaceService);
    final plan = ProductionPlan(
      id: 'plan-valid',
      name: 'Valid Queue',
      tasks: [
        ProductionTask.manualSingleFrame(
          id: 'task-1',
          planId: 'plan-valid',
          title: 'Manual',
          payload: const {'input': 'manual'},
          createdAt: DateTime.utc(2026, 5, 25),
          updatedAt: DateTime.utc(2026, 5, 25),
        ),
      ],
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );

    await service.savePlans([plan]);

    final emptyFile = File(
      _workspacePath(
        tempDir,
        '${WorkspacePaths.deterministicPlansDir}/script-recast-empty.json',
      ),
    );
    final malformedFile = File(
      _workspacePath(
        tempDir,
        '${WorkspacePaths.deterministicPlansDir}/script-recast-malformed.json',
      ),
    );
    await emptyFile.writeAsString('');
    await malformedFile.writeAsString('{');

    final loaded = await service.loadPlans();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'plan-valid');
    expect(await emptyFile.exists(), isFalse);
    expect(await malformedFile.exists(), isFalse);

    final quarantined = await Directory(
      _workspacePath(
        tempDir,
        '${WorkspacePaths.deterministicPlansDir}/_invalid',
      ),
    )
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .toList();

    expect(quarantined, hasLength(2));
    expect(
      quarantined
          .any((entry) => entry.path.endsWith('script-recast-empty.json')),
      isTrue,
    );
    expect(
      quarantined
          .any((entry) => entry.path.endsWith('script-recast-malformed.json')),
      isTrue,
    );
  });

  test('load compacts legacy deterministic plans with repeated references',
      () async {
    final service = ProductionQueueService(workspaceService: workspaceService);
    final sharedVibe = 'encoded-shared-vibe-${List.filled(4096, 'x').join()}';
    final task1 = ProductionTask.scriptRecastFrame(
      id: 'task-1',
      planId: 'plan-refs',
      title: 'Frame 1',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 1,
      sourceFileName: 'nai_1.json',
      payload: {
        'input': 'first prompt',
        'parameters': {
          'seed': 1,
          'reference_image_multiple': [sharedVibe],
          'reference_strength_multiple': [0.45],
          'reference_information_extracted_multiple': [1.0],
        },
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final task2 = ProductionTask.scriptRecastFrame(
      id: 'task-2',
      planId: 'plan-refs',
      title: 'Frame 2',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 2,
      sourceFileName: 'nai_2.json',
      payload: {
        'input': 'second prompt',
        'parameters': {
          'seed': 2,
          'reference_image_multiple': [sharedVibe],
          'reference_strength_multiple': [0.45],
          'reference_information_extracted_multiple': [1.0],
        },
      },
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final legacyPlan = ProductionPlan(
      id: 'plan-refs',
      name: 'Reference Plan',
      tasks: [task1, task2],
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25),
    );
    final file = File(
      _workspacePath(
        tempDir,
        WorkspacePaths.productionPlanFile('plan-refs'),
      ),
    );
    await file.parent.create(recursive: true);
    final legacyJson = jsonEncode(legacyPlan.toJson());
    await file.writeAsString(legacyJson);

    final loaded = await service.loadPlans();
    final rewrittenJson = await file.readAsString();
    final loadedPlan = loaded.single;
    final requestParameters =
        loadedPlan.requestPayloadForTask(loadedPlan.tasks.first)['parameters']
            as Map<String, dynamic>;

    expect(loadedPlan.sharedPayloadParameters['reference_image_multiple'], [
      sharedVibe,
    ]);
    expect(requestParameters['reference_image_multiple'], [
      sharedVibe,
    ]);
    expect(
      RegExp(RegExp.escape(sharedVibe)).allMatches(legacyJson).length,
      2,
    );
    expect(
      RegExp(RegExp.escape(sharedVibe)).allMatches(rewrittenJson).length,
      1,
    );
    expect(rewrittenJson.length, lessThan(legacyJson.length));
  });

  test('saves and loads last-used production execution settings', () async {
    final service = ProductionQueueService(workspaceService: workspaceService);
    const settings = ProductionPlanExecutionSettings(
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
    );

    expect(await service.loadLastExecutionSettings(), isNull);

    await service.saveLastExecutionSettings(settings);

    final loaded = await service.loadLastExecutionSettings();
    expect(loaded?.toJson(), settings.toJson());
    expect(
      File(
        _workspacePath(
          tempDir,
          WorkspacePaths.productionExecutionSettings,
        ),
      ).existsSync(),
      isTrue,
    );
  });
}

String _workspacePath(Directory root, String relativePath) {
  return [
    root.path,
    ...relativePath.split('/'),
  ].join(Platform.pathSeparator);
}
