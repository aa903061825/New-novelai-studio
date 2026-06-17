import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

class ArtistStudioImportResult {
  final List<ArtistChain> artistChains;
  final List<CharacterEntry> characters;
  final Map<String, dynamic> filterRules;

  const ArtistStudioImportResult({
    required this.artistChains,
    required this.characters,
    this.filterRules = const {},
  });
}

class ArtistStudioImporter {
  Future<ArtistStudioImportResult> importDataRoot(String rootPath) async {
    final dataJson = await _findDataJson(rootPath);
    if (dataJson == null) {
      return const ArtistStudioImportResult(
        artistChains: [],
        characters: [],
      );
    }

    final decoded = await _decodeObject(dataJson);
    return ArtistStudioImportResult(
      artistChains: _mapArtists(decoded['artists']),
      characters: _mapCharacters(decoded['characters']),
      filterRules: await _loadFilterRules(rootPath, dataJson),
    );
  }

  List<ArtistChain> _mapArtists(dynamic value) {
    final rows = _mapList(value);
    return rows.indexed.map((entry) {
      final index = entry.$1;
      final json = entry.$2;
      final name = _string(json['name']);
      return ArtistChain(
        id: _string(json['id'], fallback: 'artist-$index'),
        name: name.isEmpty ? 'Artist Chain ${index + 1}' : name,
        tags: _stringList(json['tags']),
        prompt: _string(json['prompt']),
        imageRefs: _stringList(json['images']),
        source: SourceRef(
          type: 'artist_studio',
          id: json['id']?.toString(),
        ),
        note: _string(json['note'] ?? json['notes']),
      );
    }).toList(growable: false);
  }

  List<CharacterEntry> _mapCharacters(dynamic value) {
    final rows = _mapList(value);
    return rows.indexed.map((entry) {
      final index = entry.$1;
      final json = entry.$2;
      final id = _string(json['id'], fallback: 'character-$index');
      final baseOutfit = _outfitFromValue(
        id: '$id-outfit',
        name: 'Imported Outfit',
        value: json['outfit'],
      );
      final presetOutfits = _presetOutfits(id, json['presets']);
      final outfits = [
        if (baseOutfit != null) baseOutfit,
        ...presetOutfits,
      ];

      return CharacterEntry(
        id: id,
        name: _string(json['name'], fallback: 'Character ${index + 1}'),
        traits: _traits(json),
        outfits: outfits,
        defaultOutfitId: _defaultOutfitId(
          id: id,
          activePresetIdx: json['activePresetIdx'],
          hasBaseOutfit: baseOutfit != null,
          presetCount: presetOutfits.length,
        ),
        imageRefs: _stringList(json['images']),
        source: SourceRef(type: 'artist_studio', id: json['id']?.toString()),
        note: _string(json['notes'] ?? json['note']),
      );
    }).toList(growable: false);
  }

  ViewVariantTexts _traits(Map<String, dynamic> json) {
    if (json['traits'] is Map) return ViewVariantTexts.fromJson(json['traits']);
    return ViewVariantTexts(frontFull: _string(json['features']));
  }

  List<WorkspaceOutfit> _presetOutfits(String characterId, dynamic value) {
    return _mapList(value).indexed.map((entry) {
      final index = entry.$1;
      final json = entry.$2;
      return _outfitFromValue(
            id: '$characterId-preset-$index',
            name: _string(json['name'], fallback: 'Preset ${index + 1}'),
            value: json['outfit'],
          ) ??
          WorkspaceOutfit(
            id: '$characterId-preset-$index',
            name: _string(json['name'], fallback: 'Preset ${index + 1}'),
            tags: const ViewVariantTexts(frontFull: ''),
          );
    }).toList(growable: false);
  }

  WorkspaceOutfit? _outfitFromValue({
    required String id,
    required String name,
    required dynamic value,
  }) {
    final text = _outfitText(value);
    if (text.isEmpty) return null;
    return WorkspaceOutfit(
      id: id,
      name: name,
      tags: ViewVariantTexts(frontFull: text),
    );
  }

  String? _defaultOutfitId({
    required String id,
    required dynamic activePresetIdx,
    required bool hasBaseOutfit,
    required int presetCount,
  }) {
    if (activePresetIdx is int &&
        activePresetIdx >= 0 &&
        activePresetIdx < presetCount) {
      return '$id-preset-$activePresetIdx';
    }
    if (hasBaseOutfit) return '$id-outfit';
    return null;
  }

  String _outfitText(dynamic value) {
    if (value is Map) {
      final parts = <String>[];
      for (final entry in _mapValue(value).entries) {
        if (_isSensitiveKey(entry.key)) continue;
        final text = _nullableString(entry.value);
        if (text == null || text.trim().isEmpty || _isSensitiveString(text)) {
          continue;
        }
        parts.add(text);
      }
      return parts.join(', ');
    }
    return _string(value);
  }

  Future<File?> _findDataJson(String rootPath) async {
    final root = Directory(rootPath);
    final candidates = <File>[
      File(_join(root.path, 'data.json')),
      File(_join(root.path, 'data', 'data.json')),
    ];

    if (await root.exists()) {
      candidates.addAll(await _childDataJsonCandidates(root));
      final parent = root.parent;
      if (await parent.exists()) {
        candidates.add(File(_join(parent.path, 'data', 'data.json')));
        candidates.addAll(await _childDataJsonCandidates(parent));
      }
    }

    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate.path)) continue;
      if (await candidate.exists()) return candidate;
    }
    return null;
  }

  Future<List<File>> _childDataJsonCandidates(Directory root) async {
    final result = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        result.add(File(_join(entity.path, 'data', 'data.json')));
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _loadFilterRules(
    String rootPath,
    File dataJson,
  ) async {
    final candidates = <File>[];
    var directory = Directory(rootPath);
    for (var i = 0; i < 4; i++) {
      candidates.add(File(_join(directory.path, 'nai_unified_config.json')));
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }

    directory = dataJson.parent;
    for (var i = 0; i < 4; i++) {
      candidates.add(File(_join(directory.path, 'nai_unified_config.json')));
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }

    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate.path)) continue;
      if (await candidate.exists()) {
        return _withoutLocalSecrets(await _decodeObject(candidate));
      }
    }
    return const {};
  }

  Future<Map<String, dynamic>> _decodeObject(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return const {};
    return _mapValue(decoded);
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(_mapValue).toList(growable: false);
  }

  Map<String, dynamic> _mapValue(Map<dynamic, dynamic> value) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return result;
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_nullableString)
        .whereType<String>()
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  String _string(dynamic value, {String fallback = ''}) {
    return _nullableString(value) ?? fallback;
  }

  String? _nullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  Map<String, dynamic> _withoutLocalSecrets(Map<String, dynamic> value) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (_isSensitiveKey(entry.key)) continue;
      if (entry.value is String && _isSensitiveString(entry.value as String)) {
        continue;
      }
      result[entry.key] = entry.value;
    }
    return result;
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
        normalized.contains('proxy') ||
        normalized.contains('url');
  }

  bool _isSensitiveString(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('bearer ') || normalized.contains('pst-');
  }

  String _join(String first, String second, [String? third]) {
    final separator = Platform.pathSeparator;
    final joined = '$first$separator$second';
    if (third == null) return joined;
    return '$joined$separator$third';
  }
}
