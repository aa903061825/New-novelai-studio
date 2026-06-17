import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/tools/generation_prompt_sanitizer.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

class ScriptPromptReplacementEngine {
  const ScriptPromptReplacementEngine();

  String applyRules({
    required String prompt,
    required int frameIndex,
    required List<ScriptPromptReplacementRule> rules,
  }) {
    var tags = PromptTagProcessor.splitWorkshopTags(prompt);
    var changed = false;
    for (final rule in rules) {
      final application = _applyRule(tags, frameIndex, rule);
      tags = application.tags;
      changed = changed || application.changed;
    }
    if (!changed) {
      return prompt;
    }
    return sanitizeGenerationPrompt(tags.join(', '));
  }

  _RuleApplication _applyRule(
    List<String> tags,
    int frameIndex,
    ScriptPromptReplacementRule rule,
  ) {
    final action = rule.effectiveAction;
    if (action == ScriptPromptReplacementAction.none) {
      return _RuleApplication.unchanged(tags);
    }

    final includedTerms = _includedTerms(rule);
    if (includedTerms.isEmpty ||
        !_ruleCanApplyToFrame(includedTerms, frameIndex)) {
      return _RuleApplication.unchanged(tags);
    }

    final eligibleTerms = [
      for (final term in includedTerms)
        if (_termCanApplyToFrame(term, frameIndex)) _TermMatch.fromTerm(term),
    ].where((term) => term.key.isNotEmpty).toList(growable: false);
    if (eligibleTerms.isEmpty) {
      return _RuleApplication.unchanged(tags);
    }

    final tagKeys = [
      for (final tag in tags) PromptTagProcessor.normalizeMatchKey(tag),
    ];
    final presentTagKeys = tagKeys.toSet();
    final presentSourceKeys = {
      for (final term in eligibleTerms)
        if (presentTagKeys.contains(term.key)) term.key,
    };
    if (!_matchesRule(rule, eligibleTerms, presentSourceKeys)) {
      return _RuleApplication.unchanged(tags);
    }

    final keysToRemove = _keysToRemove(rule, eligibleTerms, presentSourceKeys);
    if (keysToRemove.isEmpty) {
      return _RuleApplication.unchanged(tags);
    }

    final remaining = <String>[];
    int? insertionIndex;
    for (var index = 0; index < tags.length; index += 1) {
      if (keysToRemove.contains(tagKeys[index])) {
        insertionIndex ??= remaining.length;
        continue;
      }
      remaining.add(tags[index]);
    }

    if (action == ScriptPromptReplacementAction.delete) {
      return _RuleApplication.changed(remaining);
    }

    final replacementTags = _replacementTags(rule, remaining);
    if (replacementTags.isEmpty) {
      return _RuleApplication.changed(remaining);
    }

    final next = [...remaining];
    next.insertAll(insertionIndex ?? next.length, replacementTags);
    return _RuleApplication.changed(next);
  }

  List<ScriptPromptReplacementTerm> _includedTerms(
    ScriptPromptReplacementRule rule,
  ) {
    final excluded = rule.excludedTermIds.toSet();
    return [
      for (final term in rule.sourceTerms)
        if (!excluded.contains(term.id)) term,
    ];
  }

  bool _ruleCanApplyToFrame(
    List<ScriptPromptReplacementTerm> terms,
    int frameIndex,
  ) {
    final scopedTerms = terms.where((term) => term.frameIndexes.isNotEmpty);
    if (scopedTerms.isEmpty) {
      return true;
    }
    return scopedTerms.any((term) => term.frameIndexes.contains(frameIndex));
  }

  bool _termCanApplyToFrame(
    ScriptPromptReplacementTerm term,
    int frameIndex,
  ) {
    return term.frameIndexes.isEmpty || term.frameIndexes.contains(frameIndex);
  }

  bool _matchesRule(
    ScriptPromptReplacementRule rule,
    List<_TermMatch> eligibleTerms,
    Set<String> presentSourceKeys,
  ) {
    switch (rule.matchMode) {
      case ScriptPromptReplacementMatchMode.any:
        return presentSourceKeys.isNotEmpty;
      case ScriptPromptReplacementMatchMode.all:
        return {
          for (final term in eligibleTerms) term.key,
        }.every(presentSourceKeys.contains);
      case ScriptPromptReplacementMatchMode.anchor:
        final anchor = _anchorTerm(rule, eligibleTerms);
        return anchor != null && presentSourceKeys.contains(anchor.key);
    }
  }

  Set<String> _keysToRemove(
    ScriptPromptReplacementRule rule,
    List<_TermMatch> eligibleTerms,
    Set<String> presentSourceKeys,
  ) {
    switch (rule.matchMode) {
      case ScriptPromptReplacementMatchMode.any:
      case ScriptPromptReplacementMatchMode.anchor:
        return presentSourceKeys;
      case ScriptPromptReplacementMatchMode.all:
        return {
          for (final term in eligibleTerms) term.key,
        };
    }
  }

  _TermMatch? _anchorTerm(
    ScriptPromptReplacementRule rule,
    List<_TermMatch> eligibleTerms,
  ) {
    final anchorTermId = rule.anchorTermId.trim();
    if (anchorTermId.isNotEmpty) {
      for (final term in eligibleTerms) {
        if (term.id == anchorTermId) {
          return term;
        }
      }
      return null;
    }
    return eligibleTerms.isEmpty ? null : eligibleTerms.first;
  }

  List<String> _replacementTags(
    ScriptPromptReplacementRule rule,
    List<String> remaining,
  ) {
    final output = rule.manualPhrase.trim().isNotEmpty
        ? rule.manualPhrase
        : rule.targetPrompt;
    final existingKeys = {
      for (final tag in remaining) PromptTagProcessor.normalizeMatchKey(tag),
    };
    final replacementKeys = <String>{};
    final result = <String>[];
    for (final tag in sanitizeGenerationPromptTags(
        PromptTagProcessor.splitWorkshopTags(output))) {
      final key = PromptTagProcessor.normalizeMatchKey(tag);
      if (key.isEmpty ||
          existingKeys.contains(key) ||
          replacementKeys.contains(key)) {
        continue;
      }
      replacementKeys.add(key);
      result.add(tag);
    }
    return result;
  }
}

class _RuleApplication {
  final List<String> tags;
  final bool changed;

  const _RuleApplication({
    required this.tags,
    required this.changed,
  });

  factory _RuleApplication.unchanged(List<String> tags) {
    return _RuleApplication(tags: tags, changed: false);
  }

  factory _RuleApplication.changed(List<String> tags) {
    return _RuleApplication(tags: tags, changed: true);
  }
}

class _TermMatch {
  final String id;
  final String key;

  const _TermMatch({
    required this.id,
    required this.key,
  });

  factory _TermMatch.fromTerm(ScriptPromptReplacementTerm term) {
    return _TermMatch(
      id: term.id,
      key: PromptTagProcessor.normalizeMatchKey(term.text),
    );
  }
}
