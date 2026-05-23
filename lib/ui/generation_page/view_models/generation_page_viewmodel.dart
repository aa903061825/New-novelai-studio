import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_command/flutter_command.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/generation_size.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:lorem_ipsum/lorem_ipsum.dart';
import 'package:nai_casrand/ui/generation_page/models/generation_payload_cache.dart';
import 'package:nai_casrand/data/services/api_service.dart';
import 'package:nai_casrand/data/services/file_service.dart';
import 'package:nai_casrand/data/services/image_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/use_cases/generate_payload_use_case.dart';

const infoCardContentListLength = 200;

class ApiStatusException implements Exception {
  final int statusCode;
  final String message;

  const ApiStatusException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => message;
}

class GenerationPageViewmodel extends ChangeNotifier {
  PayloadConfig get payloadConfig => GetIt.I<PayloadConfig>();
  CommandStatus get commandStatus => GetIt.I<CommandStatus>();
  ConfigService? get configService =>
      GetIt.I.isRegistered<ConfigService>() ? GetIt.I<ConfigService>() : null;
  StudioGalleryService? get galleryService =>
      GetIt.I.isRegistered<StudioGalleryService>()
          ? GetIt.I<StudioGalleryService>()
          : null;
  List<Command<void, InfoCardContent>> get commandList =>
      commandStatus.commandList;
  int get colNum => payloadConfig.settings.generationPageColumnCount;

  Command<void, InfoCardContent>? currentCommand;
  int _cooldownGeneration = 0;
  int _generatedBatchResolutionCount = 0;
  bool _hasPendingCachedPayloadRetry = false;
  bool _pendingFastRetry429 = false;

  final GenerationPayloadCache<PayloadGenerationResult> _payloadResultCache =
      GenerationPayloadCache<PayloadGenerationResult>();

  bool get _isBatchResolutionEnabled =>
      payloadConfig.paramConfig.enableBatchResolution;

  bool get _isStopAtEndBatchResolution =>
      payloadConfig.paramConfig.batchResolutionMode == 'stop_at_end';

  bool get _shouldStopAtEndBatchResolution =>
      _isBatchResolutionEnabled &&
      _isStopAtEndBatchResolution &&
      !_hasPendingCachedPayloadRetry &&
      !_hasNextBatchResolution;

  bool get _hasNextBatchResolution {
    if (!_isBatchResolutionEnabled) return true;
    if (!_isStopAtEndBatchResolution) return true;
    final resolutions = payloadConfig.paramConfig.parseBatchResolutions();
    return _generatedBatchResolutionCount < resolutions.length;
  }

  @protected
  PayloadGenerationResult generatePayloadResult() {
    return GeneratePayloadUseCase(payloadConfig: payloadConfig)();
  }

  @protected
  Future<ApiResponse> fetchData(ApiRequest request) {
    return ApiService().fetchData(request);
  }

  @protected
  Uint8List processResponse(Uint8List responseBytes) {
    return ImageService().processResponse(responseBytes);
  }

  @protected
  Future<Uint8List> embedMetadata(
    Uint8List imageBytes,
    String metadataString,
  ) {
    return ImageService().embedMetadata(imageBytes, metadataString);
  }

  @protected
  String encodePreviewThumbnail(Uint8List imageBytes) {
    return ImageService().encodePreviewThumbnailB64(imageBytes);
  }

  @protected
  Future<void> savePictureToFile(
    Uint8List bytes,
    String fileName,
    String saveDir,
  ) {
    return FileService().savePictureToFile(bytes, fileName, saveDir);
  }

  @protected
  String generateTimestampString(DateTime time) {
    return FileService().generateTimestampString(time);
  }

  @protected
  String generateRandomString() {
    return FileService().generateRandomString();
  }

  @protected
  int randomInt(int upperBound) {
    return Random().nextInt(upperBound);
  }

  @protected
  void scheduleCooldown(Duration duration, void Function() callback) {
    Timer(duration, callback);
  }

  @visibleForTesting
  int computeCooldownSeconds() {
    final base = payloadConfig.settings.batchIntervalSec;
    final rawMin = payloadConfig.settings.batchIntervalJitterMinSec;
    final rawMax = payloadConfig.settings.batchIntervalJitterMaxSec;
    final minJitter = min(rawMin, rawMax);
    final maxJitter = max(rawMin, rawMax);
    final jitter = maxJitter == minJitter
        ? minJitter
        : minJitter + randomInt(maxJitter - minJitter + 1);
    return base + jitter;
  }

  void setCardsPerCol(int value) {
    payloadConfig.settings.generationPageColumnCount = value;
    notifyListeners();
  }

  bool get hasCurrentConfigPreviewSourceImages =>
      _latestGeneratedImageBytes().isNotEmpty;

  int saveCurrentConfigPreview() {
    final service = configService;
    if (service == null) return 0;

    final previewImages = _latestGeneratedImageBytes()
        .map(encodePreviewThumbnail)
        .toList(growable: false);
    if (previewImages.isEmpty) return 0;

    service.updateConfigPreviewByUuid(
      service.currentUuid,
      previewImages: previewImages,
      previewCoverIndex: randomInt(previewImages.length),
    );
    notifyListeners();
    return previewImages.length;
  }

  List<Uint8List> _latestGeneratedImageBytes({int limit = 9}) {
    return commandList.reversed
        .map((command) => command.value.imageBytes)
        .whereType<Uint8List>()
        .take(limit)
        .toList(growable: false);
  }

  void addAndRunCommand(Command<void, InfoCardContent> command) {
    // Make sure list is not longer than expected
    while (commandList.length >= infoCardContentListLength) {
      commandList.removeAt(0);
    }
    // Push command into list and run command
    commandList.add(command);
    command();
  }

  void addLoremInfoCardContent() async {
    // Async command as image requires loading
    commandFunc() async {
      await Future.delayed(const Duration(milliseconds: 500));
      final random = Random();
      final bytes =
          Uint8List.sublistView(await rootBundle.load('assets/appicon.png'));
      return InfoCardContent(
        title: '#${commandList.length}: ${loremIpsum(
          words: random.nextInt(3) + 3,
          initWithLorem: true,
        )}',
        info: loremIpsum(
          words: random.nextInt(300),
          initWithLorem: true,
        ),
        additionalInfo: {"Random Seed": random.nextInt(1 << 31)},
        imageBytes: random.nextInt(2) == 1 ? null : bytes,
      );
    }

    // Skip if active command exists
    if (currentCommand != null && currentCommand!.isExecuting.value) return;
    final command = Command.createAsyncNoParam(
      commandFunc,
      initialValue: InfoCardContent.fromEmpty(),
    );
    currentCommand = command;
    addAndRunCommand(command);
  }

  void addTestPromptInfoCardContent() {
    // Sync command but wrapped as async
    commandFunc() async {
      final payloadResult = generatePayloadResult();
      final additionalInfo = digestPayloadResult(payloadResult);
      return InfoCardContent(
          title: tr('test_prompt'),
          info: payloadResult.comment,
          additionalInfo: additionalInfo,
          contentOrderText: payloadResult.contentOrderText);
    }

    // Skip the check of active command (because command is sync)
    final command = Command.createAsyncNoParam(
      commandFunc,
      initialValue: InfoCardContent.fromEmpty(),
    );
    command.isExecuting.addListener(() {
      if (command.isExecuting.value) return;
      notifyListeners();
    });
    addAndRunCommand(command);
  }

  void nextCommand() {
    // Stop if batch is inactive or cooling down
    if (!commandStatus.isBatchActive.value) return;
    if (commandStatus.isCoolingDown.value) return;

    if (_shouldStopAtEndBatchResolution) {
      stopBatch();
      _addSystemMessageCard(
        title: tr('batch_resolution_end_title'),
        message: tr('batch_resolution_end_message'),
      );
      return;
    }

    // Skip if active command exists
    if (currentCommand != null && currentCommand!.isExecuting.value) return;

    // Generate, postprocess and save image
    commandFunc() async {
      final endpoint = payloadConfig.settings.debugApiEnabled
          ? payloadConfig.settings.debugApiPath
          : 'https://image.novelai.net/ai/generate-image';

      var generatedNewPayload = false;
      final payloadResult = _payloadResultCache.takeOrGenerate(() {
        generatedNewPayload = true;
        return _generateBatchPayloadResult();
      });
      if (generatedNewPayload && _isStopAtEndBatchResolution) {
        _generatedBatchResolutionCount++;
      }

      final request = ApiRequest(
        endpoint: endpoint,
        proxy: payloadConfig.settings.proxy,
        headers: payloadConfig.getHeaders(),
        payload: payloadResult.payload,
      );
      try {
        final response = await fetchData(request);
        final statusCode = int.tryParse(response.status) ?? 0;
        if (statusCode < 200 || statusCode >= 300) {
          throw ApiStatusException(
            statusCode: statusCode,
            message: _buildApiErrorMessage(statusCode, response.data),
          );
        }
        var imageBytes = processResponse(response.data);
        // Add custom metadata
        if (payloadConfig.settings.metadataEraseEnabled) {
          final metadataString = payloadConfig.settings.customMetadataEnabled
              ? payloadConfig.settings.customMetadataContent
              : '';
          imageBytes = await embedMetadata(imageBytes, metadataString);
        }
        // Save image
        final filePrefix = payloadResult.suggestedFileName.isNotEmpty
            ? _getSafeFileName(payloadResult.suggestedFileName)
            : '';
        final fileName = [
          generateTimestampString(commandStatus.batchTimestamp),
          commandStatus.currentTotalCount.toString().padLeft(6, '0'),
          filePrefix,
          '${generateRandomString()}.png',
        ].join('-');
        await savePictureToFile(
          imageBytes,
          fileName,
          payloadConfig.settings.outputFolderPath,
        );
        final additionalInfo = digestPayloadResult(payloadResult);
        await _persistGeneratedResultToGallery(
          fileName: fileName,
          info: payloadResult.comment,
          additionalInfo: additionalInfo,
        );
        _hasPendingCachedPayloadRetry = false;
        _payloadResultCache.markSuccess();
        // Only increment total count after successful generation
        commandStatus.currentTotalCount++;
        await _persistResumeStateAfterSuccessfulGeneration();
        return InfoCardContent(
          title: fileName,
          info: payloadResult.comment,
          additionalInfo: additionalInfo,
          contentOrderText: payloadResult.contentOrderText,
          imageBytes: imageBytes,
        );
      } catch (e) {
        _hasPendingCachedPayloadRetry = true;
        _pendingFastRetry429 = e is ApiStatusException &&
            e.statusCode == 429 &&
            payloadConfig.settings.retryOn429Enabled;
        return InfoCardContent(
          title: 'Error occurred in generation process.',
          info: e.toString(),
          additionalInfo: digestPayloadResult(payloadResult),
          contentOrderText: payloadResult.contentOrderText,
        );
      }
    }

    // Create command and attach post-command operations
    final command = Command.createAsyncNoParam(
      commandFunc,
      initialValue: InfoCardContent.fromEmpty(),
    );
    command.isExecuting.addListener(() {
      notifyListeners();
      // Only update after execution
      if (command.isExecuting.value) return;
      if (!commandStatus.isBatchActive.value) return;

      commandStatus.currentBatchCount++;
      if (commandStatus.currentTotalCount >=
              payloadConfig.settings.numberOfRequests &&
          payloadConfig.settings.numberOfRequests != 0) {
        stopBatch(clearPendingResume: true);
        return;
      }
      if (_shouldStopAtEndBatchResolution) {
        stopBatch();
        _addSystemMessageCard(
          title: tr('batch_resolution_end_title'),
          message: tr('batch_resolution_end_message'),
        );
        return;
      }
      if (_pendingFastRetry429) {
        _pendingFastRetry429 = false;
        setCooldown(
          overrideSeconds: payloadConfig.settings.retryOn429DelaySec,
        );
        return;
      } else if (commandStatus.currentBatchCount >=
          payloadConfig.settings.batchCount) {
        setCooldown();
        return;
      } else {
        nextCommand();
      }
    });

    // Execute command
    currentCommand = command;
    addAndRunCommand(command);
  }

  void startBatch() {
    startBatchFromScratch();
  }

  void startBatchFromScratch() {
    unawaited(_startBatchWithCurrentConfig(initialTotalCount: 0));
  }

  void resumeBatchFromLast() {
    final startNumber =
        payloadConfig.generationRuntimeState.resumeCompletedCount + 1;
    resumeBatchFromNumber(startNumber);
  }

  void resumeBatchFromNumber(int startNumber) {
    if (startNumber <= 0) {
      return;
    }
    final finiteTarget = payloadConfig.settings.numberOfRequests;
    if (finiteTarget != 0 && startNumber > finiteTarget) {
      return;
    }
    unawaited(
      _startBatchWithCurrentConfig(
        initialTotalCount: max(0, startNumber - 1),
        batchTimestamp: payloadConfig.generationRuntimeState.resumeStartedAt,
      ),
    );
  }

  Future<void> _startBatchWithCurrentConfig({
    required int initialTotalCount,
    DateTime? batchTimestamp,
  }) async {
    _payloadResultCache.reset();
    _hasPendingCachedPayloadRetry = false;
    _pendingFastRetry429 = false;
    _cooldownGeneration++;
    commandStatus.isCoolingDown.value = false;

    _prepareBatchStartState(initialTotalCount);

    if (_isBatchResolutionEnabled &&
        payloadConfig.paramConfig.parseBatchResolutions().isEmpty) {
      commandStatus.isBatchActive.value = false;
      _addSystemMessageCard(
        title: tr('batch_resolution_invalid_title'),
        message: tr('batch_resolution_invalid_message'),
      );
      return;
    }

    commandStatus.currentBatchCount = 0;
    commandStatus.currentTotalCount = initialTotalCount;
    commandStatus.isBatchActive.value = true;
    commandStatus.batchTimestamp = batchTimestamp ?? DateTime.now();
    if (_shouldPersistPendingBatchResume) {
      await _savePendingBatchResumeStateAsync();
    }
    if (!commandStatus.isBatchActive.value) return;
    nextCommand();
  }

  void _prepareBatchStartState(int completedCount) {
    payloadConfig.resetPromptSelectionState();
    payloadConfig.paramConfig.resetBatchResolutionCursor();
    _generatedBatchResolutionCount = 0;

    if (completedCount <= 0) {
      return;
    }

    _primePromptSelectionState(completedCount);
    _primeBatchResolutionState(completedCount);
  }

  void _primePromptSelectionState(int completedCount) {
    final paramConfig = payloadConfig.paramConfig;
    final originalBatchResolutionEnabled = paramConfig.enableBatchResolution;
    paramConfig.enableBatchResolution = false;
    try {
      for (var i = 0; i < completedCount; i++) {
        generatePayloadResult();
      }
    } finally {
      paramConfig.enableBatchResolution = originalBatchResolutionEnabled;
    }
  }

  void _primeBatchResolutionState(int completedCount) {
    if (!_isBatchResolutionEnabled || completedCount <= 0) {
      return;
    }

    if (_isStopAtEndBatchResolution) {
      final resolutionCount =
          payloadConfig.paramConfig.parseBatchResolutions().length;
      _generatedBatchResolutionCount = min(completedCount, resolutionCount);
      return;
    }

    for (var i = 0; i < completedCount; i++) {
      payloadConfig.paramConfig.takeBatchResolution();
    }
  }

  void stopBatch({bool clearPendingResume = false}) {
    _cooldownGeneration++;
    commandStatus.isBatchActive.value = false;
    commandStatus.isCoolingDown.value = false;
    _payloadResultCache.reset();
    _generatedBatchResolutionCount = 0;
    _hasPendingCachedPayloadRetry = false;
    _pendingFastRetry429 = false;
    if (clearPendingResume) {
      _clearPendingBatchResumeState();
    } else if (_shouldPersistPendingBatchResume) {
      _savePendingBatchResumeState();
    }
  }

  void setCooldown({int? overrideSeconds}) {
    final cooldownGeneration = ++_cooldownGeneration;
    commandStatus.isCoolingDown.value = true;
    final cooldownSeconds = overrideSeconds ?? computeCooldownSeconds();
    scheduleCooldown(
      Duration(seconds: cooldownSeconds),
      () {
        if (_cooldownGeneration != cooldownGeneration) return;
        commandStatus.isCoolingDown.value = false;
        commandStatus.currentBatchCount = 0;
        nextCommand();
      },
    );
  }

  void toggleBatch() {
    if (commandStatus.isBatchActive.value) {
      stopBatch();
    } else {
      startBatchFromScratch();
    }
  }

  bool get _shouldPersistPendingBatchResume =>
      payloadConfig.settings.numberOfRequests != 0;

  bool get _hasReachedFiniteRequestTarget =>
      payloadConfig.settings.numberOfRequests != 0 &&
      commandStatus.currentTotalCount >=
          payloadConfig.settings.numberOfRequests;

  void _savePendingBatchResumeState() {
    final runtimeState = payloadConfig.generationRuntimeState;
    runtimeState.hasPendingBatchResume = true;
    runtimeState.resumeTargetTotalCount =
        payloadConfig.settings.numberOfRequests;
    runtimeState.resumeCompletedCount = commandStatus.currentTotalCount;
    runtimeState.resumeStartedAt = commandStatus.batchTimestamp;
    configService?.saveGenerationRuntimeState(runtimeState);
  }

  Future<void> _savePendingBatchResumeStateAsync() async {
    final runtimeState = payloadConfig.generationRuntimeState;
    runtimeState.hasPendingBatchResume = true;
    runtimeState.resumeTargetTotalCount =
        payloadConfig.settings.numberOfRequests;
    runtimeState.resumeCompletedCount = commandStatus.currentTotalCount;
    runtimeState.resumeStartedAt = commandStatus.batchTimestamp;
    final service = configService;
    if (service != null) {
      await service.saveGenerationRuntimeStateAsync(runtimeState);
    }
  }

  void _clearPendingBatchResumeState() {
    payloadConfig.generationRuntimeState.clearPendingBatchResume();
    configService?.saveGenerationRuntimeState(
      payloadConfig.generationRuntimeState,
    );
  }

  Future<void> _clearPendingBatchResumeStateAsync() async {
    payloadConfig.generationRuntimeState.clearPendingBatchResume();
    final service = configService;
    if (service != null) {
      await service.saveGenerationRuntimeStateAsync(
        payloadConfig.generationRuntimeState,
      );
    }
  }

  Future<void> _persistResumeStateAfterSuccessfulGeneration() async {
    try {
      if (_hasReachedFiniteRequestTarget) {
        await _clearPendingBatchResumeStateAsync();
      } else if (_shouldPersistPendingBatchResume) {
        await _savePendingBatchResumeStateAsync();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Best-effort generation runtime state persistence failed: $e',
        );
      }
    }
  }

  Future<void> _persistGeneratedResultToGallery({
    required String fileName,
    required String info,
    required Map<String, dynamic> additionalInfo,
  }) async {
    final service = galleryService;
    if (service == null) return;

    try {
      await service.saveSnapshot(
        config: payloadConfig,
        title: fileName,
        imagePath:
            _joinOutputPath(payloadConfig.settings.outputFolderPath, fileName),
        info: info,
        additionalInfo: additionalInfo,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Best-effort gallery persistence failed: $e');
      }
    }
  }

  /// Make PayloadResult readable for better visualization.
  Map<String, dynamic> digestPayloadResult(
      PayloadGenerationResult payloadResult) {
    // 明确将 payload 转换为可空动态类型
    final additionalInfo = Map<String, dynamic>.from(payloadResult.payload);

    // 使用 Map.from 确保 parameters 的类型为 Map<String, dynamic>
    final additionalInfoParam = Map<String, dynamic>.from(
      additionalInfo['parameters']! as Map,
    );

    // 移除不需要的键
    for (final key in [
      'reference_image_multiple',
      'reference_information_extracted_multiple',
      'reference_strength_multiple',
      'director_reference_images',
      'director_reference_strength_values',
      'director_reference_secondary_strength_values',
      'director_reference_information_extracted',
      'director_reference_descriptions',
    ]) {
      additionalInfoParam.remove(key);
    }

    additionalInfo.remove('parameters');

    // 合并时使用显式类型转换
    additionalInfo.addAll(additionalInfoParam.cast<String, dynamic>());

    return additionalInfo;
  }

  void clearCommandList() {
    // Remove finished commands in list
    commandList.removeWhere((command) => !command.isExecuting.value);
    notifyListeners();
  }

  String _getSafeFileName(String fileName) {
    String safeName = fileName.replaceAll(RegExp(r'[<>"/\\|?*{}\[\]]'), '');
    safeName = safeName.replaceAll(RegExp(r'[:]'), '_');
    return safeName.substring(0, min(200, safeName.length));
  }

  void setOverride(bool? value) {
    if (value == null) return;
    payloadConfig.useOverridePrompt = value;
    notifyListeners();
  }

  void setCharacterOverride(bool? value) {
    if (value == null) return;
    payloadConfig.useCharacterPromptWithOverride = value;
    notifyListeners();
  }

  void setOverridePrompt(String value) {
    payloadConfig.overridePrompt = value;
    notifyListeners();
  }

  void setUC(String value) {
    payloadConfig.paramConfig.negativePrompt = value;
    notifyListeners();
  }

  void _addSystemMessageCard({
    required String title,
    required String message,
  }) {
    commandFunc() async {
      return InfoCardContent(
        title: title,
        info: message,
        additionalInfo: const {},
      );
    }

    final command = Command.createAsyncNoParam(
      commandFunc,
      initialValue: InfoCardContent.fromEmpty(),
    );
    addAndRunCommand(command);
  }

  String _buildApiErrorMessage(int statusCode, Uint8List responseBytes) {
    final responseText =
        utf8.decode(responseBytes, allowMalformed: true).trim();
    if (responseText.isEmpty) {
      return 'API request failed with status $statusCode.';
    }

    final shortened = responseText.length > 800
        ? '${responseText.substring(0, 800)}...'
        : responseText;
    return 'API request failed with status $statusCode: $shortened';
  }

  String _joinOutputPath(String directory, String fileName) {
    if (directory.trim().isEmpty) {
      return fileName;
    }
    if (directory.endsWith('/') || directory.endsWith('\\')) {
      return '$directory$fileName';
    }
    return '$directory${Platform.pathSeparator}$fileName';
  }

  PayloadGenerationResult _generateBatchPayloadResult() {
    if (!_isStopAtEndBatchResolution) {
      return generatePayloadResult();
    }

    final resolutions = payloadConfig.paramConfig.parseBatchResolutions();
    if (_generatedBatchResolutionCount >= resolutions.length) {
      return generatePayloadResult();
    }

    final selectedResolution = resolutions[_generatedBatchResolutionCount];
    final originalEnableBatchResolution =
        payloadConfig.paramConfig.enableBatchResolution;
    final originalSizes = payloadConfig.paramConfig.sizes;
    payloadConfig.paramConfig.enableBatchResolution = false;
    payloadConfig.paramConfig.sizes = [
      GenerationSize(
        width: selectedResolution.width,
        height: selectedResolution.height,
      ),
    ];
    try {
      return generatePayloadResult();
    } finally {
      payloadConfig.paramConfig.enableBatchResolution =
          originalEnableBatchResolution;
      payloadConfig.paramConfig.sizes = originalSizes;
    }
  }
}
