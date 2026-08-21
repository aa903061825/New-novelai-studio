import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
typedef ProductionOutputImageDeleter = Future<bool> Function(String path);

class ProductionPlanDeletionResult {
  final bool deleted;
  final int deletedImageCount;
  final List<String> failedImagePaths;

  const ProductionPlanDeletionResult({
    required this.deleted,
    this.deletedImageCount = 0,
    this.failedImagePaths = const [],
  });
}

class _ProductionExecutionActivation {
  final ProductionPlan plan;
  final ProductionPlanExecutionSettings executionSettings;
  final int runEpoch;
  final ProductionPlan? planToPersist;
  final ProductionTask? runnableTask;

  const _ProductionExecutionActivation({
    required this.plan,
    required this.executionSettings,
    required this.runEpoch,
    this.planToPersist,
    this.runnableTask,
  });
}

class ProductionQueueExecutionSettings {
  final String model;
  final String sampler;
  final int? steps;
  final double? scale;
  final double? cfgRescale;
  final String noiseSchedule;
  final bool? sm;
  final bool? smDyn;
  final bool? dynamicThresholding;
  final bool? varietyPlus;
  final bool? autoPosition;
  final bool? legacyUc;
  final int? width;
  final int? height;
  final int? seed;
  final String tokenReference;
  final int requestIntervalSeconds;
  final int requestIntervalRandomRangeSeconds;
  final int retryCount;
  final bool retryIndefinitely;
  final int retryOn429DelaySeconds;
  final String outputDirectory;
  final bool useOriginalGenerationSettings;
  final bool useOriginalSeed;

  const ProductionQueueExecutionSettings({
    this.model = '',
    this.sampler = '',
    this.steps,
    this.scale,
    this.cfgRescale,
    this.noiseSchedule = '',
    this.sm,
    this.smDyn,
    this.dynamicThresholding,
    this.varietyPlus,
    this.autoPosition,
    this.legacyUc,
    this.width,
    this.height,
    this.seed = _randomSeedSentinel,
    this.tokenReference = 'unset',
    this.requestIntervalSeconds = 0,
    this.requestIntervalRandomRangeSeconds = 0,
    this.retryCount = 0,
    this.retryIndefinitely = false,
    this.retryOn429DelaySeconds = 10,
    this.outputDirectory = '',
    this.useOriginalGenerationSettings = false,
    this.useOriginalSeed = false,
  });
}

class _ProductionQueueTaskStats {
  static const empty = _ProductionQueueTaskStats(
    totalTasks: 0,
    completedTasks: 0,
    failedTasks: 0,
    abnormalTasks: 0,
    runningTasks: 0,
    queuedTasks: 0,
    hasRestoredUnfinishedWork: false,
  );

  final int totalTasks;
  final int completedTasks;
  final int failedTasks;
  final int abnormalTasks;
  final int runningTasks;
  final int queuedTasks;
  final bool hasRestoredUnfinishedWork;

  const _ProductionQueueTaskStats({
    required this.totalTasks,
    required this.completedTasks,
    required this.failedTasks,
    required this.abnormalTasks,
    required this.runningTasks,
    required this.queuedTasks,
    required this.hasRestoredUnfinishedWork,
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
  final ProductionOutputImageDeleter deleteOutputImage;
  final ProductionClock now;
  ProductionTask? _selectedTask;
  String? _selectedPlanId;
  String? _activePlanId;
  final Map<String, String> _selectedTaskIdsByPlanId = {};
  final Set<String> _pendingPlanDeletionIds = <String>{};
  final Set<String> _pendingExecutionActivationIds = <String>{};
  ProductionPlanExecutionSettings? _lastUsedExecutionSettings;
  bool _isExecuting = false;
  bool _pauseRequested = false;
  bool _isPaused = false;
  bool _clearCompletedTasksPending = false;
  ProductionPlan? _selectedPlanStatsPlan;
  _ProductionQueueTaskStats? _selectedPlanStats;
  late bool _useOriginalModel;
  late bool _useOriginalSize;
  late bool _useOriginalSampler;
  late bool _useOriginalSteps;
  late bool _useOriginalScale;
  late bool _useOriginalCfgRescale;
  late bool _useOriginalNoiseSchedule;
  late bool _useOriginalSm;
  late bool _useOriginalSmDyn;
  late bool _useOriginalDynamicThresholding;
  late bool _useOriginalVarietyPlus;
  late bool _useOriginalAutoPosition;
  late bool _useOriginalLegacyUc;
  late bool _useOriginalSeed;
  late String _model;
  late String _sampler;
  late int? _steps;
  late double? _scale;
  late double? _cfgRescale;
  late String _noiseSchedule;
  late bool? _sm;
  late bool? _smDyn;
  late bool? _dynamicThresholding;
  late bool? _varietyPlus;
  late bool? _autoPosition;
  late bool? _legacyUc;
  late int? _width;
  late int? _height;
  late int? _seed;
  late int _requestIntervalSeconds;
  late int _requestIntervalRandomRangeSeconds;
  late int _retryCount;
  late bool _retryIndefinitely;
  late int _retryOn429DelaySeconds;
  late String _outputDirectory;
  int _executionEpoch = 0;
  Future<void> _executionSettingsSaveQueue = Future<void>.value();
  Future<void> _queueMutation = Future<void>.value();

  ProductionQueueViewModel({
    required List<ProductionPlan> plans,
    this.settings = const ProductionQueueExecutionSettings(),
    this.queueService,
    this.executorService,
    this.loadRecastKnowledgeBase,
    this.saveRecastKnowledgeBase,
    ProductionDirectoryPicker? pickOutputDirectory,
    ProductionOutputImageDeleter? deleteOutputImage,
    ProductionTaskJsonExporter? exporter,
    ProductionClock? now,
  })  : _plans = List.unmodifiable(plans),
        pickOutputDirectoryPath = pickOutputDirectory,
        deleteOutputImage = deleteOutputImage ?? _defaultDeleteOutputImage,
        exporter = exporter ?? _defaultExporter,
        now = now ?? (() => DateTime.now().toUtc()) {
    _applyInitialExecutionSettings(_initialPlanExecutionSettings(_plans));
    ProductionPlan? initialPlan;
    for (final plan in plans) {
      if (plan.tasks.isEmpty || visibleTasksForPlan(plan).isNotEmpty) {
        initialPlan = plan;
        break;
      }
    }
    _selectedPlanId = initialPlan?.id;
    _selectedTask =
        initialPlan == null ? null : _taskForPlanSelection(initialPlan);
    if (_selectedTask != null && _selectedPlanId != null) {
      _selectedTaskIdsByPlanId[_selectedPlanId!] = _selectedTask!.id;
    }
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

  /// The plan currently selected in the queue UI.
  ///
  /// A plan whose tasks are all dismissed is intentionally not selected by
  /// the queue projection.  Script Exhibition can still focus such a plan
  /// explicitly through [focusProductionTask], but ordinary queue reads must
  /// not fall back to the first persisted (and hidden) plan.
  ProductionPlan? get selectedPlan => _planById(_selectedPlanId);

  ProductionPlan? get activePlan => _planById(_activePlanId);

  List<ProductionPlan> get plans => _plans;

  /// Plans projected for queue presentation. Dismissed tasks stay in [plans]
  /// for Script Exhibition, but do not keep an otherwise empty queue tab alive.
  List<ProductionPlan> get visiblePlans => List.unmodifiable([
        for (final plan in plans)
          if (_isQueuePlanVisible(plan)) plan,
      ]);

  List<ProductionTask> visibleTasksForPlan(ProductionPlan? plan) {
    if (plan == null) return const [];
    return List.unmodifiable(
      plan.tasks.where((task) => !task.isQueueDismissed),
    );
  }

  /// Number of completed script tasks that can be safely hidden from Queue.
  int get completedTasksPendingDismissal => _completedTasksPendingDismissal;

  /// Alias used by queue surfaces that describe this as a clearable count.
  int get completedTasksToClear => completedTasksPendingDismissal;

  bool get canClearCompletedTasks =>
      !_clearCompletedTasksPending && completedTasksPendingDismissal > 0;

  int get _completedTasksPendingDismissal {
    var count = 0;
    for (final plan in plans) {
      if (!_isPlanEligibleForCompletedClear(plan)) continue;
      for (final task in plan.tasks) {
        if (_canDismissCompletedTask(task)) count += 1;
      }
    }
    return count;
  }

  ProductionTask? get selectedTask => _selectedTask;

  int get totalTasks => _statsForSelectedPlan.totalTasks;

  int get completedTasks => _statsForSelectedPlan.completedTasks;

  int get failedTasks => _statsForSelectedPlan.failedTasks;

  int get abnormalTasks => _statsForSelectedPlan.abnormalTasks;

  int get runningTasks => _statsForSelectedPlan.runningTasks;

  bool get hasFailedTasks => failedTasks > 0;

  bool get hasAbnormalTasks => abnormalTasks > 0;

  bool get isExecuting => _isExecuting;

  bool get pauseRequested => _pauseRequested;

  bool get isPaused => _isPaused;

  bool get isViewingActivePlan =>
      activePlan == null || selectedPlan?.id == activePlan?.id;

  bool get canEditSelectedPlanSettings => isViewingActivePlan;

  bool get canStartSelectedPlan =>
      activePlan == null &&
      selectedPlan != null &&
      !_isPlanDeletionPending(selectedPlan?.id) &&
      !_isPlanExecutionActivationPending(selectedPlan?.id) &&
      _statsForSelectedPlan.queuedTasks > 0;

  bool get canStop => _isExecuting || _isPaused;

  bool get canPause => _isExecuting && !_pauseRequested;

  bool get canResume {
    if (_isExecuting) return false;
    if (_isPaused) {
      final plan = activePlan;
      return plan != null && _taskStatsForPlan(plan).queuedTasks > 0;
    }
    return selectedPlan != null &&
        _statsForSelectedPlan.queuedTasks > 0 &&
        _statsForSelectedPlan.hasRestoredUnfinishedWork;
  }

  bool get canClearCurrentPlan =>
      activePlan == null &&
      !_isPlanExecutionActivationPending(selectedPlan?.id) &&
      _statsForSelectedPlan.totalTasks > 0;

  bool get canRenameSelectedPlan =>
      activePlan == null &&
      !_isPlanExecutionActivationPending(selectedPlan?.id) &&
      selectedPlan != null;

  bool get useOriginalGenerationSettings =>
      _useOriginalModel &&
      _useOriginalSize &&
      _useOriginalSampler &&
      _useOriginalSteps &&
      _useOriginalScale &&
      _useOriginalCfgRescale &&
      _useOriginalNoiseSchedule &&
      _useOriginalSm &&
      _useOriginalSmDyn &&
      _useOriginalDynamicThresholding &&
      _useOriginalVarietyPlus &&
      _useOriginalAutoPosition &&
      _useOriginalLegacyUc &&
      _useOriginalSeed;

  bool get useOriginalModel => _useOriginalModel;

  bool get useOriginalSize => _useOriginalSize;

  bool get useOriginalSampler => _useOriginalSampler;

  bool get useOriginalSteps => _useOriginalSteps;

  bool get useOriginalScale => _useOriginalScale;

  bool get useOriginalCfgRescale => _useOriginalCfgRescale;

  bool get useOriginalNoiseSchedule => _useOriginalNoiseSchedule;

  bool get useOriginalSm => _useOriginalSm;

  bool get useOriginalSmDyn => _useOriginalSmDyn;

  bool get useOriginalDynamicThresholding => _useOriginalDynamicThresholding;

  bool get useOriginalVarietyPlus => _useOriginalVarietyPlus;

  bool get useOriginalAutoPosition => _useOriginalAutoPosition;

  bool get useOriginalLegacyUc => _useOriginalLegacyUc;

  bool get useOriginalSeed => _useOriginalSeed;

  String get batchModel => _model;

  String get batchSampler => _sampler;

  int? get batchSteps => _steps;

  double? get batchScale => _scale;

  double? get batchCfgRescale => _cfgRescale;

  String get batchNoiseSchedule => _noiseSchedule;

  bool? get batchSm => _sm;

  bool? get batchSmDyn => _smDyn;

  bool? get batchDynamicThresholding => _dynamicThresholding;

  bool? get batchVarietyPlus => _varietyPlus;

  bool? get batchAutoPosition => _autoPosition;

  bool? get batchLegacyUc => _legacyUc;

  int? get batchWidth => _width;

  int? get batchHeight => _height;

  int? get batchSeed => _seed;

  int get requestIntervalSeconds => _requestIntervalSeconds;

  int get requestIntervalRandomRangeSeconds =>
      _requestIntervalRandomRangeSeconds;

  int get retryCount => _retryCount;

  bool get retryIndefinitely => _retryIndefinitely;

  int get retryOn429DelaySeconds => _retryOn429DelaySeconds;

  String get outputDirectory => _outputDirectory;

  bool get canPickOutputDirectory => pickOutputDirectoryPath != null;

  void selectTask(ProductionTask task) {
    final plan = selectedPlan;
    if (plan == null ||
        task.isQueueDismissed ||
        !plan.tasks.any((candidate) => candidate.id == task.id)) {
      return;
    }
    _selectedTask = task;
    _selectedTaskIdsByPlanId[plan.id] = task.id;
    notifyListeners();
  }

  bool selectPlan(String planId) {
    final target = _planById(planId.trim());
    if (target == null || !_isQueuePlanVisible(target)) {
      return false;
    }
    final currentPlan = selectedPlan;
    if (currentPlan?.id == target.id) return true;
    if (currentPlan != null && _selectedTask != null) {
      _selectedTaskIdsByPlanId[currentPlan.id] = _selectedTask!.id;
    }
    _selectedPlanId = target.id;
    _selectedTask = _taskForPlanSelection(target);
    _applyPlanExecutionSettings(
      target.executionSettings ??
          _lastUsedExecutionSettings ??
          _currentExecutionSettings(),
    );
    notifyListeners();
    return true;
  }

  void setUseOriginalGenerationSettings(bool value) {
    if (_useOriginalModel == value &&
        _useOriginalSize == value &&
        _useOriginalSampler == value &&
        _useOriginalSteps == value &&
        _useOriginalScale == value &&
        _useOriginalCfgRescale == value &&
        _useOriginalNoiseSchedule == value &&
        _useOriginalSm == value &&
        _useOriginalSmDyn == value &&
        _useOriginalDynamicThresholding == value &&
        _useOriginalVarietyPlus == value &&
        _useOriginalAutoPosition == value &&
        _useOriginalLegacyUc == value &&
        _useOriginalSeed == value) {
      return;
    }
    _useOriginalModel = value;
    _useOriginalSize = value;
    _useOriginalSampler = value;
    _useOriginalSteps = value;
    _useOriginalScale = value;
    _useOriginalCfgRescale = value;
    _useOriginalNoiseSchedule = value;
    _useOriginalSm = value;
    _useOriginalSmDyn = value;
    _useOriginalDynamicThresholding = value;
    _useOriginalVarietyPlus = value;
    _useOriginalAutoPosition = value;
    _useOriginalLegacyUc = value;
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

  void setUseOriginalCfgRescale(bool value) {
    if (_useOriginalCfgRescale == value) return;
    _useOriginalCfgRescale = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalNoiseSchedule(bool value) {
    if (_useOriginalNoiseSchedule == value) return;
    _useOriginalNoiseSchedule = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalSm(bool value) {
    if (_useOriginalSm == value) return;
    _useOriginalSm = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalSmDyn(bool value) {
    if (_useOriginalSmDyn == value) return;
    _useOriginalSmDyn = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalDynamicThresholding(bool value) {
    if (_useOriginalDynamicThresholding == value) return;
    _useOriginalDynamicThresholding = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalVarietyPlus(bool value) {
    if (_useOriginalVarietyPlus == value) return;
    _useOriginalVarietyPlus = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalAutoPosition(bool value) {
    if (_useOriginalAutoPosition == value) return;
    _useOriginalAutoPosition = value;
    _notifyAndPersistExecutionSettings();
  }

  void setUseOriginalLegacyUc(bool value) {
    if (_useOriginalLegacyUc == value) return;
    _useOriginalLegacyUc = value;
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

  void setBatchCfgRescaleText(String value) {
    final next = _parseUnitDouble(value);
    if (_cfgRescale == next) return;
    _cfgRescale = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchNoiseSchedule(String value) {
    final next = value.trim();
    if (_noiseSchedule == next) return;
    _noiseSchedule = next;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchSm(bool value) {
    if (_sm == value) return;
    _sm = value;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchSmDyn(bool value) {
    if (_smDyn == value) return;
    _smDyn = value;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchDynamicThresholding(bool value) {
    if (_dynamicThresholding == value) return;
    _dynamicThresholding = value;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchVarietyPlus(bool value) {
    if (_varietyPlus == value) return;
    _varietyPlus = value;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchAutoPosition(bool value) {
    if (_autoPosition == value) return;
    _autoPosition = value;
    _notifyAndPersistExecutionSettings();
  }

  void setBatchLegacyUc(bool value) {
    if (_legacyUc == value) return;
    _legacyUc = value;
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

  void setRetryOn429DelaySecondsText(String value) {
    final next = _parsePositiveInt(value) ?? 1;
    if (_retryOn429DelaySeconds == next) return;
    _retryOn429DelaySeconds = next;
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
    await _enqueueQueueMutation(() => _renameSelectedPlanNow(label));
  }

  Future<void> _renameSelectedPlanNow(String label) async {
    final plan = selectedPlan;
    final next = label.trim();
    if (plan == null ||
        next.isEmpty ||
        activePlan != null ||
        _isPlanDeletionPending(plan.id) ||
        _isPlanExecutionActivationPending(plan.id) ||
        plan.name == next) {
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

  Future<void> load({String? preferredPlanId}) {
    return _enqueueQueueMutation(
      () => _loadNow(preferredPlanId: preferredPlanId),
    );
  }

  Future<void> _loadNow({String? preferredPlanId}) async {
    final service = queueService;
    if (service == null) return;
    final lastUsedSettings = await service.loadLastExecutionSettings();
    _lastUsedExecutionSettings = lastUsedSettings;
    final loadedPlans = await service.loadPlansReadOnly();
    final runningPlan = activePlan;
    final nextPlans = runningPlan == null
        ? loadedPlans
        : [
            runningPlan,
            for (final plan in loadedPlans)
              if (plan.id != runningPlan.id) plan,
          ];
    final preferred = preferredPlanId?.trim();
    final preferredPlan = preferred == null || preferred.isEmpty
        ? null
        : nextPlans.where((plan) => plan.id == preferred).firstOrNull;
    final selectedPlanId = runningPlan != null
        ? _selectedPlanId
        : preferredPlan != null && _isQueuePlanVisible(preferredPlan)
            ? preferredPlan.id
            : _firstVisiblePlanId(nextPlans);
    _setPlans(
      nextPlans,
      selectedPlanId: selectedPlanId,
      fallbackExecutionSettings: lastUsedSettings,
    );
    notifyListeners();
  }

  void applyPersistedTaskDeletions({
    required Map<String, Set<String>> taskIdsByPlanId,
    required DateTime updatedAt,
  }) {
    if (taskIdsByPlanId.isEmpty) return;
    var changed = false;
    final nextPlans = <ProductionPlan>[];
    for (final plan in plans) {
      final deletedTaskIds = taskIdsByPlanId[plan.id];
      if (deletedTaskIds == null || deletedTaskIds.isEmpty) {
        nextPlans.add(plan);
        continue;
      }
      final nextTasks = plan.tasks
          .where((task) => !deletedTaskIds.contains(task.id))
          .toList(growable: false);
      if (nextTasks.length == plan.tasks.length) {
        nextPlans.add(plan);
        continue;
      }
      changed = true;
      if (nextTasks.isNotEmpty) {
        nextPlans.add(
          plan.copyWith(tasks: nextTasks, updatedAt: updatedAt),
        );
      }
    }
    if (!changed) return;
    _setPlans(
      nextPlans,
      preserveCurrentExecutionSettings: true,
    );
    notifyListeners();
  }

  Future<bool> loadAndFocusProductionTask({
    required String planId,
    required String taskId,
  }) {
    return _enqueueQueueMutation(
      () => _loadAndFocusProductionTaskNow(
        planId: planId,
        taskId: taskId,
      ),
    );
  }

  Future<bool> _loadAndFocusProductionTaskNow({
    required String planId,
    required String taskId,
  }) async {
    final service = queueService;
    final lastUsedSettings =
        service == null ? null : await service.loadLastExecutionSettings();
    final loadedPlans =
        service == null ? plans : await service.loadPlansReadOnly();
    final runningPlan = activePlan;
    final focusablePlans = runningPlan == null
        ? loadedPlans
        : [
            runningPlan,
            for (final plan in loadedPlans)
              if (plan.id != runningPlan.id) plan,
          ];
    return _focusProductionTaskInPlans(
      focusablePlans,
      planId: planId,
      taskId: taskId,
      fallbackExecutionSettings: lastUsedSettings,
    );
  }

  bool focusProductionTask({
    required String planId,
    required String taskId,
  }) {
    return _focusProductionTaskInPlans(
      plans,
      planId: planId,
      taskId: taskId,
    );
  }

  Future<void> start() async {
    final executor = executorService;
    if (executor == null) return;
    final activation = await _activateStartPlan();
    if (activation == null) return;
    final runEpoch = activation.runEpoch;
    var hasRunPreviousTask = false;
    try {
      while (_executionEpoch == runEpoch && !_pauseRequested) {
        final currentPlan = _planById(_activePlanId);
        if (currentPlan == null) break;
        final nextTask = _nextQueuedTask(currentPlan);
        if (nextTask == null) break;
        final executionSettings = _executionSettingsForPlan(currentPlan);
        if (hasRunPreviousTask) {
          await _waitForNextRequestInterval(executor, executionSettings);
        }
        if (_executionEpoch != runEpoch || _pauseRequested) break;
        final executionPlan = _executionPlanForTask(
          currentPlan,
          nextTask,
          executionSettings,
        );
        try {
          await executor.rerunTaskInPlan(
            executionPlan,
            taskId: nextTask.id,
            maxRetries: _maxRetriesFor(executionSettings),
            retryIndefinitely: executionSettings.retryIndefinitely,
            retryOn429Delay: Duration(
              seconds: executionSettings.retryOn429DelaySeconds,
            ),
            onTaskUpdate: (task) {
              if (_executionEpoch != runEpoch) return Future<void>.value();
              return _replaceTaskInPlan(executionPlan.id, task);
            },
            shouldContinue: () =>
                _executionEpoch == runEpoch && !_pauseRequested,
            shouldAcceptResult: () => _executionEpoch == runEpoch,
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
      final updatedPlan = _planById(_activePlanId);
      _isPaused = _pauseRequested &&
          (updatedPlan?.tasks.any(
                (task) => task.status == ProductionTaskStatus.queued,
              ) ??
              false);
    } finally {
      if (_executionEpoch == runEpoch) {
        _isExecuting = false;
        _pauseRequested = false;
        if (!_isPaused) {
          _activePlanId = null;
        }
        notifyListeners();
      }
    }
  }

  Future<_ProductionExecutionActivation?> _activateStartPlan() {
    final resumedPlan = _isPaused ? activePlan : null;
    final candidatePlan = resumedPlan ?? selectedPlan;
    if (candidatePlan == null ||
        _isPlanDeletionPending(candidatePlan.id) ||
        _isPlanExecutionActivationPending(candidatePlan.id)) {
      return Future<_ProductionExecutionActivation?>.value();
    }
    final planId = candidatePlan.id;
    final resume = resumedPlan != null;
    _pendingExecutionActivationIds.add(planId);
    notifyListeners();
    final activation =
        _enqueueQueueMutation<_ProductionExecutionActivation?>(() async {
      final currentPlan = _planById(planId);
      if (currentPlan == null ||
          _isPlanDeletionPending(planId) ||
          _isExecuting ||
          (resume
              ? !_isPaused || activePlan?.id != planId
              : activePlan != null)) {
        return null;
      }
      ProductionPlan? planToPersist;
      var plan = currentPlan;
      if (!resume) {
        final preparedPlan = currentPlan.copyWith(
          executionSettings: _currentExecutionSettings(),
          updatedAt: now().toUtc(),
        );
        final planIndex =
            plans.indexWhere((candidate) => candidate.id == currentPlan.id);
        if (planIndex < 0) return null;
        final nextPlans = plans.toList(growable: false);
        nextPlans[planIndex] = preparedPlan;
        _setPlans(
          nextPlans,
          selectedTaskId: _selectedTask?.id,
          preserveCurrentExecutionSettings: true,
        );
        plan = preparedPlan;
        planToPersist = preparedPlan;
      }
      final runEpoch = ++_executionEpoch;
      _activePlanId = plan.id;
      _isExecuting = true;
      _pauseRequested = false;
      _isPaused = false;
      notifyListeners();
      final service = queueService;
      if (service != null && planToPersist != null) {
        await service.savePlanChanges(
          updatedPlans: [planToPersist],
          deletedPlanIds: const [],
        );
      }
      return _ProductionExecutionActivation(
        plan: plan,
        executionSettings: _executionSettingsForPlan(plan),
        runEpoch: runEpoch,
        planToPersist: planToPersist,
      );
    });
    return activation.whenComplete(() {
      _pendingExecutionActivationIds.remove(planId);
      notifyListeners();
    });
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
    final plan = activePlan;
    if (plan == null) {
      _activePlanId = null;
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
    _activePlanId = null;
    notifyListeners();
  }

  Future<void> resume() async {
    if (!canResume) return;
    await start();
  }

  Future<void> retryFailed() async {
    await rerunAbnormalTasks();
  }

  Future<void> rerunAbnormalTasks() async {
    final executor = executorService;
    // Dismissed tasks are intentionally excluded from queue statistics.  Keep
    // this command a no-op when nothing visible is abnormal so a persisted
    // dismissed row cannot be revived by an abnormal-task retry.
    if (executor == null) return;
    final activation = await _activateRerunAbnormalPlan();
    if (activation == null) return;
    final plan = activation.plan;
    final executionSettings = activation.executionSettings;
    final runEpoch = activation.runEpoch;
    try {
      final executionPlan = _executionPlan(plan, executionSettings);
      final result = await executor.rerunAbnormalTasksInPlan(
        executionPlan,
        maxRetries: _maxRetriesFor(executionSettings),
        retryIndefinitely: executionSettings.retryIndefinitely,
        retryOn429Delay: Duration(
          seconds: executionSettings.retryOn429DelaySeconds,
        ),
        onTaskUpdate: (updatedTask) {
          if (_executionEpoch != runEpoch) return Future<void>.value();
          return _replaceTaskInPlan(executionPlan.id, updatedTask);
        },
        shouldContinue: () => _executionEpoch == runEpoch && !_pauseRequested,
        shouldAcceptResult: () => _executionEpoch == runEpoch,
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
        _activePlanId = null;
        notifyListeners();
      }
    }
  }

  Future<_ProductionExecutionActivation?> _activateRerunAbnormalPlan() {
    final candidatePlan = selectedPlan;
    if (candidatePlan == null ||
        activePlan != null ||
        _isExecuting ||
        _isPlanDeletionPending(candidatePlan.id) ||
        _isPlanExecutionActivationPending(candidatePlan.id) ||
        _taskStatsForPlan(candidatePlan).abnormalTasks <= 0) {
      return Future<_ProductionExecutionActivation?>.value();
    }
    final planId = candidatePlan.id;
    _pendingExecutionActivationIds.add(planId);
    notifyListeners();
    final activation =
        _enqueueQueueMutation<_ProductionExecutionActivation?>(() async {
      final plan = _planById(planId);
      if (plan == null ||
          activePlan != null ||
          _isExecuting ||
          _isPlanDeletionPending(planId) ||
          _taskStatsForPlan(plan).abnormalTasks <= 0) {
        return null;
      }
      final executionSettings = _currentExecutionSettings();
      final runEpoch = ++_executionEpoch;
      _activePlanId = plan.id;
      _isExecuting = true;
      _pauseRequested = false;
      _isPaused = false;
      notifyListeners();
      return _ProductionExecutionActivation(
        plan: plan,
        executionSettings: executionSettings,
        runEpoch: runEpoch,
      );
    });
    return activation.whenComplete(() {
      _pendingExecutionActivationIds.remove(planId);
      notifyListeners();
    });
  }

  /// Hides completed script results from Queue while keeping their task rows
  /// in the persisted plan for Script Exhibition and image organization.
  Future<int> clearCompletedTasks() {
    if (_clearCompletedTasksPending) return Future<int>.value(0);
    _clearCompletedTasksPending = true;
    notifyListeners();
    final clear = _enqueueQueueMutation(_clearCompletedTasksNow);
    return clear.whenComplete(() {
      _clearCompletedTasksPending = false;
      notifyListeners();
    });
  }

  /// Semantic alias for callers that use the persisted dismissal terminology.
  Future<int> dismissCompletedTasks() => clearCompletedTasks();

  Future<int> _clearCompletedTasksNow() async {
    final dismissalAt = now().toUtc();
    final initialBatch = _collectCompletedDismissalChanges(dismissalAt);
    if (initialBatch.plans.isEmpty) return 0;

    // Re-read eligibility immediately before the first await.  Activation is
    // serialized through the same mutation lane, but this second collection
    // also protects against any non-queued state transition being introduced
    // later.
    final latestBatch = _collectCompletedDismissalChanges(dismissalAt);
    if (latestBatch.plans.isEmpty) return 0;

    final service = queueService;
    if (service != null) {
      await service.savePlanChanges(
        updatedPlans: latestBatch.plans,
        deletedPlanIds: const [],
      );
    }
    // A start request reserves its plan before entering the mutation lane.
    // When the persistence call above is blocked, that reservation can arrive
    // while this clear is awaiting.  Do not publish a dismissal for a plan
    // that became activation/deletion-pending during the await; restore the
    // current plan in storage before the queued activation/deletion runs.
    final appliedPlans = <ProductionPlan>[];
    final plansToRestore = <ProductionPlan>[];
    var appliedCount = 0;
    for (final dismissedPlan in latestBatch.plans) {
      final currentPlan = _planById(dismissedPlan.id);
      if (currentPlan == null ||
          !_isPlanEligibleForCompletedClear(currentPlan)) {
        if (currentPlan != null) plansToRestore.add(currentPlan);
        continue;
      }
      appliedPlans.add(dismissedPlan);
      final currentTasksById = {
        for (final task in currentPlan.tasks) task.id: task,
      };
      for (final dismissedTask in dismissedPlan.tasks) {
        final currentTask = currentTasksById[dismissedTask.id];
        if (currentTask == null) continue;
        if (!currentTask.isQueueDismissed && dismissedTask.isQueueDismissed) {
          appliedCount += 1;
        }
      }
    }
    if (service != null && plansToRestore.isNotEmpty) {
      await service.savePlanChanges(
        updatedPlans: plansToRestore,
        deletedPlanIds: const [],
      );
    }
    final updatesById = {
      for (final plan in appliedPlans) plan.id: plan,
    };
    final nextPlans = [
      for (final plan in plans) updatesById[plan.id] ?? plan,
    ];
    _setPlans(
      nextPlans,
      preserveCurrentExecutionSettings: true,
    );
    notifyListeners();
    return appliedCount;
  }

  Future<void> clearCurrentPlan() {
    return _enqueueQueueMutation(_clearCurrentPlanNow);
  }

  Future<void> _clearCurrentPlanNow() async {
    final plan = selectedPlan;
    final visibleTasks = visibleTasksForPlan(plan);
    if (plan == null ||
        activePlan != null ||
        _isPlanDeletionPending(plan.id) ||
        _isPlanExecutionActivationPending(plan.id) ||
        visibleTasks.isEmpty) {
      return;
    }
    _pauseRequested = false;
    _isPaused = false;
    final updatedPlan = plan.copyWith(
      tasks: [
        for (final task in plan.tasks)
          if (task.isQueueDismissed) task,
      ],
      updatedAt: now().toUtc(),
    );
    await _saveUpdatedPlan(updatedPlan);
    _selectedTask = null;
    notifyListeners();
  }

  bool canDeletePlan(String planId) {
    final normalizedPlanId = planId.trim();
    return _planById(normalizedPlanId) != null &&
        !_isPlanDeletionPending(normalizedPlanId) &&
        activePlan?.id != normalizedPlanId;
  }

  Future<ProductionPlanDeletionResult> deletePlan(
    String planId, {
    bool deleteLocalImages = false,
  }) {
    final normalizedPlanId = planId.trim();
    if (_planById(normalizedPlanId) == null ||
        _isPlanDeletionPending(normalizedPlanId) ||
        activePlan?.id == normalizedPlanId) {
      return Future<ProductionPlanDeletionResult>.value(
        const ProductionPlanDeletionResult(deleted: false),
      );
    }
    _pendingPlanDeletionIds.add(normalizedPlanId);
    notifyListeners();
    final deletion = _enqueueQueueMutation(
      () => _deletePlanNow(
        normalizedPlanId,
        deleteLocalImages: deleteLocalImages,
      ),
    );
    return deletion.whenComplete(() {
      _pendingPlanDeletionIds.remove(normalizedPlanId);
      notifyListeners();
    });
  }

  Future<ProductionPlanDeletionResult> _deletePlanNow(
    String planId, {
    required bool deleteLocalImages,
  }) async {
    final normalizedPlanId = planId.trim();
    final planIndex = plans.indexWhere((plan) => plan.id == normalizedPlanId);
    if (planIndex < 0 || activePlan?.id == normalizedPlanId) {
      return const ProductionPlanDeletionResult(deleted: false);
    }
    final plan = plans[planIndex];
    final remainingPlans = [
      for (final candidate in plans)
        if (candidate.id != plan.id) candidate,
    ];
    String? fallbackPlanId = _selectedPlanId;
    if (_selectedPlanId == plan.id) {
      if (planIndex < remainingPlans.length) {
        fallbackPlanId = remainingPlans[planIndex].id;
      } else if (remainingPlans.isNotEmpty) {
        fallbackPlanId = remainingPlans.last.id;
      } else {
        fallbackPlanId = null;
      }
    }

    final service = queueService;
    if (service != null) {
      await service.savePlanChanges(
        updatedPlans: const [],
        deletedPlanIds: [plan.id],
      );
    }
    _selectedTaskIdsByPlanId.remove(plan.id);
    _setPlans(
      remainingPlans,
      selectedPlanId: fallbackPlanId,
    );
    notifyListeners();

    if (!deleteLocalImages) {
      return const ProductionPlanDeletionResult(deleted: true);
    }
    final pathsUsedByRemainingPlans = {
      for (final candidate in remainingPlans)
        for (final task in candidate.tasks)
          if (task.outputImagePath?.trim().isNotEmpty == true)
            _normalizedOutputPath(task.outputImagePath!),
    };
    final outputPaths = {
      for (final task in plan.tasks)
        if (task.outputImagePath?.trim().isNotEmpty == true)
          task.outputImagePath!.trim(),
    }.where(
      (path) =>
          !pathsUsedByRemainingPlans.contains(_normalizedOutputPath(path)),
    );
    var deletedImageCount = 0;
    final failedImagePaths = <String>[];
    for (final path in outputPaths) {
      try {
        if (await deleteOutputImage(path)) {
          deletedImageCount += 1;
        } else {
          failedImagePaths.add(path);
        }
      } catch (_) {
        failedImagePaths.add(path);
      }
    }
    return ProductionPlanDeletionResult(
      deleted: true,
      deletedImageCount: deletedImageCount,
      failedImagePaths: List.unmodifiable(failedImagePaths),
    );
  }

  Future<ProductionTask?> queueRerunTask(ProductionTask task) {
    return _enqueueQueueMutation(
      () => _queueRerunTaskNow(task),
    );
  }

  Future<ProductionTask?> _queueRerunTaskNow(ProductionTask task) async {
    final plan = selectedPlan;
    if (plan == null || _isPlanDeletionPending(plan.id) || plan.tasks.isEmpty) {
      return null;
    }
    final runningPlan = activePlan;
    if (runningPlan != null && runningPlan.id != plan.id) return null;
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
      clearQueueDismissedAt: true,
    );
    final insertionIndex = _quickRerunInsertionIndex(plan, sourceTask);
    final tasks = [...plan.tasks]..insert(insertionIndex, rerunTask);
    await _saveUpdatedPlan(
      plan.copyWith(tasks: tasks, updatedAt: queuedAt),
      selectedTaskId: rerunTask.id,
    );
    notifyListeners();
    return rerunTask;
  }

  Future<ProductionTask?> quickRerunTask(ProductionTask task) async {
    final rerunTask = await queueRerunTask(task);
    if (rerunTask == null) return rerunTask;
    if (activePlan != null && !_isPaused) return rerunTask;
    if (_isPaused) {
      await resume();
    } else {
      await start();
    }
    return rerunTask;
  }

  Future<void> rerunTask(ProductionTask task) async {
    final plan = selectedPlan;
    final executor = executorService;
    if (plan == null ||
        executor == null ||
        _isPlanDeletionPending(plan.id) ||
        _isPlanExecutionActivationPending(plan.id) ||
        task.taskType != ProductionTaskType.scriptRecastFrame ||
        activePlan != null) {
      _selectedTask = task;
      notifyListeners();
      return;
    }

    final activation = await _activateRerunTask(plan.id, task);
    if (activation == null || activation.runnableTask == null) return;
    final runnableTask = activation.runnableTask!;
    final executionSettings = activation.executionSettings;
    final runEpoch = activation.runEpoch;
    var planToRun = activation.plan;
    try {
      final sourceTask = activation.plan.tasks.firstWhere(
        (candidate) => candidate.id == runnableTask.id,
        orElse: () => runnableTask,
      );
      if (sourceTask.isQueueDismissed) {
        planToRun = activation.plan.copyWith(
          tasks: [
            for (final candidate in activation.plan.tasks)
              candidate.id == runnableTask.id
                  ? runnableTask.copyWith(clearQueueDismissedAt: true)
                  : candidate,
          ],
          planFingerprint: activation.plan.planFingerprint,
          updatedAt: activation.plan.updatedAt,
        );
        await _saveUpdatedPlan(
          planToRun,
          selectedTaskId: runnableTask.id,
        );
      }
      _activePlanId = planToRun.id;
      final executionPlan = _executionPlan(planToRun, executionSettings);
      final result = await executor.rerunTaskInPlan(
        executionPlan,
        taskId: runnableTask.id,
        maxRetries: _maxRetriesFor(executionSettings),
        retryIndefinitely: executionSettings.retryIndefinitely,
        retryOn429Delay: Duration(
          seconds: executionSettings.retryOn429DelaySeconds,
        ),
        onTaskUpdate: (updatedTask) {
          if (_executionEpoch != runEpoch) return Future<void>.value();
          return _replaceTaskInPlan(executionPlan.id, updatedTask);
        },
        shouldContinue: () => _executionEpoch == runEpoch && !_pauseRequested,
        shouldAcceptResult: () => _executionEpoch == runEpoch,
      );
      if (_executionEpoch != runEpoch) return;
      await _saveUpdatedPlan(result.plan, selectedTaskId: runnableTask.id);
    } catch (error) {
      if (_executionEpoch != runEpoch) return;
      await _replaceTaskInPlan(
        planToRun.id,
        _unexpectedFailureTask(runnableTask, error),
      );
    } finally {
      if (_executionEpoch == runEpoch) {
        _isExecuting = false;
        _pauseRequested = false;
        _isPaused = false;
        _activePlanId = null;
        notifyListeners();
      }
    }
  }

  Future<_ProductionExecutionActivation?> _activateRerunTask(
    String planId,
    ProductionTask requestedTask,
  ) {
    _pendingExecutionActivationIds.add(planId);
    notifyListeners();
    final activation =
        _enqueueQueueMutation<_ProductionExecutionActivation?>(() async {
      final plan = _planById(planId);
      if (plan == null ||
          activePlan != null ||
          _isExecuting ||
          _isPlanDeletionPending(planId)) {
        return null;
      }
      final sourceTask = plan.tasks.firstWhere(
        (candidate) => candidate.id == requestedTask.id,
        orElse: () => requestedTask,
      );
      final runnableTask = sourceTask.isQueueDismissed
          ? sourceTask.copyWith(clearQueueDismissedAt: true)
          : sourceTask;
      final executionSettings = _currentExecutionSettings();
      final runEpoch = ++_executionEpoch;
      _activePlanId = plan.id;
      _selectedTask = runnableTask;
      _isExecuting = true;
      _pauseRequested = false;
      _isPaused = false;
      notifyListeners();
      return _ProductionExecutionActivation(
        plan: plan,
        executionSettings: executionSettings,
        runEpoch: runEpoch,
        runnableTask: runnableTask,
      );
    });
    return activation.whenComplete(() {
      _pendingExecutionActivationIds.remove(planId);
      notifyListeners();
    });
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

  ProductionPlan? _planById(String? planId) {
    if (planId == null || planId.isEmpty) return null;
    for (final plan in plans) {
      if (plan.id == planId) return plan;
    }
    return null;
  }

  bool _isPlanDeletionPending(String? planId) {
    final normalizedPlanId = planId?.trim();
    return normalizedPlanId != null &&
        normalizedPlanId.isNotEmpty &&
        _pendingPlanDeletionIds.contains(normalizedPlanId);
  }

  bool _isPlanExecutionActivationPending(String? planId) {
    final normalizedPlanId = planId?.trim();
    return normalizedPlanId != null &&
        normalizedPlanId.isNotEmpty &&
        _pendingExecutionActivationIds.contains(normalizedPlanId);
  }

  bool _isPlanEligibleForCompletedClear(ProductionPlan plan) {
    return plan.id != _activePlanId &&
        !_isPlanDeletionPending(plan.id) &&
        !_isPlanExecutionActivationPending(plan.id);
  }

  ({List<ProductionPlan> plans, int count}) _collectCompletedDismissalChanges(
      DateTime dismissalAt) {
    final changedPlans = <ProductionPlan>[];
    var dismissedCount = 0;
    for (final plan in plans) {
      if (!_isPlanEligibleForCompletedClear(plan)) continue;
      var planChanged = false;
      final nextTasks = [
        for (final task in plan.tasks)
          if (_canDismissCompletedTask(task))
            task.copyWith(queueDismissedAt: dismissalAt)
          else
            task,
      ];
      for (var index = 0; index < plan.tasks.length; index += 1) {
        if (!identical(nextTasks[index], plan.tasks[index])) {
          planChanged = true;
          dismissedCount += 1;
        }
      }
      if (!planChanged) continue;
      // Dismissal is queue metadata, so retain both plan and task timestamps
      // and the pre-existing fingerprint exactly.
      changedPlans.add(
        plan.copyWith(
          tasks: nextTasks,
          planFingerprint: plan.planFingerprint,
          updatedAt: plan.updatedAt,
        ),
      );
    }
    return (plans: changedPlans, count: dismissedCount);
  }

  String? _firstVisiblePlanId(List<ProductionPlan> candidates) {
    for (final plan in candidates) {
      if (_isQueuePlanVisible(plan)) {
        return plan.id;
      }
    }
    return null;
  }

  bool _isQueuePlanVisible(ProductionPlan plan) {
    return plan.tasks.isEmpty || visibleTasksForPlan(plan).isNotEmpty;
  }

  ProductionTask? _taskForPlanSelection(
    ProductionPlan plan, {
    bool includeDismissed = false,
  }) {
    final selectedTaskId = _selectedTaskIdsByPlanId[plan.id];
    final selectedTask = _findTaskInPlan(plan, selectedTaskId);
    if (selectedTask != null &&
        (includeDismissed || !selectedTask.isQueueDismissed)) {
      return selectedTask;
    }
    final firstTask = plan.tasks
        .where((task) => includeDismissed || !task.isQueueDismissed)
        .firstOrNull;
    if (firstTask == null) return null;
    _selectedTaskIdsByPlanId[plan.id] = firstTask.id;
    return firstTask;
  }

  ProductionPlanExecutionSettings _executionSettingsForPlan(
    ProductionPlan plan,
  ) {
    if (plan.id == _activePlanId && plan.id == selectedPlan?.id) {
      return _currentExecutionSettings();
    }
    return plan.executionSettings ??
        (plan.id == selectedPlan?.id
            ? _currentExecutionSettings()
            : _lastUsedExecutionSettings ?? _currentExecutionSettings());
  }

  _ProductionQueueTaskStats get _statsForSelectedPlan {
    final plan = selectedPlan;
    final cachedPlan = _selectedPlanStatsPlan;
    final cachedStats = _selectedPlanStats;
    if (identical(cachedPlan, plan) && cachedStats != null) {
      return cachedStats;
    }
    final stats = _taskStatsForPlan(plan);
    _selectedPlanStatsPlan = plan;
    _selectedPlanStats = stats;
    return stats;
  }

  _ProductionQueueTaskStats _taskStatsForPlan(ProductionPlan? plan) {
    if (plan == null) return _ProductionQueueTaskStats.empty;
    var totalTasks = 0;
    var completedTasks = 0;
    var failedTasks = 0;
    var abnormalTasks = 0;
    var runningTasks = 0;
    var queuedTasks = 0;
    var hasPriorRunEvidence = false;
    for (final task in plan.tasks) {
      if (task.isQueueDismissed) continue;
      totalTasks += 1;
      switch (task.status) {
        case ProductionTaskStatus.completed:
          completedTasks += 1;
        case ProductionTaskStatus.failed:
          failedTasks += 1;
        case ProductionTaskStatus.running:
          runningTasks += 1;
        case ProductionTaskStatus.queued:
          queuedTasks += 1;
        case ProductionTaskStatus.skipped:
          break;
      }
      if (_isAbnormalTask(task)) {
        abnormalTasks += 1;
      }
      if (!hasPriorRunEvidence && _hasPriorRunEvidence(task)) {
        hasPriorRunEvidence = true;
      }
    }
    return _ProductionQueueTaskStats(
      totalTasks: totalTasks,
      completedTasks: completedTasks,
      failedTasks: failedTasks,
      abnormalTasks: abnormalTasks,
      runningTasks: runningTasks,
      queuedTasks: queuedTasks,
      hasRestoredUnfinishedWork: queuedTasks > 0 && hasPriorRunEvidence,
    );
  }

  bool _isAbnormalTask(ProductionTask task) {
    return task.status == ProductionTaskStatus.failed ||
        (task.error?.trim().isNotEmpty ?? false);
  }

  bool _canDismissCompletedTask(ProductionTask task) {
    if (task.status != ProductionTaskStatus.completed ||
        task.isQueueDismissed ||
        task.taskType != ProductionTaskType.scriptRecastFrame) {
      return false;
    }
    final hasScriptIdentity = [
      task.source.scriptId,
      task.source.scriptPath,
      task.source.scriptName,
    ].any((value) => value?.trim().isNotEmpty ?? false);
    // The queue projection is deliberately independent of image ownership.
    // A completed script task may have an empty path while an image write is
    // being repaired or while the exhibition is using another provenance
    // record.  It is still a script-backed task and must be dismissible; the
    // persisted task itself remains available to Script Exhibition.
    return hasScriptIdentity;
  }

  ProductionTask? _nextQueuedTask(ProductionPlan plan) {
    for (final task in plan.tasks) {
      if (task.status == ProductionTaskStatus.queued &&
          !task.isQueueDismissed) {
        return task;
      }
    }
    return null;
  }

  Future<void> _waitForNextRequestInterval(
    ProductionExecutorService executor,
    ProductionPlanExecutionSettings executionSettings,
  ) async {
    final baseInterval = Duration(
      seconds: executionSettings.requestIntervalSeconds,
    );
    final randomRangeSeconds =
        executionSettings.requestIntervalRandomRangeSeconds;
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

  int _quickRerunInsertionIndex(
    ProductionPlan plan,
    ProductionTask sourceTask,
  ) {
    final runningIndex = plan.tasks.indexWhere(
      (task) => task.status == ProductionTaskStatus.running,
    );
    if (runningIndex >= 0) {
      return _afterQueuedRerunBlock(plan.tasks, runningIndex + 1);
    }
    final sourceGroupEnd = _sourceTaskGroupEndIndex(plan.tasks, sourceTask);
    if (sourceGroupEnd >= 0) return sourceGroupEnd + 1;
    final queuedIndex = plan.tasks.indexWhere(
      (task) => task.status == ProductionTaskStatus.queued,
    );
    if (queuedIndex >= 0) {
      return _afterQueuedRerunBlock(plan.tasks, queuedIndex);
    }
    return plan.tasks.length;
  }

  int _afterQueuedRerunBlock(List<ProductionTask> tasks, int startIndex) {
    var insertionIndex = startIndex.clamp(0, tasks.length).toInt();
    while (insertionIndex < tasks.length &&
        _isQueuedRerunTask(tasks[insertionIndex])) {
      insertionIndex += 1;
    }
    return insertionIndex;
  }

  int _sourceTaskGroupEndIndex(
    List<ProductionTask> tasks,
    ProductionTask sourceTask,
  ) {
    var endIndex = -1;
    for (var index = 0; index < tasks.length; index += 1) {
      final task = tasks[index];
      if (_isSameProductionTaskGroup(task, sourceTask)) {
        endIndex = index;
      }
    }
    return endIndex;
  }

  bool _isQueuedRerunTask(ProductionTask task) {
    return task.status == ProductionTaskStatus.queued &&
        task.id.contains('-rerun');
  }

  bool _isSameProductionTaskGroup(
    ProductionTask task,
    ProductionTask sourceTask,
  ) {
    if (task.id == sourceTask.id) return true;
    if (task.planId != sourceTask.planId ||
        task.taskType != sourceTask.taskType) {
      return false;
    }
    if (task.taskType == ProductionTaskType.scriptRecastFrame &&
        sourceTask.source.frameIndex != null) {
      final source = task.source;
      final target = sourceTask.source;
      return source.scriptId == target.scriptId &&
          source.recastRunId == target.recastRunId &&
          source.mappingConfigFingerprint == target.mappingConfigFingerprint &&
          source.frameIndex == target.frameIndex &&
          source.sourceFileName == target.sourceFileName;
    }
    return task.id.startsWith('${sourceTask.id}-rerun');
  }

  ProductionTask _resetTaskForRestart(ProductionTask task, DateTime resetAt) {
    if (task.isQueueDismissed) return task;
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
    ProductionPlanExecutionSettings executionSettings,
  ) {
    final executionTask = _executionTask(task, executionSettings);
    return plan.copyWith(
      executionSettings: executionSettings,
      tasks: [
        for (final existingTask in plan.tasks)
          existingTask.id == task.id ? executionTask : existingTask,
      ],
    );
  }

  ProductionTask _executionTask(
    ProductionTask task,
    ProductionPlanExecutionSettings executionSettings,
  ) {
    final normalizedTask = _normalizeTaskPayload(task);
    if (_usesOriginalGenerationSettings(executionSettings)) {
      return normalizedTask;
    }
    return normalizedTask.copyWith(
      payload: _configuredPayload(
        _normalizedPayload(task),
        executionSettings,
      ),
    );
  }

  ProductionPlan _executionPlan(
    ProductionPlan plan,
    ProductionPlanExecutionSettings executionSettings,
  ) {
    final planWithSettings = plan.copyWith(
      executionSettings: executionSettings,
      tasks: [
        for (final task in plan.tasks) _normalizeTaskPayload(task),
      ],
    );
    if (_usesOriginalGenerationSettings(executionSettings)) {
      return planWithSettings;
    }
    return planWithSettings.copyWith(
      tasks: [
        for (final task in plan.tasks)
          task.copyWith(
            payload: _configuredPayload(
              _normalizedPayload(task),
              executionSettings,
            ),
          ),
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

  Map<String, dynamic> _configuredPayload(
    Map<String, dynamic> payload,
    ProductionPlanExecutionSettings executionSettings,
  ) {
    final parameters = _mapValue(payload['parameters']);
    final nextModel = !executionSettings.useOriginalModel &&
            executionSettings.model.trim().isNotEmpty
        ? executionSettings.model.trim()
        : _stringValue(payload['model']) ?? '';
    final nextParameters = <String, dynamic>{
      ...parameters,
      if (!executionSettings.useOriginalSize && executionSettings.width != null)
        'width': executionSettings.width,
      if (!executionSettings.useOriginalSize &&
          executionSettings.height != null)
        'height': executionSettings.height,
      if (!executionSettings.useOriginalSteps &&
          executionSettings.steps != null)
        'steps': executionSettings.steps,
      if (!executionSettings.useOriginalScale &&
          executionSettings.scale != null)
        'scale': executionSettings.scale,
      if (!executionSettings.useOriginalCfgRescale &&
          executionSettings.cfgRescale != null)
        'cfg_rescale': executionSettings.cfgRescale,
      if (!executionSettings.useOriginalNoiseSchedule &&
          executionSettings.noiseSchedule.trim().isNotEmpty)
        'noise_schedule': executionSettings.noiseSchedule.trim(),
      if (!executionSettings.useOriginalSm && executionSettings.sm != null)
        'sm': executionSettings.sm,
      if (!executionSettings.useOriginalSmDyn &&
          executionSettings.smDyn != null)
        'sm_dyn': executionSettings.smDyn,
      if (!executionSettings.useOriginalDynamicThresholding &&
          executionSettings.dynamicThresholding != null)
        'dynamic_thresholding': executionSettings.dynamicThresholding,
      if (!executionSettings.useOriginalSampler &&
          executionSettings.sampler.trim().isNotEmpty)
        'sampler': executionSettings.sampler.trim(),
    };
    _applyConfiguredVarietyPlus(nextParameters, executionSettings);
    _applyConfiguredAutoPosition(nextParameters, executionSettings);
    _applyConfiguredLegacyUc(nextParameters, executionSettings);
    _normalizeConfiguredCompanionParameters(
      nextParameters,
      model: nextModel,
      executionSettings: executionSettings,
    );
    return <String, dynamic>{
      ...payload,
      if (nextModel.isNotEmpty) 'model': nextModel,
      'parameters': nextParameters,
    };
  }

  void _applyConfiguredVarietyPlus(
    Map<String, dynamic> parameters,
    ProductionPlanExecutionSettings executionSettings,
  ) {
    if (executionSettings.useOriginalVarietyPlus ||
        executionSettings.varietyPlus == null) {
      return;
    }
    if (!executionSettings.varietyPlus!) {
      parameters.remove('skip_cfg_above_sigma');
      return;
    }
    final width = _intValue(parameters['width']);
    final height = _intValue(parameters['height']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      parameters.remove('skip_cfg_above_sigma');
      return;
    }
    final normalizedArea = 4.0 * (width / 8) * (height / 8) / 63232;
    parameters['skip_cfg_above_sigma'] = 19.0 * math.sqrt(normalizedArea);
  }

  void _applyConfiguredAutoPosition(
    Map<String, dynamic> parameters,
    ProductionPlanExecutionSettings executionSettings,
  ) {
    if (executionSettings.useOriginalAutoPosition ||
        executionSettings.autoPosition == null) {
      return;
    }
    final prompt = <String, dynamic>{
      ..._mapValue(parameters['v4_prompt']),
      'use_coords': !executionSettings.autoPosition!,
    };
    parameters['v4_prompt'] = prompt;
  }

  void _applyConfiguredLegacyUc(
    Map<String, dynamic> parameters,
    ProductionPlanExecutionSettings executionSettings,
  ) {
    if (executionSettings.useOriginalLegacyUc ||
        executionSettings.legacyUc == null) {
      return;
    }
    parameters['legacy_uc'] = executionSettings.legacyUc;
    final negativePrompt = <String, dynamic>{
      ..._mapValue(parameters['v4_negative_prompt']),
      'legacy_uc': executionSettings.legacyUc,
    };
    parameters['v4_negative_prompt'] = negativePrompt;
  }

  void _normalizeConfiguredCompanionParameters(
    Map<String, dynamic> parameters, {
    required String model,
    required ProductionPlanExecutionSettings executionSettings,
  }) {
    final generationFamilyChanged = (!executionSettings.useOriginalModel &&
            executionSettings.model.trim().isNotEmpty) ||
        (!executionSettings.useOriginalSampler &&
            executionSettings.sampler.trim().isNotEmpty) ||
        (!executionSettings.useOriginalNoiseSchedule &&
            executionSettings.noiseSchedule.trim().isNotEmpty) ||
        (!executionSettings.useOriginalSm && executionSettings.sm != null) ||
        (!executionSettings.useOriginalSmDyn &&
            executionSettings.smDyn != null);
    if (!generationFamilyChanged) return;

    final isV4 = model.contains('diffusion-4');
    if (isV4) {
      parameters.remove('sm');
      parameters.remove('sm_dyn');
      if (parameters['noise_schedule'] == 'native') {
        parameters['noise_schedule'] = 'karras';
      }
    }

    parameters.remove('prefer_brownian');
    parameters.remove('deliberate_euler_ancestral_bug');
    if (parameters['sampler'] == 'k_euler_ancestral' &&
        parameters['noise_schedule'] != 'native') {
      parameters['prefer_brownian'] = true;
      parameters['deliberate_euler_ancestral_bug'] = false;
    }
  }

  int _maxRetriesFor(ProductionPlanExecutionSettings executionSettings) =>
      executionSettings.retryCount <= 0 ? 1 : executionSettings.retryCount;

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
      await service.savePlanChanges(
        updatedPlans: [updatedPlan],
        deletedPlanIds:
            previousPlanId == updatedPlan.id ? const [] : [previousPlanId],
      );
    }
    if (_selectedPlanId == previousPlanId) {
      _selectedPlanId = updatedPlan.id;
    }
    if (_activePlanId == previousPlanId) {
      _activePlanId = updatedPlan.id;
    }
    final rememberedTaskId = _selectedTaskIdsByPlanId.remove(previousPlanId);
    if (rememberedTaskId != null) {
      _selectedTaskIdsByPlanId[updatedPlan.id] =
          selectedTaskId ?? rememberedTaskId;
    }
    _setPlans(
      nextPlans,
      selectedTaskId: _selectedPlanId == updatedPlan.id ? selectedTaskId : null,
      preserveCurrentExecutionSettings: preserveCurrentExecutionSettings,
    );
  }

  Future<void> _replaceTaskInPlan(String planId, ProductionTask task) {
    return _enqueueQueueMutation(
      () => _replaceTaskInPlanNow(planId, task),
    );
  }

  Future<void> _replaceTaskInPlanNow(
    String planId,
    ProductionTask task,
  ) async {
    final planIndex = plans.indexWhere((plan) => plan.id == planId);
    if (planIndex < 0) return;
    final updatedPlan = plans[planIndex].copyWith(
      tasks: [
        for (final existingTask in plans[planIndex].tasks)
          existingTask.id == task.id ? task : existingTask,
      ],
      updatedAt: now().toUtc(),
    );
    final nextPlans = plans.toList(growable: false);
    nextPlans[planIndex] = updatedPlan;
    final isSelectedPlan = selectedPlan?.id == planId;
    if (!isSelectedPlan) {
      _selectedTaskIdsByPlanId[planId] = task.id;
    }
    _setPlans(
      nextPlans,
      selectedTaskId: isSelectedPlan ? task.id : null,
    );
    notifyListeners();
    final service = queueService;
    if (service != null) {
      await service.savePlanChanges(
        updatedPlans: [updatedPlan],
        deletedPlanIds: const [],
      );
    }
  }

  void _setPlans(
    List<ProductionPlan> nextPlans, {
    String? selectedPlanId,
    String? selectedTaskId,
    ProductionPlanExecutionSettings? fallbackExecutionSettings,
    bool preserveCurrentExecutionSettings = false,
    bool allowDismissedSelectedTask = false,
  }) {
    final previousPlan = selectedPlan;
    if (previousPlan != null && _selectedTask != null) {
      _selectedTaskIdsByPlanId[previousPlan.id] = _selectedTask!.id;
    }
    final normalizedPlans =
        _isExecuting ? nextPlans : _normalizeIdleRunningTasks(nextPlans);
    _plans = List.unmodifiable(normalizedPlans);
    final requestedPlanId = selectedPlanId ?? _selectedPlanId;
    final requestedPlan = _planById(requestedPlanId);
    final requestedPlanIsVisible =
        requestedPlan == null || _isQueuePlanVisible(requestedPlan);
    final visiblePlanId = requestedPlan == null
        ? _firstVisiblePlanId(normalizedPlans)
        : requestedPlanIsVisible
            ? requestedPlan.id
            : _firstVisiblePlanId(normalizedPlans);
    _selectedPlanId = allowDismissedSelectedTask && requestedPlan != null
        ? requestedPlan.id
        : visiblePlanId;
    final currentPlan = selectedPlan;
    if (currentPlan != null && selectedTaskId != null) {
      _selectedTaskIdsByPlanId[currentPlan.id] = selectedTaskId;
    }
    _selectedTask = currentPlan == null
        ? null
        : _taskForPlanSelection(
            currentPlan,
            includeDismissed: allowDismissedSelectedTask,
          );
    if (!preserveCurrentExecutionSettings && currentPlan != null) {
      final settingsPlans = [
        currentPlan,
        for (final plan in plans)
          if (plan.id != currentPlan.id) plan,
      ];
      final planSettings = _initialPlanExecutionSettings(
        settingsPlans,
        fallbackExecutionSettings:
            fallbackExecutionSettings ?? _lastUsedExecutionSettings,
      );
      if (planSettings != null) {
        _applyPlanExecutionSettings(planSettings);
      }
    }
    if (!_isExecuting &&
        !_pauseRequested &&
        activePlan == null &&
        !_isPlanExecutionActivationPending(_selectedPlanId)) {
      final plan = selectedPlan;
      _isPaused = _taskStatsForPlan(plan).hasRestoredUnfinishedWork;
      if (_isPaused) {
        _activePlanId = plan?.id;
      }
    }
    if (_activePlanId != null && _planById(_activePlanId) == null) {
      _activePlanId = null;
      _isPaused = false;
    }
  }

  bool _focusProductionTaskInPlans(
    List<ProductionPlan> sourcePlans, {
    required String planId,
    required String taskId,
    ProductionPlanExecutionSettings? fallbackExecutionSettings,
  }) {
    final normalizedPlanId = planId.trim();
    final normalizedTaskId = taskId.trim();
    if (normalizedPlanId.isEmpty || normalizedTaskId.isEmpty) {
      return false;
    }

    ProductionPlan? targetPlan;
    for (final plan in sourcePlans) {
      if (plan.id == normalizedPlanId) {
        targetPlan = plan;
        break;
      }
    }
    if (targetPlan == null) {
      return false;
    }
    final hasTask = targetPlan.tasks.any((task) => task.id == normalizedTaskId);
    if (!hasTask) {
      return false;
    }

    _setPlans(
      sourcePlans,
      selectedPlanId: normalizedPlanId,
      selectedTaskId: normalizedTaskId,
      fallbackExecutionSettings: fallbackExecutionSettings,
      allowDismissedSelectedTask: true,
    );
    notifyListeners();
    return true;
  }

  List<ProductionPlan> _normalizeIdleRunningTasks(List<ProductionPlan> plans) {
    return [
      for (final plan in plans)
        if (plan.tasks.any((task) =>
            task.status == ProductionTaskStatus.running &&
            !task.isQueueDismissed))
          plan.copyWith(
            tasks: [
              for (final task in plan.tasks)
                task.status == ProductionTaskStatus.running &&
                        !task.isQueueDismissed
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

  ProductionTask? _findTaskInPlan(ProductionPlan? plan, String? taskId) {
    if (plan == null || taskId == null) return null;
    for (final task in plan.tasks) {
      if (task.id == taskId) return task;
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
      _useOriginalCfgRescale = settings.useOriginalGenerationSettings;
      _useOriginalNoiseSchedule = settings.useOriginalGenerationSettings;
      _useOriginalSm = settings.useOriginalGenerationSettings;
      _useOriginalSmDyn = settings.useOriginalGenerationSettings;
      _useOriginalDynamicThresholding = settings.useOriginalGenerationSettings;
      _useOriginalVarietyPlus = settings.useOriginalGenerationSettings;
      _useOriginalAutoPosition = settings.useOriginalGenerationSettings;
      _useOriginalLegacyUc = settings.useOriginalGenerationSettings;
      _useOriginalSeed =
          settings.useOriginalGenerationSettings || settings.useOriginalSeed;
      _model = settings.model;
      _sampler = settings.sampler;
      _steps = settings.steps;
      _scale = settings.scale;
      _cfgRescale = settings.cfgRescale;
      _noiseSchedule = settings.noiseSchedule;
      _sm = settings.sm;
      _smDyn = settings.smDyn;
      _dynamicThresholding = settings.dynamicThresholding;
      _varietyPlus = settings.varietyPlus;
      _autoPosition = settings.autoPosition;
      _legacyUc = settings.legacyUc;
      _width = settings.width;
      _height = settings.height;
      _seed = _normalizeSeed(settings.seed);
      _requestIntervalSeconds =
          _nonNegativeInt(settings.requestIntervalSeconds);
      _requestIntervalRandomRangeSeconds =
          _nonNegativeInt(settings.requestIntervalRandomRangeSeconds);
      _retryCount = _positiveIntOrOne(settings.retryCount);
      _retryIndefinitely = settings.retryIndefinitely;
      _retryOn429DelaySeconds =
          _positiveIntOrOne(settings.retryOn429DelaySeconds);
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
    _useOriginalCfgRescale = planSettings.useOriginalCfgRescale;
    _useOriginalNoiseSchedule = planSettings.useOriginalNoiseSchedule;
    _useOriginalSm = planSettings.useOriginalSm;
    _useOriginalSmDyn = planSettings.useOriginalSmDyn;
    _useOriginalDynamicThresholding =
        planSettings.useOriginalDynamicThresholding;
    _useOriginalVarietyPlus = planSettings.useOriginalVarietyPlus;
    _useOriginalAutoPosition = planSettings.useOriginalAutoPosition;
    _useOriginalLegacyUc = planSettings.useOriginalLegacyUc;
    _useOriginalSeed = planSettings.useOriginalSeed;
    _model = planSettings.model;
    _sampler = planSettings.sampler;
    _steps = planSettings.steps;
    _scale = planSettings.scale;
    _cfgRescale = planSettings.cfgRescale;
    _noiseSchedule = planSettings.noiseSchedule;
    _sm = planSettings.sm;
    _smDyn = planSettings.smDyn;
    _dynamicThresholding = planSettings.dynamicThresholding;
    _varietyPlus = planSettings.varietyPlus;
    _autoPosition = planSettings.autoPosition;
    _legacyUc = planSettings.legacyUc;
    _width = planSettings.width;
    _height = planSettings.height;
    _seed = _normalizeSeed(planSettings.seed);
    _requestIntervalSeconds =
        _nonNegativeInt(planSettings.requestIntervalSeconds);
    _requestIntervalRandomRangeSeconds =
        _nonNegativeInt(planSettings.requestIntervalRandomRangeSeconds);
    _retryCount = _positiveIntOrOne(planSettings.retryCount);
    _retryIndefinitely = planSettings.retryIndefinitely;
    _retryOn429DelaySeconds =
        _positiveIntOrOne(planSettings.retryOn429DelaySeconds);
    _outputDirectory = planSettings.outputDirectory;
  }

  ProductionPlanExecutionSettings _currentExecutionSettings() {
    return ProductionPlanExecutionSettings(
      model: _model,
      sampler: _sampler,
      steps: _steps,
      scale: _scale,
      cfgRescale: _cfgRescale,
      noiseSchedule: _noiseSchedule,
      sm: _sm,
      smDyn: _smDyn,
      dynamicThresholding: _dynamicThresholding,
      varietyPlus: _varietyPlus,
      autoPosition: _autoPosition,
      legacyUc: _legacyUc,
      width: _width,
      height: _height,
      seed: _normalizeSeed(_seed),
      useOriginalModel: _useOriginalModel,
      useOriginalSize: _useOriginalSize,
      useOriginalSampler: _useOriginalSampler,
      useOriginalSteps: _useOriginalSteps,
      useOriginalScale: _useOriginalScale,
      useOriginalCfgRescale: _useOriginalCfgRescale,
      useOriginalNoiseSchedule: _useOriginalNoiseSchedule,
      useOriginalSm: _useOriginalSm,
      useOriginalSmDyn: _useOriginalSmDyn,
      useOriginalDynamicThresholding: _useOriginalDynamicThresholding,
      useOriginalVarietyPlus: _useOriginalVarietyPlus,
      useOriginalAutoPosition: _useOriginalAutoPosition,
      useOriginalLegacyUc: _useOriginalLegacyUc,
      useOriginalSeed: _useOriginalSeed,
      requestIntervalSeconds: _requestIntervalSeconds,
      requestIntervalRandomRangeSeconds: _requestIntervalRandomRangeSeconds,
      retryCount: _retryCount,
      retryIndefinitely: _retryIndefinitely,
      retryOn429DelaySeconds: _retryOn429DelaySeconds,
      outputDirectory: _outputDirectory,
    );
  }

  void _notifyAndPersistExecutionSettings() {
    final planId = selectedPlan?.id;
    final currentSettings = _currentExecutionSettings();
    _lastUsedExecutionSettings = currentSettings;
    final planIndex = plans.indexWhere((candidate) => candidate.id == planId);
    if (planIndex >= 0) {
      final nextPlans = plans.toList(growable: false);
      nextPlans[planIndex] = nextPlans[planIndex].copyWith(
        executionSettings: currentSettings,
        updatedAt: now().toUtc(),
      );
      _plans = List.unmodifiable(nextPlans);
    }
    notifyListeners();
    _executionSettingsSaveQueue =
        _executionSettingsSaveQueue.catchError((_) {}).then(
              (_) => _persistExecutionSettings(
                planId: planId,
                currentSettings: currentSettings,
              ),
            );
    unawaited(_executionSettingsSaveQueue);
  }

  Future<void> _persistExecutionSettings({
    required String? planId,
    required ProductionPlanExecutionSettings currentSettings,
  }) {
    // Plan settings writes share the same mutation lane as queue deletion and
    // execution callbacks.  This prevents a delayed settings save from
    // recreating a plan that was deleted while the save was in flight.
    return _enqueueQueueMutation(
      () => _persistExecutionSettingsNow(
        planId: planId,
        currentSettings: currentSettings,
      ),
    );
  }

  Future<void> _persistExecutionSettingsNow({
    required String? planId,
    required ProductionPlanExecutionSettings currentSettings,
  }) async {
    final service = queueService;
    if (service != null) {
      await service.saveLastExecutionSettings(currentSettings);
    }
    if (_isExecuting && _activePlanId == planId) {
      return;
    }
    final plan = _planById(planId);
    if (plan == null) return;
    final updatedPlan = plan.copyWith(
      executionSettings: currentSettings,
      updatedAt: now().toUtc(),
    );
    if (service != null) {
      await service.savePlanChanges(
        updatedPlans: [updatedPlan],
        deletedPlanIds: const [],
      );
    }
    final latestPlan = _planById(planId);
    if (latestPlan == null) return;
    final mergedPlan = latestPlan.copyWith(
      executionSettings: currentSettings,
      updatedAt: updatedPlan.updatedAt,
    );
    final latestPlanIndex =
        plans.indexWhere((candidate) => candidate.id == planId);
    if (latestPlanIndex < 0) return;
    final mergedPlans = plans.toList(growable: false);
    mergedPlans[latestPlanIndex] = mergedPlan;
    _setPlans(
      mergedPlans,
      preserveCurrentExecutionSettings: true,
    );
  }

  Future<T> _enqueueQueueMutation<T>(Future<T> Function() operation) {
    final next = _queueMutation.then((_) => operation());
    _queueMutation = next.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    return next;
  }

  @visibleForTesting
  Future<void> flushPendingExecutionSettingsSaves() {
    return _executionSettingsSaveQueue;
  }
}

Future<bool> _defaultDeleteOutputImage(String path) async {
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty) return false;
  final type = await FileSystemEntity.type(
    normalizedPath,
    followLinks: false,
  );
  if (type == FileSystemEntityType.notFound) return true;
  if (type != FileSystemEntityType.file) return false;
  await File(normalizedPath).delete();
  return true;
}

String _normalizedOutputPath(String path) {
  final absolute = File(path.trim()).absolute.path.replaceAll('/', r'\');
  return Platform.isWindows ? absolute.toLowerCase() : absolute;
}

bool _usesOriginalGenerationSettings(
  ProductionPlanExecutionSettings executionSettings,
) {
  return executionSettings.useOriginalModel &&
      executionSettings.useOriginalSize &&
      executionSettings.useOriginalSampler &&
      executionSettings.useOriginalSteps &&
      executionSettings.useOriginalScale &&
      executionSettings.useOriginalCfgRescale &&
      executionSettings.useOriginalNoiseSchedule &&
      executionSettings.useOriginalSm &&
      executionSettings.useOriginalSmDyn &&
      executionSettings.useOriginalDynamicThresholding &&
      executionSettings.useOriginalVarietyPlus &&
      executionSettings.useOriginalAutoPosition &&
      executionSettings.useOriginalLegacyUc &&
      executionSettings.useOriginalSeed;
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

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
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

double? _parseUnitDouble(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null) return null;
  return parsed.clamp(0.0, 1.0).toDouble();
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
