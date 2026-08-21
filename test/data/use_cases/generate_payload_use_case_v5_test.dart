import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/models/generation_runtime_state.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/use_cases/generate_payload_use_case.dart';

PayloadConfig _payload(ParamConfig paramConfig) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      comment: 'root',
      strs: const ['1girl, city night'],
      prompts: const [],
    ),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: paramConfig,
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('V5 parameter payload uses v4 schema and transparency hints', () {
    final config = ParamConfig(
      model: naiDiffusion5Curated,
      sampler: 'ddim_v3',
      noiseSchedule: 'exponential',
      qualityPreset: 'light',
      ucPresetMode: 'humanFocus',
      transparentBackground: true,
      sm: true,
      smDyn: true,
      varietyPlus: true,
      dynamicThresholding: true,
      legacyUc: true,
    );

    final parameters = config.getPayload();

    expect(parameters['params_version'], 4);
    expect(parameters['sampler'], 'k_euler_ancestral');
    expect(parameters['noise_schedule'], 'karras');
    expect(parameters['tag_hint_qt'], 3);
    expect(parameters['tag_hint_uc_preset'], 4);
    expect(parameters['tag_hint_transparent_background'], isTrue);
    expect(parameters['straight_alpha'], isTrue);
    expect(parameters.containsKey('sm'), isFalse);
    expect(parameters.containsKey('sm_dyn'), isFalse);
    expect(parameters.containsKey('skip_cfg_above_sigma'), isFalse);
    expect(parameters['dynamic_thresholding'], isFalse);
    expect(parameters['legacy_uc'], isFalse);
  });

  test('V5 preset selections survive config serialization', () {
    final original = ParamConfig(
      model: naiDiffusion5Curated,
      qualityPreset: 'light',
      ucPresetMode: 'furryFocus',
      transparentBackground: true,
    );

    final restored = ParamConfig.fromJson(original.toJson());

    expect(restored.model, naiDiffusion5Curated);
    expect(restored.qualityPreset, 'light');
    expect(restored.ucPresetMode, 'furryFocus');
    expect(restored.transparentBackground, isTrue);
  });

  test('V5 presets alter base prompts and reject legacy reference fields', () {
    final payload = _payload(ParamConfig(
      model: naiDiffusion5Full,
      qualityPreset: 'standard',
      ucPresetMode: 'light',
      transparentBackground: true,
      negativePrompt: 'custom defect',
    ));
    payload.generationRuntimeState = GenerationRuntimeState(vibeEnabled: true);
    payload.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'old.vibe',
        vibeB64: 'must-not-be-sent',
        referenceStrength: 0.5,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payload)();
    final parameters = result.payload['parameters'] as Map<String, dynamic>;
    final positive = result.payload['input'] as String;
    final negative = parameters['negative_prompt'] as String;
    final v4Prompt = parameters['v4_prompt'] as Map<String, dynamic>;
    final v4Negative = parameters['v4_negative_prompt'] as Map<String, dynamic>;

    expect(positive, contains('transparent background'));
    expect(positive, contains('very aesthetic'));
    expect(positive, contains('masterpiece'));
    expect(positive, contains('no text'));
    expect(
      (v4Prompt['caption'] as Map<String, dynamic>)['base_caption'],
      positive,
    );
    expect(negative, startsWith('lowres, bad hands, bad anatomy'));
    expect(negative, endsWith('custom defect'));
    expect(
      (v4Negative['caption'] as Map<String, dynamic>)['base_caption'],
      negative,
    );
    expect(parameters.containsKey('reference_image_multiple'), isFalse);
    expect(parameters.containsKey('director_reference_images'), isFalse);
  });

  test('V5 preset merge does not duplicate existing exact tags', () {
    final payload = _payload(ParamConfig(
      model: naiDiffusion5Curated,
      qualityPreset: 'standard',
      transparentBackground: true,
    ));
    payload.rootPromptConfig = PromptConfig(
      comment: 'root',
      strs: const ['1girl, masterpiece, transparent background'],
      prompts: const [],
    );

    final positive = GeneratePayloadUseCase(payloadConfig: payload)()
        .payload['input'] as String;

    expect(RegExp('masterpiece').allMatches(positive), hasLength(1));
    expect(
      RegExp('transparent background').allMatches(positive),
      hasLength(1),
    );
  });

  test('V5 sends the exact custom character center in structured prompts', () {
    final payload = _payload(ParamConfig(
      model: naiDiffusion5Full,
      autoPosition: false,
    ));
    payload.characterConfigList = [
      CharacterConfig(
        name: 'heroine',
        positions: const [Point(3, 3)],
        freeformPosition: const Point(0.237, 0.814),
        positivePromptConfig: PromptConfig(
          strs: const ['silver hair, blue eyes'],
          prompts: const [],
        ),
        negativePrompt: 'bad hands',
        enabled: true,
      ),
    ];

    final parameters = GeneratePayloadUseCase(payloadConfig: payload)()
        .payload['parameters'] as Map<String, dynamic>;
    final character =
        (parameters['characterPrompts'] as List).single as Map<String, dynamic>;
    final center = character['center'] as Map<String, dynamic>;
    final v4Prompt = parameters['v4_prompt'] as Map<String, dynamic>;
    final caption = v4Prompt['caption'] as Map<String, dynamic>;
    final structuredCharacter =
        (caption['char_captions'] as List).single as Map<String, dynamic>;
    final structuredCenter =
        (structuredCharacter['centers'] as List).single as Map<String, dynamic>;

    expect(center, {'x': 0.237, 'y': 0.814});
    expect(structuredCenter, {'x': 0.237, 'y': 0.814});
    expect(v4Prompt['use_coords'], isTrue);
  });

  test('V4.5 never sends a V5 freeform center', () {
    final payload = _payload(ParamConfig(
      model: 'nai-diffusion-4-5-full',
      autoPosition: false,
    ));
    payload.characterConfigList = [
      CharacterConfig(
        name: 'heroine',
        positions: const [Point(2, 5)],
        freeformPosition: const Point(0.237, 0.814),
        positivePromptConfig: PromptConfig(
          strs: const ['silver hair'],
          prompts: const [],
        ),
        negativePrompt: '',
        enabled: true,
      ),
    ];

    final parameters = GeneratePayloadUseCase(payloadConfig: payload)()
        .payload['parameters'] as Map<String, dynamic>;
    final character =
        (parameters['characterPrompts'] as List).single as Map<String, dynamic>;

    expect(character['center'], {'x': 0.3, 'y': 0.9});
    expect(character['center'], isNot({'x': 0.237, 'y': 0.814}));
  });
}
