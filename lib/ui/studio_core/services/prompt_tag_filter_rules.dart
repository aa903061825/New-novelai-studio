import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

typedef PromptTagFilterRuleAdder = Future<void> Function(
  List<String> tags,
  PromptTagFilterRuleTarget target,
);

enum PromptTagFilterRuleTarget {
  deleteKeywords,
  strongFilterKeywords,
  replaceSource,
  scriptScopedBlockWords,
}

class PromptTagFilterRulesController {
  final PromptTagFilterRuleAdder addTags;

  const PromptTagFilterRulesController({
    required this.addTags,
  });
}

Future<void> appendTagsToFilterRules({
  required Future<Map<String, dynamic>> Function()? loadFilterRules,
  required Future<void> Function(Map<String, dynamic> rules)? saveFilterRules,
  required List<String> tags,
  required PromptTagFilterRuleTarget target,
}) async {
  final saver = saveFilterRules;
  if (saver == null) {
    return;
  }
  final incoming = normalizeFilterRuleTags(tags);
  if (incoming.isEmpty) {
    return;
  }
  final current =
      loadFilterRules == null ? <String, dynamic>{} : await loadFilterRules();
  final config = FilterRuleConfig.fromMap(current);
  final updated = addTagsToFilterRuleConfig(
    config,
    incoming,
    target,
  );
  await saver({
    ...current,
    ...updated.toMap(),
  });
}

FilterRuleConfig addTagsToFilterRuleConfig(
  FilterRuleConfig config,
  List<String> tags,
  PromptTagFilterRuleTarget target,
) {
  final incoming = normalizeFilterRuleTags(tags);
  return switch (target) {
    PromptTagFilterRuleTarget.deleteKeywords => FilterRuleConfig(
        deleteKeywords: mergeFilterRuleWords(config.deleteKeywords, incoming),
        strongFilterKeywords: config.strongFilterKeywords,
        replaceRules: config.replaceRules,
        removeWeights: config.removeWeights,
        exactMatch: config.exactMatch,
        deleteArtistTags: config.deleteArtistTags,
      ),
    PromptTagFilterRuleTarget.strongFilterKeywords => FilterRuleConfig(
        deleteKeywords: config.deleteKeywords,
        strongFilterKeywords: mergeFilterRuleWords(
          config.strongFilterKeywords,
          incoming,
        ),
        replaceRules: config.replaceRules,
        removeWeights: config.removeWeights,
        exactMatch: config.exactMatch,
        deleteArtistTags: config.deleteArtistTags,
      ),
    PromptTagFilterRuleTarget.replaceSource => FilterRuleConfig(
        deleteKeywords: config.deleteKeywords,
        strongFilterKeywords: config.strongFilterKeywords,
        replaceRules: mergeFilterReplaceSources(config.replaceRules, incoming),
        removeWeights: config.removeWeights,
        exactMatch: config.exactMatch,
        deleteArtistTags: config.deleteArtistTags,
      ),
    PromptTagFilterRuleTarget.scriptScopedBlockWords => config,
  };
}

List<String> normalizeFilterRuleTags(List<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final tag in tags) {
    final text = tag.trim();
    final key = PromptTagProcessor.normalizeMatchKey(text);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(text);
  }
  return result;
}

String mergeFilterRuleWords(String existing, List<String> incoming) {
  final values = <String>[
    ...PromptTagProcessor.splitWorkshopTags(existing),
    ...incoming,
  ];
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final text = value.trim();
    final key = PromptTagProcessor.normalizeMatchKey(text);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(text);
  }
  return result.join(', ');
}

String mergeFilterReplaceSources(String existing, List<String> incoming) {
  final rules = PromptTagProcessor.parseReplaceRulesText(existing);
  final existingSources = {
    for (final rule in rules)
      PromptTagProcessor.normalizeMatchKey(rule.oldValue): rule,
  };
  final lines = [
    for (final rule in rules)
      if (rule.oldValue.trim().isNotEmpty)
        '${rule.oldValue.trim()} -> ${rule.newValue.trim()}',
  ];
  for (final tag in incoming) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (key.isEmpty || existingSources.containsKey(key)) {
      continue;
    }
    existingSources[key] = ReplaceRule(tag, '');
    lines.add('$tag -> ');
  }
  return lines.join('\n');
}
