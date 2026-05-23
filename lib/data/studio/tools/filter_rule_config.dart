class FilterRuleConfig {
  final String deleteKeywords;
  final String strongFilterKeywords;
  final String replaceRules;
  final bool removeWeights;
  final bool exactMatch;
  final bool deleteArtistTags;

  const FilterRuleConfig({
    this.deleteKeywords = '',
    this.strongFilterKeywords = '',
    this.replaceRules = '',
    this.removeWeights = true,
    this.exactMatch = true,
    this.deleteArtistTags = false,
  });

  factory FilterRuleConfig.fromMap(Map<String, dynamic> json) {
    return FilterRuleConfig(
      deleteKeywords: json['delete_keywords'] as String? ?? '',
      strongFilterKeywords: json['strong_filter_keywords'] as String? ?? '',
      replaceRules: json['replace_rules'] as String? ?? '',
      removeWeights: json['remove_weights'] as bool? ?? true,
      exactMatch: json['exact_match'] as bool? ?? true,
      deleteArtistTags: json['delete_artist_tags'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'delete_keywords': deleteKeywords,
      'strong_filter_keywords': strongFilterKeywords,
      'replace_rules': replaceRules,
      'remove_weights': removeWeights,
      'exact_match': exactMatch,
      'delete_artist_tags': deleteArtistTags,
    };
  }
}

class ReplaceRule {
  final String oldValue;
  final String newValue;

  const ReplaceRule(this.oldValue, this.newValue);

  @override
  bool operator ==(Object other) {
    return other is ReplaceRule &&
        other.oldValue == oldValue &&
        other.newValue == newValue;
  }

  @override
  int get hashCode => Object.hash(oldValue, newValue);

  @override
  String toString() => 'ReplaceRule($oldValue -> $newValue)';
}
