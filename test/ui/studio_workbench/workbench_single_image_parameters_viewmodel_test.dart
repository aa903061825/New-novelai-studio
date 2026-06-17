import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';

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
  test('updates only the supplied workbench payload', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    expect(viewmodel.generationCount, 1);

    viewmodel.setSteps(17);
    viewmodel.setScale(7.25);
    viewmodel.setCfgRescale(0.35);
    viewmodel.setSampler('k_euler');
    viewmodel.setNegativePrompt('bad anatomy');

    expect(payload.paramConfig.steps, 17);
    expect(payload.paramConfig.scale, 7.25);
    expect(payload.paramConfig.cfgRescale, 0.35);
    expect(payload.paramConfig.sampler, 'k_euler');
    expect(payload.paramConfig.negativePrompt, 'bad anatomy');
  });

  test('keeps workbench generation count bounded for accidental runs', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setGenerationCount('4');
    expect(viewmodel.generationCount, 4);

    viewmodel.setGenerationCount('0');
    expect(viewmodel.generationCount, 1);

    viewmodel.setGenerationCount('200');
    expect(
      viewmodel.generationCount,
      WorkbenchSingleImageParametersViewmodel.maxGenerationCount,
    );

    viewmodel.setGenerationCount('not a number');
    expect(
      viewmodel.generationCount,
      WorkbenchSingleImageParametersViewmodel.maxGenerationCount,
    );
  });

  test('normalizes manual size to 64 pixel multiples', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setManualSize(width: '801', height: '1201');

    expect(
      payload.paramConfig.sizes,
      const [GenerationSize(width: 832, height: 1216)],
    );
  });

  test('commits draft size text before starting generation', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setDraftWidthText('704');
    viewmodel.setDraftHeightText('1472');

    expect(
      payload.paramConfig.sizes,
      const [GenerationSize(width: 832, height: 1216)],
    );
    expect(viewmodel.commitDraftSize(), isTrue);
    expect(
      payload.paramConfig.sizes,
      const [GenerationSize(width: 704, height: 1472)],
    );
  });

  test('falls back to the default selected size when imported sizes are empty',
      () {
    final payload = _payload();
    payload.paramConfig.sizes = [];
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    expect(
        viewmodel.selectedSize, const GenerationSize(width: 832, height: 1216));
    expect(viewmodel.draftWidthText, '832');
    expect(viewmodel.draftHeightText, '1216');
  });

  test('fixed seed input is retained when random seed is toggled', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setRandomSeedEnabled(false);
    viewmodel.setSeed('12345');
    viewmodel.setRandomSeedEnabled(true);
    viewmodel.setRandomSeedEnabled(false);

    expect(payload.paramConfig.randomSeed, isFalse);
    expect(payload.paramConfig.seed, 12345);
  });

  test('edits character prompt cards in the workbench payload', () {
    final payload = _payload();
    payload.characterConfigList = [
      CharacterConfig.fromEmpty(),
    ];
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setCharacterPrompt(0, 'silver hair, blue eyes');
    viewmodel.setCharacterNegativePrompt(0, 'bad hands');
    viewmodel.setCharacterName(0, '主角');
    viewmodel.setUseCharacterPromptWithOverride(true);

    expect(payload.useCharacterPromptWithOverride, isTrue);
    expect(payload.characterConfigList.single.name, '主角');
    expect(
      payload.characterConfigList.single.positivePromptConfig.strs,
      ['silver hair, blue eyes'],
    );
    expect(payload.characterConfigList.single.negativePrompt, 'bad hands');
  });

  test('stacks and reorders character prompt blocks', () {
    final payload = _payload();
    payload.characterConfigList = [
      CharacterConfig.fromEmpty()
        ..positivePromptConfig.strs = ['base character'],
    ];
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.insertCharacterPromptBlock(0, 1, 'standing pose, red dress');
    viewmodel.insertCharacterPromptBlock(0, 1, 'windy hair');
    viewmodel.moveCharacterPromptBlock(0, 2, 1);
    viewmodel.setCharacterPromptBlock(0, 0, 'heroine, silver hair');
    viewmodel.removeCharacterPromptBlock(0, 1);

    final promptConfig =
        payload.characterConfigList.single.positivePromptConfig;
    expect(promptConfig.type, 'str');
    expect(promptConfig.selectionMethod, 'all');
    expect(promptConfig.shuffled, isFalse);
    expect(promptConfig.strs, [
      'heroine, silver hair',
      'windy hair',
    ]);
  });

  test('tagifies character prompt blocks and restores the original stack', () {
    final payload = _payload();
    payload.characterConfigList = [
      CharacterConfig.fromEmpty()
        ..positivePromptConfig.strs = [
          'heroine, silver hair',
          'blue eyes, long hair',
        ],
    ];
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setCharacterPromptTagified(0, true);

    expect(viewmodel.isCharacterPromptTagified(0), isTrue);
    expect(payload.characterConfigList.single.positivePromptConfig.strs, [
      'heroine',
      'silver hair',
      'blue eyes',
      'long hair',
    ]);
    expect(payload.characterConfigList.single.positivePromptConfig.type, 'str');
    expect(
      payload.characterConfigList.single.positivePromptConfig.selectionMethod,
      'all',
    );
    expect(
      payload.characterConfigList.single.positivePromptConfig.shuffled,
      isFalse,
    );

    viewmodel.setCharacterPromptTagified(0, false);

    expect(viewmodel.isCharacterPromptTagified(0), isFalse);
    expect(payload.characterConfigList.single.positivePromptConfig.strs, [
      'heroine, silver hair',
      'blue eyes, long hair',
    ]);
  });

  test('adds blank character cards up to the workbench character limit', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    for (var index = 0; index < 7; index++) {
      viewmodel.addCharacter();
    }

    expect(payload.characterConfigList, hasLength(6));
    expect(payload.characterConfigList.last.name, '角色 6');
    expect(payload.characterConfigList.every((character) => character.enabled),
        isTrue);
  });
}
