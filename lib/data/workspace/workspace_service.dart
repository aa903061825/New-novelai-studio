import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/workspace/importers/artist_studio_importer.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/models/workspace_manifest.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';

class WorkspaceService {
  Directory? _root;
  WorkspaceManifest? _currentManifest;

  Directory? get root => _root;

  WorkspaceManifest? get currentManifest => _currentManifest;

  Future<void> createWorkspace(
    String path, {
    String name = 'Novel Studio',
  }) async {
    final workspaceRoot = Directory(path);
    await workspaceRoot.create(recursive: true);

    _root = workspaceRoot;
    _currentManifest = WorkspaceManifest.empty(name: name);

    for (final directory in WorkspacePaths.directories) {
      await _directory(directory).create(recursive: true);
    }

    await _writeJsonFile(WorkspacePaths.manifest, _currentManifest!.toJson());

    for (final filePath in WorkspacePaths.emptyArrayFiles) {
      await _writeJsonFile(filePath, <dynamic>[]);
    }
    for (final filePath in WorkspacePaths.emptyObjectFiles) {
      await _writeJsonFile(filePath, <String, dynamic>{});
    }
  }

  Future<void> openWorkspace(String path) async {
    final workspaceRoot = Directory(path);
    final manifestJson = await _readJsonFileFrom(
      workspaceRoot,
      WorkspacePaths.manifest,
    );
    final manifest = WorkspaceManifest.fromJson(_jsonMap(manifestJson));

    _root = workspaceRoot;
    _currentManifest = manifest;
  }

  Future<List<CharacterEntry>> loadCharacters() {
    return _readList(
      WorkspacePaths.characters,
      CharacterEntry.fromJson,
    );
  }

  Future<void> saveCharacters(List<CharacterEntry> characters) {
    return _writeJsonFile(
      WorkspacePaths.characters,
      characters.map((character) => character.toJson()).toList(),
    );
  }

  Future<List<ArtistChain>> loadArtistChains() {
    return _readList(
      WorkspacePaths.artistChains,
      ArtistChain.fromJson,
    );
  }

  Future<void> saveArtistChains(List<ArtistChain> artistChains) {
    return _writeJsonFile(
      WorkspacePaths.artistChains,
      artistChains.map((artistChain) => artistChain.toJson()).toList(),
    );
  }

  Future<List<InspirationEntry>> loadInspirations() {
    return _readList(
      WorkspacePaths.inspirations,
      InspirationEntry.fromJson,
    );
  }

  Future<void> saveInspirations(List<InspirationEntry> inspirations) {
    return _writeJsonFile(
      WorkspacePaths.inspirations,
      inspirations.map((entry) => entry.toJson()).toList(),
    );
  }

  Future<List<LoraEntry>> loadLoras() {
    return _readList(
      WorkspacePaths.loras,
      LoraEntry.fromJson,
    );
  }

  Future<void> saveLoras(List<LoraEntry> loras) {
    return _writeJsonFile(
      WorkspacePaths.loras,
      loras.map((entry) => entry.toJson()).toList(),
    );
  }

  Future<Map<String, dynamic>> loadFilterRules() async {
    final json = await _readJsonFile(WorkspacePaths.filterRules);
    return Map.unmodifiable(_jsonMap(json));
  }

  Future<void> saveFilterRules(Map<String, dynamic> filterRules) {
    return _writeJsonFile(
      WorkspacePaths.filterRules,
      _sanitizeFilterRules(filterRules),
    );
  }

  Future<ArtistStudioImportResult> importArtistStudioData(
      String rootPath) async {
    final result = await ArtistStudioImporter().importDataRoot(rootPath);
    await saveArtistChains(result.artistChains);
    await saveCharacters(result.characters);
    await saveFilterRules(result.filterRules);
    return result;
  }

  Future<List<Recipe>> loadRecipes(String block) {
    _checkBlock(block);
    return _readList(
      WorkspacePaths.recipeFile(block),
      Recipe.fromJson,
    );
  }

  Future<void> saveRecipes(String block, List<Recipe> recipes) {
    _checkBlock(block);
    return _writeJsonFile(
      WorkspacePaths.recipeFile(block),
      recipes.map((recipe) => recipe.toJson()).toList(),
    );
  }

  Future<List<TagEntry>> loadTags(String block) {
    _checkBlock(block);
    return _readList(
      WorkspacePaths.tagFile(block),
      TagEntry.fromJson,
    );
  }

  Future<void> saveTags(String block, List<TagEntry> tags) {
    _checkBlock(block);
    return _writeJsonFile(
      WorkspacePaths.tagFile(block),
      tags.map((tag) => tag.toJson()).toList(),
    );
  }

  Future<WorkspacePromptConfig> loadPromptConfig(String id) async {
    final json = await _readJsonFile(WorkspacePaths.promptConfigFile(id));
    return WorkspacePromptConfig.fromJson(json);
  }

  Future<void> savePromptConfig(WorkspacePromptConfig promptConfig) {
    return _writeJsonFile(
      WorkspacePaths.promptConfigFile(promptConfig.id),
      promptConfig.toJson(),
    );
  }

  Future<GenerationProfile> loadGenerationProfile(String id) async {
    final json = await _readJsonFile(WorkspacePaths.generationProfileFile(id));
    return GenerationProfile.fromJson(json);
  }

  Future<void> saveGenerationProfile(GenerationProfile generationProfile) {
    return _writeJsonFile(
      WorkspacePaths.generationProfileFile(generationProfile.id),
      generationProfile.toJson(),
    );
  }

  Future<List<BatchPlan>> loadBatchPlans() {
    return _readEntityDirectory(
      WorkspacePaths.batchPlansDir,
      BatchPlan.fromJson,
    );
  }

  Future<void> saveBatchPlans(List<BatchPlan> batchPlans) {
    return _writeEntityDirectory(
      WorkspacePaths.batchPlansDir,
      batchPlans,
      (entry) => entry.id,
      (entry) => entry.toJson(),
    );
  }

  Future<List<AssemblyPresetEntry>> loadAssemblyPresets() {
    return _readEntityDirectory(
      WorkspacePaths.assemblyPresetsDir,
      AssemblyPresetEntry.fromJson,
    );
  }

  Future<void> saveAssemblyPresets(List<AssemblyPresetEntry> presets) {
    return _writeEntityDirectory(
      WorkspacePaths.assemblyPresetsDir,
      presets,
      (entry) => entry.id,
      (entry) => entry.toJson(),
    );
  }

  Future<List<WorkflowEntry>> loadWorkflows() {
    return _readEntityDirectory(
      WorkspacePaths.workflowsDir,
      WorkflowEntry.fromJson,
    );
  }

  Future<void> saveWorkflows(List<WorkflowEntry> workflows) {
    return _writeEntityDirectory(
      WorkspacePaths.workflowsDir,
      workflows,
      (entry) => entry.id,
      (entry) => entry.toJson(),
    );
  }

  Future<List<T>> _readList<T>(
    String relativePath,
    T Function(dynamic json) fromJson,
  ) async {
    final json = await _readJsonFile(relativePath);
    if (json is! List) {
      throw FormatException('$relativePath must be a JSON array.');
    }
    return json.map(fromJson).toList(growable: false);
  }

  Future<dynamic> _readJsonFile(String relativePath) async {
    final workspaceRoot = _root;
    if (workspaceRoot == null) {
      throw StateError('No workspace is open.');
    }
    return _readJsonFileFrom(workspaceRoot, relativePath);
  }

  Future<dynamic> _readJsonFileFrom(
    Directory workspaceRoot,
    String relativePath,
  ) async {
    final source = await File(
      _resolveFrom(workspaceRoot, relativePath),
    ).readAsString();
    return jsonDecode(source);
  }

  Future<void> _writeJsonFile(String relativePath, Object? value) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(value)}\n');
  }

  Future<List<T>> _readEntityDirectory<T>(
    String relativePath,
    T Function(dynamic json) fromJson,
  ) async {
    final directory = _directory(relativePath);
    if (!await directory.exists()) {
      return const [];
    }

    final entries = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
    entries.sort((left, right) => left.path.compareTo(right.path));

    final values = <T>[];
    for (final file in entries) {
      final decoded = jsonDecode(await file.readAsString());
      values.add(fromJson(decoded));
    }
    return values;
  }

  Future<void> _writeEntityDirectory<T>(
    String relativePath,
    List<T> values,
    String Function(T entry) idOf,
    Object? Function(T entry) toJson,
  ) async {
    final directory = _directory(relativePath);
    await directory.create(recursive: true);
    final existing = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
    for (final file in existing) {
      await file.delete();
    }
    for (final value in values) {
      await _writeJsonFile('$relativePath/${idOf(value)}.json', toJson(value));
    }
  }

  File _file(String relativePath) {
    return File(_resolve(relativePath));
  }

  Directory _directory(String relativePath) {
    return Directory(_resolve(relativePath));
  }

  void _checkBlock(String block) {
    if (!WorkspacePaths.blocks.contains(block)) {
      throw ArgumentError.value(block, 'block', 'Unknown workspace block.');
    }
  }

  String _resolve(String relativePath) {
    final workspaceRoot = _root;
    if (workspaceRoot == null) {
      throw StateError('No workspace is open.');
    }

    return _resolveFrom(workspaceRoot, relativePath);
  }

  String _resolveFrom(Directory workspaceRoot, String relativePath) {
    final segments = relativePath.split('/');
    for (final segment in segments) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains('\\') ||
          segment.contains(Platform.pathSeparator)) {
        throw ArgumentError.value(
          relativePath,
          'relativePath',
          'Workspace paths must stay under the workspace root.',
        );
      }
    }

    return [
      workspaceRoot.path,
      ...segments,
    ].join(Platform.pathSeparator);
  }
}

Map<String, dynamic> _jsonMap(dynamic json) {
  if (json is! Map) {
    throw const FormatException('Expected a JSON object.');
  }

  return json.map((key, value) {
    if (key is! String) {
      throw const FormatException('JSON object keys must be strings.');
    }
    return MapEntry(key, value);
  });
}

Map<String, dynamic> _sanitizeFilterRules(Map<String, dynamic> value) {
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (_isSensitiveKey(entry.key)) {
      continue;
    }
    final sanitized = _sanitizeFilterValue(entry.value);
    if (sanitized != null) {
      result[entry.key] = sanitized;
    }
  }
  return result;
}

dynamic _sanitizeFilterValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return _isSensitiveString(value) ? null : value;
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || _isSensitiveKey(key)) {
        continue;
      }
      final sanitized = _sanitizeFilterValue(entry.value);
      if (sanitized != null) {
        result[key] = sanitized;
      }
    }
    return result;
  }
  if (value is List) {
    final result = <dynamic>[];
    for (final item in value) {
      final sanitized = _sanitizeFilterValue(item);
      if (sanitized != null) {
        result.add(sanitized);
      }
    }
    return result;
  }
  if (value is num || value is bool) {
    return value;
  }
  return value.toString();
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
