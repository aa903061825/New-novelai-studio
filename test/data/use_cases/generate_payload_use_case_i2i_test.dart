import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/i2i_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/precise_reference_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';
import 'package:nai_casrand/data/use_cases/generate_payload_use_case.dart';

PayloadConfig _buildPayloadConfig({I2IConfig? i2iConfig}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      comment: 'root',
      strs: const ['normal prompt'],
      prompts: const [],
    ),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  )..i2iConfig = i2iConfig ?? I2IConfig();
}

Map<String, dynamic> _parameters(PayloadGenerationResult result) {
  return result.payload['parameters'] as Map<String, dynamic>;
}

Map<String, dynamic> _v4Prompt(Map<String, dynamic> parameters) {
  return parameters['v4_prompt'] as Map<String, dynamic>;
}

void main() {
  test('source image switches action from generate to img2img', () {
    final textToImageConfig = _buildPayloadConfig();
    final imageToImageConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(imageB64: 'source-image'),
    );

    final textToImage = GeneratePayloadUseCase(
      payloadConfig: textToImageConfig,
    )();
    final imageToImage = GeneratePayloadUseCase(
      payloadConfig: imageToImageConfig,
    )();

    expect(textToImage.payload['action'], 'generate');
    expect(imageToImage.payload['action'], 'img2img');
  });

  test('source image emits image, strength, noise, and extra noise seed', () {
    final payloadConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(
        imageB64: 'source-image',
        strength: 0.72,
        noise: 0.18,
      ),
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = _parameters(result);

    expect(params['image'], 'source-image');
    expect(params['strength'], 0.72);
    expect(params['noise'], 0.18);
    expect(params['extra_noise_seed'], isA<int>());
  });

  test('strength and noise are clamped in the request payload', () {
    final lowConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(imageB64: 'low-source', strength: -0.5, noise: -0.1),
    );
    final highConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(imageB64: 'high-source', strength: 1.5, noise: 2.0),
    );

    final lowParams = _parameters(
      GeneratePayloadUseCase(payloadConfig: lowConfig)(),
    );
    final highParams = _parameters(
      GeneratePayloadUseCase(payloadConfig: highConfig)(),
    );

    expect(lowParams['strength'], 0.0);
    expect(lowParams['noise'], 0.0);
    expect(highParams['strength'], 1.0);
    expect(highParams['noise'], 1.0);
  });

  test('disabled override prompt does not replace the normal prompt', () {
    final payloadConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(
        imageB64: 'source-image',
        overridePromptEnabled: false,
        overridePrompt: 'override prompt',
      ),
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = _parameters(result);
    final v4Prompt = _v4Prompt(params);
    final caption = v4Prompt['caption'] as Map<String, dynamic>;

    expect(result.payload['input'], 'normal prompt');
    expect(caption['base_caption'], 'normal prompt');
  });

  test('enabled override prompt replaces input and V4 base caption', () {
    final payloadConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(
        imageB64: 'source-image',
        overridePromptEnabled: true,
        overridePrompt: ' override prompt ',
      ),
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = _parameters(result);
    final v4Prompt = _v4Prompt(params);
    final caption = v4Prompt['caption'] as Map<String, dynamic>;

    expect(result.payload['input'], 'override prompt');
    expect(caption['base_caption'], 'override prompt');
  });

  test('vibe transfer fields can still be emitted with image-to-image', () {
    final payloadConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(imageB64: 'source-image'),
    );
    payloadConfig.paramConfig.model = 'nai-diffusion-4-full';
    payloadConfig.generationRuntimeState = GenerationRuntimeState(
      vibeEnabled: true,
    );
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'modern.vibe',
        vibeB64: 'vibe-image',
        referenceStrength: 0.3,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = _parameters(result);

    expect(result.payload['action'], 'img2img');
    expect(params['image'], 'source-image');
    expect(params['reference_image_multiple'], ['vibe-image']);
    expect(params['reference_strength_multiple'], [0.3]);
    expect(params['reference_information_extracted_multiple'], [1.0]);
  });

  test('precise reference fields can still be emitted with image-to-image', () {
    final payloadConfig = _buildPayloadConfig(
      i2iConfig: I2IConfig(imageB64: 'source-image'),
    );
    payloadConfig.paramConfig.model = 'nai-diffusion-4-5-full';
    payloadConfig.usePreciseReference = true;
    payloadConfig.generationRuntimeState = GenerationRuntimeState(
      vibeEnabled: true,
    );
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'ignored.vibe',
        vibeB64: 'vibe-image',
        referenceStrength: 0.3,
      ),
    ];
    payloadConfig.preciseReferenceList = [
      PreciseReferenceConfig(
        imageB64: 'precise-image',
        fileName: 'precise.png',
        type: 'character',
        strength: 0.8,
        fidelity: 0.6,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = _parameters(result);

    expect(result.payload['action'], 'img2img');
    expect(params['image'], 'source-image');
    expect(params['director_reference_images'], ['precise-image']);
    expect(params.containsKey('reference_image_multiple'), isFalse);
    expect(params.containsKey('reference_strength_multiple'), isFalse);
    expect(
      params.containsKey('reference_information_extracted_multiple'),
      isFalse,
    );
  });

  test('text-to-image request omits image-to-image-only parameters', () {
    final payloadConfig = _buildPayloadConfig();

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = _parameters(result);

    expect(result.payload['action'], 'generate');
    expect(params.containsKey('image'), isFalse);
    expect(params.containsKey('strength'), isFalse);
    expect(params.containsKey('noise'), isFalse);
    expect(params.containsKey('extra_noise_seed'), isFalse);
  });
}
