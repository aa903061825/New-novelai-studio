import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/models/vibe_config.dart';
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

void main() {
  test('disabled vibe omits NAI3 reference payload fields', () {
    final payloadConfig = _buildPayloadConfig();
    payloadConfig.paramConfig.model = 'nai-diffusion-3';
    payloadConfig.generationRuntimeState = GenerationRuntimeState(
      vibeEnabled: false,
    );
    payloadConfig.vibeConfigList = [
      VibeConfig(
        imageB64: 'nai3-image',
        fileName: 'legacy.png',
        infoExtracted: 1.0,
        referenceStrength: 0.3,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params.containsKey('reference_image_multiple'), isFalse);
    expect(params.containsKey('reference_strength_multiple'), isFalse);
    expect(
      params.containsKey('reference_information_extracted_multiple'),
      isFalse,
    );
  });

  test('enabled vibe keeps NAI4 reference payload fields', () {
    final payloadConfig = _buildPayloadConfig();
    payloadConfig.paramConfig.model = 'nai-diffusion-4-full';
    payloadConfig.generationRuntimeState = GenerationRuntimeState(
      vibeEnabled: true,
    );
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'modern.vibe',
        vibeB64: 'nai4-vibe',
        referenceStrength: 0.2,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params['reference_image_multiple'], ['nai4-vibe']);
    expect(params['reference_strength_multiple'], [0.2]);
    expect(params['reference_information_extracted_multiple'], [1.0]);
  });

  test('enabled NAI4 vibe emits all configured V4 vibes', () {
    final payloadConfig = _buildPayloadConfig();
    payloadConfig.paramConfig.model = 'nai-diffusion-4-full';
    payloadConfig.generationRuntimeState = GenerationRuntimeState(
      vibeEnabled: true,
    );
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'script-main.vibe',
        vibeB64: 'script-vibe',
        referenceStrength: 0.2,
      ),
      VibeConfigV4(
        fileName: 'legacy-extra.vibe',
        vibeB64: 'extra-vibe',
        referenceStrength: 0.9,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params['reference_image_multiple'], ['script-vibe', 'extra-vibe']);
    expect(params['reference_strength_multiple'], [0.2, 0.9]);
    expect(params['reference_information_extracted_multiple'], [1.0, 1.0]);
  });

  test('disabled vibe omits NAI4 reference payload fields', () {
    final payloadConfig = _buildPayloadConfig();
    payloadConfig.paramConfig.model = 'nai-diffusion-4-5-full';
    payloadConfig.generationRuntimeState = GenerationRuntimeState(
      vibeEnabled: false,
    );
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'modern.vibe',
        vibeB64: 'nai4-vibe',
        referenceStrength: 0.2,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params.containsKey('reference_image_multiple'), isFalse);
    expect(params.containsKey('reference_strength_multiple'), isFalse);
    expect(
      params.containsKey('reference_information_extracted_multiple'),
      isFalse,
    );
  });
}
