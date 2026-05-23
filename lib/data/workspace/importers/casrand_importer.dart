import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

class CasRandImportResult {
  final WorkspacePromptConfig promptConfig;
  final GenerationProfile generationProfile;
  final List<Map<String, dynamic>> replaceRules;

  const CasRandImportResult({
    required this.promptConfig,
    required this.generationProfile,
    required this.replaceRules,
  });
}

class CasRandImporter {
  CasRandImportResult importJson(
    Map<String, dynamic> json, {
    required String promptConfigId,
    required String profileId,
    String promptConfigName = 'Imported CasRand Config',
    String profileName = 'Imported CasRand Profile',
    String secretRef = 'default_nai_token',
  }) {
    final replaceRules = _mapList(json['prompt_replace_rules']);
    final paramConfig = _withoutSecrets(_mapValue(json['param_config']));
    final settings = _mapValue(json['settings']);
    final negativePrompt =
        paramConfig.remove('negative_prompt')?.toString() ?? '';

    final promptConfig = WorkspacePromptConfig(
      id: promptConfigId,
      name: promptConfigName,
      rootConfig: _mapValue(json['prompt_config']),
      savedBlocks: _mapList(json['saved_config']),
      replaceRuleIds: _replaceRuleIds(replaceRules),
      generationProfileId: profileId,
    );

    final generationProfile = GenerationProfile(
      id: profileId,
      name: profileName,
      params: paramConfig,
      negativePrompt: negativePrompt,
      batchDefaults: _batchDefaults(settings),
      secretRef: secretRef,
    );

    return CasRandImportResult(
      promptConfig: promptConfig,
      generationProfile: generationProfile,
      replaceRules: replaceRules,
    );
  }

  Map<String, dynamic> _batchDefaults(Map<String, dynamic> settings) {
    final defaults = <String, dynamic>{};
    const keys = [
      'batch_count',
      'batch_interval',
      'batch_interval_jitter_min',
      'batch_interval_jitter_max',
      'retry_on_429_enabled',
      'retry_on_429_delay_sec',
      'number_of_requests',
    ];
    for (final key in keys) {
      if (settings.containsKey(key)) {
        defaults[key] = settings[key];
      }
    }
    return defaults;
  }

  List<String> _replaceRuleIds(List<Map<String, dynamic>> replaceRules) {
    return replaceRules.indexed
        .map(
            (entry) => entry.$2['id']?.toString() ?? 'replace-rule-${entry.$1}')
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) => _mapValue(entry))
        .toList(growable: false);
  }

  Map<String, dynamic> _mapValue(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return result;
  }

  Map<String, dynamic> _withoutSecrets(Map<String, dynamic> value) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (_isSensitiveKey(entry.key)) continue;
      final sanitized = _sanitizeValue(entry.value);
      if (sanitized != _omitValue) {
        result[entry.key] = sanitized;
      }
    }
    return result;
  }

  dynamic _sanitizeValue(dynamic value) {
    if (value is String && _isSensitiveString(value)) return _omitValue;
    if (value is Map) return _withoutSecrets(_mapValue(value));
    if (value is List) {
      return value
          .map(_sanitizeValue)
          .where((entry) => entry != _omitValue)
          .toList(growable: false);
    }
    return value;
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('apikey') ||
        normalized.contains('token') ||
        normalized.contains('authorization') ||
        normalized.contains('bearer') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('proxy');
  }

  bool _isSensitiveString(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('bearer ') || normalized.contains('pst-');
  }
}

const Object _omitValue = Object();
