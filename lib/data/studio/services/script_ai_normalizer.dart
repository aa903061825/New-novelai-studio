import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

class ScriptAiNormalizer {
  const ScriptAiNormalizer();

  String normalizePromptKey(String text) {
    final parts = PromptTagProcessor.splitWorkshopTags(text)
        .map(PromptTagProcessor.normalizeMatchKey)
        .map((tag) => tag.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' '))
        .map((tag) => tag.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false)
      ..sort();
    return parts.join(',');
  }

  String slottedCacheKey({
    required String roleIdentity,
    required String partText,
  }) {
    return 'role:${normalizePromptKey(roleIdentity)}|part:${normalizePromptKey(partText)}';
  }

  String inlinePromptCacheKey(String prompt) {
    return 'prompt:${normalizePromptKey(prompt)}';
  }
}
