import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/ui/navigation/view_models/navigation_view_model.dart';

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  test('changing studio sections does not serialize generation config', () {
    final payload = _RecordingPayloadConfig();
    GetIt.I.registerSingleton<ConfigService>(ConfigService());
    GetIt.I.registerSingleton<PayloadConfig>(payload);

    final navigationViewModel = NavigationViewModel();
    navigationViewModel.changeIndex(1);

    expect(navigationViewModel.currentPageIndex, 1);
    expect(payload.toJsonCount, 0);
  });
}

class _RecordingPayloadConfig extends PayloadConfig {
  int toJsonCount = 0;

  _RecordingPayloadConfig()
      : super(
          rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
          characterConfigList: const [],
          savedPromptConfigList: const [],
          paramConfig: ParamConfig(),
          settings: Settings.fromJson({'welcome_message_version': '1.0.0'}),
          overridePrompt: '',
          useOverridePrompt: false,
          useCharacterPromptWithOverride: false,
        );

  @override
  Map<String, dynamic> toJson() {
    toJsonCount += 1;
    return super.toJson();
  }
}
