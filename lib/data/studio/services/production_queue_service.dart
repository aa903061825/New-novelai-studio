import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

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
    return [
      ...compactedPlans,
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  Future<void> savePlans(List<ProductionPlan> plans) {
    return workspaceService.saveProductionPlans(_compactPlans(plans));
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
