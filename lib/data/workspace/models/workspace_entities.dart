final Object _omitValue = Object();

Map<String, dynamic> _asMap(dynamic value, String fieldName) {
  if (value == null) return <String, dynamic>{};
  if (value is! Map) {
    throw FormatException('$fieldName must be a JSON object.');
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$fieldName must use string keys.');
    }
    result[key] = entry.value;
  }
  return result;
}

List<dynamic> _asList(dynamic value, String fieldName) {
  if (value == null) return <dynamic>[];
  if (value is List) return value;
  throw FormatException('$fieldName must be a JSON array.');
}

List<String> _stringList(dynamic value, String fieldName) {
  return _asList(value, fieldName).whereType<String>().toList(growable: false);
}

Map<String, dynamic> _dynamicMap(dynamic value, String fieldName) {
  return Map<String, dynamic>.from(_asMap(value, fieldName));
}

Map<String, String> _stringMap(dynamic value, String fieldName) {
  return _asMap(value, fieldName).map(
    (key, value) => MapEntry(key, value is String ? value : '$value'),
  );
}

String _stringValue(
  dynamic value,
  String fieldName, {
  String defaultValue = '',
}) {
  if (value == null) return defaultValue;
  if (value is String) return value;
  throw FormatException('$fieldName must be a string.');
}

String? _optionalStringValue(dynamic value, String fieldName) {
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('$fieldName must be a string.');
}

DateTime _dateTime(dynamic value, String fieldName) {
  if (value == null) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  if (value is! String) {
    throw FormatException('$fieldName must be an ISO-8601 date string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$fieldName must be an ISO-8601 date string.');
  }
  return parsed.toUtc();
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized.contains('apikey') ||
      normalized.contains('token') ||
      normalized.contains('authorization') ||
      normalized.contains('bearer') ||
      normalized.contains('password') ||
      normalized.contains('secret') ||
      normalized.contains('private') ||
      normalized.contains('proxy');
}

bool _isSensitiveString(String value) {
  final trimmed = value.trim().toLowerCase();
  return trimmed.startsWith('bearer ') || trimmed.contains('pst-');
}

Map<String, dynamic> _sanitizeWorkspaceMap(Map<String, dynamic> value) {
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (_isSensitiveKey(entry.key)) continue;
    final sanitized = _sanitizeWorkspaceValue(entry.value);
    if (!identical(sanitized, _omitValue)) {
      result[entry.key] = sanitized;
    }
  }
  return result;
}

dynamic _sanitizeWorkspaceValue(dynamic value) {
  if (value is String && _isSensitiveString(value)) return _omitValue;
  if (value is Map) {
    return _sanitizeWorkspaceMap(_asMap(value, 'nested workspace value'));
  }
  if (value is List) {
    return value
        .map(_sanitizeWorkspaceValue)
        .where((entry) => !identical(entry, _omitValue))
        .toList(growable: false);
  }
  return value;
}

String? _sanitizeWorkspaceString(String value) {
  return _isSensitiveString(value) ? null : value;
}

List<String> _sanitizeWorkspaceStringList(List<String> values) {
  return values
      .where((entry) => _sanitizeWorkspaceString(entry) != null)
      .toList(growable: false);
}

Map<String, String> _sanitizeWorkspaceStringMap(Map<String, String> values) {
  final sanitized = _sanitizeWorkspaceMap(values);
  return sanitized.map((key, value) => MapEntry(key, value.toString()));
}

class SourceRef {
  final String type;
  final String? id;
  final String? path;

  const SourceRef({
    required this.type,
    this.id,
    this.path,
  });

  factory SourceRef.fromJson(dynamic json) {
    final map = _asMap(json, 'source');
    return SourceRef(
      type: _stringValue(map['type'], 'source.type', defaultValue: 'manual'),
      id: _optionalStringValue(map['id'], 'source.id'),
      path: _optionalStringValue(map['path'], 'source.path'),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (id != null) 'id': id,
        if (path != null) 'path': path,
      };
}

class ViewVariantTexts {
  final String frontFull;
  final String? frontCowboy;
  final String? frontUpper;
  final String? frontLower;
  final String? backFull;
  final String? backCowboy;
  final String? backUpper;
  final String? backLower;

  const ViewVariantTexts({
    required this.frontFull,
    this.frontCowboy,
    this.frontUpper,
    this.frontLower,
    this.backFull,
    this.backCowboy,
    this.backUpper,
    this.backLower,
  });

  factory ViewVariantTexts.fromJson(dynamic json) {
    final map = _asMap(json, 'view variants');
    return ViewVariantTexts(
      frontFull: _stringValue(map['front_full'], 'front_full'),
      frontCowboy: _optionalStringValue(map['front_cowboy'], 'front_cowboy'),
      frontUpper: _optionalStringValue(map['front_upper'], 'front_upper'),
      frontLower: _optionalStringValue(map['front_lower'], 'front_lower'),
      backFull: _optionalStringValue(map['back_full'], 'back_full'),
      backCowboy: _optionalStringValue(map['back_cowboy'], 'back_cowboy'),
      backUpper: _optionalStringValue(map['back_upper'], 'back_upper'),
      backLower: _optionalStringValue(map['back_lower'], 'back_lower'),
    );
  }

  Map<String, dynamic> toJson() => {
        'front_full': _sanitizeWorkspaceString(frontFull) ?? '',
        if (frontCowboy != null &&
            _sanitizeWorkspaceString(frontCowboy!) != null)
          'front_cowboy': frontCowboy,
        if (frontUpper != null && _sanitizeWorkspaceString(frontUpper!) != null)
          'front_upper': frontUpper,
        if (frontLower != null && _sanitizeWorkspaceString(frontLower!) != null)
          'front_lower': frontLower,
        if (backFull != null && _sanitizeWorkspaceString(backFull!) != null)
          'back_full': backFull,
        if (backCowboy != null && _sanitizeWorkspaceString(backCowboy!) != null)
          'back_cowboy': backCowboy,
        if (backUpper != null && _sanitizeWorkspaceString(backUpper!) != null)
          'back_upper': backUpper,
        if (backLower != null && _sanitizeWorkspaceString(backLower!) != null)
          'back_lower': backLower,
      };
}

class WorkspaceOutfit {
  final String id;
  final String name;
  final ViewVariantTexts tags;
  final List<String> imageRefs;
  final String note;

  const WorkspaceOutfit({
    required this.id,
    required this.name,
    required this.tags,
    this.imageRefs = const [],
    this.note = '',
  });

  factory WorkspaceOutfit.fromJson(dynamic json) {
    final map = _asMap(json, 'outfit');
    return WorkspaceOutfit(
      id: _stringValue(map['id'], 'outfit.id'),
      name: _stringValue(map['name'], 'outfit.name'),
      tags: ViewVariantTexts.fromJson(map['tags']),
      imageRefs: _stringList(map['imageRefs'], 'outfit.imageRefs'),
      note: _stringValue(map['note'], 'outfit.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tags': tags.toJson(),
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class CharacterEntry {
  final String id;
  final String name;
  final ViewVariantTexts traits;
  final List<WorkspaceOutfit> outfits;
  final String? defaultOutfitId;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const CharacterEntry({
    required this.id,
    required this.name,
    required this.traits,
    this.outfits = const [],
    this.defaultOutfitId,
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory CharacterEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'character');
    return CharacterEntry(
      id: _stringValue(map['id'], 'character.id'),
      name: _stringValue(map['name'], 'character.name'),
      traits: ViewVariantTexts.fromJson(map['traits']),
      outfits: _asList(map['outfits'], 'character.outfits')
          .map(WorkspaceOutfit.fromJson)
          .toList(growable: false),
      defaultOutfitId: _optionalStringValue(
        map['defaultOutfitId'],
        'character.defaultOutfitId',
      ),
      imageRefs: _stringList(map['imageRefs'], 'character.imageRefs'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'character.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'traits': traits.toJson(),
        'outfits': outfits.map((outfit) => outfit.toJson()).toList(),
        if (defaultOutfitId != null) 'defaultOutfitId': defaultOutfitId,
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class Recipe {
  final String id;
  final String name;
  final String block;
  final String category;
  final String group;
  final String tags;
  final Map<String, String> variants;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const Recipe({
    required this.id,
    required this.name,
    required this.block,
    this.category = '',
    this.group = '',
    this.tags = '',
    this.variants = const {},
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory Recipe.fromJson(dynamic json) {
    final map = _asMap(json, 'recipe');
    return Recipe(
      id: _stringValue(map['id'], 'recipe.id'),
      name: _stringValue(map['name'], 'recipe.name'),
      block: _stringValue(map['block'], 'recipe.block'),
      category: _stringValue(map['category'], 'recipe.category'),
      group: _stringValue(map['group'], 'recipe.group'),
      tags: _stringValue(map['tags'], 'recipe.tags'),
      variants: _stringMap(map['variants'], 'recipe.variants'),
      imageRefs: _stringList(map['imageRefs'], 'recipe.imageRefs'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'recipe.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'block': block,
        if (category.isNotEmpty) 'category': category,
        if (group.isNotEmpty) 'group': group,
        if (tags.isNotEmpty && _sanitizeWorkspaceString(tags) != null)
          'tags': tags,
        if (_sanitizeWorkspaceStringMap(variants).isNotEmpty)
          'variants': _sanitizeWorkspaceStringMap(variants),
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class TagEntry {
  final String id;
  final String tag;
  final String zh;
  final String block;
  final String category;
  final List<String> aliases;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const TagEntry({
    required this.id,
    required this.tag,
    this.zh = '',
    required this.block,
    this.category = '',
    this.aliases = const [],
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory TagEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'tag entry');
    final tag = _stringValue(map['tag'], 'tag.tag');
    return TagEntry(
      id: _stringValue(map['id'], 'tag.id', defaultValue: tag),
      tag: tag,
      zh: _stringValue(map['zh'] ?? map['name_zh'], 'tag.zh'),
      block: _stringValue(map['block'], 'tag.block'),
      category: _stringValue(map['category'], 'tag.category'),
      aliases: _stringList(map['aliases'], 'tag.aliases'),
      imageRefs: _stringList(map['imageRefs'], 'tag.imageRefs'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'tag.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tag': tag,
        if (zh.isNotEmpty) 'zh': zh,
        'block': block,
        if (category.isNotEmpty) 'category': category,
        if (_sanitizeWorkspaceStringList(aliases).isNotEmpty)
          'aliases': _sanitizeWorkspaceStringList(aliases),
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class ArtistChain {
  final String id;
  final String name;
  final List<String> tags;
  final String prompt;
  final List<String> styleTags;
  final List<String> imageRefs;
  final Map<String, String> translations;
  final SourceRef source;
  final String note;

  const ArtistChain({
    required this.id,
    required this.name,
    this.tags = const [],
    this.prompt = '',
    this.styleTags = const [],
    this.imageRefs = const [],
    this.translations = const {},
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory ArtistChain.fromJson(dynamic json) {
    final map = _asMap(json, 'artist chain');
    return ArtistChain(
      id: _stringValue(map['id'], 'artistChain.id'),
      name: _stringValue(map['name'], 'artistChain.name'),
      tags: _stringList(map['tags'], 'artistChain.tags'),
      prompt: _stringValue(map['prompt'], 'artistChain.prompt'),
      styleTags: _stringList(map['styleTags'], 'artistChain.styleTags'),
      imageRefs: _stringList(map['imageRefs'], 'artistChain.imageRefs'),
      translations: _stringMap(map['translations'], 'artistChain.translations'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'artistChain.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (_sanitizeWorkspaceStringList(tags).isNotEmpty)
          'tags': _sanitizeWorkspaceStringList(tags),
        if (prompt.isNotEmpty && _sanitizeWorkspaceString(prompt) != null)
          'prompt': prompt,
        if (_sanitizeWorkspaceStringList(styleTags).isNotEmpty)
          'styleTags': _sanitizeWorkspaceStringList(styleTags),
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        if (_sanitizeWorkspaceStringMap(translations).isNotEmpty)
          'translations': _sanitizeWorkspaceStringMap(translations),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class InspirationEntry {
  final String id;
  final String name;
  final String prompt;
  final String negativePrompt;
  final List<String> tags;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const InspirationEntry({
    required this.id,
    required this.name,
    this.prompt = '',
    this.negativePrompt = '',
    this.tags = const [],
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory InspirationEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'inspiration');
    return InspirationEntry(
      id: _stringValue(map['id'], 'inspiration.id'),
      name: _stringValue(map['name'], 'inspiration.name'),
      prompt: _stringValue(map['prompt'], 'inspiration.prompt'),
      negativePrompt: _stringValue(
        map['negativePrompt'],
        'inspiration.negativePrompt',
      ),
      tags: _stringList(map['tags'], 'inspiration.tags'),
      imageRefs: _stringList(map['imageRefs'], 'inspiration.imageRefs'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'inspiration.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (prompt.isNotEmpty && _sanitizeWorkspaceString(prompt) != null)
          'prompt': prompt,
        if (negativePrompt.isNotEmpty &&
            _sanitizeWorkspaceString(negativePrompt) != null)
          'negativePrompt': negativePrompt,
        if (_sanitizeWorkspaceStringList(tags).isNotEmpty)
          'tags': _sanitizeWorkspaceStringList(tags),
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class LoraEntry {
  final String id;
  final String name;
  final String baseModel;
  final List<String> triggerWords;
  final double? defaultStrength;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const LoraEntry({
    required this.id,
    required this.name,
    this.baseModel = '',
    this.triggerWords = const [],
    this.defaultStrength,
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory LoraEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'lora');
    return LoraEntry(
      id: _stringValue(map['id'], 'lora.id'),
      name: _stringValue(map['name'], 'lora.name'),
      baseModel: _stringValue(map['baseModel'], 'lora.baseModel'),
      triggerWords: _stringList(map['triggerWords'], 'lora.triggerWords'),
      defaultStrength: switch (map['defaultStrength']) {
        final num value => value.toDouble(),
        _ => null,
      },
      imageRefs: _stringList(map['imageRefs'], 'lora.imageRefs'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'lora.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (baseModel.isNotEmpty) 'baseModel': baseModel,
        if (_sanitizeWorkspaceStringList(triggerWords).isNotEmpty)
          'triggerWords': _sanitizeWorkspaceStringList(triggerWords),
        if (defaultStrength != null) 'defaultStrength': defaultStrength,
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class WorkflowEntry {
  final String id;
  final String name;
  final String summary;
  final List<String> imageRefs;
  final Map<String, dynamic> payload;
  final SourceRef source;
  final String note;

  const WorkflowEntry({
    required this.id,
    required this.name,
    this.summary = '',
    this.imageRefs = const [],
    this.payload = const {},
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory WorkflowEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'workflow');
    return WorkflowEntry(
      id: _stringValue(map['id'], 'workflow.id'),
      name: _stringValue(map['name'], 'workflow.name'),
      summary: _stringValue(map['summary'], 'workflow.summary'),
      imageRefs: _stringList(map['imageRefs'], 'workflow.imageRefs'),
      payload: _dynamicMap(map['payload'], 'workflow.payload'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'workflow.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (summary.isNotEmpty && _sanitizeWorkspaceString(summary) != null)
          'summary': summary,
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        if (payload.isNotEmpty) 'payload': _sanitizeWorkspaceMap(payload),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class AssemblyPresetEntry {
  final String id;
  final String name;
  final String summary;
  final List<String> imageRefs;
  final Map<String, dynamic> payload;
  final SourceRef source;
  final String note;

  const AssemblyPresetEntry({
    required this.id,
    required this.name,
    this.summary = '',
    this.imageRefs = const [],
    this.payload = const {},
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory AssemblyPresetEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'assembly preset');
    return AssemblyPresetEntry(
      id: _stringValue(map['id'], 'assemblyPreset.id'),
      name: _stringValue(map['name'], 'assemblyPreset.name'),
      summary: _stringValue(map['summary'], 'assemblyPreset.summary'),
      imageRefs: _stringList(map['imageRefs'], 'assemblyPreset.imageRefs'),
      payload: _dynamicMap(map['payload'], 'assemblyPreset.payload'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'assemblyPreset.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (summary.isNotEmpty && _sanitizeWorkspaceString(summary) != null)
          'summary': summary,
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        if (payload.isNotEmpty) 'payload': _sanitizeWorkspaceMap(payload),
        'source': source.toJson(),
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class WorkspacePromptConfig {
  final String id;
  final String name;
  final Map<String, dynamic> rootConfig;
  final List<Map<String, dynamic>> savedBlocks;
  final List<String> replaceRuleIds;
  final String? generationProfileId;

  const WorkspacePromptConfig({
    required this.id,
    required this.name,
    required this.rootConfig,
    this.savedBlocks = const [],
    this.replaceRuleIds = const [],
    this.generationProfileId,
  });

  factory WorkspacePromptConfig.fromJson(dynamic json) {
    final map = _asMap(json, 'prompt config');
    return WorkspacePromptConfig(
      id: _stringValue(map['id'], 'promptConfig.id'),
      name: _stringValue(map['name'], 'promptConfig.name'),
      rootConfig: _dynamicMap(map['rootConfig'], 'promptConfig.rootConfig'),
      savedBlocks: _asList(map['savedBlocks'], 'promptConfig.savedBlocks')
          .map((block) => _dynamicMap(block, 'promptConfig.savedBlocks[]'))
          .toList(growable: false),
      replaceRuleIds:
          _stringList(map['replaceRuleIds'], 'promptConfig.replaceRuleIds'),
      generationProfileId: _optionalStringValue(
        map['generationProfileId'],
        'promptConfig.generationProfileId',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootConfig': _sanitizeWorkspaceMap(rootConfig),
        'savedBlocks': savedBlocks
            .map(_sanitizeWorkspaceMap)
            .toList(growable: false),
        if (replaceRuleIds.isNotEmpty) 'replaceRuleIds': replaceRuleIds,
        if (generationProfileId != null)
          'generationProfileId': generationProfileId,
      };
}

class GenerationProfile {
  final String id;
  final String name;
  final Map<String, dynamic> params;
  final String negativePrompt;
  final List<String> vibeRefs;
  final List<String> preciseReferenceRefs;
  final Map<String, dynamic> batchDefaults;
  final String? secretRef;

  const GenerationProfile({
    required this.id,
    required this.name,
    this.params = const {},
    this.negativePrompt = '',
    this.vibeRefs = const [],
    this.preciseReferenceRefs = const [],
    this.batchDefaults = const {},
    this.secretRef,
  });

  factory GenerationProfile.fromJson(dynamic json) {
    final map = _asMap(json, 'generation profile');
    return GenerationProfile(
      id: _stringValue(map['id'], 'generationProfile.id'),
      name: _stringValue(map['name'], 'generationProfile.name'),
      params: _dynamicMap(map['params'], 'generationProfile.params'),
      negativePrompt: _stringValue(
        map['negativePrompt'],
        'generationProfile.negativePrompt',
      ),
      vibeRefs: _stringList(map['vibeRefs'], 'generationProfile.vibeRefs'),
      preciseReferenceRefs: _stringList(
        map['preciseReferenceRefs'],
        'generationProfile.preciseReferenceRefs',
      ),
      batchDefaults:
          _dynamicMap(map['batchDefaults'], 'generationProfile.batchDefaults'),
      secretRef: _optionalStringValue(
        map['secretRef'],
        'generationProfile.secretRef',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (params.isNotEmpty) 'params': _sanitizeWorkspaceMap(params),
        if (negativePrompt.isNotEmpty) 'negativePrompt': negativePrompt,
        if (vibeRefs.isNotEmpty) 'vibeRefs': vibeRefs,
        if (preciseReferenceRefs.isNotEmpty)
          'preciseReferenceRefs': preciseReferenceRefs,
        if (batchDefaults.isNotEmpty)
          'batchDefaults': _sanitizeWorkspaceMap(batchDefaults),
        if (secretRef != null) 'secretRef': secretRef,
      };
}

class BatchPlan {
  final String id;
  final String name;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> statusSnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BatchPlan({
    required this.id,
    required this.name,
    this.items = const [],
    this.statusSnapshot = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory BatchPlan.fromJson(dynamic json) {
    final map = _asMap(json, 'batch plan');
    return BatchPlan(
      id: _stringValue(map['id'], 'batchPlan.id'),
      name: _stringValue(map['name'], 'batchPlan.name'),
      items: _asList(map['items'], 'batchPlan.items')
          .map((item) => _dynamicMap(item, 'batchPlan.items[]'))
          .toList(growable: false),
      statusSnapshot:
          _dynamicMap(map['statusSnapshot'], 'batchPlan.statusSnapshot'),
      createdAt: _dateTime(map['createdAt'], 'batchPlan.createdAt'),
      updatedAt: _dateTime(map['updatedAt'], 'batchPlan.updatedAt'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (items.isNotEmpty)
          'items': items.map(_sanitizeWorkspaceMap).toList(growable: false),
        if (statusSnapshot.isNotEmpty)
          'statusSnapshot': _sanitizeWorkspaceMap(statusSnapshot),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}
