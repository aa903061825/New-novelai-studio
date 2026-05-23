import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';

class KamiaImportResult {
  final Map<String, List<Recipe>> recipes;
  final Map<String, List<TagEntry>> tags;
  final List<CharacterEntry> characters;
  final List<InspirationEntry> inspirations;
  final List<LoraEntry> loras;
  final List<WorkflowEntry> workflows;
  final List<BatchPlan> batchPlans;
  final List<AssemblyPresetEntry> assemblyPresets;

  const KamiaImportResult({
    required this.recipes,
    required this.tags,
    required this.characters,
    this.inspirations = const [],
    this.loras = const [],
    this.workflows = const [],
    this.batchPlans = const [],
    this.assemblyPresets = const [],
  });
}

class KamiaImporter {
  Future<KamiaImportResult> importProject(String projectPath) async {
    final dataPath = _join(projectPath, 'data');
    return KamiaImportResult(
      recipes: await _loadRecipes(dataPath),
      tags: await _loadTags(dataPath),
      characters: await _loadCharacters(dataPath),
      inspirations: await _loadInspirations(dataPath),
      loras: await _loadLoras(dataPath),
      workflows: await _loadWorkflows(dataPath),
      batchPlans: await _loadBatchPlans(dataPath),
      assemblyPresets: await _loadAssemblyPresets(dataPath),
    );
  }

  Future<Map<String, List<Recipe>>> _loadRecipes(String dataPath) async {
    final result = <String, List<Recipe>>{};
    for (final block in WorkspacePaths.blocks) {
      final file = File(_join(dataPath, 'recipes', '$block.json'));
      if (!await file.exists()) {
        result[block] = const [];
        continue;
      }
      final rows = _jsonList(await file.readAsString());
      result[block] = rows.map((json) {
        return Recipe(
          id: _string(json['id']),
          name: _string(json['name']),
          block: _string(json['block'], fallback: block),
          category: _string(json['category']),
          group: _string(json['group']),
          tags: _string(json['tags']),
          variants: _recipeVariants(json),
          imageRefs: _imageRefs(json['image']),
          source: SourceRef(type: 'kamia', id: json['id']?.toString()),
          note: _string(json['note']),
        );
      }).toList(growable: false);
    }
    return result;
  }

  Future<Map<String, List<TagEntry>>> _loadTags(String dataPath) async {
    final result = <String, List<TagEntry>>{};
    for (final block in WorkspacePaths.blocks) {
      final file = File(_join(dataPath, 'tags', '$block.json'));
      if (!await file.exists()) {
        result[block] = const [];
        continue;
      }
      final rows = _jsonList(await file.readAsString());
      result[block] = rows.map((json) {
        final tag = _string(json['tag']);
        return TagEntry(
          id: _string(json['id'], fallback: '${block}_$tag'),
          tag: tag,
          zh: _string(json['name_zh'] ?? json['zh']),
          block: _string(json['block'], fallback: block),
          category: _string(json['category']),
          aliases: _stringList(json['aliases']),
          imageRefs: _imageRefs(json['image']),
          source: SourceRef(type: 'kamia', id: tag),
          note: _string(json['note']),
        );
      }).toList(growable: false);
    }
    return result;
  }

  Future<List<CharacterEntry>> _loadCharacters(String dataPath) async {
    final file = File(_join(dataPath, 'characters.json'));
    if (!await file.exists()) return const [];
    final rows = _jsonList(await file.readAsString());
    return rows.map((json) {
      return CharacterEntry(
        id: _string(json['id']),
        name: _string(json['name']),
        traits: ViewVariantTexts.fromJson(json['traits']),
        outfits: _outfits(json['outfits']),
        defaultOutfitId: _nullableString(
          json['default_outfit'] ?? json['defaultOutfitId'],
        ),
        imageRefs: _imageRefs(json['preview_image'] ?? json['image']),
        source: SourceRef(type: 'kamia', id: json['id']?.toString()),
        note: _string(json['note']),
      );
    }).toList(growable: false);
  }

  Future<List<InspirationEntry>> _loadInspirations(String dataPath) async {
    final rows = await _loadJsonCollection(dataPath, 'inspirations.json');
    return rows.map((json) {
      final id = _string(
        json['id'],
        fallback: _string(json['name'] ?? json['title'], fallback: 'inspiration'),
      );
      return InspirationEntry(
        id: id,
        name: _string(json['name'] ?? json['title'], fallback: id),
        prompt: _string(
          json['prompt'] ?? json['content'] ?? json['description'],
        ),
        negativePrompt: _string(
          json['negative_prompt'] ?? json['negativePrompt'],
        ),
        tags: _stringListFromAny(json['tags']),
        imageRefs: _imageRefs(
          json['preview_image'] ?? json['image'] ?? json['images'],
        ),
        source: SourceRef(type: 'kamia', id: id),
        note: _string(json['note']),
      );
    }).toList(growable: false);
  }

  Future<List<LoraEntry>> _loadLoras(String dataPath) async {
    final rows = await _loadJsonCollection(dataPath, 'loras.json');
    return rows.map((json) {
      final id = _string(
        json['id'],
        fallback: _string(json['name'] ?? json['title'], fallback: 'lora'),
      );
      return LoraEntry(
        id: id,
        name: _string(json['name'] ?? json['title'], fallback: id),
        baseModel: _string(
          json['base_model'] ?? json['baseModel'] ?? json['model'],
        ),
        triggerWords: _stringListFromAny(
          json['trigger_words'] ?? json['triggerWords'] ?? json['triggers'],
        ),
        defaultStrength: _nullableDouble(
          json['default_strength'] ?? json['defaultStrength'] ?? json['weight'],
        ),
        imageRefs: _imageRefs(
          json['preview_image'] ?? json['image'] ?? json['images'],
        ),
        source: SourceRef(type: 'kamia', id: id),
        note: _string(json['note']),
      );
    }).toList(growable: false);
  }

  Future<List<WorkflowEntry>> _loadWorkflows(String dataPath) async {
    final rows = await _loadJsonCollection(
      dataPath,
      'workflows.json',
      directoryName: 'workflows',
    );
    return rows.map((json) {
      final id = _string(
        json['id'],
        fallback: _string(json['name'] ?? json['title'], fallback: 'workflow'),
      );
      return WorkflowEntry(
        id: id,
        name: _string(json['name'] ?? json['title'], fallback: id),
        summary: _string(
          json['summary'] ?? json['description'] ?? json['prompt'],
        ),
        imageRefs: _imageRefs(
          json['preview_image'] ?? json['image'] ?? json['images'],
        ),
        payload: _payloadMap(json),
        source: SourceRef(type: 'kamia', id: id),
        note: _string(json['note']),
      );
    }).toList(growable: false);
  }

  Future<List<BatchPlan>> _loadBatchPlans(String dataPath) async {
    final rows = await _loadJsonCollection(
      dataPath,
      'batch_plans.json',
      directoryName: 'batch_plans',
    );
    return rows.map((json) {
      final id = _string(
        json['id'],
        fallback: _string(json['name'], fallback: 'batch-plan'),
      );
      return BatchPlan(
        id: id,
        name: _string(json['name'], fallback: id),
        items: _mapList(json['items'] ?? json['queue']),
        statusSnapshot: _payloadMap(json['statusSnapshot'] ?? json['status']),
        createdAt: _dateTime(json['createdAt'] ?? json['created_at']),
        updatedAt: _dateTime(json['updatedAt'] ?? json['updated_at']),
      );
    }).toList(growable: false);
  }

  Future<List<AssemblyPresetEntry>> _loadAssemblyPresets(String dataPath) async {
    final rows = await _loadJsonCollection(
      dataPath,
      'assembly_presets.json',
      directoryName: 'assembly_presets',
    );
    return rows.map((json) {
      final id = _string(
        json['id'],
        fallback: _string(
          json['name'] ?? json['title'],
          fallback: 'assembly-preset',
        ),
      );
      return AssemblyPresetEntry(
        id: id,
        name: _string(json['name'] ?? json['title'], fallback: id),
        summary: _string(
          json['summary'] ?? json['description'] ?? json['prompt'],
        ),
        imageRefs: _imageRefs(
          json['preview_image'] ?? json['image'] ?? json['images'],
        ),
        payload: _payloadMap(json),
        source: SourceRef(type: 'kamia', id: id),
        note: _string(json['note']),
      );
    }).toList(growable: false);
  }

  List<WorkspaceOutfit> _outfits(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((entry) {
      final json = _mapValue(entry);
      return WorkspaceOutfit(
        id: _string(json['id']),
        name: _string(json['name']),
        tags: ViewVariantTexts.fromJson(json['tags']),
        imageRefs: _imageRefs(json['preview_image'] ?? json['image']),
        note: _string(json['note']),
      );
    }).toList(growable: false);
  }

  Map<String, String> _recipeVariants(Map<String, dynamic> json) {
    final variants = <String, String>{};
    for (final entry in json.entries) {
      if (!entry.key.startsWith('tags_')) continue;
      final value = _nullableString(entry.value);
      if (value == null || value.isEmpty) continue;
      variants[entry.key.replaceFirst('tags_', '')] = value;
    }
    return variants;
  }

  List<Map<String, dynamic>> _jsonList(String content) {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      return decoded.whereType<Map>().map(_mapValue).toList(growable: false);
    }
    if (decoded is Map) {
      final map = _mapValue(decoded);
      final values =
          map['items'] ?? map['data'] ?? map['recipes'] ?? map['tags'];
      if (values is List) {
        return values.whereType<Map>().map(_mapValue).toList(growable: false);
      }
    }
    return const [];
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

  List<String> _imageRefs(dynamic value) {
    if (value is List) return _stringList(value);
    final image = _nullableString(value);
    if (image == null || image.isEmpty) return const [];
    return [image];
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_nullableString)
        .whereType<String>()
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _stringListFromAny(dynamic value) {
    if (value is List) return _stringList(value);
    final single = _nullableString(value);
    if (single == null || single.trim().isEmpty) return const [];
    return single
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  double? _nullableDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  DateTime _dateTime(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<List<Map<String, dynamic>>> _loadJsonCollection(
    String dataPath,
    String fileName, {
    String? directoryName,
  }) async {
    final file = File(_join(dataPath, fileName));
    if (await file.exists()) {
      return _jsonList(await file.readAsString());
    }

    final folder = Directory(
      _join(
        dataPath,
        directoryName ?? fileName.replaceAll('.json', ''),
      ),
    );
    if (!await folder.exists()) return const [];

    final result = <Map<String, dynamic>>[];
    final files = await folder
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    for (final entry in files) {
      final decoded = jsonDecode(await entry.readAsString());
      if (decoded is List) {
        result.addAll(
          decoded.whereType<Map>().map(_mapValue).toList(growable: false),
        );
        continue;
      }
      if (decoded is Map) {
        result.add(_mapValue(decoded));
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(_mapValue).toList(growable: false);
  }

  Map<String, dynamic> _payloadMap(dynamic value) {
    if (value is Map) {
      return _mapValue(value);
    }
    return const {};
  }

  String _string(dynamic value, {String fallback = ''}) {
    return _nullableString(value) ?? fallback;
  }

  String? _nullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  String _join(String first, String second, [String? third]) {
    final separator = Platform.pathSeparator;
    final joined = '$first$separator$second';
    if (third == null) return joined;
    return '$joined$separator$third';
  }
}
