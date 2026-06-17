import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_production_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

typedef ScriptRecastSmokeFetch = Future<ApiResponse> Function(
  ApiRequest request,
);
typedef ScriptRecastSmokeProcessResponse = Uint8List Function(Uint8List bytes);
typedef ScriptRecastSmokeSavePicture = Future<void> Function(
  Uint8List bytes,
  String fileName,
  String saveDir,
);

const defaultScriptAcceptanceTargets = [
  ScriptAcceptanceTarget(
    label: 'vulpisfoglia suzuran 忍冬x铃兰 BBC',
    primaryPath: r'E:\NAI的脚本群\作品集\vulpisfoglia suzuran 忍冬x铃兰 BBC',
  ),
  ScriptAcceptanceTarget(
    label: 'Chino',
    primaryPath: r'E:\NAI的脚本群\作品集\Chino',
  ),
  ScriptAcceptanceTarget(
    label: '1战败',
    primaryPath: r'E:\NAI的脚本群\作品集\1战败',
  ),
  ScriptAcceptanceTarget(
    label: 'ある執事のトリスビアスの物語',
    primaryPath: r'E:\NAI的脚本群\作品集\ある執事のトリスビアスの物語',
    fallbackPath: r'E:\NAI的脚本群\作品集\ある輪廻のトリスビアスの物語',
  ),
];

Future<void> main(List<String> args) async {
  final cli = _ScriptRecastAcceptanceCliOptions.parse(args);
  final localConfig = await _resolveScriptRecastSmokeConfig();
  final reports = await runScriptRecastAcceptance(
    targets: defaultScriptAcceptanceTargets,
    apiToken: localConfig.apiToken,
    fingerprintFrameLimit: cli.fingerprintFrameLimit,
    smokeOptions: cli.smokeOptions.withDefaultsFrom(localConfig),
  );
  printScriptRecastAcceptanceReport(reports);

  if (reports.any(
    (report) =>
        report.status == ScriptAcceptanceStatus.failed ||
        report.realApiSmokeResults.any(
          (result) =>
              result.status == ScriptAcceptanceRealApiSmokeStatus.failed,
        ),
  )) {
    exitCode = 1;
  }
}

Future<List<ScriptAcceptanceReport>> runScriptRecastAcceptance({
  required List<ScriptAcceptanceTarget> targets,
  String? apiToken,
  int fingerprintFrameLimit = 10,
  ScriptRecastRealSmokeOptions smokeOptions =
      const ScriptRecastRealSmokeOptions(),
}) async {
  final reports = <ScriptAcceptanceReport>[];
  var remainingSmokeTargets =
      smokeOptions.enabled ? smokeOptions.targetLimit : 0;
  for (final target in targets) {
    final targetSmokeOptions = remainingSmokeTargets > 0
        ? smokeOptions
        : smokeOptions.copyWith(enabled: false);
    final report = await _runTarget(
      target: target,
      apiToken: apiToken,
      fingerprintFrameLimit: fingerprintFrameLimit,
      smokeOptions: targetSmokeOptions,
    );
    reports.add(report);
    if (report.realApiSmokeResults.isNotEmpty) {
      remainingSmokeTargets -= 1;
    }
  }
  return List.unmodifiable(reports);
}

Future<ScriptAcceptanceReport> _runTarget({
  required ScriptAcceptanceTarget target,
  required String? apiToken,
  required int fingerprintFrameLimit,
  required ScriptRecastRealSmokeOptions smokeOptions,
}) async {
  final resolved = await target.resolve();
  if (resolved == null) {
    return ScriptAcceptanceReport.skipped(
      label: target.label,
      configuredPath: target.primaryPath,
      fallbackPath: target.fallbackPath,
      message: 'SKIPPED: script directory does not exist.',
    );
  }

  final before = await snapshotNaiJsonFiles(resolved);
  final script = await const ScriptRecastParserService().parseDirectory(
    resolved,
  );
  final engine = const ScriptRecastEngine();
  final mapping = RecastMapping.defaults(script.id);
  final first = engine.resolvePayloads(
    script: script,
    mapping: mapping,
    characters: const [],
    artistChains: const [],
  );
  final second = engine.resolvePayloads(
    script: script,
    mapping: mapping,
    characters: const [],
    artistChains: const [],
  );
  final after = await snapshotNaiJsonFiles(resolved);
  final productionProbe = await _probeDeterministicProductionPlan(
    script: script,
    result: first,
    frameLimit: fingerprintFrameLimit,
  );

  final firstSummaries = first.frames.take(fingerprintFrameLimit).map(
        (frame) => FingerprintSummary(
          frameIndex: frame.frameIndex,
          sourceFileName: frame.sourceFileName,
          payloadFingerprint: _fingerprintJson(_canonicalJson(frame.payload)),
          policyMetadataKeys: _policyMetadataKeys(frame.payload),
        ),
      );
  final secondSummaries = second.frames.take(fingerprintFrameLimit).map(
        (frame) => FingerprintSummary(
          frameIndex: frame.frameIndex,
          sourceFileName: frame.sourceFileName,
          payloadFingerprint: _fingerprintJson(_canonicalJson(frame.payload)),
          policyMetadataKeys: _policyMetadataKeys(frame.payload),
        ),
      );
  final firstFingerprints = firstSummaries
      .map((summary) => summary.payloadFingerprint)
      .toList(growable: false);
  final secondFingerprints = secondSummaries
      .map((summary) => summary.payloadFingerprint)
      .toList(growable: false);
  final errorCount = script.frames
      .where((frame) => frame.parseStatus == ScriptFrameParseStatus.error)
      .length;
  final fingerprintSummaries = firstSummaries.toList(growable: false);
  final smokeResults = await _runRealApiSmokeIfRequested(
    script: script,
    result: first,
    apiToken: apiToken,
    parseErrorCount: errorCount,
    options: smokeOptions,
  );
  final smokeFailed = smokeResults.any(
    (result) => result.status == ScriptAcceptanceRealApiSmokeStatus.failed,
  );

  return ScriptAcceptanceReport(
    label: target.label,
    configuredPath: target.primaryPath,
    fallbackPath: target.fallbackPath,
    actualPath: resolved.path,
    status: errorCount == 0 && !smokeFailed
        ? ScriptAcceptanceStatus.passed
        : ScriptAcceptanceStatus.failed,
    frameCount: script.frames.length,
    detectedSchema: script.detectedSchema.name,
    parsedCount: script.frames.length - errorCount,
    errorCount: errorCount,
    warningCount: script.parseWarnings.length,
    fingerprintStable: _listEquals(firstFingerprints, secondFingerprints),
    snapshotUnchanged: _snapshotEquals(before, after),
    productionPlanTaskCount: productionProbe.taskCount,
    productionPlanFingerprintStable: productionProbe.fingerprintStable,
    realApiStatus: _realApiStatus(
      apiToken: apiToken,
      parseErrorCount: errorCount,
      smokeOptions: smokeOptions,
      smokeResults: smokeResults,
    ),
    fingerprintSummaries: List.unmodifiable(fingerprintSummaries),
    realApiSmokeResults: smokeResults,
    fileSnapshotsBefore: before,
    fileSnapshotsAfter: after,
    message: errorCount == 0
        ? smokeFailed
            ? 'FAILED: real API smoke failed.'
            : 'OK'
        : 'FAILED: parse errors detected.',
  );
}

Future<List<ScriptAcceptanceRealApiSmokeResult>> _runRealApiSmokeIfRequested({
  required Script script,
  required ScriptRecastResult result,
  required String? apiToken,
  required int parseErrorCount,
  required ScriptRecastRealSmokeOptions options,
}) async {
  if (!options.enabled || !_hasToken(apiToken) || parseErrorCount > 0) {
    return const [];
  }
  final frameLimit = options.frameLimit <= 0 ? 1 : options.frameLimit;
  final sampledFrames = result.frames.take(frameLimit).toList(growable: false);
  if (sampledFrames.isEmpty) {
    return const [];
  }

  final outputDirectory =
      options.outputDirectory ?? _defaultSmokeOutputDirectory();
  await Directory(outputDirectory).create(recursive: true);
  final tempDir = await Directory.systemTemp.createTemp(
    'script-recast-real-smoke-plan-',
  );
  try {
    final workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    final queueService = ProductionQueueService(
      workspaceService: workspaceService,
    );
    final productionService = ScriptRecastProductionService(
      queueService: queueService,
      now: () => DateTime.utc(2026, 5, 26),
    );
    final sampledResult = ScriptRecastResult(
      scriptId: result.scriptId,
      mappingId: result.mappingId,
      frames: sampledFrames,
      configFingerprint: result.configFingerprint,
    );
    final plan = await productionService.enqueueRecastResult(
      result: sampledResult,
      planId: 'real-smoke-${_slug(script.name)}',
      planName: '${script.name} real API smoke',
      recastRunId: 'real-smoke-${_slug(script.name)}-run',
      scriptName: script.name,
      scriptPath: script.rootPath,
    );
    final smokeResults = <ScriptAcceptanceRealApiSmokeResult>[];
    for (final task in plan.tasks) {
      try {
        final bytes = await _requestSmokeImage(
          payload: task.payload,
          apiToken: apiToken!,
          options: options,
        );
        final fileName = _smokeFileName(script.name, task.source.frameIndex);
        final savePicture = options.savePictureToFile ?? _saveSmokePicture;
        await savePicture(bytes, fileName, outputDirectory);
        final outputPath = _joinOutputPath(outputDirectory, fileName);
        smokeResults.add(
          ScriptAcceptanceRealApiSmokeResult(
            frameIndex: task.source.frameIndex ?? 0,
            sourceFileName: task.source.sourceFileName ?? task.title,
            status: ScriptAcceptanceRealApiSmokeStatus.completed,
            payloadFingerprint: task.payloadFingerprint,
            outputImagePath: outputPath,
            productionPlanId: plan.id,
            productionTaskId: task.id,
            productionPlanFingerprint: plan.planFingerprint,
          ),
        );
      } catch (error) {
        smokeResults.add(
          ScriptAcceptanceRealApiSmokeResult(
            frameIndex: task.source.frameIndex ?? 0,
            sourceFileName: task.source.sourceFileName ?? task.title,
            status: ScriptAcceptanceRealApiSmokeStatus.failed,
            payloadFingerprint: task.payloadFingerprint,
            error: _sanitizeSmokeError(error, apiToken),
            productionPlanId: plan.id,
            productionTaskId: task.id,
            productionPlanFingerprint: plan.planFingerprint,
          ),
        );
      }
    }
    return List.unmodifiable(smokeResults);
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<Uint8List> _requestSmokeImage({
  required Map<String, dynamic> payload,
  required String apiToken,
  required ScriptRecastRealSmokeOptions options,
}) async {
  final fetch = options.fetchData ?? _fetchSmokeData;
  final response = await fetch(
    ApiRequest(
      endpoint: options.endpoint,
      proxy: options.proxy,
      headers: _headersForToken(apiToken),
      payload: payload,
    ),
  );
  final statusCode = int.tryParse(response.status) ?? 0;
  if (statusCode < 200 || statusCode >= 300) {
    throw StateError(
      'NAI API ${response.status}: ${_apiErrorMessage(response.data)}',
    );
  }
  final process = options.processResponse ?? _processSmokeResponse;
  return process(response.data);
}

Future<ApiResponse> _fetchSmokeData(ApiRequest request) async {
  final url = Uri.parse(request.endpoint);
  http.Response response;
  if (request.proxy.trim().isEmpty) {
    response = await http.post(
      url,
      headers: request.headers,
      body: jsonEncode(request.payload),
    );
  } else {
    final ioClient = HttpClient();
    ioClient.findProxy = (_) => 'PROXY ${request.proxy.trim()}';
    ioClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    final client = IOClient(ioClient);
    try {
      response = await client.post(
        url,
        headers: request.headers,
        body: jsonEncode(request.payload),
      );
    } finally {
      client.close();
    }
  }
  return ApiResponse(
    status: response.statusCode.toString(),
    data: response.bodyBytes,
  );
}

Uint8List _processSmokeResponse(Uint8List zippedResponseBytes) {
  try {
    final archive = ZipDecoder().decodeBytes(zippedResponseBytes);
    for (final file in archive) {
      if (file.name != 'image_0.png') {
        continue;
      }
      final content = file.content;
      if (content is Uint8List) {
        return content;
      }
      if (content is List<int>) {
        return Uint8List.fromList(content);
      }
      throw StateError('image_0.png has unsupported content.');
    }
    throw StateError('image_0.png not found in response archive.');
  } catch (error) {
    throw StateError(
      'Error unpacking NAI response: $error; '
      'responseBytes=${zippedResponseBytes.length}',
    );
  }
}

Future<void> _saveSmokePicture(
  Uint8List bytes,
  String fileName,
  String saveDir,
) async {
  await Directory(saveDir).create(recursive: true);
  await File(_joinOutputPath(saveDir, fileName)).writeAsBytes(bytes);
}

String _smokeFileName(String scriptName, int? frameIndex) {
  final index = frameIndex ?? 0;
  return '${_slug(scriptName).replaceAll('_', '-')}-frame-$index.png';
}

String _realApiStatus({
  required String? apiToken,
  required int parseErrorCount,
  required ScriptRecastRealSmokeOptions smokeOptions,
  required List<ScriptAcceptanceRealApiSmokeResult> smokeResults,
}) {
  if (!_hasToken(apiToken)) {
    return 'skipped-real-api';
  }
  if (parseErrorCount > 0) {
    return 'skipped-real-api-parse-errors';
  }
  if (!smokeOptions.enabled) {
    return 'available-not-requested';
  }
  if (smokeResults.isEmpty) {
    return 'skipped-real-api';
  }
  final completed = smokeResults
      .where((result) =>
          result.status == ScriptAcceptanceRealApiSmokeStatus.completed)
      .length;
  final total = smokeResults.length;
  final prefix = completed == total ? 'completed-real-api' : 'failed-real-api';
  return '$prefix:$completed/$total';
}

Map<String, String> _headersForToken(String apiToken) => {
      'content-type': 'application/json',
      'authorization': 'Bearer ${apiToken.trim()}',
      'referer': 'https://novelai.net',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0',
    };

String _apiErrorMessage(Uint8List data) {
  try {
    return utf8.decode(data, allowMalformed: true);
  } catch (_) {
    return '${data.length} response bytes';
  }
}

String _sanitizeSmokeError(Object error, String? apiToken) {
  var message = error.toString();
  final token = apiToken?.trim();
  if (token != null && token.isNotEmpty) {
    message = message.replaceAll(token, '[redacted-token]');
  }
  message = message.replaceAll(
    RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer [redacted-token]',
  );
  message = message.replaceAll(
    RegExp(r'pst-[A-Za-z0-9_-]+'),
    '[redacted-token]',
  );
  return message;
}

String _defaultSmokeOutputDirectory() {
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null && userProfile.trim().isNotEmpty) {
    return _joinOutputPath(
      _joinOutputPath(userProfile.trim(), 'Documents'),
      'nai-generated${Platform.pathSeparator}script-recast-smoke',
    );
  }
  return _joinOutputPath(
    Directory.current.path,
    'script-recast-smoke',
  );
}

String _joinOutputPath(String directory, String fileName) {
  if (directory.isEmpty) {
    return fileName;
  }
  if (directory.endsWith('/') || directory.endsWith(r'\')) {
    return '$directory$fileName';
  }
  return '$directory${Platform.pathSeparator}$fileName';
}

Future<List<NaiJsonSnapshot>> snapshotNaiJsonFiles(Directory directory) async {
  if (!await directory.exists()) {
    return const [];
  }

  final files = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is File && _naiFilePattern.hasMatch(_fileName(entity.path))) {
      files.add(entity);
    }
  }
  files.sort((left, right) => _fileName(left.path).compareTo(
        _fileName(right.path),
      ));

  final snapshots = <NaiJsonSnapshot>[];
  for (final file in files) {
    final stat = await file.stat();
    final bytes = await file.readAsBytes();
    snapshots.add(
      NaiJsonSnapshot(
        path: file.path,
        length: stat.size,
        lastWriteTimeUtc: stat.modified.toUtc(),
        hash: _fingerprintBytes(bytes),
      ),
    );
  }
  return List.unmodifiable(snapshots);
}

Future<_ProductionPlanProbe> _probeDeterministicProductionPlan({
  required Script script,
  required ScriptRecastResult result,
  required int frameLimit,
}) async {
  final sampledFrames = result.frames.take(frameLimit).toList(growable: false);
  if (sampledFrames.isEmpty) {
    return const _ProductionPlanProbe(
      taskCount: 0,
      fingerprintStable: true,
    );
  }

  final tempDir = await Directory.systemTemp.createTemp(
    'script-recast-acceptance-production-',
  );
  try {
    final workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
    final queueService = ProductionQueueService(
      workspaceService: workspaceService,
    );
    final productionService = ScriptRecastProductionService(
      queueService: queueService,
      now: () => DateTime.utc(2026, 5, 26),
    );
    final sampledResult = ScriptRecastResult(
      scriptId: result.scriptId,
      mappingId: result.mappingId,
      frames: sampledFrames,
      configFingerprint: result.configFingerprint,
    );

    final plan = await productionService.enqueueRecastResult(
      result: sampledResult,
      planId: 'acceptance-${_slug(script.name)}',
      planName: '${script.name} acceptance sample',
      recastRunId: 'acceptance-${_slug(script.name)}-run',
      scriptName: script.name,
      scriptPath: script.rootPath,
    );
    final loaded = await queueService.loadPlans();
    final restored = loaded.singleWhere((candidate) => candidate.id == plan.id);
    return _ProductionPlanProbe(
      taskCount: restored.tasks.length,
      fingerprintStable: restored.planFingerprint == plan.planFingerprint,
    );
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

void printScriptRecastAcceptanceReport(
  List<ScriptAcceptanceReport> reports, {
  StringSink? output,
}) {
  final sink = output ?? stdout;
  sink.writeln('script-recast-acceptance');
  for (final report in reports) {
    sink.writeln('');
    sink.writeln('[${report.status.name}] ${report.label}');
    sink.writeln('configuredPath: ${report.configuredPath}');
    if (report.fallbackPath != null) {
      sink.writeln('fallbackPath: ${report.fallbackPath}');
    }
    if (report.actualPath != null) {
      sink.writeln('actualPath: ${report.actualPath}');
    }
    sink.writeln('message: ${report.message}');
    if (report.status == ScriptAcceptanceStatus.skipped) {
      continue;
    }
    sink.writeln('frameCount: ${report.frameCount}');
    sink.writeln('detectedSchema: ${report.detectedSchema}');
    sink.writeln(
      'parsed/error: ${report.parsedCount}/${report.errorCount}',
    );
    sink.writeln('warnings: ${report.warningCount}');
    sink.writeln('fingerprintStable: ${report.fingerprintStable}');
    sink.writeln('sourceReadOnly: ${report.snapshotUnchanged}');
    sink.writeln('productionPlanTasks: ${report.productionPlanTaskCount}');
    sink.writeln(
      'productionPlanFingerprintStable: '
      '${report.productionPlanFingerprintStable}',
    );
    sink.writeln('realApi: ${report.realApiStatus}');
    if (report.realApiSmokeResults.isNotEmpty) {
      sink.writeln('realApiSmokeResults:');
      for (final result in report.realApiSmokeResults) {
        sink.writeln(
          '  #${result.frameIndex} ${result.sourceFileName} '
          '${result.status.name} ${result.payloadFingerprint}',
        );
        if (result.outputImagePath != null) {
          sink.writeln('    outputImagePath: ${result.outputImagePath}');
        }
        if (result.productionPlanId != null) {
          sink.writeln('    productionPlanId: ${result.productionPlanId}');
        }
        if (result.productionTaskId != null) {
          sink.writeln('    productionTaskId: ${result.productionTaskId}');
        }
        if (result.productionPlanFingerprint != null) {
          sink.writeln(
            '    productionPlanFingerprint: '
            '${result.productionPlanFingerprint}',
          );
        }
        if (result.error != null) {
          sink.writeln('    error: ${result.error}');
        }
      }
    }
    sink.writeln('fingerprints:');
    for (final summary in report.fingerprintSummaries) {
      sink.writeln(
        '  #${summary.frameIndex} ${summary.sourceFileName} '
        '${summary.payloadFingerprint}',
      );
    }
  }
}

class ScriptAcceptanceTarget {
  final String label;
  final String primaryPath;
  final String? fallbackPath;

  const ScriptAcceptanceTarget({
    required this.label,
    required this.primaryPath,
    this.fallbackPath,
  });

  Future<Directory?> resolve() async {
    final primary = Directory(primaryPath);
    if (await primary.exists()) {
      return primary;
    }
    final fallback = fallbackPath;
    if (fallback == null) {
      return null;
    }
    final fallbackDirectory = Directory(fallback);
    if (await fallbackDirectory.exists()) {
      return fallbackDirectory;
    }
    return null;
  }
}

enum ScriptAcceptanceStatus { passed, failed, skipped }

enum ScriptAcceptanceRealApiSmokeStatus { completed, failed }

class ScriptAcceptanceRealApiSmokeResult {
  final int frameIndex;
  final String sourceFileName;
  final ScriptAcceptanceRealApiSmokeStatus status;
  final String payloadFingerprint;
  final String? outputImagePath;
  final String? error;
  final String? productionPlanId;
  final String? productionTaskId;
  final String? productionPlanFingerprint;

  const ScriptAcceptanceRealApiSmokeResult({
    required this.frameIndex,
    required this.sourceFileName,
    required this.status,
    required this.payloadFingerprint,
    this.outputImagePath,
    this.error,
    this.productionPlanId,
    this.productionTaskId,
    this.productionPlanFingerprint,
  });
}

class ScriptAcceptanceReport {
  final String label;
  final String configuredPath;
  final String? fallbackPath;
  final String? actualPath;
  final ScriptAcceptanceStatus status;
  final int frameCount;
  final String detectedSchema;
  final int parsedCount;
  final int errorCount;
  final int warningCount;
  final bool fingerprintStable;
  final bool snapshotUnchanged;
  final int productionPlanTaskCount;
  final bool productionPlanFingerprintStable;
  final String realApiStatus;
  final List<FingerprintSummary> fingerprintSummaries;
  final List<ScriptAcceptanceRealApiSmokeResult> realApiSmokeResults;
  final List<NaiJsonSnapshot> fileSnapshotsBefore;
  final List<NaiJsonSnapshot> fileSnapshotsAfter;
  final String message;

  const ScriptAcceptanceReport({
    required this.label,
    required this.configuredPath,
    required this.fallbackPath,
    required this.actualPath,
    required this.status,
    required this.frameCount,
    required this.detectedSchema,
    required this.parsedCount,
    required this.errorCount,
    required this.warningCount,
    required this.fingerprintStable,
    required this.snapshotUnchanged,
    required this.productionPlanTaskCount,
    required this.productionPlanFingerprintStable,
    required this.realApiStatus,
    required this.fingerprintSummaries,
    this.realApiSmokeResults = const [],
    required this.fileSnapshotsBefore,
    required this.fileSnapshotsAfter,
    required this.message,
  });

  factory ScriptAcceptanceReport.skipped({
    required String label,
    required String configuredPath,
    required String? fallbackPath,
    required String message,
  }) {
    return ScriptAcceptanceReport(
      label: label,
      configuredPath: configuredPath,
      fallbackPath: fallbackPath,
      actualPath: null,
      status: ScriptAcceptanceStatus.skipped,
      frameCount: 0,
      detectedSchema: 'unknown',
      parsedCount: 0,
      errorCount: 0,
      warningCount: 0,
      fingerprintStable: true,
      snapshotUnchanged: true,
      productionPlanTaskCount: 0,
      productionPlanFingerprintStable: true,
      realApiStatus: 'skipped-real-api',
      fingerprintSummaries: const [],
      realApiSmokeResults: const [],
      fileSnapshotsBefore: const [],
      fileSnapshotsAfter: const [],
      message: message,
    );
  }
}

class ScriptRecastRealSmokeOptions {
  final bool enabled;
  final int frameLimit;
  final int targetLimit;
  final String endpoint;
  final String proxy;
  final String? outputDirectory;
  final ScriptRecastSmokeFetch? fetchData;
  final ScriptRecastSmokeProcessResponse? processResponse;
  final ScriptRecastSmokeSavePicture? savePictureToFile;

  const ScriptRecastRealSmokeOptions({
    this.enabled = false,
    this.frameLimit = 1,
    this.targetLimit = 1,
    this.endpoint = 'https://image.novelai.net/ai/generate-image',
    this.proxy = '',
    this.outputDirectory,
    this.fetchData,
    this.processResponse,
    this.savePictureToFile,
  });

  ScriptRecastRealSmokeOptions copyWith({
    bool? enabled,
    int? frameLimit,
    int? targetLimit,
    String? endpoint,
    String? proxy,
    String? outputDirectory,
    ScriptRecastSmokeFetch? fetchData,
    ScriptRecastSmokeProcessResponse? processResponse,
    ScriptRecastSmokeSavePicture? savePictureToFile,
  }) {
    return ScriptRecastRealSmokeOptions(
      enabled: enabled ?? this.enabled,
      frameLimit: frameLimit ?? this.frameLimit,
      targetLimit: targetLimit ?? this.targetLimit,
      endpoint: endpoint ?? this.endpoint,
      proxy: proxy ?? this.proxy,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      fetchData: fetchData ?? this.fetchData,
      processResponse: processResponse ?? this.processResponse,
      savePictureToFile: savePictureToFile ?? this.savePictureToFile,
    );
  }

  ScriptRecastRealSmokeOptions withDefaultsFrom(
    ScriptRecastSmokeLocalConfig config,
  ) {
    return copyWith(
      proxy: proxy.isNotEmpty ? proxy : config.proxy,
      outputDirectory: outputDirectory ?? config.outputDirectory,
    );
  }
}

class ScriptRecastSmokeLocalConfig {
  final String? apiToken;
  final String proxy;
  final String? outputDirectory;

  const ScriptRecastSmokeLocalConfig({
    this.apiToken,
    this.proxy = '',
    this.outputDirectory,
  });
}

class _ScriptRecastAcceptanceCliOptions {
  final int fingerprintFrameLimit;
  final ScriptRecastRealSmokeOptions smokeOptions;

  const _ScriptRecastAcceptanceCliOptions({
    required this.fingerprintFrameLimit,
    required this.smokeOptions,
  });

  factory _ScriptRecastAcceptanceCliOptions.parse(List<String> args) {
    var fingerprintFrameLimit = 10;
    var smokeEnabled = false;
    var smokeFrameLimit = 1;
    var smokeTargetLimit = 1;
    var smokeEndpoint = 'https://image.novelai.net/ai/generate-image';
    var smokeProxy = '';
    String? smokeOutputDirectory;

    for (final arg in args) {
      if (arg == '--real-api-smoke') {
        smokeEnabled = true;
      } else if (arg.startsWith('--fingerprint-frame-limit=')) {
        fingerprintFrameLimit = _positiveIntOption(
          arg,
          '--fingerprint-frame-limit=',
          fallback: fingerprintFrameLimit,
        );
      } else if (arg.startsWith('--smoke-frame-limit=')) {
        smokeFrameLimit = _positiveIntOption(
          arg,
          '--smoke-frame-limit=',
          fallback: smokeFrameLimit,
        );
      } else if (arg.startsWith('--smoke-target-limit=')) {
        smokeTargetLimit = _positiveIntOption(
          arg,
          '--smoke-target-limit=',
          fallback: smokeTargetLimit,
        );
      } else if (arg.startsWith('--smoke-output-dir=')) {
        smokeOutputDirectory = arg.substring('--smoke-output-dir='.length);
      } else if (arg.startsWith('--smoke-endpoint=')) {
        smokeEndpoint = arg.substring('--smoke-endpoint='.length);
      } else if (arg.startsWith('--smoke-proxy=')) {
        smokeProxy = arg.substring('--smoke-proxy='.length);
      }
    }

    return _ScriptRecastAcceptanceCliOptions(
      fingerprintFrameLimit: fingerprintFrameLimit,
      smokeOptions: ScriptRecastRealSmokeOptions(
        enabled: smokeEnabled,
        frameLimit: smokeFrameLimit,
        targetLimit: smokeTargetLimit,
        endpoint: smokeEndpoint,
        proxy: smokeProxy,
        outputDirectory: smokeOutputDirectory,
      ),
    );
  }
}

class FingerprintSummary {
  final int frameIndex;
  final String sourceFileName;
  final String payloadFingerprint;
  final List<String> policyMetadataKeys;

  const FingerprintSummary({
    required this.frameIndex,
    required this.sourceFileName,
    required this.payloadFingerprint,
    this.policyMetadataKeys = const [],
  });
}

class NaiJsonSnapshot {
  final String path;
  final int length;
  final DateTime lastWriteTimeUtc;
  final String hash;

  const NaiJsonSnapshot({
    required this.path,
    required this.length,
    required this.lastWriteTimeUtc,
    required this.hash,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'length': length,
        'lastWriteTimeUtc': lastWriteTimeUtc.toIso8601String(),
        'hash': hash,
      };
}

class _ProductionPlanProbe {
  final int taskCount;
  final bool fingerprintStable;

  const _ProductionPlanProbe({
    required this.taskCount,
    required this.fingerprintStable,
  });
}

bool _hasToken(String? token) {
  final trimmed = token?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return false;
  }
  final lower = trimmed.toLowerCase();
  return lower != 'null' &&
      lower != 'none' &&
      lower != 'token' &&
      lower != 'pst-abcd' &&
      !lower.contains('placeholder') &&
      !lower.contains('your-token') &&
      !lower.contains('your_api_key');
}

Future<ScriptRecastSmokeLocalConfig> _resolveScriptRecastSmokeConfig() async {
  final localConfigFiles = _defaultLocalConfigFiles();
  final localConfigDirectories = _defaultLocalConfigDirectories();
  final token = await resolveScriptRecastSmokeToken(
    localConfigFiles: localConfigFiles,
    localConfigDirectories: localConfigDirectories,
  );
  final localValues = await _readSmokeLocalConfigValues(
    localConfigFiles,
    localConfigDirectories,
  );
  final environment = Platform.environment;
  return ScriptRecastSmokeLocalConfig(
    apiToken: token,
    proxy: environment['NAI_PROXY']?.trim().isNotEmpty == true
        ? environment['NAI_PROXY']!.trim()
        : localValues.proxy,
    outputDirectory:
        environment['NAI_SMOKE_OUTPUT_DIR']?.trim().isNotEmpty == true
            ? environment['NAI_SMOKE_OUTPUT_DIR']!.trim()
            : localValues.outputDirectory,
  );
}

Future<String?> resolveScriptRecastSmokeToken({
  Map<String, String>? environment,
  List<File>? localConfigFiles,
  List<Directory>? localConfigDirectories,
}) async {
  final envToken =
      _apiTokenFromEnvironment(environment ?? Platform.environment);
  if (_hasToken(envToken)) {
    return envToken!.trim();
  }
  for (final directory
      in localConfigDirectories ?? _defaultLocalConfigDirectories()) {
    final hiveConfig = await _readHiveSmokeLocalConfig(directory);
    if (_hasToken(hiveConfig.apiToken)) {
      return hiveConfig.apiToken!.trim();
    }
  }
  final tokens = <String>[];
  for (final file in localConfigFiles ?? _defaultLocalConfigFiles()) {
    if (!await file.exists()) {
      continue;
    }
    final text = await _decodeLooseText(file);
    tokens.addAll(
      _jsonStringValues(text, 'api_key').where(_hasToken).map(
            (token) => token.trim(),
          ),
    );
  }
  return tokens.isEmpty ? null : tokens.last;
}

String? _apiTokenFromEnvironment(Map<String, String> environment) {
  for (final name in const ['NAI_API_TOKEN', 'NOVELAI_TOKEN', 'NAI_TOKEN']) {
    final value = environment[name];
    if (_hasToken(value)) {
      return value!.trim();
    }
  }
  return null;
}

Future<ScriptRecastSmokeLocalConfig> _readSmokeLocalConfigValues(
  List<File> files,
  List<Directory> directories,
) async {
  var proxy = '';
  String? outputDirectory;
  for (final directory in directories) {
    final hiveConfig = await _readHiveSmokeLocalConfig(directory);
    if (hiveConfig.proxy.trim().isNotEmpty) {
      proxy = hiveConfig.proxy.trim();
    }
    if (hiveConfig.outputDirectory?.trim().isNotEmpty == true) {
      outputDirectory = hiveConfig.outputDirectory!.trim();
    }
  }
  for (final file in files) {
    if (!await file.exists()) {
      continue;
    }
    final text = await _decodeLooseText(file);
    final proxies = _jsonStringValues(text, 'proxy')
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    final outputDirectories = _jsonStringValues(text, 'output_folder')
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (proxies.isNotEmpty) {
      proxy = proxies.last.trim();
    }
    if (outputDirectories.isNotEmpty) {
      outputDirectory = outputDirectories.last.trim();
    }
  }
  return ScriptRecastSmokeLocalConfig(
    proxy: proxy,
    outputDirectory: outputDirectory,
  );
}

Future<ScriptRecastSmokeLocalConfig> _readHiveSmokeLocalConfig(
  Directory directory,
) async {
  if (!await directory.exists()) {
    return const ScriptRecastSmokeLocalConfig();
  }
  try {
    Hive.init(directory.path);
    final box = await Hive.openBox('savedBox');
    try {
      final configJson = _currentSavedConfigJson(box);
      if (configJson == null) {
        return const ScriptRecastSmokeLocalConfig();
      }
      final decoded = jsonDecode(configJson);
      if (decoded is! Map) {
        return const ScriptRecastSmokeLocalConfig();
      }
      final settings = decoded['settings'];
      if (settings is! Map) {
        return const ScriptRecastSmokeLocalConfig();
      }
      final apiToken = settings['api_key'];
      final proxy = settings['proxy'];
      final outputDirectory = settings['output_folder'];
      return ScriptRecastSmokeLocalConfig(
        apiToken:
            apiToken is String && _hasToken(apiToken) ? apiToken.trim() : null,
        proxy: proxy is String ? proxy.trim() : '',
        outputDirectory:
            outputDirectory is String && outputDirectory.trim().isNotEmpty
                ? outputDirectory.trim()
                : null,
      );
    } finally {
      await box.close();
    }
  } catch (_) {
    return const ScriptRecastSmokeLocalConfig();
  }
}

String? _currentSavedConfigJson(Box<dynamic> box) {
  final savedUuid = box.get('savedUuid');
  if (savedUuid is String && savedUuid.trim().isNotEmpty) {
    final saved = box.get('savedConfig-${savedUuid.trim()}');
    if (saved is String && saved.trim().isNotEmpty) {
      return saved;
    }
  }
  final legacySaved = box.get('savedConfig');
  if (legacySaved is String && legacySaved.trim().isNotEmpty) {
    return legacySaved;
  }
  for (final key in box.keys) {
    final keyString = key.toString();
    if (!keyString.startsWith('savedConfig-')) {
      continue;
    }
    final saved = box.get(key);
    if (saved is String && saved.trim().isNotEmpty) {
      return saved;
    }
  }
  return null;
}

List<File> _defaultLocalConfigFiles() {
  final files = <File>[];
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null && userProfile.trim().isNotEmpty) {
    files.add(File(_joinOutputPath(
      _joinOutputPath(userProfile.trim(), 'Documents'),
      'savedbox.hive',
    )));
  }
  files.add(File(r'C:\Users\admin\Documents\savedbox.hive'));
  return files;
}

List<Directory> _defaultLocalConfigDirectories() {
  final directories = <Directory>[];
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null && userProfile.trim().isNotEmpty) {
    directories.add(Directory(
      _joinOutputPath(userProfile.trim(), 'Documents'),
    ));
  }
  directories.add(Directory(r'C:\Users\admin\Documents'));
  return directories;
}

Future<String> _decodeLooseText(File file) async {
  final bytes = await file.readAsBytes();
  return utf8.decode(bytes, allowMalformed: true);
}

List<String> _jsonStringValues(String text, String key) {
  final pattern =
      RegExp('"${RegExp.escape(key)}"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"');
  return [
    for (final match in pattern.allMatches(text))
      _decodeJsonStringFragment(match.group(1) ?? ''),
  ];
}

String _decodeJsonStringFragment(String fragment) {
  try {
    return jsonDecode('"$fragment"') as String;
  } catch (_) {
    return fragment;
  }
}

int _positiveIntOption(
  String arg,
  String prefix, {
  required int fallback,
}) {
  final parsed = int.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

List<String> _policyMetadataKeys(Map<String, dynamic> payload) {
  final matches = <String>[];
  void visit(Object? value, String path) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final childPath = path.isEmpty ? key : '$path.$key';
        if (_isPolicyMetadataKey(key)) {
          matches.add(childPath);
        }
        visit(entry.value, childPath);
      }
    } else if (value is Iterable) {
      var index = 0;
      for (final item in value) {
        visit(item, '$path[$index]');
        index += 1;
      }
    }
  }

  visit(payload, '');
  matches.sort();
  return List.unmodifiable(matches);
}

bool _isPolicyMetadataKey(String key) {
  final lower = key.toLowerCase();
  return lower == 'segmentpolicies' ||
      lower == 'parampolicies' ||
      lower == 'frameoverrides' ||
      lower == 'outputpolicy' ||
      lower.endsWith('policy');
}

bool _snapshotEquals(
  List<NaiJsonSnapshot> before,
  List<NaiJsonSnapshot> after,
) {
  if (before.length != after.length) {
    return false;
  }
  for (var index = 0; index < before.length; index += 1) {
    if (jsonEncode(before[index].toJson()) !=
        jsonEncode(after[index].toJson())) {
      return false;
    }
  }
  return true;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _fingerprintBytes(List<int> bytes) {
  final fnvOffset = BigInt.parse('cbf29ce484222325', radix: 16);
  final fnvPrime = BigInt.parse('100000001b3', radix: 16);
  final mask64 = BigInt.parse('ffffffffffffffff', radix: 16);
  var hash = fnvOffset;
  for (final byte in bytes) {
    hash ^= BigInt.from(byte);
    hash = (hash * fnvPrime) & mask64;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String _fingerprintJson(String canonicalJson) {
  return _fingerprintBytes(utf8.encode(canonicalJson));
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((left, right) => left.key.toString().compareTo(
            right.key.toString(),
          ));
    return {
      for (final entry in entries)
        entry.key.toString(): _canonicalValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  return value;
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.split('/').last;
}

String _slug(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'script' : slug;
}

final _naiFilePattern = RegExp(r'^nai_\d+\.json$');
