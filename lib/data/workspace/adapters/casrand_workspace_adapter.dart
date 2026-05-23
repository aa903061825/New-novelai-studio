import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/prompt_replace_rule.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

class CasRandWorkspaceAdapter {
  PayloadConfig toPayloadConfig(
    WorkspacePromptConfig promptConfig,
    GenerationProfile generationProfile, {
    Map<String, dynamic> legacySettings = const {},
    List<Map<String, dynamic>> replaceRules = const [],
  }) {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig.fromJson(
        _promptJson(promptConfig.rootConfig),
      ),
      characterConfigList: const [],
      savedPromptConfigList: promptConfig.savedBlocks
          .map((block) => PromptConfig.fromJson(_promptJson(block)))
          .toList(growable: false),
      paramConfig: _paramConfig(generationProfile),
      settings: Settings.fromJson({
        ...generationProfile.batchDefaults,
        ...legacySettings,
      }),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    );
    payload.promptReplaceRules = replaceRules
        .map((rule) => PromptReplaceRule.fromJson(rule))
        .toList(growable: false);
    return payload;
  }

  ParamConfig _paramConfig(GenerationProfile generationProfile) {
    final paramJson = ParamConfig().toJson();
    paramJson.addAll(generationProfile.params);
    if (generationProfile.negativePrompt.isNotEmpty) {
      paramJson['negative_prompt'] = generationProfile.negativePrompt;
    }

    final config = ParamConfig.fromJson(paramJson);
    config.loadJson(generationProfile.params);
    if (generationProfile.negativePrompt.isNotEmpty) {
      config.negativePrompt = generationProfile.negativePrompt;
    }
    return config;
  }

  Map<String, dynamic> _promptJson(Map<String, dynamic> json) {
    return {
      ...PromptConfig(strs: const [], prompts: const []).toJson(),
      ...json,
    };
  }
}
