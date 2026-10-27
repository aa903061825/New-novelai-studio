import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/models/command_status.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/studio/models/studio_director_tool.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/use_cases/generate_payload_use_case.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';

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
  StudioGalleryOperation? lastOperation;
  String? lastSourceRecordId;
  String? lastSourceImagePath;
  Map<String, dynamic>? lastOperationParameters;
  int saveSnapshotCallCount = 0;
  int saveOperationSnapshotCallCount = 0;

  @override
  Future<StudioGalleryRecord> saveSnapshot({
    required PayloadConfig config,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> additionalInfo = const {},
    DateTime? createdAt,
    String? id,
    StudioGalleryLineage? lineage,
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
      lineage: lineage,
    );
  }

  @override
  Future<StudioGalleryRecord> saveOperationSnapshot({
    required PayloadConfig config,
    required StudioGalleryOperation operation,
    required String sourceRecordId,
    String? sourceImagePath,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> parameters = const {},
    Map<String, dynamic> additionalInfo = const {},
    DateTime? createdAt,
    String? id,
  }) async {
    saveOperationSnapshotCallCount++;
    lastTitle = title;
    lastImagePath = imagePath;
    lastInfo = info;
    lastAdditionalInfo = Map<String, dynamic>.from(additionalInfo);
    lastOperation = operation;
    lastSourceRecordId = sourceRecordId;
    lastSourceImagePath = sourceImagePath;
    lastOperationParameters = Map<String, dynamic>.from(parameters);
    return StudioGalleryRecord.fromPayloadConfig(
      config: config,
      id: id ?? 'operation-record-$saveOperationSnapshotCallCount',
      createdAt: createdAt ?? DateTime.parse('2026-05-22T00:00:00Z'),
      title: title,
      imagePath: imagePath,
      info: info,
      additionalInfo: additionalInfo,
      lineage: StudioGalleryLineage(
        operation: operation,
        sourceRecordId: sourceRecordId,
        sourceImagePath: sourceImagePath,
        parameters: parameters,
      ),
    );
  }
}

StudioGalleryRecord _galleryRecord({
  required String id,
  required String imagePath,
  String title = 'source.png',
}) {
  return StudioGalleryRecord.fromPayloadConfig(
    config: _buildPayloadConfig(),
    id: id,
    createdAt: DateTime.parse('2026-05-22T00:00:00Z'),
    title: title,
    imagePath: imagePath,
    info: 'source prompt',
  );
}

String _writePngFixture(String name, {int width = 1, int height = 1}) {
  final directory = Directory(
    '${Directory.current.path}${Platform.pathSeparator}'
    'build${Platform.pathSeparator}generation_viewmodel_operation_test',
  );
  directory.createSync(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  final image = img.Image(width: width, height: height);
  file.writeAsBytesSync(img.encodePng(image));
  return file.path;
}

Uint8List _zipBytes(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = Uint8List.fromList(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
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
    final fixtureDirectory = Directory(
      '${Directory.current.path}${Platform.pathSeparator}'
      'build${Platform.pathSeparator}generation_viewmodel_operation_test',
    );
    if (fixtureDirectory.existsSync()) {
      fixtureDirectory.deleteSync(recursive: true);
    }
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

  test('enhanceGalleryRecord sends img2img and saves lineage', () async {
    final payloadConfig = GetIt.I<PayloadConfig>();
    payloadConfig.overridePrompt = 'enhance prompt';
    payloadConfig.useOverridePrompt = true;
    payloadConfig.i2iConfig.updateStrengthAndNoise(0.42, 0.12);
    payloadConfig.settings.outputFolderPath = r'C:\outputs';
    final sourcePath = _writePngFixture('source.png');
    final sourceBytes = File(sourcePath).readAsBytesSync();
    final galleryService = _FakeGalleryService();
    GetIt.I.registerSingleton<StudioGalleryService>(galleryService);
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(status: '200', data: Uint8List.fromList([9, 8, 7])),
      ],
    );

    await viewmodel.enhanceGalleryRecord(
      _galleryRecord(
        id: 'source-record',
        imagePath: sourcePath,
        title: 'source.png',
      ),
    );

    final request = viewmodel.requestPayloads.single;
    final params = request['parameters'] as Map<String, dynamic>;
    expect(request['action'], 'img2img');
    expect(request['input'], contains('enhance prompt'));
    expect(params['image'], base64Encode(sourceBytes));
    expect(params['strength'], 0.42);
    expect(params['noise'], 0.12);
    expect(viewmodel.savedFileNames.single, contains('enhance-source.png'));
    expect(galleryService.saveOperationSnapshotCallCount, 1);
    expect(galleryService.lastOperation, StudioGalleryOperation.enhance);
    expect(galleryService.lastSourceRecordId, 'source-record');
    expect(galleryService.lastSourceImagePath, sourcePath);
    expect(galleryService.lastInfo, contains('enhance prompt'));
    expect(galleryService.lastAdditionalInfo?['action'], 'img2img');
    expect(galleryService.lastOperationParameters?['strength'], 0.42);
    expect(galleryService.lastOperationParameters?['noise'], 0.12);
    expect(galleryService.lastOperationParameters?['source_width'], 1);
    expect(galleryService.lastOperationParameters?['source_height'], 1);
  });

  test('upscaleGalleryRecord rejects oversized sources before fetchData',
      () async {
    final sourcePath = _writePngFixture(
      'oversized.png',
      width: 1025,
      height: 768,
    );
    final viewmodel = _TestGenerationPageViewmodel();

    await expectLater(
      viewmodel.upscaleGalleryRecord(
        _galleryRecord(id: 'oversized-source', imagePath: sourcePath),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('1024x1024'),
        ),
      ),
    );

    expect(viewmodel.requestPayloads, isEmpty);
    expect(viewmodel.savedFileNames, isEmpty);
  });

  test('runDirectorToolGalleryRecord sends augment request and saves lineage',
      () async {
    final payloadConfig = GetIt.I<PayloadConfig>();
    payloadConfig.settings.outputFolderPath = r'C:\outputs';
    final sourcePath = _writePngFixture(
      'director-source.png',
      width: 2,
      height: 3,
    );
    final galleryService = _FakeGalleryService();
    GetIt.I.registerSingleton<StudioGalleryService>(galleryService);
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(
          status: '200',
          data: _zipBytes({
            'image_0.png': [1, 2, 3],
          }),
        ),
      ],
    );

    await viewmodel.runDirectorToolGalleryRecord(
      _galleryRecord(id: 'source-record', imagePath: sourcePath),
      const StudioDirectorToolOptions(
        tool: StudioDirectorTool.colorize,
        prompt: 'red hair',
        defry: 3,
      ),
    );

    expect(
      viewmodel.requestEndpoints.single,
      'https://image.novelai.net/ai/augment-image',
    );
    expect(viewmodel.requestPayloads.single['req_type'], 'colorize');
    expect(viewmodel.requestPayloads.single['prompt'], 'red hair');
    expect(viewmodel.requestPayloads.single['defry'], 3);
    expect(viewmodel.savedFileNames.single, contains('director-colorize'));
    expect(galleryService.saveOperationSnapshotCallCount, 1);
    expect(galleryService.lastOperation, StudioGalleryOperation.directorTool);
    expect(galleryService.lastSourceRecordId, 'source-record');
    expect(galleryService.lastSourceImagePath, sourcePath);
    expect(galleryService.lastAdditionalInfo?['req_type'], 'colorize');
    expect(galleryService.lastOperationParameters?['tool'], 'colorize');
    expect(galleryService.lastOperationParameters?['req_type'], 'colorize');
    expect(galleryService.lastOperationParameters?['prompt'], 'red hair');
    expect(galleryService.lastOperationParameters?['defry'], 3);
    expect(galleryService.lastOperationParameters?['source_width'], 2);
    expect(galleryService.lastOperationParameters?['source_height'], 3);
  });

  test('runDirectorToolGalleryRecord saves every director result variant',
      () async {
    final payloadConfig = GetIt.I<PayloadConfig>();
    payloadConfig.settings.outputFolderPath = r'C:\outputs';
    final sourcePath = _writePngFixture(
      'director-source.png',
      width: 2,
      height: 3,
    );
    final galleryService = _FakeGalleryService();
    GetIt.I.registerSingleton<StudioGalleryService>(galleryService);
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(
          status: '200',
          data: _zipBytes({
            'image_0.png': [10],
            'image_1.png': [20],
          }),
        ),
      ],
    );

    await viewmodel.runDirectorToolGalleryRecord(
      _galleryRecord(id: 'source-record', imagePath: sourcePath),
      const StudioDirectorToolOptions(
        tool: StudioDirectorTool.removeBackground,
      ),
    );

    expect(galleryService.saveOperationSnapshotCallCount, 2);
    expect(viewmodel.savedFileNames, hasLength(2));
    expect(viewmodel.savedFileNames.first, contains('image_0'));
    expect(viewmodel.savedFileNames.last, contains('image_1'));
    expect(galleryService.lastOperation, StudioGalleryOperation.directorTool);
    expect(galleryService.lastOperationParameters?['tool'], 'removeBackground');
    expect(galleryService.lastOperationParameters?['req_type'], 'bg-removal');
    expect(galleryService.lastOperationParameters?['variant_index'], 1);
    expect(galleryService.lastOperationParameters?['variant_name'], 'image_1');
    expect(galleryService.lastAdditionalInfo?['variant_index'], 1);
    expect(galleryService.lastAdditionalInfo?['variant_name'], 'image_1');
  });

  test('runInpaintGalleryRecord sends infill and saves lineage', () async {
    final payloadConfig = GetIt.I<PayloadConfig>();
    payloadConfig.overridePrompt = 'inpaint prompt';
    payloadConfig.useOverridePrompt = true;
    payloadConfig.settings.outputFolderPath = r'C:\outputs';
    final sourcePath = _writePngFixture(
      'inpaint-source.png',
      width: 2,
      height: 3,
    );
    final maskPath = _writePngFixture(
      'inpaint-mask.png',
      width: 2,
      height: 3,
    );
    final sourceBytes = File(sourcePath).readAsBytesSync();
    final maskBytes = File(maskPath).readAsBytesSync();
    final galleryService = _FakeGalleryService();
    GetIt.I.registerSingleton<StudioGalleryService>(galleryService);
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(status: '200', data: Uint8List.fromList([4, 5, 6])),
      ],
    );

    await viewmodel.runInpaintGalleryRecord(
      _galleryRecord(id: 'source-record', imagePath: sourcePath),
      maskImagePath: maskPath,
      strength: 0.72,
    );

    final request = viewmodel.requestPayloads.single;
    final params = request['parameters'] as Map<String, dynamic>;
    expect(request['action'], 'infill');
    expect(request['model'], endsWith('-inpainting'));
    expect(request['input'], contains('inpaint prompt'));
    expect(params['image'], base64Encode(sourceBytes));
    expect(params['mask'], base64Encode(maskBytes));
    expect(params['inpaintImg2ImgStrength'], 0.72);
    expect(viewmodel.savedFileNames.single, contains('inpaint-source.png'));
    expect(galleryService.saveOperationSnapshotCallCount, 1);
    expect(galleryService.lastOperation, StudioGalleryOperation.inpaint);
    expect(galleryService.lastSourceRecordId, 'source-record');
    expect(galleryService.lastSourceImagePath, sourcePath);
    expect(
        galleryService.lastOperationParameters?['mask_image_path'], maskPath);
    expect(galleryService.lastOperationParameters?['source_width'], 2);
    expect(galleryService.lastOperationParameters?['source_height'], 3);
    expect(galleryService.lastOperationParameters?['mask_width'], 2);
    expect(galleryService.lastOperationParameters?['mask_height'], 3);
  });

  test('runInpaintGalleryRecord rejects invalid masks before fetchData',
      () async {
    final sourcePath = _writePngFixture(
      'inpaint-source.png',
      width: 2,
      height: 3,
    );
    final maskPath = _writePngFixture(
      'inpaint-mask.png',
      width: 1,
      height: 1,
    );
    final viewmodel = _TestGenerationPageViewmodel();

    await expectLater(
      viewmodel.runInpaintGalleryRecord(
        _galleryRecord(id: 'source-record', imagePath: sourcePath),
        maskImagePath: maskPath,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('dimensions'),
        ),
      ),
    );

    expect(viewmodel.requestPayloads, isEmpty);
    expect(viewmodel.savedFileNames, isEmpty);
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
      final result = command.value;
      expect(result.imageBytes, isNull);
      expect(result.imagePath, isNotNull);
      expect(result.imagePath, isNotEmpty);
    },
  );

  test('startSingleImageGeneration uses the requested workbench count',
      () async {
    final viewmodel = _TestGenerationPageViewmodel(
      onNextCommand: () {},
    );

    viewmodel.startSingleImageGeneration(count: 3);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(viewmodel.payloadConfig.settings.numberOfRequests, 3);
    expect(viewmodel.payloadConfig.settings.batchCount, 3);
    expect(viewmodel.commandStatus.isBatchActive.value, isTrue);
    expect(viewmodel.nextCommandCallCount, 1);
  });

  test('single image generation encodes a changed Vibe before generation',
      () async {
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(
          status: '201',
          data: Uint8List.fromList(const [4, 5, 6]),
        ),
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );
    viewmodel.payloadConfig.paramConfig.model = 'nai-diffusion-4-5-full';
    viewmodel.payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'editable-vibe',
        vibeB64: 'old-encoding',
        infoExtracted: 0.42,
        encodedInfoExtracted: 0.76,
        referenceStrength: 0.3,
        imageBytes: Uint8List.fromList(const [1, 2, 3]),
      ),
    ];

    viewmodel.startSingleImageGeneration();
    for (var i = 0; i < 100 && viewmodel.requestEndpoints.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await _waitForBatchToStop(viewmodel);

    expect(viewmodel.requestEndpoints, [
      'https://image.novelai.net/ai/encode-vibe',
      'https://image.novelai.net/ai/generate-image',
    ]);
    expect(
      viewmodel.requestPayloads.first['information_extracted'],
      0.42,
    );
    expect(
      viewmodel.payloadConfig.vibeConfigListV4.single.vibeB64,
      base64Encode(const [4, 5, 6]),
    );
  });

  test(
    'single image generation stops after failure instead of cooling down',
    () async {
      final viewmodel = _TestGenerationPageViewmodel(
        payloadResults: [_buildPayloadResult('prompt-1')],
        responses: [Exception('request failed')],
      );

      viewmodel.startSingleImageGeneration(count: 2);
      await _waitForBatchToStop(viewmodel);

      expect(viewmodel.requestPayloads, hasLength(1));
      expect(viewmodel.generatedPayloadCount, 1);
      expect(viewmodel.savedFileNames, isEmpty);
      expect(viewmodel.commandStatus.isBatchActive.value, isFalse);
      expect(viewmodel.commandStatus.isCoolingDown.value, isFalse);
      expect(viewmodel.lastScheduledCooldown, isNull);
    },
  );

  test('single image generation omits empty reference arrays by default',
      () async {
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );

    viewmodel.startSingleImageGeneration();
    await _waitForBatchToStop(viewmodel);

    final params =
        viewmodel.requestPayloads.single['parameters'] as Map<String, dynamic>;
    expect(params.containsKey('reference_image_multiple'), isFalse);
    expect(params.containsKey('reference_strength_multiple'), isFalse);
    expect(
      params.containsKey('reference_information_extracted_multiple'),
      isFalse,
    );
  });

  test('single image generation sends the current configured size', () async {
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );
    viewmodel.payloadConfig.paramConfig.sizes = const [
      GenerationSize(width: 704, height: 1472),
    ];

    viewmodel.startSingleImageGeneration();
    await _waitForBatchToStop(viewmodel);

    final params =
        viewmodel.requestPayloads.single['parameters'] as Map<String, dynamic>;
    expect(params['width'], 704);
    expect(params['height'], 1472);
  });

  test('single image generation ignores hidden batch resolution settings',
      () async {
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );
    viewmodel.payloadConfig.paramConfig
      ..sizes = const [
        GenerationSize(width: 1472, height: 704),
      ]
      ..enableBatchResolution = true
      ..batchResolutionMode = 'stop_at_end'
      ..batchResolutionText = [
        '704x1472',
        '832x1216',
      ].join('\n');

    viewmodel.startSingleImageGeneration();
    await _waitForBatchToStop(viewmodel);

    final params =
        viewmodel.requestPayloads.single['parameters'] as Map<String, dynamic>;
    expect(params['width'], 1472);
    expect(params['height'], 704);
  });

  test('single image generation ignores hidden global generation overrides',
      () async {
    final viewmodel = _TestGenerationPageViewmodel(
      responses: [
        ApiResponse(status: '200', data: Uint8List(0)),
      ],
    );
    viewmodel.payloadConfig.paramConfig
      ..steps = 17
      ..scale = 4.4
      ..cfgRescale = 0.35
      ..sampler = 'k_euler'
      ..noiseSchedule = 'exponential'
      ..negativePrompt = 'workbench uc'
      ..randomSeed = false
      ..seed = 123456;
    viewmodel.payloadConfig.globalGenerationParams
      ..useGlobalSteps = true
      ..useGlobalScale = true
      ..useGlobalCfgRescale = true
      ..useGlobalSampler = true
      ..useGlobalNegativePrompt = true
      ..steps = 28
      ..scale = 9.9
      ..cfgRescale = 0.9
      ..sampler = 'k_dpmpp_2m'
      ..negativePrompt = 'global uc';

    viewmodel.startSingleImageGeneration();
    await _waitForBatchToStop(viewmodel);

    final params =
        viewmodel.requestPayloads.single['parameters'] as Map<String, dynamic>;
    expect(params['steps'], 17);
    expect(params['scale'], 4.4);
    expect(params['cfg_rescale'], 0.35);
    expect(params['sampler'], 'k_euler');
    expect(params['noise_schedule'], 'exponential');
    expect(params['negative_prompt'], 'workbench uc');
    expect(params['seed'], 123456);
    expect(
      ((params['v4_negative_prompt'] as Map<String, dynamic>)['caption']
          as Map<String, dynamic>)['base_caption'],
      'workbench uc',
    );
  });

  test(
    'single image generation reports payload errors instead of command errors',
    () async {
      final viewmodel = _TestGenerationPageViewmodel();
      viewmodel.payloadConfig.paramConfig.sizes = [];

      viewmodel.startSingleImageGeneration();
      await _waitForBatchToStop(viewmodel);

      final card = viewmodel.commandList.last.value;
      expect(card.title, '生成失败');
      expect(card.info, contains('RangeError'));
      expect(card.additionalInfo, isEmpty);
      expect(viewmodel.requestPayloads, isEmpty);
      expect(viewmodel.commandStatus.isBatchActive.value, isFalse);
    },
  );

  test('generation preflight errors notify result listeners', () async {
    final viewmodel = _TestGenerationPageViewmodel();
    viewmodel.payloadConfig.paramConfig
      ..enableBatchResolution = true
      ..batchResolutionText = '';
    var notificationCount = 0;
    viewmodel.addListener(() => notificationCount++);

    viewmodel.startBatchFromScratch();
    for (var i = 0; i < 100; i++) {
      if (viewmodel.commandList case [final command]) {
        if (!command.isExecutingSync.value && !command.isExecuting.value) {
          break;
        }
      }
      await Future<void>.delayed(Duration.zero);
    }

    expect(viewmodel.commandList, hasLength(1));
    expect(viewmodel.commandList.single.value.info, isNotEmpty);
    expect(notificationCount, greaterThan(0));
    expect(viewmodel.commandStatus.isBatchActive.value, isFalse);
  });

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
