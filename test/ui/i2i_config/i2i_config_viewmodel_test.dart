import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/i2i_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/ui/i2i_config/view_models/i2i_config_viewmodel.dart';

void main() {
  test('imports metadata into generation parameters', () {
    final paramConfig = ParamConfig();
    final viewmodel = I2iVibeViewmodel(
      config: I2IConfig(),
      paramConfig: paramConfig,
    );

    final imported = viewmodel.importMetadataParameters({
      'width': 1024,
      'height': 768,
      'scale': 7.5,
      'sampler': 'k_euler',
      'steps': 32,
    });

    expect(imported, 5);
    expect(paramConfig.sizes, const [GenerationSize(width: 1024, height: 768)]);
    expect(paramConfig.scale, 7.5);
    expect(paramConfig.sampler, 'k_euler');
    expect(paramConfig.steps, 32);
  });

  test('sets target size from source image scale options', () {
    final paramConfig = ParamConfig(
      sizes: const [GenerationSize(width: 832, height: 1216)],
    );
    final i2iConfig = I2IConfig()
      ..width = 640
      ..height = 960;
    final viewmodel = I2iVibeViewmodel(
      config: i2iConfig,
      paramConfig: paramConfig,
    );

    final options = viewmodel.getTargetSizeOptions();

    expect(options.first, const GenerationSize(width: 640, height: 960));
    expect(options, contains(const GenerationSize(width: 832, height: 1216)));

    viewmodel.setTargetSize(options.first);

    expect(paramConfig.sizes, [options.first]);
  });

  test('removeImage clears image dimensions and notifies i2i config', () {
    final i2iConfig = I2IConfig(
      imageB64: 'source-image',
      width: 640,
      height: 960,
    );
    final viewmodel = I2iVibeViewmodel(
      config: i2iConfig,
      paramConfig: ParamConfig(),
    );
    var configNotifications = 0;
    i2iConfig.addListener(() => configNotifications++);

    viewmodel.removeImage();

    expect(i2iConfig.imageB64, isNull);
    expect(i2iConfig.width, 0);
    expect(i2iConfig.height, 0);
    expect(configNotifications, 1);
  });

  test('strength and noise changes notify i2i config', () {
    final i2iConfig = I2IConfig();
    final viewmodel = I2iVibeViewmodel(
      config: i2iConfig,
      paramConfig: ParamConfig(),
    );
    var configNotifications = 0;
    i2iConfig.addListener(() => configNotifications++);

    viewmodel.setStrength(0.7);
    viewmodel.setNoise(0.2);

    expect(i2iConfig.strength, 0.7);
    expect(i2iConfig.noise, 0.2);
    expect(configNotifications, 2);
  });

  test('preset updates strength and noise with one i2i config notification',
      () {
    final i2iConfig = I2IConfig();
    final viewmodel = I2iVibeViewmodel(
      config: i2iConfig,
      paramConfig: ParamConfig(),
    );
    var configNotifications = 0;
    i2iConfig.addListener(() => configNotifications++);

    viewmodel.setPreset(5);

    expect(i2iConfig.strength, 0.7);
    expect(i2iConfig.noise, 0.1);
    expect(configNotifications, 1);
  });

  test('override prompt setters notify i2i config', () {
    final i2iConfig = I2IConfig();
    final viewmodel = I2iVibeViewmodel(
      config: i2iConfig,
      paramConfig: ParamConfig(),
    );
    var configNotifications = 0;
    i2iConfig.addListener(() => configNotifications++);

    viewmodel.setOverridePromptEnabled(true);
    viewmodel.setOverridePrompt('line art');

    expect(i2iConfig.overridePromptEnabled, isTrue);
    expect(i2iConfig.overridePrompt, 'line art');
    expect(configNotifications, 2);
  });
}
