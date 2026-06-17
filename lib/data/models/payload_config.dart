import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/generation_runtime_state.dart';
import 'package:novel_studio/data/models/global_generation_params.dart';
import 'package:novel_studio/data/models/i2i_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/prompt_replace_rule.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/models/vibe_config.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/models/precise_reference_config.dart';

class PayloadResult {
  final String comment;
  final Map<String, dynamic> payload;

  const PayloadResult({
    required this.comment,
    required this.payload,
  });
}

const Map<int, String> xMapping = {
  0: 'X',
  1: 'A',
  2: 'B',
  3: 'C',
  4: 'D',
  5: 'E',
};

const Map<int, double> doubleMapping = {
  0: 0.0,
  1: 0.1,
  2: 0.3,
  3: 0.5,
  4: 0.7,
  5: 0.9
};

class PayloadConfig {
  PromptConfig rootPromptConfig;
  List<CharacterConfig> characterConfigList;
  List<PromptConfig> savedPromptConfigList;
  List<PromptReplaceRule> promptReplaceRules = [];

  ParamConfig paramConfig;
  GlobalGenerationParams globalGenerationParams;
  GenerationRuntimeState generationRuntimeState;

  Settings settings;

  I2IConfig i2iConfig = I2IConfig();
  List<VibeConfig> vibeConfigList = [];
  List<VibeConfigV4> vibeConfigListV4 = [];
  List<PreciseReferenceConfig> preciseReferenceList = [];
  bool usePreciseReference = false;

  String overridePrompt;
  bool useOverridePrompt;
  bool useCharacterPromptWithOverride;

  PayloadConfig({
    required this.rootPromptConfig,
    required this.characterConfigList,
    required this.savedPromptConfigList,
    required this.paramConfig,
    GlobalGenerationParams? globalGenerationParams,
    GenerationRuntimeState? generationRuntimeState,
    required this.settings,
    required this.overridePrompt,
    required this.useOverridePrompt,
    required this.useCharacterPromptWithOverride,
  })  : globalGenerationParams = globalGenerationParams ??
            GlobalGenerationParams.fromParamConfig(paramConfig),
        generationRuntimeState =
            generationRuntimeState ?? GenerationRuntimeState();

  VibeConfigV4? get scriptVibeConfigV4 =>
      vibeConfigListV4.isEmpty ? null : vibeConfigListV4.first;

  void setScriptVibeConfigV4(VibeConfigV4? config) {
    vibeConfigListV4 = config == null ? [] : [config];
  }

  void setScriptVibeConfigV4List(List<VibeConfigV4> configs) {
    vibeConfigListV4 = List.unmodifiable(configs);
  }

  Map<String, String> getHeaders() {
    return {
      "authorization": "Bearer ${settings.apiKey}",
      "referer": "https://novelai.net",
      "user-agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"
    };
  }

  Map<String, dynamic> toJson() {
    return {
      "prompt_config": rootPromptConfig.toJson(),
      "character_config":
          characterConfigList.map((elem) => elem.toJson()).toList(),
      "saved_config":
          savedPromptConfigList.map((elem) => elem.toJson()).toList(),
      'prompt_replace_rules':
          promptReplaceRules.map((elem) => elem.toJson()).toList(),
      "param_config": paramConfig.toJson(),
      "settings": settings.toJson(),
      'vibe_config_list': vibeConfigList.map((elem) => elem.toJson()).toList(),
      'vibe_config_list_v4':
          vibeConfigListV4.map((elem) => elem.toJson()).toList(),
      'override_prompt': overridePrompt,
      'use_override_prompt': useOverridePrompt,
      'use_character_prompt_with_override': useCharacterPromptWithOverride,
      'use_precise_reference': usePreciseReference,
      'precise_reference_list':
          preciseReferenceList.map((elem) => elem.toJson()).toList(),
      'i2i_config': i2iConfig.toJson(),
    };
  }

  factory PayloadConfig.fromJson(Map<String, dynamic> jsonData) {
    final jsonCharacterList = jsonData.containsKey('character_config')
        ? jsonData['character_config'] as List<dynamic>
        : [];
    final jsonSavedPromptList = jsonData.containsKey('saved_config')
        ? jsonData['saved_config'] as List<dynamic>
        : [];
    final characterList = jsonCharacterList
        .map((configJson) => CharacterConfig.fromJson(configJson))
        .toList();
    final savedList = jsonSavedPromptList
        .map((configJson) => PromptConfig.fromJson(configJson))
        .toList();
    final jsonReplaceRules = jsonData.containsKey('prompt_replace_rules')
        ? jsonData['prompt_replace_rules'] as List<dynamic>
        : [];
    final replaceRuleList = jsonReplaceRules
        .whereType<Map<String, dynamic>>()
        .map((ruleJson) => PromptReplaceRule.fromJson(ruleJson))
        .toList();
    final jsonVibeList = jsonData.containsKey('vibe_config_list')
        ? jsonData['vibe_config_list'] as List<dynamic>
        : [];
    final vibeList = jsonVibeList
        .whereType<Map<String, dynamic>>()
        .map((configJson) => VibeConfig.fromJson(configJson))
        .toList();
    final jsonVibeV4List = jsonData.containsKey('vibe_config_list_v4')
        ? jsonData['vibe_config_list_v4'] as List<dynamic>
        : [];
    final vibeV4List = jsonVibeV4List
        .whereType<Map<String, dynamic>>()
        .map((configJson) => VibeConfigV4.fromJson(configJson))
        .toList();
    final jsonPreciseList = jsonData.containsKey('precise_reference_list')
        ? jsonData['precise_reference_list'] as List<dynamic>
        : [];
    final preciseList = jsonPreciseList
        .whereType<Map<String, dynamic>>()
        .map((configJson) => PreciseReferenceConfig.fromJson(configJson))
        .toList();

    final payloadConfig = PayloadConfig(
      rootPromptConfig: PromptConfig.fromJson(jsonData['prompt_config']),
      characterConfigList: characterList,
      savedPromptConfigList: savedList,
      paramConfig: ParamConfig.fromJson(jsonData['param_config'] ?? {}),
      settings: Settings.fromJson(jsonData['settings'] ?? {}),
      overridePrompt: jsonData['override_prompt'] ?? '',
      useOverridePrompt: jsonData['use_override_prompt'] ?? false,
      useCharacterPromptWithOverride:
          jsonData['use_character_prompt_with_override'] ?? false,
    );
    payloadConfig.promptReplaceRules = replaceRuleList;
    payloadConfig.vibeConfigList = vibeList;
    payloadConfig.vibeConfigListV4 = vibeV4List;
    payloadConfig.usePreciseReference =
        jsonData['use_precise_reference'] ?? false;
    payloadConfig.preciseReferenceList = preciseList;
    payloadConfig.i2iConfig =
        I2IConfig.fromJson(_readObject(jsonData['i2i_config']));
    return payloadConfig;
  }

  void loadJson(
    Map<String, dynamic> jsonData, {
    bool preserveCurrentApiKey = false,
  }) {
    final currentApiKey = settings.apiKey;
    final jsonCharacterList = jsonData.containsKey('character_config')
        ? jsonData['character_config'] as List<dynamic>
        : [];
    final jsonSavedPromptList = jsonData.containsKey('saved_config')
        ? jsonData['saved_config'] as List<dynamic>
        : [];
    final characterList = jsonCharacterList.map((configJson) {
      return CharacterConfig.fromJson(configJson);
    }).toList();
    final savedList = jsonSavedPromptList
        .map((configJson) => PromptConfig.fromJson(configJson))
        .toList();
    final jsonReplaceRules = jsonData.containsKey('prompt_replace_rules')
        ? jsonData['prompt_replace_rules'] as List<dynamic>
        : [];
    rootPromptConfig = PromptConfig.fromJson(jsonData['prompt_config']);
    characterConfigList = characterList;
    savedPromptConfigList = savedList;
    promptReplaceRules = jsonReplaceRules
        .whereType<Map<String, dynamic>>()
        .map((ruleJson) => PromptReplaceRule.fromJson(ruleJson))
        .toList();
    paramConfig = ParamConfig.fromJson(
      (jsonData['param_config'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    settings = Settings.fromJson(
      (jsonData['settings'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    final jsonVibeList = jsonData.containsKey('vibe_config_list')
        ? jsonData['vibe_config_list'] as List<dynamic>
        : [];
    vibeConfigList = jsonVibeList
        .whereType<Map<String, dynamic>>()
        .map((configJson) => VibeConfig.fromJson(configJson))
        .toList();
    final jsonVibeV4List = jsonData.containsKey('vibe_config_list_v4')
        ? jsonData['vibe_config_list_v4'] as List<dynamic>
        : [];
    vibeConfigListV4 = jsonVibeV4List
        .whereType<Map<String, dynamic>>()
        .map((configJson) => VibeConfigV4.fromJson(configJson))
        .toList();
    overridePrompt = jsonData['override_prompt'] ?? '';
    useOverridePrompt = jsonData['use_override_prompt'] ?? false;
    useCharacterPromptWithOverride =
        jsonData['use_character_prompt_with_override'] ?? false;
    usePreciseReference = jsonData['use_precise_reference'] ?? false;

    final jsonPreciseList = jsonData.containsKey('precise_reference_list')
        ? jsonData['precise_reference_list'] as List<dynamic>
        : [];
    preciseReferenceList = jsonPreciseList
        .whereType<Map<String, dynamic>>()
        .map((configJson) => PreciseReferenceConfig.fromJson(configJson))
        .toList();
    i2iConfig.loadJson(_readObject(jsonData['i2i_config']));
    if (preserveCurrentApiKey) {
      settings.apiKey = currentApiKey;
    }
  }

  void resetPromptSelectionState() {
    rootPromptConfig.resetSelectionState();
    for (final savedConfig in savedPromptConfigList) {
      savedConfig.resetSelectionState();
    }
    for (final characterConfig in characterConfigList) {
      characterConfig.positivePromptConfig.resetSelectionState();
    }
  }

  static Map<String, dynamic> _readObject(dynamic value) {
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }
}
