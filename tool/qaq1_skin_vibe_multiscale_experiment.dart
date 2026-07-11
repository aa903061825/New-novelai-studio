import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image/image.dart' as img;

const _generateEndpoint = 'https://image.novelai.net/ai/generate-image';
const _encodeVibeEndpoint = 'https://image.novelai.net/ai/encode-vibe';
const _model = 'nai-diffusion-4-5-full';
const _seed = 544884037;
const _proxy = '127.0.0.1:7890';

const _outputRoot =
    r'C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest';
const _noVibeBase =
    r'C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest\hanabi-p1-qaq1-reweighted-no-vibe-seed544884037.png';
const _skinTarget =
    r'C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest\hanabi-p1-qaq1-reweighted-vibe033-skin-target-seed544884037.png';

const _artistChain =
    '0.9:: kedama_milk ::, 1.2:: ciloranko ::, 0.35:: ask_(askzy) ::, '
    '0.6:: :mignon ::, 0.51:: rhasta ::, 0.2:: icecake ::, '
    '0.85:: chen_bin ::, 1.5:: detailed ::, 0.8:: docyacico ::, '
    '0.8:: chack520 ::, 1.08:: kimhiro ::, 0.8:: nanmokaken ::, '
    '0.5:: as109 ::';

const _quality = '1.3:: best quality ::, 1.3:: amazing quality ::, '
    '1.3:: very aesthetic ::, 1.3:: incredibly absurdres ::';

const _skinMaterial =
    'soft luminous skin, warm peach skin tone, clean rosy gradients, '
    'delicate blush on skin, glossy smooth skin highlights, soft rim light, '
    'gentle translucent nylon sheen, sheer black pantyhose, '
    'subtle fabric translucency over knees and calves, polished anime shading';

const _sourceNegative =
    'lowres, bad anatomy, bad hands, missing fingers, extra fingers, '
    'worst quality, low quality, blurry, text, watermark, logo, signature, '
    'child, loli, underage, childlike body, nsfw, nude, explicit, erotic, '
    'suggestive, fetish pose, low angle, from below, dutch angle, extreme perspective, '
    'bunny girl, bunny ears, rabbit ears, leotard, swimsuit, bodysuit, lingerie, '
    'cleavage, breasts focus, sitting, reclining, bed, bedroom, '
    'head out of frame, face cropped, torso cropped, center crop, '
    'leg focus, foot focus, close-up thighs, thigh focus, crotch focus, upskirt, '
    'panty shot, exposed underwear, spread legs, high kick, leg up, clothes lift, '
    'see-through clothes, multiple girls, 2girls, 3girls, group, crowd, '
    'multiple views, character sheet, reference sheet, collage, grid, panel, '
    'comic, manga panel, speech bubble, chibi, mascot, creature, monster, '
    'cropped, out of frame, extra arms, extra legs, duplicate, clone, bad feet';

final _compositionGuard = _VibeRef.file(
  r'E:\NAI的脚本群\QAQ的画风\1\防止从下.naiv4vibe',
  info: 0.18,
  strength: 0.08,
);

Future<void> main() async {
  final token = await _resolveTokenWithRetry();
  if (!_hasToken(token)) {
    stderr.writeln('No NovelAI token found.');
    exitCode = 2;
    return;
  }

  final client = _createClient(_proxy);
  try {
    final skinDir =
        Directory('$_outputRoot${Platform.pathSeparator}skin-vibes');
    await skinDir.create(recursive: true);

    final sourceSpecs = [
      _SourceSpec(
        id: 'fullbody-v2',
        seed: _seed + 141,
        width: 832,
        height: 1216,
        prompt:
            '$_quality, $_artistChain, adult original woman, mature proportions, '
            'head-to-toe full body, entire body visible, head visible, feet visible, '
            'small margin around body, standing pose, straight-on eye-level camera, centered composition, '
            'full outfit visible, tasteful modest short dress, skirt hem down, black semi-sheer pantyhose, '
            'simple shoes, face neck hands and legs visible, neutral warm white studio background, '
            'material and skin tone study, safe non-explicit, $_skinMaterial',
        vibes: [],
      ),
      _SourceSpec(
        id: 'balanced-v2',
        seed: _seed + 142,
        width: 832,
        height: 1216,
        prompt:
            '$_quality, $_artistChain, adult original woman, mature proportions, '
            'full body fashion illustration, entire body visible from head to shoes, '
            'straight-on eye-level camera, calm standing pose, hands relaxed, '
            'tasteful blouse and skirt, skirt hem down, black semi-sheer pantyhose visible from thighs to calves, '
            'full outfit readable, neutral sunlit studio background, material and skin tone study, '
            'safe non-explicit, $_skinMaterial',
        vibes: [],
      ),
      _SourceSpec(
        id: 'lowerbody-neutral-v2',
        seed: _seed + 143,
        width: 832,
        height: 1216,
        prompt:
            '$_quality, $_artistChain, adult original woman, mature proportions, '
            'full body in frame, lower body clearly readable but not close-up, head visible, feet visible, '
            'eye-level camera, standing normally, both feet on ground, modest framing, skirt hem down, '
            'black semi-sheer pantyhose, natural knees and calves, clean fabric highlights, '
            'neutral pale studio background, material and skin tone study, safe non-explicit, '
            '$_skinMaterial',
        vibes: [
          _VibeRef.file(
            r'E:\NAI的脚本群\QAQ的画风\1\2d0e77-8b0dd8.naiv4vibe',
            info: 0.02,
            strength: 0.04,
          ),
          _VibeRef.file(
            r'E:\NAI的脚本群\QAQ的画风\1\防止从下.naiv4vibe',
            info: 0.10,
            strength: 0.08,
          ),
        ],
      ),
    ];

    final generatedSources = <_GeneratedSource>[];
    for (final spec in sourceSpecs) {
      final pngPath = '${skinDir.path}${Platform.pathSeparator}'
          'qaq1-skinvibe-source-${spec.id}-seed${spec.seed}.png';
      if (!await File(pngPath).exists()) {
        stdout.writeln('Generating source ${spec.id} -> $pngPath');
        final bytes = await _requestNaiImage(
          client: client,
          token: token!.trim(),
          payload: _payload(
            input: spec.prompt,
            negative: _sourceNegative,
            width: spec.width,
            height: spec.height,
            seed: spec.seed,
            scale: 5.0,
            cfgRescale: 0.25,
            useCoords: false,
            useOrder: true,
            vibes: spec.vibes,
          ),
        );
        await _writeBytes(pngPath, bytes);
      } else {
        stdout.writeln('Keeping existing source ${spec.id} -> $pngPath');
      }

      final vibePath = '${skinDir.path}${Platform.pathSeparator}'
          'qaq1-skinvibe-${spec.id}.naiv4vibe';
      if (!await File(vibePath).exists()) {
        stdout.writeln('Encoding source ${spec.id} -> $vibePath');
        final encoding = await _encodeVibe(
          client: client,
          token: token!.trim(),
          imageBytes: await File(pngPath).readAsBytes(),
        );
        await _writeNaiV4Vibe(
          path: vibePath,
          name: 'QAQ1 skin vibe ${spec.id}',
          encoding: encoding,
          sourceImagePath: pngPath,
          defaultInfo: 0.1,
          defaultStrength: 0.16,
        );
      } else {
        stdout.writeln('Keeping existing vibe ${spec.id} -> $vibePath');
      }

      generatedSources.add(_GeneratedSource(
        id: spec.id,
        pngPath: pngPath,
        vibePath: vibePath,
      ));
    }

    final materialVibes = await _ensureMaterialSwatchVibes(
      client: client,
      token: token!.trim(),
      skinDir: skinDir,
    );
    final compositionAnchorVibe = await _ensureCompositionAnchorVibe(
      client: client,
      token: token.trim(),
      skinDir: skinDir,
    );

    final baseComment = _readNaiComment(File(_noVibeBase));
    final baseInput = baseComment['prompt'] as String;
    final baseNegative = (baseComment['uc'] ??
            (baseComment['v4_negative_prompt'] as Map?)?['caption']
                ?['base_caption'])
        .toString();
    final baseV4Prompt = _stringKeyMap(baseComment['v4_prompt'] as Map);
    final baseV4Negative =
        _stringKeyMap(baseComment['v4_negative_prompt'] as Map);

    List<_VibeRef> skinRefs(double info, double strength) => [
          for (final source in generatedSources)
            _VibeRef.file(source.vibePath, info: info, strength: strength),
        ];

    final finalSpecs = [
      _FinalSpec(
        id: 'v2-t2i-i006-s014',
        outputName:
            'hanabi-p1-qaq1-skinvibe-multiscale-v2-t2i-i006-s014-seed$_seed.png',
        vibes: skinRefs(0.06, 0.14),
      ),
      _FinalSpec(
        id: 'v2-t2i-i008-s016-guard',
        outputName:
            'hanabi-p1-qaq1-skinvibe-multiscale-v2-t2i-i008-s016-guard-seed$_seed.png',
        vibes: [...skinRefs(0.08, 0.16), _compositionGuard],
      ),
      _FinalSpec(
        id: 'v3-swatch-t2i-i004-s020',
        outputName:
            'hanabi-p1-qaq1-skinvibe-swatch-v3-t2i-i004-s020-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.04, strength: 0.20),
        ],
      ),
      _FinalSpec(
        id: 'v3-swatch-t2i-i004-s020-guard',
        outputName:
            'hanabi-p1-qaq1-skinvibe-swatch-v3-t2i-i004-s020-guard-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.04, strength: 0.20),
          _compositionGuard,
        ],
      ),
      _FinalSpec(
        id: 'v3-swatch-plus-balanced-t2i',
        outputName:
            'hanabi-p1-qaq1-skinvibe-swatch-v3-balanced-t2i-i004-s018-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.04, strength: 0.18),
          _VibeRef.file(
            generatedSources
                .firstWhere((source) => source.id == 'balanced-v2')
                .vibePath,
            info: 0.03,
            strength: 0.08,
          ),
        ],
      ),
      _FinalSpec(
        id: 'v4-swatch-t2i-i002-s026',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v4-t2i-swatch-i002-s026-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.26),
        ],
      ),
      _FinalSpec(
        id: 'v4-split-swatch-t2i',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v4-t2i-split-swatch-i004-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.skinOnly, info: 0.04, strength: 0.14),
          _VibeRef.file(
            materialVibes.stockingsOnly,
            info: 0.04,
            strength: 0.10,
          ),
        ],
      ),
      _FinalSpec(
        id: 'v4-swatch-composition-anchor',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v4-t2i-swatch-anchor-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.03, strength: 0.18),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.02,
            strength: 0.07,
          ),
        ],
      ),
      _FinalSpec(
        id: 'v4-swatch-anchor-guard',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v4-t2i-swatch-anchor-guard-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.03, strength: 0.18),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.02,
            strength: 0.06,
          ),
          _compositionGuard,
        ],
      ),
      _FinalSpec(
        id: 'v5-anchor-guard-mat022',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v5-t2i-anchor-guard-mat022-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.22),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.02,
            strength: 0.06,
          ),
          _compositionGuard,
        ],
      ),
      _FinalSpec(
        id: 'v5-anchor-guard-mat026',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v5-t2i-anchor-guard-mat026-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.26),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.02,
            strength: 0.07,
          ),
          _compositionGuard,
        ],
      ),
      _FinalSpec(
        id: 'v5-anchor-guard-split',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v5-t2i-anchor-guard-split-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.skinOnly, info: 0.03, strength: 0.16),
          _VibeRef.file(
            materialVibes.stockingsOnly,
            info: 0.03,
            strength: 0.08,
          ),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.02,
            strength: 0.06,
          ),
          _compositionGuard,
        ],
      ),
      _FinalSpec(
        id: 'v5-anchor-only-mat022',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v5-t2i-anchor-only-mat022-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.22),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.03,
            strength: 0.08,
          ),
        ],
      ),
      _FinalSpec(
        id: 'v6-anchor012-mat020',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v6-t2i-anchor012-mat020-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.20),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.03,
            strength: 0.12,
          ),
        ],
      ),
      _FinalSpec(
        id: 'v6-anchor014-mat020-guard',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v6-t2i-anchor014-mat020-guard-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.20),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.03,
            strength: 0.14,
          ),
          _compositionGuard,
        ],
      ),
      _FinalSpec(
        id: 'v6-anchor010-mat024',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v6-t2i-anchor010-mat024-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.24),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.03,
            strength: 0.10,
          ),
        ],
      ),
      _FinalSpec(
        id: 'v6-anchor016-mat018',
        outputName:
            'hanabi-p1-qaq1-skinvibe-v6-t2i-anchor016-mat018-seed$_seed.png',
        vibes: [
          _VibeRef.file(materialVibes.combined, info: 0.02, strength: 0.18),
          _VibeRef.file(
            compositionAnchorVibe,
            info: 0.03,
            strength: 0.16,
          ),
        ],
      ),
    ];

    for (final spec in finalSpecs) {
      final outputPath =
          '$_outputRoot${Platform.pathSeparator}${spec.outputName}';
      if (await File(outputPath).exists()) {
        stdout.writeln('Keeping existing final ${spec.id} -> $outputPath');
        continue;
      }
      stdout.writeln('Generating final ${spec.id} -> $outputPath');
      final payload = _payload(
        input: baseInput,
        negative: baseNegative,
        width: (baseComment['width'] as num?)?.toInt() ?? 832,
        height: (baseComment['height'] as num?)?.toInt() ?? 1216,
        seed: _seed,
        scale: (baseComment['scale'] as num?)?.toDouble() ?? 4.0,
        cfgRescale: (baseComment['cfg_rescale'] as num?)?.toDouble() ?? 0.4,
        sampler: baseComment['sampler'] as String? ?? 'k_euler_ancestral',
        steps: (baseComment['steps'] as num?)?.toInt() ?? 28,
        useCoords: baseV4Prompt['use_coords'] == true,
        useOrder: baseV4Prompt['use_order'] != false,
        vibes: spec.vibes,
        v4Prompt: baseV4Prompt,
        v4NegativePrompt: baseV4Negative,
      );
      try {
        final bytes = await _requestNaiImage(
          client: client,
          token: token.trim(),
          payload: payload,
        );
        await _writeBytes(outputPath, bytes);
      } catch (error) {
        stderr.writeln('Final ${spec.id} failed, continuing: $error');
      }
    }

    await _runWhiteStockingLowAngleScene(
      client: client,
      token: token.trim(),
      skinDir: skinDir,
      materialVibes: materialVibes,
    );
    await _runWhiteStockingFullBodyLowAngleScene(
      client: client,
      token: token.trim(),
      skinDir: skinDir,
      materialVibes: materialVibes,
    );

    stdout.writeln('Done. Skin Vibe files:');
    for (final source in generatedSources) {
      stdout.writeln('  ${source.id}: ${source.vibePath}');
    }
  } finally {
    client.close();
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
  required bool useCoords,
  required bool useOrder,
  required List<_VibeRef> vibes,
  String sampler = 'k_euler_ancestral',
  int steps = 28,
  Map<String, dynamic>? v4Prompt,
  Map<String, dynamic>? v4NegativePrompt,
}) {
  final resolved = vibes.map(_resolveVibe).toList(growable: false);
  final parameters = <String, dynamic>{
    'params_version': 3,
    'width': width,
    'height': height,
    'scale': scale,
    'sampler': sampler,
    'steps': steps,
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
    'use_coords': useCoords,
    'seed': seed,
    'characterPrompts': <dynamic>[],
    'v4_prompt': v4Prompt ??
        {
          'caption': {
            'base_caption': input,
            'char_captions': <dynamic>[],
          },
          'use_coords': useCoords,
          'use_order': useOrder,
        },
    'v4_negative_prompt': v4NegativePrompt ??
        {
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

Future<_MaterialVibes> _ensureMaterialSwatchVibes({
  required http.Client client,
  required String token,
  required Directory skinDir,
}) async {
  final combinedSheet = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-material-swatch-skin-stockings-v3.png';
  final skinSheet = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-material-swatch-skin-only-v3.png';
  final stockingSheet = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-material-swatch-stockings-only-v3.png';

  await _writeMaterialSheetIfMissing(
    outputPath: combinedSheet,
    patches: _combinedPatches(skinDir.path),
  );
  await _writeMaterialSheetIfMissing(
    outputPath: skinSheet,
    patches: _skinOnlyPatches(),
  );
  await _writeMaterialSheetIfMissing(
    outputPath: stockingSheet,
    patches: _stockingOnlyPatches(skinDir.path),
  );

  Future<String> encode(String imagePath, String suffix) async {
    final vibePath = '${skinDir.path}${Platform.pathSeparator}'
        'qaq1-material-swatch-$suffix-v3.naiv4vibe';
    if (!await File(vibePath).exists()) {
      stdout.writeln('Encoding material swatch $suffix -> $vibePath');
      final encoding = await _encodeVibe(
        client: client,
        token: token,
        imageBytes: await File(imagePath).readAsBytes(),
      );
      await _writeNaiV4Vibe(
        path: vibePath,
        name: 'QAQ1 material swatch $suffix v3',
        encoding: encoding,
        sourceImagePath: imagePath,
        defaultInfo: 0.04,
        defaultStrength: 0.20,
      );
    } else {
      stdout.writeln('Keeping material swatch $suffix -> $vibePath');
    }
    return vibePath;
  }

  return _MaterialVibes(
    combined: await encode(combinedSheet, 'skin-stockings'),
    skinOnly: await encode(skinSheet, 'skin-only'),
    stockingsOnly: await encode(stockingSheet, 'stockings-only'),
  );
}

Future<String> _ensureCompositionAnchorVibe({
  required http.Client client,
  required String token,
  required Directory skinDir,
}) async {
  final vibePath = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-composition-anchor-no-vibe-baseline.naiv4vibe';
  if (await File(vibePath).exists()) {
    stdout.writeln('Keeping composition anchor vibe -> $vibePath');
    return vibePath;
  }
  stdout.writeln('Encoding composition anchor vibe -> $vibePath');
  final encoding = await _encodeVibe(
    client: client,
    token: token,
    imageBytes: await File(_noVibeBase).readAsBytes(),
  );
  await _writeNaiV4Vibe(
    path: vibePath,
    name: 'QAQ1 composition anchor no-vibe baseline',
    encoding: encoding,
    sourceImagePath: _noVibeBase,
    defaultInfo: 0.02,
    defaultStrength: 0.07,
  );
  return vibePath;
}

Future<void> _runWhiteStockingLowAngleScene({
  required http.Client client,
  required String token,
  required Directory skinDir,
  required _MaterialVibes materialVibes,
}) async {
  final sceneDir = Directory('$_outputRoot${Platform.pathSeparator}'
      'white-stockings-low-angle');
  await sceneDir.create(recursive: true);

  final whiteStockingVibe = await _ensureWhiteStockingSwatchVibe(
    client: client,
    token: token,
    skinDir: skinDir,
  );
  final warmWhiteStockingVibe = await _ensureWhiteStockingWarmSwatchVibe(
    client: client,
    token: token,
    skinDir: skinDir,
  );

  const seed = _seed + 4400;
  const prompt =
      '$_quality, $_artistChain, adult original woman, mature proportions, '
      '1girl, solo, low-angle upward view, from below, camera near ground, '
      'full body in frame, standing pose, looking down at viewer, confident smile, '
      'street stairway, soft daylight, cherry blossoms, modest short coat and skirt, '
      'skirt hem down, white semi-sheer pantyhose, white sheer tights, '
      'subtle warm skin tone visible through white nylon, glossy soft stocking highlights, '
      'knees and calves visible, shoes visible, balanced full-body composition, '
      'soft luminous skin, warm skin tone, safe non-explicit fashion illustration';
  const negative =
      'lowres, bad anatomy, bad hands, missing fingers, extra fingers, worst quality, '
      'low quality, blurry, text, watermark, logo, signature, child, loli, underage, '
      'childlike body, nsfw, nude, explicit, erotic, fetish pose, crotch focus, '
      'upskirt, under skirt, panty shot, exposed underwear, see-through underwear, '
      'skirt lift, clothes lift, spread legs, high kick, leg up, foot focus, '
      'bare legs, black pantyhose, black stockings, dark stockings, thighhighs, '
      'extreme perspective, fisheye, close-up thighs, multiple girls, 2girls, '
      'group, cropped head, head out of frame, out of frame, duplicate, extra legs';

  final noVibePath = '${sceneDir.path}${Platform.pathSeparator}'
      'white-lowangle-no-vibe-seed$seed.png';
  if (!await File(noVibePath).exists()) {
    stdout.writeln('Generating white stocking baseline -> $noVibePath');
    final bytes = await _requestNaiImage(
      client: client,
      token: token,
      payload: _payload(
        input: prompt,
        negative: negative,
        width: 832,
        height: 1216,
        seed: seed,
        scale: 4.5,
        cfgRescale: 0.35,
        useCoords: false,
        useOrder: true,
        vibes: const [],
      ),
    );
    await _writeBytes(noVibePath, bytes);
  } else {
    stdout.writeln('Keeping white stocking baseline -> $noVibePath');
  }

  final anchorPath = '${sceneDir.path}${Platform.pathSeparator}'
      'white-lowangle-composition-anchor.naiv4vibe';
  if (!await File(anchorPath).exists()) {
    stdout
        .writeln('Encoding white low-angle composition anchor -> $anchorPath');
    final encoding = await _encodeVibe(
      client: client,
      token: token,
      imageBytes: await File(noVibePath).readAsBytes(),
    );
    await _writeNaiV4Vibe(
      path: anchorPath,
      name: 'white low-angle composition anchor',
      encoding: encoding,
      sourceImagePath: noVibePath,
      defaultInfo: 0.03,
      defaultStrength: 0.08,
    );
  } else {
    stdout.writeln('Keeping white low-angle composition anchor -> $anchorPath');
  }

  final specs = [
    _FinalSpec(
      id: 'white-swatch-only',
      outputName: 'white-lowangle-vibe-white-swatch-i004-s022-seed$seed.png',
      vibes: [
        _VibeRef.file(whiteStockingVibe, info: 0.04, strength: 0.22),
      ],
    ),
    _FinalSpec(
      id: 'white-swatch-anchor',
      outputName:
          'white-lowangle-vibe-white-swatch-anchor-i003-s022-seed$seed.png',
      vibes: [
        _VibeRef.file(whiteStockingVibe, info: 0.03, strength: 0.22),
        _VibeRef.file(anchorPath, info: 0.03, strength: 0.08),
      ],
    ),
    _FinalSpec(
      id: 'white-swatch-skin-anchor',
      outputName: 'white-lowangle-vibe-white-swatch-skin-anchor-seed$seed.png',
      vibes: [
        _VibeRef.file(whiteStockingVibe, info: 0.03, strength: 0.18),
        _VibeRef.file(materialVibes.skinOnly, info: 0.03, strength: 0.10),
        _VibeRef.file(anchorPath, info: 0.03, strength: 0.08),
      ],
    ),
    _FinalSpec(
      id: 'white-swatch-anchor-stronger',
      outputName:
          'white-lowangle-vibe-white-swatch-anchor-i002-s026-a010-seed$seed.png',
      vibes: [
        _VibeRef.file(whiteStockingVibe, info: 0.02, strength: 0.26),
        _VibeRef.file(anchorPath, info: 0.03, strength: 0.10),
      ],
    ),
    _FinalSpec(
      id: 'white-swatch-v2-anchor-balanced',
      outputName:
          'white-lowangle-vibe-white-swatch-v2-anchor-i002-s020-a016-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.02, strength: 0.20),
        _VibeRef.file(anchorPath, info: 0.04, strength: 0.16),
      ],
    ),
    _FinalSpec(
      id: 'white-swatch-v2-anchor-preserve',
      outputName:
          'white-lowangle-vibe-white-swatch-v2-anchor-i002-s018-a020-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.02, strength: 0.18),
        _VibeRef.file(anchorPath, info: 0.04, strength: 0.20),
      ],
    ),
    _FinalSpec(
      id: 'white-swatch-v2-skin-anchor',
      outputName:
          'white-lowangle-vibe-white-swatch-v2-skin-anchor-i002-s018-a016-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.02, strength: 0.18),
        _VibeRef.file(materialVibes.skinOnly, info: 0.02, strength: 0.05),
        _VibeRef.file(anchorPath, info: 0.04, strength: 0.16),
      ],
    ),
    _FinalSpec(
      id: 'white-swatch-v2-low-strength',
      outputName:
          'white-lowangle-vibe-white-swatch-v2-anchor-i003-s016-a018-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.03, strength: 0.16),
        _VibeRef.file(anchorPath, info: 0.04, strength: 0.18),
      ],
    ),
  ];

  for (final spec in specs) {
    final outputPath = '${sceneDir.path}${Platform.pathSeparator}'
        '${spec.outputName}';
    if (await File(outputPath).exists()) {
      stdout.writeln('Keeping white final ${spec.id} -> $outputPath');
      continue;
    }
    stdout.writeln('Generating white final ${spec.id} -> $outputPath');
    final bytes = await _requestNaiImage(
      client: client,
      token: token,
      payload: _payload(
        input: prompt,
        negative: negative,
        width: 832,
        height: 1216,
        seed: seed,
        scale: 4.5,
        cfgRescale: 0.35,
        useCoords: false,
        useOrder: true,
        vibes: spec.vibes,
      ),
    );
    await _writeBytes(outputPath, bytes);
  }
}

Future<void> _runWhiteStockingFullBodyLowAngleScene({
  required http.Client client,
  required String token,
  required Directory skinDir,
  required _MaterialVibes materialVibes,
}) async {
  final sceneDir = Directory('$_outputRoot${Platform.pathSeparator}'
      'white-stockings-low-angle-fullbody');
  await sceneDir.create(recursive: true);

  final warmWhiteStockingVibe = await _ensureWhiteStockingWarmSwatchVibe(
    client: client,
    token: token,
    skinDir: skinDir,
  );

  const seed = _seed + 4510;
  const prompt =
      '$_quality, $_artistChain, adult original woman, mature proportions, '
      '1girl, solo, mild low-angle upward view, camera near ground, '
      'standing on an outdoor stairway, looking down at viewer, gentle smile, '
      'entire full body visible from head to shoes, shoes fully visible near bottom of frame, '
      'head near upper third, centered full-body composition, white spring coat, '
      'modest short skirt under coat, skirt hem down, white semi-sheer pantyhose, '
      'white sheer tights, subtle warm skin tone visible through white nylon, '
      'fine nylon weave, glossy soft stocking highlights on knees and calves, '
      'soft luminous skin, warm skin tone, soft daylight, pale cherry blossoms, '
      'safe non-explicit fashion illustration';
  const negative =
      'lowres, bad anatomy, bad hands, missing fingers, extra fingers, worst quality, '
      'low quality, blurry, text, watermark, logo, signature, child, loli, underage, '
      'childlike body, nsfw, nude, explicit, erotic, fetish pose, crotch focus, '
      'upskirt, under skirt, panty shot, exposed underwear, see-through underwear, '
      'skirt lift, clothes lift, spread legs, high kick, leg up, foot focus, '
      'bare legs, black pantyhose, black stockings, dark stockings, thighhighs, '
      'garter belt, extreme perspective, fisheye, close-up thighs, close-up legs, '
      'cropped feet, feet out of frame, ankle crop, cropped head, head out of frame, '
      'out of frame, multiple girls, 2girls, group, duplicate, extra legs';

  final noVibePath = '${sceneDir.path}${Platform.pathSeparator}'
      'white-fullbody-lowangle-no-vibe-seed$seed.png';
  if (!await File(noVibePath).exists()) {
    stdout.writeln('Generating white full-body baseline -> $noVibePath');
    final bytes = await _requestNaiImage(
      client: client,
      token: token,
      payload: _payload(
        input: prompt,
        negative: negative,
        width: 768,
        height: 1344,
        seed: seed,
        scale: 4.5,
        cfgRescale: 0.35,
        useCoords: false,
        useOrder: true,
        vibes: const [],
      ),
    );
    await _writeBytes(noVibePath, bytes);
  } else {
    stdout.writeln('Keeping white full-body baseline -> $noVibePath');
  }

  final anchorPath = '${sceneDir.path}${Platform.pathSeparator}'
      'white-fullbody-lowangle-composition-anchor.naiv4vibe';
  if (!await File(anchorPath).exists()) {
    stdout.writeln(
      'Encoding white full-body low-angle composition anchor -> $anchorPath',
    );
    final encoding = await _encodeVibe(
      client: client,
      token: token,
      imageBytes: await File(noVibePath).readAsBytes(),
    );
    await _writeNaiV4Vibe(
      path: anchorPath,
      name: 'white full-body low-angle composition anchor',
      encoding: encoding,
      sourceImagePath: noVibePath,
      defaultInfo: 0.04,
      defaultStrength: 0.16,
    );
  } else {
    stdout.writeln(
      'Keeping white full-body low-angle composition anchor -> $anchorPath',
    );
  }

  final specs = [
    _FinalSpec(
      id: 'white-fullbody-v2-balanced',
      outputName:
          'white-fullbody-lowangle-vibe-v2-anchor-i002-s020-a016-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.02, strength: 0.20),
        _VibeRef.file(anchorPath, info: 0.04, strength: 0.16),
      ],
    ),
    _FinalSpec(
      id: 'white-fullbody-v2-preserve',
      outputName:
          'white-fullbody-lowangle-vibe-v2-anchor-i002-s018-a022-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.02, strength: 0.18),
        _VibeRef.file(anchorPath, info: 0.05, strength: 0.22),
      ],
    ),
    _FinalSpec(
      id: 'white-fullbody-v2-material',
      outputName:
          'white-fullbody-lowangle-vibe-v2-anchor-i003-s022-a014-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.03, strength: 0.22),
        _VibeRef.file(anchorPath, info: 0.03, strength: 0.14),
      ],
    ),
    _FinalSpec(
      id: 'white-fullbody-v2-skin',
      outputName:
          'white-fullbody-lowangle-vibe-v2-skin-anchor-i002-s018-a018-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.02, strength: 0.18),
        _VibeRef.file(materialVibes.skinOnly, info: 0.02, strength: 0.05),
        _VibeRef.file(anchorPath, info: 0.04, strength: 0.18),
      ],
    ),
    _FinalSpec(
      id: 'white-fullbody-v2-preserve-max',
      outputName:
          'white-fullbody-lowangle-vibe-v2-anchor-i002-s014-a028-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.02, strength: 0.14),
        _VibeRef.file(anchorPath, info: 0.06, strength: 0.28),
      ],
    ),
    _FinalSpec(
      id: 'white-fullbody-v2-preserve-skin',
      outputName:
          'white-fullbody-lowangle-vibe-v2-skin-anchor-i003-s016-a026-seed$seed.png',
      vibes: [
        _VibeRef.file(warmWhiteStockingVibe, info: 0.03, strength: 0.16),
        _VibeRef.file(materialVibes.skinOnly, info: 0.02, strength: 0.04),
        _VibeRef.file(anchorPath, info: 0.06, strength: 0.26),
      ],
    ),
  ];

  for (final spec in specs) {
    final outputPath = '${sceneDir.path}${Platform.pathSeparator}'
        '${spec.outputName}';
    if (await File(outputPath).exists()) {
      stdout.writeln('Keeping white full-body final ${spec.id} -> $outputPath');
      continue;
    }
    stdout
        .writeln('Generating white full-body final ${spec.id} -> $outputPath');
    final bytes = await _requestNaiImage(
      client: client,
      token: token,
      payload: _payload(
        input: prompt,
        negative: negative,
        width: 768,
        height: 1344,
        seed: seed,
        scale: 4.5,
        cfgRescale: 0.35,
        useCoords: false,
        useOrder: true,
        vibes: spec.vibes,
      ),
    );
    await _writeBytes(outputPath, bytes);
  }
}

Future<String> _ensureWhiteStockingSwatchVibe({
  required http.Client client,
  required String token,
  required Directory skinDir,
}) async {
  final sheetPath = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-material-swatch-white-stockings-v1.png';
  final vibePath = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-material-swatch-white-stockings-v1.naiv4vibe';
  await _writeWhiteStockingSheetIfMissing(sheetPath);
  if (!await File(vibePath).exists()) {
    stdout.writeln('Encoding white stocking material swatch -> $vibePath');
    final encoding = await _encodeVibe(
      client: client,
      token: token,
      imageBytes: await File(sheetPath).readAsBytes(),
    );
    await _writeNaiV4Vibe(
      path: vibePath,
      name: 'QAQ1 white stocking material swatch v1',
      encoding: encoding,
      sourceImagePath: sheetPath,
      defaultInfo: 0.03,
      defaultStrength: 0.22,
    );
  } else {
    stdout.writeln('Keeping white stocking material swatch -> $vibePath');
  }
  return vibePath;
}

Future<String> _ensureWhiteStockingWarmSwatchVibe({
  required http.Client client,
  required String token,
  required Directory skinDir,
}) async {
  final sheetPath = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-material-swatch-white-stockings-v2.png';
  final vibePath = '${skinDir.path}${Platform.pathSeparator}'
      'qaq1-material-swatch-white-stockings-v2.naiv4vibe';
  await _writeWhiteStockingWarmSheetIfMissing(sheetPath);
  if (!await File(vibePath).exists()) {
    stdout.writeln('Encoding warm white stocking material swatch -> $vibePath');
    final encoding = await _encodeVibe(
      client: client,
      token: token,
      imageBytes: await File(sheetPath).readAsBytes(),
    );
    await _writeNaiV4Vibe(
      path: vibePath,
      name: 'QAQ1 warm white stocking material swatch v2',
      encoding: encoding,
      sourceImagePath: sheetPath,
      defaultInfo: 0.02,
      defaultStrength: 0.20,
    );
  } else {
    stdout.writeln('Keeping warm white stocking material swatch -> $vibePath');
  }
  return vibePath;
}

Future<void> _writeWhiteStockingSheetIfMissing(String outputPath) async {
  final output = File(outputPath);
  if (await output.exists()) {
    stdout.writeln('Keeping white stocking material sheet -> $outputPath');
    return;
  }
  final sheet = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(sheet, color: img.ColorRgb8(244, 240, 236));
  final random = Random(440037);
  const tile = 256;
  for (var tileIndex = 0; tileIndex < 16; tileIndex++) {
    final tileImage = img.Image(width: tile, height: tile, numChannels: 3);
    final warm = 224 + random.nextInt(18);
    final cool = 236 + random.nextInt(16);
    for (var y = 0; y < tile; y++) {
      for (var x = 0; x < tile; x++) {
        final dx = (x - tile / 2) / tile;
        final dy = (y - tile / 2) / tile;
        final curve = max(0.0, 1.0 - (dx * dx * 1.8 + dy * dy * 0.6));
        final weave = ((x + tileIndex * 7) % 9 == 0 ? 7 : 0) +
            ((y + tileIndex * 5) % 13 == 0 ? 4 : 0);
        final sheen = (curve * 28).round() + weave;
        final r = (warm + sheen).clamp(0, 255);
        final g = (cool + sheen).clamp(0, 255);
        final b = (245 + sheen).clamp(0, 255);
        tileImage.setPixelRgb(x, y, r, g, b);
      }
    }
    for (var i = 0; i < 4; i++) {
      final x0 = random.nextInt(tile);
      for (var y = 0; y < tile; y++) {
        final x = (x0 + (sin(y / 28 + i) * 10).round()).clamp(0, tile - 1);
        tileImage.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    img.compositeImage(
      sheet,
      tileImage,
      dstX: (tileIndex % 4) * tile,
      dstY: (tileIndex ~/ 4) * tile,
    );
  }
  await output.parent.create(recursive: true);
  await output.writeAsBytes(img.encodePng(sheet));
  stdout.writeln('Wrote white stocking material sheet -> $outputPath');
}

Future<void> _writeWhiteStockingWarmSheetIfMissing(String outputPath) async {
  final output = File(outputPath);
  if (await output.exists()) {
    stdout.writeln('Keeping warm white stocking material sheet -> $outputPath');
    return;
  }
  final sheet = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(sheet, color: img.ColorRgb8(232, 226, 220));
  final random = Random(440038);
  const tile = 256;
  for (var tileIndex = 0; tileIndex < 16; tileIndex++) {
    final tileImage = img.Image(width: tile, height: tile, numChannels: 3);
    final skinR = 228 + random.nextInt(16);
    final skinG = 193 + random.nextInt(15);
    final skinB = 183 + random.nextInt(14);
    final nylonR = 224 + random.nextInt(18);
    final nylonG = 226 + random.nextInt(18);
    final nylonB = 232 + random.nextInt(16);
    final alpha = 0.58 + random.nextDouble() * 0.16;
    for (var y = 0; y < tile; y++) {
      for (var x = 0; x < tile; x++) {
        final dx = (x - tile / 2) / tile;
        final dy = (y - tile / 2) / tile;
        final roundLight = max(0.0, 1.0 - (dx * dx * 2.0 + dy * dy * 0.7));
        final verticalWeave = ((x + tileIndex * 3) % 7 == 0 ? 10 : 0);
        final horizontalWeave = ((y + tileIndex * 5) % 19 == 0 ? 5 : 0);
        final fineWeave = ((x + y + tileIndex * 11) % 11 == 0 ? -6 : 0);
        final sheen = (roundLight * 30).round() +
            verticalWeave +
            horizontalWeave +
            fineWeave;
        final r = (skinR * (1 - alpha) + nylonR * alpha + sheen).round();
        final g = (skinG * (1 - alpha) + nylonG * alpha + sheen).round();
        final b = (skinB * (1 - alpha) + nylonB * alpha + sheen).round();
        tileImage.setPixelRgb(
          x,
          y,
          r.clamp(0, 255),
          g.clamp(0, 255),
          b.clamp(0, 255),
        );
      }
    }
    for (var i = 0; i < 3; i++) {
      final x0 = random.nextInt(tile);
      for (var y = 0; y < tile; y++) {
        final x = (x0 + (sin(y / 25 + i * 1.7) * 9).round()).clamp(0, tile - 1);
        tileImage.setPixelRgb(x, y, 250, 250, 252);
      }
    }
    img.compositeImage(
      sheet,
      tileImage,
      dstX: (tileIndex % 4) * tile,
      dstY: (tileIndex ~/ 4) * tile,
    );
  }
  await output.parent.create(recursive: true);
  await output.writeAsBytes(img.encodePng(sheet));
  stdout.writeln('Wrote warm white stocking material sheet -> $outputPath');
}

List<_Patch> _combinedPatches(String skinDir) {
  final lowerV2 = '$skinDir${Platform.pathSeparator}'
      'qaq1-skinvibe-source-lowerbody-neutral-v2-seed544884180.png';
  final balancedV2 = '$skinDir${Platform.pathSeparator}'
      'qaq1-skinvibe-source-balanced-v2-seed544884179.png';
  return [
    ..._skinOnlyPatches(),
    _Patch(lowerV2, 150, 170, 540, 260),
    _Patch(lowerV2, 160, 400, 520, 280),
    _Patch(lowerV2, 150, 620, 520, 360),
    _Patch(lowerV2, 235, 250, 180, 520),
    _Patch(lowerV2, 420, 240, 190, 540),
    _Patch(balancedV2, 275, 650, 300, 440),
    _Patch(balancedV2, 300, 760, 270, 330),
  ];
}

List<_Patch> _skinOnlyPatches() {
  return const [
    _Patch(_skinTarget, 80, 420, 240, 520),
    _Patch(_skinTarget, 450, 300, 290, 560),
    _Patch(_skinTarget, 155, 520, 230, 250),
    _Patch(_skinTarget, 500, 450, 260, 260),
    _Patch(_skinTarget, 70, 760, 240, 280),
    _Patch(_skinTarget, 510, 760, 260, 280),
    _Patch(_skinTarget, 620, 980, 170, 150),
    _Patch(_skinTarget, 105, 390, 180, 180),
  ];
}

List<_Patch> _stockingOnlyPatches(String skinDir) {
  final lowerV2 = '$skinDir${Platform.pathSeparator}'
      'qaq1-skinvibe-source-lowerbody-neutral-v2-seed544884180.png';
  final balancedV2 = '$skinDir${Platform.pathSeparator}'
      'qaq1-skinvibe-source-balanced-v2-seed544884179.png';
  return [
    _Patch(lowerV2, 150, 170, 540, 260),
    _Patch(lowerV2, 160, 400, 520, 280),
    _Patch(lowerV2, 150, 620, 520, 360),
    _Patch(lowerV2, 235, 250, 180, 520),
    _Patch(lowerV2, 420, 240, 190, 540),
    _Patch(balancedV2, 275, 650, 300, 440),
    _Patch(balancedV2, 300, 760, 270, 330),
  ];
}

Future<void> _writeMaterialSheetIfMissing({
  required String outputPath,
  required List<_Patch> patches,
}) async {
  final output = File(outputPath);
  if (await output.exists()) {
    stdout.writeln('Keeping material sheet -> $outputPath');
    return;
  }

  final sheet = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(sheet, color: img.ColorRgb8(242, 236, 232));
  const tile = 256;
  for (var index = 0; index < min(patches.length, 16); index++) {
    final patch = patches[index];
    final source = img.decodePng(await File(patch.path).readAsBytes());
    if (source == null) {
      throw FormatException('Could not decode patch source: ${patch.path}');
    }
    final x = patch.x.clamp(0, source.width - 1);
    final y = patch.y.clamp(0, source.height - 1);
    final width = patch.width.clamp(1, source.width - x);
    final height = patch.height.clamp(1, source.height - y);
    final cropped = img.copyCrop(
      source,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    final resized = img.copyResizeCropSquare(
      cropped,
      size: tile,
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(
      sheet,
      resized,
      dstX: (index % 4) * tile,
      dstY: (index ~/ 4) * tile,
    );
  }
  await output.parent.create(recursive: true);
  await output.writeAsBytes(img.encodePng(sheet));
  stdout.writeln('Wrote material sheet -> $outputPath');
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

Map<String, dynamic> _readNaiComment(File file) {
  final metadata = _extractPngTextChunks(file.readAsBytesSync());
  final comment = metadata['Comment'];
  if (comment == null) {
    throw FormatException('PNG has no Comment metadata: ${file.path}');
  }
  final decoded = jsonDecode(comment);
  if (decoded is! Map) {
    throw FormatException('PNG Comment is not a JSON object: ${file.path}');
  }
  return _stringKeyMap(decoded);
}

Map<String, String> _extractPngTextChunks(Uint8List bytes) {
  const pngHeader = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < pngHeader.length; i++) {
    if (bytes.length <= i || bytes[i] != pngHeader[i]) {
      throw const FormatException('Not a PNG file.');
    }
  }
  final metadata = <String, String>{};
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = _readUint32(bytes, offset);
    final type = utf8.decode(bytes.sublist(offset + 4, offset + 8));
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    if (dataEnd > bytes.length) break;
    final data = bytes.sublist(dataStart, dataEnd);
    switch (type) {
      case 'tEXt':
        final entry = _parseTextChunk(data);
        if (entry != null) metadata[entry.key] = entry.value;
      case 'iTXt':
        final entry = _parseInternationalTextChunk(data);
        if (entry != null) metadata[entry.key] = entry.value;
    }
    offset = dataEnd + 4;
    if (type == 'IEND') break;
  }
  return metadata;
}

MapEntry<String, String>? _parseTextChunk(Uint8List data) {
  final separator = data.indexOf(0);
  if (separator <= 0) return null;
  return MapEntry(
    utf8.decode(data.sublist(0, separator), allowMalformed: true),
    utf8.decode(data.sublist(separator + 1), allowMalformed: true),
  );
}

MapEntry<String, String>? _parseInternationalTextChunk(Uint8List data) {
  final keywordEnd = data.indexOf(0);
  if (keywordEnd <= 0) return null;
  var cursor = keywordEnd + 1;
  if (cursor + 2 > data.length) return null;
  final compressionFlag = data[cursor++];
  cursor += 1;
  final langEnd = data.indexOf(0, cursor);
  if (langEnd < 0) return null;
  cursor = langEnd + 1;
  final translatedEnd = data.indexOf(0, cursor);
  if (translatedEnd < 0) return null;
  cursor = translatedEnd + 1;
  final textBytes = data.sublist(cursor);
  if (compressionFlag != 0) return null;
  return MapEntry(
    utf8.decode(data.sublist(0, keywordEnd), allowMalformed: true),
    utf8.decode(textBytes, allowMalformed: true),
  );
}

int _readUint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
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

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) {
    final normalizedValue = value is Map ? _stringKeyMap(value) : value;
    return MapEntry(key.toString(), normalizedValue);
  });
}

String _randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
          bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

class _SourceSpec {
  final String id;
  final int seed;
  final int width;
  final int height;
  final String prompt;
  final List<_VibeRef> vibes;

  const _SourceSpec({
    required this.id,
    required this.seed,
    required this.width,
    required this.height,
    required this.prompt,
    this.vibes = const [],
  });
}

class _FinalSpec {
  final String id;
  final String outputName;
  final List<_VibeRef> vibes;

  const _FinalSpec({
    required this.id,
    required this.outputName,
    required this.vibes,
  });
}

class _GeneratedSource {
  final String id;
  final String pngPath;
  final String vibePath;

  const _GeneratedSource({
    required this.id,
    required this.pngPath,
    required this.vibePath,
  });
}

class _MaterialVibes {
  final String combined;
  final String skinOnly;
  final String stockingsOnly;

  const _MaterialVibes({
    required this.combined,
    required this.skinOnly,
    required this.stockingsOnly,
  });
}

class _Patch {
  final String path;
  final int x;
  final int y;
  final int width;
  final int height;

  const _Patch(this.path, this.x, this.y, this.width, this.height);
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
