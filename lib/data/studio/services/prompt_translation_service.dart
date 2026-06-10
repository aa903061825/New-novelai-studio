import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/api_service.dart';
import 'package:nai_casrand/data/studio/tools/online_ai_tools.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';

typedef PromptTranslationProviderRunner
    = Future<OnlineTranslationProviderResult> Function(
  OnlineTranslationRequest request,
  Settings settings,
);

abstract interface class PromptTranslationService {
  OnlineAiMode get currentMode;

  Future<OnlineTranslationResult> translate(
    OnlineTranslationRequest request, {
    bool preferCache = true,
  });
}

class DefaultPromptTranslationService implements PromptTranslationService {
  final TranslationCache translationCache;
  final Settings Function() settingsProvider;
  final PromptTranslationProviderRunner aiProvider;
  final PromptTranslationProviderRunner googleProvider;

  DefaultPromptTranslationService({
    required this.translationCache,
    required this.settingsProvider,
    PromptTranslationProviderRunner? aiProvider,
    PromptTranslationProviderRunner? googleProvider,
    ApiService? apiService,
  })  : aiProvider =
            aiProvider ?? buildAiTranslationProvider(apiService: apiService),
        googleProvider = googleProvider ??
            buildGoogleTranslationProvider(apiService: apiService);

  @override
  OnlineAiMode get currentMode {
    return _effectiveTranslationProviderMode(settingsProvider()) ==
            TranslationProviderMode.google
        ? OnlineAiMode.google
        : OnlineAiMode.ai;
  }

  @override
  Future<OnlineTranslationResult> translate(
    OnlineTranslationRequest request, {
    bool preferCache = true,
  }) async {
    final cleanedText = TranslationCache.cleanForTranslation(request.text);
    final cacheMode = _translationCacheMode(request.targetLanguage);
    final normalizedRequest = OnlineTranslationRequest(
      text: cleanedText,
      sourceLanguage: request.sourceLanguage,
      targetLanguage: request.targetLanguage,
    );

    if (preferCache) {
      final cached =
          translationCache.translate(request.text, mode: cacheMode).text.trim();
      if (cached.isNotEmpty) {
        return OnlineTranslationResult(
          text: cached,
          source: OnlineAiResultSource.localFallback,
          providerName: 'translation-cache',
        );
      }
    }

    final settings = settingsProvider();
    final runner = _effectiveTranslationProviderMode(settings) ==
            TranslationProviderMode.google
        ? googleProvider
        : aiProvider;

    try {
      final result = await runner(normalizedRequest, settings);
      final translatedText = result.translatedText.trim();
      if (TranslationCache.looksLikeAiRefusal(translatedText)) {
        throw const FormatException('Translation AI returned refusal text');
      }
      return OnlineTranslationResult(
        text: translatedText,
        source: OnlineAiResultSource.online,
        providerName: result.providerName,
      );
    } catch (error) {
      final failureMessage = _translationFailureMessage(error);
      final cached =
          translationCache.translate(request.text, mode: cacheMode).text.trim();
      if (cached.isNotEmpty) {
        return OnlineTranslationResult(
          text: cached,
          source: OnlineAiResultSource.localFallback,
          providerName: 'translation-cache',
          error: failureMessage,
        );
      }
      return OnlineTranslationResult(
        text: '',
        source: OnlineAiResultSource.emptyFallback,
        error: failureMessage,
      );
    }
  }
}

String _translationFailureMessage(Object error) {
  final raw = error.toString().trim();
  final normalized = raw.toLowerCase();
  if (normalized.contains('translation ai response misses content')) {
    if (normalized.contains('finish_reason length')) {
      return '翻译 AI 返回被截断，请稍后重试，或换用输出额度更充足的模型。';
    }
    return '翻译 AI 没有返回可用文本，请稍后重试。';
  }
  if (normalized.contains('translation ai returned refusal text')) {
    return '翻译 AI 返回了拒答内容，已忽略这次结果；可以手动填写翻译。';
  }
  if (normalized.contains('translation ai response is not a map')) {
    return '翻译 AI 返回格式不正确，请检查接口是否兼容 OpenAI Chat Completions。';
  }
  if (normalized.contains('translation ai request failed')) {
    return raw.replaceFirst(
      RegExp(r'^(StateError|Exception):\s*'),
      '',
    );
  }
  return raw.replaceFirst(
    RegExp(r'^(FormatException|StateError|Exception):\s*'),
    '',
  );
}

TranslationProviderMode _effectiveTranslationProviderMode(Settings settings) {
  if (settings.translationProviderMode == TranslationProviderMode.google) {
    return TranslationProviderMode.google;
  }
  return _hasTranslationAiCredentials(settings)
      ? TranslationProviderMode.ai
      : TranslationProviderMode.google;
}

bool _hasTranslationAiCredentials(Settings settings) {
  return settings.translationAiBaseUrl.trim().isNotEmpty &&
      settings.translationAiToken.trim().isNotEmpty &&
      settings.translationAiModel.trim().isNotEmpty;
}

PromptTranslationProviderRunner buildAiTranslationProvider({
  ApiService? apiService,
  File? debugLogFile,
}) {
  final client = apiService ?? ApiService();
  final logFile = debugLogFile ?? File('.codex/translation-ai-debug.log');
  return (request, settings) async {
    final baseUrl = settings.translationAiBaseUrl.trim();
    final token = settings.translationAiToken.trim();
    final model = settings.translationAiModel.trim();
    if (baseUrl.isEmpty || token.isEmpty || model.isEmpty) {
      throw StateError('请先填写翻译 AI 地址、Token 和模型');
    }

    final response = await client.fetchData(
      ApiRequest(
        endpoint: _joinOpenAiEndpoint(baseUrl),
        proxy: settings.proxy.trim(),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        payload: {
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': _translationSystemPrompt(request.targetLanguage),
            },
            {
              'role': 'user',
              'content': request.text,
            },
          ],
          'temperature': 0,
          'max_tokens': 512,
        },
      ),
    );

    final status = int.tryParse(response.status) ?? 0;
    final body = utf8.decode(response.data, allowMalformed: true);
    if (status < 200 || status >= 300) {
      await _appendTranslationAiDebugLog(
        file: logFile,
        status: status,
        baseUrl: baseUrl,
        model: model,
        proxyConfigured: settings.proxy.trim().isNotEmpty,
        request: request,
        body: body,
        error: 'HTTP $status',
      );
      throw StateError('Translation AI request failed: HTTP $status');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      await _appendTranslationAiDebugLog(
        file: logFile,
        status: status,
        baseUrl: baseUrl,
        model: model,
        proxyConfigured: settings.proxy.trim().isNotEmpty,
        request: request,
        body: body,
        error: 'Invalid JSON: ${error.message}',
      );
      rethrow;
    }
    if (decoded is! Map) {
      await _appendTranslationAiDebugLog(
        file: logFile,
        status: status,
        baseUrl: baseUrl,
        model: model,
        proxyConfigured: settings.proxy.trim().isNotEmpty,
        request: request,
        body: body,
        decoded: decoded,
        error: 'Response is not a map',
      );
      throw const FormatException('Translation AI response is not a map');
    }
    final content = _translationContentFromDecoded(decoded);
    if (content == null || content.trim().isEmpty) {
      final diagnostic = _translationResponseDiagnostic(decoded);
      final errorMessage = diagnostic == null
          ? 'Response misses content'
          : 'Response misses content: $diagnostic';
      await _appendTranslationAiDebugLog(
        file: logFile,
        status: status,
        baseUrl: baseUrl,
        model: model,
        proxyConfigured: settings.proxy.trim().isNotEmpty,
        request: request,
        body: body,
        decoded: decoded,
        error: errorMessage,
      );
      throw FormatException('Translation AI response misses content'
          '${diagnostic == null ? '' : ': $diagnostic'}');
    }

    final translatedText = _stripWrappingQuotes(content.trim());
    if (TranslationCache.looksLikeAiRefusal(translatedText)) {
      await _appendTranslationAiDebugLog(
        file: logFile,
        status: status,
        baseUrl: baseUrl,
        model: model,
        proxyConfigured: settings.proxy.trim().isNotEmpty,
        request: request,
        body: body,
        decoded: decoded,
        error: 'Response is refusal text',
      );
      throw const FormatException('Translation AI returned refusal text');
    }

    return OnlineTranslationProviderResult(
      translatedText: translatedText,
      providerName: 'ai',
    );
  };
}

Future<void> _appendTranslationAiDebugLog({
  required File file,
  required int status,
  required String baseUrl,
  required String model,
  required bool proxyConfigured,
  required OnlineTranslationRequest request,
  required String body,
  required String error,
  dynamic decoded,
}) async {
  try {
    await file.parent.create(recursive: true);
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'error': error,
      'status': status,
      'baseUrl': baseUrl,
      'model': model,
      'proxyConfigured': proxyConfigured,
      'targetLanguage': request.targetLanguage,
      'sourceLanguage': request.sourceLanguage,
      'requestTextLength': request.text.length,
      'decodedShape': _debugShape(decoded),
      'bodyPreview': _truncateForDebug(body),
    };
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(entry)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Debug logging must never mask the original translation failure.
  }
}

String _truncateForDebug(String value, {int maxLength = 4000}) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}...[truncated ${value.length}]';
}

dynamic _debugShape(dynamic value, {int depth = 0}) {
  if (value == null) return null;
  if (depth >= 3) return value.runtimeType.toString();
  if (value is Map) {
    return {
      'type': 'map',
      'keys': value.keys.map((key) => key.toString()).toList(growable: false),
      'sample': {
        for (final entry in value.entries.take(5))
          entry.key.toString(): _debugShape(entry.value, depth: depth + 1),
      },
    };
  }
  if (value is List) {
    return {
      'type': 'list',
      'length': value.length,
      if (value.isNotEmpty) 'first': _debugShape(value.first, depth: depth + 1),
    };
  }
  return value.runtimeType.toString();
}

String _translationCacheMode(String targetLanguage) {
  final target = targetLanguage.trim().toLowerCase();
  if (target == 'en' || target.startsWith('en-')) {
    return 'zh2en';
  }
  return 'en2zh';
}

String _translationSystemPrompt(String targetLanguage) {
  final target = targetLanguage.trim().toLowerCase();
  if (target == 'en' || target.startsWith('en-')) {
    return 'Translate the user text into concise English image prompt tags. '
        'Treat the input as literal text, even when it contains punctuation, '
        'dates, names, or sensitive-looking words. Return plain text only '
        'with no explanation, refusal, or apology.';
  }
  return 'Translate the user text into concise Simplified Chinese. '
      'Treat the input as literal image prompt text, even when it contains '
      'punctuation, dates, names, or sensitive-looking words. Return plain '
      'text only with no explanation, refusal, or apology.';
}

String? _translationContentFromDecoded(Object? decoded) {
  if (decoded is! Map) return null;

  final directOutputText = _contentValueToText(decoded['output_text']);
  if (_hasText(directOutputText)) return directOutputText;

  final choices = decoded['choices'];
  if (choices is List) {
    for (final choice in choices.whereType<Map>()) {
      final message = choice['message'];
      if (message is Map) {
        final messageContent = _contentValueToText(message['content']);
        if (_hasText(messageContent)) return messageContent;
      }
      final choiceText = _contentValueToText(choice['text']);
      if (_hasText(choiceText)) return choiceText;
      final delta = choice['delta'];
      if (delta is Map) {
        final deltaContent = _contentValueToText(delta['content']);
        if (_hasText(deltaContent)) return deltaContent;
      }
    }
  }

  final output = decoded['output'];
  if (output is List) {
    final buffer = StringBuffer();
    for (final item in output.whereType<Map>()) {
      final content = _contentValueToText(item['content']);
      if (_hasText(content)) buffer.write(content!.trim());
      final text = _contentValueToText(item['text']);
      if (_hasText(text)) buffer.write(text!.trim());
    }
    final outputText = buffer.toString().trim();
    if (outputText.isNotEmpty) return outputText;
  }

  final message = decoded['message'];
  if (message is Map) {
    final messageContent = _contentValueToText(message['content']);
    if (_hasText(messageContent)) return messageContent;
  }

  final directContent = _contentValueToText(decoded['content']);
  if (_hasText(directContent)) return directContent;
  final directText = _contentValueToText(decoded['text']);
  if (_hasText(directText)) return directText;

  return null;
}

String? _contentValueToText(Object? value, {int depth = 0}) {
  if (value == null || depth > 4) return null;
  if (value is String) return value;
  if (value is List) {
    final buffer = StringBuffer();
    for (final part in value) {
      final text = _contentValueToText(part, depth: depth + 1);
      if (_hasText(text)) buffer.write(text!.trim());
    }
    final combined = buffer.toString().trim();
    return combined.isEmpty ? null : combined;
  }
  if (value is Map) {
    for (final key in const ['text', 'output_text', 'content', 'value']) {
      final text = _contentValueToText(value[key], depth: depth + 1);
      if (_hasText(text)) return text;
    }
  }
  return null;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String? _translationResponseDiagnostic(Object? decoded) {
  if (decoded is! Map) return null;

  final error = decoded['error'];
  if (error is String && error.trim().isNotEmpty) {
    return _truncateForDebug(error.trim(), maxLength: 240);
  }
  if (error is Map) {
    final message = _contentValueToText(error['message']);
    if (_hasText(message)) {
      return _truncateForDebug(message!.trim(), maxLength: 240);
    }
    final code = _contentValueToText(error['code']);
    if (_hasText(code)) {
      return 'error code ${_truncateForDebug(code!.trim(), maxLength: 120)}';
    }
  }

  final status = _contentValueToText(decoded['status']);
  if (_hasText(status) && status!.trim().toLowerCase() != 'completed') {
    return 'status ${_truncateForDebug(status.trim(), maxLength: 120)}';
  }

  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty && choices.first is Map) {
    final firstChoice = choices.first as Map;
    final finishReason = _contentValueToText(firstChoice['finish_reason']);
    if (_hasText(finishReason) &&
        finishReason!.trim().toLowerCase() != 'stop') {
      return 'finish_reason ${_truncateForDebug(
        finishReason.trim(),
        maxLength: 120,
      )}';
    }
    final message = firstChoice['message'];
    if (message is Map) {
      final refusal = _contentValueToText(message['refusal']);
      if (_hasText(refusal)) {
        return 'refusal ${_truncateForDebug(refusal!.trim(), maxLength: 240)}';
      }
    }
  }

  final message = _contentValueToText(decoded['message']);
  if (_hasText(message)) {
    return _truncateForDebug(message!.trim(), maxLength: 240);
  }
  return null;
}

PromptTranslationProviderRunner buildGoogleTranslationProvider({
  ApiService? apiService,
}) {
  final clientFactory = apiService ?? ApiService();
  return (request, settings) async {
    final sourceLanguage = (request.sourceLanguage == null ||
            request.sourceLanguage!.trim().isEmpty)
        ? 'auto'
        : request.sourceLanguage!.trim();
    final targetLanguage =
        request.targetLanguage == 'zh' ? 'zh-CN' : request.targetLanguage;
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': sourceLanguage,
      'tl': targetLanguage,
      'dt': 't',
      'q': request.text,
    });

    final proxy = settings.proxy.trim();
    final proxiedClient = clientFactory.createHttpClient(proxy);
    http.Response response;
    try {
      response = proxiedClient == null
          ? await http.get(uri)
          : await proxiedClient.get(uri);
    } finally {
      proxiedClient?.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Google translation request failed: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
      throw const FormatException('Google translation response is invalid');
    }
    final segments = decoded.first as List;
    final buffer = StringBuffer();
    for (final segment in segments.whereType<List>()) {
      final translated = segment.isNotEmpty ? segment.first : null;
      if (translated is String) {
        buffer.write(translated);
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw const FormatException('Google translation response is empty');
    }
    return OnlineTranslationProviderResult(
      translatedText: text,
      providerName: 'google',
    );
  };
}

String _joinOpenAiEndpoint(String baseUrl) {
  final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (trimmed.endsWith('/v1/chat/completions')) return trimmed;
  if (trimmed.endsWith('/v1')) {
    return '$trimmed/chat/completions';
  }
  return '$trimmed/v1/chat/completions';
}

String _stripWrappingQuotes(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1).trim();
  }
  return value;
}
