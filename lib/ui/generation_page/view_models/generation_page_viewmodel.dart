import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_command/flutter_command.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/models/command_status.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/i2i_config.dart';
import 'package:novel_studio/data/models/info_card_content.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/data/services/nai_account_usage_service.dart';
import 'package:novel_studio/data/services/vibe_encoding_service.dart';
import 'package:novel_studio/data/studio/models/generation_payload_document.dart';
import 'package:novel_studio/data/studio/models/studio_director_tool.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/services/studio_director_tool_service.dart';
import 'package:novel_studio/data/studio/services/studio_image_operation_service.dart';
import 'package:novel_studio/ui/generation_page/models/generation_payload_cache.dart';
import 'package:novel_studio/data/services/api_service.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/services/image_service.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/use_cases/generate_payload_use_case.dart';

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

class _GallerySourceImage {
  final String path;
  final String imageB64;
  final int width;
  final int height;

  const _GallerySourceImage({
    required this.path,
    required this.imageB64,
    required this.width,
    required this.height,
  });
}

class GenerationPageViewmodel extends ChangeNotifier {
  final PayloadConfig? _payloadConfig;
  final CommandStatus? _commandStatus;
  final ConfigService? _configService;
  final StudioGalleryService? _galleryService;
  final NaiAccountUsageService? _naiAccountUsageService;

  GenerationPageViewmodel({
    PayloadConfig? payloadConfig,
    CommandStatus? commandStatus,
    ConfigService? configService,
    StudioGalleryService? galleryService,
    NaiAccountUsageService? naiAccountUsageService,
  })  : _payloadConfig = payloadConfig,
        _commandStatus = commandStatus,
        _configService = configService,
        _galleryService = galleryService,
        _naiAccountUsageService = naiAccountUsageService;

  PayloadConfig get payloadConfig => _payloadConfig ?? GetIt.I<PayloadConfig>();
  CommandStatus get commandStatus => _commandStatus ?? GetIt.I<CommandStatus>();
  ConfigService? get configService =>
      _configService ??
      (GetIt.I.isRegistered<ConfigService>() ? GetIt.I<ConfigService>() : null);
  StudioGalleryService? get galleryService =>
      _galleryService ??
      (GetIt.I.isRegistered<StudioGalleryService>()
          ? GetIt.I<StudioGalleryService>()
          : null);
  NaiAccountUsageService? get naiAccountUsageService => _naiAccountUsageService;
  List<Command<void, InfoCardContent>> get commandList =>
      commandStatus.commandList;
  int get colNum => payloadConfig.settings.generationPageColumnCount;

  bool get isV5OpusUsageExhausted {
    final capabilities =
        GenerationModelCapabilities.fromModel(payloadConfig.paramConfig.model);
    final snapshot = naiAccountUsageService?.snapshot;
    return capabilities.isV5 &&
        snapshot?.isOpus == true &&
        snapshot?.opusUsage?.isNegative == true;
  }

  Future<void> refreshNaiAccountUsage() async {
    if (!GenerationModelCapabilities.fromModel(payloadConfig.paramConfig.model)
        .isV5) {
      return;
    }
    await naiAccountUsageService?.refresh(
      generationEndpoint: payloadConfig.settings.imageGenerationEndpoint,
      proxy: payloadConfig.settings.proxy,
      headers: payloadConfig.getHeaders(),
    );
  }

  Command<void, InfoCardContent>? currentCommand;
  int _cooldownGeneration = 0;
  int _generatedBatchResolutionCount = 0;
  bool _hasPendingCachedPayloadRetry = false;
  bool _pendingFastRetry429 = false;
  bool _stopBatchOnGenerationFailure = false;
  bool _currentCommandFailed = false;
  bool _useGlobalGenerationParamsForBatch = true;
  bool _useBatchResolutionForBatch = true;

  final GenerationPayloadCache<PayloadGenerationResult> _payloadResultCache =
      GenerationPayloadCache<PayloadGenerationResult>();

  bool get _isBatchResolutionEnabled =>
      _useBatchResolutionForBatch &&
      payloadConfig.paramConfig.enableBatchResolution;

  bool get _isStopAtEndBatchResolution =>
      _isBatchResolutionEnabled &&
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
    return GeneratePayloadUseCase(
      payloadConfig: payloadConfig,
      useGlobalGenerationParams: _useGlobalGenerationParamsForBatch,
      useBatchResolution: _useBatchResolutionForBatch,
    )();
  }

  @protected
  Future<ApiResponse> fetchData(ApiRequest request) {
    return ApiService().fetchData(request);
  }

  @protected
  Future<int> prepareVibesForGeneration() async {
    final model = payloadConfig.paramConfig.model;
    if (!_shouldPrepareVibes) {
      return 0;
    }
    final vibes = payloadConfig.vibeConfigListV4
        .where(
          (vibe) =>
              vibe.vibeB64.trim().isNotEmpty ||
              VibeEncodingService.hasSourceImage(vibe),
        )
        .toList(growable: false);
    if (vibes.isEmpty) return 0;

    final encodedCount = await VibeEncodingService(
      fetchData: fetchData,
    ).prepareForGeneration(
      vibes: vibes,
      model: model,
      generationEndpoint: payloadConfig.settings.imageGenerationEndpoint,
      proxy: payloadConfig.settings.proxy,
      headers: payloadConfig.getHeaders(),
    );
    if (encodedCount > 0) {
      await configService?.saveConfig(payloadConfig.toJson());
      notifyListeners();
    }
    return encodedCount;
  }

  bool get _hasPendingVibePreparation {
    final model = payloadConfig.paramConfig.model;
    if (!_shouldPrepareVibes) {
      return false;
    }
    for (final vibe in payloadConfig.vibeConfigListV4) {
      final encoding = vibe.encodingFor(model, vibe.infoExtracted);
      if (encoding == null || encoding != vibe.vibeB64) {
        return true;
      }
    }
    return false;
  }

  bool get _shouldPrepareVibes {
    final model = payloadConfig.paramConfig.model;
    final capabilities = GenerationModelCapabilities.fromModel(model);
    if (!payloadConfig.generationRuntimeState.vibeEnabled ||
        !capabilities.isV4 ||
        !capabilities.supportsVibeTransfer) {
      return false;
    }
    final preciseReferenceActive = payloadConfig.usePreciseReference &&
        capabilities.supportsPreciseReference &&
        payloadConfig.preciseReferenceList.isNotEmpty;
    return !preciseReferenceActive;
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
  Future<String> resolvePictureSavePath(
    String fileName,
    String saveDir,
  ) {
    return FileService().resolvePictureSavePath(fileName, saveDir);
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

  void notifyConfigChanged() {
    notifyListeners();
  }

  Future<void> enhanceGalleryRecord(StudioGalleryRecord record) async {
    final source = await _readGallerySourceImage(record);
    final strength = payloadConfig.i2iConfig.strength.clamp(0.0, 1.0);
    final noise = payloadConfig.i2iConfig.noise.clamp(0.0, 1.0);
    final payloadResult =
        const StudioImageOperationService().buildEnhancePayload(
      payloadConfig: payloadConfig,
      sourceImageB64: source.imageB64,
      strength: strength,
      noise: noise,
    );
    final request = ApiRequest(
      endpoint: payloadConfig.settings.imageGenerationEndpoint,
      proxy: payloadConfig.settings.proxy,
      headers: payloadConfig.getHeaders(),
      payload: payloadResult.payload,
    );
    final response = await fetchData(request);
    final statusCode = int.tryParse(response.status) ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiStatusException(
        statusCode: statusCode,
        message: _buildApiErrorMessage(statusCode, response.data),
      );
    }
    var imageBytes = processResponse(response.data);
    if (payloadConfig.settings.metadataEraseEnabled) {
      final metadataString = payloadConfig.settings.customMetadataEnabled
          ? payloadConfig.settings.customMetadataContent
          : '';
      imageBytes = await embedMetadata(imageBytes, metadataString);
    }

    final sourceTitle = record.title.trim().isEmpty ? record.id : record.title;
    final filePrefix = _getSafeFileName('enhance-$sourceTitle');
    final fileName = [
      generateTimestampString(DateTime.now()),
      filePrefix,
      '${generateRandomString()}.png',
    ].where((part) => part.trim().isNotEmpty).join('-');
    await savePictureToFile(
      imageBytes,
      fileName,
      payloadConfig.settings.outputFolderPath,
    );
    final imagePath = await resolvePictureSavePath(
      fileName,
      payloadConfig.settings.outputFolderPath,
    );
    final additionalInfo = digestPayloadResult(payloadResult);
    await galleryService?.saveOperationSnapshot(
      config: payloadConfig,
      operation: StudioGalleryOperation.enhance,
      sourceRecordId: record.id,
      sourceImagePath: source.path,
      title: fileName,
      imagePath: imagePath,
      info: payloadResult.comment,
      additionalInfo: additionalInfo,
      parameters: {
        'strength': strength,
        'noise': noise,
        'source_width': source.width,
        'source_height': source.height,
      },
    );
    final content = InfoCardContent(
      title: fileName,
      info: payloadResult.comment,
      additionalInfo: additionalInfo,
      contentOrderText: payloadResult.contentOrderText,
      imageBytes: imageBytes,
      imagePath: imagePath,
    );
    commandList.add(
      Command.createSyncNoParam<InfoCardContent>(
        () => content,
        initialValue: content,
      ),
    );
    notifyListeners();
  }

  Future<void> upscaleGalleryRecord(StudioGalleryRecord record) async {
    final source = await _readGallerySourceImage(record);
    final validation = const StudioImageOperationService()
        .validateUpscaleSource(width: source.width, height: source.height);
    if (!validation.isValid) {
      throw StateError(validation.message ?? 'Upscale source is invalid.');
    }
    throw UnsupportedError(
      'Upscale execution is pending official API contract confirmation.',
    );
  }

  Future<void> runDirectorToolGalleryRecord(
    StudioGalleryRecord record,
    StudioDirectorToolOptions options,
  ) async {
    final source = await _readGallerySourceImage(record);
    final request = const StudioDirectorToolService().buildRequest(
      config: payloadConfig,
      sourceImageB64: source.imageB64,
      sourceWidth: source.width,
      sourceHeight: source.height,
      options: options,
    );
    final response = await fetchData(request);
    final statusCode = int.tryParse(response.status) ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiStatusException(
        statusCode: statusCode,
        message: _buildApiErrorMessage(statusCode, response.data),
      );
    }

    final resultImages =
        const StudioDirectorToolService().decodeResultImages(response.data);
    final sourceTitle = record.title.trim().isEmpty ? record.id : record.title;
    final baseAdditionalInfo = Map<String, dynamic>.from(request.payload)
      ..remove('image');
    final info = _directorToolInfo(options);
    for (final resultImage in resultImages) {
      var imageBytes = resultImage.bytes;
      if (payloadConfig.settings.metadataEraseEnabled) {
        final metadataString = payloadConfig.settings.customMetadataEnabled
            ? payloadConfig.settings.customMetadataContent
            : '';
        imageBytes = await embedMetadata(imageBytes, metadataString);
      }

      final filePrefix = _getSafeFileName(
        'director-${options.tool.requestType}-${resultImage.variantName}-$sourceTitle',
      );
      final fileName = [
        generateTimestampString(DateTime.now()),
        filePrefix,
        '${generateRandomString()}.png',
      ].where((part) => part.trim().isNotEmpty).join('-');
      await savePictureToFile(
        imageBytes,
        fileName,
        payloadConfig.settings.outputFolderPath,
      );
      final imagePath = await resolvePictureSavePath(
        fileName,
        payloadConfig.settings.outputFolderPath,
      );
      final additionalInfo = Map<String, dynamic>.from(baseAdditionalInfo)
        ..['variant_index'] = resultImage.variantIndex
        ..['variant_name'] = resultImage.variantName;
      final parameters = options.toLineageParameters(
        sourceWidth: source.width,
        sourceHeight: source.height,
      )
        ..['variant_index'] = resultImage.variantIndex
        ..['variant_name'] = resultImage.variantName;
      await galleryService?.saveOperationSnapshot(
        config: payloadConfig,
        operation: StudioGalleryOperation.directorTool,
        sourceRecordId: record.id,
        sourceImagePath: source.path,
        title: fileName,
        imagePath: imagePath,
        info: info,
        additionalInfo: additionalInfo,
        parameters: parameters,
      );
      final content = InfoCardContent(
        title: fileName,
        info: info,
        additionalInfo: additionalInfo,
        imageBytes: imageBytes,
        imagePath: imagePath,
      );
      commandList.add(
        Command.createSyncNoParam<InfoCardContent>(
          () => content,
          initialValue: content,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> runInpaintGalleryRecord(
    StudioGalleryRecord record, {
    required String maskImagePath,
    double strength = 1.0,
  }) async {
    final source = await _readGallerySourceImage(record);
    final mask = await _readImageFile(maskImagePath, 'Inpaint mask image');
    final payloadResult =
        const StudioImageOperationService().buildInpaintPayload(
      payloadConfig: payloadConfig,
      sourceImageB64: source.imageB64,
      sourceWidth: source.width,
      sourceHeight: source.height,
      maskImageB64: mask.imageB64,
      maskWidth: mask.width,
      maskHeight: mask.height,
      strength: strength,
    );
    final request = ApiRequest(
      endpoint: payloadConfig.settings.imageGenerationEndpoint,
      proxy: payloadConfig.settings.proxy,
      headers: payloadConfig.getHeaders(),
      payload: payloadResult.payload,
    );
    final response = await fetchData(request);
    final statusCode = int.tryParse(response.status) ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiStatusException(
        statusCode: statusCode,
        message: _buildApiErrorMessage(statusCode, response.data),
      );
    }

    var imageBytes = processResponse(response.data);
    if (payloadConfig.settings.metadataEraseEnabled) {
      final metadataString = payloadConfig.settings.customMetadataEnabled
          ? payloadConfig.settings.customMetadataContent
          : '';
      imageBytes = await embedMetadata(imageBytes, metadataString);
    }

    final sourceTitle = record.title.trim().isEmpty ? record.id : record.title;
    final filePrefix = _getSafeFileName('inpaint-$sourceTitle');
    final fileName = [
      generateTimestampString(DateTime.now()),
      filePrefix,
      '${generateRandomString()}.png',
    ].where((part) => part.trim().isNotEmpty).join('-');
    await savePictureToFile(
      imageBytes,
      fileName,
      payloadConfig.settings.outputFolderPath,
    );
    final imagePath = await resolvePictureSavePath(
      fileName,
      payloadConfig.settings.outputFolderPath,
    );
    final additionalInfo = digestPayloadResult(payloadResult);
    final clampedStrength = strength.clamp(0.0, 1.0);
    await galleryService?.saveOperationSnapshot(
      config: payloadConfig,
      operation: StudioGalleryOperation.inpaint,
      sourceRecordId: record.id,
      sourceImagePath: source.path,
      title: fileName,
      imagePath: imagePath,
      info: payloadResult.comment,
      additionalInfo: additionalInfo,
      parameters: {
        'strength': clampedStrength,
        'source_width': source.width,
        'source_height': source.height,
        'mask_width': mask.width,
        'mask_height': mask.height,
        'mask_image_path': mask.path,
      },
    );
    final content = InfoCardContent(
      title: fileName,
      info: payloadResult.comment,
      additionalInfo: additionalInfo,
      contentOrderText: payloadResult.contentOrderText,
      imageBytes: imageBytes,
      imagePath: imagePath,
    );
    commandList.add(
      Command.createSyncNoParam<InfoCardContent>(
        () => content,
        initialValue: content,
      ),
    );
    notifyListeners();
  }

  String _directorToolInfo(StudioDirectorToolOptions options) {
    final prompt = options.prompt.trim();
    if (prompt.isEmpty) {
      return 'Director Tool: ${options.tool.requestType}';
    }
    return 'Director Tool: ${options.tool.requestType}\n$prompt';
  }

  Future<_GallerySourceImage> _readGallerySourceImage(
    StudioGalleryRecord record,
  ) async {
    final path = record.imagePath?.trim();
    if (path == null || path.isEmpty) {
      throw StateError('Gallery record does not have an image path.');
    }
    return _readImageFile(path, 'Gallery record image');
  }

  Future<_GallerySourceImage> _readImageFile(
    String path,
    String label,
  ) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('$label does not exist: $path');
    }
    final bytes = await file.readAsBytes();
    final i2iConfig = I2IConfig()..setImage(bytes);
    final imageB64 = i2iConfig.imageB64;
    if (imageB64 == null || imageB64.isEmpty) {
      throw StateError('$label could not be read: $path');
    }
    return _GallerySourceImage(
      path: file.path,
      imageB64: imageB64,
      width: i2iConfig.width,
      height: i2iConfig.height,
    );
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
    command.isExecuting.addListener(notifyListeners);
    notifyListeners();
    command();
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
      final endpoint = payloadConfig.settings.imageGenerationEndpoint;
      _currentCommandFailed = false;

      PayloadGenerationResult? payloadResult;
      try {
        var generatedNewPayload = false;
        payloadResult = _payloadResultCache.takeOrGenerate(() {
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
        final imagePath = await resolvePictureSavePath(
          fileName,
          payloadConfig.settings.outputFolderPath,
        );
        final additionalInfo = digestPayloadResult(payloadResult);
        await _persistGeneratedResultToGallery(
          fileName: fileName,
          imagePath: imagePath,
          info: payloadResult.comment,
          additionalInfo: additionalInfo,
        );
        _hasPendingCachedPayloadRetry = false;
        _payloadResultCache.markSuccess();
        // Only increment total count after successful generation
        commandStatus.currentTotalCount++;
        await _persistResumeStateAfterSuccessfulGeneration();
        unawaited(refreshNaiAccountUsage());
        return InfoCardContent(
          title: fileName,
          info: payloadResult.comment,
          additionalInfo: additionalInfo,
          contentOrderText: payloadResult.contentOrderText,
          imageBytes: imageBytes,
          imagePath: imagePath,
        );
      } catch (e) {
        _currentCommandFailed = true;
        _hasPendingCachedPayloadRetry = payloadResult != null;
        _pendingFastRetry429 = e is ApiStatusException &&
            e.statusCode == 429 &&
            payloadConfig.settings.retryOn429Enabled;
        return InfoCardContent(
          title: '生成失败',
          info: e.toString(),
          additionalInfo: payloadResult == null
              ? const {}
              : digestPayloadResult(payloadResult),
          contentOrderText: payloadResult?.contentOrderText,
        );
      }
    }

    // Create command and attach post-command operations
    final command = Command.createAsyncNoParam(
      commandFunc,
      initialValue: InfoCardContent.fromEmpty(),
    );
    command.isExecuting.addListener(() {
      // Only update after execution
      if (command.isExecuting.value) return;
      if (!commandStatus.isBatchActive.value) return;

      if (_currentCommandFailed && _stopBatchOnGenerationFailure) {
        stopBatch(clearPendingResume: true);
        return;
      }

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

  void startSingleImageGeneration({int count = 1}) {
    final requestCount = max(1, count);
    payloadConfig.settings.numberOfRequests = requestCount;
    payloadConfig.settings.batchCount = requestCount;
    startBatchFromScratch(
      stopOnFailure: true,
      useGlobalGenerationParams: false,
      useBatchResolution: false,
    );
  }

  void startBatchFromScratch({
    bool stopOnFailure = false,
    bool useGlobalGenerationParams = true,
    bool useBatchResolution = true,
  }) {
    _stopBatchOnGenerationFailure = stopOnFailure;
    _useGlobalGenerationParamsForBatch = useGlobalGenerationParams;
    _useBatchResolutionForBatch = useBatchResolution;
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
    _stopBatchOnGenerationFailure = false;
    _useGlobalGenerationParamsForBatch = true;
    _useBatchResolutionForBatch = true;
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

    if (_hasPendingVibePreparation) {
      try {
        await prepareVibesForGeneration();
      } catch (error) {
        commandStatus.isBatchActive.value = false;
        _addSystemMessageCard(
          title: 'Vibe 编码失败',
          message: error.toString(),
        );
        return;
      }
    }

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
    _stopBatchOnGenerationFailure = false;
    _currentCommandFailed = false;
    _useGlobalGenerationParamsForBatch = true;
    _useBatchResolutionForBatch = true;
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
    required String imagePath,
    required String info,
    required Map<String, dynamic> additionalInfo,
  }) async {
    final service = galleryService;
    if (service == null) return;

    try {
      await service.saveSnapshot(
        config: payloadConfig,
        title: fileName,
        imagePath: imagePath,
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
    final additionalInfo = Map<String, dynamic>.from(payloadResult.payload);
    final document = GenerationPayloadDocument.fromMap(additionalInfo);
    final additionalInfoParam = Map<String, dynamic>.from(
      document.parameters,
    );

    for (final key in [
      'reference_image_multiple',
      'reference_information_extracted_multiple',
      'reference_strength_multiple',
      'director_reference_images',
      'director_reference_strength_values',
      'director_reference_secondary_strength_values',
      'director_reference_information_extracted',
      'director_reference_descriptions',
      'image',
      'mask',
    ]) {
      additionalInfoParam.remove(key);
    }

    additionalInfo['input'] = document.positivePrompt;
    additionalInfo['negativePrompt'] = document.negativePrompt;
    additionalInfo.remove('parameters');
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
