import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

class ProductionQueueService {
  final WorkspaceService workspaceService;

  const ProductionQueueService({
    required this.workspaceService,
  });

  Future<List<ProductionPlan>> loadPlans() async {
    final plans = await workspaceService.loadProductionPlans();
    final compactedPlans = _compactPlans(plans);
    if (_hasCompactedPlans(plans, compactedPlans)) {
      await workspaceService.saveProductionPlans(compactedPlans);
    }
    return _sortPlansByRecent(compactedPlans);
  }

  Future<List<ProductionPlan>> loadPlansReadOnly() async {
    return _sortPlansByRecent(await workspaceService.loadProductionPlans());
  }

  /// Loads only plans that still have queue-visible work.
  ///
  /// Fully dismissed plans remain on disk for Script Exhibition and can still
  /// be loaded through [loadPlansReadOnly] when a result is explicitly focused.
  Future<List<ProductionPlan>> loadPlansForQueue() async {
    return _sortPlansByRecent(
      await workspaceService.loadProductionPlansForQueue(),
    );
  }

  Future<List<ProductionPlan>> loadPlansForScriptExhibition() async {
    final plans =
        await workspaceService.loadProductionPlansForScriptExhibition();
    return _sortPlansByRecent(_deduplicateScriptExhibitionPlans(plans));
  }

  Future<void> savePlansForScriptExhibition(
    List<ProductionPlan> plans,
  ) async {
    final proposedById = {for (final plan in plans) plan.id.trim(): plan};
    final current = await workspaceService.loadProductionPlans();
    final changedPlans = <ProductionPlan>[];
    for (final plan in current) {
      final proposed = proposedById[plan.id.trim()];
      if (proposed == null) continue;
      final proposedTasks = {for (final task in proposed.tasks) task.id: task};
      var changed = false;
      final tasks = plan.tasks.map((task) {
        final path = proposedTasks[task.id]?.outputImagePath;
        if (path == null || path == task.outputImagePath) return task;
        changed = true;
        return task.copyWith(outputImagePath: path);
      }).toList(growable: false);
      if (changed) {
        changedPlans.add(plan.copyWith(
          tasks: tasks,
          planFingerprint: plan.planFingerprint,
        ));
      }
    }
    if (changedPlans.isNotEmpty) {
      await savePlanChanges(
        updatedPlans: changedPlans,
        deletedPlanIds: const [],
      );
    }
  }

  Future<ProductionPlan?> loadPlanReadOnly(String planId) {
    return workspaceService.loadProductionPlan(planId);
  }

  Future<void> savePlans(List<ProductionPlan> plans) {
    return workspaceService.saveProductionPlans(_compactPlans(plans));
  }

  Future<void> savePlanChanges({
    required Iterable<ProductionPlan> updatedPlans,
    required Iterable<String> deletedPlanIds,
  }) {
    return workspaceService.saveProductionPlanUpdates(
      updatedPlans: [
        for (final plan in updatedPlans) plan.compactSharedPayloadParameters(),
      ],
      deletedPlanIds: deletedPlanIds,
    );
  }

  Future<ProductionPlanExecutionSettings?> loadLastExecutionSettings() {
    return workspaceService.loadProductionExecutionSettings();
  }

  Future<void> saveLastExecutionSettings(
    ProductionPlanExecutionSettings settings,
  ) {
    return workspaceService.saveProductionExecutionSettings(settings);
  }
}

List<ProductionPlan> _compactPlans(List<ProductionPlan> plans) {
  return [
    for (final plan in plans) plan.compactSharedPayloadParameters(),
  ];
}

bool _hasCompactedPlans(
  List<ProductionPlan> original,
  List<ProductionPlan> compacted,
) {
  if (original.length != compacted.length) {
    return true;
  }
  for (var index = 0; index < original.length; index += 1) {
    if (!identical(original[index], compacted[index])) {
      return true;
    }
  }
  return false;
}

List<ProductionPlan> _sortPlansByRecent(List<ProductionPlan> plans) {
  return [...plans]
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
}

List<ProductionPlan> _deduplicateScriptExhibitionPlans(
  List<ProductionPlan> plans,
) {
  final seenPlanIds = <String>{};
  final seenOutputPaths = <String>{};
  final result = <ProductionPlan>[];

  for (final plan in plans) {
    final planId = plan.id.trim();
    if (!seenPlanIds.add(planId)) {
      continue;
    }

    final tasks = <ProductionTask>[];
    for (final task in plan.tasks) {
      final outputPath = task.outputImagePath?.trim() ?? '';
      if (outputPath.isEmpty) {
        tasks.add(task);
        continue;
      }
      final outputKey = _normalizedProductionOutputPath(outputPath);
      if (outputKey.isEmpty || seenOutputPaths.add(outputKey)) {
        tasks.add(task);
      }
    }
    if (tasks.isEmpty) continue;
    result.add(
      tasks.length == plan.tasks.length ? plan : plan.copyWith(tasks: tasks),
    );
  }
  return result;
}

String _normalizedProductionOutputPath(String path) {
  return path.trim().replaceAll('\\', '/').toLowerCase();
}
