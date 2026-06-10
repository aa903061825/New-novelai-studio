String sanitizeGenerationPrompt(String prompt) {
  final fragments = prompt.split(',');
  final clean = <String>[];
  for (final fragment in fragments) {
    final trimmed = fragment.trim();
    if (trimmed.isEmpty || isUnsafeGenerationPromptTag(trimmed)) {
      continue;
    }
    clean.add(trimmed);
  }
  return clean.join(', ');
}

List<String> sanitizeGenerationPromptTags(Iterable<String> tags) {
  final clean = <String>[];
  for (final tag in tags) {
    final sanitized = sanitizeGenerationPrompt(tag);
    if (sanitized.isNotEmpty) {
      clean.add(sanitized);
    }
  }
  return List.unmodifiable(clean);
}

bool isUnsafeGenerationPromptTag(String tag) {
  final trimmed = tag.trim();
  if (trimmed.isEmpty) {
    return false;
  }

  final unweighted = _stripNovelAiWeight(trimmed);
  final unwrapped = _stripSquareBrackets(unweighted).trim();
  final compact = unwrapped.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  if (compact.isEmpty) {
    return false;
  }

  if (_isBracketedCjkPlaceholder(trimmed)) {
    return true;
  }
  if (compact.contains(_artistChainLabelCjk)) {
    return true;
  }
  if (compact.contains(_roleLabelCjk)) {
    return true;
  }
  if (_englishDisplayLabelPattern.hasMatch(compact)) {
    return true;
  }
  if (_cjkPattern.hasMatch(compact) &&
      _digitPattern.hasMatch(compact) &&
      compact.length <= 16) {
    return true;
  }
  return false;
}

String _stripNovelAiWeight(String tag) {
  final match = RegExp(r'^[+-]?\d+(?:\.\d+)?::\s*(.*?)\s*::$').firstMatch(tag);
  return match == null ? tag : match.group(1)!;
}

String _stripSquareBrackets(String tag) {
  var current = tag.trim();
  while (
      current.length >= 2 && current.startsWith('[') && current.endsWith(']')) {
    current = current.substring(1, current.length - 1).trim();
  }
  return current;
}

bool _isBracketedCjkPlaceholder(String tag) {
  final trimmed = tag.trim();
  return trimmed.startsWith('[') &&
      trimmed.endsWith(']') &&
      _cjkPattern.hasMatch(trimmed);
}

final _cjkPattern = RegExp(
  '[${String.fromCharCode(0x3400)}-${String.fromCharCode(0x9fff)}]',
);
final _digitPattern = RegExp(r'\d');
final _englishDisplayLabelPattern = RegExp(
  r'^(artist(chain|string|stack|group|mix)|role|character)[a-z]*\d*$',
);
final _artistChainLabelCjk = String.fromCharCodes([0x753b, 0x5e08, 0x4e32]);
final _roleLabelCjk = String.fromCharCodes([0x89d2, 0x8272]);
