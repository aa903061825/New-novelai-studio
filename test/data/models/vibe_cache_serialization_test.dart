import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/models/vibe_config.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      comment: 'root',
      strs: const ['masterpiece'],
      prompts: const [],
    ),
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
  test('VibeConfig supports json roundtrip', () {
    final config = VibeConfig.fromBytes(
      Uint8List.fromList(const [0, 1, 2, 3]),
      'vibe.png',
      0.7,
      0.3,
    );

    final restored = VibeConfig.fromJson(config.toJson());

    expect(restored.fileName, config.fileName);
    expect(restored.imageB64, config.imageB64);
    expect(restored.infoExtracted, config.infoExtracted);
    expect(restored.referenceStrength, config.referenceStrength);
  });

  test('VibeConfigV4 stores an explicit image path instead of image bytes', () {
    final fullSizePng = Uint8List.fromList(const [137, 80, 78, 71, 1, 2, 3]);
    final config = VibeConfigV4(
      fileName: 'v4.vibe',
      vibeB64: 'abc123',
      infoExtracted: 0.42,
      referenceStrength: 0.65,
      imageBytes: fullSizePng,
      sourceImagePath: r'C:\app\vibe-assets\current\v4.png',
    );

    final json = config.toJson();
    final restored = VibeConfigV4.fromJson(json);

    expect(json.keys, isNot(contains('image_b64')));
    expect(json['info_extracted'], 0.42);
    expect(json['source_image_path'], r'C:\app\vibe-assets\current\v4.png');
    expect(restored.fileName, config.fileName);
    expect(restored.vibeB64, config.vibeB64);
    expect(restored.infoExtracted, config.infoExtracted);
    expect(restored.referenceStrength, config.referenceStrength);
    expect(restored.sourceImagePath, config.sourceImagePath);
    expect(restored.imageBytes, isNull);
  });

  test('VibeConfigV4 reads NAI import info for strength and extraction', () {
    final config = VibeConfigV4.fromNaiV4VibeJson(
      'style.naiv4vibe',
      {
        'name': 'Soft Vibe',
        'importInfo': {
          'strength': 0.33,
          'information_extracted': 0.7,
        },
        'encodings': {
          'v4-5full': {
            'unknown': {'encoding': 'encoded-vibe'},
          },
        },
      },
      0.2,
    );

    expect(config.fileName, 'Soft Vibe');
    expect(config.vibeB64, 'encoded-vibe');
    expect(config.infoExtracted, 0.7);
    expect(config.referenceStrength, 0.33);
  });

  test('VibeConfigV4 keeps legacy image json lazy during config load', () {
    final restored = VibeConfigV4.fromJson({
      'file_name': 'legacy-v4.png',
      'vibe_b64': 'abc123',
      'reference_strength': 0.65,
      'image_b64': 'BwgJ',
    });

    expect(restored.fileName, 'legacy-v4.png');
    expect(restored.vibeB64, 'abc123');
    expect(restored.referenceStrength, 0.65);
    expect(restored.imageBytes, isNull);
    expect(restored.legacyImageB64, 'BwgJ');
    expect(restored.toJson()['image_b64'], 'BwgJ');
  });

  test('PayloadConfig persists vibe lists in json', () {
    final payloadConfig = _buildPayloadConfig();
    payloadConfig.vibeConfigList = [
      VibeConfig.fromBytes(
        Uint8List.fromList(const [1, 2, 3]),
        'legacy-vibe.png',
        1.0,
        0.25,
      ),
    ];
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'v4.vibe',
        vibeB64: 'vibe-encoding',
        infoExtracted: 0.25,
        referenceStrength: 0.4,
      ),
    ];

    final restored = PayloadConfig.fromJson(payloadConfig.toJson());

    expect(restored.vibeConfigList.length, 1);
    expect(restored.vibeConfigList.first.fileName, 'legacy-vibe.png');
    expect(restored.vibeConfigListV4.length, 1);
    expect(restored.vibeConfigListV4.first.vibeB64, 'vibe-encoding');
    expect(restored.vibeConfigListV4.first.infoExtracted, 0.25);
  });

  test('PayloadConfig persists all script-level V4 vibes', () {
    final payloadConfig = _buildPayloadConfig();
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'script-main.png',
        vibeB64: 'first-vibe',
        referenceStrength: 0.4,
      ),
      VibeConfigV4(
        fileName: 'extra.png',
        vibeB64: 'second-vibe',
        referenceStrength: 0.8,
      ),
    ];

    final json = payloadConfig.toJson();
    final jsonVibes = json['vibe_config_list_v4'] as List<dynamic>;
    final restored = PayloadConfig.fromJson(json);

    expect(jsonVibes.length, 2);
    expect(restored.vibeConfigListV4.length, 2);
    expect(
      restored.vibeConfigListV4.map((vibe) => vibe.vibeB64),
      ['first-vibe', 'second-vibe'],
    );
  });
}
