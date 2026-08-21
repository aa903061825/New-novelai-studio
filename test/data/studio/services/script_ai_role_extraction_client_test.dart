import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_client.dart';

void main() {
  test('openai-compatible role extraction client posts JSON mode request',
      () async {
    ApiRequest? captured;
    final client = OpenAiCompatibleScriptAiRoleExtractionClient(
      fetchData: (request) async {
        captured = request;
        return ApiResponse(
          status: '200',
          data: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'reasoning_content': 'I inspect the slot evidence first.',
                      'content': '{"schema_version":1,"roles":[]}',
                    },
                  },
                ],
              }),
            ),
          ),
        );
      },
    );

    final result = await client.extractRoles(
      const ScriptAiRoleExtractionClientRequest(
        baseUrl: 'https://script.example/v1',
        token: 'secret',
        model: 'gpt-4.1-mini',
        proxy: '127.0.0.1:7890',
        requestJson: {
          'schema_version': 1,
          'request_kind': 'chunk_extract_v2',
        },
      ),
    );

    expect(result.rawJson, contains('"schema_version":1'));
    expect(result.reasoningContent, 'I inspect the slot evidence first.');
    expect(captured?.endpoint, 'https://script.example/v1/chat/completions');
    expect(captured?.proxy, '127.0.0.1:7890');
    expect(captured?.timeout, const Duration(minutes: 5));
    expect(captured?.logLabel, 'script-ai-role-extraction');
    expect(captured?.headers['Authorization'], 'Bearer secret');
    expect(captured?.headers['Content-Type'], 'application/json');
    expect(captured?.payload['model'], 'gpt-4.1-mini');
    expect(captured?.payload['response_format'], {'type': 'json_object'});
    expect(captured?.payload.containsKey('reasoning_effort'), isFalse);

    final messages = (captured?.payload['messages'] as List).cast<Map>();
    expect(messages.first['role'], 'system');
    final systemPrompt = messages.first['content'] as String;
    expect(systemPrompt, contains('Script AI role extraction engine'));
    expect(systemPrompt, contains('chunk_extract_v2'));
    expect(systemPrompt, contains('timeline_segments'));
    expect(systemPrompt, contains('needs_more_evidence'));
    expect(systemPrompt, contains('evidence_followup'));
    expect(systemPrompt, contains('Request only frame/source evidence'));
    expect(systemPrompt, contains('never file paths'));
    expect(systemPrompt, contains('strong_filter_keywords'));
    expect(systemPrompt, contains('official art'));
    expect(systemPrompt, contains('Output every stage label in Chinese'));
    expect(systemPrompt, contains('replacement table contract'));
    expect(systemPrompt, contains('source_terms is the complete'));
    expect(systemPrompt, contains('term_cache_suggestions'));
    expect(
        systemPrompt, contains('Only suggest translations or classifications'));
    expect(systemPrompt, contains('replace, merge, delete, or leave empty'));
    expect(systemPrompt, contains('Do not hard-filter role-scoped source'));
    expect(systemPrompt, contains('User filter/block rules'));
    expect(systemPrompt, contains('inverted nipples'));
    expect(systemPrompt, contains('large breasts'));
    expect(systemPrompt, contains('upperBody'));
    expect(systemPrompt, contains('accessory'));
    expect(systemPrompt, contains('clothingState'));
    expect(systemPrompt, contains('Use other for role-scoped source terms'));
    expect(systemPrompt, contains('replacement-relevant clothingState'));
    expect(systemPrompt, contains('no panties'));
    expect(systemPrompt, contains('strap slip'));
    expect(systemPrompt, contains('bottomless'));
    expect(systemPrompt, contains('bikini aside'));
    expect(systemPrompt, contains('1girl, 2girls, 1boy, solo'));
    expect(systemPrompt, contains('girl is not the same source term as 1girl'));
    expect(systemPrompt, contains('natural-language source phrases'));
    expect(systemPrompt, contains('Do not force state variants'));
    expect(
        systemPrompt,
        contains(
            'keep state-specific source terms in prompt_terms as clothingState'));
    expect(systemPrompt, isNot(contains('role-local uncertain candidate')));
    expect(
      systemPrompt,
      isNot(
        contains('Do not split separate outfit slots for state variants'),
      ),
    );
    expect(
      systemPrompt,
      isNot(contains('combine their terms into the same five fields')),
    );
    expect(
      systemPrompt,
      isNot(
        contains('identity, body, clothing, clothing_state, accessory'),
      ),
    );
    expect(systemPrompt, isNot(contains('"non_role"')));
    expect(systemPrompt, contains('appearance_group_id'));
    expect(systemPrompt, contains('merge_with_stage_ids'));
    expect(systemPrompt, contains('field_reasons'));
    expect(systemPrompt, contains('canonical_name'));
    expect(systemPrompt, contains('franchise'));
    expect(systemPrompt, contains('raw_identity_tags'));
    expect(systemPrompt, contains('variant_tags'));
    expect(systemPrompt, contains('merge_with_role_id'));
    expect(systemPrompt, contains('official costume variants'));
    expect(systemPrompt, contains('why each stable term belongs'));
    expect(systemPrompt, contains('which stages should be merged'));
    expect(systemPrompt, contains('Do not put another role'));
    expect(systemPrompt, contains('ako (dress) (blue archive)'));
    expect(systemPrompt, contains('stomach bulge'));
    expect(systemPrompt, contains('thighs'));
    expect(systemPrompt, contains('spread legs'));
    expect(systemPrompt, contains('马赛克'));
    expect(systemPrompt, contains('审查'));
    expect(systemPrompt.toLowerCase(), isNot(contains('asset catalog')));
    expect(messages.last['role'], 'user');
    expect(jsonDecode(messages.last['content'] as String), {
      'schema_version': 1,
      'request_kind': 'chunk_extract_v2',
    });
  });

  test('role extraction client sends configured reasoning effort', () async {
    ApiRequest? captured;
    final client = OpenAiCompatibleScriptAiRoleExtractionClient(
      fetchData: (request) async {
        captured = request;
        return ApiResponse(
          status: '200',
          data: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '{}'},
                  },
                ],
              }),
            ),
          ),
        );
      },
    );

    await client.extractRoles(
      const ScriptAiRoleExtractionClientRequest(
        baseUrl: 'https://script.example/v1',
        token: 'secret',
        model: 'gpt-5.4',
        reasoningEffort: 'xhigh',
        requestJson: {},
      ),
    );

    expect(captured?.payload['reasoning_effort'], 'xhigh');
  });

  test('role extraction client appends v1 chat completions to non-v1 base URL',
      () async {
    ApiRequest? captured;
    final client = OpenAiCompatibleScriptAiRoleExtractionClient(
      fetchData: (request) async {
        captured = request;
        return ApiResponse(
          status: '200',
          data: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '{}'},
                  },
                ],
              }),
            ),
          ),
        );
      },
    );

    await client.extractRoles(
      const ScriptAiRoleExtractionClientRequest(
        baseUrl: 'https://script.example',
        token: 'secret',
        model: 'gpt-4.1-mini',
        requestJson: {},
      ),
    );

    expect(captured?.endpoint, 'https://script.example/v1/chat/completions');
  });

  test('role extraction client streams reasoning and content deltas', () async {
    ApiRequest? captured;
    final reasoningDeltas = <String>[];
    final contentDeltas = <String>[];
    final client = OpenAiCompatibleScriptAiRoleExtractionClient(
      streamData: (request, {required onTextChunk}) async {
        captured = request;
        onTextChunk(
          'data: {"choices":[{"delta":{"reasoning_content":"inspect "}}]}\n\n',
        );
        onTextChunk(
          'data: {"choices":[{"delta":{"content":"{\\"schema_version\\":1,"}}]}\n\n',
        );
        onTextChunk(
          'data: {"choices":[{"delta":{"reasoning_content":"slot-0"}}]}\n\n',
        );
        onTextChunk(
          'data: {"choices":[{"delta":{"content":"\\"roles\\":[]}"}}]}\n\n',
        );
        onTextChunk('data: [DONE]\n\n');
        return ApiResponse(
          status: '200',
          data: Uint8List.fromList(utf8.encode('')),
        );
      },
    );

    final result = await client.extractRoles(
      ScriptAiRoleExtractionClientRequest(
        baseUrl: 'https://script.example/v1',
        token: 'secret',
        model: 'gpt-4.1-mini',
        requestJson: const {'schema_version': 1},
        onStreamDelta: (delta) {
          if (delta.reasoningContentDelta.isNotEmpty) {
            reasoningDeltas.add(delta.reasoningContentDelta);
          }
          if (delta.contentDelta.isNotEmpty) {
            contentDeltas.add(delta.contentDelta);
          }
        },
      ),
    );

    expect(captured?.payload['stream'], isTrue);
    expect(result.reasoningContent, 'inspect slot-0');
    expect(result.rawJson, '{"schema_version":1,"roles":[]}');
    expect(reasoningDeltas, ['inspect ', 'slot-0']);
    expect(contentDeltas, ['{"schema_version":1,', '"roles":[]}']);
  });
}
