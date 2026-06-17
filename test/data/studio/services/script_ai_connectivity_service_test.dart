import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/studio/services/script_ai_connectivity_service.dart';

void main() {
  test('posts a minimal chat completion to test script ai connectivity',
      () async {
    ApiRequest? captured;
    final service = DefaultScriptAiConnectivityService(
      fetchData: (request) async {
        captured = request;
        return ApiResponse(
          status: '200',
          data: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '{"ok":true}'},
                  },
                ],
              }),
            ),
          ),
        );
      },
    );

    final result = await service.testConnection(
      const ScriptAiConnectivityRequest(
        baseUrl: 'https://script.example/v1',
        token: 'secret',
        model: 'gpt-4.1-mini',
        proxy: '127.0.0.1:7890',
      ),
    );

    expect(result.success, isTrue);
    expect(captured?.endpoint, 'https://script.example/v1/chat/completions');
    expect(captured?.proxy, '127.0.0.1:7890');
    expect(captured?.headers['Authorization'], 'Bearer secret');
    expect(captured?.payload['model'], 'gpt-4.1-mini');
    expect(captured?.payload['messages'], isA<List>());
  });

  test('returns a failure result for http errors', () async {
    final service = DefaultScriptAiConnectivityService(
      fetchData: (_) async => ApiResponse(
        status: '401',
        data: Uint8List.fromList(utf8.encode('bad token')),
      ),
    );

    final result = await service.testConnection(
      const ScriptAiConnectivityRequest(
        baseUrl: 'https://script.example/v1',
        token: 'wrong',
        model: 'gpt-4.1-mini',
      ),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('HTTP 401'));
  });
}
