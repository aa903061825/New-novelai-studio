List<String> promptTagsForIndexes(List<String> tags, Set<int> indexes) {
  return [
    for (final index in indexes.toList()..sort())
      if (index >= 0 && index < tags.length) tags[index],
  ];
}

String joinPromptTags(List<String> tags) {
  return tags
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .join(', ');
}

String promptTagsToPrompt(List<String> tags, {String fallback = ''}) {
  final prompt = joinPromptTags(tags);
  return prompt.isEmpty ? fallback.trim() : prompt;
}

int clampPromptTagInsertIndex(int index, List<String> tags) {
  return index.clamp(0, tags.length).toInt();
}
