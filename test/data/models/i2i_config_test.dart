import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/i2i_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';

PayloadConfig _payloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const ['prompt'], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson(const {}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('round-trips image-to-image config through json', () {
    final config = I2IConfig(
      imageB64: 'source-image',
      width: 832,
      height: 1216,
      strength: 0.72,
      noise: 0.18,
      overridePromptEnabled: true,
      overridePrompt: 'line art, clean edges',
    );

    final restored = I2IConfig.fromJson(config.toJson());

    expect(restored.imageB64, 'source-image');
    expect(restored.width, 832);
    expect(restored.height, 1216);
    expect(restored.strength, 0.72);
    expect(restored.noise, 0.18);
    expect(restored.overridePromptEnabled, isTrue);
    expect(restored.overridePrompt, 'line art, clean edges');
  });

  test('loadJson replaces current state with serialized values', () {
    final config = I2IConfig(
      imageB64: 'old-image',
      width: 64,
      height: 64,
      strength: 0.1,
      noise: 0.2,
      overridePromptEnabled: true,
      overridePrompt: 'old prompt',
    );
    var notificationCount = 0;
    config.addListener(() => notificationCount++);

    config.loadJson({
      'image_b64': 'new-image',
      'width': 512,
      'height': 768,
      'strength': 0.6,
      'noise': 0.05,
      'override_prompt_enabled': false,
      'override_prompt': 'ignored prompt',
    });

    expect(config.imageB64, 'new-image');
    expect(config.width, 512);
    expect(config.height, 768);
    expect(config.strength, 0.6);
    expect(config.noise, 0.05);
    expect(config.overridePromptEnabled, isFalse);
    expect(config.overridePrompt, 'ignored prompt');
    expect(notificationCount, 1);
  });

  test('fromJson uses blank defaults for missing values', () {
    final config = I2IConfig.fromJson(const {});

    expect(config.imageB64, isNull);
    expect(config.width, 0);
    expect(config.height, 0);
    expect(config.strength, 0.5);
    expect(config.noise, 0);
    expect(config.overridePromptEnabled, isFalse);
    expect(config.overridePrompt, isEmpty);
  });

  test('getConfigResult only sends non-empty enabled override prompt', () {
    final disabled = I2IConfig(
      imageB64: 'source-image',
      overridePromptEnabled: false,
      overridePrompt: 'line art',
    );
    final empty = I2IConfig(
      imageB64: 'source-image',
      overridePromptEnabled: true,
      overridePrompt: '   ',
    );
    final enabled = I2IConfig(
      imageB64: 'source-image',
      overridePromptEnabled: true,
      overridePrompt: ' line art ',
    );

    expect(disabled.getConfigResult().overridePrompts, isNull);
    expect(empty.getConfigResult().overridePrompts, isNull);
    expect(enabled.getConfigResult().overridePrompts, 'line art');
  });

  test('payload loadJson preserves i2i config identity and notifies listener',
      () {
    final payload = _payloadConfig();
    final originalI2iConfig = payload.i2iConfig;
    var notificationCount = 0;
    originalI2iConfig.addListener(() => notificationCount++);

    payload.loadJson({
      ...payload.toJson(),
      'i2i_config': {
        'image_b64': 'loaded-image',
        'width': 704,
        'height': 1024,
        'strength': 0.64,
        'noise': 0.09,
        'override_prompt_enabled': true,
        'override_prompt': 'loaded override',
      },
    });

    expect(identical(payload.i2iConfig, originalI2iConfig), isTrue);
    expect(notificationCount, 1);
    expect(payload.i2iConfig.imageB64, 'loaded-image');
    expect(payload.i2iConfig.width, 704);
    expect(payload.i2iConfig.height, 1024);
    expect(payload.i2iConfig.strength, 0.64);
    expect(payload.i2iConfig.noise, 0.09);
    expect(payload.i2iConfig.overridePromptEnabled, isTrue);
    expect(payload.i2iConfig.overridePrompt, 'loaded override');
  });
}
