import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/workspace/adapters/casrand_workspace_adapter.dart';
import 'package:nai_casrand/data/workspace/importers/casrand_importer.dart';

void main() {
  Map<String, dynamic> legacyConfig() => {
        'prompt_config': {
          'selectionMethod': 'all',
          'shuffled': false,
          'prob': 0.0,
          'num': 1,
          'randomBracketsUpper': 0,
          'randomBracketsLower': 0,
          'type': 'str',
          'comment': 'root',
          'filter': '',
          'strs': ['masterpiece', 'Bearer prompt-secret'],
          'private_block': {'strs': ['private-only prompt']},
          'prompts': [],
          'enabled': true,
        },
        'character_config': const [],
        'saved_config': const [],
        'prompt_replace_rules': [
          {
            'id': 'replace-1',
            'source': 'cat',
            'target': 'dog',
            'enabled': true,
          }
        ],
        'param_config': {
          'model': 'nai-diffusion-4-5-full',
          'width': 832,
          'height': 1216,
          'steps': 28,
          'scale': 5.0,
          'negative_prompt': 'bad anatomy',
          'api_key': 'pst-param-secret',
          'nested': {'token': 'pst-nested-secret', 'keep': true},
        },
        'settings': {'api_key': 'pst-secret', 'proxy': '127.0.0.1:7890'},
        'override_prompt': '',
        'use_override_prompt': false,
        'use_character_prompt_with_override': false,
      };

  test('CasRandImporter splits prompt config and generation profile', () {
    final result = CasRandImporter().importJson(
      legacyConfig(),
      promptConfigId: 'prompt-1',
      profileId: 'profile-1',
    );

    expect(result.promptConfig.id, 'prompt-1');
    expect(result.promptConfig.rootConfig['comment'], 'root');
    expect(result.generationProfile.params['model'], 'nai-diffusion-4-5-full');
    expect(result.generationProfile.negativePrompt, 'bad anatomy');
    expect(result.promptConfig.toJson().toString(),
        isNot(contains('Bearer prompt-secret')));
    expect(result.promptConfig.toJson().toString(),
        isNot(contains('private-only prompt')));
    expect(result.generationProfile.toJson().toString(),
        isNot(contains('pst-secret')));
    expect(result.generationProfile.toJson().toString(),
        isNot(contains('pst-param-secret')));
    expect(result.generationProfile.toJson().toString(),
        isNot(contains('pst-nested-secret')));
  });

  test('CasRandWorkspaceAdapter restores PayloadConfig for generation', () {
    final imported = CasRandImporter().importJson(
      legacyConfig(),
      promptConfigId: 'prompt-1',
      profileId: 'profile-1',
    );

    final payload = CasRandWorkspaceAdapter().toPayloadConfig(
      imported.promptConfig,
      imported.generationProfile,
      legacySettings: {'api_key': 'current-key'},
    );

    expect(payload, isA<PayloadConfig>());
    expect(payload.rootPromptConfig.comment, 'root');
    expect(payload.paramConfig.model, 'nai-diffusion-4-5-full');
    expect(payload.paramConfig.sizes.single.width, 832);
    expect(payload.paramConfig.sizes.single.height, 1216);
    expect(payload.paramConfig.negativePrompt, 'bad anatomy');
    expect(payload.settings.apiKey, 'current-key');
  });
}
