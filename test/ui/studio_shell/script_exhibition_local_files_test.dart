import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_shell_view.dart';

void main() {
  test('collects local image paths from exhibition items', () {
    final item = ScriptExhibitionItem(
      id: 'generated-1',
      scriptId: 'script-1',
      scriptTitle: 'Script',
      sourceFolder: r'C:\stories\script',
      versionId: 'production-plan-1',
      versionLabel: 'Plan 1',
      sourceKind: ScriptExhibitionItemSourceKind.generated,
      frameIndex: 1,
      sourceFileName: '001.json',
      title: 'Generated',
      subtitle: 'Done',
      prompt: 'prompt',
      imagePath: r'C:\outputs\generated.png',
      statusLabel: 'Done',
      updatedAt: DateTime.parse('2026-06-18T10:00:00Z'),
      galleryRecord: StudioGalleryRecord.fromRecastPayload(
        id: 'gallery-1',
        title: 'Gallery',
        imagePath: r'C:\gallery\saved.png',
        info: 'prompt',
        payload: const {'input': 'prompt'},
        createdAt: DateTime.parse('2026-06-18T10:00:00Z'),
        provenance: const StudioRecastProvenance(
          scriptId: 'script-1',
          scriptName: 'Script',
          scriptPath: r'C:\stories\script',
          productionPlanId: 'plan-1',
          productionPlanFingerprint: 'fingerprint',
          taskId: 'task-1',
          payloadFingerprint: 'payload',
          mappingConfigFingerprint: 'mapping',
          outputImagePath: r'C:\outputs\from-provenance.png',
        ),
      ),
    );
    final paths = scriptExhibitionLocalImagePathsForItems([
      item,
      ScriptExhibitionItem(
        id: 'remote-1',
        scriptId: 'script-1',
        scriptTitle: 'Script',
        sourceFolder: r'C:\stories\script',
        versionId: 'production-plan-2',
        versionLabel: 'Plan 2',
        sourceKind: ScriptExhibitionItemSourceKind.generated,
        frameIndex: 2,
        sourceFileName: '002.json',
        title: 'Remote',
        subtitle: 'Done',
        prompt: 'prompt',
        imagePath: 'https://example.invalid/remote.png',
        statusLabel: 'Done',
        updatedAt: DateTime.parse('2026-06-18T10:00:00Z'),
      ),
    ]);

    expect(
      paths,
      unorderedEquals([
        r'C:\outputs\generated.png',
        r'C:\gallery\saved.png',
        r'C:\outputs\from-provenance.png',
      ]),
    );
  });

  test('deletes local image files best effort without deleting directories',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-local-files-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}generated.png',
    );
    await imageFile.writeAsBytes(const [1, 2, 3]);
    final nestedDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}nested',
    );
    await nestedDir.create();

    await deleteScriptExhibitionLocalImageFiles([
      imageFile.path,
      nestedDir.path,
      'https://example.invalid/remote.png',
      '${tempDir.path}${Platform.pathSeparator}missing.png',
    ]);

    expect(await imageFile.exists(), isFalse);
    expect(await nestedDir.exists(), isTrue);
  });

  test('batch deletes production version items with one plan load and save',
      () async {
    final originalUpdatedAt = DateTime.parse('2026-06-18T09:00:00Z');
    final deletionUpdatedAt = DateTime.parse('2026-06-18T11:00:00Z');
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Plan 1',
      createdAt: originalUpdatedAt,
      updatedAt: originalUpdatedAt,
      tasks: [
        _task(planId: 'plan-1', taskId: 'task-1'),
        _task(planId: 'plan-1', taskId: 'task-2'),
        _task(planId: 'plan-1', taskId: 'task-kept'),
      ],
    );
    final unrelatedPlan = ProductionPlan(
      id: 'plan-2',
      name: 'Plan 2',
      createdAt: originalUpdatedAt,
      updatedAt: originalUpdatedAt,
      tasks: [_task(planId: 'plan-2', taskId: 'task-other')],
    );
    var loadCount = 0;
    var saveCount = 0;
    List<ProductionPlan>? savedPlans;

    final changed = await deleteScriptExhibitionProductionItems(
      items: [
        _productionItem(planId: 'plan-1', taskId: 'task-1'),
        _productionItem(planId: 'plan-1', taskId: 'task-2'),
      ],
      loadPlans: () async {
        loadCount += 1;
        return [plan, unrelatedPlan];
      },
      savePlans: (plans) async {
        saveCount += 1;
        savedPlans = plans;
      },
      updatedAt: deletionUpdatedAt,
    );

    expect(changed, isTrue);
    expect(loadCount, 1);
    expect(saveCount, 1);
    final saved = savedPlans!;
    expect(saved, hasLength(2));
    final savedPlan = saved.singleWhere((plan) => plan.id == 'plan-1');
    expect(savedPlan.tasks.map((task) => task.id), ['task-kept']);
    expect(savedPlan.updatedAt, deletionUpdatedAt);
    final savedUnrelated = saved.singleWhere((plan) => plan.id == 'plan-2');
    expect(savedUnrelated.tasks.map((task) => task.id), ['task-other']);
    expect(savedUnrelated.updatedAt, originalUpdatedAt);
  });

  test('targeted production deletion never loads or rewrites sibling plans',
      () async {
    final originalUpdatedAt = DateTime.parse('2026-06-18T09:00:00Z');
    final deletionUpdatedAt = DateTime.parse('2026-06-18T11:00:00Z');
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Plan 1',
      createdAt: originalUpdatedAt,
      updatedAt: originalUpdatedAt,
      tasks: [
        _task(planId: 'plan-1', taskId: 'task-delete'),
        _task(planId: 'plan-1', taskId: 'task-kept'),
      ],
    );
    final loadedPlanIds = <String>[];
    List<ProductionPlan>? savedUpdatedPlans;
    Set<String>? savedDeletedPlanIds;

    final changed = await deleteScriptExhibitionProductionItems(
      items: [
        _productionItem(planId: 'plan-1', taskId: 'task-delete'),
      ],
      loadPlans: () => throw StateError('full plan load must not run'),
      savePlans: (_) => throw StateError('full plan save must not run'),
      loadPlan: (planId) async {
        loadedPlanIds.add(planId);
        return plan;
      },
      savePlanChanges: ({
        required updatedPlans,
        required deletedPlanIds,
      }) async {
        savedUpdatedPlans = updatedPlans;
        savedDeletedPlanIds = deletedPlanIds;
      },
      updatedAt: deletionUpdatedAt,
    );

    expect(changed, isTrue);
    expect(loadedPlanIds, ['plan-1']);
    expect(savedDeletedPlanIds, isEmpty);
    expect(savedUpdatedPlans, hasLength(1));
    expect(savedUpdatedPlans!.single.id, 'plan-1');
    expect(
      savedUpdatedPlans!.single.tasks.map((task) => task.id),
      ['task-kept'],
    );
    expect(savedUpdatedPlans!.single.updatedAt, deletionUpdatedAt);
  });

  test('removes one generated task when another image exists for the frame',
      () async {
    final originalUpdatedAt = DateTime.parse('2026-06-18T09:00:00Z');
    final deletionUpdatedAt = DateTime.parse('2026-06-18T11:00:00Z');
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Plan 1',
      createdAt: originalUpdatedAt,
      updatedAt: originalUpdatedAt,
      tasks: [
        _task(planId: 'plan-1', taskId: 'task-1', frameIndex: 7),
        _task(planId: 'plan-1', taskId: 'task-2', frameIndex: 7),
        _task(planId: 'plan-1', taskId: 'task-other', frameIndex: 8),
      ],
    );
    List<ProductionPlan>? savedPlans;

    final changed = await deleteScriptExhibitionProductionItems(
      items: [
        _productionItem(planId: 'plan-1', taskId: 'task-1', frameIndex: 7),
      ],
      loadPlans: () async => [plan],
      savePlans: (plans) async {
        savedPlans = plans;
      },
      updatedAt: deletionUpdatedAt,
    );

    expect(changed, isTrue);
    final savedPlan = savedPlans!.single;
    expect(savedPlan.tasks.map((task) => task.id), [
      'task-2',
      'task-other',
    ]);
    expect(savedPlan.updatedAt, deletionUpdatedAt);
  });

  test('removes the last generated task for a frame instead of requeueing it',
      () async {
    final originalUpdatedAt = DateTime.parse('2026-06-18T09:00:00Z');
    final deletionUpdatedAt = DateTime.parse('2026-06-18T11:00:00Z');
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Plan 1',
      createdAt: originalUpdatedAt,
      updatedAt: originalUpdatedAt,
      tasks: [
        _task(
          planId: 'plan-1',
          taskId: 'task-1',
          frameIndex: 7,
          attempts: 2,
          error: 'previous error',
        ),
        _task(planId: 'plan-1', taskId: 'task-other', frameIndex: 8),
      ],
    );
    List<ProductionPlan>? savedPlans;

    final changed = await deleteScriptExhibitionProductionItems(
      items: [
        _productionItem(planId: 'plan-1', taskId: 'task-1', frameIndex: 7),
      ],
      loadPlans: () async => [plan],
      savePlans: (plans) async {
        savedPlans = plans;
      },
      updatedAt: deletionUpdatedAt,
    );

    expect(changed, isTrue);
    final savedPlan = savedPlans!.single;
    expect(savedPlan.tasks.map((task) => task.id), [
      'task-other',
    ]);
    expect(savedPlan.updatedAt, deletionUpdatedAt);
  });

  test('skips production plan IO when no production items are present',
      () async {
    var loadCount = 0;
    var saveCount = 0;

    final changed = await deleteScriptExhibitionProductionItems(
      items: [
        _productionItem(planId: '', taskId: ''),
      ],
      loadPlans: () async {
        loadCount += 1;
        return const [];
      },
      savePlans: (_) async {
        saveCount += 1;
      },
      updatedAt: DateTime.parse('2026-06-18T11:00:00Z'),
    );

    expect(changed, isFalse);
    expect(loadCount, 0);
    expect(saveCount, 0);
  });
}

ProductionTask _task({
  required String planId,
  required String taskId,
  int frameIndex = 1,
  int attempts = 0,
  String? error,
}) {
  final now = DateTime.parse('2026-06-18T09:00:00Z');
  return ProductionTask.scriptRecastFrame(
    id: taskId,
    planId: planId,
    title: taskId,
    scriptId: 'script-1',
    scriptName: 'Script',
    scriptPath: r'C:\stories\script',
    recastRunId: 'run-1',
    frameIndex: frameIndex,
    sourceFileName: 'frame-$frameIndex.json',
    payload: {'input': taskId},
    status: ProductionTaskStatus.completed,
    attempts: attempts,
    outputImagePath: r'C:\outputs\generated.png',
    error: error,
    createdAt: now,
    updatedAt: now,
    startedAt: now,
    completedAt: now,
  );
}

ScriptExhibitionItem _productionItem({
  required String planId,
  required String taskId,
  int frameIndex = 1,
}) {
  return ScriptExhibitionItem(
    id: 'production-$planId-$taskId',
    scriptId: 'script-1',
    scriptTitle: 'Script',
    sourceFolder: r'C:\stories\script',
    versionId: 'production-$planId',
    versionLabel: 'Plan',
    sourceKind: ScriptExhibitionItemSourceKind.generated,
    frameIndex: frameIndex,
    sourceFileName: 'frame-$frameIndex.json',
    title: taskId,
    subtitle: 'Done',
    prompt: 'prompt',
    imagePath: r'C:\outputs\generated.png',
    statusLabel: 'Done',
    updatedAt: DateTime.parse('2026-06-18T09:00:00Z'),
    productionPlanId: planId,
    taskId: taskId,
  );
}
