const Object _omitValue = Object();

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

double _doubleValue(
  dynamic value,
  String fieldName, {
  double defaultValue = 0,
}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  throw FormatException('$fieldName must be a number.');
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

class WorkspaceOutfitPartTags {
  final List<String> upperBodyTags;
  final List<String> upperClothingTags;
  final List<String> lowerBodyTags;
  final List<String> lowerClothingTags;
  final List<String> weaponTags;

  const WorkspaceOutfitPartTags({
    this.upperBodyTags = const [],
    this.upperClothingTags = const [],
    this.lowerBodyTags = const [],
    this.lowerClothingTags = const [],
    this.weaponTags = const [],
  });

  factory WorkspaceOutfitPartTags.fromJson(dynamic json) {
    final map = _asMap(json, 'outfit.partTags');
    return WorkspaceOutfitPartTags(
      upperBodyTags: _stringList(
        map['upperBodyTags'],
        'outfit.partTags.upperBodyTags',
      ),
      upperClothingTags: _stringList(
        map['upperClothingTags'],
        'outfit.partTags.upperClothingTags',
      ),
      lowerBodyTags: _stringList(
        map['lowerBodyTags'],
        'outfit.partTags.lowerBodyTags',
      ),
      lowerClothingTags: _stringList(
        map['lowerClothingTags'],
        'outfit.partTags.lowerClothingTags',
      ),
      weaponTags: _stringList(
        map['weaponTags'],
        'outfit.partTags.weaponTags',
      ),
    );
  }

  bool get isEmpty =>
      upperBodyTags.isEmpty &&
      upperClothingTags.isEmpty &&
      lowerBodyTags.isEmpty &&
      lowerClothingTags.isEmpty &&
      weaponTags.isEmpty;

  Map<String, dynamic> toJson() => {
        if (_sanitizeWorkspaceStringList(upperBodyTags).isNotEmpty)
          'upperBodyTags': _sanitizeWorkspaceStringList(upperBodyTags),
        if (_sanitizeWorkspaceStringList(upperClothingTags).isNotEmpty)
          'upperClothingTags': _sanitizeWorkspaceStringList(upperClothingTags),
        if (_sanitizeWorkspaceStringList(lowerBodyTags).isNotEmpty)
          'lowerBodyTags': _sanitizeWorkspaceStringList(lowerBodyTags),
        if (_sanitizeWorkspaceStringList(lowerClothingTags).isNotEmpty)
          'lowerClothingTags': _sanitizeWorkspaceStringList(lowerClothingTags),
        if (_sanitizeWorkspaceStringList(weaponTags).isNotEmpty)
          'weaponTags': _sanitizeWorkspaceStringList(weaponTags),
      };
}

class WorkspaceOutfit {
  final String id;
  final String name;
  final ViewVariantTexts tags;
  final WorkspaceOutfitPartTags partTags;
  final List<String> imageRefs;
  final String negativePrompt;
  final String note;

  const WorkspaceOutfit({
    required this.id,
    required this.name,
    required this.tags,
    this.partTags = const WorkspaceOutfitPartTags(),
    this.imageRefs = const [],
    this.negativePrompt = '',
    this.note = '',
  });

  factory WorkspaceOutfit.fromJson(dynamic json) {
    final map = _asMap(json, 'outfit');
    return WorkspaceOutfit(
      id: _stringValue(map['id'], 'outfit.id'),
      name: _stringValue(map['name'], 'outfit.name'),
      tags: ViewVariantTexts.fromJson(map['tags']),
      partTags: WorkspaceOutfitPartTags.fromJson(map['partTags']),
      imageRefs: _stringList(map['imageRefs'], 'outfit.imageRefs'),
      negativePrompt: _stringValue(
        map['negativePrompt'],
        'outfit.negativePrompt',
      ),
      note: _stringValue(map['note'], 'outfit.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tags': tags.toJson(),
        if (!partTags.isEmpty) 'partTags': partTags.toJson(),
        if (_sanitizeWorkspaceStringList(imageRefs).isNotEmpty)
          'imageRefs': _sanitizeWorkspaceStringList(imageRefs),
        if (negativePrompt.isNotEmpty &&
            _sanitizeWorkspaceString(negativePrompt) != null)
          'negativePrompt': negativePrompt,
        if (note.isNotEmpty && _sanitizeWorkspaceString(note) != null)
          'note': note,
      };
}

class WorkspacePoint {
  final double x;
  final double y;

  const WorkspacePoint({required this.x, required this.y});

  factory WorkspacePoint.fromJson(dynamic json) {
    final map = _asMap(json, 'workspace point');
    return WorkspacePoint(
      x: _doubleValue(map['x'], 'workspacePoint.x'),
      y: _doubleValue(map['y'], 'workspacePoint.y'),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspacePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
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
  final List<String> anchorTags;
  final List<String> identityTags;
  final List<String> conflictTags;
  final List<WorkspacePoint> defaultCenters;
  final List<String> aliases;
  final String recastNotes;

  const CharacterEntry({
    required this.id,
    required this.name,
    required this.traits,
    this.outfits = const [],
    this.defaultOutfitId,
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
    this.anchorTags = const [],
    this.identityTags = const [],
    this.conflictTags = const [],
    this.defaultCenters = const [],
    this.aliases = const [],
    this.recastNotes = '',
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
      anchorTags: _stringList(map['anchorTags'], 'character.anchorTags'),
      identityTags: _stringList(map['identityTags'], 'character.identityTags'),
      conflictTags: _stringList(map['conflictTags'], 'character.conflictTags'),
      defaultCenters: _asList(
        map['defaultCenters'],
        'character.defaultCenters',
      ).map(WorkspacePoint.fromJson).toList(growable: false),
      aliases: _stringList(map['aliases'], 'character.aliases'),
      recastNotes: _stringValue(map['recastNotes'], 'character.recastNotes'),
    );
  }

  CharacterEntry copyWith({
    String? id,
    String? name,
    ViewVariantTexts? traits,
    List<WorkspaceOutfit>? outfits,
    Object? defaultOutfitId = _omitValue,
    List<String>? imageRefs,
    SourceRef? source,
    String? note,
    List<String>? anchorTags,
    List<String>? identityTags,
    List<String>? conflictTags,
    List<WorkspacePoint>? defaultCenters,
    List<String>? aliases,
    String? recastNotes,
  }) {
    return CharacterEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      traits: traits ?? this.traits,
      outfits: outfits ?? this.outfits,
      defaultOutfitId: identical(defaultOutfitId, _omitValue)
          ? this.defaultOutfitId
          : defaultOutfitId as String?,
      imageRefs: imageRefs ?? this.imageRefs,
      source: source ?? this.source,
      note: note ?? this.note,
      anchorTags: anchorTags ?? this.anchorTags,
      identityTags: identityTags ?? this.identityTags,
      conflictTags: conflictTags ?? this.conflictTags,
      defaultCenters: defaultCenters ?? this.defaultCenters,
      aliases: aliases ?? this.aliases,
      recastNotes: recastNotes ?? this.recastNotes,
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
        if (_sanitizeWorkspaceStringList(anchorTags).isNotEmpty)
          'anchorTags': _sanitizeWorkspaceStringList(anchorTags),
        if (_sanitizeWorkspaceStringList(identityTags).isNotEmpty)
          'identityTags': _sanitizeWorkspaceStringList(identityTags),
        if (_sanitizeWorkspaceStringList(conflictTags).isNotEmpty)
          'conflictTags': _sanitizeWorkspaceStringList(conflictTags),
        if (defaultCenters.isNotEmpty)
          'defaultCenters':
              defaultCenters.map((center) => center.toJson()).toList(),
        if (_sanitizeWorkspaceStringList(aliases).isNotEmpty)
          'aliases': _sanitizeWorkspaceStringList(aliases),
        if (recastNotes.isNotEmpty &&
            _sanitizeWorkspaceString(recastNotes) != null)
          'recastNotes': recastNotes,
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

class WorkspaceWeightedTag {
  final String tag;
  final double weight;

  const WorkspaceWeightedTag({required this.tag, required this.weight});

  factory WorkspaceWeightedTag.fromJson(dynamic json) {
    final map = _asMap(json, 'weighted tag');
    return WorkspaceWeightedTag(
      tag: _stringValue(map['tag'], 'weightedTag.tag'),
      weight:
          _doubleValue(map['weight'], 'weightedTag.weight', defaultValue: 1),
    );
  }

  Map<String, dynamic> toJson() => {'tag': tag, 'weight': weight};
}

class ArtistEntry {
  final String name;
  final String prefix;
  final double weight;
  final String? groupedWith;

  const ArtistEntry({
    required this.name,
    this.prefix = 'artist:',
    this.weight = 1,
    this.groupedWith,
  });

  factory ArtistEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'artist entry');
    return ArtistEntry(
      name: _stringValue(map['name'], 'artistEntry.name'),
      prefix: _stringValue(
        map['prefix'],
        'artistEntry.prefix',
        defaultValue: 'artist:',
      ),
      weight:
          _doubleValue(map['weight'], 'artistEntry.weight', defaultValue: 1),
      groupedWith: _optionalStringValue(
        map['groupedWith'],
        'artistEntry.groupedWith',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (prefix != 'artist:') 'prefix': prefix,
        if (weight != 1) 'weight': weight,
        if (groupedWith != null) 'groupedWith': groupedWith,
      };
}

class WorkspaceVibeReference {
  final String id;
  final String name;
  final String vibeB64;
  final double referenceStrength;
  final double infoExtracted;
  final SourceRef source;
  final String note;

  const WorkspaceVibeReference({
    required this.id,
    required this.name,
    required this.vibeB64,
    this.referenceStrength = 0.6,
    this.infoExtracted = 1.0,
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  WorkspaceVibeReference copyWith({
    String? id,
    String? name,
    String? vibeB64,
    double? referenceStrength,
    double? infoExtracted,
    SourceRef? source,
    String? note,
  }) {
    return WorkspaceVibeReference(
      id: id ?? this.id,
      name: name ?? this.name,
      vibeB64: vibeB64 ?? this.vibeB64,
      referenceStrength: (referenceStrength ?? this.referenceStrength)
          .clamp(0.0, 1.0)
          .toDouble(),
      infoExtracted:
          (infoExtracted ?? this.infoExtracted).clamp(0.0, 1.0).toDouble(),
      source: source ?? this.source,
      note: note ?? this.note,
    );
  }

  factory WorkspaceVibeReference.fromJson(dynamic json) {
    if (json is String) {
      return WorkspaceVibeReference(
        id: json,
        name: json,
        vibeB64: '',
      );
    }
    final map = _asMap(json, 'vibe reference');
    final name = _stringValue(map['name'], 'vibeReference.name');
    final vibeB64 = _stringValue(
      map['vibeB64'] ?? map['vibe_b64'] ?? map['encoding'],
      'vibeReference.vibeB64',
    );
    return WorkspaceVibeReference(
      id: _stringValue(
        map['id'],
        'vibeReference.id',
        defaultValue: name.isNotEmpty ? name : vibeB64,
      ),
      name: name,
      vibeB64: vibeB64,
      referenceStrength: _doubleValue(
        map['referenceStrength'] ?? map['reference_strength'],
        'vibeReference.referenceStrength',
        defaultValue: 0.6,
      ).clamp(0.0, 1.0),
      infoExtracted: _doubleValue(
        map['infoExtracted'] ?? map['info_extracted'],
        'vibeReference.infoExtracted',
        defaultValue: 1.0,
      ).clamp(0.0, 1.0),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'vibeReference.note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (vibeB64.isNotEmpty && _sanitizeWorkspaceString(vibeB64) != null)
          'vibeB64': vibeB64,
        if (referenceStrength != 0.6) 'referenceStrength': referenceStrength,
        if (infoExtracted != 1.0) 'infoExtracted': infoExtracted,
        if (source.type != 'manual' || source.id != null || source.path != null)
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
  final List<ArtistEntry> artists;
  final List<WorkspaceWeightedTag> globalNegatives;
  final List<WorkspaceWeightedTag> styleHintsWeighted;
  final List<WorkspaceVibeReference> vibeRefs;

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
    this.artists = const [],
    this.globalNegatives = const [],
    this.styleHintsWeighted = const [],
    this.vibeRefs = const [],
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
      artists: _asList(map['artists'], 'artistChain.artists')
          .map(ArtistEntry.fromJson)
          .toList(growable: false),
      globalNegatives:
          _asList(map['globalNegatives'], 'artistChain.globalNegatives')
              .map(WorkspaceWeightedTag.fromJson)
              .toList(growable: false),
      styleHintsWeighted:
          _asList(map['styleHintsWeighted'], 'artistChain.styleHintsWeighted')
              .map(WorkspaceWeightedTag.fromJson)
              .toList(growable: false),
      vibeRefs: _asList(map['vibeRefs'], 'artistChain.vibeRefs')
          .map(WorkspaceVibeReference.fromJson)
          .toList(growable: false),
    );
  }

  ArtistChain copyWith({
    String? id,
    String? name,
    List<String>? tags,
    String? prompt,
    List<String>? styleTags,
    List<String>? imageRefs,
    Map<String, String>? translations,
    SourceRef? source,
    String? note,
    List<ArtistEntry>? artists,
    List<WorkspaceWeightedTag>? globalNegatives,
    List<WorkspaceWeightedTag>? styleHintsWeighted,
    List<WorkspaceVibeReference>? vibeRefs,
  }) {
    return ArtistChain(
      id: id ?? this.id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      prompt: prompt ?? this.prompt,
      styleTags: styleTags ?? this.styleTags,
      imageRefs: imageRefs ?? this.imageRefs,
      translations: translations ?? this.translations,
      source: source ?? this.source,
      note: note ?? this.note,
      artists: artists ?? this.artists,
      globalNegatives: globalNegatives ?? this.globalNegatives,
      styleHintsWeighted: styleHintsWeighted ?? this.styleHintsWeighted,
      vibeRefs: vibeRefs ?? this.vibeRefs,
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
        if (artists.isNotEmpty)
          'artists': artists.map((artist) => artist.toJson()).toList(),
        if (globalNegatives.isNotEmpty)
          'globalNegatives':
              globalNegatives.map((tag) => tag.toJson()).toList(),
        if (styleHintsWeighted.isNotEmpty)
          'styleHintsWeighted':
              styleHintsWeighted.map((tag) => tag.toJson()).toList(),
        if (vibeRefs.isNotEmpty)
          'vibeRefs': vibeRefs.map((vibe) => vibe.toJson()).toList(),
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
  final List<String> sourceCategoryPath;
  final String? sourceParentId;
  final String? sourceParentName;
  final String? sourceVariantLabel;
  final List<InspirationEntry> variants;

  const InspirationEntry({
    required this.id,
    required this.name,
    this.prompt = '',
    this.negativePrompt = '',
    this.tags = const [],
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
    this.sourceCategoryPath = const [],
    this.sourceParentId,
    this.sourceParentName,
    this.sourceVariantLabel,
    this.variants = const [],
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
      sourceCategoryPath: _stringList(
        map['sourceCategoryPath'],
        'inspiration.sourceCategoryPath',
      ),
      sourceParentId: _optionalStringValue(
        map['sourceParentId'],
        'inspiration.sourceParentId',
      ),
      sourceParentName: _optionalStringValue(
        map['sourceParentName'],
        'inspiration.sourceParentName',
      ),
      sourceVariantLabel: _optionalStringValue(
        map['sourceVariantLabel'],
        'inspiration.sourceVariantLabel',
      ),
      variants: _asList(map['variants'], 'inspiration.variants')
          .map(InspirationEntry.fromJson)
          .toList(growable: false),
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
        if (_sanitizeWorkspaceStringList(sourceCategoryPath).isNotEmpty)
          'sourceCategoryPath':
              _sanitizeWorkspaceStringList(sourceCategoryPath),
        if (sourceParentId != null &&
            _sanitizeWorkspaceString(sourceParentId!) != null)
          'sourceParentId': sourceParentId,
        if (sourceParentName != null &&
            _sanitizeWorkspaceString(sourceParentName!) != null)
          'sourceParentName': sourceParentName,
        if (sourceVariantLabel != null &&
            _sanitizeWorkspaceString(sourceVariantLabel!) != null)
          'sourceVariantLabel': sourceVariantLabel,
        if (variants.isNotEmpty)
          'variants': variants.map((entry) => entry.toJson()).toList(),
      };
}

class PromptChunkEntry {
  final String id;
  final String name;
  final String prompt;
  final String negativePrompt;
  final List<String> tags;
  final SourceRef source;
  final String note;

  const PromptChunkEntry({
    required this.id,
    required this.name,
    required this.prompt,
    this.negativePrompt = '',
    this.tags = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory PromptChunkEntry.fromJson(dynamic json) {
    final map = _asMap(json, 'prompt chunk');
    return PromptChunkEntry(
      id: _stringValue(map['id'], 'promptChunk.id'),
      name: _stringValue(map['name'], 'promptChunk.name'),
      prompt: _stringValue(map['prompt'], 'promptChunk.prompt'),
      negativePrompt: _stringValue(
        map['negativePrompt'],
        'promptChunk.negativePrompt',
      ),
      tags: _stringList(map['tags'], 'promptChunk.tags'),
      source: map['source'] == null
          ? const SourceRef(type: 'manual')
          : SourceRef.fromJson(map['source']),
      note: _stringValue(map['note'], 'promptChunk.note'),
    );
  }

  String insertIntoPrompt(
    String basePrompt, {
    bool prepend = false,
    String separator = ', ',
  }) {
    final chunk = prompt.trim();
    final base = basePrompt.trim();
    if (chunk.isEmpty) return base;
    if (base.isEmpty) return chunk;
    return prepend ? '$chunk$separator$base' : '$base$separator$chunk';
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
        'savedBlocks':
            savedBlocks.map(_sanitizeWorkspaceMap).toList(growable: false),
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
