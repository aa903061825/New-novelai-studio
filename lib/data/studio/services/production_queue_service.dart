import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class ProductionQueueService {
  final WorkspaceService workspaceService;

  const ProductionQueueService({
    required this.workspaceService,
  });

  Future<List<ProductionPlan>> loadPlans() async {
    final plans = await workspaceService.loadProductionPlans();
    return [
      ...plans,
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  Future<void> savePlans(List<ProductionPlan> plans) {
    return workspaceService.saveProductionPlans(plans);
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
