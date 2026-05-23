import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/use_cases/generate_payload_use_case.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';

PayloadConfig _buildPayloadConfig({
  int numberOfRequests = 3,
  GenerationRuntimeState? generationRuntimeState,
}) {
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
      numberOfRequests: numberOfRequests,
      fileNamePrefixKey: '',
      generationPageColumnCount: 2,
      themeMode: 'system',
    ),
    generationRuntimeState: generationRuntimeState,
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

PayloadConfig _buildSequentialPayloadConfig({
  int numberOfRequests = 3,
  GenerationRuntimeState? generationRuntimeState,
  int repeatCount = 1,
}) {
  final payloadConfig = _buildPayloadConfig(
    numberOfRequests: numberOfRequests,
    generationRuntimeState: generationRuntimeState,
  );
  payloadConfig.rootPromptConfig = PromptConfig(
    selectionMethod: 'single_sequential',
    shuffled: false,
    num: repeatCount,
    type: 'str',
    comment: 'root',
    strs: const ['prompt-1', 'prompt-2', 'prompt-3'],
    prompts: const [],
  );
  payloadConfig.paramConfig.randomSeed = false;
  payloadConfig.paramConfig.seed = 12345;
  return payloadConfig;
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

class _FakeConfigService extends ConfigService {
  int saveGenerationRuntimeStateCallCount = 0;
  int saveGenerationRuntimeStateAsyncCallCount = 0;
  GenerationRuntimeState? lastSavedState;
  int? throwOnAsyncSaveCall;

  @override
  void saveGenerationRuntimeState(GenerationRuntimeState state) {
    saveGenerationRuntimeStateCallCount++;
    lastSavedState = GenerationRuntimeState.fromJson(state.toJson());
  }

  @override
  Future<void> saveGenerationRuntimeStateAsync(
    GenerationRuntimeState state,
  ) async {
    saveGenerationRuntimeStateAsyncCallCount++;
    lastSavedState = GenerationRuntimeState.fromJson(state.toJson());
    if (throwOnAsyncSaveCall == saveGenerationRuntimeStateAsyncCallCount) {
      throw Exception('runtime state persistence failed');
    }
  }
}

class _TestGenerationPageViewmodel extends GenerationPageViewmodel {
  _TestGenerationPageViewmodel({
    List<PayloadGenerationResult> payloadResults = const [],
    List<Object> responses = const [],
    this.onNextCommand,
    this.fetchDataOverride,
  })  : _payloadResults = Queue.of(payloadResults),
        _responses = Queue.of(responses);

  final Queue<PayloadGenerationResult> _payloadResults;
  final Queue<Object> _responses;
  final void Function()? onNextCommand;
  final Future<ApiResponse> Function(ApiRequest request)? fetchDataOverride;

  @override
  PayloadGenerationResult generatePayloadResult() {
    if (_payloadResults.isNotEmpty) {
      return _payloadResults.removeFirst();
    }
    return super.generatePayloadResult();
  }

  @override
  Future<ApiResponse> fetchData(ApiRequest request) async {
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
  ) async {}

  @override
  String generateTimestampString(DateTime time) => '20260504000000';

  @override
  String generateRandomString() => 'fixed1';

  @override
  void scheduleCooldown(Duration duration, void Function() callback) {
    lastScheduledCooldown = duration;
    lastCooldownCallback = callback;
  }

  Duration? lastScheduledCooldown;
  void Function()? lastCooldownCallback;

  @override
  void nextCommand() {
    final onNextCommand = this.onNextCommand;
    if (onNextCommand != null) {
      onNextCommand();
      return;
    }
    super.nextCommand();
  }
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

Future<void> _waitForCommandToStart(GenerationPageViewmodel viewmodel) async {
  for (var i = 0; i < 1000; i++) {
    if (viewmodel.currentCommand != null) {
      await Future<void>.delayed(Duration.zero);
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }

  fail('Timed out waiting for command to start');
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
    GetIt.I.registerSingleton<ConfigService>(_FakeConfigService());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('startBatchFromScratch ignores pending resume and resets total count',
      () {
    final payloadConfig = GetIt.I<PayloadConfig>();
    payloadConfig.settings.numberOfRequests = 7;
    payloadConfig.generationRuntimeState = GenerationRuntimeState(
      hasPendingBatchResume: true,
      resumeTargetTotalCount: 7,
      resumeCompletedCount: 4,
      resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
    );
    final commandStatus = GetIt.I<CommandStatus>();
    commandStatus.currentTotalCount = 99;
    final viewmodel = _TestGenerationPageViewmodel(
      onNextCommand: () {},
    );

    viewmodel.startBatchFromScratch();

    expect(commandStatus.currentTotalCount, 0);
    expect(payloadConfig.generationRuntimeState.hasPendingBatchResume, isTrue);
    expect(payloadConfig.generationRuntimeState.resumeTargetTotalCount, 7);
    expect(payloadConfig.generationRuntimeState.resumeCompletedCount, 0);
    expect(payloadConfig.generationRuntimeState.resumeStartedAt, isNotNull);
  });

  test('finite start persists pending resume state before first success', () {
    final payloadConfig = _buildPayloadConfig(numberOfRequests: 3);
    GetIt.I.unregister<PayloadConfig>();
    GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
    final configService = GetIt.I<ConfigService>() as _FakeConfigService;
    final viewmodel = _TestGenerationPageViewmodel(
      onNextCommand: () {},
    );

    viewmodel.startBatchFromScratch();

    expect(configService.saveGenerationRuntimeStateAsyncCallCount, 1);
    expect(configService.lastSavedState, isNotNull);
    expect(configService.lastSavedState!.hasPendingBatchResume, isTrue);
    expect(configService.lastSavedState!.resumeTargetTotalCount, 3);
    expect(configService.lastSavedState!.resumeCompletedCount, 0);
    expect(configService.lastSavedState!.resumeStartedAt, isNotNull);
  });

  test('stopBatch keeps pending resume after one successful image', () async {
    final payloadConfig = _buildPayloadConfig(numberOfRequests: 3);
    payloadConfig.settings.batchCount = 1;
    await GetIt.I.unregister<PayloadConfig>();
    GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
    final configService = GetIt.I<ConfigService>() as _FakeConfigService;
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [_buildPayloadResult('prompt-1')],
      responses: [ApiResponse(status: '200', data: Uint8List(0))],
    );

    viewmodel.startBatchFromScratch();
    await _waitForCommandToStart(viewmodel);
    final command = viewmodel.currentCommand;
    expect(command, isNotNull);
    while (command!.isExecutingSync.value || command.isExecuting.value) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    viewmodel.stopBatch();

    expect(payloadConfig.generationRuntimeState.hasPendingBatchResume, isTrue);
    expect(payloadConfig.generationRuntimeState.resumeTargetTotalCount, 3);
    expect(payloadConfig.generationRuntimeState.resumeCompletedCount, 1);
    expect(configService.lastSavedState, isNotNull);
    expect(configService.lastSavedState!.hasPendingBatchResume, isTrue);
  });

  test('resumeBatchFromNumber(2) initializes currentTotalCount to 1', () {
    final viewmodel = _TestGenerationPageViewmodel(
      onNextCommand: () {},
    );

    viewmodel.resumeBatchFromNumber(2);

    expect(viewmodel.commandStatus.currentTotalCount, 1);
  });

  test(
    'resumeBatchFromNumber does not start when input is zero or negative',
    () {
      var nextCommandCalls = 0;
      final viewmodel = _TestGenerationPageViewmodel(
        onNextCommand: () {
          nextCommandCalls++;
        },
      );

      viewmodel.resumeBatchFromNumber(0);
      viewmodel.resumeBatchFromNumber(-1);

      expect(nextCommandCalls, 0);
      expect(viewmodel.commandStatus.isBatchActive.value, isFalse);
      expect(viewmodel.currentCommand, isNull);
    },
  );

  test(
    'resumeBatchFromNumber does not start when finite start is beyond target',
    () {
      final payloadConfig = _buildPayloadConfig(numberOfRequests: 3);
      GetIt.I.unregister<PayloadConfig>();
      GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
      final configService = GetIt.I<ConfigService>() as _FakeConfigService;
      var nextCommandCalls = 0;
      final viewmodel = _TestGenerationPageViewmodel(
        onNextCommand: () {
          nextCommandCalls++;
        },
      );

      viewmodel.resumeBatchFromNumber(4);

      expect(nextCommandCalls, 0);
      expect(viewmodel.commandStatus.isBatchActive.value, isFalse);
      expect(viewmodel.currentCommand, isNull);
      expect(configService.saveGenerationRuntimeStateAsyncCallCount, 0);
    },
  );

  test('normal finite completion clears pending resume state', () async {
    final payloadConfig = _buildPayloadConfig(
      numberOfRequests: 2,
      generationRuntimeState: GenerationRuntimeState(
        hasPendingBatchResume: true,
        resumeTargetTotalCount: 2,
        resumeCompletedCount: 1,
        resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
      ),
    );
    await GetIt.I.unregister<PayloadConfig>();
    GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
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

    viewmodel.startBatchFromScratch();
    await _waitForBatchToStop(viewmodel);

    expect(payloadConfig.generationRuntimeState.hasPendingBatchResume, isFalse);
    expect(payloadConfig.generationRuntimeState.resumeTargetTotalCount, 0);
    expect(payloadConfig.generationRuntimeState.resumeCompletedCount, 0);
    expect(payloadConfig.generationRuntimeState.resumeStartedAt, isNull);
  });

  test(
    'successful in-flight request persists updated completed count after manual stop',
    () async {
      final payloadConfig = _buildPayloadConfig(numberOfRequests: 3);
      GetIt.I.unregister<PayloadConfig>();
      GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
      final configService = GetIt.I<ConfigService>() as _FakeConfigService;
      final responseCompleter = Completer<ApiResponse>();
      final viewmodel = _TestGenerationPageViewmodel(
        payloadResults: [_buildPayloadResult('prompt-1')],
        fetchDataOverride: (_) => responseCompleter.future,
      );

      viewmodel.startBatchFromScratch();
      await _waitForCommandToStart(viewmodel);
      final command = viewmodel.currentCommand;
      expect(command, isNotNull);

      viewmodel.stopBatch();
      responseCompleter
          .complete(ApiResponse(status: '200', data: Uint8List(0)));

      while (command!.isExecutingSync.value || command.isExecuting.value) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);

      expect(
          payloadConfig.generationRuntimeState.hasPendingBatchResume, isTrue);
      expect(payloadConfig.generationRuntimeState.resumeCompletedCount, 1);
      expect(configService.lastSavedState, isNotNull);
      expect(configService.lastSavedState!.hasPendingBatchResume, isTrue);
      expect(configService.lastSavedState!.resumeCompletedCount, 1);
    },
  );

  test(
    'persistence failure after image save keeps the command successful',
    () async {
      final payloadConfig = _buildPayloadConfig(numberOfRequests: 3);
      payloadConfig.settings.batchCount = 1;
      await GetIt.I.unregister<PayloadConfig>();
      GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
      final configService = GetIt.I<ConfigService>() as _FakeConfigService;
      configService.throwOnAsyncSaveCall = 2;
      final viewmodel = _TestGenerationPageViewmodel(
        payloadResults: [_buildPayloadResult('prompt-1')],
        responses: [ApiResponse(status: '200', data: Uint8List(0))],
      );

      viewmodel.startBatchFromScratch();
      await _waitForCommandToStart(viewmodel);
      final command = viewmodel.currentCommand;
      expect(command, isNotNull);
      while (command!.isExecutingSync.value || command.isExecuting.value) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);

      final card = viewmodel.commandList.last.value;
      expect(card.title, isNot('Error occurred in generation process.'));
      expect(card.imageBytes, isNotNull);
      expect(viewmodel.commandStatus.currentTotalCount, 1);
    },
  );

  test('unlimited mode does not create resumable state', () async {
    final payloadConfig = _buildPayloadConfig(numberOfRequests: 0);
    payloadConfig.settings.batchCount = 1;
    await GetIt.I.unregister<PayloadConfig>();
    GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
    final configService = GetIt.I<ConfigService>() as _FakeConfigService;
    final viewmodel = _TestGenerationPageViewmodel(
      payloadResults: [_buildPayloadResult('prompt-1')],
      responses: [ApiResponse(status: '200', data: Uint8List(0))],
    );

    viewmodel.startBatchFromScratch();
    final command = viewmodel.currentCommand;
    expect(command, isNotNull);
    while (command!.isExecutingSync.value || command.isExecuting.value) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    viewmodel.stopBatch();

    expect(payloadConfig.generationRuntimeState.hasPendingBatchResume, isFalse);
    expect(
        configService.lastSavedState?.hasPendingBatchResume ?? false, isFalse);
  });

  test(
    'startBatchFromScratch resets sequential prompt selection state between runs',
    () async {
      final payloadConfig = _buildSequentialPayloadConfig(numberOfRequests: 1);
      await GetIt.I.unregister<PayloadConfig>();
      GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
      final viewmodel = _TestGenerationPageViewmodel(
        responses: [
          ApiResponse(status: '200', data: Uint8List(0)),
          ApiResponse(status: '200', data: Uint8List(0)),
        ],
      );

      viewmodel.startBatchFromScratch();
      await _waitForBatchToStop(viewmodel);
      final firstRunInput =
          viewmodel.commandList.last.value.additionalInfo['input'];

      viewmodel.startBatchFromScratch();
      await _waitForBatchToStop(viewmodel);
      final secondRunInput =
          viewmodel.commandList.last.value.additionalInfo['input'];

      expect(firstRunInput, 'prompt-1');
      expect(secondRunInput, 'prompt-1');
    },
  );

  test(
    'resumeBatchFromLast fast-forwards sequential prompt selection after app restart',
    () async {
      final payloadConfig = _buildSequentialPayloadConfig(
        numberOfRequests: 2,
        generationRuntimeState: GenerationRuntimeState(
          hasPendingBatchResume: true,
          resumeTargetTotalCount: 2,
          resumeCompletedCount: 1,
          resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
        ),
      );
      await GetIt.I.unregister<PayloadConfig>();
      GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
      final viewmodel = _TestGenerationPageViewmodel(
        responses: [ApiResponse(status: '200', data: Uint8List(0))],
      );

      viewmodel.resumeBatchFromLast();
      await _waitForBatchToStop(viewmodel);

      expect(viewmodel.commandList.last.value.additionalInfo['input'], 'prompt-2');
    },
  );

  test(
    'resumeBatchFromNumber fast-forwards sequential prompt selection to the requested start number',
    () async {
      final payloadConfig = _buildSequentialPayloadConfig(numberOfRequests: 3);
      await GetIt.I.unregister<PayloadConfig>();
      GetIt.I.registerSingleton<PayloadConfig>(payloadConfig);
      final viewmodel = _TestGenerationPageViewmodel(
        responses: [ApiResponse(status: '200', data: Uint8List(0))],
      );

      viewmodel.resumeBatchFromNumber(3);
      await _waitForBatchToStop(viewmodel);

      expect(viewmodel.commandList.last.value.additionalInfo['input'], 'prompt-3');
    },
  );
}
