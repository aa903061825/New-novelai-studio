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
}
