String normalizeStudioCodexSourceType(String sourceType) {
  return sourceType.trim().toLowerCase().replaceAll('-', '_');
}

bool isStudioCodexSourceType(String sourceType) {
  final normalized = normalizeStudioCodexSourceType(sourceType);
  if (normalized.isEmpty) return false;
  return normalized == 'codex' ||
      normalized == 'legacy_codex' ||
      normalized.startsWith('novalai_codex') ||
      normalized.contains('_codex') ||
      normalized.contains('codex_');
}

bool isAdultStudioCodexSourceType(String sourceType) {
  final normalized = normalizeStudioCodexSourceType(sourceType);
  return isStudioCodexSourceType(normalized) && normalized.contains('adult');
}
