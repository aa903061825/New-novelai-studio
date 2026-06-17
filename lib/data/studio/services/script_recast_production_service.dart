import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_payload_adapter.dart';

typedef ScriptRecastProductionClock = DateTime Function();

class ScriptRecastProductionService {
  final ProductionQueueService queueService;
  final ScriptRecastProductionClock now;
  final ScriptRecastPayloadAdapter payloadAdapter;

  const ScriptRecastProductionService({
    required this.queueService,
    required this.now,
    this.payloadAdapter = const ScriptRecastPayloadAdapter(),
  });

  Future<ProductionPlan> enqueueRecastResult({
    required ScriptRecastResult result,
    required String planId,
    required String planName,
    required String recastRunId,
    String? scriptName,
    String? scriptPath,
  }) async {
    final timestamp = now().toUtc();
    final existingPlans = await queueService.loadPlans();
    final requestedPlanId = planId.trim().isEmpty ? 'script-recast' : planId;
    final resolvedPlanId = _nonConflictingPlanId(
      requestedPlanId,
      existingPlans.map((plan) => plan.id),
    );
    final resolvedRecastRunId = _recastRunIdForPlan(
      recastRunId,
      requestedPlanId: requestedPlanId,
      resolvedPlanId: resolvedPlanId,
    );
    final resolvedPlanName = _nonConflictingPlanName(
      requestedName: planName,
      timestamp: timestamp,
      existingPlanNames: existingPlans.map((plan) => plan.name),
    );
    final previousPlan = _findPlan(existingPlans, requestedPlanId);
    final lastUsedSettings = await queueService.loadLastExecutionSettings();
    final inheritedSettings = lastUsedSettings ??
        previousPlan?.executionSettings ??
        _latestExecutionSettings(existingPlans);
    final tasks = <ProductionTask>[];
    for (var index = 0; index < result.frames.length; index += 1) {
      final frame = result.frames[index];
      tasks.add(
        ProductionTask.scriptRecastFrame(
          id: '$resolvedPlanId:frame-${frame.frameIndex}',
          planId: resolvedPlanId,
          title: frame.sourceFileName,
          scriptId: result.scriptId,
          scriptName: scriptName,
          scriptPath: scriptPath,
          recastRunId: resolvedRecastRunId,
          mappingConfigFingerprint: result.configFingerprint,
          frameIndex: frame.frameIndex,
          sourceFileName: frame.sourceFileName,
          payload: payloadAdapter.toNaiRequestPayload(frame.payload),
          payloadFingerprint: frame.payloadFingerprint,
          suggestedFileName: _suggestedPngName(
            planId: resolvedPlanId,
            sourceFileName: frame.sourceFileName,
          ),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      if ((index + 1) % 8 == 0 && index + 1 < result.frames.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final plan = ProductionPlan(
      id: resolvedPlanId,
      name: resolvedPlanName,
      tasks: tasks,
      executionSettings: inheritedSettings,
      createdAt: timestamp,
      updatedAt: timestamp,
    ).compactSharedPayloadParameters();

    await queueService.savePlans([
      plan,
      for (final existing in existingPlans)
        if (existing.id != plan.id) existing,
    ]);
    return plan;
  }

  String _nonConflictingPlanId(String base, Iterable<String> existingPlanIds) {
    final existing = existingPlanIds.toSet();
    if (!existing.contains(base)) return base;
    var suffix = 2;
    while (existing.contains('$base-$suffix')) {
      suffix += 1;
    }
    return '$base-$suffix';
  }

  String _nonConflictingPlanName({
    required String requestedName,
    required DateTime timestamp,
    required Iterable<String> existingPlanNames,
  }) {
    final existing = existingPlanNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final requested = requestedName.trim();
    if (requested.isNotEmpty && !existing.contains(requested)) {
      return requested;
    }
    final dateLabel = _dateLabel(timestamp);
    if (!existing.contains(dateLabel)) {
      return dateLabel;
    }
    var suffix = 2;
    while (existing.contains('$dateLabel-$suffix')) {
      suffix += 1;
    }
    return '$dateLabel-$suffix';
  }

  String _dateLabel(DateTime timestamp) {
    final date = timestamp.toUtc();
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _recastRunIdForPlan(
    String recastRunId, {
    required String requestedPlanId,
    required String resolvedPlanId,
  }) {
    if (requestedPlanId == resolvedPlanId) {
      return recastRunId;
    }
    final trimmed = recastRunId.trim();
    if (trimmed.isEmpty || trimmed == '$requestedPlanId-run') {
      return '$resolvedPlanId-run';
    }
    return trimmed;
  }

  String _suggestedPngName({
    required String planId,
    required String sourceFileName,
  }) {
    final withoutJson = sourceFileName.replaceFirst(
      RegExp(r'\.json$', caseSensitive: false),
      '',
    );
    return '${_safeFilePrefix(planId)}-$withoutJson.png';
  }

  String _safeFilePrefix(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'script-recast' : normalized;
  }

  ProductionPlan? _findPlan(List<ProductionPlan> plans, String planId) {
    for (final plan in plans) {
      if (plan.id == planId) return plan;
    }
    return null;
  }

  ProductionPlanExecutionSettings? _latestExecutionSettings(
    List<ProductionPlan> plans,
  ) {
    ProductionPlan? latest;
    for (final plan in plans) {
      if (plan.executionSettings == null) continue;
      if (latest == null || plan.updatedAt.isAfter(latest.updatedAt)) {
        latest = plan;
      }
    }
    return latest?.executionSettings;
  }
}
