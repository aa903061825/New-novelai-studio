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
    final resolvedPlanName = _resolvedPlanName(
      requestedName: planName,
      timestamp: timestamp,
      existingPlans: existingPlans,
      scriptId: result.scriptId,
      scriptName: scriptName,
      scriptPath: scriptPath,
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

    await queueService.savePlanChanges(
      updatedPlans: [plan],
      deletedPlanIds: const [],
    );
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

  String _resolvedPlanName({
    required String requestedName,
    required DateTime timestamp,
    required List<ProductionPlan> existingPlans,
    required String scriptId,
    required String? scriptName,
    required String? scriptPath,
  }) {
    final normalizedScriptName = scriptName?.trim();
    if (normalizedScriptName != null && normalizedScriptName.isNotEmpty) {
      return _nextScriptVersionPlanName(
        scriptName: normalizedScriptName,
        scriptId: scriptId,
        scriptPath: scriptPath,
        existingPlans: existingPlans,
      );
    }

    final existing = existingPlans
        .map((plan) => plan.name)
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

  String _nextScriptVersionPlanName({
    required String scriptName,
    required String scriptId,
    required String? scriptPath,
    required List<ProductionPlan> existingPlans,
  }) {
    final matchingPlans = [
      for (final plan in existingPlans)
        if (_planMatchesScript(
          plan,
          scriptId: scriptId,
          scriptName: scriptName,
          scriptPath: scriptPath,
        ))
          plan,
    ];
    var nextVersion = matchingPlans.length + 2;
    final versionPattern = RegExp(
      '^${RegExp.escape(scriptName)}版本([0-9]+)\$',
      caseSensitive: false,
    );
    for (final plan in matchingPlans) {
      final match = versionPattern.firstMatch(plan.name.trim());
      final version = int.tryParse(match?.group(1) ?? '');
      if (version != null && version >= nextVersion) {
        nextVersion = version + 1;
      }
    }

    final existingNames = {
      for (final plan in existingPlans) plan.name.trim().toLowerCase(),
    };
    var candidate = '$scriptName版本$nextVersion';
    while (existingNames.contains(candidate.toLowerCase())) {
      nextVersion += 1;
      candidate = '$scriptName版本$nextVersion';
    }
    return candidate;
  }

  bool _planMatchesScript(
    ProductionPlan plan, {
    required String scriptId,
    required String scriptName,
    required String? scriptPath,
  }) {
    final normalizedScriptId = scriptId.trim();
    final normalizedScriptPath = _normalizedScriptPath(scriptPath);
    final normalizedScriptName = scriptName.trim().toLowerCase();
    return plan.tasks.any((task) {
      final source = task.source;
      final sourceScriptId = source.scriptId?.trim() ?? '';
      if (normalizedScriptId.isNotEmpty &&
          sourceScriptId.isNotEmpty &&
          normalizedScriptId == sourceScriptId) {
        return true;
      }
      final sourceScriptPath = _normalizedScriptPath(source.scriptPath);
      if (normalizedScriptPath != null &&
          sourceScriptPath != null &&
          normalizedScriptPath == sourceScriptPath) {
        return true;
      }
      final incomingHasStrongIdentity =
          normalizedScriptId.isNotEmpty || normalizedScriptPath != null;
      final sourceHasStrongIdentity =
          sourceScriptId.isNotEmpty || sourceScriptPath != null;
      if (incomingHasStrongIdentity && sourceHasStrongIdentity) {
        return false;
      }
      return normalizedScriptName.isNotEmpty &&
          source.scriptName?.trim().toLowerCase() == normalizedScriptName;
    });
  }

  String? _normalizedScriptPath(String? path) {
    final normalized = path
        ?.trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
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
