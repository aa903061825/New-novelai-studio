import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/services/script_ai_json_response_decoder.dart';

class ScriptAiRoleExtractionParser {
  final ScriptAiJsonResponseDecoder decoder;

  const ScriptAiRoleExtractionParser({
    this.decoder = const ScriptAiJsonResponseDecoder(),
  });

  ScriptAiRoleExtraction parse(String rawResponse) {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty) {
      return ScriptAiRoleExtraction.failure(
        message: 'Empty AI response',
        rawResponse: rawResponse,
      );
    }

    final decoded = decoder.decode(
      trimmed,
      score: _extractionCompletenessScore,
      canSelect: _hasMinimumExtractionShape,
    );
    if (decoded.isFailure) {
      return ScriptAiRoleExtraction.failure(
        message: 'Invalid JSON: ${decoded.failure!.message}',
        rawResponse: rawResponse,
      );
    }
    if (decoded.value is! Map) {
      return ScriptAiRoleExtraction.failure(
        message: 'Missing JSON object in AI response',
        rawResponse: rawResponse,
      );
    }
    if (!_hasMinimumExtractionShape(decoded.value)) {
      return ScriptAiRoleExtraction.failure(
        message: 'Missing role extraction object in AI response',
        rawResponse: rawResponse,
      );
    }

    final json = Map<String, dynamic>.from(decoded.value! as Map);
    json['status'] ??= ScriptAiRoleExtractionStatus.ready.name;
    json['raw_response'] = rawResponse;

    return ScriptAiRoleExtraction.fromJson(json);
  }

  int _extractionCompletenessScore(Object? value) {
    if (value is! Map) return 0;

    var score = 0;
    for (final entry in _extractionKeyWeights.entries) {
      if (value.containsKey(entry.key)) {
        score += entry.value;
      }
    }
    return score;
  }

  bool _hasMinimumExtractionShape(Object? value) {
    if (value is! Map) return false;
    if (value['status'] == 'needs_more_evidence' &&
        value['evidence_requests'] is List) {
      return true;
    }
    if (value['status'] == 'failed' &&
        _hasPlausibleAttentionItem(value['attention_items'])) {
      return true;
    }
    if (value['roles'] is! List) return false;
    return _extractionSchemaSignals.any(value.containsKey);
  }

  bool _hasPlausibleAttentionItem(Object? value) {
    if (value is! List) return false;
    return value.whereType<Map>().any(
          (item) =>
              _hasTextField(item, 'kind') || _hasTextField(item, 'message'),
        );
  }

  bool _hasTextField(Map value, String key) {
    final field = value[key];
    return field is String && field.trim().isNotEmpty;
  }
}

const _extractionKeyWeights = {
  'schema_version': 1,
  'status': 1,
  'confidence': 2,
  'roles': 4,
  'artist_chains': 3,
  'strong_filter_keywords': 3,
  'attention_items': 3,
  'unassigned_terms': 3,
};
const _extractionSchemaSignals = {
  'schema_version',
  'confidence',
  'artist_chains',
  'strong_filter_keywords',
  'attention_items',
  'unassigned_terms',
};
