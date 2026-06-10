import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

String deriveCharacterIdentityPromptExcluding(
  CharacterEntry character,
  RecastPromptParts usedParts,
) {
  final usedPartKeys = _promptPartTagKeys(usedParts);
  return _joinPromptTags(
    _withoutSkinVariantAliases([
      ..._explicitIdentityCandidates(
        character.anchorTags,
        excludedKeys: const <String>{},
      ),
      ..._explicitIdentityCandidates(
        character.identityTags,
        excludedKeys: usedPartKeys,
      ),
    ]),
  );
}

Iterable<String> _explicitIdentityCandidates(
  Iterable<String> tags, {
  required Set<String> excludedKeys,
}) sync* {
  for (final tag in _uniqueTags(tags)) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (key.isNotEmpty && !excludedKeys.contains(key)) {
      yield tag;
    }
  }
}

Set<String> _promptPartTagKeys(RecastPromptParts parts) {
  return {
    ..._tagMapForText(parts.upperBody).keys,
    ..._tagMapForText(parts.lowerBody).keys,
    ..._tagMapForText(parts.upperClothing).keys,
    ..._tagMapForText(parts.lowerClothing).keys,
  };
}

Map<String, String> _tagMapForText(String text) {
  return {
    for (final tag in _splitDisplayTags(text))
      PromptTagProcessor.normalizeMatchKey(tag): tag,
  }..remove('');
}

String _joinPromptTags(Iterable<String> tags) {
  return _uniqueTags([
    for (final tag in tags) ..._splitDisplayTags(tag),
  ]).join(', ');
}

Iterable<String> _withoutSkinVariantAliases(Iterable<String> tags) sync* {
  final unique = _uniqueTags([
    for (final tag in tags) ..._splitDisplayTags(tag),
  ]);
  final keys = {
    for (final tag in unique) _metadataTagKey(tag),
  }..remove('');

  for (final tag in unique) {
    final key = _metadataTagKey(tag);
    final baseKey = _skinVariantBaseKey(key);
    if (baseKey != null && keys.contains(baseKey)) {
      continue;
    }
    yield tag;
  }
}

String _metadataTagKey(String tag) {
  return PromptTagProcessor.cleanTagDisplay(tag)
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_');
}

String? _skinVariantBaseKey(String key) {
  final match = RegExp(r'^(.+?)_(?:\([^)]+\)_)+\(([^)]+)\)$').firstMatch(key);
  if (match == null) {
    return null;
  }
  final baseName = match.group(1);
  final series = match.group(2);
  if (baseName == null || series == null) {
    return null;
  }
  return '${baseName}_($series)';
}

List<String> _splitDisplayTags(String text) {
  return PromptTagProcessor.splitWorkshopTags(text)
      .map(PromptTagProcessor.cleanTagDisplay)
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

List<String> _uniqueTags(Iterable<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final tag in tags) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final key = PromptTagProcessor.normalizeMatchKey(trimmed);
    if (key.isNotEmpty && seen.add(key)) {
      result.add(trimmed);
    }
  }
  return List.unmodifiable(result);
}
