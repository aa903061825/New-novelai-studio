import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:nai_casrand/core/constants/settings.dart';

import '../../core/constants/defaults.dart';

const defaultNaiImageGenerationEndpoint =
    'https://image.novelai.net/ai/generate-image';

enum TranslationProviderMode { ai, google }

const scriptAiReasoningEffortOptions = [
  '',
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
];

class Settings {
  // Don't show again
  String welcomeMessageVersion;

  // Display settings
  int generationPageColumnCount;
  String themeMode;
  double uiTextScale;
  double imagePreviewDialogHeight;

  // API key
  String apiKey;

  // Studio AI tools
  String scriptAiBaseUrl;
  String scriptAiToken;
  String scriptAiModel;
  String scriptAiReasoningEffort;
  String translationProvider;
  String translationAiBaseUrl;
  String translationAiToken;
  String translationAiModel;

  // Output dir, for windows only
  String outputFolderPath;

  // Proxy settings
  String proxy;

  // Debug API path
  String debugApiPath;
  bool debugApiEnabled;

  // Image metadata erase
  bool metadataEraseEnabled;
  bool customMetadataEnabled;
  String customMetadataContent;

  // Batch settings
  int batchCount;
  int batchIntervalSec;
  int batchIntervalJitterMinSec;
  int batchIntervalJitterMaxSec;
  bool retryOn429Enabled;
  int retryOn429DelaySec;
  // Number of requests
  int numberOfRequests;

  // File name prefix key
  String fileNamePrefixKey;

  Settings({
    required this.welcomeMessageVersion,
    required this.apiKey,
    this.scriptAiBaseUrl = '',
    this.scriptAiToken = '',
    this.scriptAiModel = '',
    this.scriptAiReasoningEffort = '',
    this.translationProvider = 'ai',
    this.translationAiBaseUrl = '',
    this.translationAiToken = '',
    this.translationAiModel = '',
    required this.outputFolderPath,
    required this.proxy,
    required this.debugApiEnabled,
    required this.debugApiPath,
    required this.metadataEraseEnabled,
    required this.customMetadataEnabled,
    required this.customMetadataContent,
    required this.batchCount,
    required this.batchIntervalSec,
    this.batchIntervalJitterMinSec = 0,
    this.batchIntervalJitterMaxSec = 0,
    this.retryOn429Enabled = false,
    this.retryOn429DelaySec = 10,
    required this.numberOfRequests,
    required this.fileNamePrefixKey,
    required this.generationPageColumnCount,
    required this.themeMode,
    this.uiTextScale = 1.1,
    this.imagePreviewDialogHeight = 760,
  });

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      welcomeMessageVersion: json['welcome_message_version'] ?? '',
      apiKey: json['api_key'] ?? 'pst-abcd',
      scriptAiBaseUrl: json['script_ai_base_url'] ?? '',
      scriptAiToken: json['script_ai_token'] ?? '',
      scriptAiModel: json['script_ai_model'] ?? '',
      scriptAiReasoningEffort: normalizeScriptAiReasoningEffort(
        json['script_ai_reasoning_effort'] as String?,
      ),
      translationProvider: _translationProviderName(
        json['translation_provider'] as String?,
      ),
      translationAiBaseUrl: json['translation_ai_base_url'] ?? '',
      translationAiToken: json['translation_ai_token'] ?? '',
      translationAiModel: json['translation_ai_model'] ?? '',
      outputFolderPath: json['output_folder'] ?? '',
      proxy: json['proxy'] ?? '',
      debugApiEnabled: false,
      debugApiPath: 'http://localhost:5000/ai/generate-image',
      metadataEraseEnabled: json['metadata_erase_enabled'] ?? false,
      customMetadataEnabled: json['custom_metadata_enabled'] ?? false,
      customMetadataContent:
          json['custom_metadata_content'] ?? defaultWatermarkContent,
      batchCount: json['batch_count'] ?? 10,
      batchIntervalSec: json['batch_interval'] ?? 10,
      batchIntervalJitterMinSec: json['batch_interval_jitter_min'] ?? 0,
      batchIntervalJitterMaxSec: json['batch_interval_jitter_max'] ?? 0,
      retryOn429Enabled: json['retry_on_429_enabled'] ?? false,
      retryOn429DelaySec: json['retry_on_429_delay_sec'] ?? 10,
      numberOfRequests: json['number_of_requests'] ?? 0,
      fileNamePrefixKey: json['file_name_prefix_key'] ?? '',
      generationPageColumnCount: json['generation_page_column_count'] ?? 2,
      themeMode: json['theme_mode'] ?? 'system',
      uiTextScale:
          ((json['ui_text_scale'] ?? 1.1) as num).toDouble().clamp(1.0, 1.35),
      imagePreviewDialogHeight:
          ((json['image_preview_dialog_height'] ?? 760) as num)
              .toDouble()
              .clamp(520, 980),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'welcome_message_version': welcomeMessageVersion,
      'api_key': apiKey,
      'script_ai_base_url': scriptAiBaseUrl,
      'script_ai_token': scriptAiToken,
      'script_ai_model': scriptAiModel,
      'script_ai_reasoning_effort': scriptAiReasoningEffort,
      'translation_provider': translationProvider,
      'translation_ai_base_url': translationAiBaseUrl,
      'translation_ai_token': translationAiToken,
      'translation_ai_model': translationAiModel,
      'output_folder': outputFolderPath,
      'proxy': proxy,
      'metadata_erase_enabled': metadataEraseEnabled,
      'custom_metadata_enabled': customMetadataEnabled,
      'custom_metadata_content': customMetadataContent,
      'batch_count': batchCount,
      'batch_interval': batchIntervalSec,
      'batch_interval_jitter_min': batchIntervalJitterMinSec,
      'batch_interval_jitter_max': batchIntervalJitterMaxSec,
      'retry_on_429_enabled': retryOn429Enabled,
      'retry_on_429_delay_sec': retryOn429DelaySec,
      'file_name_prefix_key': fileNamePrefixKey,
      'number_of_requests': numberOfRequests,
      'generation_page_column_count': generationPageColumnCount,
      'theme_mode': themeMode,
      'ui_text_scale': uiTextScale,
      'image_preview_dialog_height': imagePreviewDialogHeight,
    };
  }

  AdaptiveThemeMode get theme =>
      stringToThemeMode[themeMode] ?? AdaptiveThemeMode.system;

  String get imageGenerationEndpoint {
    if (debugApiEnabled) {
      return debugApiPath;
    }
    return defaultNaiImageGenerationEndpoint;
  }

  TranslationProviderMode get translationProviderMode =>
      translationProvider == TranslationProviderMode.google.name
          ? TranslationProviderMode.google
          : TranslationProviderMode.ai;
}

String _translationProviderName(String? value) {
  return value == TranslationProviderMode.google.name
      ? TranslationProviderMode.google.name
      : TranslationProviderMode.ai.name;
}

String normalizeScriptAiReasoningEffort(String? value) {
  final normalized = value?.trim() ?? '';
  return scriptAiReasoningEffortOptions.contains(normalized) ? normalized : '';
}
