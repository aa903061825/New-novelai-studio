import 'dart:convert';

import 'package:novel_studio/data/models/api_request.dart';

typedef ScriptAiChatExceptionFactory = Exception Function(String message);

class ScriptAiOpenAiChatContent {
  final String rawJson;
  final String reasoningContent;

  const ScriptAiOpenAiChatContent({
    required this.rawJson,
    this.reasoningContent = '',
  });
}

class ScriptAiOpenAiChatClient {
  const ScriptAiOpenAiChatClient();

  void validateConfig({
    required String baseUrl,
    required String token,
    required String model,
    required String label,
    required ScriptAiChatExceptionFactory createException,
  }) {
    if (baseUrl.trim().isEmpty) {
      throw createException('$label base URL is empty.');
    }
    if (token.trim().isEmpty) {
      throw createException('$label token is empty.');
    }
    if (model.trim().isEmpty) {
      throw createException('$label model is empty.');
    }
  }

  String chatCompletionsEndpoint(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/v1/chat/completions')) return trimmed;
    if (trimmed.endsWith('/v1')) return '$trimmed/chat/completions';
    return '$trimmed/v1/chat/completions';
  }

  void ensureSuccess({
    required ApiResponse response,
    required String label,
    required ScriptAiChatExceptionFactory createException,
  }) {
    final status = int.tryParse(response.status) ?? 0;
    if (status < 200 || status >= 300) {
      throw createException('$label request failed: HTTP $status');
    }
  }

  ScriptAiOpenAiChatContent contentFromResponse({
    required ApiResponse response,
    required String label,
    required ScriptAiChatExceptionFactory createException,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.data));
    } on FormatException catch (error) {
      throw createException(
        '$label response is malformed JSON: ${error.message}.',
      );
    }

    if (decoded is! Map) {
      throw createException('$label response is not a map.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw createException('$label response misses choices.');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map || message['content'] is! String) {
      throw createException('$label response misses content.');
    }
    return ScriptAiOpenAiChatContent(
      rawJson: message['content'] as String,
      reasoningContent: message['reasoning_content'] is String
          ? message['reasoning_content'] as String
          : '',
    );
  }
}
