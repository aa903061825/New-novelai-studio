import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

String deriveOutfitIdentityPrompt(WorkspaceOutfit? outfit) {
  return _joinUniqueTags(deriveOutfitIdentityTags(outfit));
}

List<String> deriveOutfitIdentityTags(WorkspaceOutfit? outfit) {
  if (outfit == null || _isDefaultOutfit(outfit)) {
    return const [];
  }
  final records = _identityRecords(outfit.tags.frontFull);
  final byKey = {
    for (final record in records) record.key: record,
  };
  final result = <String>[];
  for (final record in records) {
    final baseKey = _skinVariantBaseKey(record.key);
    if (baseKey == null) {
      continue;
    }
    final baseRecord = byKey[baseKey];
    if (baseRecord != null) {
      result.add(baseRecord.display);
    } else {
      result.add(_skinVariantBaseDisplay(record.display));
    }
    result.add(record.display);
  }
  if (result.isNotEmpty) {
    return _uniqueTags(result);
  }
  return _uniqueTags(records.map((record) => record.display));
}

String deriveSelectedOutfitIdentityPrompt(
  WorkspaceOutfit? upperOutfit,
  WorkspaceOutfit? lowerOutfit,
) {
  return _joinUniqueTags([
    ...deriveOutfitIdentityTags(upperOutfit),
    ...deriveOutfitIdentityTags(lowerOutfit),
  ]);
}

bool hasOutfitIdentityPrompt(WorkspaceOutfit? outfit) {
  return deriveOutfitIdentityTags(outfit).isNotEmpty;
}

String mergeBaseAndOutfitIdentity(
  String baseIdentity,
  String outfitIdentity,
) {
  final outfitTags = _splitPromptTags(outfitIdentity);
  final replacementBaseKeys = {
    for (final tag in outfitTags)
      if (_skinVariantBaseKey(_metadataTagKey(tag)) case final baseKey?)
        baseKey,
  };
  final baseTags = <String>[];
  for (final tag in _splitPromptTags(baseIdentity)) {
    final baseKey = _skinVariantBaseKey(_metadataTagKey(tag));
    if (baseKey != null && replacementBaseKeys.contains(baseKey)) {
      continue;
    }
    baseTags.add(tag);
  }
  return _joinUniqueTags([...baseTags, ...outfitTags]);
}

bool _isDefaultOutfit(WorkspaceOutfit outfit) {
  final id = outfit.id.trim().toLowerCase();
  final name = outfit.name.trim().toLowerCase();
  return id == 'default' ||
      id == 'default-outfit' ||
      name == 'default' ||
      name == 'default outfit';
}

List<_IdentityRecord> _identityRecords(String text) {
  final result = <_IdentityRecord>[];
  for (final tag in _splitPromptTags(text)) {
    final display = _displayTagPreservingWeights(tag);
    final key = _metadataTagKey(display);
    if (key.isEmpty || !_isMetadataCharacterTag(key)) {
      continue;
    }
    result.add(_IdentityRecord(display: display, key: key));
  }
  return result;
}

List<String> _splitPromptTags(String text) {
  return PromptTagProcessor.splitWorkshopTags(text)
      .map(_displayTagPreservingWeights)
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

String _displayTagPreservingWeights(String tag) {
  return PromptTagProcessor.cleanTagDisplay(tag, removeWeights: false).trim();
}

bool _isMetadataCharacterTag(String key) {
  return RegExp(r'^[a-z0-9][a-z0-9_]*(?:_\([^)]+\))+$').hasMatch(key);
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

String _skinVariantBaseDisplay(String display) {
  final descriptor = PromptTagProcessor.describeWorkshopTag(display);
  final value = descriptor.displayText.trim();
  final match = RegExp(r'^(.+?)([_\s])(?:\([^()]+\)[_\s])+\(([^()]+)\)$')
      .firstMatch(value);
  if (match == null) return display;
  final baseName = match.group(1)?.trim();
  final series = match.group(3)?.trim();
  if (baseName == null ||
      baseName.isEmpty ||
      series == null ||
      series.isEmpty) {
    return display;
  }
  final separator = match.group(2) == '_' ? '_' : ' ';
  final baseDisplay = '$baseName$separator($series)';
  final weight = descriptor.weight;
  if (weight == null) return baseDisplay;
  return PromptTagProcessor.formatInlineWeightTag(baseDisplay, weight);
}

String _joinUniqueTags(Iterable<String> tags) {
  return _uniqueTags(tags).join(', ');
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

class _IdentityRecord {
  final String display;
  final String key;

  const _IdentityRecord({
    required this.display,
    required this.key,
  });
}
