import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const _generateEndpoint = 'https://image.novelai.net/ai/generate-image';
const _encodeVibeEndpoint = 'https://image.novelai.net/ai/encode-vibe';
const _model = 'nai-diffusion-4-5-full';
const _proxy = '127.0.0.1:7890';
const _seed = 544890101;

const _outputRoot =
    r'C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest\pepe-multi-angle';
const _whiteStockingMaterialVibe =
    r'C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest\skin-vibes\qaq1-material-swatch-white-stockings-v2.naiv4vibe';

const _artistChain =
    '0.9:: kedama_milk ::, 1.2:: ciloranko ::, 0.35:: ask_(askzy) ::, '
    '0.6:: :mignon ::, 0.51:: rhasta ::, 0.2:: icecake ::, '
    '0.85:: chen_bin ::, 1.5:: detailed ::, 0.8:: docyacico ::, '
    '0.8:: chack520 ::, 1.08:: kimhiro ::, 0.8:: nanmokaken ::, '
    '0.5:: as109 ::';

const _quality = '1.3:: best quality ::, 1.3:: amazing quality ::, '
    '1.3:: very aesthetic ::, 1.3:: incredibly absurdres ::';

const _pepeCharacter =
    'adult Pecorine-inspired original woman, mature proportions, 1girl, solo, '
    'long brown hair, blue eyes, animal ears, white frilled headdress, '
    'gold forehead chain, gold ornaments, teal choker, bracelets, '
    'white fantasy dress, red waist pouch, modest skirt hem down, '
    'white semi-sheer pantyhose, white sheer tights, black mary jane shoes';

const _skinMaterial =
    'soft luminous skin, warm peach skin tone, clean rosy gradients, '
    'subtle warm skin tone visible through white nylon, fine nylon weave, '
    'glossy soft stocking highlights on knees and calves, soft daylight';

const _negative =
    'lowres, bad anatomy, bad hands, missing fingers, extra fingers, '
    'worst quality, low quality, blurry, text, watermark, logo, signature, '
    'child, loli, underage, childlike body, nsfw, nude, explicit, erotic, '
    'fetish pose, crotch focus, upskirt, under skirt, panty shot, '
    'exposed underwear, see-through underwear, skirt lift, clothes lift, '
    'spread legs, high kick, leg up, foot focus, bare legs, black pantyhose, '
    'black stockings, dark stockings, thighhighs, garter belt, lingerie, '
    'swimsuit, bodysuit, close-up thighs, close-up legs, cropped feet, '
    'feet out of frame, ankle crop, cropped head, head out of frame, '
    'multiple girls, 2girls, group, duplicate, extra legs';

Future<void> main() async {
  final token = await _resolveTokenWithRetry();
  if (!_hasToken(token)) {
    stderr.writeln('No NovelAI token found.');
    exitCode = 2;
    return;
  }
  if (!await File(_whiteStockingMaterialVibe).exists()) {
    stderr.writeln('Missing material Vibe: $_whiteStockingMaterialVibe');
    stderr.writeln('Run tool/qaq1_skin_vibe_multiscale_experiment.dart first.');
    exitCode = 3;
    return;
  }

  final client = _createClient(_proxy);
  try {
    final outputDir = Directory(_outputRoot);
    await outputDir.create(recursive: true);

    final sourceVibePath = await _ensurePepeSkinSource033(
      client: client,
      token: token!.trim(),
      outputDir: outputDir,
    );

    final cameras = [
      _CameraSpec(
        id: 'front-fullbody',
        seed: _seed + 1,
        width: 768,
        height: 1344,
        framing: 'eye-level front view, centered full body from head to shoes, '
            'standing in a bright cafe courtyard, gentle smile, relaxed pose, '
            'shoes fully visible near bottom of frame',
      ),
      _CameraSpec(
        id: 'low-angle-stairs',
        seed: _seed + 2,
        width: 768,
        height: 1344,
        framing: 'mild low-angle upward view, camera near ground, standing on '
            'outdoor stone stairs, looking down at viewer, safe fashion pose, '
            'entire full body visible from head to shoes',
      ),
      _CameraSpec(
        id: 'side-three-quarter',
        seed: _seed + 3,
        width: 832,
        height: 1216,
        framing:
            'three-quarter side view, walking through a sunlit market street, '
            'full body in frame, one hand near red waist pouch, shoes visible, '
            'balanced fashion illustration composition',
      ),
      _CameraSpec(
        id: 'high-angle-path',
        seed: _seed + 4,
        width: 832,
        height: 1216,
        framing:
            'slight high-angle view from front, standing on a pale stone path, '
            'looking up gently, full body in frame, shoes visible, '
            'soft cherry blossom background',
      ),
    ];

    for (final camera in cameras) {
      await _runCameraSet(
        client: client,
        token: token.trim(),
        outputDir: outputDir,
        camera: camera,
        sourceVibePath: sourceVibePath,
      );
    }
  } finally {
    client.close();
  }
}

Future<String> _ensurePepeSkinSource033({
  required http.Client client,
  required String token,
  required Directory outputDir,
}) async {
  final sourcePng = '${outputDir.path}${Platform.pathSeparator}'
      'pepe-skin-source-033-seed${_seed + 33}.png';
  final sourceVibe = '${outputDir.path}${Platform.pathSeparator}'
      'pepe-skin-source-033.naiv4vibe';
  const prompt = '$_quality, $_artistChain, $_pepeCharacter, $_skinMaterial, '
      'neutral full-body standing pose, eye-level camera, white studio garden, '
      'simple pale background, safe non-explicit fashion illustration, '
      'entire body visible from head to shoes';

  if (!await File(sourcePng).exists()) {
    stdout.writeln('Generating 0.33 skin source PNG -> $sourcePng');
    final bytes = await _requestNaiImage(
      client: client,
      token: token,
      payload: _payload(
        input: prompt,
        negative: _negative,
        width: 768,
        height: 1344,
        seed: _seed + 33,
        scale: 4.5,
        cfgRescale: 0.35,
        vibes: const [],
      ),
    );
    await _writeBytes(sourcePng, bytes);
  } else {
    stdout.writeln('Keeping 0.33 skin source PNG -> $sourcePng');
  }

  if (!await File(sourceVibe).exists()) {
    stdout.writeln('Encoding 0.33 skin source Vibe -> $sourceVibe');
    final encoding = await _encodeVibe(
      client: client,
      token: token,
      imageBytes: await File(sourcePng).readAsBytes(),
    );
    await _writeNaiV4Vibe(
      path: sourceVibe,
      name: 'QAQ1 Pepe skin effect source 0.33',
      encoding: encoding,
      sourceImagePath: sourcePng,
      defaultInfo: 0.33,
      defaultStrength: 0.33,
    );
  } else {
    stdout.writeln('Keeping 0.33 skin source Vibe -> $sourceVibe');
  }
  return sourceVibe;
}

Future<void> _runCameraSet({
  required http.Client client,
  required String token,
  required Directory outputDir,
  required _CameraSpec camera,
  required String sourceVibePath,
}) async {
  final prompt = '$_quality, $_artistChain, $_pepeCharacter, $_skinMaterial, '
      '${camera.framing}, safe non-explicit fashion illustration';
  final basePath = '${outputDir.path}${Platform.pathSeparator}'
      '${camera.id}-no-vibe-seed${camera.seed}.png';
  if (!await File(basePath).exists()) {
    stdout.writeln('Generating ${camera.id} no-vibe -> $basePath');
    final bytes = await _requestNaiImage(
      client: client,
      token: token,
      payload: _payload(
        input: prompt,
        negative: _negative,
        width: camera.width,
        height: camera.height,
        seed: camera.seed,
        scale: 4.5,
        cfgRescale: 0.35,
        vibes: const [],
      ),
    );
    await _writeBytes(basePath, bytes);
  } else {
    stdout.writeln('Keeping ${camera.id} no-vibe -> $basePath');
  }

  final anchorPath = '${outputDir.path}${Platform.pathSeparator}'
      '${camera.id}-composition-anchor.naiv4vibe';
  if (!await File(anchorPath).exists()) {
    stdout.writeln('Encoding ${camera.id} composition anchor -> $anchorPath');
    final encoding = await _encodeVibe(
      client: client,
      token: token,
      imageBytes: await File(basePath).readAsBytes(),
    );
    await _writeNaiV4Vibe(
      path: anchorPath,
      name: 'QAQ1 Pepe ${camera.id} composition anchor',
      encoding: encoding,
      sourceImagePath: basePath,
      defaultInfo: 0.05,
      defaultStrength: 0.22,
    );
  } else {
    stdout.writeln('Keeping ${camera.id} composition anchor -> $anchorPath');
  }

  final variants = [
    _VariantSpec(
      id: 'source033',
      outputName: '${camera.id}-source033-i033-s033-seed${camera.seed}.png',
      vibes: [
        _VibeRef.file(sourceVibePath, info: 0.33, strength: 0.33),
      ],
    ),
    _VariantSpec(
      id: 'controlled',
      outputName:
          '${camera.id}-controlled-material-source-anchor-seed${camera.seed}.png',
      vibes: [
        _VibeRef.file(_whiteStockingMaterialVibe, info: 0.02, strength: 0.18),
        _VibeRef.file(sourceVibePath, info: 0.08, strength: 0.08),
        _VibeRef.file(anchorPath, info: 0.05, strength: 0.22),
      ],
    ),
    _VariantSpec(
      id: 'material-anchor',
      outputName:
          '${camera.id}-material-anchor-i002-s020-a026-seed${camera.seed}.png',
      vibes: [
        _VibeRef.file(_whiteStockingMaterialVibe, info: 0.02, strength: 0.20),
        _VibeRef.file(anchorPath, info: 0.06, strength: 0.26),
      ],
    ),
  ];

  for (final variant in variants) {
    final outputPath = '${outputDir.path}${Platform.pathSeparator}'
        '${variant.outputName}';
    if (await File(outputPath).exists()) {
      stdout.writeln('Keeping ${camera.id} ${variant.id} -> $outputPath');
      continue;
    }
    stdout.writeln('Generating ${camera.id} ${variant.id} -> $outputPath');
    final bytes = await _requestNaiImage(
      client: client,
      token: token,
      payload: _payload(
        input: prompt,
        negative: _negative,
        width: camera.width,
        height: camera.height,
        seed: camera.seed,
        scale: 4.5,
        cfgRescale: 0.35,
        vibes: variant.vibes,
      ),
    );
    await _writeBytes(outputPath, bytes);
  }
}

Map<String, dynamic> _payload({
  required String input,
  required String negative,
  required int width,
  required int height,
  required int seed,
  required double scale,
  required double cfgRescale,
  required List<_VibeRef> vibes,
}) {
  final resolved = vibes.map(_resolveVibe).toList(growable: false);
  final parameters = <String, dynamic>{
    'params_version': 3,
    'width': width,
    'height': height,
    'scale': scale,
    'sampler': 'k_euler_ancestral',
    'steps': 28,
    'n_samples': 1,
    'ucPreset': 2,
    'qualityToggle': false,
    'dynamic_thresholding': false,
    'controlnet_strength': 1.0,
    'legacy': false,
    'add_original_image': true,
    'cfg_rescale': cfgRescale,
    'noise_schedule': 'karras',
    'skip_cfg_above_sigma': null,
    'use_coords': false,
    'seed': seed,
    'characterPrompts': <dynamic>[],
    'v4_prompt': {
      'caption': {
        'base_caption': input,
        'char_captions': <dynamic>[],
      },
      'use_coords': false,
      'use_order': true,
    },
    'v4_negative_prompt': {
      'caption': {
        'base_caption': negative,
        'char_captions': <dynamic>[],
      },
      'legacy_uc': false,
    },
    'negative_prompt': negative,
    'reference_image_multiple':
        resolved.map((reference) => reference.encoding).toList(),
    'reference_information_extracted_multiple':
        resolved.map((reference) => reference.info).toList(),
    'reference_strength_multiple':
        resolved.map((reference) => reference.strength).toList(),
    'legacy_v3_extend': false,
    'legacy_uc': false,
  };
  parameters.removeWhere((_, value) => value == null);

  return {
    'input': input,
    'model': _model,
    'action': 'generate',
    'parameters': parameters,
  };
}

Future<Uint8List> _requestNaiImage({
  required http.Client client,
  required String token,
  required Map<String, dynamic> payload,
}) async {
  for (var attempt = 1; attempt <= 3; attempt++) {
    final response = await client.post(
      Uri.parse(_generateEndpoint),
      headers: _headersForToken(token),
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _extractImage(response.bodyBytes);
    }
    if ((response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500) &&
        attempt < 3) {
      await Future<void>.delayed(Duration(seconds: 3 * attempt));
      continue;
    }
    throw Exception(
      'NovelAI generate failed HTTP ${response.statusCode}: '
      '${_sanitizeError(response.body, token)}',
    );
  }
  throw StateError('NovelAI generate exhausted without response.');
}

Future<String> _encodeVibe({
  required http.Client client,
  required String token,
  required Uint8List imageBytes,
}) async {
  final response = await client.post(
    Uri.parse(_encodeVibeEndpoint),
    headers: _headersForToken(token),
    body: jsonEncode({
      'image': base64Encode(imageBytes),
      'information_extracted': 1,
      'mask': null,
      'model': _model,
    }),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'NovelAI encode-vibe failed HTTP ${response.statusCode}: '
      '${_sanitizeError(response.body, token)}',
    );
  }
  return base64Encode(response.bodyBytes);
}

Future<void> _writeNaiV4Vibe({
  required String path,
  required String name,
  required String encoding,
  required String sourceImagePath,
  required double defaultInfo,
  required double defaultStrength,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final now = DateTime.now().millisecondsSinceEpoch;
  final id = _randomHex(12);
  final json = {
    'identifier': 'novelai-vibe-transfer',
    'version': 1,
    'type': 'encoding',
    'id': id,
    'encodings': {
      'v4-5full': {
        'unknown': {'encoding': encoding},
      },
    },
    'name': name,
    'createdAt': now,
    'importInfo': {
      'model': _model,
      'information_extracted': defaultInfo,
      'strength': defaultStrength,
      'sourceImagePath': sourceImagePath,
    },
  };
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
}

_ResolvedVibe _resolveVibe(_VibeRef ref) {
  final decoded = jsonDecode(File(ref.path).readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Vibe file must contain a JSON object: ${ref.path}');
  }
  final encoding = _extractVibeEncoding(decoded);
  if (encoding == null || encoding.trim().isEmpty) {
    throw FormatException("Could not find encoding in vibe file: ${ref.path}");
  }
  return _ResolvedVibe(
    encoding: encoding.trim(),
    info: ref.info.clamp(0.0, 1.0).toDouble(),
    strength: ref.strength.clamp(0.0, 1.0).toDouble(),
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

Uint8List _extractImage(Uint8List responseBytes) {
  final archive = ZipDecoder().decodeBytes(responseBytes);
  for (final file in archive.files) {
    if (file.name == 'image_0.png') {
      return Uint8List.fromList(file.content as List<int>);
    }
  }
  throw const FormatException('NovelAI response did not contain image_0.png.');
}

Future<void> _writeBytes(String outputPath, Uint8List bytes) async {
  final file = File(outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

http.Client _createClient(String proxy) {
  if (proxy.trim().isEmpty) return http.Client();
  final ioClient = HttpClient();
  ioClient.findProxy = (_) => 'PROXY ${proxy.trim()}';
  ioClient.badCertificateCallback = (_, __, ___) => true;
  return IOClient(ioClient);
}

Map<String, String> _headersForToken(String token) => {
      'content-type': 'application/json',
      'authorization': 'Bearer ${token.trim()}',
      'referer': 'https://novelai.net',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0',
    };

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
    if (pstMatches.isNotEmpty) return pstMatches.last.trim();
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
        RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'),
        'Bearer [redacted-token]',
      )
      .replaceAll(RegExp(r'pst-[A-Za-z0-9_-]+'), '[redacted-token]');
}

String _randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class _CameraSpec {
  final String id;
  final int seed;
  final int width;
  final int height;
  final String framing;

  const _CameraSpec({
    required this.id,
    required this.seed,
    required this.width,
    required this.height,
    required this.framing,
  });
}

class _VariantSpec {
  final String id;
  final String outputName;
  final List<_VibeRef> vibes;

  const _VariantSpec({
    required this.id,
    required this.outputName,
    required this.vibes,
  });
}

class _VibeRef {
  final String path;
  final double info;
  final double strength;

  const _VibeRef.file(
    this.path, {
    required this.info,
    required this.strength,
  });
}

class _ResolvedVibe {
  final String encoding;
  final double info;
  final double strength;

  const _ResolvedVibe({
    required this.encoding,
    required this.info,
    required this.strength,
  });
}
