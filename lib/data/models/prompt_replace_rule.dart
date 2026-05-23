import 'package:uuid/uuid.dart';

class PromptReplaceRule {
  String id;
  String source;
  String target;
  bool enabled;

  PromptReplaceRule({
    required this.id,
    required this.source,
    required this.target,
    required this.enabled,
  });

  factory PromptReplaceRule.fromJson(Map<String, dynamic> json) {
    return PromptReplaceRule(
      id: json['id']?.toString() ?? const Uuid().v4(),
      source: json['source']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source,
      'target': target,
      'enabled': enabled,
    };
  }

  factory PromptReplaceRule.fromEmpty() {
    return PromptReplaceRule(
      id: const Uuid().v4(),
      source: '',
      target: '',
      enabled: true,
    );
  }

  PromptReplaceRule copyWith({
    String? id,
    String? source,
    String? target,
    bool? enabled,
  }) {
    return PromptReplaceRule(
      id: id ?? this.id,
      source: source ?? this.source,
      target: target ?? this.target,
      enabled: enabled ?? this.enabled,
    );
  }
}
