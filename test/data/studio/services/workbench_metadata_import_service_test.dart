import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/workbench_metadata_import_service.dart';

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('imports NovelAI JSON metadata into workbench prompt and parameters',
      () async {
    final payload = _payload();
    final service = WorkbenchMetadataImportService();
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'Software': 'NovelAI',
          'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
          'Description': '1girl, 1boy, rainy room',
          'Comment': {
            'steps': 28,
            'height': 1216,
            'width': 832,
            'scale': 4.0,
            'cfg_rescale': 0.4,
            'seed': 2787767294,
            'sampler': 'k_euler_ancestral',
            'noise_schedule': 'karras',
            'v4_prompt': {
              'caption': {
                'base_caption': '1girl, 1boy, rainy room',
                'char_captions': [
                  {
                    'char_caption': 'girl, twin braids',
                    'centers': [
                      {'x': 0.5, 'y': 0.5},
                    ],
                  },
                  {
                    'char_caption': 'boy, black suit',
                    'centers': [
                      {'x': 0.9, 'y': 0.5},
                    ],
                  },
                ],
              },
            },
            'v4_negative_prompt': {
              'caption': {
                'base_caption': 'blurry, lowres',
                'char_captions': [
                  {'char_caption': 'bad hands'},
                  {'char_caption': ''},
                ],
              },
            },
          },
        }),
      ),
    );

    final summary = await service.importBytes(payload, 'p001.json', bytes);

    expect(summary.fieldsLoaded, greaterThanOrEqualTo(9));
    expect(summary.charactersLoaded, 2);
    expect(payload.overridePrompt, '1girl, 1boy, rainy room');
    expect(payload.useOverridePrompt, isTrue);
    expect(payload.useCharacterPromptWithOverride, isTrue);
    expect(payload.paramConfig.model, 'nai-diffusion-4-5-full');
    expect(payload.paramConfig.sizes.single.width, 832);
    expect(payload.paramConfig.sizes.single.height, 1216);
    expect(payload.paramConfig.randomSeed, isFalse);
    expect(payload.paramConfig.seed, 2787767294);
    expect(payload.paramConfig.negativePrompt, 'blurry, lowres');
    expect(payload.characterConfigList.first.positivePromptConfig.strs,
        ['girl, twin braids']);
    expect(payload.characterConfigList.first.negativePrompt, 'bad hands');
    expect(payload.characterConfigList.first.positions.single.x, 3);
    expect(payload.characterConfigList.first.positions.single.y, 3);
  });

  test('preserves official prompt randomizer syntax on metadata import',
      () async {
    final payload = _payload();
    final service = WorkbenchMetadataImportService();
    const randomizedPrompt = '1girl, ||red hair|blue hair|green hair||, rain';
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'Software': 'NovelAI',
          'Description': randomizedPrompt,
          'Comment': {
            'steps': 28,
            'seed': 123,
            'width': 832,
            'height': 1216,
          },
        }),
      ),
    );

    await service.importBytes(payload, 'randomizer.json', bytes);

    expect(payload.overridePrompt, randomizedPrompt);
    expect(payload.useOverridePrompt, isTrue);
  });

  test('imports ComfyUI PNG text prompt graph into workbench prompt', () async {
    final payload = _payload();
    final service = WorkbenchMetadataImportService();
    final bytes = _pngWithTextChunks({
      'prompt': jsonEncode({
        '63': {
          'class_type': 'KSampler',
          'inputs': {
            'seed': 317540284430262,
            'steps': 40,
            'cfg': 5.5,
            'sampler_name': 'er_sde',
            'scheduler': 'beta',
            'positive': ['11', 0],
            'negative': ['12', 0],
          },
        },
        '11': {
          'class_type': 'CLIPTextEncode',
          'inputs': {
            'text': ['89', 0],
          },
        },
        '12': {
          'class_type': 'CLIPTextEncode',
          'inputs': {
            'text': 'bad hands, lowres, watermark',
          },
        },
        '89': {
          'class_type': 'JoinStringMulti',
          'inputs': {
            'delimiter': ' ',
            'string_1': ['100', 0],
            'string_2': ['101', 0],
          },
        },
        '100': {
          'class_type': 'CR Text',
          'inputs': {
            'text': 'masterpiece, @artist',
          },
        },
        '101': {
          'class_type': 'CR Text',
          'inputs': {
            'text': '2girls, lantern light',
          },
        },
      }),
      'workflow': jsonEncode({'id': 'sample-workflow'}),
    });

    final summary = await service.importBytes(payload, 'comfy.png', bytes);

    expect(summary.usedStructuredMetadata, isTrue);
    expect(payload.useOverridePrompt, isTrue);
    expect(payload.overridePrompt, contains('masterpiece, @artist'));
    expect(payload.overridePrompt, contains('2girls, lantern light'));
    expect(payload.overridePrompt, isNot(contains('"class_type"')));
    expect(payload.paramConfig.negativePrompt, 'bad hands, lowres, watermark');
    expect(payload.paramConfig.randomSeed, isFalse);
    expect(payload.paramConfig.seed, 317540284430262);
    expect(payload.paramConfig.steps, 40);
    expect(payload.paramConfig.scale, 5.5);
    expect(payload.paramConfig.sampler, 'er_sde');
    expect(payload.paramConfig.noiseSchedule, 'beta');
  });

  test('imports NovelAI stealth_pngcomp metadata without text chunks',
      () async {
    final payload = _payload();
    final service = WorkbenchMetadataImportService();
    final bytes = _pngWithStealthMetadata(
      'stealth_pngcomp',
      jsonEncode({
        'Description': 'stealth comp prompt, blue room',
        'Comment': {
          'seed': 12345,
          'steps': 28,
          'width': 832,
          'height': 1216,
          'uc': 'lowres, blurry',
        },
      }),
    );

    final summary =
        await service.importBytes(payload, 'stealth-comp.png', bytes);

    expect(summary.usedStructuredMetadata, isTrue);
    expect(payload.overridePrompt, 'stealth comp prompt, blue room');
    expect(payload.paramConfig.seed, 12345);
    expect(payload.paramConfig.steps, 28);
    expect(payload.paramConfig.negativePrompt, 'lowres, blurry');
  });

  test('imports NovelAI stealth_pnginfo metadata without gzip', () async {
    final payload = _payload();
    final service = WorkbenchMetadataImportService();
    final bytes = _pngWithStealthMetadata(
      'stealth_pnginfo',
      jsonEncode({
        'Description': 'stealth info prompt, sunset',
        'Comment': {
          'seed': 67890,
          'scale': 5.5,
        },
      }),
    );

    await service.importBytes(payload, 'stealth-info.png', bytes);

    expect(payload.overridePrompt, 'stealth info prompt, sunset');
    expect(payload.paramConfig.seed, 67890);
    expect(payload.paramConfig.scale, 5.5);
  });

  test('parses prompt-bearing png file text chunks before broken image data',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'workbench-png-file-fast-path-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/fast-path.png');
    await file.writeAsBytes(_pngWithTextThenBrokenChunk({
      'Description': 'fast path prompt, no full image decode',
      'Comment': jsonEncode({
        'seed': 24680,
        'steps': 28,
      }),
    }));

    final parsed = await WorkbenchMetadataImportService().parseFile(file);

    expect(parsed.prompt, 'fast path prompt, no full image decode');
    expect(parsed.parameters['seed'], 24680);
    expect(parsed.parameters['steps'], 28);
  });

  test('parseFile falls back to stealth png metadata without text chunks',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'workbench-png-file-stealth-fallback-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/stealth.png');
    await file.writeAsBytes(_pngWithStealthMetadata(
      'stealth_pngcomp',
      jsonEncode({
        'Description': 'file fallback stealth prompt',
        'Comment': {
          'seed': 13579,
        },
      }),
    ));

    final parsed = await WorkbenchMetadataImportService().parseFile(file);

    expect(parsed.prompt, 'file fallback stealth prompt');
    expect(parsed.parameters['seed'], 13579);
  });
}

Uint8List _pngWithTextChunks(Map<String, String> textChunks) {
  final bytes = BytesBuilder();
  bytes.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.add(_pngChunk(
      'IHDR',
      Uint8List.fromList([
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        2,
        0,
        0,
        0,
      ])));
  for (final entry in textChunks.entries) {
    bytes.add(_pngChunk(
      'tEXt',
      Uint8List.fromList([
        ...utf8.encode(entry.key),
        0,
        ...utf8.encode(entry.value),
      ]),
    ));
  }
  bytes.add(_pngChunk('IEND', Uint8List(0)));
  return bytes.toBytes();
}

Uint8List _pngWithStealthMetadata(String magic, String metadata) {
  const width = 96;
  const height = 96;
  final payload = magic == 'stealth_pngcomp'
      ? GZipCodec().encode(utf8.encode(metadata))
      : utf8.encode(metadata);
  final bitLength = payload.length * 8;
  final bitLengthBytes = ByteData(4)..setInt32(0, bitLength);
  final embedded = <int>[
    ...utf8.encode(magic),
    ...bitLengthBytes.buffer.asUint8List(),
    ...payload,
  ];
  if (embedded.length * 8 > width * height) {
    throw StateError('Stealth test PNG is too small for metadata.');
  }

  final alpha = Uint8List(width * height);
  alpha.fillRange(0, alpha.length, 254);
  for (var bitIndex = 0; bitIndex < embedded.length * 8; bitIndex += 1) {
    final byte = embedded[bitIndex ~/ 8];
    final bit = (byte >> (7 - (bitIndex % 8))) & 1;
    final x = bitIndex ~/ height;
    final y = bitIndex % height;
    alpha[y * width + x] = 254 | bit;
  }

  final rawRows = BytesBuilder(copy: false);
  for (var y = 0; y < height; y += 1) {
    rawRows.addByte(0);
    for (var x = 0; x < width; x += 1) {
      rawRows.add([0, 0, 0, alpha[y * width + x]]);
    }
  }

  final bytes = BytesBuilder();
  bytes.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.add(_pngChunk(
    'IHDR',
    Uint8List.fromList([
      ..._uint32(width),
      ..._uint32(height),
      8,
      6,
      0,
      0,
      0,
    ]),
  ));
  bytes.add(_pngChunk(
    'IDAT',
    Uint8List.fromList(ZLibCodec().encode(rawRows.toBytes())),
  ));
  bytes.add(_pngChunk('IEND', Uint8List(0)));
  return bytes.toBytes();
}

Uint8List _pngWithTextThenBrokenChunk(Map<String, String> textChunks) {
  final bytes = BytesBuilder();
  bytes.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.add(_pngChunk(
      'IHDR',
      Uint8List.fromList([
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        2,
        0,
        0,
        0,
      ])));
  for (final entry in textChunks.entries) {
    bytes.add(_pngChunk(
      'tEXt',
      Uint8List.fromList([
        ...utf8.encode(entry.key),
        0,
        ...utf8.encode(entry.value),
      ]),
    ));
  }
  bytes.add(const [0x7F, 0xFF, 0xFF, 0xFF]);
  bytes.add(ascii.encode('IDAT'));
  return bytes.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  final crcInput = Uint8List.fromList([...typeBytes, ...data]);
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32(crcInput)),
  ]);
}

Uint8List _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
