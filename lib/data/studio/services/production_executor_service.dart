import 'dart:math';
import 'dart:typed_data';

import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/services/production_nai_adapter_service.dart';
import 'package:nai_casrand/data/studio/services/production_queue_service.dart';

typedef ProductionImageRequest = Future<Uint8List> Function(
  Map<String, dynamic> payload,
);
typedef ProductionImageSave = Future<String> Function(
  Uint8List bytes,
  String fileName,
);
typedef ProductionScopedImageSave = Future<String> Function(
  Uint8List bytes,
  String fileName,
  String productionPlanId,
  String? outputDirectory,
);
typedef ProductionClock = DateTime Function();
typedef ProductionDelay = Future<void> Function(Duration duration);
typedef ProductionRandomInt = int Function(int upperBound);
typedef ProductionTaskUpdate = Future<void> Function(ProductionTask task);
typedef ProductionShouldContinue = bool Function();

Future<void> _defaultProductionDelay(Duration duration) {
  return Future<void>.delayed(duration);
}

int _defaultProductionRandomInt(int upperBound) {
  return Random().nextInt(upperBound);
}

class ProductionExecutionResult {
  final ProductionPlan plan;
  final List<String> changedTaskIds;

  const ProductionExecutionResult({
    required this.plan,
    required this.changedTaskIds,
  });

  List<ProductionTask> get tasks => plan.tasks;
}

class ProductionResumeMismatch implements Exception {
  final String message;

  const ProductionResumeMismatch(this.message);

  @override
  String toString() => 'ProductionResumeMismatch: $message';
}

class ProductionExecutorService {
  final ProductionQueueService? queueService;
  final ProductionImageRequest requestImage;
  final ProductionImageSave saveImage;
  final ProductionScopedImageSave? savePlanImage;
  final ProductionClock now;
  final ProductionDelay delay;
  final ProductionRandomInt randomInt;

  ProductionExecutorService({
    this.queueService,
    required this.requestImage,
    required this.saveImage,
    this.savePlanImage,
    required this.now,
    ProductionDelay? delay,
    ProductionRandomInt? randomInt,
  })  : delay = delay ?? _defaultProductionDelay,
        randomInt = randomInt ?? _defaultProductionRandomInt;

  Future<ProductionPlan> runPlan(
    ProductionPlan plan, {
    int maxRetries = 1,
    bool retryIndefinitely = false,
    Duration requestInterval = Duration.zero,
    Duration requestIntervalRandomRange = Duration.zero,
    ProductionTaskUpdate? onTaskUpdate,
    ProductionShouldContinue? shouldContinue,
  }) async {
    final result = await _runMatchingTasks(
      plan,
      maxRetries: maxRetries,
      retryIndefinitely: retryIndefinitely,
      requestInterval: requestInterval,
      requestIntervalRandomRange: requestIntervalRandomRange,
      onTaskUpdate: onTaskUpdate,
      shouldRun: (task) => task.status == ProductionTaskStatus.queued,
      shouldContinue: shouldContinue,
    );
    return result.plan;
  }

  Future<ProductionPlan> retryFailed(
    String planId, {
    int maxRetries = 1,
    bool retryIndefinitely = false,
  }) async {
    final plans = await _loadPlans();
    final plan = _findPlan(plans, planId);
    final result = await _runMatchingTasks(
      plan,
      maxRetries: maxRetries,
      retryIndefinitely: retryIndefinitely,
      requestInterval: Duration.zero,
      requestIntervalRandomRange: Duration.zero,
      onTaskUpdate: null,
      shouldRun: (task) => task.status == ProductionTaskStatus.failed,
    );
    await _saveUpdatedPlan(plans, result.plan);
    return result.plan;
  }

  Future<ProductionExecutionResult> rerunFrame(
    String planId, {
    required int frameIndex,
    int maxRetries = 1,
    bool retryIndefinitely = false,
  }) async {
    final plans = await _loadPlans();
    final plan = _findPlan(plans, planId);
    final result = await _runMatchingTasks(
      plan,
      maxRetries: maxRetries,
      retryIndefinitely: retryIndefinitely,
      requestInterval: Duration.zero,
      requestIntervalRandomRange: Duration.zero,
      onTaskUpdate: null,
      shouldRun: (task) =>
          task.taskType == ProductionTaskType.scriptRecastFrame &&
          task.source.frameIndex == frameIndex,
    );
    await _saveUpdatedPlan(plans, result.plan);
    return result;
  }

  Future<ProductionExecutionResult> rerunTask(
    String planId, {
    required String taskId,
    int maxRetries = 1,
    bool retryIndefinitely = false,
  }) async {
    final plans = await _loadPlans();
    final plan = _findPlan(plans, planId);
    final result = await _runMatchingTasks(
      plan,
      maxRetries: maxRetries,
      retryIndefinitely: retryIndefinitely,
      requestInterval: Duration.zero,
      requestIntervalRandomRange: Duration.zero,
      onTaskUpdate: null,
      shouldRun: (task) => task.id == taskId,
    );
    await _saveUpdatedPlan(plans, result.plan);
    return result;
  }

  Future<ProductionExecutionResult> rerunTaskInPlan(
    ProductionPlan plan, {
    required String taskId,
    int maxRetries = 1,
    bool retryIndefinitely = false,
    ProductionTaskUpdate? onTaskUpdate,
    ProductionShouldContinue? shouldContinue,
  }) {
    return _runMatchingTasks(
      plan,
      maxRetries: maxRetries,
      retryIndefinitely: retryIndefinitely,
      requestInterval: Duration.zero,
      requestIntervalRandomRange: Duration.zero,
      onTaskUpdate: onTaskUpdate,
      shouldRun: (task) => task.id == taskId,
      shouldContinue: shouldContinue,
    );
  }

  Future<ProductionExecutionResult> rerunAbnormalTasksInPlan(
    ProductionPlan plan, {
    int maxRetries = 1,
    bool retryIndefinitely = false,
    ProductionTaskUpdate? onTaskUpdate,
    ProductionShouldContinue? shouldContinue,
  }) {
    return _runMatchingTasks(
      plan,
      maxRetries: maxRetries,
      retryIndefinitely: retryIndefinitely,
      requestInterval: Duration.zero,
      requestIntervalRandomRange: Duration.zero,
      onTaskUpdate: onTaskUpdate,
      shouldRun: _isAbnormalTask,
      shouldContinue: shouldContinue,
    );
  }

  Future<ProductionPlan> resumePlan({
    required String productionPlanId,
    required String recastRunId,
    required String planFingerprint,
    int maxRetries = 1,
    bool retryIndefinitely = false,
  }) async {
    final plans = await _loadPlans();
    final plan = _findPlan(plans, productionPlanId);
    if (plan.planFingerprint != planFingerprint) {
      throw ProductionResumeMismatch(
        'Plan fingerprint changed for $productionPlanId.',
      );
    }
    final hasDifferentRun = plan.tasks.any(
      (task) =>
          task.taskType == ProductionTaskType.scriptRecastFrame &&
          task.source.recastRunId != recastRunId,
    );
    if (hasDifferentRun) {
      throw ProductionResumeMismatch(
        'Recast run changed for $productionPlanId.',
      );
    }
    final result = await _runMatchingTasks(
      plan,
      maxRetries: maxRetries,
      retryIndefinitely: retryIndefinitely,
      requestInterval: Duration.zero,
      requestIntervalRandomRange: Duration.zero,
      onTaskUpdate: null,
      shouldRun: (task) => task.status == ProductionTaskStatus.queued,
    );
    await _saveUpdatedPlan(plans, result.plan);
    return result.plan;
  }

  Future<ProductionExecutionResult> _runMatchingTasks(
    ProductionPlan plan, {
    required int maxRetries,
    required bool retryIndefinitely,
    required Duration requestInterval,
    required Duration requestIntervalRandomRange,
    required ProductionTaskUpdate? onTaskUpdate,
    required bool Function(ProductionTask task) shouldRun,
    ProductionShouldContinue? shouldContinue,
  }) async {
    final changedTaskIds = <String>[];
    final updatedTasks = <ProductionTask>[];
    final effectiveInterval =
        requestInterval.isNegative ? Duration.zero : requestInterval;
    final effectiveRandomRange = requestIntervalRandomRange.isNegative
        ? Duration.zero
        : requestIntervalRandomRange;
    var hasRunPreviousTask = false;
    for (var index = 0; index < plan.tasks.length; index += 1) {
      final task = plan.tasks[index];
      if (!shouldRun(task)) {
        updatedTasks.add(task);
        continue;
      }
      if (shouldContinue != null && !shouldContinue()) {
        updatedTasks.addAll(plan.tasks.skip(index));
        break;
      }
      if (hasRunPreviousTask) {
        final nextDelay = _nextRequestInterval(
          effectiveInterval,
          effectiveRandomRange,
        );
        if (nextDelay.inMicroseconds > 0) {
          await delay(nextDelay);
        }
      }
      changedTaskIds.add(task.id);
      updatedTasks.add(
        await _executeTask(
          plan,
          task,
          maxRetries: maxRetries,
          retryIndefinitely: retryIndefinitely,
          onTaskUpdate: onTaskUpdate,
          shouldContinue: shouldContinue,
        ),
      );
      hasRunPreviousTask = true;
    }
    return ProductionExecutionResult(
      plan: plan.copyWith(tasks: updatedTasks, updatedAt: now()),
      changedTaskIds: changedTaskIds,
    );
  }

  Duration _nextRequestInterval(
    Duration baseInterval,
    Duration randomRange,
  ) {
    final rangeSeconds = randomRange.inSeconds;
    if (rangeSeconds <= 0) return baseInterval;
    final jitterSeconds =
        randomInt(rangeSeconds + 1).clamp(0, rangeSeconds).toInt();
    return baseInterval + Duration(seconds: jitterSeconds);
  }

  Future<ProductionTask> _executeTask(
    ProductionPlan plan,
    ProductionTask task, {
    required int maxRetries,
    required bool retryIndefinitely,
    ProductionTaskUpdate? onTaskUpdate,
    ProductionShouldContinue? shouldContinue,
  }) async {
    final effectiveMaxRetries = max(1, maxRetries);
    var currentTask = task;
    var attempt = 0;
    while (retryIndefinitely || attempt < effectiveMaxRetries) {
      attempt += 1;
      final startedAt = now();
      final requestTask = _taskWithExecutionSeed(plan, currentTask);
      final runningTask = requestTask.copyWith(
        status: ProductionTaskStatus.running,
        attempts: requestTask.attempts + 1,
        updatedAt: startedAt,
        startedAt: startedAt,
        clearCompletedAt: true,
        clearError: true,
      );
      await onTaskUpdate?.call(runningTask);

      try {
        final bytes =
            await requestImage(plan.requestPayloadForTask(runningTask));
        final fileName = _outputFileName(runningTask);
        final outputPath = savePlanImage == null
            ? await saveImage(bytes, fileName)
            : await savePlanImage!(
                bytes,
                fileName,
                plan.id,
                plan.executionSettings?.outputDirectory,
              );
        final completedAt = now();
        final completedTask = runningTask.copyWith(
          status: ProductionTaskStatus.completed,
          outputImagePath: outputPath,
          updatedAt: completedAt,
          completedAt: completedAt,
          clearError: true,
        );
        await onTaskUpdate?.call(completedTask);
        return completedTask;
      } catch (error) {
        final failedAt = now();
        final canRetry = attempt < effectiveMaxRetries ||
            retryIndefinitely && _allowsInfiniteRetry(error);
        final shouldKeepGoing = shouldContinue == null || shouldContinue();
        final shouldRetry = canRetry && shouldKeepGoing;
        currentTask = runningTask.copyWith(
          status: canRetry
              ? ProductionTaskStatus.queued
              : ProductionTaskStatus.failed,
          error: error.toString(),
          updatedAt: failedAt,
          completedAt: failedAt,
        );
        await onTaskUpdate?.call(currentTask);
        if (!shouldRetry) {
          return currentTask;
        }
      }
    }
    return currentTask;
  }

  bool _allowsInfiniteRetry(Object error) {
    if (error is! ProductionNaiApiException) {
      return true;
    }
    return error.statusCode == 429;
  }

  ProductionTask _taskWithExecutionSeed(
    ProductionPlan plan,
    ProductionTask task,
  ) {
    final settings = plan.executionSettings;
    if (settings == null || settings.useOriginalSeed) {
      return task;
    }
    final configuredSeed = settings.seed;
    final seed = configuredSeed == null ||
            configuredSeed < 0 ||
            configuredSeed >= _seedMaxExclusive
        ? randomInt(_seedMaxExclusive)
        : configuredSeed;
    final payload = _payloadWithSeed(task.payload, seed);
    return task.copyWith(payload: payload);
  }

  Future<List<ProductionPlan>> _loadPlans() {
    final service = queueService;
    if (service == null) {
      throw StateError('A ProductionQueueService is required for this action.');
    }
    return service.loadPlans();
  }

  Future<void> _saveUpdatedPlan(
    List<ProductionPlan> plans,
    ProductionPlan updatedPlan,
  ) {
    final service = queueService;
    if (service == null) {
      throw StateError('A ProductionQueueService is required for this action.');
    }
    return service.savePlans(
      plans
          .map((plan) => plan.id == updatedPlan.id ? updatedPlan : plan)
          .toList(growable: false),
    );
  }

  ProductionPlan _findPlan(List<ProductionPlan> plans, String planId) {
    return plans.firstWhere(
      (plan) => plan.id == planId,
      orElse: () => throw StateError('Production plan $planId was not found.'),
    );
  }

  String _outputFileName(ProductionTask task) {
    final suggested = task.suggestedFileName;
    if (suggested != null && suggested.isNotEmpty) {
      return suggested;
    }
    return '${task.id}.png';
  }
}

Map<String, dynamic> _payloadWithSeed(Map<String, dynamic> payload, int seed) {
  final parameters = _mapValue(payload['parameters']);
  return <String, dynamic>{
    ...payload,
    'parameters': <String, dynamic>{
      ...parameters,
      'seed': seed,
    },
  };
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, child) => MapEntry(key.toString(), child));
  }
  return const {};
}

bool _isAbnormalTask(ProductionTask task) {
  return task.status == ProductionTaskStatus.failed ||
      (task.error?.trim().isNotEmpty ?? false);
}

const _seedMaxExclusive = 1 << 32;
