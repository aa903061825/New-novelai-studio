import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';

PayloadConfig _payload({
  required String prompt,
  required String apiKey,
  required String proxy,
}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(steps: 33),
    settings: Settings.fromJson({
      'api_key': apiKey,
      'proxy': proxy,
      'output_folder': r'C:\private-output',
    }),
    overridePrompt: prompt,
    useOverridePrompt: true,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('workbench export keeps creative state and omits local settings', () {
    final document = WorkbenchDocument.fromPayloadConfig(
      _payload(prompt: 'city rain', apiKey: 'pst-secret', proxy: '127.0.0.1:9'),
    );

    final json = document.toJson();

    expect(json['kind'], WorkbenchDocument.kind);
    expect(json['version'], WorkbenchDocument.currentVersion);
    expect((json['payload'] as Map<String, dynamic>)['settings'], isNull);
    expect(json.toString(), isNot(contains('pst-secret')));
    expect(json.toString(), isNot(contains('private-output')));
    expect(json.toString(), contains('city rain'));
  });

  test('applyTo restores creative state and preserves local settings', () {
    final document = WorkbenchDocument.fromPayloadConfig(
      _payload(prompt: 'imported prompt', apiKey: 'pst-export', proxy: ''),
    );
    final target = _payload(
      prompt: 'current prompt',
      apiKey: 'pst-current',
      proxy: '127.0.0.1:7890',
    );

    document.applyTo(target);

    expect(target.overridePrompt, 'imported prompt');
    expect(target.paramConfig.steps, 33);
    expect(target.settings.apiKey, 'pst-current');
    expect(target.settings.proxy, '127.0.0.1:7890');
  });
}
