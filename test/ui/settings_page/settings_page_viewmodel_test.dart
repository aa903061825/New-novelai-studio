import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/settings_page/view_models/settings_page_viewmodel.dart';

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton(
      PayloadConfig(
        rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
        characterConfigList: const [],
        savedPromptConfigList: const [],
        paramConfig: ParamConfig(),
        settings: Settings.fromJson({}),
        overridePrompt: '',
        useOverridePrompt: false,
        useCharacterPromptWithOverride: false,
      ),
    );
    GetIt.I.registerSingleton(ConfigService());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('sets batch interval jitter values from numeric input', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('10');
    viewmodel.setBatchIntervalJitterMax('40');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 10);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 40);
  });

  test('clamps negative jitter values to zero', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('-3');
    viewmodel.setBatchIntervalJitterMax('-9');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 0);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 0);
  });

  test('ignores invalid jitter input and keeps existing values', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('10');
    viewmodel.setBatchIntervalJitterMax('40');
    viewmodel.setBatchIntervalJitterMin('abc');
    viewmodel.setBatchIntervalJitterMax('4.5');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 10);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 40);
  });

  test('jitter setters notify listeners after successful updates', () {
    final viewmodel = SettingsPageViewmodel();
    var notificationCount = 0;

    viewmodel.addListener(() {
      notificationCount++;
    });

    viewmodel.setBatchIntervalJitterMin('10');
    viewmodel.setBatchIntervalJitterMax('40');

    expect(notificationCount, 2);
  });

  test('sets retry-on-429 settings from input', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setRetryOn429Enabled(true);
    viewmodel.setRetryOn429DelaySec('15');

    expect(viewmodel.settings.retryOn429Enabled, isTrue);
    expect(viewmodel.settings.retryOn429DelaySec, 15);
  });

  test('retry-on-429 delay ignores invalid input and clamps to at least 1', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setRetryOn429DelaySec('10');
    viewmodel.setRetryOn429DelaySec('abc');
    expect(viewmodel.settings.retryOn429DelaySec, 10);

    viewmodel.setRetryOn429DelaySec('0');
    expect(viewmodel.settings.retryOn429DelaySec, 1);
  });

  test('loadImportedJson preserves current api key', () {
    final viewmodel = SettingsPageViewmodel();
    viewmodel.settings.apiKey = 'current-key';

    viewmodel.loadImportedJson({
      'prompt_config': {
        'selectionMethod': 'single',
        'shuffled': false,
        'prob': 0.0,
        'num': 1,
        'randomBracketsUpper': 0,
        'randomBracketsLower': 0,
        'type': 'str',
        'comment': 'imported',
        'filter': '',
        'strs': ['imported prompt'],
        'prompts': [],
        'enabled': true,
      },
      'character_config': const [],
      'saved_config': const [],
      'param_config': ParamConfig().toJson(),
      'settings': {
        'api_key': 'imported-key',
        'proxy': '127.0.0.1:7890',
      },
    });

    expect(viewmodel.settings.apiKey, 'current-key');
    expect(viewmodel.settings.proxy, '127.0.0.1:7890');
    expect(viewmodel.payloadConfig.rootPromptConfig.comment, 'imported');
  });
}
