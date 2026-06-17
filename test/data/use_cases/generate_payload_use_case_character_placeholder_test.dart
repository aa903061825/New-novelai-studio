import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/prompt_replace_rule.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/use_cases/generate_payload_use_case.dart';

CharacterConfig _buildCharacterConfig({
  required List<String> prompts,
  String selectionMethod = 'all',
}) {
  final characterPromptConfig = PromptConfig(
    selectionMethod: selectionMethod,
    shuffled: false,
    num: 1,
    type: 'str',
    comment: 'character',
    strs: prompts,
    prompts: const [],
  );

  return CharacterConfig(
    positions: [const Point(1, 1)],
    positivePromptConfig: characterPromptConfig,
    negativePrompt: '',
    enabled: true,
  );
}

PayloadConfig _buildPayloadConfigWithCharacterSequence(List<String> sequence) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      comment: 'root',
      strs: const ['scene'],
      prompts: const [],
    ),
    characterConfigList: [
      _buildCharacterConfig(
        prompts: sequence,
        selectionMethod: 'single_sequential',
      ),
    ],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

PayloadConfig _buildPayloadConfigWithCharacters(List<String> prompts) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      comment: 'root',
      strs: const ['scene'],
      prompts: const [],
    ),
    characterConfigList: prompts
        .map((prompt) => _buildCharacterConfig(prompts: [prompt]))
        .toList(),
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

PayloadConfig _buildPayloadConfigWithContentPrompt({
  required String selectionMethod,
  required List<String> prompts,
  int num = 1,
}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(
      selectionMethod: 'all',
      shuffled: false,
      type: 'config',
      comment: 'root',
      strs: const [],
      prompts: [
        PromptConfig(
          selectionMethod: selectionMethod,
          shuffled: false,
          num: num,
          type: 'str',
          comment: '内容',
          strs: prompts,
          prompts: const [],
        ),
      ],
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
  test('only a single comma placeholder is treated as inactive', () {
    final payloadConfig = _buildPayloadConfigWithCharacterSequence([
      ',',
      'heroine',
      '，',
      ',,',
      '，，',
      '!!!',
    ]);
    final useCase = GeneratePayloadUseCase(payloadConfig: payloadConfig);

    final first = useCase();
    final firstParams = first.payload['parameters'] as Map<String, dynamic>;
    final firstCharacterPrompts =
        firstParams['characterPrompts'] as List<dynamic>;

    final second = useCase();
    final secondParams = second.payload['parameters'] as Map<String, dynamic>;
    final secondCharacterPrompts =
        secondParams['characterPrompts'] as List<dynamic>;

    final third = useCase();
    final thirdParams = third.payload['parameters'] as Map<String, dynamic>;
    final thirdCharacterPrompts =
        thirdParams['characterPrompts'] as List<dynamic>;

    final fourth = useCase();
    final fourthParams = fourth.payload['parameters'] as Map<String, dynamic>;
    final fourthCharacterPrompts =
        fourthParams['characterPrompts'] as List<dynamic>;

    final fifth = useCase();
    final fifthParams = fifth.payload['parameters'] as Map<String, dynamic>;
    final fifthCharacterPrompts =
        fifthParams['characterPrompts'] as List<dynamic>;

    final sixth = useCase();
    final sixthParams = sixth.payload['parameters'] as Map<String, dynamic>;
    final sixthCharacterPrompts =
        sixthParams['characterPrompts'] as List<dynamic>;

    expect(firstCharacterPrompts, isEmpty);
    expect(secondCharacterPrompts.length, 1);
    expect(
      (secondCharacterPrompts.first as Map<String, dynamic>)['prompt'],
      'heroine',
    );
    expect(thirdCharacterPrompts, isEmpty);
    expect(
      (fourthCharacterPrompts.first as Map<String, dynamic>)['prompt'],
      ',,',
    );
    expect(
      (fifthCharacterPrompts.first as Map<String, dynamic>)['prompt'],
      '，，',
    );
    expect(
      (sixthCharacterPrompts.first as Map<String, dynamic>)['prompt'],
      '!!!',
    );
  });

  test('placeholder-only secondary layers do not cancel valid layers', () {
    final payloadConfig = _buildPayloadConfigWithCharacters([
      'heroine',
      ',',
      '，',
    ]);

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characterPrompts = params['characterPrompts'] as List<dynamic>;
    final v4Prompt = params['v4_prompt'] as Map<String, dynamic>;
    final caption = v4Prompt['caption'] as Map<String, dynamic>;
    final v4CharCaptions = caption['char_captions'] as List<dynamic>;

    expect(characterPrompts.length, 1);
    expect(
      (characterPrompts.first as Map<String, dynamic>)['prompt'],
      'heroine',
    );
    expect(v4CharCaptions.length, 1);
  });

  test('raw non-placeholder is kept even when replacement turns it into comma',
      () {
    final payloadConfig = _buildPayloadConfigWithCharacters(['heroine']);
    payloadConfig.promptReplaceRules = [
      PromptReplaceRule(
        id: 'to-comma',
        source: 'heroine',
        target: ',',
        enabled: true,
      ),
    ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characterPrompts = params['characterPrompts'] as List<dynamic>;

    expect(characterPrompts.length, 1);
    expect(
      (characterPrompts.first as Map<String, dynamic>)['prompt'],
      ',',
    );
  });

  test('tracks selected order for 内容 single sequential selection', () {
    final payloadConfig = _buildPayloadConfigWithContentPrompt(
      selectionMethod: 'single_sequential',
      prompts: ['pose a', 'pose b', 'pose c'],
    );
    final useCase = GeneratePayloadUseCase(payloadConfig: payloadConfig);

    final first = useCase();
    final second = useCase();

    expect(first.contentOrderText, '1');
    expect(second.contentOrderText, '2');
  });

  test('tracks multiple selected orders for 内容 multiple_num selection', () {
    final payloadConfig = _buildPayloadConfigWithContentPrompt(
      selectionMethod: 'multiple_num',
      prompts: ['pose a', 'pose b', 'pose c'],
      num: 2,
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.contentOrderText, isNotNull);
    final parts = result.contentOrderText!.split(',');
    expect(parts, hasLength(2));
    for (final part in parts) {
      expect(int.parse(part), inInclusiveRange(1, 3));
    }
  });

  test('omits content order text when 内容 prompt selects nothing', () {
    final payloadConfig = _buildPayloadConfigWithContentPrompt(
      selectionMethod: 'multiple_prob',
      prompts: ['pose a', 'pose b'],
      num: 1,
    );
    payloadConfig.rootPromptConfig.prompts.first.prob = 0.0;

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.contentOrderText, isNull);
  });
}
