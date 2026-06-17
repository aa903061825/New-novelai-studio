import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_executor_service.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_payload_adapter.dart';

typedef ProductionTaskJsonExporter = Future<bool> Function(
  String content,
  String fileName,
);
typedef ProductionKnowledgeBaseLoader = Future<Map<String, dynamic>> Function();
typedef ProductionKnowledgeBaseSaver = Future<void> Function(
  Map<String, dynamic> knowledgeBase,
);
typedef ProductionClock = DateTime Function();
typedef ProductionDirectoryPicker = Future<String?> Function();

class ProductionQueueExecutionSettings {
  final String model;
  final String sampler;
  final int? steps;
  final double? scale;
  final int? width;
  final int? height;
  final int? seed;
  final String tokenReference;
  final int requestIntervalSeconds;
  final int requestIntervalRandomRangeSeconds;
  final int retryCount;
  final bool retryIndefinitely;
  final String outputDirectory;
  final bool useOriginalGenerationSettings;
  final bool useOriginalSeed;

  const ProductionQueueExecutionSettings({
    this.model = '',
    this.sampler = '',
    this.steps,
    this.scale,
    this.width,
    this.height,
    this.seed = _randomSeedSentinel,
    this.tokenReference = 'unset',
    this.requestIntervalSeconds = 0,
    this.requestIntervalRandomRangeSeconds = 0,
    this.retryCount = 0,
    this.retryIndefinitely = false,
    this.outputDirectory = '',
    this.useOriginalGenerationSettings = false,
    this.useOriginalSeed = false,
  });
}

class ProductionQueueViewModel extends ChangeNotifier {
  List<ProductionPlan> _plans;
  final ProductionQueueExecutionSettings settings;
  final ProductionQueueService? queueService;
  final ProductionExecutorService? executorService;
  final ProductionTaskJsonExporter exporter;
  final ProductionKnowledgeBaseLoader? loadRecastKnowledgeBase;
  final ProductionKnowledgeBaseSaver? saveRecastKnowledgeBase;
  final ProductionDirectoryPicker? pickOutputDirectoryPath;
  final ProductionClock now;
  ProductionTask? _selectedTask;
  bool _isExecuting = false;
  bool _pauseRequested = false;
  bool _isPaused = false;
  late bool _useOriginalModel;
  late bool _useOriginalSize;
  late bool _useOriginalSampler;
  late bool _useOriginalSteps;
  late bool _useOriginalScale;
  late bool _useOriginalSeed;
  late String _model;
  late String _sampler;
  late int? _steps;
  late double? _scale;
  late int? _width;
  late int? _height;
  late int? _seed;
  late int _requestIntervalSeconds;
  late int _requestIntervalRandomRangeSeconds;
  late int _retryCount;
  late bool _retryIndefinitely;
  late String _outputDirectory;
  int _executionEpoch = 0;
  Future<void> _executionSettingsSaveQueue = Future<void>.value();

  ProductionQueueViewModel({
    required List<ProductionPlan> plans,
    this.settings = const ProductionQueueExecutionSettings(),
    this.queueService,
    this.executorService,
    this.loadRecastKnowledgeBase,
    this.saveRecastKnowledgeBase,
    ProductionDirectoryPicker? pickOutputDirectory,
    ProductionTaskJsonExporter? exporter,
    ProductionClock? now,
  })  : _plans = List.unmodifiable(plans),
        pickOutputDirectoryPath = pickOutputDirectory,
        exporter = exporter ?? _defaultExporter,
        now = now ?? (() => DateTime.now().toUtc()) {
    _applyInitialExecutionSettings(_initialPlanExecutionSettings(_plans));
    _selectedTask = plans.isEmpty || plans.first.tasks.isEmpty
        ? null
        : plans.first.tasks.first;
  }

  factory ProductionQueueViewModel.empty() {
    final now = DateTime.now().toUtc();
    return ProductionQueueViewModel(
      plans: [
        ProductionPlan(
          id: 'empty-production-queue',
          name: 'Deterministic Queue',
          tasks: const [],
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }

  ProductionPlan? get selectedPlan => plans.isEmpty ? null : plans.first;

  List<ProductionPlan> get plans => _plans;

  ProductionTask? get selectedTask => _selectedTask;

  int get totalTasks => selectedPlan?.tasks.length ?? 0;

  int get completedTasks => _count(ProductionTaskStatus.completed);

  int get failedTasks => _count(ProductionTaskStatus.failed);

  int get abnormalTasks =>
      selectedPlan?.tasks.where(_isAbnormalTask).length ?? 0;

  int get runningTasks => _count(ProductionTaskStatus.running);

  bool get hasFailedTasks => failedTasks > 0;

  bool get hasAbnormalTasks => abnormalTasks > 0;

  bool get isExecuting => _isExecuting;

  bool get pauseRequested => _pauseRequested;

  bool get isPaused => _isPaused;

  bool get canStop => _isExecuting || _isPaused;

  bool get canPause => _isExecuting && !_pauseRequested;

  bool get canResume =>
      !_isExecuting &&
      selectedPlan != null &&
      selectedPlan!.tasks
          .any((task) => task.status == ProductionTaskStatus.queued) &&
      (_isPaused || _hasRestoredUnfinishedWork(selectedPlan!));

  bool get canClearCurrentPlan => !_isExecuting && totalTasks > 0;

  bool get canRenameSelectedPlan => !_isExecuting && selectedPlan != null;

  bool get useOriginalGenerationSettings =>
      _useOriginalModel &&
      _useOriginalSize &&
      _useOriginalSampler &&
      _useOriginalSteps &&
      _useOriginalScale &&
      _useOriginalSeed;

  bool get useOriginalModel => _useOriginalModel;

  bool get useOriginalSize => _useOriginalSize;

  bool get useOriginalSampler => _useOriginalSampler;

  bool get useOriginalSteps => _useOriginalSteps;

  bool get useOriginalScale => _useOriginalScale;

  bool get useOriginalSeed => _useOriginalSeed;

  String get batchModel => _model;

  String get batchSampler => _sampler;

  int? get batchSteps => _steps;

  double? get batchScale => _scale;

  int? get batchWidth => _width;

  int? get batchHeight => _height;

  int? get batchSeed => _seed;

  int get requestIntervalSeconds => _requestIntervalSeconds;

  int get requestIntervalRandomRangeSeconds =>
      _requestIntervalRandomRangeSeconds;

  int get retryCount => _retryCount;

  bool get retryIndefinitely => _retryIndefinitely;

  String get outputDirectory => _outputDirectory;

  bool get canPickOutputDirectory => pickOutputDirectoryPath != null;

  void selectTask(ProductionTask task) {
    _selectedTask = task;
    notifyListeners();
  }

  void setUseOriginalGenerationSettings(bool value) {
    if (_useOriginalModel == value &&
        _useOriginalSize == value &&
        _useOriginalSampler == value &&
        _useOriginalSteps == value &&
        _useOriginalScale == value &&
        _useOriginalSeed == value) {
      return;
    }
    _useOriginalModel = value;
    _useOriginalSize = value;
    _useOriginalSampler = value;
    _useOriginalSteps = value;
    _useOriginalScale = value;
    _useOriginalSeed = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalModel(bool value) {
    if (_useOriginalModel == value) return;
    _useOriginalModel = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalSize(bool value) {
    if (_useOriginalSize == value) return;
    _useOriginalSize = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalSampler(bool value) {
    if (_useOriginalSampler == value) return;
    _useOriginalSampler = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalSteps(bool value) {
    if (_useOriginalSteps == value) return;
    _useOriginalSteps = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalScale(bool value) {
    if (_useOriginalScale == value) return;
    _useOriginalScale = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalSeed(bool value) {
    if (_useOriginalSeed == value) return;
    _useOriginalSeed = value;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchModel(String value) {
    final next = value.trim();
    if (_model == next) return;
    _model = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchSampler(String value) {
    final next = value.trim();
    if (_sampler == next) return;
    _sampler = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchWidthText(String value) {
    final next = _parsePositiveInt(value);
    if (_width == next) return;
    _width = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchHeightText(String value) {
    final next = _parsePositiveInt(value);
    if (_height == next) return;
    _height = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchStepsText(String value) {
    final next = _parsePositiveInt(value);
    if (_steps == next) return;
    _steps = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchScaleText(String value) {
    final next = _parsePositiveDouble(value);
    if (_scale == next) return;
    _scale = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchSeedText(String value) {
    final next = _parseSeed(value);
    if (_seed == next) return;
    _seed = next;
    _notifyAndPersistExecutionSettings();
  }

  void setRequestIntervalSecondsText(String value) {
    final next = _parseNonNegativeInt(value);
    if (_requestIntervalSeconds == next) return;
    _requestIntervalSeconds = next;
    _notifyAndPersistExecutionSettings();
  }

  void setRequestIntervalRandomRangeText(String value) {
    final next = _parseNonNegativeInt(value);
    if (_requestIntervalRandomRangeSeconds == next) return;
    _requestIntervalRandomRangeSeconds = next;
    _notifyAndPersistExecutionSettings();
  }

  void setRetryCountText(String value) {
    final next = _parsePositiveInt(value) ?? 1;
    if (_retryCount == next) return;
    _retryCount = next;
    _notifyAndPersistExecutionSettings();
  }

  void setRetryIndefinitely(bool value) {
    if (_retryIndefinitely == value) return;
    _retryIndefinitely = value;
    _notifyAndPersistExecutionSettings();
  }

  void setOutputDirectory(String value) {
    final next = value.trim();
    if (_outputDirectory == next) return;
    _outputDirectory = next;
    _notifyAndPersistExecutionSettings();
  }

  Future<void> pickOutputDirectory() async {
    final picker = pickOutputDirectoryPath;
    if (picker == null) return;
    final picked = await picker();
    if (picked == null) return;
    setOutputDirectory(picked);
  }

  Future<void> renameSelectedPlan(String label) async {
    final plan = selectedPlan;
    final next = label.trim();
    if (plan == null || next.isEmpty || _isExecuting || plan.name == next) {
      return;
    }
    final renamedAt = now().toUtc();
    final renamedPlan = _renamePlanIdentity(
      plan,
      next,
      existingPlanIds: plans.map((plan) => plan.id),
      updatedAt: renamedAt,
    );
    final selectedTaskId = _renamedTaskIdFor(
      renamedPlan,
      previousTaskId: _selectedTask?.id,
    );
    await _replacePlan(
      previousPlanId: plan.id,
      updatedPlan: renamedPlan,
      selectedTaskId: selectedTaskId,
    );
    notifyListeners();
  }

  Future<void> load() async {
    final service = queueService;
    if (service == null) return;
    final lastUsedSettings = await service.loadLastExecutionSettings();
    _setPlans(
      await service.loadPlans(),
      fallbackExecutionSettings: lastUsedSettings,
    );
    notifyListeners();
  }

  Future<void> start() async {
    final plan = selectedPlan;
    final executor = executorService;
    if (plan == null || executor == null || _isExecuting) return;

    final runEpoch = ++_executionEpoch;
    _isExecuting = true;
    _pauseRequested = false;
    _isPaused = false;
    notifyListeners();
    var hasRunPreviousTask = false;
    try {
      while (_executionEpoch == runEpoch && !_pauseRequested) {
        final currentPlan = selectedPlan;
        if (currentPlan == null) break;
        final nextTask = _nextQueuedTask(currentPlan);
        if (nextTask == null) break;
        if (hasRunPreviousTask) {
          await _waitForNextRequestInterval(executor);
        }
        if (_executionEpoch != runEpoch || _pauseRequested) break;
        final executionPlan = _executionPlanForTask(currentPlan, nextTask);
        try {
          await executor.rerunTaskInPlan(
            executionPlan,
            taskId: nextTask.id,
            maxRetries: _maxRetries,
            retryIndefinitely: _retryIndefinitely,
            onTaskUpdate: (task) {
              if (_executionEpoch != runEpoch) return Future<void>.value();
              return _replaceTaskInPlan(executionPlan.id, task);
            },
            shouldContinue: () =>
                _executionEpoch == runEpoch && !_pauseRequested,
          );
        } catch (error) {
          if (_executionEpoch != runEpoch) return;
          await _replaceTaskInPlan(
            currentPlan.id,
            _unexpectedFailureTask(nextTask, error),
          );
        }
        hasRunPreviousTask = true;
      }
      if (_executionEpoch != runEpoch) return;
      final updatedPlan = selectedPlan;
      _isPaused = _pauseRequested &&
          (updatedPlan?.tasks.any(
                (task) => task.status == ProductionTaskStatus.queued,
              ) ??
              false);
    } finally {
      if (_executionEpoch == runEpoch) {
        _isExecuting = false;
        _pauseRequested = false;
        notifyListeners();
      }
    }
  }

  void pause() {
    if (!canPause) return;
    _pauseRequested = true;
    notifyListeners();
  }

  Future<void> stop() async {
    if (!canStop) return;
    _executionEpoch += 1;
    _isExecuting = false;
    _pauseRequested = false;
    _isPaused = false;
    final plan = selectedPlan;
    if (plan == null) {
      notifyListeners();
      return;
    }
    final stoppedAt = now().toUtc();
    final resetTasks = [
      for (final task in plan.tasks) _resetTaskForRestart(task, stoppedAt),
    ];
    final updatedPlan = plan.copyWith(
      tasks: resetTasks,
      updatedAt: stoppedAt,
    );
    await _saveUpdatedPlan(
      updatedPlan,
      selectedTaskId: resetTasks.isEmpty ? null : resetTasks.first.id,
    );
    notifyListeners();
  }

  Future<void> resume() async {
    if (!canResume) return;
    _isPaused = false;
    notifyListeners();
    await start();
  }

  Future<void> retryFailed() async {
    await rerunAbnormalTasks();
  }

  Future<void> rerunAbnormalTasks() async {
    final plan = selectedPlan;
    final executor = executorService;
    if (plan == null || executor == null || _isExecuting) return;

    final runEpoch = ++_executionEpoch;
    _isExecuting = true;
    _pauseRequested = false;
    _isPaused = false;
    notifyListeners();
    try {
      final executionPlan = _executionPlan(plan);
      final result = await executor.rerunAbnormalTasksInPlan(
        executionPlan,
        maxRetries: _maxRetries,
        retryIndefinitely: _retryIndefinitely,
        onTaskUpdate: (updatedTask) {
          if (_executionEpoch != runEpoch) return Future<void>.value();
          return _replaceTaskInPlan(executionPlan.id, updatedTask);
        },
        shouldContinue: () => _executionEpoch == runEpoch && !_pauseRequested,
      );
      if (_executionEpoch != runEpoch) return;
      await _saveUpdatedPlan(
        result.plan,
        selectedTaskId: result.changedTaskIds.isEmpty
            ? _selectedTask?.id
            : result.changedTaskIds.first,
      );
    } finally {
      if (_executionEpoch == runEpoch) {
        _isExecuting = false;
        _pauseRequested = false;
        _isPaused = false;
        notifyListeners();
      }
    }
  }

  Future<void> clearCurrentPlan() async {
    final plan = selectedPlan;
    if (plan == null || _isExecuting || plan.tasks.isEmpty) return;
    _pauseRequested = false;
    _isPaused = false;
    final updatedPlan = plan.copyWith(
      tasks: const [],
      updatedAt: now().toUtc(),
    );
    await _saveUpdatedPlan(updatedPlan);
    _selectedTask = null;
    notifyListeners();
  }

  Future<ProductionTask?> queueRerunTask(ProductionTask task) async {
    final plan = selectedPlan;
    if (plan == null || plan.tasks.isEmpty) return null;
    final sourceTask = plan.tasks.firstWhere(
      (candidate) => candidate.id == task.id,
      orElse: () => task,
    );
    final queuedAt = now().toUtc();
    final taskIds = plan.tasks.map((task) => task.id).toSet();
    final rerunTaskId = _uniqueRerunTaskId(sourceTask.id, taskIds);
    final rerunTask = sourceTask.copyWith(
      id: rerunTaskId,
      planId: plan.id,
      suggestedFileName: '$rerunTaskId.png',
      status: ProductionTaskStatus.queued,
      attempts: 0,
      createdAt: queuedAt,
      updatedAt: queuedAt,
      clearOutputImagePath: true,
      clearError: true,
      clearStartedAt: true,
      clearCompletedAt: true,
      clearRating: true,
      clearRatedAt: true,
    );
    final insertionIndex = _quickRerunInsertionIndex(plan, sourceTask.id);
    final tasks = [...plan.tasks]..insert(insertionIndex, rerunTask);
    await _saveUpdatedPlan(
      plan.copyWith(tasks: tasks, updatedAt: queuedAt),
      selectedTaskId: rerunTask.id,
    );
    notifyListeners();
    return rerunTask;
  }

  Future<void> rerunTask(ProductionTask task) async {
    final plan = selectedPlan;
    final executor = executorService;
    if (plan == null ||
        executor == null ||
        task.taskType != ProductionTaskType.scriptRecastFrame ||
        _isExecuting) {
      _selectedTask = task;
      notifyListeners();
      return;
    }

    final runEpoch = ++_executionEpoch;
    _selectedTask = task;
    _isExecuting = true;
    _pauseRequested = false;
    _isPaused = false;
    notifyListeners();
    try {
      final executionPlan = _executionPlan(plan);
      final result = await executor.rerunTaskInPlan(
        executionPlan,
        taskId: task.id,
        maxRetries: _maxRetries,
        retryIndefinitely: _retryIndefinitely,
        onTaskUpdate: (updatedTask) {
          if (_executionEpoch != runEpoch) return Future<void>.value();
          return _replaceTaskInPlan(executionPlan.id, updatedTask);
        },
        shouldContinue: () => _executionEpoch == runEpoch && !_pauseRequested,
      );
      if (_executionEpoch != runEpoch) return;
      await _saveUpdatedPlan(result.plan, selectedTaskId: task.id);
    } catch (error) {
      if (_executionEpoch != runEpoch) return;
      await _replaceTaskInPlan(
        plan.id,
        _unexpectedFailureTask(task, error),
      );
    } finally {
      if (_executionEpoch == runEpoch) {
        _isExecuting = false;
        _pauseRequested = false;
        _isPaused = false;
        notifyListeners();
      }
    }
  }

  Future<bool> exportSelectedTaskJson() async {
    final task = selectedTask;
    if (task == null) return false;
    const encoder = JsonEncoder.withIndent('  ');
    final exported = await exporter(
      '${encoder.convert(task.payload)}\n',
      '${task.id}-payload.json',
    );
    notifyListeners();
    return exported;
  }

  Future<void> rateTask(ProductionTask task, int rating) async {
    RangeError.checkValueInInterval(rating, 1, 5, 'rating');
    final ratedAt = now().toUtc();
    final ratedTask = task.copyWith(
      rating: rating,
      ratedAt: ratedAt,
      updatedAt: ratedAt,
    );
    await _replaceTaskInPlan(task.planId, ratedTask);
    if (rating >= 4) {
      await _saveHighRatedProductionSample(ratedTask);
    }
  }

  int _count(ProductionTaskStatus status) {
    return selectedPlan?.tasks.where((task) => task.status == status).length ??
        0;
  }

  bool _isAbnormalTask(ProductionTask task) {
    return task.status == ProductionTaskStatus.failed ||
        (task.error?.trim().isNotEmpty ?? false);
  }

  ProductionTask? _nextQueuedTask(ProductionPlan plan) {
    for (final task in plan.tasks) {
      if (task.status == ProductionTaskStatus.queued) {
        return task;
      }
    }
    return null;
  }

  Future<void> _waitForNextRequestInterval(
    ProductionExecutorService executor,
  ) async {
    final baseInterval = Duration(seconds: _requestIntervalSeconds);
    final randomRangeSeconds = _requestIntervalRandomRangeSeconds;
    final jitterSeconds = randomRangeSeconds <= 0
        ? 0
        : executor.randomInt(randomRangeSeconds + 1).clamp(
              0,
              randomRangeSeconds,
            );
    final delay = baseInterval + Duration(seconds: jitterSeconds.toInt());
    if (delay.inMicroseconds <= 0) return;
    await executor.delay(delay);
  }

  int _quickRerunInsertionIndex(ProductionPlan plan, String sourceTaskId) {
    final runningIndex = plan.tasks.indexWhere(
      (task) => task.status == ProductionTaskStatus.running,
    );
    if (runningIndex >= 0) return runningIndex + 1;
    final queuedIndex = plan.tasks.indexWhere(
      (task) => task.status == ProductionTaskStatus.queued,
    );
    if (queuedIndex >= 0) return queuedIndex;
    final sourceIndex =
        plan.tasks.indexWhere((task) => task.id == sourceTaskId);
    return sourceIndex < 0 ? plan.tasks.length : sourceIndex + 1;
  }

  ProductionTask _resetTaskForRestart(ProductionTask task, DateTime resetAt) {
    return task.copyWith(
      status: ProductionTaskStatus.queued,
      attempts: 0,
      updatedAt: resetAt,
      clearOutputImagePath: true,
      clearError: true,
      clearStartedAt: true,
      clearCompletedAt: true,
      clearRating: true,
      clearRatedAt: true,
    );
  }

  ProductionPlan _executionPlanForTask(
    ProductionPlan plan,
    ProductionTask task,
  ) {
    final executionTask = _executionTask(task);
    return plan.copyWith(
      executionSettings: _currentExecutionSettings(),
      tasks: [
        for (final existingTask in plan.tasks)
          existingTask.id == task.id ? executionTask : existingTask,
      ],
    );
  }

  ProductionTask _executionTask(ProductionTask task) {
    final normalizedTask = _normalizeTaskPayload(task);
    if (useOriginalGenerationSettings) return normalizedTask;
    return normalizedTask.copyWith(
      payload: _configuredPayload(_normalizedPayload(task)),
    );
  }

  ProductionPlan _executionPlan(ProductionPlan plan) {
    final planWithSettings = plan.copyWith(
      executionSettings: _currentExecutionSettings(),
      tasks: [
        for (final task in plan.tasks) _normalizeTaskPayload(task),
      ],
    );
    if (useOriginalGenerationSettings) return planWithSettings;
    return planWithSettings.copyWith(
      tasks: [
        for (final task in plan.tasks)
          task.copyWith(payload: _configuredPayload(_normalizedPayload(task))),
      ],
    );
  }

  ProductionTask _normalizeTaskPayload(ProductionTask task) {
    if (task.taskType != ProductionTaskType.scriptRecastFrame) {
      return task;
    }
    return task.copyWith(payload: _normalizedPayload(task));
  }

  Map<String, dynamic> _normalizedPayload(ProductionTask task) {
    if (task.taskType != ProductionTaskType.scriptRecastFrame) {
      return task.payload;
    }
    return const ScriptRecastPayloadAdapter().toNaiRequestPayload(task.payload);
  }

  Map<String, dynamic> _configuredPayload(Map<String, dynamic> payload) {
    final parameters = _mapValue(payload['parameters']);
    final nextParameters = <String, dynamic>{
      ...parameters,
      if (!_useOriginalSize && _width != null) 'width': _width,
      if (!_useOriginalSize && _height != null) 'height': _height,
      if (!_useOriginalSteps && _steps != null) 'steps': _steps,
      if (!_useOriginalScale && _scale != null) 'scale': _scale,
      if (!_useOriginalSampler && _sampler.trim().isNotEmpty)
        'sampler': _sampler.trim(),
    };
    return <String, dynamic>{
      ...payload,
      if (!_useOriginalModel && _model.trim().isNotEmpty)
        'model': _model.trim(),
      'parameters': nextParameters,
    };
  }

  int get _maxRetries => _retryCount <= 0 ? 1 : _retryCount;

  ProductionTask _unexpectedFailureTask(ProductionTask task, Object error) {
    final failedAt = now().toUtc();
    return task.copyWith(
      status: ProductionTaskStatus.failed,
      attempts: task.attempts + 1,
      error: error.toString(),
      updatedAt: failedAt,
      completedAt: failedAt,
      clearStartedAt: true,
    );
  }

  Future<void> _saveUpdatedPlan(
    ProductionPlan updatedPlan, {
    String? selectedTaskId,
    bool preserveCurrentExecutionSettings = false,
  }) async {
    return _replacePlan(
      previousPlanId: updatedPlan.id,
      updatedPlan: updatedPlan,
      selectedTaskId: selectedTaskId,
      preserveCurrentExecutionSettings: preserveCurrentExecutionSettings,
    );
  }

  Future<void> _replacePlan({
    required String previousPlanId,
    required ProductionPlan updatedPlan,
    String? selectedTaskId,
    bool preserveCurrentExecutionSettings = false,
  }) async {
    final nextPlans = plans
        .map((plan) => plan.id == previousPlanId ? updatedPlan : plan)
        .toList(growable: false);
    final service = queueService;
    if (service != null) {
      await service.savePlans(nextPlans);
    }
    _setPlans(
      nextPlans,
      selectedTaskId: selectedTaskId,
      preserveCurrentExecutionSettings: preserveCurrentExecutionSettings,
    );
  }

  Future<void> _replaceTaskInPlan(String planId, ProductionTask task) async {
    final nextPlans = [
      for (final plan in plans)
        if (plan.id == planId)
          plan.copyWith(
            tasks: [
              for (final existingTask in plan.tasks)
                existingTask.id == task.id ? task : existingTask,
            ],
            updatedAt: now().toUtc(),
          )
        else
          plan,
    ];
    _setPlans(nextPlans, selectedTaskId: task.id);
    notifyListeners();
    final service = queueService;
    if (service != null) {
      await service.savePlans(nextPlans);
    }
  }

  void _setPlans(
    List<ProductionPlan> nextPlans, {
    String? selectedTaskId,
    ProductionPlanExecutionSettings? fallbackExecutionSettings,
    bool preserveCurrentExecutionSettings = false,
  }) {
    final previousSelectedTaskId = selectedTaskId ?? _selectedTask?.id;
    final normalizedPlans =
        _isExecuting ? nextPlans : _normalizeIdleRunningTasks(nextPlans);
    _plans = List.unmodifiable(normalizedPlans);
    _selectedTask = _findTask(previousSelectedTaskId) ??
        (plans.isEmpty || plans.first.tasks.isEmpty
            ? null
            : plans.first.tasks.first);
    if (!_isExecuting && !preserveCurrentExecutionSettings) {
      final planSettings = _initialPlanExecutionSettings(
        plans,
        fallbackExecutionSettings: fallbackExecutionSettings,
      );
      if (planSettings != null) {
        _applyPlanExecutionSettings(planSettings);
      }
    }
    if (!_isExecuting && !_pauseRequested) {
      final plan = selectedPlan;
      _isPaused = plan != null && _hasRestoredUnfinishedWork(plan);
    }
  }

  List<ProductionPlan> _normalizeIdleRunningTasks(List<ProductionPlan> plans) {
    return [
      for (final plan in plans)
        if (plan.tasks
            .any((task) => task.status == ProductionTaskStatus.running))
          plan.copyWith(
            tasks: [
              for (final task in plan.tasks)
                task.status == ProductionTaskStatus.running
                    ? task.copyWith(
                        status: ProductionTaskStatus.queued,
                        updatedAt: now().toUtc(),
                        clearCompletedAt: true,
                      )
                    : task,
            ],
            updatedAt: now().toUtc(),
          )
        else
          plan,
    ];
  }

  bool _hasRestoredUnfinishedWork(ProductionPlan plan) {
    final hasQueued =
        plan.tasks.any((task) => task.status == ProductionTaskStatus.queued);
    if (!hasQueued) return false;
    return plan.tasks.any(_hasPriorRunEvidence);
  }

  bool _hasPriorRunEvidence(ProductionTask task) {
    return task.status == ProductionTaskStatus.completed ||
        task.status == ProductionTaskStatus.failed ||
        task.status == ProductionTaskStatus.running ||
        task.status == ProductionTaskStatus.skipped ||
        task.attempts > 0 ||
        task.outputImagePath != null ||
        (task.error?.trim().isNotEmpty ?? false) ||
        task.startedAt != null ||
        task.completedAt != null;
  }

  ProductionTask? _findTask(String? taskId) {
    if (taskId == null) return null;
    for (final plan in plans) {
      for (final task in plan.tasks) {
        if (task.id == taskId) return task;
      }
    }
    return null;
  }

  Future<void> _saveHighRatedProductionSample(ProductionTask task) async {
    final loader = loadRecastKnowledgeBase;
    final saver = saveRecastKnowledgeBase;
    if (loader == null || saver == null) {
      return;
    }
    final current = await loader();
    final next = Map<String, dynamic>.from(current);
    final samples = Map<String, dynamic>.from(
      next['productionSamples'] as Map? ?? const <String, dynamic>{},
    );
    samples[task.id] = {
      'taskId': task.id,
      'planId': task.planId,
      'taskType': task.taskType.name,
      'title': task.title,
      'rating': task.rating,
      if (task.ratedAt != null)
        'ratedAt': task.ratedAt!.toUtc().toIso8601String(),
      'scriptId': task.source.scriptId,
      'scriptName': task.source.scriptName,
      'scriptPath': task.source.scriptPath,
      'recastRunId': task.source.recastRunId,
      'frameIndex': task.source.frameIndex,
      'sourceFileName': task.source.sourceFileName,
      'payloadFingerprint': task.payloadFingerprint,
      'outputImagePath': task.outputImagePath,
      'payload': task.payload,
    }..removeWhere((_, value) => value == null);
    next['productionSamples'] = samples;
    await saver(next);
  }

  void _applyInitialExecutionSettings(
    ProductionPlanExecutionSettings? planSettings,
  ) {
    if (planSettings == null) {
      _useOriginalModel = settings.useOriginalGenerationSettings;
      _useOriginalSize = settings.useOriginalGenerationSettings;
      _useOriginalSampler = settings.useOriginalGenerationSettings;
      _useOriginalSteps = settings.useOriginalGenerationSettings;
      _useOriginalScale = settings.useOriginalGenerationSettings;
      _useOriginalSeed =
          settings.useOriginalGenerationSettings || settings.useOriginalSeed;
      _model = settings.model;
      _sampler = settings.sampler;
      _steps = settings.steps;
      _scale = settings.scale;
      _width = settings.width;
      _height = settings.height;
      _seed = _normalizeSeed(settings.seed);
      _requestIntervalSeconds =
          _nonNegativeInt(settings.requestIntervalSeconds);
      _requestIntervalRandomRangeSeconds =
          _nonNegativeInt(settings.requestIntervalRandomRangeSeconds);
      _retryCount = _positiveIntOrOne(settings.retryCount);
      _retryIndefinitely = settings.retryIndefinitely;
      _outputDirectory = settings.outputDirectory;
      return;
    }
    _applyPlanExecutionSettings(planSettings);
  }

  void _applyPlanExecutionSettings(
    ProductionPlanExecutionSettings planSettings,
  ) {
    _useOriginalModel = planSettings.useOriginalModel;
    _useOriginalSize = planSettings.useOriginalSize;
    _useOriginalSampler = planSettings.useOriginalSampler;
    _useOriginalSteps = planSettings.useOriginalSteps;
    _useOriginalScale = planSettings.useOriginalScale;
    _useOriginalSeed = planSettings.useOriginalSeed;
    _model = planSettings.model;
    _sampler = planSettings.sampler;
    _steps = planSettings.steps;
    _scale = planSettings.scale;
    _width = planSettings.width;
    _height = planSettings.height;
    _seed = _normalizeSeed(planSettings.seed);
    _requestIntervalSeconds =
        _nonNegativeInt(planSettings.requestIntervalSeconds);
    _requestIntervalRandomRangeSeconds =
        _nonNegativeInt(planSettings.requestIntervalRandomRangeSeconds);
    _retryCount = _positiveIntOrOne(planSettings.retryCount);
    _retryIndefinitely = planSettings.retryIndefinitely;
    _outputDirectory = planSettings.outputDirectory;
  }

  ProductionPlanExecutionSettings _currentExecutionSettings() {
    return ProductionPlanExecutionSettings(
      model: _model,
      sampler: _sampler,
      steps: _steps,
      scale: _scale,
      width: _width,
      height: _height,
      seed: _normalizeSeed(_seed),
      useOriginalModel: _useOriginalModel,
      useOriginalSize: _useOriginalSize,
      useOriginalSampler: _useOriginalSampler,
      useOriginalSteps: _useOriginalSteps,
      useOriginalScale: _useOriginalScale,
      useOriginalSeed: _useOriginalSeed,
      requestIntervalSeconds: _requestIntervalSeconds,
      requestIntervalRandomRangeSeconds: _requestIntervalRandomRangeSeconds,
      retryCount: _retryCount,
      retryIndefinitely: _retryIndefinitely,
      outputDirectory: _outputDirectory,
    );
  }

  void _notifyAndPersistExecutionSettings() {
    notifyListeners();
    _executionSettingsSaveQueue = _executionSettingsSaveQueue
        .catchError((_) {})
        .then((_) => _persistExecutionSettings());
    unawaited(_executionSettingsSaveQueue);
  }

  Future<void> _persistExecutionSettings() async {
    final service = queueService;
    final currentSettings = _currentExecutionSettings();
    if (service != null) {
      await service.saveLastExecutionSettings(currentSettings);
    }
    final plan = selectedPlan;
    if (plan == null) return;
    if (_isExecuting) {
      final updatedAt = now().toUtc();
      final nextPlans = [
        for (final existingPlan in plans)
          existingPlan.id == plan.id
              ? existingPlan.copyWith(
                  executionSettings: currentSettings,
                  updatedAt: updatedAt,
                )
              : existingPlan,
      ];
      _setPlans(nextPlans, selectedTaskId: _selectedTask?.id);
      return;
    }
    await _saveUpdatedPlan(
      plan.copyWith(
        executionSettings: currentSettings,
        updatedAt: now().toUtc(),
      ),
      selectedTaskId: _selectedTask?.id,
      preserveCurrentExecutionSettings: true,
    );
  }

  @visibleForTesting
  Future<void> flushPendingExecutionSettingsSaves() {
    return _executionSettingsSaveQueue;
  }
}

String _uniqueRerunTaskId(String sourceTaskId, Set<String> existingIds) {
  final baseId = '$sourceTaskId-rerun';
  if (!existingIds.contains(baseId)) return baseId;
  var suffix = 2;
  while (existingIds.contains('$baseId-$suffix')) {
    suffix += 1;
  }
  return '$baseId-$suffix';
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, child) => MapEntry(key.toString(), child));
  }
  return const {};
}

int? _parsePositiveInt(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

int _parseNonNegativeInt(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < 0) return 0;
  return parsed;
}

double? _parsePositiveDouble(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

int? _parseSeed(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return _randomSeedSentinel;
  final parsed = int.tryParse(trimmed);
  if (parsed == null ||
      parsed < _randomSeedSentinel ||
      parsed >= _seedMaxExclusive) {
    return _randomSeedSentinel;
  }
  return parsed;
}

int _normalizeSeed(int? value) {
  if (value == null ||
      value < _randomSeedSentinel ||
      value >= _seedMaxExclusive) {
    return _randomSeedSentinel;
  }
  return value;
}

const _randomSeedSentinel = -1;
const _seedMaxExclusive = 1 << 32;

ProductionPlanExecutionSettings? _initialPlanExecutionSettings(
  List<ProductionPlan> plans, {
  ProductionPlanExecutionSettings? fallbackExecutionSettings,
}) {
  return fallbackExecutionSettings ??
      _selectedPlanExecutionSettings(plans) ??
      _latestPlanExecutionSettings(plans);
}

ProductionPlanExecutionSettings? _selectedPlanExecutionSettings(
  List<ProductionPlan> plans,
) {
  if (plans.isEmpty) return null;
  return plans.first.executionSettings;
}

ProductionPlanExecutionSettings? _latestPlanExecutionSettings(
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

ProductionPlan _renamePlanIdentity(
  ProductionPlan plan,
  String label, {
  required Iterable<String> existingPlanIds,
  required DateTime updatedAt,
}) {
  final nextPlanId = _nonConflictingPlanId(
    _planIdForLabel(plan.id, label),
    existingPlanIds.where((id) => id != plan.id),
  );
  final renamedTasks = [
    for (var index = 0; index < plan.tasks.length; index += 1)
      _renameTaskForPlan(
        plan.tasks[index],
        planId: nextPlanId,
        fallbackIndex: index,
        updatedAt: updatedAt,
      ),
  ];
  return plan.copyWith(
    id: nextPlanId,
    name: label,
    tasks: renamedTasks,
    updatedAt: updatedAt,
  );
}

ProductionTask _renameTaskForPlan(
  ProductionTask task, {
  required String planId,
  required int fallbackIndex,
  required DateTime updatedAt,
}) {
  final source = task.source;
  final frameIndex = source.frameIndex;
  final nextTaskId = frameIndex == null
      ? '$planId:task-${fallbackIndex + 1}'
      : '$planId:frame-$frameIndex';
  return task.copyWith(
    id: nextTaskId,
    planId: planId,
    source: ProductionTaskSource(
      scriptId: source.scriptId,
      scriptName: source.scriptName,
      scriptPath: source.scriptPath,
      recastRunId: _renamedRecastRunId(source.recastRunId, planId),
      mappingConfigFingerprint: source.mappingConfigFingerprint,
      frameIndex: source.frameIndex,
      sourceFileName: source.sourceFileName,
    ),
    suggestedFileName: _suggestedPngNameForTask(
      planId: planId,
      task: task,
      fallbackTaskId: nextTaskId,
    ),
    updatedAt: updatedAt,
  );
}

String _planIdForLabel(String previousPlanId, String label) {
  final slug = _slug(label);
  if (previousPlanId.startsWith('script-recast-')) {
    return 'script-recast-$slug';
  }
  return '$previousPlanId-$slug';
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

String _renamedRecastRunId(String? previousRunId, String planId) {
  if (previousRunId == null || previousRunId.trim().isEmpty) {
    return '$planId-run';
  }
  return '$planId-run';
}

String _suggestedPngNameForTask({
  required String planId,
  required ProductionTask task,
  required String fallbackTaskId,
}) {
  final sourceFileName = task.source.sourceFileName?.trim();
  final baseName = sourceFileName == null || sourceFileName.isEmpty
      ? fallbackTaskId
      : sourceFileName.replaceFirst(
          RegExp(r'\.json$', caseSensitive: false),
          '',
        );
  return '${_safeFilePrefix(planId)}-$baseName.png';
}

String? _renamedTaskIdFor(
  ProductionPlan renamedPlan, {
  required String? previousTaskId,
}) {
  if (previousTaskId == null) return null;
  final frameMatch = RegExp(r':frame-(\d+)$').firstMatch(previousTaskId);
  if (frameMatch != null) {
    return '${renamedPlan.id}:frame-${frameMatch.group(1)}';
  }
  final taskMatch = RegExp(r':task-(\d+)$').firstMatch(previousTaskId);
  if (taskMatch != null) {
    return '${renamedPlan.id}:task-${taskMatch.group(1)}';
  }
  return renamedPlan.tasks.isEmpty ? null : renamedPlan.tasks.first.id;
}

String _slug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return slug.isEmpty ? 'renamed-queue' : slug;
}

String _safeFilePrefix(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? 'production-plan' : normalized;
}

int _nonNegativeInt(int value) {
  return value < 0 ? 0 : value;
}

int _positiveIntOrOne(int value) {
  return value <= 0 ? 1 : value;
}

Future<bool> _defaultExporter(String content, String fileName) {
  return FileService().saveStringToFile(content, fileName);
}
