import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/prompt_replace_rule.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/use_cases/generate_payload_use_case.dart';

PayloadConfig _buildPayloadConfig({
  required List<PromptReplaceRule> rules,
  String basePrompt = 'cat base',
  String characterPrompt = 'cat pose',
  String overridePrompt = 'cat override',
  bool useOverridePrompt = false,
  bool useCharacterPromptWithOverride = false,
}) {
  final paramConfig = ParamConfig();
  paramConfig.negativePrompt = 'bad cat';

  final characterPromptConfig = PromptConfig(
    selectionMethod: 'all',
    shuffled: false,
    type: 'str',
    comment: 'character',
    strs: [characterPrompt],
    prompts: const [],
  );

  final payloadConfig = PayloadConfig(
    rootPromptConfig: PromptConfig(
      selectionMethod: 'all',
      shuffled: false,
      comment: 'root',
      strs: [basePrompt],
      prompts: const [],
    ),
    characterConfigList: [
      CharacterConfig(
        positions: [const Point(1, 1)],
        positivePromptConfig: characterPromptConfig,
        negativePrompt: 'char-uc-cat',
        enabled: true,
      ),
    ],
    savedPromptConfigList: const [],
    paramConfig: paramConfig,
    settings: Settings.fromJson({}),
    overridePrompt: overridePrompt,
    useOverridePrompt: useOverridePrompt,
    useCharacterPromptWithOverride: useCharacterPromptWithOverride,
  );

  payloadConfig.promptReplaceRules = rules;
  return payloadConfig;
}

void main() {
  test(
      'uses global generation params when the corresponding toggles are enabled',
      () {
    final payloadConfig = _buildPayloadConfig(rules: const []);
    payloadConfig.paramConfig.steps = 28;
    payloadConfig.paramConfig.scale = 6.5;
    payloadConfig.paramConfig.cfgRescale = 0.1;
    payloadConfig.paramConfig.sampler = 'k_euler_ancestral';
    payloadConfig.paramConfig.negativePrompt = 'config uc';

    payloadConfig.globalGenerationParams
      ..useGlobalSteps = true
      ..useGlobalScale = true
      ..useGlobalCfgRescale = true
      ..useGlobalSampler = true
      ..useGlobalNegativePrompt = true
      ..steps = 15
      ..scale = 8.2
      ..cfgRescale = 0.45
      ..sampler = 'k_euler'
      ..negativePrompt = 'global uc';

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params['steps'], 15);
    expect(params['scale'], 8.2);
    expect(params['cfg_rescale'], 0.45);
    expect(params['sampler'], 'k_euler');
    expect(params['negative_prompt'], 'global uc');
    expect(
      ((params['v4_negative_prompt'] as Map<String, dynamic>)['caption']
          as Map<String, dynamic>)['base_caption'],
      'global uc',
    );
  });

  test(
      'keeps config-owned generation params when the global toggles are disabled',
      () {
    final payloadConfig = _buildPayloadConfig(rules: const []);
    payloadConfig.paramConfig.steps = 21;
    payloadConfig.paramConfig.scale = 7.3;
    payloadConfig.paramConfig.cfgRescale = 0.2;
    payloadConfig.paramConfig.sampler = 'k_dpmpp_2m';
    payloadConfig.paramConfig.negativePrompt = 'config only uc';

    payloadConfig.globalGenerationParams
      ..useGlobalSteps = false
      ..useGlobalScale = false
      ..useGlobalCfgRescale = false
      ..useGlobalSampler = false
      ..useGlobalNegativePrompt = false
      ..steps = 15
      ..scale = 8.2
      ..cfgRescale = 0.45
      ..sampler = 'k_euler'
      ..negativePrompt = 'global uc';

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params['steps'], 21);
    expect(params['scale'], 7.3);
    expect(params['cfg_rescale'], 0.2);
    expect(params['sampler'], 'k_dpmpp_2m');
    expect(params['negative_prompt'], 'config only uc');
    expect(
      ((params['v4_negative_prompt'] as Map<String, dynamic>)['caption']
          as Map<String, dynamic>)['base_caption'],
      'config only uc',
    );
  });

  test('can explicitly ignore global generation params', () {
    final payloadConfig = _buildPayloadConfig(rules: const []);
    payloadConfig.paramConfig.steps = 21;
    payloadConfig.paramConfig.scale = 7.3;
    payloadConfig.paramConfig.cfgRescale = 0.2;
    payloadConfig.paramConfig.sampler = 'k_dpmpp_2m';
    payloadConfig.paramConfig.negativePrompt = 'config only uc';

    payloadConfig.globalGenerationParams
      ..useGlobalSteps = true
      ..useGlobalScale = true
      ..useGlobalCfgRescale = true
      ..useGlobalSampler = true
      ..useGlobalNegativePrompt = true
      ..steps = 15
      ..scale = 8.2
      ..cfgRescale = 0.45
      ..sampler = 'k_euler'
      ..negativePrompt = 'global uc';

    final result = GeneratePayloadUseCase(
      payloadConfig: payloadConfig,
      useGlobalGenerationParams: false,
    )();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params['steps'], 21);
    expect(params['scale'], 7.3);
    expect(params['cfg_rescale'], 0.2);
    expect(params['sampler'], 'k_dpmpp_2m');
    expect(params['negative_prompt'], 'config only uc');
    expect(
      ((params['v4_negative_prompt'] as Map<String, dynamic>)['caption']
          as Map<String, dynamic>)['base_caption'],
      'config only uc',
    );
  });

  test('can explicitly ignore batch resolution params', () {
    final payloadConfig = _buildPayloadConfig(rules: const []);
    payloadConfig.paramConfig
      ..sizes = const [GenerationSize(width: 1472, height: 704)]
      ..enableBatchResolution = true
      ..batchResolutionMode = 'loop'
      ..batchResolutionText = '704x1472';

    final result = GeneratePayloadUseCase(
      payloadConfig: payloadConfig,
      useBatchResolution: false,
    )();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params['width'], 1472);
    expect(params['height'], 704);
  });

  test('replaces base/character/override prompts but keeps UC unchanged', () {
    final rules = [
      PromptReplaceRule(
        id: 'r1',
        source: 'cat',
        target: 'dog',
        enabled: true,
      ),
    ];

    final regularConfig = _buildPayloadConfig(
      rules: rules,
      useOverridePrompt: false,
    );
    final regularResult =
        GeneratePayloadUseCase(payloadConfig: regularConfig)();
    final regularParams =
        regularResult.payload['parameters'] as Map<String, dynamic>;
    final regularCharacters =
        regularParams['characterPrompts'] as List<dynamic>;

    expect(regularResult.payload['input'], 'dog base');
    expect((regularCharacters.first as Map<String, dynamic>)['prompt'],
        'dog pose');
    expect(
        (regularCharacters.first as Map<String, dynamic>)['uc'], 'char-uc-cat');
    expect(regularParams['negative_prompt'], 'bad cat');
    expect(
      ((regularParams['v4_negative_prompt'] as Map<String, dynamic>)['caption']
          as Map<String, dynamic>)['base_caption'],
      'bad cat',
    );
    expect(
      ((((regularParams['v4_negative_prompt']
                  as Map<String, dynamic>)['caption']
              as Map<String, dynamic>)['char_captions'] as List<dynamic>)
          .first as Map<String, dynamic>)['char_caption'],
      'char-uc-cat',
    );

    final overrideConfig = _buildPayloadConfig(
      rules: rules,
      useOverridePrompt: true,
      useCharacterPromptWithOverride: true,
      overridePrompt: 'cat override',
    );
    final overrideResult =
        GeneratePayloadUseCase(payloadConfig: overrideConfig)();
    final overrideParams =
        overrideResult.payload['parameters'] as Map<String, dynamic>;
    final overrideCharacters =
        overrideParams['characterPrompts'] as List<dynamic>;

    expect(overrideResult.payload['input'], 'dog override');
    expect((overrideCharacters.first as Map<String, dynamic>)['prompt'],
        'dog pose');
    expect((overrideCharacters.first as Map<String, dynamic>)['uc'],
        'char-uc-cat');
    expect(overrideParams['negative_prompt'], 'bad cat');
    expect(
      ((overrideParams['v4_negative_prompt'] as Map<String, dynamic>)['caption']
          as Map<String, dynamic>)['base_caption'],
      'bad cat',
    );
    expect(
      ((((overrideParams['v4_negative_prompt']
                  as Map<String, dynamic>)['caption']
              as Map<String, dynamic>)['char_captions'] as List<dynamic>)
          .first as Map<String, dynamic>)['char_caption'],
      'char-uc-cat',
    );
  });

  test('skips empty source rules and supports empty target deletion', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'ignore-empty-source',
          source: '',
          target: 'X',
          enabled: true,
        ),
        PromptReplaceRule(
          id: 'delete-token',
          source: '--',
          target: '',
          enabled: true,
        ),
      ],
      basePrompt: 'A--B',
      characterPrompt: 'C--D',
      overridePrompt: 'E--F',
      useOverridePrompt: true,
      useCharacterPromptWithOverride: true,
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], 'EF');
    expect((characters.first as Map<String, dynamic>)['prompt'], 'CD');
    expect(params['negative_prompt'], 'bad cat');
  });

  test('applies replacement rules in list order', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'step-1',
          source: 'ab',
          target: 'a',
          enabled: true,
        ),
        PromptReplaceRule(
          id: 'step-2',
          source: 'a',
          target: 'x',
          enabled: true,
        ),
      ],
      basePrompt: 'ab',
      characterPrompt: 'ab',
      overridePrompt: 'ab',
      useOverridePrompt: false,
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], 'x');
    expect((characters.first as Map<String, dynamic>)['prompt'], 'x');
  });

  test('matches irregular whitespace in source phrase', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'spaces',
          source: '  cat hood  ',
          target: 'dog hood',
          enabled: true,
        ),
      ],
      basePrompt: 'cat\u3000\u3000hood',
      characterPrompt: 'cat\thood',
      overridePrompt: 'cat   hood',
      useOverridePrompt: true,
      useCharacterPromptWithOverride: true,
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], 'dog hood');
    expect((characters.first as Map<String, dynamic>)['prompt'], 'dog hood');
  });

  test(
      'applies single-source replacements case-insensitively in list order and trims deleted spacing',
      () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'delete-large',
          source: 'LARGE',
          target: '',
          enabled: true,
        ),
        PromptReplaceRule(
          id: 'replace-emerald',
          source: 'EMERALD',
          target: 'xxxx',
          enabled: true,
        ),
      ],
      basePrompt: 'large emerald eyes with fierce piercing gaze',
      characterPrompt: 'Large Emerald eyes with fierce piercing gaze',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], 'xxxx eyes with fierce piercing gaze');
    expect(
      (characters.first as Map<String, dynamic>)['prompt'],
      'xxxx eyes with fierce piercing gaze',
    );
  });

  test('display comment reflects replaced prompt text', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'comment',
          source: 'cat',
          target: 'dog',
          enabled: true,
        ),
      ],
      basePrompt: 'cat base',
      characterPrompt: 'cat pose',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.comment, contains('dog base'));
    expect(result.comment, contains('dog pose'));
  });

  test('single-source comment replacement preserves the label before colon',
      () {
    final payloadConfig = PayloadConfig(
      rootPromptConfig: PromptConfig(
        selectionMethod: 'all',
        shuffled: false,
        type: 'str',
        comment: 'cat title',
        strs: ['cat prompt'],
        prompts: const [],
      ),
      characterConfigList: const [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    )..promptReplaceRules = [
        PromptReplaceRule(
          id: 'single-comment-label',
          source: 'cat',
          target: 'dog',
          enabled: true,
        ),
      ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.payload['input'], 'dog prompt');
    expect(result.comment, 'cat title: dog prompt');
  });

  test('merges comma-separated source tags at the earliest prompt position',
      () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'group-merge',
          source: 'black panties, white thighhighs, white strapless dress',
          target: 'bunny outfit',
          enabled: true,
        ),
      ],
      basePrompt: '1girl, white thighhighs, smile, black panties',
      characterPrompt: 'black panties, white thighhighs',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], '1girl, bunny outfit, smile');
    expect(
        (characters.first as Map<String, dynamic>)['prompt'], 'bunny outfit');
    expect(result.comment, contains('root: 1girl, bunny outfit, smile'));
    expect(result.comment, contains('character: bunny outfit'));
  });

  test('matches comma-separated source tags case-insensitively', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'group-merge-case-insensitive',
          source: 'BLACK PANTIES, WHITE THIGHHIGHS',
          target: 'bunny outfit',
          enabled: true,
        ),
      ],
      basePrompt: '1girl, white thighhighs, smile, black panties',
      characterPrompt: 'Black Panties, White Thighhighs',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], '1girl, bunny outfit, smile');
    expect(
        (characters.first as Map<String, dynamic>)['prompt'], 'bunny outfit');
  });

  test('matches grouped tags inside weighted blocks that contain commas', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'weighted-block-with-commas',
          source:
              'bihyung (black survival), yeshunguang (zenless zone zero), hair-based animal ears, downward hair flips, pointy hair, side locks',
          target: 'replacement character',
          enabled: true,
        ),
      ],
      basePrompt:
          '{{1.8::yeshunguang (zenless zone zero), side locks::}}, 1.2::pink horns, horns on headwear::, 1.3::slender waist',
      characterPrompt:
          '{{1.8::yeshunguang (zenless zone zero), side locks::}}, smile',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(
      result.payload['input'],
      '{{1.8::replacement character::}}, 1.2::pink horns, horns on headwear::, 1.3::slender waist',
    );
    expect(
      (characters.first as Map<String, dynamic>)['prompt'],
      '{{1.8::replacement character::}}, smile',
    );
  });

  test('ignores stray source punctuation around grouped tag names', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'source-stray-punctuation',
          source:
              'bihyung (black survival), :yeshunguang (zenless zone zero), hair-based animal ears, downward hair flips, pointy hair, side locks；',
          target: 'replacement character',
          enabled: true,
        ),
      ],
      basePrompt:
          '{{1.8::yeshunguang (zenless zone zero), side locks::}}, 1.2::pink horns, horns on headwear::, 1.3::slender waist',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(
      result.payload['input'],
      '{{1.8::replacement character::}}, 1.2::pink horns, horns on headwear::, 1.3::slender waist',
    );
  });

  test('deletes an entire weighted block when an inner grouped tag matches',
      () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'delete-weighted-block-with-inner-match',
          source: 'yeshunguang (zenless zone zero), side locks',
          target: '',
          enabled: true,
        ),
      ],
      basePrompt:
          '{{1.8::yeshunguang (zenless zone zero), side locks::}}, modernized hanbok',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.payload['input'], 'modernized hanbok');
  });

  test('deletes every matched tag in a grouped rule when target is empty', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'group-delete',
          source: 'black panties, white thighhighs',
          target: '',
          enabled: true,
        ),
      ],
      basePrompt: '1girl, black panties, smile, white thighhighs',
      characterPrompt: 'white thighhighs, black panties',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], '1girl, smile');
    expect((characters.first as Map<String, dynamic>)['prompt'], '');
    expect(result.comment, contains('root: 1girl, smile'));
    expect(result.comment, contains('character: '));
  });

  test(
      'matches weighted grouped tags and inherits the anchor shell for a plain target',
      () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'weighted-group',
          source: 'black panties, white thighhighs',
          target: 'bunny outfit',
          enabled: true,
        ),
      ],
      basePrompt: '1girl, {white thighhighs}, 1::black panties::',
      characterPrompt: '0.8::black panties::, smile',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], '1girl, {bunny outfit}');
    expect((characters.first as Map<String, dynamic>)['prompt'],
        '0.8::bunny outfit::, smile');
  });

  test('uses weighted target as-is instead of nesting inherited shell', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'weighted-target',
          source: 'black panties, white thighhighs',
          target: '0.8::bunny outfit::',
          enabled: true,
        ),
      ],
      basePrompt: '1::black panties::, white thighhighs',
      characterPrompt: '{white thighhighs}, black panties',
    );

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;
    final characters = params['characterPrompts'] as List<dynamic>;

    expect(result.payload['input'], '0.8::bunny outfit::');
    expect((characters.first as Map<String, dynamic>)['prompt'],
        '0.8::bunny outfit::');
  });

  test('suggestedFileName reflects grouped/global replacements', () {
    final payloadConfig = _buildPayloadConfig(
      rules: [
        PromptReplaceRule(
          id: 'group-filename',
          source: 'black panties, white thighhighs',
          target: 'bunny outfit',
          enabled: true,
        ),
      ],
      basePrompt: '1girl, white thighhighs, smile, black panties',
    );
    payloadConfig.settings.fileNamePrefixKey = '__root__';

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.payload['input'], '1girl, bunny outfit, smile');
    expect(result.comment, contains('root: 1girl, bunny outfit, smile'));
    expect(result.suggestedFileName, '1girl, bunny outfit, smile');
  });

  test('preserves comment labels when grouped rules apply line by line', () {
    final payloadConfig = PayloadConfig(
      rootPromptConfig: PromptConfig(
        selectionMethod: 'all',
        shuffled: false,
        type: 'config',
        comment: 'root',
        strs: const [],
        prompts: [
          PromptConfig(
            selectionMethod: 'all',
            shuffled: false,
            type: 'str',
            comment: 'look',
            strs: ['black panties, smile'],
            prompts: const [],
          ),
          PromptConfig(
            selectionMethod: 'all',
            shuffled: false,
            type: 'str',
            comment: 'outfit',
            strs: ['white thighhighs, blush'],
            prompts: const [],
          ),
        ],
      ),
      characterConfigList: [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    )..promptReplaceRules = [
        PromptReplaceRule(
          id: 'group-comment',
          source: 'black panties, white thighhighs',
          target: 'bunny outfit',
          enabled: true,
        ),
      ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.payload['input'], 'bunny outfit, smile, blush');
    expect(result.comment,
        'root:\n  look: bunny outfit, smile\n  outfit: bunny outfit, blush');
  });

  test('leaves unmatched comment lines unchanged for grouped rules', () {
    final payloadConfig = PayloadConfig(
      rootPromptConfig: PromptConfig(
        selectionMethod: 'all',
        shuffled: false,
        type: 'config',
        comment: 'root',
        strs: const [],
        prompts: [
          PromptConfig(
            selectionMethod: 'all',
            shuffled: false,
            type: 'str',
            comment: 'look',
            strs: ['smile, blush'],
            prompts: const [],
          ),
        ],
      ),
      characterConfigList: [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    )..promptReplaceRules = [
        PromptReplaceRule(
          id: 'group-comment-no-match',
          source: 'black panties, white thighhighs',
          target: 'bunny outfit',
          enabled: true,
        ),
      ];

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();

    expect(result.payload['input'], 'smile, blush');
    expect(result.comment, 'root:\n  look: smile, blush');
  });
}
