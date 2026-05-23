import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/parameters_config/view_models/parameters_config_viewmodel.dart';

class _FakeConfigService extends ConfigService {
  int saveGlobalGenerationParamsCallCount = 0;

  @override
  void saveGlobalGenerationParams(params) {
    saveGlobalGenerationParamsCallCount++;
  }
}

PayloadConfig _buildPayloadConfig() {
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
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<ConfigService>(_FakeConfigService());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('routes edits to config or global params based on each toggle', () {
    final viewmodel = ParametersConfigViewmodel();

    viewmodel.setUseGlobalSteps(false);
    viewmodel.setSteps(17);
    expect(viewmodel.payloadConfig.paramConfig.steps, 17);
    expect(viewmodel.payloadConfig.globalGenerationParams.steps, isNot(17));

    viewmodel.setUseGlobalSteps(true);
    viewmodel.setSteps(15);
    expect(viewmodel.payloadConfig.globalGenerationParams.steps, 15);
    expect(viewmodel.payloadConfig.paramConfig.steps, 17);

    viewmodel.setUseGlobalScale(false);
    viewmodel.setScale(7.1);
    expect(viewmodel.payloadConfig.paramConfig.scale, 7.1);

    viewmodel.setUseGlobalScale(true);
    viewmodel.setScale(8.4);
    expect(viewmodel.payloadConfig.globalGenerationParams.scale, 8.4);
    expect(viewmodel.payloadConfig.paramConfig.scale, 7.1);

    viewmodel.setUseGlobalCfgRescale(false);
    viewmodel.setCfgRescale(0.25);
    expect(viewmodel.payloadConfig.paramConfig.cfgRescale, 0.25);

    viewmodel.setUseGlobalCfgRescale(true);
    viewmodel.setCfgRescale(0.55);
    expect(viewmodel.payloadConfig.globalGenerationParams.cfgRescale, 0.55);
    expect(viewmodel.payloadConfig.paramConfig.cfgRescale, 0.25);

    viewmodel.setUseGlobalSampler(false);
    viewmodel.setSampler('k_dpmpp_2m');
    expect(viewmodel.payloadConfig.paramConfig.sampler, 'k_dpmpp_2m');

    viewmodel.setUseGlobalSampler(true);
    viewmodel.setSampler('k_euler');
    expect(viewmodel.payloadConfig.globalGenerationParams.sampler, 'k_euler');
    expect(viewmodel.payloadConfig.paramConfig.sampler, 'k_dpmpp_2m');

    viewmodel.setUseGlobalNegativePrompt(false);
    viewmodel.setNegativePrompt('config uc');
    expect(viewmodel.payloadConfig.paramConfig.negativePrompt, 'config uc');

    viewmodel.setUseGlobalNegativePrompt(true);
    viewmodel.setNegativePrompt('global uc');
    expect(
      viewmodel.payloadConfig.globalGenerationParams.negativePrompt,
      'global uc',
    );
    expect(viewmodel.payloadConfig.paramConfig.negativePrompt, 'config uc');
  });

  test('persists global state when toggles or active global values change', () {
    final viewmodel = ParametersConfigViewmodel();
    final configService = GetIt.I<ConfigService>() as _FakeConfigService;

    viewmodel.setUseGlobalSteps(true);
    viewmodel.setSteps(16);
    viewmodel.setUseGlobalNegativePrompt(true);
    viewmodel.setNegativePrompt('persisted uc');
    viewmodel.setUseGlobalSampler(false);
    viewmodel.setSampler('k_dpmpp_2m');

    expect(configService.saveGlobalGenerationParamsCallCount, 4);
  });

  test('imports metadata into the currently active source for each field', () {
    final viewmodel = ParametersConfigViewmodel();

    viewmodel.payloadConfig.paramConfig.steps = 28;
    viewmodel.payloadConfig.paramConfig.scale = 6.5;
    viewmodel.payloadConfig.paramConfig.cfgRescale = 0.1;
    viewmodel.payloadConfig.paramConfig.sampler = 'k_euler_ancestral';
    viewmodel.payloadConfig.paramConfig.negativePrompt = 'config uc';

    viewmodel.setUseGlobalSteps(true);
    viewmodel.setUseGlobalScale(false);
    viewmodel.setUseGlobalCfgRescale(true);
    viewmodel.setUseGlobalSampler(false);
    viewmodel.setUseGlobalNegativePrompt(true);

    final loadedCount = viewmodel.applyMetadataToActiveSource({
      'steps': 11,
      'scale': 7.7,
      'cfg_rescale': 0.66,
      'sampler': 'k_euler',
      'negative_prompt': 'imported uc',
    });

    expect(loadedCount, 5);
    expect(viewmodel.payloadConfig.globalGenerationParams.steps, 11);
    expect(viewmodel.payloadConfig.paramConfig.steps, 28);
    expect(viewmodel.payloadConfig.paramConfig.scale, 7.7);
    expect(viewmodel.payloadConfig.globalGenerationParams.scale, isNot(7.7));
    expect(viewmodel.payloadConfig.globalGenerationParams.cfgRescale, 0.66);
    expect(viewmodel.payloadConfig.paramConfig.cfgRescale, 0.1);
    expect(viewmodel.payloadConfig.paramConfig.sampler, 'k_euler');
    expect(
      viewmodel.payloadConfig.globalGenerationParams.sampler,
      isNot('k_euler'),
    );
    expect(
      viewmodel.payloadConfig.globalGenerationParams.negativePrompt,
      'imported uc',
    );
    expect(viewmodel.payloadConfig.paramConfig.negativePrompt, 'config uc');
  });
}
