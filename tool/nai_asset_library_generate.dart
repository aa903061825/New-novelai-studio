import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/param_config.dart';

const _defaultQueuePath = r'tool\asset-library-image-queue.json';
const _defaultEndpoint = 'https://image.novelai.net/ai/generate-image';
const _defaultPreviewRoot = r'E:\codeximage\nai-new\preview-images';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final token = await _resolveTokenWithRetry();
  if (!_hasToken(token)) {
    stderr.writeln(
      'No NovelAI token found. Set NAI_API_TOKEN, NOVELAI_TOKEN, or NAI_TOKEN, '
      'or save the token in the app config.',
    );
    exitCode = 2;
    return;
  }

  final queue = _readQueue(options.queuePath);
  final pending = queue
      .where((item) => !File(item.outputPath).existsSync())
      .take(options.limit)
      .toList(growable: false);
  if (pending.isEmpty) {
    stdout.writeln('No pending NAI asset previews.');
    return;
  }

  final client = _createClient(options.proxy);
  stdout.writeln(
    'NAI generation mode: sequential; inter-image delay=${options.delayMs}ms; '
    'retry delay=${options.retryDelayMs}ms.',
  );
  try {
    for (var index = 0; index < pending.length; index++) {
      final item = pending[index];
      final effectiveSeed = item.seed ??
          (options.seed == null ? _randomSeed() : options.seed! + index);
      final payload = _payloadForItem(item: item, seed: effectiveSeed);
      stdout.writeln(
        '[${index + 1}/${pending.length}] NAI generating ${item.id} -> ${item.outputPath}',
      );
      final bytes = await _requestNaiImage(
        client: client,
        token: token!.trim(),
        endpoint: options.endpoint,
        payload: payload,
        maxAttempts: options.retryCount,
        retryDelayMs: options.retryDelayMs,
      );
      await _writeImage(item.outputPath, bytes);
      await _copyPreview(item.outputPath, options.previewRoot);
      if (item.requestPayloadManifestPath != null) {
        await _appendRequestPayload(
          item.requestPayloadManifestPath!,
          id: item.id,
          seed: effectiveSeed,
          payload: payload,
        );
      }
      if (options.delayMs > 0 && index < pending.length - 1) {
        await Future<void>.delayed(Duration(milliseconds: options.delayMs));
      }
    }
  } finally {
    client.close();
  }
}

Future<String?> _resolveTokenWithRetry() async {
  final envToken = _tokenFromEnvironment();
  if (_hasToken(envToken)) return envToken!.trim();
  final looseHiveToken = await _tokenFromLooseHiveFile();
  if (_hasToken(looseHiveToken)) return looseHiveToken!.trim();
  return _tokenFromKnownLocalConfigFiles();
}

String? _tokenFromEnvironment() {
  for (final name in const ['NAI_API_TOKEN', 'NOVELAI_TOKEN', 'NAI_TOKEN']) {
    final value = Platform.environment[name];
    if (_hasToken(value)) return value!.trim();
  }
  return null;
}

Future<String?> _tokenFromLooseHiveFile() async {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null || home.trim().isEmpty) return null;
  final file = File('${home.trim()}${Platform.pathSeparator}Documents'
      '${Platform.pathSeparator}savedbox.hive');
  if (!await file.exists()) return null;
  try {
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    final pstMatches = RegExp(r'pst-[A-Za-z0-9_-]+')
        .allMatches(text)
        .map((match) => match.group(0))
        .where(_hasToken)
        .cast<String>()
        .toList(growable: false);
    if (pstMatches.isNotEmpty) {
      return pstMatches.last.trim();
    }
    final jsonMatch = RegExp(r'"api_key"\s*:\s*"([^"]+)"').firstMatch(text);
    final token = jsonMatch?.group(1);
    if (_hasToken(token)) return token!.trim();
  } catch (_) {
    return null;
  }
  return null;
}

Future<String?> _tokenFromKnownLocalConfigFiles() async {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  final files = <File>[
    if (home != null && home.trim().isNotEmpty)
      File('${home.trim()}${Platform.pathSeparator}Documents'
          '${Platform.pathSeparator}savedbox.hive'),
    File(r'C:\Users\admin\Documents\savedbox.hive'),
  ];
  final tokens = <String>[];
  for (final file in files) {
    if (!await file.exists()) continue;
    try {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      tokens.addAll(
        _jsonStringValues(text, 'api_key').where(_hasToken).map(
              (token) => token.trim(),
            ),
      );
      tokens.addAll(
        RegExp(r'pst-[A-Za-z0-9_-]+')
            .allMatches(text)
            .map((match) => match.group(0))
            .where(_hasToken)
            .cast<String>(),
      );
    } catch (_) {
      continue;
    }
  }
  return tokens.isEmpty ? null : tokens.last.trim();
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

List<_QueueItem> _readQueue(String queuePath) {
  final raw = File(queuePath).readAsStringSync();
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw const FormatException('Asset image queue must be a JSON array.');
  }
  return decoded
      .whereType<Map>()
      .map((entry) => _QueueItem.fromJson(entry.cast<String, dynamic>()))
      .toList(growable: false);
}

Future<Uint8List> _requestNaiImage({
  required http.Client client,
  required String token,
  required String endpoint,
  required Map<String, dynamic> payload,
  required int maxAttempts,
  required int retryDelayMs,
}) async {
  final request = ApiRequest(
    endpoint: endpoint,
    proxy: '',
    headers: _headersForToken(token),
    payload: payload,
  );
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    late final http.Response response;
    try {
      response = await client.post(
        Uri.parse(request.endpoint),
        headers: request.headers,
        body: jsonEncode(request.payload),
      );
    } catch (error) {
      if (attempt < maxAttempts) {
        await _waitBeforeRetry(
          retryDelayMs: retryDelayMs,
          attempt: attempt,
          maxAttempts: maxAttempts,
          reason: 'NovelAI request error: $error',
        );
        continue;
      }
      rethrow;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _extractImage(response.bodyBytes);
    }
    if (_shouldRetryStatus(response.statusCode) && attempt < maxAttempts) {
      await _waitBeforeRetry(
        retryDelayMs: retryDelayMs,
        attempt: attempt,
        maxAttempts: maxAttempts,
        reason: 'NovelAI request failed with HTTP ${response.statusCode}: '
            '${_sanitizeError(response.body, token)}',
      );
      continue;
    }
    throw Exception(
      'NovelAI request failed with HTTP ${response.statusCode}: '
      '${_sanitizeError(response.body, token)}',
    );
  }
  throw StateError('NovelAI request exhausted without a response.');
}

Future<void> _appendRequestPayload(
  String manifestPath, {
  required String id,
  required int seed,
  required Map<String, dynamic> payload,
}) async {
  final file = File(manifestPath);
  List<dynamic> entries = const [];
  if (await file.exists()) {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) entries = decoded;
    } catch (_) {
      entries = const [];
    }
  }
  final updated = [
    ...entries.where((entry) => entry is! Map || entry['id'] != id),
    {
      'id': id,
      'seed': seed,
      'payload': payload,
    },
  ];
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(updated));
}

bool _shouldRetryStatus(int statusCode) {
  return statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

Future<void> _waitBeforeRetry({
  required int retryDelayMs,
  required int attempt,
  required int maxAttempts,
  required String reason,
}) async {
  final delay = Duration(milliseconds: retryDelayMs * attempt);
  stderr.writeln(
    '$reason; retrying in ${delay.inSeconds}s '
    '(attempt ${attempt + 1}/$maxAttempts).',
  );
  await Future<void>.delayed(delay);
}

Map<String, String> _headersForToken(String token) => {
      'content-type': 'application/json',
      'authorization': 'Bearer ${token.trim()}',
      'referer': 'https://novelai.net',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0',
    };

Map<String, dynamic> _payloadForItem({
  required _QueueItem item,
  required int seed,
}) {
  final prompt = item.prompt;
  final model = item.model ?? 'nai-diffusion-4-5-full';
  if (GenerationModelCapabilities.fromModel(model).isV5) {
    return _v5PayloadForItem(
      item: item,
      model: model,
      prompt: prompt,
      seed: seed,
    );
  }
  final vibeReferences = _resolveVibeReferences(item);
  final negative = item.negativePrompt ??
      'lowres, bad anatomy, bad hands, missing fingers, extra fingers, '
          'worst quality, low quality, blurry, text, watermark, logo, signature, '
          'nsfw, nude, explicit, multiple girls, 2girls, 3girls, group, crowd, '
          'multiple views, character sheet, reference sheet, collage, grid, panel, '
          'comic, manga panel, speech bubble, chibi, mascot, creature, monster, '
          'censored, mosaic censoring, black bars, cropped, out of frame, '
          'extra arms, extra legs, duplicate, clone, bad feet, malformed feet';
  final parameters = <String, dynamic>{
    'params_version': 3,
    'width': item.width ?? 832,
    'height': item.height ?? 1216,
    'scale': item.scale ?? 5.5,
    'sampler': item.sampler ?? 'k_euler_ancestral',
    'steps': item.steps ?? 28,
    'n_samples': 1,
    'ucPreset': item.ucPreset ?? 2,
    'qualityToggle': item.qualityToggle ?? false,
    'dynamic_thresholding': item.dynamicThresholding ?? false,
    'controlnet_strength': 1.0,
    'legacy': item.legacy ?? false,
    'add_original_image': true,
    'cfg_rescale': item.cfgRescale ?? 0.1,
    'noise_schedule': item.noiseSchedule ?? 'karras',
    'skip_cfg_above_sigma': null,
    'use_coords': item.useCoords ?? true,
    'seed': seed,
    'characterPrompts': <dynamic>[],
    'v4_prompt': {
      'caption': {
        'base_caption': prompt,
        'char_captions': <dynamic>[],
      },
      'use_coords': item.useCoords ?? true,
      'use_order': item.useOrder ?? true,
    },
    'v4_negative_prompt': {
      'caption': {
        'base_caption': negative,
        'char_captions': <dynamic>[],
      },
      'legacy_uc': item.legacyUc ?? false,
    },
    'negative_prompt': negative,
    'reference_image_multiple':
        vibeReferences.map((reference) => reference.encoding).toList(),
    'reference_information_extracted_multiple':
        vibeReferences.map((_) => 1.0).toList(),
    'reference_strength_multiple':
        vibeReferences.map((reference) => reference.strength).toList(),
    'legacy_v3_extend': false,
    'legacy_uc': item.legacyUc ?? false,
  };
  parameters.removeWhere((_, value) => value == null);
  return {
    'input': prompt,
    'model': model,
    'action': item.action ?? 'generate',
    'parameters': parameters,
  };
}

Map<String, dynamic> _v5PayloadForItem({
  required _QueueItem item,
  required String model,
  required String prompt,
  required int seed,
}) {
  final negative = item.negativePrompt ??
      'lowres, bad anatomy, bad hands, missing fingers, extra fingers, '
          'worst quality, low quality, blurry, text, watermark, logo, signature, '
          'nsfw, nude, explicit, multiple girls, 2girls, 3girls, group, crowd, '
          'multiple views, character sheet, reference sheet, collage, grid, panel, '
          'comic, manga panel, speech bubble, chibi, mascot, creature, monster, '
          'censored, mosaic censoring, black bars, cropped, out of frame, '
          'extra arms, extra legs, duplicate, clone, bad feet, malformed feet';
  final parameters = ParamConfig(
    model: model,
    sizes: [
      GenerationSize(
        width: item.width ?? 832,
        height: item.height ?? 1216,
      ),
    ],
    scale: item.scale ?? 6.5,
    sampler: item.sampler ?? 'k_euler_ancestral',
    steps: item.steps ?? 28,
    randomSeed: false,
    seed: seed,
    nSamples: 1,
    qualityToggle: item.qualityToggle ?? false,
    qualityPreset: item.qualityPreset ??
        ((item.qualityToggle ?? false) ? 'standard' : 'none'),
    ucPresetMode: item.ucPresetMode ?? 'none',
    dynamicThresholding: item.dynamicThresholding ?? false,
    legacy: item.legacy ?? false,
    cfgRescale: item.cfgRescale ?? 0.1,
    noiseSchedule: item.noiseSchedule ?? 'native',
    negativePrompt: negative,
    legacyUc: item.legacyUc ?? false,
  ).getPayload();
  parameters['v4_prompt'] = _structuredPrompt(prompt);
  parameters['v4_negative_prompt'] = _structuredPrompt(negative);
  return {
    'input': prompt,
    'model': model,
    'action': item.action ?? 'generate',
    'parameters': parameters,
  };
}

Map<String, dynamic> _structuredPrompt(String baseCaption) {
  return {
    'caption': {
      'base_caption': baseCaption,
      'char_captions': <dynamic>[],
    },
    'use_coords': false,
    'use_order': true,
  };
}

List<_ResolvedVibeReference> _resolveVibeReferences(_QueueItem item) {
  final references = <_ResolvedVibeReference>[];
  for (final reference in item.vibeReferences) {
    if (reference.vibeB64 != null && reference.vibeB64!.trim().isNotEmpty) {
      references.add(
        _ResolvedVibeReference(
          encoding: reference.vibeB64!.trim(),
          strength: _clampStrength(reference.strength ?? 0.3),
        ),
      );
      continue;
    }
    final sourcePath = reference.path;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      throw FormatException(
        'Vibe reference for ${item.id} must include either path or vibeB64.',
      );
    }
    references.add(_readNaiV4VibeFile(sourcePath.trim(), reference.strength));
  }
  return references;
}

_ResolvedVibeReference _readNaiV4VibeFile(
  String filePath,
  double? overrideStrength,
) {
  final decoded = jsonDecode(File(filePath).readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Vibe file must contain a JSON object: $filePath');
  }

  final encoding = _extractVibeEncoding(decoded);
  if (encoding == null || encoding.trim().isEmpty) {
    throw FormatException(
      "Could not find a valid 'encoding' field in vibe file: $filePath",
    );
  }

  final embeddedStrength = _optionalDouble(
    (decoded['importInfo'] is Map)
        ? (decoded['importInfo'] as Map)['strength']
        : null,
  );
  return _ResolvedVibeReference(
    encoding: encoding.trim(),
    strength: _clampStrength(overrideStrength ?? embeddedStrength ?? 0.3),
  );
}

String? _extractVibeEncoding(Map<String, dynamic> json) {
  final direct = json['encoding'];
  if (direct is String && direct.isNotEmpty) return direct;

  final encodings = json['encodings'];
  if (encodings is! Map) return null;
  for (final modelEntry in encodings.values) {
    if (modelEntry is! Map) continue;
    for (final typeEntry in modelEntry.values) {
      if (typeEntry is! Map) continue;
      final encoding = typeEntry['encoding'];
      if (encoding is String && encoding.isNotEmpty) return encoding;
    }
  }
  return null;
}

double _clampStrength(double value) => value.clamp(0.0, 1.0).toDouble();

Uint8List _extractImage(Uint8List responseBytes) {
  final archive = ZipDecoder().decodeBytes(responseBytes);
  for (final file in archive.files) {
    if (file.name == 'image_0.png') {
      return Uint8List.fromList(file.content as List<int>);
    }
  }
  throw const FormatException('NovelAI response did not contain image_0.png.');
}

Future<void> _writeImage(String outputPath, Uint8List bytes) async {
  final file = File(outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

Future<void> _copyPreview(String outputPath, String previewRoot) async {
  final source = File(outputPath);
  final normalizedPreviewRoot =
      previewRoot.endsWith(r'\') || previewRoot.endsWith('/')
          ? previewRoot
          : '$previewRoot${Platform.pathSeparator}';
  final preview = File(
    '$normalizedPreviewRoot${_fileName(outputPath)}',
  );
  await preview.parent.create(recursive: true);
  await source.copy(preview.path);
}

http.Client _createClient(String proxy) {
  if (proxy.trim().isEmpty) return http.Client();
  final ioClient = HttpClient();
  ioClient.findProxy = (_) => 'PROXY ${proxy.trim()}';
  ioClient.badCertificateCallback = (_, __, ___) => true;
  return IOClient(ioClient);
}

int _randomSeed() => Random.secure().nextInt(1 << 32);

bool _hasToken(String? token) {
  final trimmed = token?.trim();
  if (trimmed == null || trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  return lower != 'null' &&
      lower != 'none' &&
      lower != 'token' &&
      !lower.contains('placeholder') &&
      !lower.contains('your-token') &&
      !lower.contains('your_api_key');
}

String _sanitizeError(String message, String token) {
  return message
      .replaceAll(token, '[redacted-token]')
      .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer [redacted-token]')
      .replaceAll(RegExp(r'pst-[A-Za-z0-9_-]+'), '[redacted-token]');
}

String _fileName(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

class _QueueItem {
  final String id;
  final String prompt;
  final String outputPath;
  final List<_VibeReference> vibeReferences;
  final String? negativePrompt;
  final String? model;
  final String? action;
  final int? width;
  final int? height;
  final int? steps;
  final String? sampler;
  final String? noiseSchedule;
  final double? scale;
  final double? cfgRescale;
  final int? ucPreset;
  final bool? qualityToggle;
  final bool? dynamicThresholding;
  final bool? legacy;
  final bool? legacyUc;
  final bool? useCoords;
  final bool? useOrder;
  final String? qualityPreset;
  final String? ucPresetMode;
  final int? seed;
  final String? requestPayloadManifestPath;

  const _QueueItem({
    required this.id,
    required this.prompt,
    required this.outputPath,
    this.vibeReferences = const [],
    this.negativePrompt,
    this.model,
    this.action,
    this.width,
    this.height,
    this.steps,
    this.sampler,
    this.noiseSchedule,
    this.scale,
    this.cfgRescale,
    this.ucPreset,
    this.qualityToggle,
    this.dynamicThresholding,
    this.legacy,
    this.legacyUc,
    this.useCoords,
    this.useOrder,
    this.qualityPreset,
    this.ucPresetMode,
    this.seed,
    this.requestPayloadManifestPath,
  });

  factory _QueueItem.fromJson(Map<String, dynamic> json) {
    return _QueueItem(
      id: json['id'] as String,
      prompt: json['prompt'] as String,
      outputPath: json['outputPath'] as String,
      vibeReferences: _parseVibeReferences(json),
      negativePrompt: json['negativePrompt'] as String?,
      model: json['model'] as String?,
      action: json['action'] as String?,
      width: _optionalInt(json['width']),
      height: _optionalInt(json['height']),
      steps: _optionalInt(json['steps']),
      sampler: json['sampler'] as String?,
      noiseSchedule: json['noise_schedule'] as String?,
      scale: _optionalDouble(json['scale']),
      cfgRescale: _optionalDouble(json['cfg_rescale']),
      ucPreset: _optionalInt(json['ucPreset']),
      qualityToggle: json['qualityToggle'] as bool?,
      dynamicThresholding: json['dynamic_thresholding'] as bool?,
      legacy: json['legacy'] as bool?,
      legacyUc: json['legacy_uc'] as bool?,
      useCoords: json['use_coords'] as bool?,
      useOrder: json['use_order'] as bool?,
      qualityPreset: json['quality_preset'] as String?,
      ucPresetMode: json['uc_preset_mode'] as String?,
      seed: _optionalInt(json['seed']),
      requestPayloadManifestPath: json['requestPayloadManifestPath'] as String?,
    );
  }
}

class _VibeReference {
  final String? path;
  final String? vibeB64;
  final double? strength;

  const _VibeReference({
    this.path,
    this.vibeB64,
    this.strength,
  });
}

class _ResolvedVibeReference {
  final String encoding;
  final double strength;

  const _ResolvedVibeReference({
    required this.encoding,
    required this.strength,
  });
}

List<_VibeReference> _parseVibeReferences(Map<String, dynamic> json) {
  final references = <_VibeReference>[];
  final rawReferences = json['vibeReferences'];
  if (rawReferences is List) {
    for (final entry in rawReferences) {
      if (entry is String) {
        references.add(_VibeReference(path: entry));
      } else if (entry is Map) {
        references.add(
          _VibeReference(
            path: entry['path'] as String?,
            vibeB64: (entry['vibeB64'] ?? entry['vibe_b64']) as String?,
            strength: _optionalDouble(
              entry['strength'] ??
                  entry['referenceStrength'] ??
                  entry['reference_strength'],
            ),
          ),
        );
      }
    }
  }

  final rawPaths = json['vibePaths'];
  if (rawPaths is List) {
    for (final path in rawPaths.whereType<String>()) {
      references.add(_VibeReference(path: path));
    }
  }
  return references;
}

int? _optionalInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

double? _optionalDouble(dynamic value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return null;
}

class _Options {
  final String queuePath;
  final String endpoint;
  final String previewRoot;
  final String proxy;
  final int limit;
  final int delayMs;
  final int retryCount;
  final int retryDelayMs;
  final int? seed;

  const _Options({
    required this.queuePath,
    required this.endpoint,
    required this.previewRoot,
    required this.proxy,
    required this.limit,
    required this.delayMs,
    required this.retryCount,
    required this.retryDelayMs,
    required this.seed,
  });

  factory _Options.parse(List<String> args) {
    var queuePath = _defaultQueuePath;
    var endpoint = _defaultEndpoint;
    var previewRoot = _defaultPreviewRoot;
    var proxy = Platform.environment['NAI_PROXY'] ?? '';
    var limit = 1;
    var delayMs = 1200;
    var retryCount = 6;
    var retryDelayMs = 15000;
    int? seed;

    for (final arg in args) {
      if (arg.startsWith('--queue=')) {
        queuePath = arg.substring('--queue='.length);
      } else if (arg.startsWith('--endpoint=')) {
        endpoint = arg.substring('--endpoint='.length);
      } else if (arg.startsWith('--preview-root=')) {
        previewRoot = arg.substring('--preview-root='.length);
      } else if (arg.startsWith('--proxy=')) {
        proxy = arg.substring('--proxy='.length);
      } else if (arg.startsWith('--limit=')) {
        limit = int.tryParse(arg.substring('--limit='.length)) ?? limit;
      } else if (arg.startsWith('--delay-ms=')) {
        delayMs = int.tryParse(arg.substring('--delay-ms='.length)) ?? delayMs;
      } else if (arg.startsWith('--delay=')) {
        delayMs = int.tryParse(arg.substring('--delay='.length)) ?? delayMs;
      } else if (arg.startsWith('--retry-count=')) {
        retryCount =
            int.tryParse(arg.substring('--retry-count='.length)) ?? retryCount;
      } else if (arg.startsWith('--retry-delay-ms=')) {
        retryDelayMs =
            int.tryParse(arg.substring('--retry-delay-ms='.length)) ??
                retryDelayMs;
      } else if (arg.startsWith('--retry-delay=')) {
        retryDelayMs = int.tryParse(arg.substring('--retry-delay='.length)) ??
            retryDelayMs;
      } else if (arg.startsWith('--seed=')) {
        seed = int.tryParse(arg.substring('--seed='.length));
      }
    }

    return _Options(
      queuePath: queuePath,
      endpoint: endpoint,
      previewRoot: previewRoot,
      proxy: proxy,
      limit: limit < 1 ? 1 : limit,
      delayMs: delayMs < 0 ? 0 : delayMs,
      retryCount: retryCount < 1 ? 1 : retryCount,
      retryDelayMs: retryDelayMs < 0 ? 0 : retryDelayMs,
      seed: seed,
    );
  }
}
