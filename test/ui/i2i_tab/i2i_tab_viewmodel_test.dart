import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';

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
}
