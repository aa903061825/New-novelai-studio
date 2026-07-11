import 'package:novel_studio/data/models/payload_config.dart';

class WorkbenchDocument {
  static const kind = 'novel-studio-workbench';
  static const currentVersion = 1;

  static const _payloadKeys = <String>{
    'prompt_config',
    'character_config',
    'saved_config',
    'prompt_replace_rules',
    'param_config',
    'vibe_config_list',
    'vibe_config_list_v4',
    'override_prompt',
    'use_override_prompt',
    'use_character_prompt_with_override',
    'use_precise_reference',
    'precise_reference_list',
    'i2i_config',
  };

  static const _summaryPayloadKeys = <String>{
    'prompt_config',
    'character_config',
    'saved_config',
    'param_config',
    'override_prompt',
    'use_override_prompt',
    'use_character_prompt_with_override',
  };

  static const empty = WorkbenchDocument(
    version: currentVersion,
    payload: <String, dynamic>{},
  );

  final int version;
  final Map<String, dynamic> payload;

  const WorkbenchDocument({
    required this.version,
    required this.payload,
  });

  factory WorkbenchDocument.fromPayloadConfig(PayloadConfig config) {
    return WorkbenchDocument(
      version: currentVersion,
      payload: _extractPayload(config.toJson()),
    );
  }

  factory WorkbenchDocument.fromPayloadJson(Map<String, dynamic> json) {
    return WorkbenchDocument(
      version: currentVersion,
      payload: _extractPayload(json),
    );
  }

  factory WorkbenchDocument.fromJson(Map<String, dynamic> json) {
    if (json['kind'] != kind) {
      throw const FormatException('Unsupported workbench document kind.');
    }
    final version = json['version'];
    if (version is! int || version > currentVersion) {
      throw const FormatException('Unsupported workbench document version.');
    }
    final payload = json['payload'];
    if (payload is! Map) {
      throw const FormatException('Workbench document payload is missing.');
    }
    return WorkbenchDocument(
      version: version,
      payload: _extractPayload(payload.cast<String, dynamic>()),
    );
  }

  factory WorkbenchDocument.summaryFromJson(Map<String, dynamic> json) {
    if (json['kind'] != kind) {
      throw const FormatException('Unsupported workbench document kind.');
    }
    final version = json['version'];
    if (version is! int || version > currentVersion) {
      throw const FormatException('Unsupported workbench document version.');
    }
    final payload = json['payload'];
    if (payload is! Map) {
      throw const FormatException('Workbench document payload is missing.');
    }
    return WorkbenchDocument(
      version: version,
      payload: _extractPayload(
        payload.cast<String, dynamic>(),
        keys: _summaryPayloadKeys,
      ),
    );
  }

  static WorkbenchDocument? trySummaryFromJson(dynamic json) {
    if (json is! Map) {
      return null;
    }
    try {
      return WorkbenchDocument.summaryFromJson(json.cast<String, dynamic>());
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'version': version,
      'payload': payload,
    };
  }

  void applyTo(PayloadConfig target) {
    target.loadJson(
      {
        ...target.toJson(),
        // Legacy documents omit I2I state; imports should clear it to defaults.
        'i2i_config': const <String, dynamic>{},
        ...payload,
        'settings': target.settings.toJson(),
      },
      preserveCurrentApiKey: true,
    );
  }

  static Map<String, dynamic> _extractPayload(
    Map<String, dynamic> json, {
    Set<String> keys = _payloadKeys,
  }) {
    return {
      for (final key in keys)
        if (json.containsKey(key)) key: json[key],
    };
  }
}
