import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/i2i_config.dart';
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

  test('workbench document round-trips image-to-image config', () {
    final source =
        _payload(prompt: 'city rain', apiKey: 'pst-export', proxy: '')
          ..i2iConfig = I2IConfig(
            imageB64: 'source-image',
            width: 832,
            height: 1216,
            strength: 0.72,
            noise: 0.18,
            overridePromptEnabled: true,
            overridePrompt: 'line art',
          );
    final document = WorkbenchDocument.fromPayloadConfig(source);
    final target = _payload(
      prompt: 'current prompt',
      apiKey: 'pst-current',
      proxy: '',
    );

    document.applyTo(target);

    expect(document.payload['i2i_config'], isA<Map<String, dynamic>>());
    expect(target.i2iConfig.imageB64, 'source-image');
    expect(target.i2iConfig.width, 832);
    expect(target.i2iConfig.height, 1216);
    expect(target.i2iConfig.strength, 0.72);
    expect(target.i2iConfig.noise, 0.18);
    expect(target.i2iConfig.overridePromptEnabled, isTrue);
    expect(target.i2iConfig.overridePrompt, 'line art');
  });

  test('old documents without image-to-image config keep blank state', () {
    final target =
        _payload(prompt: 'current prompt', apiKey: 'pst-current', proxy: '')
          ..i2iConfig = I2IConfig(
            imageB64: 'current-image',
            width: 512,
            height: 768,
            strength: 0.8,
            noise: 0.3,
            overridePromptEnabled: true,
            overridePrompt: 'current i2i prompt',
          );
    final document = WorkbenchDocument.fromJson({
      'kind': WorkbenchDocument.kind,
      'version': WorkbenchDocument.currentVersion,
      'payload': _payload(
        prompt: 'legacy prompt',
        apiKey: 'pst-export',
        proxy: '',
      ).toJson()
        ..remove('i2i_config'),
    });

    document.applyTo(target);

    expect(target.i2iConfig.imageB64, isNull);
    expect(target.i2iConfig.width, 0);
    expect(target.i2iConfig.height, 0);
    expect(target.i2iConfig.strength, 0.5);
    expect(target.i2iConfig.noise, 0);
    expect(target.i2iConfig.overridePromptEnabled, isFalse);
    expect(target.i2iConfig.overridePrompt, isEmpty);
  });
}
