import 'package:novel_studio/data/models/generation_runtime_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/i2i_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';

class _FakeConfigService extends ConfigService {
  int saveGenerationRuntimeStateCallCount = 0;
  GenerationRuntimeState? lastSavedState;

  @override
  void saveGenerationRuntimeState(GenerationRuntimeState state) {
    saveGenerationRuntimeStateCallCount++;
    lastSavedState = GenerationRuntimeState.fromJson(state.toJson());
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

  test('setVibeEnabled updates runtime state and persists it', () {
    final viewmodel = I2iTabViewmodel();
    final configService = GetIt.I<ConfigService>() as _FakeConfigService;

    viewmodel.setVibeEnabled(false);

    expect(viewmodel.payloadConfig.generationRuntimeState.vibeEnabled, isFalse);
    expect(configService.saveGenerationRuntimeStateCallCount, 1);
    expect(configService.lastSavedState, isNotNull);
    expect(configService.lastSavedState!.vibeEnabled, isFalse);
  });

  test('creates i2i viewmodel from active payload i2i and parameter configs',
      () {
    final payload = GetIt.I<PayloadConfig>();
    final activeI2iConfig = I2IConfig(
      imageB64: 'active-source',
      strength: 0.72,
      noise: 0.18,
    );
    final activeParamConfig = ParamConfig(model: 'nai-diffusion-4-5-full');
    payload.i2iConfig = activeI2iConfig;
    payload.paramConfig = activeParamConfig;

    final i2iViewmodel = I2iTabViewmodel().createI2iViewmodel();

    expect(identical(i2iViewmodel.config, activeI2iConfig), isTrue);
    expect(identical(i2iViewmodel.paramConfig, activeParamConfig), isTrue);
  });
}
