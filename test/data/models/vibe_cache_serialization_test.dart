import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/models/vibe_config.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';

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

  test('VibeConfigV4 supports json roundtrip', () {
    final config = VibeConfigV4(
      fileName: 'v4.vibe',
      vibeB64: 'abc123',
      referenceStrength: 0.65,
      imageBytes: Uint8List.fromList(const [7, 8, 9]),
    );

    final restored = VibeConfigV4.fromJson(config.toJson());

    expect(restored.fileName, config.fileName);
    expect(restored.vibeB64, config.vibeB64);
    expect(restored.referenceStrength, config.referenceStrength);
    expect(restored.imageBytes, isNotNull);
    expect(restored.imageBytes, config.imageBytes);
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
        referenceStrength: 0.4,
      ),
    ];

    final restored = PayloadConfig.fromJson(payloadConfig.toJson());

    expect(restored.vibeConfigList.length, 1);
    expect(restored.vibeConfigList.first.fileName, 'legacy-vibe.png');
    expect(restored.vibeConfigListV4.length, 1);
    expect(restored.vibeConfigListV4.first.vibeB64, 'vibe-encoding');
  });
}
