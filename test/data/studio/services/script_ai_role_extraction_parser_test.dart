import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_parser.dart';

void main() {
  group('ScriptAiRoleExtractionParser', () {
    const parser = ScriptAiRoleExtractionParser();

    test('parses plain role extraction JSON object', () {
      const raw = '''
{
  "schema_version": 1,
  "confidence": 0.82,
  "roles": [
    {
      "source_role_id": "slot-0",
      "source_kind": "slot",
      "display_name": "Hero",
      "confidence": 0.9,
      "frame_indexes": [1],
      "evidence_terms": ["hero"],
      "warnings": [],
      "stages": [
        {
          "stage_id": "slot-0-main",
          "label": "main",
          "confidence": 0.9,
          "frame_indexes": [1],
          "identity": "hero",
          "upper_body": "blue eyes",
          "lower_body": "",
          "upper_clothing": "jacket",
          "lower_clothing": "skirt",
          "evidence_terms": ["hero", "jacket", "skirt"],
          "missing_fields": [],
          "warnings": []
        }
      ],
      "unassigned_terms": []
    }
  ]
}
''';

      final extraction = parser.parse(raw);

      expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(extraction.confidence, 0.82);
      expect(extraction.roles.single.sourceRoleId, 'slot-0');
      expect(extraction.roles.single.stages.single.upperClothing, 'jacket');
      expect(extraction.rawResponse, raw);
    });

    test('recovers fenced JSON object', () {
      const raw = '''
```json
{"schema_version":1,"confidence":0.7,"roles":[]}
```''';

      final extraction = parser.parse(raw);

      expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(extraction.confidence, 0.7);
      expect(extraction.rawResponse, raw);
    });

    test('recovers double encoded JSON object', () {
      final raw = jsonEncode(
        '{"schema_version":1,"confidence":0.64,"roles":[]}',
      );

      final extraction = parser.parse(raw);

      expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(extraction.schemaVersion, 1);
      expect(extraction.confidence, 0.64);
      expect(extraction.rawResponse, raw);
    });

    test('prefers later full extraction object over earlier decoy object', () {
      const raw = 'draft {"note":"ignore"} final '
          '{"schema_version":1,"confidence":0.91,"roles":[],'
          '"artist_chains":[],"strong_filter_keywords":[],'
          '"attention_items":[],"unassigned_terms":[]}';

      final extraction = parser.parse(raw);

      expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(extraction.confidence, 0.91);
      expect(extraction.rawResponse, raw);
    });

    test('parser accepts needs_more_evidence response', () {
      final extraction = parser.parse('''
{
  "schema_version": 2,
  "status": "needs_more_evidence",
  "chunk_id": "chunk-1",
  "evidence_requests": [
    {
      "id": "slot-0-stage-ambiguity",
      "source_id": "slot-0",
      "frame_indexes": [1, 2],
      "wanted_fields": ["base_caption", "char_caption"],
      "reason": "Need exact captions."
    }
  ]
}
''');

      expect(extraction.isNeedsMoreEvidence, isTrue);
      expect(extraction.evidenceRequests.single.sourceId, 'slot-0');
    });

    test('parser accepts failed response with attention items and no roles', () {
      final extraction = parser.parse('''
{
  "schema_version": 2,
  "status": "failed",
  "chunk_id": "chunk-1",
  "attention_items": [
    {
      "id": "chunk-1-insufficient-evidence",
      "kind": "insufficient_evidence",
      "message": "Exact frame evidence could not resolve the role.",
      "frame_indexes": [1, 2],
      "blocking": true
    }
  ]
}
''');

      expect(extraction.isFailed, isTrue);
      expect(extraction.attentionItems.single.kind, 'insufficient_evidence');
    });

    test('parser rejects failed-shaped decoy without real attention items', () {
      const raw = '{"status":"failed","attention_items":[]}';

      final extraction = parser.parse(raw);

      expect(extraction.isFailed, isTrue);
      expect(extraction.attentionItems.single.kind, 'parse_failure');
      expect(
        extraction.attentionItems.single.message,
        contains('Missing role extraction object'),
      );
      expect(extraction.rawResponse, raw);
    });

    test('returns failure for invalid response', () {
      const raw = 'this is not json';

      final extraction = parser.parse(raw);

      expect(extraction.status, ScriptAiRoleExtractionStatus.failed);
      expect(extraction.attentionItems.single.kind, 'parse_failure');
      expect(
          extraction.attentionItems.single.message, contains('Invalid JSON'));
      expect(extraction.rawResponse, raw);
    });

    test('returns failure for decoy-only object', () {
      const raw = 'noise before {"note":"ignore"} noise after';

      final extraction = parser.parse(raw);

      expect(extraction.status, ScriptAiRoleExtractionStatus.failed);
      expect(extraction.attentionItems.single.kind, 'parse_failure');
      expect(
        extraction.attentionItems.single.message,
        contains('Missing role extraction object'),
      );
      expect(extraction.rawResponse, raw);
    });
  });
}
