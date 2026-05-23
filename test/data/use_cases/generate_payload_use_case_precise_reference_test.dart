import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/precise_reference_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';
import 'package:nai_casrand/data/use_cases/generate_payload_use_case.dart';

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      comment: 'root',
      strs: const ['1girl'],
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

Uint8List _buildValidPngBytes() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('precise reference removes vibe transfer payload keys', () {
    final payloadConfig = _buildPayloadConfig();
    payloadConfig.paramConfig.model = 'nai-diffusion-4-5-full';
    payloadConfig.usePreciseReference = true;
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'should-be-ignored',
        vibeB64: 'dummy-vibe',
        referenceStrength: 0.5,
      ),
    ];
    payloadConfig.preciseReferenceList = [
      PreciseReferenceConfig.fromBytes(
        _buildValidPngBytes(),
        'ref.png',
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params.containsKey('director_reference_images'), isTrue);
    expect(params.containsKey('reference_image_multiple'), isFalse);
    expect(params.containsKey('reference_strength_multiple'), isFalse);
    expect(
      params.containsKey('reference_information_extracted_multiple'),
      isFalse,
    );
  });
}
