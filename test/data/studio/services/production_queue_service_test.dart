import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

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

  test('exhibition path updates preserve newer queue state and other plans',
      () async {
    final now = DateTime.utc(2026);
    ProductionTask task(String id, ProductionTaskStatus status) =>
        ProductionTask.manualSingleFrame(
          id: id,
          planId: 'plan-1',
          title: id,
          payload: const {'input': 'local test'},
          status: status,
          outputImagePath: '$id.png',
          createdAt: now,
          updatedAt: now,
        );
    final first = task('first', ProductionTaskStatus.completed);
    final running = task('second', ProductionTaskStatus.running);
    final current = ProductionPlan(
      id: 'plan-1',
      name: 'Latest name',
      tasks: [first, running],
      createdAt: now,
      updatedAt: now,
    );
    final unrelated = ProductionPlan(
      id: 'plan-2',
      name: 'Unrelated',
      tasks: const [],
      createdAt: now,
      updatedAt: now,
    );
    await workspaceService.saveProductionPlans([current, unrelated]);
    final service = ProductionQueueService(workspaceService: workspaceService);
    await service.savePlansForScriptExhibition([
      current.copyWith(name: 'Stale name', tasks: [
        first.copyWith(outputImagePath: 'organized.png'),
      ]),
    ]);
    final stored = await workspaceService.loadProductionPlans();
    expect(stored.map((plan) => plan.id), containsAll(['plan-1', 'plan-2']));
    final updated = stored.singleWhere((plan) => plan.id == 'plan-1');
    expect(updated.name, 'Latest name');
    expect(updated.tasks.first.outputImagePath, 'organized.png');
    expect(updated.tasks.last.status, ProductionTaskStatus.running);
    expect(updated.tasks.last.outputImagePath, 'second.png');
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

  test('read-only load does not rewrite legacy deterministic plans', () async {
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

    final loaded = await service.loadPlansReadOnly();
    final rewrittenJson = await file.readAsString();

    expect(loaded.single.id, 'plan-refs');
    expect(rewrittenJson, legacyJson);
    expect(
      RegExp(RegExp.escape(sharedVibe)).allMatches(rewrittenJson).length,
      2,
    );
  });

  test('read-only load tolerates concurrent deterministic plan saves',
      () async {
    final service = ProductionQueueService(workspaceService: workspaceService);
    final largePrompt = List.filled(16384, 'prompt-fragment').join(',');
    List<ProductionPlan> plansForGeneration(int generation) {
      return [
        for (var index = 0; index < 12; index += 1)
          ProductionPlan(
            id: 'plan-$index',
            name: 'Plan $index',
            tasks: [
              ProductionTask.manualSingleFrame(
                id: 'task-$generation-$index',
                planId: 'plan-$index',
                title: 'Manual $index',
                payload: {
                  'input': '$generation-$index-$largePrompt',
                  'parameters': {'seed': generation * 1000 + index},
                },
                createdAt: DateTime.utc(2026, 5, 25),
                updatedAt: DateTime.utc(2026, 5, 25, 0, generation),
              ),
            ],
            createdAt: DateTime.utc(2026, 5, 25),
            updatedAt: DateTime.utc(2026, 5, 25, 0, generation),
          ),
      ];
    }

    await service.savePlans(plansForGeneration(0));

    var writerDone = false;
    final loadErrors = <Object>[];
    final writer = () async {
      try {
        for (var generation = 1; generation <= 6; generation += 1) {
          await service.savePlans(plansForGeneration(generation));
        }
      } finally {
        writerDone = true;
      }
    }();

    while (!writerDone) {
      try {
        await service.loadPlansReadOnly();
      } catch (error) {
        loadErrors.add(error);
      }
      await Future<void>.delayed(Duration.zero);
    }
    await writer;

    expect(loadErrors, isEmpty);
    expect((await service.loadPlansReadOnly()).length, 12);
  });

  test('queue load excludes exhibition-only plans without deleting them',
      () async {
    final service = ProductionQueueService(workspaceService: workspaceService);
    final now = DateTime.utc(2026, 8, 22);

    ProductionTask task({
      required String id,
      required String planId,
      DateTime? queueDismissedAt,
    }) {
      return ProductionTask.manualSingleFrame(
        id: id,
        planId: planId,
        title: id,
        payload: {'input': id},
        status: queueDismissedAt == null
            ? ProductionTaskStatus.queued
            : ProductionTaskStatus.completed,
        outputImagePath: queueDismissedAt == null ? null : 'C:/outputs/$id.png',
        queueDismissedAt: queueDismissedAt,
        createdAt: now,
        updatedAt: now,
      );
    }

    ProductionPlan plan(String id, List<ProductionTask> tasks) {
      return ProductionPlan(
        id: id,
        name: id,
        tasks: tasks,
        createdAt: now,
        updatedAt: now,
      );
    }

    final dismissedAt = now.add(const Duration(hours: 1));
    final exhibitionOnly = plan('exhibition-only', [
      task(
        id: 'archived-task',
        planId: 'exhibition-only',
        queueDismissedAt: dismissedAt,
      ),
    ]);
    final active = plan('active-plan', [
      task(
        id: 'dismissed-sibling',
        planId: 'active-plan',
        queueDismissedAt: dismissedAt,
      ),
      task(id: 'queued-task', planId: 'active-plan'),
    ]);
    final empty = plan('empty-plan', const []);
    await service.savePlans([exhibitionOnly, active, empty]);

    final queuePlans = await service.loadPlansForQueue();
    final allPlans = await service.loadPlansReadOnly();

    expect(queuePlans.map((plan) => plan.id).toSet(), {
      'active-plan',
      'empty-plan',
    });
    expect(queuePlans.singleWhere((plan) => plan.id == 'active-plan').tasks,
        hasLength(2));
    expect(allPlans.map((plan) => plan.id).toSet(), {
      'exhibition-only',
      'active-plan',
      'empty-plan',
    });
    expect(
      File(
        _workspacePath(
          tempDir,
          WorkspacePaths.productionPlanFile('exhibition-only'),
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test(
      'script exhibition load includes completed results from explicit plan backups',
      () async {
    final service = ProductionQueueService(workspaceService: workspaceService);
    final now = DateTime.utc(2026, 6, 1, 10);

    ProductionTask task({
      required String id,
      required String planId,
      ProductionTaskStatus status = ProductionTaskStatus.queued,
      String? outputImagePath,
    }) {
      return ProductionTask.manualSingleFrame(
        id: id,
        planId: planId,
        title: id,
        payload: {'input': id},
        status: status,
        outputImagePath: outputImagePath,
        createdAt: now,
        updatedAt: now,
      );
    }

    ProductionPlan plan(String id, List<ProductionTask> tasks) {
      return ProductionPlan(
        id: id,
        name: id,
        tasks: tasks,
        createdAt: now,
        updatedAt: now,
      );
    }

    final activePlan = plan('active-plan', [
      task(id: 'active-task', planId: 'active-plan'),
    ]);
    await service.savePlans([activePlan]);

    final nestedBackup = Directory(
      _workspacePath(
        tempDir,
        '${WorkspacePaths.deterministicPlansDir}/backup-20260610-test',
      ),
    );
    final siblingBackup = Directory(
      _workspacePath(
        tempDir,
        'production/deterministic_plans_backup_test',
      ),
    );
    await nestedBackup.create(recursive: true);
    await siblingBackup.create(recursive: true);

    final nestedOutput = File(
      '${nestedBackup.path}${Platform.pathSeparator}nested.png',
    );
    final siblingOutput = File(
      '${siblingBackup.path}${Platform.pathSeparator}sibling.png',
    );
    await nestedOutput.writeAsBytes(const [1, 2, 3]);
    await siblingOutput.writeAsBytes(const [4, 5, 6]);

    final nestedPlan = plan('nested-archive', [
      task(
        id: 'nested-completed',
        planId: 'nested-archive',
        status: ProductionTaskStatus.completed,
        outputImagePath: nestedOutput.path,
      ),
      task(id: 'nested-queued', planId: 'nested-archive'),
    ]);
    final siblingPlan = plan('sibling-archive', [
      task(
        id: 'sibling-completed',
        planId: 'sibling-archive',
        status: ProductionTaskStatus.completed,
        outputImagePath: siblingOutput.path,
      ),
    ]);
    await File(
      '${nestedBackup.path}${Platform.pathSeparator}nested-plan.json',
    ).writeAsString(jsonEncode(nestedPlan.toJson()));
    await File(
      '${siblingBackup.path}${Platform.pathSeparator}sibling-plan.json',
    ).writeAsString(jsonEncode(siblingPlan.toJson()));

    final exhibitionPlans = await service.loadPlansForScriptExhibition();
    final exhibitionById = {
      for (final exhibitionPlan in exhibitionPlans)
        exhibitionPlan.id: exhibitionPlan,
    };

    expect(
        exhibitionById.keys,
        containsAll([
          'active-plan',
          'nested-archive',
          'sibling-archive',
        ]));
    expect(exhibitionById['nested-archive']!.tasks, hasLength(1));
    expect(
      exhibitionById['nested-archive']!.tasks.single.status,
      ProductionTaskStatus.completed,
    );
    expect(
      exhibitionById['nested-archive']!.tasks.single.outputImagePath,
      nestedOutput.path,
    );

    final queuePlans = await service.loadPlansReadOnly();
    expect(queuePlans.map((queuePlan) => queuePlan.id), ['active-plan']);

    await service.savePlansForScriptExhibition(exhibitionPlans);

    expect(
      await File(
        '${nestedBackup.path}${Platform.pathSeparator}nested-plan.json',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        _workspacePath(
          tempDir,
          WorkspacePaths.productionPlanFile('nested-archive'),
        ),
      ).exists(),
      isFalse,
    );
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
      retryOn429DelaySeconds: 17,
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
