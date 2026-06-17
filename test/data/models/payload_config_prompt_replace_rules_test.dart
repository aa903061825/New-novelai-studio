import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/generation_runtime_state.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/prompt_replace_rule.dart';
import 'package:novel_studio/data/models/settings.dart';

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
  test('PayloadConfig persists prompt replace rules in order', () {
    final payload = _buildPayloadConfig();
    payload.promptReplaceRules = [
      PromptReplaceRule(
        id: '1',
        source: 'cat',
        target: 'dog',
        enabled: true,
      ),
      PromptReplaceRule(
        id: '2',
        source: 'blue',
        target: '',
        enabled: false,
      ),
    ];

    final restored = PayloadConfig.fromJson(payload.toJson());

    expect(restored.promptReplaceRules.length, 2);
    expect(restored.promptReplaceRules[0].source, 'cat');
    expect(restored.promptReplaceRules[0].target, 'dog');
    expect(restored.promptReplaceRules[0].enabled, isTrue);
    expect(restored.promptReplaceRules[1].source, 'blue');
    expect(restored.promptReplaceRules[1].target, '');
    expect(restored.promptReplaceRules[1].enabled, isFalse);
  });

  test('PayloadConfig can load json while preserving current api key', () {
    final payload = _buildPayloadConfig();
    payload.settings.apiKey = 'current-key';

    payload.loadJson(
      {
        'prompt_config': {
          'selectionMethod': 'single',
          'shuffled': false,
          'prob': 0.0,
          'num': 1,
          'randomBracketsUpper': 0,
          'randomBracketsLower': 0,
          'type': 'str',
          'comment': 'imported',
          'filter': '',
          'strs': ['imported prompt'],
          'prompts': [],
          'enabled': true,
        },
        'character_config': const [],
        'saved_config': const [],
        'param_config': ParamConfig().toJson(),
        'settings': {
          'api_key': 'imported-key',
          'proxy': '1.2.3.4:99',
        },
      },
      preserveCurrentApiKey: true,
    );

    expect(payload.settings.apiKey, 'current-key');
    expect(payload.settings.proxy, '1.2.3.4:99');
    expect(payload.rootPromptConfig.comment, 'imported');
  });

  test('PayloadConfig does not serialize runtime global generation params', () {
    final payload = _buildPayloadConfig();
    final expectedSteps = payload.paramConfig.steps;
    payload.globalGenerationParams.steps = 15;
    payload.globalGenerationParams.useGlobalSteps = true;
    payload.globalGenerationParams.negativePrompt = 'global uc';
    payload.globalGenerationParams.useGlobalNegativePrompt = true;

    final json = payload.toJson();

    expect(json.containsKey('global_generation_params'), isFalse);
    expect(
        (json['param_config'] as Map<String, dynamic>)['steps'], expectedSteps);
    expect(
      (json['param_config'] as Map<String, dynamic>)['negative_prompt'],
      isNot('global uc'),
    );
  });

  test('PayloadConfig does not serialize generation runtime state', () {
    final payload = _buildPayloadConfig();
    payload.generationRuntimeState = GenerationRuntimeState(
      vibeEnabled: false,
      hasPendingBatchResume: true,
      resumeTargetTotalCount: 100,
      resumeCompletedCount: 49,
      resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
    );

    final json = payload.toJson();

    expect(json.containsKey('generation_runtime_state'), isFalse);
    expect(json.containsKey('vibe_enabled'), isFalse);
    expect(json.containsKey('resume_target_total_count'), isFalse);
  });
}
