import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_evidence_builder.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_client.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_service.dart';

void main() {
  group('DefaultScriptAiRoleExtractionService', () {
    test('short script sends one chunk_extract_v2 request', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtraction(chunkId: 'chunk-1'),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(client: fakeClient);

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(result.aiRequestCount, 1);
      expect(fakeClient.requests, hasLength(1));
      expect(fakeClient.requests.single.requestJson['request_kind'],
          'chunk_extract_v2');
      expect(result.requestPreview['request_kind'], 'chunk_extract_v2');
      _expectNoOldCatalogKeys(fakeClient.requests.single.requestJson);
    });

    test('short script preserves DeepSeek reasoning content', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtraction(chunkId: 'chunk-1'),
          reasoningContent: '先查看 slot-0，再拆分服装字段。',
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(client: fakeClient);

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      expect(result.reasoningContent, contains('[chunk-1]'));
      expect(result.reasoningContent, contains('先查看 slot-0'));
    });

    test('passes reasoning effort to each client request', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          if (request.requestJson['request_kind'] == 'merge_extractions') {
            return ScriptAiRoleExtractionClientResult(
              rawJson: _rawExtraction(roleId: 'slot-merged'),
            );
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(
              chunkId: request.requestJson['chunk_id'] as String?,
            ),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
      );

      await service.extractRoles(
        request: _request(
          script: _script(frameCount: 2),
          reasoningEffort: 'high',
        ),
      );

      expect(fakeClient.requests, hasLength(3));
      expect(
        fakeClient.requests.map((request) => request.reasoningEffort),
        everyElement('high'),
      );
    });

    test('long script sends multiple chunk_extract_v2 requests', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtraction(
            chunkId: request.requestJson['chunk_id'] as String?,
          ),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 3)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(fakeClient.requests.where(_isChunkRequest), hasLength(3));
      expect(result.aiRequestCount, 4);
    });

    test('completed chunk checkpoints are skipped on resume', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          if (request.requestJson['request_kind'] == 'merge_extractions') {
            return ScriptAiRoleExtractionClientResult(
              rawJson: _rawExtraction(roleId: 'slot-merged'),
            );
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(
              chunkId: request.requestJson['chunk_id'] as String?,
              roleId: 'slot-1',
              frameIndexes: const [2],
            ),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
        retryDelays: const [],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(frameCount: 2),
          completedChunkExtractions: const [
            ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              chunkId: 'chunk-1',
              confidence: 0.9,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'cached chunk',
                  confidence: 0.9,
                  frameIndexes: [1],
                ),
              ],
            ),
          ],
        ),
      );

      expect(fakeClient.requests.where(_isChunkRequest), hasLength(1));
      expect(
          fakeClient.requests
              .where(_isChunkRequest)
              .single
              .requestJson['chunk_id'],
          'chunk-2');
      expect(fakeClient.requests.where(_isMergeRequest), hasLength(1));
      expect(result.aiRequestCount, 2);
      expect(result.extraction.status, ScriptAiRoleExtractionStatus.ready);
    });

    test('multiple chunks trigger one merge_extractions request', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          if (request.requestJson['request_kind'] == 'merge_extractions') {
            return ScriptAiRoleExtractionClientResult(
              rawJson: _rawExtraction(roleId: 'slot-merged'),
            );
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(
              chunkId: request.requestJson['chunk_id'] as String?,
            ),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 2)),
      );

      expect(fakeClient.requests.where(_isChunkRequest), hasLength(2));
      expect(fakeClient.requests.where(_isMergeRequest), hasLength(1));
      expect(result.aiRequestCount, 3);
      expect(result.requestPreview['request_kind'], 'merge_extractions');
      expect(result.extraction.roles.single.sourceRoleId, 'slot-merged');
      _expectNoOldCatalogKeys(fakeClient.requests.last.requestJson);
    });

    test('merge_extractions includes raw prompts from every parsed frame',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          if (request.requestJson['request_kind'] == 'merge_extractions') {
            return ScriptAiRoleExtractionClientResult(
              rawJson: _rawExtraction(roleId: 'slot-merged'),
            );
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(
              chunkId: request.requestJson['chunk_id'] as String?,
            ),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
      );

      await service.extractRoles(
        request: _request(
          script: _script(
            frames: [
              _frame(
                1,
                baseCaption: 'frame one base',
                charCaptions: const ['alice frame one'],
                negativeBase: 'frame one negative',
              ),
              _frame(
                2,
                baseCaption: 'frame two base',
                charCaptions: const ['alice frame two'],
                negativeBase: 'frame two negative',
              ),
            ],
          ),
        ),
      );

      final mergeRequest =
          fakeClient.requests.singleWhere(_isMergeRequest).requestJson;
      expect(mergeRequest['frame_prompts'], [
        {
          'frame_index': 1,
          'base_caption': 'frame one base',
          'char_captions': ['alice frame one'],
          'negative_base': 'frame one negative',
          'negative_char_captions': <String>[],
        },
        {
          'frame_index': 2,
          'base_caption': 'frame two base',
          'char_captions': ['alice frame two'],
          'negative_base': 'frame two negative',
          'negative_char_captions': <String>[],
        },
      ]);
    });

    test('needs_more_evidence sends one evidence_followup request', () async {
      final fakeClient = _FakeRoleExtractionClient((request) async {
        if (request.requestJson['request_kind'] == 'chunk_extract_v2') {
          return ScriptAiRoleExtractionClientResult(
            rawJson: _needsEvidenceRawExtraction(),
          );
        }
        expect(request.requestJson['request_kind'], 'evidence_followup');
        expect(request.requestJson['schema_version'], 2);
        expect(request.requestJson['chunk_id'], 'chunk-1');
        final evidence = (request.requestJson['evidence'] as List)
            .cast<Map<String, dynamic>>();
        expect(evidence, hasLength(2));
        expect(evidence.first['source_id'], 'slot-0');
        expect(evidence.first['frame_index'], 1);
        expect(evidence.first['base_caption'], contains('school uniform'));
        expect(evidence.first['char_caption'], contains('black coat'));
        expect(evidence.first['negative_base'], contains('bad anatomy'));
        expect(evidence.first['negative_char_caption'], contains('lowres'));
        _expectNoForbiddenFollowUpPayload(request.requestJson);
        return ScriptAiRoleExtractionClientResult(rawJson: _rawExtraction());
      });
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(frames: [
            _frame(
              1,
              baseCaption: 'school uniform',
              charCaptions: ['black coat, black pantyhose'],
              negativeBase: 'bad anatomy',
              negativeCharCaptions: ['lowres'],
            ),
            _frame(
              2,
              baseCaption: 'school uniform',
              charCaptions: ['black coat, no shoes'],
              negativeBase: 'bad anatomy',
              negativeCharCaptions: ['lowres'],
            ),
          ]),
        ),
      );

      expect(fakeClient.requests, hasLength(2));
      expect(
        fakeClient.requests.last.requestJson['request_kind'],
        'evidence_followup',
      );
      expect(result.aiRequestCount, 2);
      expect(result.extraction.isReady, isTrue);
      expect(result.requestPreview['request_kind'], 'evidence_followup');
    });

    test(
        'follow-up client failure returns failed extraction with follow-up preview',
        () async {
      final fakeClient = _FakeRoleExtractionClient((request) async {
        if (request.requestJson['request_kind'] == 'chunk_extract_v2') {
          return ScriptAiRoleExtractionClientResult(
            rawJson: _needsEvidenceRawExtraction(),
          );
        }
        expect(request.requestJson['request_kind'], 'evidence_followup');
        throw const ScriptAiRoleExtractionClientException('follow-up boom');
      });
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(frames: [
            _frame(1, charCaptions: ['black coat']),
            _frame(2, charCaptions: ['black coat, no shoes']),
          ]),
        ),
      );

      expect(fakeClient.requests, hasLength(2));
      expect(result.extraction.isFailed, isTrue);
      expect(result.aiRequestCount, 2);
      expect(result.requestPreview['request_kind'], 'evidence_followup');
      final message = result.extraction.attentionItems.single.message;
      expect(message, contains('evidence_followup'));
      expect(message, contains('follow-up boom'));
    });

    test('follow-up caps request groups and total frames', () async {
      final fakeClient = _FakeRoleExtractionClient((request) async {
        if (request.requestJson['request_kind'] == 'chunk_extract_v2') {
          return const ScriptAiRoleExtractionClientResult(
            rawJson: '''
        {
          "schema_version": 2,
          "status": "needs_more_evidence",
          "chunk_id": "chunk-1",
          "evidence_requests": [
            {"id":"a","source_id":"slot-0","frame_indexes":[1,2,3,4,5,6,7,8,9,10,11,12,13],"wanted_fields":[],"reason":"a"},
            {"id":"b","source_id":"slot-0","frame_indexes":[14,15,16,17,18,19,20,21,22,23,24,25],"wanted_fields":[],"reason":"b"},
            {"id":"c","source_id":"slot-0","frame_indexes":[26,27,28,29,30,31,32,33,34,35,36,37],"wanted_fields":[],"reason":"c"},
            {"id":"d","source_id":"slot-0","frame_indexes":[38],"wanted_fields":[],"reason":"d"}
          ]
        }
        ''',
          );
        }
        final evidence = (request.requestJson['evidence'] as List)
            .cast<Map<String, dynamic>>();
        expect(evidence, hasLength(24));
        expect(
          evidence.map((row) => row['frame_index']),
          isNot(contains(25)),
        );
        return ScriptAiRoleExtractionClientResult(rawJson: _rawExtraction());
      });

      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [],
      );

      await service.extractRoles(
        request: _request(
          script: _script(frames: [
            for (var index = 1; index <= 40; index += 1)
              _frame(index, charCaptions: ['slot frame $index']),
          ]),
        ),
      );

      expect(fakeClient.requests, hasLength(2));
    });

    test('invalid follow-up source is returned as failed extraction', () async {
      final fakeClient = _FakeRoleExtractionClient((request) async {
        return ScriptAiRoleExtractionClientResult(
          rawJson: _needsEvidenceRawExtraction(sourceId: '../secret.json'),
        );
      });
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(frames: [
            _frame(1, charCaptions: ['black coat']),
          ]),
        ),
      );

      expect(fakeClient.requests, hasLength(1));
      expect(result.aiRequestCount, 1);
      expect(result.requestPreview['request_kind'], 'chunk_extract_v2');
      expect(result.extraction.isFailed, isTrue);
      expect(
        result.extraction.attentionItems.map((item) => item.kind),
        contains('invalid_evidence_request'),
      );
    });

    test('absent follow-up slot source is returned as failed extraction',
        () async {
      final fakeClient = _FakeRoleExtractionClient((request) async {
        return ScriptAiRoleExtractionClientResult(
          rawJson: _needsEvidenceRawExtraction(sourceId: 'slot-99'),
        );
      });
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(frames: [
            _frame(1, charCaptions: ['black coat']),
            _frame(2, charCaptions: ['black coat, no shoes']),
          ]),
        ),
      );

      expect(fakeClient.requests, hasLength(1));
      expect(result.aiRequestCount, 1);
      expect(result.requestPreview['request_kind'], 'chunk_extract_v2');
      expect(result.extraction.isFailed, isTrue);
      expect(
        result.extraction.attentionItems.map((item) => item.kind),
        contains('invalid_evidence_request'),
      );
    });

    test('follow-up response cannot request another follow-up', () async {
      final fakeClient = _FakeRoleExtractionClient((request) async {
        return ScriptAiRoleExtractionClientResult(
          rawJson: _needsEvidenceRawExtraction(),
        );
      });
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(frames: [
            _frame(1, charCaptions: ['black coat']),
            _frame(2, charCaptions: ['black coat, no shoes']),
          ]),
        ),
      );

      expect(fakeClient.requests, hasLength(2));
      expect(result.extraction.isFailed, isTrue);
      expect(
        result.extraction.attentionItems.map((item) => item.kind),
        contains('followup_limit_reached'),
      );
    });

    test('failed merge request falls back to deterministic merger', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          if (request.requestJson['request_kind'] == 'merge_extractions') {
            throw const ScriptAiRoleExtractionClientException('merge boom');
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(
              chunkId: request.requestJson['chunk_id'] as String?,
              roleId: 'slot-0',
              frameIndexes: [
                ((request.requestJson['chunk']
                    as Map<String, dynamic>)['start_frame_index'] as int)
              ],
            ),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 2)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(result.extraction.roles, hasLength(1));
      expect(result.extraction.roles.single.frameIndexes, [1, 2]);
      expect(result.aiRequestCount, 3);
      expect(result.requestPreview['request_kind'], 'merge_extractions');
    });

    test('invalid merge JSON fallback preserves diagnostic attention',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          if (request.requestJson['request_kind'] == 'merge_extractions') {
            return const ScriptAiRoleExtractionClientResult(
              rawJson: 'not role extraction json',
            );
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(
              chunkId: request.requestJson['chunk_id'] as String?,
              roleId: 'slot-0',
              frameIndexes: [
                ((request.requestJson['chunk']
                    as Map<String, dynamic>)['start_frame_index'] as int)
              ],
            ),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 2)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(result.extraction.roles.single.frameIndexes, [1, 2]);
      expect(result.extraction.attentionItems, hasLength(1));
      expect(result.extraction.attentionItems.single.kind, 'parse_failure');
      expect(result.extraction.attentionItems.single.blocking, isFalse);
      expect(result.extraction.attentionItems.single.message,
          contains('Invalid JSON'));
      expect(result.aiRequestCount, 3);
    });

    test('merge client failure falls back to chunks as non-blocking attention',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          if (request.requestJson['request_kind'] == 'merge_extractions') {
            throw const ScriptAiRoleExtractionClientException(
              'connection closed',
            );
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(
              chunkId: request.requestJson['chunk_id'] as String?,
              roleId: 'slot-0',
              frameIndexes: [
                ((request.requestJson['chunk']
                    as Map<String, dynamic>)['start_frame_index'] as int)
              ],
            ),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        builder: const ScriptAiRoleEvidenceBuilder(maxFramesPerChunk: 1),
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 2)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(result.extraction.roles.single.frameIndexes, [1, 2]);
      expect(result.extraction.attentionItems, hasLength(1));
      expect(
          result.extraction.attentionItems.single.kind, 'merge_request_failed');
      expect(result.extraction.attentionItems.single.blocking, isFalse);
      expect(result.extraction.attentionItems.single.message,
          contains('请求类型：merge_extractions'));
      expect(result.aiRequestCount, 3);
    });

    test('invalid chunk JSON returns failed extraction with request preview',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => const ScriptAiRoleExtractionClientResult(
          rawJson: 'not role extraction json',
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(client: fakeClient);

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.failed);
      expect(result.extraction.rawResponse, 'not role extraction json');
      expect(result.extraction.attentionItems.single.kind, 'parse_failure');
      expect(result.requestPreview['request_kind'], 'chunk_extract_v2');
      expect(result.aiRequestCount, 1);
    });

    test('client failure returns failed extraction with request preview',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => throw const ScriptAiRoleExtractionClientException('boom'),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.failed);
      expect(result.extraction.attentionItems.single.message, contains('boom'));
      expect(result.requestPreview['request_kind'], 'chunk_extract_v2');
      expect(result.aiRequestCount, 1);
    });

    test('client failure auto reconnects before returning chunk success',
        () async {
      var attempts = 0;
      final fakeClient = _FakeRoleExtractionClient(
        (request) async {
          attempts += 1;
          if (attempts == 1) {
            throw const ScriptAiRoleExtractionClientException('temporary drop');
          }
          return ScriptAiRoleExtractionClientResult(
            rawJson: _rawExtraction(chunkId: 'chunk-1'),
          );
        },
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      expect(result.extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(fakeClient.requests, hasLength(2));
      expect(result.aiRequestCount, 1);
    });

    test('repeated client failure reports chinese request context', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => throw const ScriptAiRoleExtractionClientException(
          'connection closed',
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final message = result.extraction.attentionItems.single.message;
      expect(result.extraction.status, ScriptAiRoleExtractionStatus.failed);
      expect(fakeClient.requests, hasLength(3));
      expect(message, contains('AI 角色字段请求失败'));
      expect(message, contains('请求类型：chunk_extract_v2'));
      expect(message, contains('Chunk：chunk-1'));
      expect(
          message, contains('地址：https://script.example/v1/chat/completions'));
      expect(message, contains('已自动重连 2 次'));
      expect(message, contains('connection closed'));
    });

    test('same outfit state variants stay as AI-provided stages', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'china-dress-barefoot',
              'label': 'Cosplay barefoot',
              'confidence': 0.9,
              'frame_indexes': [1],
              'identity': 'plana (blue archive)',
              'upper_body': 'small breasts',
              'lower_body': 'barefoot',
              'upper_clothing': 'china dress, black jacket, no coat',
              'lower_clothing': '',
              'evidence_terms': ['china dress', 'barefoot'],
              'missing_fields': ['missing_lower_clothing'],
              'warnings': [],
            },
            {
              'stage_id': 'china-dress-shoes',
              'label': 'Cosplay with socks and shoes',
              'confidence': 0.85,
              'frame_indexes': [2],
              'identity': 'plana (blue archive)',
              'upper_body': 'small breasts',
              'lower_body': '',
              'upper_clothing': 'china dress, black jacket, black coat',
              'lower_clothing': 'white socks, black shoes',
              'evidence_terms': ['china dress', 'white socks', 'black shoes'],
              'missing_fields': [],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final stages = result.extraction.roles.single.stages;
      expect(stages, hasLength(2));
      expect(stages.first.stageId, 'china-dress-barefoot');
      expect(
        stages.first.upperClothing,
        'china dress, black jacket, no coat',
      );
      expect(stages.first.lowerClothing, isEmpty);
      expect(stages.first.lowerBody, 'barefoot');
      expect(stages.first.frameIndexes, [1]);
      expect(stages.first.missingFields, ['missing_lower_clothing']);
      expect(stages.first.warnings, isEmpty);
      expect(stages.last.stageId, 'china-dress-shoes');
      expect(
        stages.last.upperClothing,
        'china dress, black jacket, black coat',
      );
      expect(stages.last.lowerClothing, 'white socks, black shoes');
      expect(stages.last.frameIndexes, [2]);
      expect(stages.last.missingFields, isEmpty);
      expect(stages.last.warnings, isEmpty);
    });

    test('equivalent nude stages with empty clothing fields are merged',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'nude-shower-sleep',
              'label': 'nude (shower/sleep)',
              'confidence': 0.9,
              'frame_indexes': [1, 2],
              'identity': 'plana (blue archive), loli, child, little girl',
              'upper_body': 'small nipples, small breasts',
              'lower_body': '',
              'upper_clothing': '',
              'lower_clothing': '',
              'evidence_terms': ['nude', 'shower', 'sleep'],
              'missing_fields': [
                'missing_upper_clothing',
                'missing_lower_clothing',
              ],
              'warnings': [],
            },
            {
              'stage_id': 'nude-shower',
              'label': 'nude (shower)',
              'confidence': 0.88,
              'frame_indexes': [3],
              'identity': 'plana (blue archive), loli, child, little girl',
              'upper_body': 'small nipples, small breasts',
              'lower_body': '',
              'upper_clothing': '',
              'lower_clothing': '',
              'evidence_terms': ['nude', 'shower'],
              'missing_fields': [
                'missing_upper_clothing',
                'missing_lower_clothing',
              ],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final stages = result.extraction.roles.single.stages;
      expect(stages, hasLength(1));
      expect(stages.single.frameIndexes, [1, 2, 3]);
      expect(stages.single.upperClothing, isEmpty);
      expect(stages.single.lowerClothing, isEmpty);
      expect(stages.single.missingFields, [
        'missing_upper_clothing',
        'missing_lower_clothing',
      ]);
      expect(stages.single.warnings, contains('outfit_state_variant_merged'));
    });

    test(
        'does not merge different replacement states with empty clothing fields',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'nude',
              'label': 'nude',
              'confidence': 0.9,
              'frame_indexes': [48],
              'identity': 'aoi (mechanic) (princess connect!), girl',
              'upper_body': 'green hair',
              'lower_body': '',
              'upper_clothing': '',
              'lower_clothing': '',
              'evidence_terms': ['completely nude'],
              'missing_fields': [
                'missing_upper_clothing',
                'missing_lower_clothing',
              ],
              'warnings': [],
            },
            {
              'stage_id': 'towel',
              'label': 'bath towel',
              'confidence': 0.88,
              'frame_indexes': [29],
              'identity': 'aoi (mechanic) (princess connect!), girl',
              'upper_body': 'green hair',
              'lower_body': '',
              'upper_clothing': '',
              'lower_clothing': '',
              'evidence_terms': ['white towel'],
              'missing_fields': [
                'missing_upper_clothing',
                'missing_lower_clothing',
              ],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final stages = result.extraction.roles.single.stages;
      expect(stages, hasLength(2));
      expect(stages.map((stage) => stage.stageId), ['nude', 'towel']);
      expect(
        stages.singleWhere((stage) => stage.stageId == 'nude').frameIndexes,
        [48],
      );
    });

    test('demotes action and transient terms before returning extraction',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'uniform-action',
              'label': 'uniform action',
              'confidence': 0.95,
              'frame_indexes': [1],
              'identity': 'hero, girl',
              'upper_body': 'blue eyes, smile, closed eyes',
              'lower_body': 'fox tail, kneeling',
              'upper_clothing': 'school uniform, wet, lifted shirt',
              'lower_clothing': 'pleated skirt, spread legs',
              'evidence_terms': [
                'blue eyes',
                'looking at viewer',
                'spread legs',
              ],
              'missing_fields': [],
              'warnings': [],
            },
            {
              'stage_id': 'uniform-subset',
              'label': 'uniform subset',
              'confidence': 0.93,
              'frame_indexes': [2],
              'identity': 'hero',
              'upper_body': 'blue eyes',
              'lower_body': 'fox tail',
              'upper_clothing': 'school uniform',
              'lower_clothing': '',
              'evidence_terms': [],
              'missing_fields': [],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final stages = result.extraction.roles.single.stages;
      expect(stages, hasLength(1));
      expect(stages.single.frameIndexes, [1, 2]);
      expect(stages.single.identity, 'hero, girl');
      expect(stages.single.upperBody, 'blue eyes');
      expect(stages.single.lowerBody, 'fox tail');
      expect(stages.single.upperClothing, 'school uniform');
      expect(stages.single.lowerClothing, 'pleated skirt');
      expect(stages.single.nonRole, isEmpty);
      expect(stages.single.nonRoleMaterialized, isFalse);
    });

    test('preserves AI identity body and clothing fields without rerouting',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'black-kimono',
              'label': 'Black kimono',
              'confidence': 0.9,
              'frame_indexes': [1],
              'identity':
                  'wakamo (blue archive), girl, fox girl, fox ears, fox tail',
              'upper_body': 'red halo, fox ears',
              'lower_body': '',
              'upper_clothing': 'large breasts, black choker',
              'lower_clothing': 'fox tail, thighs, ass',
              'evidence_terms': [
                'wakamo (blue archive)',
                'girl',
                'fox girl',
                'fox ears',
                'fox tail',
                'red halo',
                'large breasts',
                'black choker',
                'thighs',
                'ass',
              ],
              'missing_fields': [],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final stages = result.extraction.roles.single.stages;
      expect(stages, hasLength(1));
      expect(
        stages.single.identity,
        'wakamo (blue archive), girl, fox girl, fox ears, fox tail',
      );
      expect(
        stages.single.upperBody,
        'red halo, fox ears',
      );
      expect(stages.single.lowerBody, isEmpty);
      expect(stages.single.upperClothing, 'large breasts, black choker');
      expect(stages.single.lowerClothing, 'fox tail, thighs, ass');
      expect(stages.single.missingFields, isEmpty);
      expect(stages.single.warnings, isEmpty);
    });

    test('preserves provided field prompt weights while normalizing categories',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'weighted-outfit',
              'label': 'weighted outfit',
              'confidence': 0.9,
              'frame_indexes': [1],
              'identity': '1.1::plana (blue archive)::, girl',
              'upper_body': '1.25::blue eyes::',
              'lower_body': '',
              'upper_clothing': '0.75::white dress::',
              'lower_clothing': '',
              'evidence_terms': [
                '1.1::plana (blue archive)::',
                '1.25::blue eyes::',
                '0.75::white dress::',
              ],
              'missing_fields': [],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final stage = result.extraction.roles.single.stages.single;
      expect(stage.identity, '1.1:: plana (blue archive) ::, girl');
      expect(stage.upperBody, '1.25:: blue eyes ::');
      expect(stage.upperClothing, '0.75:: white dress ::');
    });

    test('restores grouped source weights after AI sorts normalized tags',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'sorted-weighted-outfit',
              'label': 'sorted weighted outfit',
              'confidence': 0.9,
              'frame_indexes': [1],
              'identity': 'alice_(series)',
              'upper_body': 'long hair, blue eyes',
              'lower_body': '',
              'upper_clothing': 'white dress',
              'lower_clothing': 'black shoes',
              'evidence_terms': [
                'long hair',
                'blue eyes',
                'white dress',
                'black shoes',
              ],
              'missing_fields': [],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(
            frames: [
              _frame(
                1,
                charCaptions: const [
                  'alice_(series), 1.5::blue eyes, white dress, long hair, black shoes::',
                ],
              ),
            ],
          ),
        ),
      );

      final stage = result.extraction.roles.single.stages.single;
      expect(stage.identity, 'alice_(series)');
      expect(stage.upperBody, '1.5:: long hair ::, 1.5:: blue eyes ::');
      expect(stage.upperClothing, '1.5:: white dress ::');
      expect(stage.lowerClothing, '1.5:: black shoes ::');
    });

    test('restores base prompt weights through role base appearances',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: jsonEncode({
            'schema_version': 1,
            'confidence': 0.9,
            'roles': [
              {
                'source_role_id': 'role-alice',
                'source_kind': 'role',
                'display_name': 'alice',
                'confidence': 0.9,
                'frame_indexes': [1],
                'appearances': [
                  {
                    'source_id': 'base',
                    'source_kind': 'base',
                    'frame_indexes': [1],
                  }
                ],
                'evidence_terms': ['alice_(series)', 'blue eyes'],
                'warnings': [],
                'stages': [
                  {
                    'stage_id': 'base-stage',
                    'label': 'base',
                    'confidence': 0.9,
                    'frame_indexes': [1],
                    'identity': 'alice_(series)',
                    'upper_body': 'blue eyes',
                    'lower_body': '',
                    'upper_clothing': '',
                    'lower_clothing': '',
                    'evidence_terms': ['alice_(series)', 'blue eyes'],
                    'missing_fields': [],
                    'warnings': [],
                  }
                ],
                'unassigned_terms': [],
              }
            ],
            'artist_chains': [],
            'strong_filter_keywords': [],
            'attention_items': [],
            'unassigned_terms': [],
          }),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(
            frames: [
              _frame(
                1,
                baseCaption: '1.4::alice_(series), blue eyes::, classroom',
                charCaptions: const [],
              ),
            ],
          ),
        ),
      );

      final stage = result.extraction.roles.single.stages.single;
      expect(stage.identity, '1.4:: alice_(series) ::');
      expect(stage.upperBody, '1.4:: blue eyes ::');
    });

    test('does not recover source identity from raw frames behind UI state',
        () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'white-dress',
              'label': '白裙',
              'confidence': 0.93,
              'frame_indexes': [1],
              'identity': 'girl',
              'upper_body': 'small breasts',
              'lower_body': '',
              'upper_clothing': 'white dress',
              'lower_clothing': '',
              'evidence_terms': ['girl', 'small breasts', 'white dress'],
              'missing_fields': ['missing_identity'],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(
          script: _script(
            frames: [
              _frame(
                1,
                charCaptions: const [
                  'girl, himekawa yoshino (date a live), small breasts, '
                      'white dress',
                ],
              ),
            ],
          ),
        ),
      );

      final stage = result.extraction.roles.single.stages.single;
      expect(stage.identity, 'girl');
      expect(
        stage.evidenceTerms,
        isNot(contains('himekawa yoshino (date a live)')),
      );
      expect(stage.warnings, isNot(contains('source_identity_recovered')));
    });

    test('stages with identical extracted fields are merged', () async {
      final fakeClient = _FakeRoleExtractionClient(
        (_) async => ScriptAiRoleExtractionClientResult(
          rawJson: _rawExtractionWithStages([
            {
              'stage_id': 'shower-sleep',
              'label': 'shower/sleep',
              'confidence': 0.9,
              'frame_indexes': [1],
              'identity': 'plana (blue archive), loli, child, little girl',
              'upper_body': 'small nipples, small breasts',
              'lower_body': '',
              'upper_clothing': '',
              'lower_clothing': '',
              'evidence_terms': ['shower', 'sleep'],
              'missing_fields': [
                'missing_upper_clothing',
                'missing_lower_clothing',
              ],
              'warnings': [],
            },
            {
              'stage_id': 'shower',
              'label': 'shower',
              'confidence': 0.88,
              'frame_indexes': [2],
              'identity': 'plana (blue archive), loli, child, little girl',
              'upper_body': 'small nipples, small breasts',
              'lower_body': '',
              'upper_clothing': '',
              'lower_clothing': '',
              'evidence_terms': ['shower'],
              'missing_fields': [
                'missing_upper_clothing',
                'missing_lower_clothing',
              ],
              'warnings': [],
            },
          ]),
        ),
      );
      final service = DefaultScriptAiRoleExtractionService(
        client: fakeClient,
        retryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.extractRoles(
        request: _request(script: _script(frameCount: 1)),
      );

      final stages = result.extraction.roles.single.stages;
      expect(stages, hasLength(1));
      expect(stages.single.frameIndexes, [1, 2]);
      expect(stages.single.identity,
          'plana (blue archive), loli, child, little girl');
      expect(stages.single.upperBody, 'small nipples, small breasts');
      expect(stages.single.upperClothing, isEmpty);
      expect(stages.single.lowerClothing, isEmpty);
      expect(stages.single.warnings, contains('outfit_state_variant_merged'));
    });
  });
}

class _FakeRoleExtractionClient implements ScriptAiRoleExtractionClient {
  final Future<ScriptAiRoleExtractionClientResult> Function(
    ScriptAiRoleExtractionClientRequest request,
  ) handler;

  final List<ScriptAiRoleExtractionClientRequest> requests = [];

  _FakeRoleExtractionClient(this.handler);

  @override
  Future<ScriptAiRoleExtractionClientResult> extractRoles(
    ScriptAiRoleExtractionClientRequest request,
  ) {
    requests.add(request);
    return handler(request);
  }
}

ScriptAiRoleExtractionServiceRequest _request({
  required Script script,
  List<ScriptAiRoleExtraction> completedChunkExtractions = const [],
  String reasoningEffort = '',
}) {
  return ScriptAiRoleExtractionServiceRequest(
    baseUrl: 'https://script.example',
    token: 'secret',
    model: 'gpt-4.1-mini',
    proxy: '127.0.0.1:7890',
    reasoningEffort: reasoningEffort,
    script: script,
    completedChunkExtractions: completedChunkExtractions,
  );
}

Script _script({int frameCount = 1, List<ScriptFrame>? frames}) {
  return Script(
    id: 'script-1',
    name: 'Opening scene',
    rootPath: '',
    detectedSchema: ScriptSchema.v4Slotted,
    frames: frames ??
        [
          for (var index = 1; index <= frameCount; index += 1) _frame(index),
        ],
  );
}

ScriptFrame _frame(
  int index, {
  String baseCaption = 'official art',
  List<String> charCaptions = const ['alice_(series), white shirt'],
  String negativeBase = 'mosaic censoring',
  List<String> negativeCharCaptions = const [],
}) {
  return ScriptFrame(
    index: index,
    fileName: 'nai_$index.json',
    sourcePath: '',
    rawJson: '{}',
    parsed: ParsedFrame(
      baseCaption: baseCaption,
      charCaptions: charCaptions,
      negativeBase: negativeBase,
      negativeCharCaptions: negativeCharCaptions,
    ),
    detectedSchema: ScriptSchema.v4Slotted,
    parseStatus: ScriptFrameParseStatus.parsed,
  );
}

String _rawExtraction({
  String? chunkId,
  String roleId = 'slot-0',
  List<int> frameIndexes = const [1],
}) {
  return jsonEncode({
    'schema_version': 1,
    if (chunkId != null) 'chunk_id': chunkId,
    'confidence': 0.8,
    'roles': [
      {
        'source_role_id': roleId,
        'source_kind': roleId.startsWith('slot-') ? 'slot' : 'global',
        'display_name': roleId,
        'confidence': 0.8,
        'frame_indexes': frameIndexes,
        'evidence_terms': ['alice'],
        'warnings': [],
        'stages': [],
        'unassigned_terms': [],
      }
    ],
    'artist_chains': [],
    'strong_filter_keywords': [],
    'attention_items': [],
    'unassigned_terms': [],
  });
}

String _rawExtractionWithStages(List<Map<String, dynamic>> stages) {
  return jsonEncode({
    'schema_version': 1,
    'confidence': 0.9,
    'roles': [
      {
        'source_role_id': 'slot-0',
        'source_kind': 'slot',
        'display_name': 'slot-0',
        'confidence': 0.9,
        'frame_indexes': [1, 2],
        'evidence_terms': ['plana (blue archive)'],
        'warnings': [],
        'stages': stages,
        'unassigned_terms': [],
      }
    ],
    'artist_chains': [],
    'strong_filter_keywords': [],
    'attention_items': [],
    'unassigned_terms': [],
  });
}

String _needsEvidenceRawExtraction({
  List<int> frameIndexes = const [1, 2],
  String sourceId = 'slot-0',
}) {
  return '''
  {
    "schema_version": 2,
    "status": "needs_more_evidence",
    "chunk_id": "chunk-1",
    "evidence_requests": [
      {
        "id": "slot-0-stage-ambiguity",
        "source_id": "$sourceId",
        "frame_indexes": $frameIndexes,
        "wanted_fields": ["base_caption", "char_caption", "negative_caption"],
        "reason": "Need exact nearby captions."
      }
    ]
  }
  ''';
}

bool _isChunkRequest(ScriptAiRoleExtractionClientRequest request) {
  return request.requestJson['request_kind'] == 'chunk_extract_v2';
}

bool _isMergeRequest(ScriptAiRoleExtractionClientRequest request) {
  return request.requestJson['request_kind'] == 'merge_extractions';
}

void _expectNoOldCatalogKeys(Map<String, dynamic> requestJson) {
  expect(requestJson, isNot(contains('asset_catalog')));
  expect(requestJson, isNot(contains('characters')));
  expect(requestJson, isNot(contains('outfits')));
  expect(requestJson, isNot(contains('vibes')));
}

void _expectNoForbiddenFollowUpPayload(Map<String, dynamic> requestJson) {
  const forbiddenTerms = [
    'path',
    'image_path',
    'directory',
    'external_asset',
    'asset_catalog',
    'character_card',
    'outfit_card',
    'vibe',
  ];
  final hits = <String>[];

  void visit(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        for (final term in forbiddenTerms) {
          if (key.contains(term)) {
            hits.add('key:$key');
          }
        }
        visit(entry.value);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
      return;
    }
    if (value is String) {
      for (final term in forbiddenTerms) {
        if (value.contains(term)) {
          hits.add('value:$value');
        }
      }
    }
  }

  visit(requestJson);
  expect(hits, isEmpty);
}
