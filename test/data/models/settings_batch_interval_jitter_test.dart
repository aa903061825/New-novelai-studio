import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/settings.dart';

void main() {
  test('settings constructor keeps jitter defaults compatible', () {
    final settings = Settings(
      welcomeMessageVersion: '',
      apiKey: 'test-key',
      outputFolderPath: '',
      proxy: '',
      debugApiEnabled: false,
      debugApiPath: 'http://localhost',
      metadataEraseEnabled: false,
      customMetadataEnabled: false,
      customMetadataContent: '',
      batchCount: 1,
      batchIntervalSec: 10,
      numberOfRequests: 0,
      fileNamePrefixKey: '',
      generationPageColumnCount: 2,
      themeMode: 'system',
    );

    expect(settings.batchIntervalJitterMinSec, 0);
    expect(settings.batchIntervalJitterMaxSec, 0);
  });

  test('settings defaults batch interval jitter values to zero', () {
    final settings = Settings.fromJson({});

    expect(settings.batchIntervalJitterMinSec, 0);
    expect(settings.batchIntervalJitterMaxSec, 0);
  });

  test('settings persists batch interval jitter values in json', () {
    final settings = Settings.fromJson({
      'batch_interval': 30,
      'batch_interval_jitter_min': 10,
      'batch_interval_jitter_max': 40,
    });

    final json = settings.toJson();

    expect(settings.batchIntervalJitterMinSec, 10);
    expect(settings.batchIntervalJitterMaxSec, 40);
    expect(json['batch_interval_jitter_min'], 10);
    expect(json['batch_interval_jitter_max'], 40);
  });

  test('settings defaults 429 retry fields correctly', () {
    final settings = Settings.fromJson({});

    expect(settings.retryOn429Enabled, isFalse);
    expect(settings.retryOn429DelaySec, 10);
  });

  test('settings persists 429 retry fields in json', () {
    final settings = Settings.fromJson({
      'retry_on_429_enabled': true,
      'retry_on_429_delay_sec': 15,
    });

    final json = settings.toJson();

    expect(settings.retryOn429Enabled, isTrue);
    expect(settings.retryOn429DelaySec, 15);
    expect(json['retry_on_429_enabled'], isTrue);
    expect(json['retry_on_429_delay_sec'], 15);
  });

  test('settings persists script and translation ai credentials', () {
    final settings = Settings.fromJson({
      'script_ai_base_url': 'https://script.example/v1',
      'script_ai_token': 'script-token',
      'translation_ai_base_url': 'https://translate.example/v1',
      'translation_ai_token': 'translation-token',
      'translation_ai_model': 'gpt-4.1-mini',
    });

    final json = settings.toJson();

    expect(settings.scriptAiBaseUrl, 'https://script.example/v1');
    expect(settings.scriptAiToken, 'script-token');
    expect(settings.translationAiBaseUrl, 'https://translate.example/v1');
    expect(settings.translationAiToken, 'translation-token');
    expect(settings.translationAiModel, 'gpt-4.1-mini');
    expect(json['script_ai_base_url'], 'https://script.example/v1');
    expect(json['script_ai_token'], 'script-token');
    expect(json['translation_ai_base_url'], 'https://translate.example/v1');
    expect(json['translation_ai_token'], 'translation-token');
    expect(json['translation_ai_model'], 'gpt-4.1-mini');
  });

  test('settings persists script ai model', () {
    final settings = Settings.fromJson({
      'script_ai_base_url': 'https://script.example/v1',
      'script_ai_token': 'script-token',
      'script_ai_model': 'gpt-4.1-mini',
    });

    final json = settings.toJson();

    expect(settings.scriptAiModel, 'gpt-4.1-mini');
    expect(json['script_ai_model'], 'gpt-4.1-mini');
  });

  test('settings persists script ai reasoning effort', () {
    for (final effort in [
      'none',
      'minimal',
      'low',
      'medium',
      'high',
      'xhigh'
    ]) {
      final settings = Settings.fromJson({
        'script_ai_reasoning_effort': ' $effort ',
      });

      final json = settings.toJson();

      expect(settings.scriptAiReasoningEffort, effort);
      expect(json['script_ai_reasoning_effort'], effort);
    }
  });

  test('settings ignores unsupported script ai reasoning effort values', () {
    final settings = Settings.fromJson({
      'script_ai_reasoning_effort': 'ultra',
    });

    expect(settings.scriptAiReasoningEffort, '');
    expect(settings.toJson()['script_ai_reasoning_effort'], '');
  });

  test('settings always uses the official NovelAI image endpoint', () {
    final settings = Settings.fromJson({
      'nai_api_endpoint': 'https://proxy.example/ai/generate-image',
    });

    final json = settings.toJson();

    expect(settings.imageGenerationEndpoint,
        'https://image.novelai.net/ai/generate-image');
    expect(json.containsKey('nai_api_endpoint'), isFalse);
  });

  test('settings persists translation provider selection', () {
    final settings = Settings.fromJson({
      'translation_provider': 'google',
    });

    final json = settings.toJson();

    expect(settings.translationProvider, 'google');
    expect(json['translation_provider'], 'google');
  });

  test('settings persists shared image preview dialog height', () {
    final settings = Settings.fromJson({
      'image_preview_dialog_height': 730.0,
    });

    final json = settings.toJson();

    expect(settings.imagePreviewDialogHeight, 730.0);
    expect(json['image_preview_dialog_height'], 730.0);
  });
}
