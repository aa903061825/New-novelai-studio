import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';
import 'package:novel_studio/ui/vibe_config_v4/viewmodels/vibe_config_v4_list_viewmodel.dart';
import 'package:novel_studio/ui/vibe_config_v4/viewmodels/vibe_config_v4_viewmodel.dart';

void main() {
  test('removes a Vibe from the unmodifiable workbench import list', () {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
      characterConfigList: const [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({'number_of_requests': 0}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    );
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    GetIt.I.registerSingleton<ConfigService>(ConfigService());
    addTearDown(GetIt.I.reset);
    final first = VibeConfigV4(
      fileName: 'first-vibe',
      vibeB64: 'encoded-first',
      referenceStrength: 0.3,
    );
    final second = VibeConfigV4(
      fileName: 'second-vibe',
      vibeB64: 'encoded-second',
      referenceStrength: 0.4,
    );
    payload.setScriptVibeConfigV4List([first, second]);
    final viewmodel = VibeConfigV4ListViewmodel();
    var notifications = 0;
    viewmodel.addListener(() => notifications++);

    viewmodel.removeConfigAtIndex(0);

    expect(payload.vibeConfigListV4, [same(second)]);
    expect(notifications, 1);
    expect(
      () => payload.vibeConfigListV4.removeAt(0),
      throwsUnsupportedError,
    );
  });

  test('reports paid Vibe encoding only after editable I changes', () {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
      characterConfigList: const [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(model: 'nai-diffusion-4-5-full'),
      settings: Settings.fromJson({'number_of_requests': 0}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    );
    payload.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'editable-vibe',
        vibeB64: 'encoded',
        infoExtracted: 0.42,
        encodedInfoExtracted: 0.76,
        referenceStrength: 0.3,
        imageBytes: Uint8List.fromList(const [1, 2, 3]),
      ),
    ];
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    expect(viewmodel.pendingVibeEncodingCount, 1);
    expect(viewmodel.vibeEncodingAnlas, 2);
    expect(viewmodel.knownExtraAnlas, 2);
  });

  test('locks I for encoded-only Vibes and opens it when source exists', () {
    final encodedOnly = VibeConfigV4(
      fileName: 'encoded-only',
      vibeB64: 'encoded',
      infoExtracted: 0.76,
      referenceStrength: 0.3,
    );
    final encodedOnlyViewmodel = VibeConfigV4Viewmodel(config: encodedOnly);

    expect(encodedOnlyViewmodel.canChangeInfoExtracted, isFalse);
    encodedOnlyViewmodel.setInfoExtracted(0.42);
    expect(encodedOnly.infoExtracted, 0.76);

    final withSource = VibeConfigV4(
      fileName: 'with-source',
      vibeB64: 'encoded',
      infoExtracted: 0.76,
      referenceStrength: 0.3,
      imageBytes: Uint8List.fromList(const [1, 2, 3]),
    );

    expect(
      VibeConfigV4Viewmodel(config: withSource).canChangeInfoExtracted,
      isTrue,
    );
  });
}
