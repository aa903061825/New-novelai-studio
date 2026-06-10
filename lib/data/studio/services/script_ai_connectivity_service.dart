import 'dart:convert';

import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/services/api_service.dart';
import 'package:nai_casrand/data/studio/services/script_ai_client.dart';

abstract interface class ScriptAiConnectivityService {
  Future<ScriptAiConnectivityResult> testConnection(
    ScriptAiConnectivityRequest request,
  );
}

class ScriptAiConnectivityRequest {
  final String baseUrl;
  final String token;
  final String model;
  final String proxy;

  const ScriptAiConnectivityRequest({
    required this.baseUrl,
    required this.token,
    required this.model,
    this.proxy = '',
  });
}

class ScriptAiConnectivityResult {
  final bool success;
  final String message;

  const ScriptAiConnectivityResult({
    required this.success,
    required this.message,
  });
}

class DefaultScriptAiConnectivityService
    implements ScriptAiConnectivityService {
  final ScriptAiFetchData fetchData;

  DefaultScriptAiConnectivityService({
    ScriptAiFetchData? fetchData,
    ApiService? apiService,
  }) : fetchData = fetchData ?? (apiService ?? ApiService()).fetchData;

  @override
  Future<ScriptAiConnectivityResult> testConnection(
    ScriptAiConnectivityRequest request,
  ) async {
    try {
      final validationError = _validationError(request);
      if (validationError != null) {
        return ScriptAiConnectivityResult(
          success: false,
          message: validationError,
        );
      }
      final response = await fetchData(
        ApiRequest(
          endpoint: _joinEndpoint(request.baseUrl),
          proxy: request.proxy,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${request.token.trim()}',
          },
          payload: {
            'model': request.model.trim(),
            'messages': const [
              {
                'role': 'system',
                'content': 'Reply with strict JSON only.',
              },
              {
                'role': 'user',
                'content': '{"ping":"script_ai_settings_test"}',
              },
            ],
            'temperature': 0,
            'max_tokens': 16,
          },
        ),
      );

      final status = int.tryParse(response.status) ?? 0;
      final body = utf8.decode(response.data, allowMalformed: true);
      if (status < 200 || status >= 300) {
        return ScriptAiConnectivityResult(
          success: false,
          message: 'HTTP $status${body.trim().isEmpty ? '' : ': $body'}',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['choices'] is! List) {
        return const ScriptAiConnectivityResult(
          success: false,
          message: '响应不是 OpenAI-compatible chat completions 格式',
        );
      }
      final choices = decoded['choices'] as List;
      if (choices.isEmpty) {
        return const ScriptAiConnectivityResult(
          success: false,
          message: '响应 choices 为空',
        );
      }
      return const ScriptAiConnectivityResult(
        success: true,
        message: '连接成功',
      );
    } catch (error) {
      return ScriptAiConnectivityResult(
        success: false,
        message: error.toString(),
      );
    }
  }

  String? _validationError(ScriptAiConnectivityRequest request) {
    if (request.baseUrl.trim().isEmpty) return '剧本 AI 地址为空';
    if (request.token.trim().isEmpty) return '剧本 AI Token 为空';
    if (request.model.trim().isEmpty) return '剧本 AI 模型为空';
    return null;
  }

  String _joinEndpoint(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/v1')) return '$trimmed/chat/completions';
    return '$trimmed/v1/chat/completions';
  }
}
