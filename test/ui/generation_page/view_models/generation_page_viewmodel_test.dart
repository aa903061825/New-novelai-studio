import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/use_cases/generate_payload_use_case.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      strs: const ['unused'],
      prompts: const [],
    ),
    characterConfigList: [],
    savedPromptConfigList: [],
    paramConfig: ParamConfig(),
    settings: Settings(
      welcomeMessageVersion: '',
      apiKey: 'test-key',
      outputFolderPath: '',
      proxy: '',
      debugApiEnabled: false,
      debugApiPath: 'http://localhost',
      metadataEraseEnabled: false,
      customMetadataEnabled: false,
      customMetadataContent: '',
      batchCount: 999,
      batchIntervalSec: 1,
      numberOfRequests: 0,
      fileNamePrefixKey: '',
      generationPageColumnCount: 2,
      themeMode: 'system',
    ),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

PayloadGenerationResult _buildPayloadResult(String prompt) {
  return PayloadGenerationResult(
    comment: prompt,
    contentOrderText: null,
    suggestedFileName: prompt,
    payload: {
      'input': prompt,
      'model': 'nai-diffusion-4-curated-preview',
      'parameters': {
        'width': 832,
        'height': 1216,
      },
    },
  );
}

class _TestGenerationPageViewmodel extends GenerationPageViewmodel {
  _TestGenerationPageViewmodel({
    List<PayloadGenerationResult> payloadResults = const [],
    List<Object> responses = const [],
    this.nextRandomInt,
    this.fetchDataOverride,
    this.onNextCommand,
  })  : _payloadResults = Queue.of(payloadResults),
        _responses = Queue.of(responses);

  final Queue<PayloadGenerationResult> _payloadResults;
  final Queue<Object> _responses;
  final int Function(int upperBound)? nextRandomInt;
  final Future<ApiResponse> Function(ApiRequest request)? fetchDataOverride;
  final void Function()? onNextCommand;

  final List<Map<String, dynamic>> requestPayloads = [];
  final List<String> requestEndpoints = [];
  final List<String> requestProxies = [];
  final List<Map<String, String>> requestHeaders = [];
  final List<String> savedFileNames = [];
  final List<int> randomUpperBounds = [];

  int generatedPayloadCount = 0;
  int nextCommandCallCount = 0;
  Duration? lastScheduledCooldown;
  void Function()? lastCooldownCallback;

  @override
  PayloadGenerationResult generatePayloadResult() {
    generatedPayloadCount++;
    if (_payloadResults.isNotEmpty) {
      return _payloadResults.removeFirst();
    }
    return super.generatePayloadResult();
  }

  @override
  Future<ApiResponse> fetchData(ApiRequest request) async {
    requestEndpoints.add(request.endpoint);
    requestProxies.add(request.proxy);
    requestHeaders.add(Map<String, String>.from(request.headers));
    requestPayloads.add(Map<String, dynamic>.from(request.payload));
    final fetchDataOverride = this.fetchDataOverride;
    if (fetchDataOverride != null) {
      return fetchDataOverride(request);
    }
    final response = _responses.removeFirst();
    if (response is Exception) {
      throw response;
    }
    return response as ApiResponse;
  }

  @override
  Uint8List processResponse(Uint8List responseBytes) {
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> savePictureToFile(
    Uint8List bytes,
    String fileName,
    String saveDir,
  ) async {
    savedFileNames.add(fileName);
  }

  @override
  Future<String> resolvePictureSavePath(
    String fileName,
    String saveDir,
  ) async {
    final directory = saveDir.trim().isEmpty
        ? r'C:\Users\tester\Documents\nai-generated'
        : saveDir;
    return [directory, fileName].join(Platform.pathSeparator);
  }

  @override
  String generateTimestampString(DateTime time) => '20260504000000';

  @override
  String generateRandomString() => 'fixed1';

  @override
  int randomInt(int upperBound) {
    randomUpperBounds.add(upperBound);
    final nextRandomInt = this.nextRandomInt;
    if (nextRandomInt != null) {
      return nextRandomInt(upperBound);
    }
    return super.randomInt(upperBound);
  }

  @override
  void scheduleCooldown(Duration duration, void Function() callback) {
    lastScheduledCooldown = duration;
    lastCooldownCallback = callback;
  }

  @override
  void nextCommand() {
    nextCommandCallCount++;
    final onNextCommand = this.onNextCommand;
    if (onNextCommand != null) {
      onNextCommand();
      return;
    }
    super.nextCommand();
  }
}

class _FakeGalleryService extends StudioGalleryService {
  _FakeGalleryService() : super(workspaceService: WorkspaceService());

  String? lastTitle;
  String? lastImagePath;
  String? lastInfo;
  Map<String, dynamic>? lastAdditionalInfo;
  int saveSnapshotCallCount = 0;

  @override
  Future<StudioGalleryRecord> saveSnapshot({
    required PayloadConfig config,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> additionalInfo = const {},
    DateTime? createdAt,
    String? id,
  }) async {
    saveSnapshotCallCount++;
    lastTitle = title;
    lastImagePath = imagePath;
    lastInfo = info;
    lastAdditionalInfo = Map<String, dynamic>.from(additionalInfo);
    return StudioGalleryRecord.fromPayloadConfig(
      config: config,
      id: id ?? 'record-$saveSnapshotCallCount',
      createdAt: createdAt ?? DateTime.parse('2026-05-22T00:00:00Z'),
      title: title,
      imagePath: imagePath,
      info: info,
      additionalInfo: additionalInfo,
    );
  }
}

Future<void> _runSingleCommand(GenerationPageViewmodel viewmodel) async {
  viewmodel.commandStatus.isBatchActive.value = true;
  viewmodel.nextCommand();

  final command = viewmodel.currentCommand;
  expect(command, isNotNull);

  viewmodel.commandStatus.isBatchActive.value = false;

  while (command!.isExecutingSync.value || command.isExecuting.value) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(Duration.zero);
}

Future<void> _runActiveCommandAndWait(
  GenerationPageViewmodel viewmodel,
) async {
  viewmodel.commandStatus.isBatchActive.value = true;
  viewmodel.nextCommand();

  final command = viewmodel.currentCommand;
  expect(command, isNotNull);

  while (command!.isExecutingSync.value || command.isExecuting.value) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(Duration.zero);
}

Future<void> _waitForBatchToStop(GenerationPageViewmodel viewmodel) async {
  for (var i = 0; i < 1000; i++) {
    final command = viewmodel.currentCommand;
    final isExecuting = (command?.isExecutingSync.value ?? false) ||
        (command?.isExecuting.value ?? false);
    if (!viewmodel.commandStatus.isBatchActive.value &&
        !viewmodel.commandStatus.isCoolingDown.value &&
        !isExecuting) {
      await Future<void>.delayed(Duration.zero);
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }

  fail('Timed out waiting for batch to stop');
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test(
      'uses official NovelAI endpoint, API token, and HTTP proxy for generation',
      () async {
    final payloadConfig = GetIt.I<PayloadConfig>();
    payloadConfig.settings.apiKey = 'pst-novelai-token';
    payloadConfig.settings.proxy = '127.0.0.1:7890';
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('prompt-1'),
      ],
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );

    await _runSingleCommand(viewmodel);

    expect(
      viewmodel.requestEndpoints,
      ['https://image.novelai.net/ai/generate-image'],
    );
    expect(viewmodel.requestHeaders.single['authorization'],
        'Bearer pst-novelai-token');
    expect(viewmodel.requestProxies, ['127.0.0.1:7890']);
  });

  test('reuses the same payload after a failed nextCommand retry', () async {
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('prompt-1'),
        _buildPayloadResult('prompt-2'),
      ],
      responses: [
        Exception('request failed'),
        Exception('request failed again'),
      ],
    );

    await _runSingleCommand(viewmodel);
    await _runSingleCommand(viewmodel);

    expect(viewmodel.generatedPayloadCount, 1);
    expect(
      viewmodel.requestPayloads.map((payload) => payload['input']).toList(),
      ['prompt-1', 'prompt-1'],
    );
  });

  test('generates a new payload after a successful nextCommand', () async {
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('prompt-1'),
        _buildPayloadResult('prompt-2'),
      ],
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );

    await _runSingleCommand(viewmodel);
    await _runSingleCommand(viewmodel);

    expect(viewmodel.generatedPayloadCount, 2);
    expect(
      viewmodel.requestPayloads.map((payload) => payload['input']).toList(),
      ['prompt-1', 'prompt-2'],
    );
    expect(viewmodel.savedFileNames, hasLength(2));
  });

  test('successful generation saves a gallery record', () async {
    final payloadConfig = GetIt.I<PayloadConfig>();
    payloadConfig.settings.outputFolderPath = r'C:\outputs';
    final galleryService = _FakeGalleryService();
    GetIt.I.registerSingleton<StudioGalleryService>(galleryService);
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('gallery prompt'),
      ],
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );

    await _runSingleCommand(viewmodel);

    final expectedFileName = '20260504000000-000000-gallery prompt-fixed1.png';
    expect(galleryService.saveSnapshotCallCount, 1);
    expect(galleryService.lastTitle, expectedFileName);
    expect(
      galleryService.lastImagePath,
      ['C:\\outputs', expectedFileName].join(Platform.pathSeparator),
    );
    expect(galleryService.lastInfo, 'gallery prompt');
    expect(galleryService.lastAdditionalInfo?['input'], 'gallery prompt');
  });

  test('successful generation resolves the default gallery image path',
      () async {
    final galleryService = _FakeGalleryService();
    GetIt.I.registerSingleton<StudioGalleryService>(galleryService);
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('gallery prompt'),
      ],
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );

    await _runSingleCommand(viewmodel);

    final expectedFileName = '20260504000000-000000-gallery prompt-fixed1.png';
    expect(galleryService.saveSnapshotCallCount, 1);
    expect(
      galleryService.lastImagePath,
      [
        r'C:\Users\tester\Documents\nai-generated',
        expectedFileName,
      ].join(Platform.pathSeparator),
    );
  });

  test('stores content order text on generated homepage cards', () async {
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        PayloadGenerationResult(
          comment: 'prompt-1',
          contentOrderText: '2,5',
          suggestedFileName: 'prompt-1',
          payload: {
            'input': 'prompt-1',
            'model': 'nai-diffusion-4-curated-preview',
            'parameters': {
              'width': 832,
              'height': 1216,
            },
          },
        ),
      ],
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );

    await _runSingleCommand(viewmodel);

    final card = viewmodel.commandList.last.value;
    expect(card.contentOrderText, '2,5');
  });

  test('stopBatch clears a failed payload cache before restarting', () async {
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('prompt-1'),
        _buildPayloadResult('prompt-2'),
      ],
      responses: [
        Exception('request failed'),
        Exception('request failed after restart'),
      ],
    );

    await _runSingleCommand(viewmodel);
    viewmodel.stopBatch();
    await _runSingleCommand(viewmodel);

    expect(viewmodel.generatedPayloadCount, 2);
    expect(
      viewmodel.requestPayloads.map((payload) => payload['input']).toList(),
      ['prompt-1', 'prompt-2'],
    );
  });

  test(
    'stop_at_end retries the cached last batch resolution payload after failure',
    () async {
      final viewmodel = _TestGenerationPageViewmodel(
        responses: [
          ApiResponse(status: '200', data: Uint8List(0)),
          Exception('last resolution failed'),
          ApiResponse(status: '200', data: Uint8List(0)),
        ],
      );
      viewmodel.payloadConfig.paramConfig.enableBatchResolution = true;
      viewmodel.payloadConfig.paramConfig.batchResolutionMode = 'stop_at_end';
      viewmodel.payloadConfig.paramConfig.batchResolutionText = [
        '832x1216',
        '1024x1024',
      ].join('\n');

      viewmodel.startBatch();
      await _waitForBatchToStop(viewmodel);

      expect(viewmodel.generatedPayloadCount, 2);
      expect(
        viewmodel.requestPayloads
            .map(
              (payload) => [
                payload['parameters']['width'],
                payload['parameters']['height'],
              ],
            )
            .toList(),
        [
          [832, 1216],
          [1024, 1024],
          [1024, 1024],
        ],
      );
      expect(viewmodel.savedFileNames, hasLength(2));
    },
  );

  test('setCooldown uses the base interval when jitter range is zero', () {
    final viewmodel = _TestGenerationPageViewmodel();
    viewmodel.payloadConfig.settings.batchIntervalSec = 30;
    viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 0;
    viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 0;

    viewmodel.setCooldown();

    expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 30));
  });

  test('stopBatch clears cooldown state', () {
    final viewmodel = _TestGenerationPageViewmodel();

    viewmodel.setCooldown();
    expect(viewmodel.commandStatus.isCoolingDown.value, isTrue);

    viewmodel.stopBatch();

    expect(viewmodel.commandStatus.isCoolingDown.value, isFalse);
  });

  test('stopBatch invalidates a pending cooldown callback', () {
    final viewmodel = _TestGenerationPageViewmodel();

    viewmodel.commandStatus.currentBatchCount = 4;
    viewmodel.setCooldown();

    final callback = viewmodel.lastCooldownCallback;
    expect(callback, isNotNull);

    viewmodel.stopBatch();
    viewmodel.commandStatus.currentBatchCount = 9;

    callback!.call();

    expect(viewmodel.commandStatus.currentBatchCount, 9);
    expect(viewmodel.commandStatus.isCoolingDown.value, isFalse);
  });

  test('startBatch invalidates a pending cooldown callback', () {
    final viewmodel = _TestGenerationPageViewmodel(
      onNextCommand: () {},
    );

    viewmodel.setCooldown();

    final callback = viewmodel.lastCooldownCallback;
    expect(callback, isNotNull);

    viewmodel.startBatch();
    viewmodel.commandStatus.currentBatchCount = 6;
    final nextCommandCountBeforeOldCallback = viewmodel.nextCommandCallCount;

    callback!.call();

    expect(viewmodel.commandStatus.currentBatchCount, 6);
    expect(viewmodel.commandStatus.isCoolingDown.value, isFalse);
    expect(viewmodel.nextCommandCallCount, nextCommandCountBeforeOldCallback);
  });

  test(
    'stopping during an in-flight command prevents cooldown progression when it completes',
    () async {
      final responseCompleter = Completer<ApiResponse>();
      final viewmodel = _TestGenerationPageViewmodel(
        payloadResults: [_buildPayloadResult('prompt-1')],
        fetchDataOverride: (_) => responseCompleter.future,
      );
      viewmodel.payloadConfig.settings.batchCount = 1;
      viewmodel.commandStatus.isBatchActive.value = true;

      viewmodel.nextCommand();

      final command = viewmodel.currentCommand;
      expect(command, isNotNull);

      viewmodel.stopBatch();
      responseCompleter
          .complete(ApiResponse(status: '200', data: Uint8List(0)));

      while (command!.isExecutingSync.value || command.isExecuting.value) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);

      expect(viewmodel.commandStatus.currentBatchCount, 0);
      expect(viewmodel.commandStatus.isCoolingDown.value, isFalse);
      expect(viewmodel.lastScheduledCooldown, isNull);
    },
  );

  test('setCooldown can sample the minimum jitter endpoint', () {
    final viewmodel = _TestGenerationPageViewmodel(
      nextRandomInt: (upperBound) => 0,
    );
    viewmodel.payloadConfig.settings.batchIntervalSec = 30;
    viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 10;
    viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 20;

    viewmodel.setCooldown();

    expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 40));
    expect(viewmodel.randomUpperBounds, [11]);
  });

  test('setCooldown can sample the maximum jitter endpoint', () {
    final viewmodel = _TestGenerationPageViewmodel(
      nextRandomInt: (upperBound) => upperBound - 1,
    );
    viewmodel.payloadConfig.settings.batchIntervalSec = 30;
    viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 10;
    viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 20;

    viewmodel.setCooldown();

    expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 50));
    expect(viewmodel.randomUpperBounds, [11]);
  });

  test('setCooldown adds jitter within the configured range', () {
    final viewmodel = _TestGenerationPageViewmodel(
      nextRandomInt: (upperBound) => 7,
    );
    viewmodel.payloadConfig.settings.batchIntervalSec = 30;
    viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 10;
    viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 20;

    viewmodel.setCooldown();

    expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 47));
    expect(viewmodel.randomUpperBounds, [11]);
  });

  test('setCooldown sorts an inverted jitter range before sampling', () {
    final viewmodel = _TestGenerationPageViewmodel(
      nextRandomInt: (upperBound) => 5,
    );
    viewmodel.payloadConfig.settings.batchIntervalSec = 30;
    viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 20;
    viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 10;

    viewmodel.setCooldown();

    expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 45));
    expect(viewmodel.randomUpperBounds, [11]);
  });

  test('429 uses configured fast retry cooldown when enabled', () async {
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('prompt-1'),
        _buildPayloadResult('prompt-2'),
      ],
      responses: [
        ApiResponse(status: '429', data: Uint8List(0)),
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );
    viewmodel.payloadConfig.settings.retryOn429Enabled = true;
    viewmodel.payloadConfig.settings.retryOn429DelaySec = 12;
    viewmodel.payloadConfig.settings.batchCount = 1;
    viewmodel.payloadConfig.settings.numberOfRequests = 1;
    await _runActiveCommandAndWait(viewmodel);

    expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 12));
    expect(viewmodel.generatedPayloadCount, 1);

    final callback = viewmodel.lastCooldownCallback;
    expect(callback, isNotNull);
    viewmodel.commandStatus.isBatchActive.value = true;
    callback!.call();

    await _waitForBatchToStop(viewmodel);

    expect(viewmodel.generatedPayloadCount, 1);
    expect(
      viewmodel.requestPayloads.map((payload) => payload['input']).toList(),
      ['prompt-1', 'prompt-1'],
    );
    expect(viewmodel.savedFileNames, hasLength(1));
  });

  test('429 falls back to normal cooldown when fast retry is disabled',
      () async {
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [
        _buildPayloadResult('prompt-1'),
      ],
      responses: [
        ApiResponse(status: '429', data: Uint8List(0)),
      ],
    );
    viewmodel.payloadConfig.settings.retryOn429Enabled = false;
    viewmodel.payloadConfig.settings.batchCount = 1;
    viewmodel.payloadConfig.settings.batchIntervalSec = 30;
    viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 0;
    viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 0;
    await _runActiveCommandAndWait(viewmodel);

    expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 30));
  });
}
