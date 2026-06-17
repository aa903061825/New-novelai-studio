import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/services/api_service.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';

void main() {
  TranslationCache buildCache() => TranslationCache(clock: () => 1710000000);

  test('uses cached translation before the selected provider', () async {
    final cache = buildCache()..setManual('blue eyes', 'cached-eyes');
    var googleCalls = 0;
    final service = DefaultPromptTranslationService(
      translationCache: cache,
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'google',
      }),
      googleProvider: (request, settings) async {
        googleCalls += 1;
        return const OnlineTranslationProviderResult(
          translatedText: 'network-eyes',
          providerName: 'google',
        );
      },
      aiProvider: (request, settings) async {
        throw StateError('AI provider should not run');
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(text: 'blue eyes', targetLanguage: 'zh'),
    );

    expect(result.text, 'cached-eyes');
    expect(result.source, OnlineAiResultSource.localFallback);
    expect(result.providerName, 'translation-cache');
    expect(googleCalls, 0);
  });

  test('reloads disk cache before provider when in-memory cache misses',
      () async {
    final cache = buildCache();
    final refreshedCache = buildCache()
      ..setCached('green_eyes', 'cached-green', source: 'ai');
    var reloadCalls = 0;
    var googleCalls = 0;
    final service = DefaultPromptTranslationService(
      translationCache: cache,
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'google',
      }),
      translationCacheReloader: () async {
        reloadCalls += 1;
        return refreshedCache;
      },
      googleProvider: (request, settings) async {
        googleCalls += 1;
        return const OnlineTranslationProviderResult(
          translatedText: 'network-green',
          providerName: 'google',
        );
      },
      aiProvider: (request, settings) async {
        throw StateError('AI provider should not run');
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(text: 'green_eyes', targetLanguage: 'zh'),
    );

    expect(result.text, 'cached-green');
    expect(result.source, OnlineAiResultSource.localFallback);
    expect(result.providerName, 'translation-cache');
    expect(reloadCalls, 1);
    expect(googleCalls, 0);
    expect(cache.getCached('green_eyes'), 'cached-green');
  });

  test('forced retranslate reports provider failure instead of cached fallback',
      () async {
    final cache = buildCache()
      ..setCached('green_eyes', 'cached-green', source: 'ai');
    var googleCalls = 0;
    final service = DefaultPromptTranslationService(
      translationCache: cache,
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'google',
      }),
      googleProvider: (request, settings) async {
        googleCalls += 1;
        throw StateError('network unavailable');
      },
      aiProvider: (request, settings) async {
        throw StateError('AI provider should not run');
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(text: 'green_eyes', targetLanguage: 'zh'),
      preferCache: false,
    );

    expect(googleCalls, 1);
    expect(result.text, isEmpty);
    expect(result.source, OnlineAiResultSource.emptyFallback);
    expect(result.providerName, isNull);
    expect(result.error, contains('network unavailable'));
  });

  test('uses reverse cache hit for Chinese input before provider', () async {
    final cache = buildCache()..setManual('blue eyes', '\u84dd\u773c\u775b');
    var googleCalls = 0;
    final service = DefaultPromptTranslationService(
      translationCache: cache,
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'google',
      }),
      googleProvider: (request, settings) async {
        googleCalls += 1;
        return const OnlineTranslationProviderResult(
          translatedText: 'network-blue-eyes',
          providerName: 'google',
        );
      },
      aiProvider: (request, settings) async {
        throw StateError('AI provider should not run');
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(
        text: '\u84dd\u773c\u775b',
        sourceLanguage: 'zh',
        targetLanguage: 'en',
      ),
    );

    expect(result.text, 'blue eyes');
    expect(result.source, OnlineAiResultSource.localFallback);
    expect(result.providerName, 'translation-cache');
    expect(googleCalls, 0);
  });

  test('uses the selected google provider when cache misses', () async {
    final service = DefaultPromptTranslationService(
      translationCache: buildCache(),
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'google',
      }),
      googleProvider: (request, settings) async {
        expect(settings.translationProvider, 'google');
        expect(request.text, 'dress');
        return const OnlineTranslationProviderResult(
          translatedText: 'google-dress',
          providerName: 'google',
        );
      },
      aiProvider: (request, settings) async {
        throw StateError('AI provider should not run');
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(text: 'dress', targetLanguage: 'zh'),
      preferCache: false,
    );

    expect(result.text, 'google-dress');
    expect(result.source, OnlineAiResultSource.online);
    expect(result.providerName, 'google');
  });

  test('uses the selected AI provider when cache misses', () async {
    final service = DefaultPromptTranslationService(
      translationCache: buildCache(),
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'ai',
        'translation_ai_base_url': 'https://translate.example/v1',
        'translation_ai_token': 'token',
        'translation_ai_model': 'gpt-4.1-mini',
      }),
      googleProvider: (request, settings) async {
        throw StateError('Google provider should not run');
      },
      aiProvider: (request, settings) async {
        expect(settings.translationProvider, 'ai');
        expect(settings.translationAiModel, 'gpt-4.1-mini');
        expect(request.text, 'cape');
        return const OnlineTranslationProviderResult(
          translatedText: 'ai-cape',
          providerName: 'ai',
        );
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(text: 'cape', targetLanguage: 'zh'),
      preferCache: false,
    );

    expect(result.text, 'ai-cape');
    expect(result.source, OnlineAiResultSource.online);
    expect(result.providerName, 'ai');
  });

  test('falls back to google when AI translation is not configured', () async {
    var googleCalls = 0;
    final service = DefaultPromptTranslationService(
      translationCache: buildCache(),
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'ai',
      }),
      googleProvider: (request, settings) async {
        googleCalls += 1;
        expect(request.text, 'silver hair');
        return const OnlineTranslationProviderResult(
          translatedText: 'google-silver-hair',
          providerName: 'google',
        );
      },
      aiProvider: (request, settings) async {
        throw StateError('AI provider should not run without credentials');
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(text: 'silver hair', targetLanguage: 'zh'),
      preferCache: false,
    );

    expect(result.text, 'google-silver-hair');
    expect(result.source, OnlineAiResultSource.online);
    expect(result.providerName, 'google');
    expect(googleCalls, 1);
  });

  test('AI provider asks for English when target language is English',
      () async {
    final apiService = _CapturingApiService('red eyes');
    final provider = buildAiTranslationProvider(apiService: apiService);

    final result = await provider(
      const OnlineTranslationRequest(
        text: '\u7ea2\u773c',
        sourceLanguage: 'zh',
        targetLanguage: 'en',
      ),
      Settings.fromJson({
        'translation_ai_base_url': 'https://translate.example/v1',
        'translation_ai_token': 'token',
        'translation_ai_model': 'gpt-4.1-mini',
      }),
    );

    final payload = apiService.lastRequest!.payload;
    final messages = payload['messages'] as List;
    final systemMessage = messages.first as Map;
    expect(systemMessage['content'], contains('English'));
    expect(systemMessage['content'], isNot(contains('Simplified Chinese')));
    expect(payload['max_tokens'], greaterThanOrEqualTo(512));
    expect(result.translatedText, 'red eyes');
  });

  test('translation service hides raw truncated AI diagnostics', () async {
    final service = DefaultPromptTranslationService(
      translationCache: buildCache(),
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'ai',
        'translation_ai_base_url': 'https://translate.example/v1',
        'translation_ai_token': 'token',
        'translation_ai_model': 'gpt-4.1-mini',
      }),
      googleProvider: (request, settings) async {
        throw StateError('Google provider should not run');
      },
      aiProvider: (request, settings) async {
        throw const FormatException(
          'Translation AI response misses content: finish_reason length',
        );
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(
        text: 'truncated synthetic tag',
        targetLanguage: 'zh',
      ),
      preferCache: false,
    );

    expect(result.text, isEmpty);
    expect(result.source, OnlineAiResultSource.emptyFallback);
    expect(result.error, contains('翻译 AI 返回被截断'));
    expect(result.error, isNot(contains('FormatException')));
    expect(result.error, isNot(contains('finish_reason')));
  });

  test('translation service rejects AI refusal text as an empty fallback',
      () async {
    final service = DefaultPromptTranslationService(
      translationCache: buildCache(),
      settingsProvider: () => Settings.fromJson({
        'translation_provider': 'ai',
        'translation_ai_base_url': 'https://translate.example/v1',
        'translation_ai_token': 'token',
        'translation_ai_model': 'gpt-4.1-mini',
      }),
      googleProvider: (request, settings) async {
        throw StateError('Google provider should not run');
      },
      aiProvider: (request, settings) async {
        return const OnlineTranslationProviderResult(
          translatedText: '抱歉，我无法回答这个问题，请提出其他合规的问题',
          providerName: 'ai',
        );
      },
    );

    final result = await service.translate(
      const OnlineTranslationRequest(
        text: '(sincos)(year 2025)',
        targetLanguage: 'zh',
      ),
      preferCache: false,
    );

    expect(result.text, isEmpty);
    expect(result.source, OnlineAiResultSource.emptyFallback);
    expect(result.error, contains('翻译 AI 返回了拒答内容'));
  });

  test('AI provider logs redacted diagnostics when content is missing',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'translation-ai-debug-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final logFile = File('${tempDir.path}/translation-ai-debug.log');
    final apiService = _CapturingApiService.fromBody(
      jsonEncode({
        'choices': [
          {'message': {}},
        ],
      }),
    );
    final provider = buildAiTranslationProvider(
      apiService: apiService,
      debugLogFile: logFile,
    );

    await expectLater(
      provider(
        const OnlineTranslationRequest(
          text: 'covered pussy',
          targetLanguage: 'zh',
        ),
        Settings.fromJson({
          'translation_ai_base_url': 'https://translate.example/v1',
          'translation_ai_token': 'secret-token',
          'translation_ai_model': 'gpt-4.1-mini',
        }),
      ),
      throwsFormatException,
    );

    final log = await logFile.readAsString();
    expect(log, contains('Response misses content'));
    expect(log, contains('gpt-4.1-mini'));
    expect(log, contains('requestTextLength'));
    expect(log, contains('bodyPreview'));
    expect(log, isNot(contains('secret-token')));
  });

  test('AI provider rejects refusal content from chat completions', () async {
    final apiService = _CapturingApiService.fromBody(
      jsonEncode({
        'choices': [
          {
            'message': {
              'content': '抱歉，我无法回答这个问题，请提出其他合规的问题',
            },
          },
        ],
      }),
    );
    final provider = buildAiTranslationProvider(apiService: apiService);

    await expectLater(
      provider(
        const OnlineTranslationRequest(
          text: '(sincos)(year 2025)',
          targetLanguage: 'zh',
        ),
        Settings.fromJson({
          'translation_ai_base_url': 'https://translate.example/v1',
          'translation_ai_token': 'token',
          'translation_ai_model': 'gpt-4.1-mini',
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('refusal'),
        ),
      ),
    );
  });

  test('AI provider accepts chat completion content parts', () async {
    final apiService = _CapturingApiService.fromBody(
      jsonEncode({
        'choices': [
          {
            'message': {
              'content': [
                {'type': 'text', 'text': '\u84dd\u773c\u775b'},
              ],
            },
          },
        ],
      }),
    );
    final provider = buildAiTranslationProvider(apiService: apiService);

    final result = await provider(
      const OnlineTranslationRequest(
        text: 'blue eyes',
        targetLanguage: 'zh',
      ),
      Settings.fromJson({
        'translation_ai_base_url': 'https://translate.example/v1',
        'translation_ai_token': 'token',
        'translation_ai_model': 'gpt-4.1-mini',
      }),
    );

    expect(result.translatedText, '\u84dd\u773c\u775b');
  });

  test('AI provider accepts responses output text', () async {
    final apiService = _CapturingApiService.fromBody(
      jsonEncode({
        'output_text': '\u7ea2\u773c',
      }),
    );
    final provider = buildAiTranslationProvider(apiService: apiService);

    final result = await provider(
      const OnlineTranslationRequest(
        text: 'red eyes',
        targetLanguage: 'zh',
      ),
      Settings.fromJson({
        'translation_ai_base_url': 'https://translate.example/v1',
        'translation_ai_token': 'token',
        'translation_ai_model': 'gpt-4.1-mini',
      }),
    );

    expect(result.translatedText, '\u7ea2\u773c');
  });

  test('AI provider surfaces success-status error bodies', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'translation-ai-error-body-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final apiService = _CapturingApiService.fromBody(
      jsonEncode({
        'error': {'message': 'upstream overloaded'},
      }),
    );
    final provider = buildAiTranslationProvider(
      apiService: apiService,
      debugLogFile: File('${tempDir.path}/translation-ai-debug.log'),
    );

    await expectLater(
      provider(
        const OnlineTranslationRequest(
          text: 'blue eyes',
          targetLanguage: 'zh',
        ),
        Settings.fromJson({
          'translation_ai_base_url': 'https://translate.example/v1',
          'translation_ai_token': 'token',
          'translation_ai_model': 'gpt-4.1-mini',
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('upstream overloaded'),
        ),
      ),
    );
  });
}

class _CapturingApiService extends ApiService {
  final String translatedText;
  final String? responseBody;
  ApiRequest? lastRequest;

  _CapturingApiService(this.translatedText) : responseBody = null;

  _CapturingApiService.fromBody(this.responseBody) : translatedText = '';

  @override
  Future<ApiResponse> fetchData(ApiRequest request) async {
    lastRequest = request;
    return ApiResponse(
      status: '200',
      data: Uint8List.fromList(
        utf8.encode(
          responseBody ??
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': translatedText},
                  },
                ],
              }),
        ),
      ),
    );
  }
}
