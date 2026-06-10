import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';

class PromptTagPresentationItem {
  final int index;
  final String rawTag;
  final String displayLabel;
  final double? weight;
  final String? weightLabel;
  final bool warning;

  const PromptTagPresentationItem({
    required this.index,
    required this.rawTag,
    required this.displayLabel,
    this.weight,
    this.weightLabel,
    this.warning = false,
  });
}

List<PromptTagPresentationItem> promptTagPresentationItems(String value) {
  final result = <PromptTagPresentationItem>[];
  for (final tag in PromptTagProcessor.analyzeWorkshopTags(value.trim())) {
    final displayLabel = tag.displayText.trim();
    if (displayLabel.isEmpty) {
      continue;
    }
    result.add(
      PromptTagPresentationItem(
        index: result.length,
        rawTag: promptTagRawValueForAnalysis(tag),
        displayLabel: displayLabel,
        weight: tag.weight,
        weightLabel: tag.weightLabel,
        warning: tag.warning != WorkshopTagWarning.none,
      ),
    );
  }
  return List.unmodifiable(result);
}

String promptTagRawValueForAnalysis(WorkshopTagAnalysis tag) {
  final raw = tag.text.trim();
  final weight = tag.weight;
  if (weight == null ||
      PromptTagProcessor.hasCompleteNonInlineWeightSyntax(raw)) {
    return raw;
  }
  return PromptTagProcessor.formatInlineWeightTag(
    tag.displayText.trim(),
    weight,
  );
}

PromptTagClassification classifyPromptTagForPresentation(
  String tag, {
  bool negative = false,
  PromptTagClassificationCache? cache,
  Map<String, PromptTagCategory> overrides = const {},
  bool cacheRuleClassification = false,
}) {
  final cleaned = PromptTagProcessor.cleanTagDisplay(tag).trim();
  final manualEntry = cache?.entryFor(cleaned, negative: negative);
  if (manualEntry != null && manualEntry.source.startsWith('manual')) {
    return PromptTagClassification(
      source: cleaned,
      category: manualEntry.category,
      group: PromptTagClassifier.groupFor(manualEntry.category),
    );
  }

  final override = promptTagCategoryOverrideFor(cleaned, overrides);
  if (override != null) {
    return PromptTagClassification(
      source: cleaned,
      category: override,
      group: PromptTagClassifier.groupFor(override),
    );
  }

  final classification = PromptTagClassifier.classify(
    cleaned,
    negative: negative,
    cache: cache,
  );
  final automaticEntry = cache?.entryFor(cleaned, negative: negative);
  final shouldCacheRuleClassification = cacheRuleClassification &&
      cache != null &&
      (automaticEntry == null ||
          automaticEntry.source == 'rules' ||
          (automaticEntry.source == 'legacy' &&
              automaticEntry.category == PromptTagCategory.other));
  if (shouldCacheRuleClassification) {
    cache.setCategory(
      cleaned,
      classification.category,
      source: 'rules',
      negative: negative,
    );
  }
  return classification;
}

PromptTagCategory? promptTagCategoryOverrideFor(
  String tag,
  Map<String, PromptTagCategory> overrides,
) {
  for (final entry in overrides.entries) {
    if (promptTagKeysMatch(entry.key, tag)) {
      return entry.value;
    }
  }
  return null;
}

String promptTagPresentationTranslation(
  String tag, {
  TranslationCache? cache,
  Map<String, String> overrides = const {},
  bool enabled = true,
}) {
  if (!enabled) {
    return '';
  }
  final override = promptTagTranslationOverrideFor(tag, overrides);
  if (override != null && override.trim().isNotEmpty) {
    return override.trim();
  }
  return cache?.translate(tag).text.trim() ?? '';
}

String? promptTagTranslationOverrideFor(
  String tag,
  Map<String, String> overrides,
) {
  final exact = overrides[tag];
  if (exact != null) {
    return exact;
  }
  for (final entry in overrides.entries) {
    if (promptTagKeysMatch(entry.key, tag)) {
      return entry.value;
    }
  }
  return null;
}

bool promptTagKeysMatch(String left, String right) {
  final leftKey = PromptTagProcessor.normalizeMatchKey(left);
  final rightKey = PromptTagProcessor.normalizeMatchKey(right);
  if (leftKey.isEmpty || rightKey.isEmpty) {
    return false;
  }
  if (leftKey == rightKey) {
    return true;
  }
  final leftArtistKey = _stripArtistPrefix(leftKey);
  final rightArtistKey = _stripArtistPrefix(rightKey);
  return leftArtistKey.isNotEmpty && leftArtistKey == rightArtistKey;
}

String _stripArtistPrefix(String key) {
  return key.replaceFirst(RegExp(r'^artist\s*[: ]\s*'), '').trim();
}
