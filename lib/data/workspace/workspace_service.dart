import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/workspace/importers/artist_studio_importer.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_exhibition_recast_summary.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_path_rebinder.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/models/workspace_manifest.dart';
import 'package:novel_studio/data/workspace/workspace_json_codecs.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';

const _scriptRecastExhibitionIndexSchemaVersion = 4;
const _scriptRecastExhibitionSummaryIndexSchemaVersion = 6;
const _recastCacheHeaderReadBytes = 1024 * 1024;
const _recastCacheHeaderChunkBytes = 16 * 1024;
const _recastCacheMetadataTailReadBytes = 1024 * 1024;
const _atomicRenameRetryDelays = [
  Duration(milliseconds: 25),
  Duration(milliseconds: 50),
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
  Duration(milliseconds: 350),
];

typedef WorkspaceAtomicFileCommitter = Future<void> Function(
  File source,
  String targetPath,
);

class WorkspaceService {
  WorkspaceService({WorkspaceAtomicFileCommitter? atomicFileCommitter})
      : _atomicFileCommitter =
            atomicFileCommitter ?? _renameFileWithTransientAccessRetries;

  Directory? _root;
  WorkspaceManifest? _currentManifest;
  final WorkspaceAtomicFileCommitter _atomicFileCommitter;
  final Map<String, Future<void>> _pendingWritesByRelativePath = {};
  final ValueNotifier<int> _artistChainRevision = ValueNotifier<int>(0);

  Directory? get root => _root;

  WorkspaceManifest? get currentManifest => _currentManifest;

  ValueListenable<int> get artistChainRevision => _artistChainRevision;

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

  Future<void> recoverWorkspace(
    String path, {
    String name = 'Novel Studio',
  }) async {
    final workspaceRoot = Directory(path);
    await workspaceRoot.create(recursive: true);

    _root = workspaceRoot;
    _currentManifest = WorkspaceManifest.empty(name: name);
    await _writeJsonFile(WorkspacePaths.manifest, _currentManifest!.toJson());
    await _ensureWorkspaceScaffold();
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
    await _ensureWorkspaceScaffold();
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

  Future<void> saveArtistChains(List<ArtistChain> artistChains) async {
    await _writeJsonFile(
      WorkspacePaths.artistChains,
      artistChains.map((artistChain) => artistChain.toJson()).toList(),
    );
    notifyArtistChainsChanged();
  }

  void notifyArtistChainsChanged() {
    _artistChainRevision.value += 1;
  }

  Future<Set<String>> loadAssetFavorites() async {
    final json = await _readJsonFile(WorkspacePaths.assetFavorites);
    if (json is! List) {
      throw const FormatException(
          'library/favorites.json must be a JSON array.');
    }
    return json
        .whereType<String>()
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet();
  }

  Future<void> saveAssetFavorites(Set<String> favoriteKeys) {
    final normalized = favoriteKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    return _writeJsonFile(WorkspacePaths.assetFavorites, normalized);
  }

  Future<void> setAssetFavorite(String key, bool isFavorite) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    final favoriteKeys = await loadAssetFavorites();
    if (isFavorite) {
      favoriteKeys.add(normalized);
    } else {
      favoriteKeys.remove(normalized);
    }
    await saveAssetFavorites(favoriteKeys);
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

  Future<List<InspirationEntry>> loadCodexEntries() async {
    final file = _file(WorkspacePaths.codexEntries);
    if (!await file.exists()) return const [];
    final entries = <InspirationEntry>[];
    final lines = await file.readAsLines();
    for (final indexedLine in lines.indexed) {
      final line = indexedLine.$2.trim();
      if (line.isEmpty) continue;
      try {
        entries.add(InspirationEntry.fromJson(_jsonMap(jsonDecode(line))));
      } on FormatException catch (error) {
        throw FormatException(
          '${WorkspacePaths.codexEntries} line ${indexedLine.$1 + 1}: '
          '${error.message}',
        );
      }
    }
    return List.unmodifiable(entries);
  }

  Future<bool> hasCodexEntries() async {
    final file = _file(WorkspacePaths.codexEntries);
    return await file.exists() && await file.length() > 0;
  }

  Future<void> saveCodexEntries(List<InspirationEntry> entries) async {
    final contents = StringBuffer();
    for (final entry in entries) {
      contents.writeln(jsonEncode(entry.toJson()));
    }
    await _writeFileAtomically(
        WorkspacePaths.codexEntries, contents.toString());
  }

  Future<List<PromptChunkEntry>> loadPromptChunks() {
    return _readList(
      WorkspacePaths.promptChunks,
      PromptChunkEntry.fromJson,
    );
  }

  Future<void> savePromptChunks(List<PromptChunkEntry> chunks) {
    return _writeJsonFile(
      WorkspacePaths.promptChunks,
      chunks.map((entry) => entry.toJson()).toList(),
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
      WorkspaceSanitizer.sanitizeMap(filterRules),
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

  Future<List<PromptAssetCategory>> loadPromptAssetCategories() {
    return _readList(
      WorkspacePaths.promptAssetCategories,
      PromptAssetCategory.fromJson,
    );
  }

  Future<void> savePromptAssetCategories(
    List<PromptAssetCategory> categories,
  ) {
    return _writeJsonFile(
      WorkspacePaths.promptAssetCategories,
      categories.map((category) => category.toJson()).toList(),
    );
  }

  Future<List<String>> listRecipeBlocks() {
    return _listLibraryBlocks('library/recipes');
  }

  Future<List<String>> listTagBlocks() {
    return _listLibraryBlocks('library/tags');
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

  Future<List<ProductionPlan>> loadProductionPlans() {
    return _readProductionPlanDirectory();
  }

  Future<ProductionPlan?> loadProductionPlan(String planId) async {
    final normalizedPlanId = planId.trim();
    if (normalizedPlanId.isEmpty) return null;
    final relativePath = WorkspacePaths.productionPlanFile(normalizedPlanId);
    final file = _file(relativePath);
    if (!await file.exists()) return null;
    try {
      return await Isolate.run(
        () => _readProductionPlanFromFilePath(file.path),
      );
    } on FormatException {
      await _quarantineInvalidEntityFile(
        file,
        WorkspacePaths.deterministicPlansDir,
      );
      return null;
    }
  }

  Future<void> saveProductionPlans(List<ProductionPlan> plans) {
    return _writeEntityDirectory(
      WorkspacePaths.deterministicPlansDir,
      plans,
      (entry) => entry.id,
      (entry) => entry.toJson(),
    );
  }

  Future<void> saveProductionPlanUpdates({
    required Iterable<ProductionPlan> updatedPlans,
    required Iterable<String> deletedPlanIds,
  }) async {
    final updatesById = <String, ProductionPlan>{};
    for (final plan in updatedPlans) {
      final planId = plan.id.trim();
      if (planId.isNotEmpty) {
        updatesById[planId] = plan;
      }
    }
    final deletions = deletedPlanIds
        .map((planId) => planId.trim())
        .where(
          (planId) => planId.isNotEmpty && !updatesById.containsKey(planId),
        )
        .toSet();
    await Future.wait<void>([
      for (final entry in updatesById.entries)
        _writeJsonFile(
          WorkspacePaths.productionPlanFile(entry.key),
          entry.value.toJson(),
        ),
      for (final planId in deletions)
        _deleteFileIfExists(WorkspacePaths.productionPlanFile(planId)),
    ]);
  }

  Future<ProductionPlanExecutionSettings?>
      loadProductionExecutionSettings() async {
    final json =
        await _readJsonFile(WorkspacePaths.productionExecutionSettings);
    final map = _jsonMap(json);
    if (map.isEmpty) return null;
    return ProductionPlanExecutionSettings.fromJson(map);
  }

  Future<void> saveProductionExecutionSettings(
    ProductionPlanExecutionSettings settings,
  ) {
    return _writeJsonFile(
      WorkspacePaths.productionExecutionSettings,
      settings.toJson(),
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

  Future<List<RecastScriptCache>> loadRecastScriptCaches() async {
    final caches = await _readRecastScriptCacheDirectory();
    return _migrateLegacyTokenizerScriptsIntoRecastCaches(caches);
  }

  Future<List<RecastExhibitionScript>> loadRecastExhibitionScripts() async {
    final directory = _directory(WorkspacePaths.scriptRecastCacheDir);
    final indexFile = _file(WorkspacePaths.scriptRecastExhibitionIndex);
    final result = await Isolate.run(
      () => _loadOrBuildRecastExhibitionIndex(
        _RecastExhibitionIndexLoadRequest(
          cacheDirectoryPath: directory.path,
          indexPath: indexFile.path,
          summaryOnly: false,
        ),
      ),
    );
    return result.scripts;
  }

  Future<List<RecastExhibitionScript>> loadRecastExhibitionSummaries() async {
    final directory = _directory(WorkspacePaths.scriptRecastCacheDir);
    final indexFile = _file(WorkspacePaths.scriptRecastExhibitionSummaryIndex);
    final result = await Isolate.run(
      () => _loadOrBuildRecastExhibitionIndex(
        _RecastExhibitionIndexLoadRequest(
          cacheDirectoryPath: directory.path,
          indexPath: indexFile.path,
          summaryOnly: true,
        ),
      ),
    );
    return result.scripts;
  }

  Stream<void> watchRecastScriptCacheChanges() {
    if (_root == null) {
      return const Stream<void>.empty();
    }
    final directory = _directory(WorkspacePaths.scriptRecastCacheDir);
    if (!directory.existsSync()) {
      return const Stream<void>.empty();
    }
    return directory.watch(events: FileSystemEvent.all).map<void>((_) {});
  }

  Future<RecastExhibitionScript?> loadRecastExhibitionScript(
    String scriptId,
  ) async {
    final cache = await loadRecastScriptCache(scriptId);
    final script =
        cache == null ? null : RecastExhibitionScript.tryFromCache(cache);
    return script == null
        ? null
        : _rebindRecastExhibitionScriptSourceRoot(script);
  }

  Future<List<String>> loadScriptExhibitionCategories() async {
    final file = _file(WorkspacePaths.scriptRecastExhibitionCategories);
    if (!await file.exists()) {
      return const [];
    }
    final json = jsonDecode(await file.readAsString());
    if (json is! List) {
      throw const FormatException(
        'script_recast/exhibition_categories.json must be a JSON array.',
      );
    }
    return _normalizedScriptExhibitionCategoryNames(json);
  }

  Future<void> saveScriptExhibitionCategories(
    Iterable<String> categoryNames,
  ) {
    return _writeJsonFile(
      WorkspacePaths.scriptRecastExhibitionCategories,
      _normalizedScriptExhibitionCategoryNames(categoryNames),
    );
  }

  Future<void> addScriptExhibitionCategory(String categoryName) async {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) return;
    await saveScriptExhibitionCategories([
      ...await loadScriptExhibitionCategories(),
      normalized,
    ]);
  }

  Future<void> removeScriptExhibitionCategory(String categoryName) async {
    final normalized = categoryName.trim().toLowerCase();
    if (normalized.isEmpty) return;
    await saveScriptExhibitionCategories(
      (await loadScriptExhibitionCategories()).where(
        (name) => name.trim().toLowerCase() != normalized,
      ),
    );
  }

  Future<Map<String, List<String>>>
      loadScriptExhibitionCategoryAssignments() async {
    final file =
        _file(WorkspacePaths.scriptRecastExhibitionCategoryAssignments);
    if (!await file.exists()) {
      return const {};
    }
    final json = await _readJsonFile(
      WorkspacePaths.scriptRecastExhibitionCategoryAssignments,
    );
    if (json is! Map) {
      throw const FormatException(
        'script_recast/exhibition_category_assignments.json must be a JSON object.',
      );
    }
    return _normalizedScriptExhibitionCategoryAssignments(json);
  }

  Future<void> saveScriptExhibitionCategoryAssignments(
    Map<String, Iterable<String>> assignments,
  ) {
    return _writeJsonFile(
      WorkspacePaths.scriptRecastExhibitionCategoryAssignments,
      _normalizedScriptExhibitionCategoryAssignments(assignments),
    );
  }

  Future<void> assignScriptExhibitionCategoryScripts(
    String categoryName,
    Iterable<String> scriptIds,
  ) async {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) return;
    final ids = _normalizedScriptExhibitionScriptIds(scriptIds);
    if (ids.isEmpty) return;
    final assignments = await loadScriptExhibitionCategoryAssignments();
    final next = <String, List<String>>{};
    var targetName = normalized;
    final targetKey = normalized.toLowerCase();
    final mergedIds = <String>{};
    for (final entry in assignments.entries) {
      if (entry.key.trim().toLowerCase() == targetKey) {
        targetName = entry.key;
        mergedIds.addAll(entry.value);
        continue;
      }
      next[entry.key] = entry.value;
    }
    mergedIds.addAll(ids);
    next[targetName] = _normalizedScriptExhibitionScriptIds(mergedIds);
    await saveScriptExhibitionCategoryAssignments(next);
  }

  Future<void> removeScriptExhibitionCategoryFromScript(
    String categoryName,
    String scriptId,
  ) async {
    final categoryKey = categoryName.trim().toLowerCase();
    final normalizedScriptId = scriptId.trim();
    if (categoryKey.isEmpty || normalizedScriptId.isEmpty) return;
    final assignments = await loadScriptExhibitionCategoryAssignments();
    final next = <String, List<String>>{};
    for (final entry in assignments.entries) {
      if (entry.key.trim().toLowerCase() != categoryKey) {
        next[entry.key] = entry.value;
        continue;
      }
      final ids = entry.value
          .where((id) => id.trim() != normalizedScriptId)
          .toList(growable: false);
      if (ids.isNotEmpty) next[entry.key] = ids;
    }
    await saveScriptExhibitionCategoryAssignments(next);
  }

  Future<void> removeScriptExhibitionCategoryAssignments(
    String categoryName,
  ) async {
    final categoryKey = categoryName.trim().toLowerCase();
    if (categoryKey.isEmpty) return;
    final assignments = await loadScriptExhibitionCategoryAssignments();
    final next = <String, List<String>>{};
    for (final entry in assignments.entries) {
      if (entry.key.trim().toLowerCase() != categoryKey) {
        next[entry.key] = entry.value;
      }
    }
    await saveScriptExhibitionCategoryAssignments(next);
  }

  Future<RecastScriptCache?> loadRecastScriptCache(String scriptId) async {
    final file = _file(_scriptRecastCacheRelativePath(scriptId));
    if (!await file.exists()) {
      return null;
    }
    final source = await file.readAsString();
    if (source.trim().isEmpty) {
      await _quarantineInvalidEntityFile(
        file,
        WorkspacePaths.scriptRecastCacheDir,
      );
      return null;
    }
    try {
      final decodedSource = _decodeWorkspaceEntityJson(source);
      final decoded = _jsonMap(decodedSource.value);
      final compacted = RecastCacheJsonCodec.compact(decoded);
      if (decodedSource.repaired || compacted.changed) {
        await _writeJsonFile(
            _scriptRecastCacheRelativePath(scriptId), compacted.value);
      }
      return RecastScriptCache.fromJson(compacted.value);
    } on FormatException {
      await _quarantineInvalidEntityFile(
        file,
        WorkspacePaths.scriptRecastCacheDir,
      );
      return null;
    }
  }

  Future<RecastScriptCacheSnapshotRestore?> restoreRecastScriptCacheSnapshot({
    required String scriptId,
    String? importPath,
  }) async {
    final file = _file(_scriptRecastCacheRelativePath(scriptId));
    if (!await file.exists()) {
      return null;
    }
    final result = await Isolate.run(
      () => _restoreRecastScriptCacheSnapshotFromFile(
        _RecastScriptCacheSnapshotRestoreRequest(
          cacheFilePath: file.path,
          importPath: importPath,
        ),
      ),
    );
    if (result.invalid) {
      await _quarantineInvalidEntityFile(
        file,
        WorkspacePaths.scriptRecastCacheDir,
      );
    }
    return result.restore;
  }

  Future<void> saveRecastScriptCache(RecastScriptCache cache) async {
    await _writeJsonFile(
      _scriptRecastCacheRelativePath(cache.scriptId),
      RecastCacheJsonCodec.compact(cache.toJson()).value,
    );
    await _deleteRecastExhibitionIndex();
  }

  Future<void> saveRecastScriptCacheUpdates(
    Iterable<RecastScriptCache> caches,
  ) async {
    var wroteAny = false;
    for (final cache in caches) {
      await _writeJsonFile(
        _scriptRecastCacheRelativePath(cache.scriptId),
        RecastCacheJsonCodec.compact(cache.toJson()).value,
      );
      wroteAny = true;
    }
    if (wroteAny) {
      await _deleteRecastExhibitionIndex();
    }
  }

  Future<void> saveRecastScriptCaches(List<RecastScriptCache> caches) async {
    await _writeEntityDirectory(
      WorkspacePaths.scriptRecastCacheDir,
      caches,
      (entry) => safeWorkspaceEntityId(prefix: 'script', id: entry.scriptId),
      (entry) => RecastCacheJsonCodec.compact(entry.toJson()).value,
    );
    await _deleteRecastExhibitionIndex();
  }

  Future<void> removeRecastScriptCaches(Iterable<String> scriptIds) async {
    final normalizedScriptIds = scriptIds
        .map((scriptId) => scriptId.trim())
        .where((scriptId) => scriptId.isNotEmpty)
        .toSet();
    if (normalizedScriptIds.isEmpty) {
      return;
    }
    await Future.wait([
      for (final scriptId in normalizedScriptIds)
        _deleteFileIfExists(_scriptRecastCacheRelativePath(scriptId)),
    ]);
    await _deleteRecastExhibitionIndex();
  }

  Future<void> removeRecastScriptCachesMatching({
    required String scriptId,
    required String scriptName,
    required String sourceRootPath,
  }) async {
    final directory = _directory(WorkspacePaths.scriptRecastCacheDir);
    final scannedScriptIds = await Isolate.run(
      () => _matchingRecastScriptCacheIds(
        directoryPath: directory.path,
        scriptId: scriptId,
        scriptName: scriptName,
        sourceRootPath: sourceRootPath,
      ),
    );
    final matchingScriptIds = {...scannedScriptIds};
    if (scriptId.trim().isNotEmpty) {
      matchingScriptIds.add(scriptId.trim());
    }
    await removeRecastScriptCaches(matchingScriptIds);
  }

  Future<List<RecastScriptCache>> _readRecastScriptCacheDirectory() async {
    final directory = _directory(WorkspacePaths.scriptRecastCacheDir);
    if (!await directory.exists()) {
      return const [];
    }

    final entries = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
    entries.sort((left, right) => left.path.compareTo(right.path));

    final caches = <RecastScriptCache>[];
    for (final file in entries) {
      final source = await file.readAsString();
      if (source.trim().isEmpty) {
        await _quarantineInvalidEntityFile(
          file,
          WorkspacePaths.scriptRecastCacheDir,
        );
        continue;
      }
      try {
        final decodedSource = _decodeWorkspaceEntityJson(source);
        final decoded = _jsonMap(decodedSource.value);
        final compacted = RecastCacheJsonCodec.compact(decoded);
        if (decodedSource.repaired || compacted.changed) {
          await _writeJsonFile(
            '${WorkspacePaths.scriptRecastCacheDir}/${_fileNameFromWorkspacePath(file.path)}',
            compacted.value,
          );
        }
        caches.add(RecastScriptCache.fromJson(compacted.value));
      } on FormatException {
        await _quarantineInvalidEntityFile(
          file,
          WorkspacePaths.scriptRecastCacheDir,
        );
      }
    }
    return caches;
  }

  Future<void> _deleteRecastExhibitionIndex() async {
    await Future.wait([
      _deleteFileIfExists(WorkspacePaths.scriptRecastExhibitionIndex),
      _deleteFileIfExists(WorkspacePaths.scriptRecastExhibitionSummaryIndex),
    ]);
  }

  Future<List<RecastScriptCache>>
      _migrateLegacyTokenizerScriptsIntoRecastCaches(
    List<RecastScriptCache> caches,
  ) async {
    final legacyScripts = await _readTokenizerScriptDirectory();
    if (legacyScripts.isEmpty) {
      return caches;
    }

    final migrated = <RecastScriptCache>[];
    for (final script in legacyScripts) {
      if (_legacyTokenizerScriptHasRecastCache(script, [
        ...caches,
        ...migrated,
      ])) {
        continue;
      }
      migrated.add(_recastCacheFromLegacyTokenizerScript(script));
    }

    final next = [...caches, ...migrated]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    if (migrated.isNotEmpty) {
      await saveRecastScriptCaches(next);
    }
    await _writeEntityDirectory<TokenizerScript>(
      WorkspacePaths.tokenizerScriptsDir,
      const [],
      (entry) => entry.scriptId,
      (entry) => entry.toJson(),
    );
    return next;
  }

  bool _legacyTokenizerScriptHasRecastCache(
    TokenizerScript script,
    List<RecastScriptCache> caches,
  ) {
    final legacyId = script.scriptId.trim();
    final legacyPath = _normalizedWorkspacePath(script.sourceFolder);
    final legacyName = script.name.trim().toLowerCase();
    for (final cache in caches) {
      if (_sameNonEmpty(cache.scriptId, legacyId)) {
        return true;
      }
      if (legacyPath.isNotEmpty &&
          legacyPath == _normalizedWorkspacePath(cache.sourceRootPath)) {
        return true;
      }
      final snapshot = cache.scriptSnapshot;
      if (_sameNonEmpty(snapshot['id']?.toString(), legacyId)) {
        return true;
      }
      if (legacyPath.isNotEmpty &&
          legacyPath ==
              _normalizedWorkspacePath(snapshot['rootPath']?.toString())) {
        return true;
      }
      if (legacyPath.isEmpty &&
          legacyName.isNotEmpty &&
          legacyName == cache.scriptName.trim().toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  RecastScriptCache _recastCacheFromLegacyTokenizerScript(
    TokenizerScript script,
  ) {
    final snapshot = _scriptFromLegacyTokenizerScript(script);
    final scriptId = _fallback(script.scriptId, snapshot.id);
    return RecastScriptCache(
      scriptId: scriptId,
      scriptName: _fallback(script.name, snapshot.name),
      sourceRootPath: _fallback(script.sourceFolder, snapshot.rootPath),
      sourceFingerprint: _legacyTokenizerSourceFingerprint(script),
      sourceContentFingerprint: _legacyTokenizerContentFingerprint(script),
      updatedAt: script.updatedAt.toUtc(),
      mapping: RecastMapping.defaults(scriptId),
      scriptSnapshot: snapshot.toJson(),
    );
  }

  Script _scriptFromLegacyTokenizerScript(TokenizerScript script) {
    final frames = _legacyTokenizerFrames(script);
    return Script(
      id: _fallback(script.scriptId, _legacyScriptId(script)),
      name: _fallback(script.name, '未命名剧本'),
      rootPath: script.sourceFolder,
      frames: List.unmodifiable(frames),
      detectedSchema: _legacyDetectedSchema(frames),
      parseWarnings: const [],
      meta: {
        'frameCount': frames.length,
        'migratedFrom': 'tokenizerScript',
        if (script.categoryNames.isNotEmpty)
          'legacyCategoryNames': script.categoryNames,
        if (script.exhibitionVersionLabels.isNotEmpty)
          'legacyExhibitionVersionLabels': script.exhibitionVersionLabels,
        if (script.exhibitionCoverItemId?.trim().isNotEmpty == true)
          'legacyExhibitionCoverItemId': script.exhibitionCoverItemId!.trim(),
        if (script.imageAttachments.isNotEmpty)
          'legacyImageAttachments': [
            for (final attachment in script.imageAttachments)
              attachment.toJson(),
          ],
      },
    );
  }

  List<ScriptFrame> _legacyTokenizerFrames(TokenizerScript script) {
    final sourceIndexes = {
      for (final (index, sourceFile) in script.sourceFiles.indexed)
        sourceFile.fileId: index + 1,
    };
    final usedSourceFileIds = <String>{};
    final frames = <ScriptFrame>[];
    for (final (index, task) in script.imageTasks.indexed) {
      final sourceFile = task.sourceFile;
      usedSourceFileIds.add(sourceFile.fileId);
      frames.add(
        _legacyFrameFromTask(
          task,
          index: sourceIndexes[sourceFile.fileId] ?? index + 1,
        ),
      );
    }
    for (final (index, sourceFile) in script.sourceFiles.indexed) {
      if (usedSourceFileIds.contains(sourceFile.fileId)) {
        continue;
      }
      frames.add(_legacyFrameFromSource(sourceFile, index: index + 1));
    }
    frames.sort((left, right) => left.index.compareTo(right.index));
    return List.unmodifiable(frames);
  }

  ScriptFrame _legacyFrameFromTask(
    TokenizerImageTask task, {
    required int index,
  }) {
    final sourceFile = task.sourceFile;
    final prompt = _firstText([
          task.originalPrompt,
          task.parsedPrompt,
          task.finalPrompt,
        ]) ??
        '';
    return ScriptFrame(
      index: index,
      fileName: _fallback(
        sourceFile.fileName,
        _fileNameFromWorkspacePath(sourceFile.path),
      ),
      sourcePath: sourceFile.path,
      sourceImagePath: _legacyDefaultImagePath(sourceFile),
      rawJson: jsonEncode({
        'taskId': task.taskId,
        'sourceFile': sourceFile.toJson(),
        'prompt': prompt,
        'generationParams': task.generationParams,
      }),
      parsed: ParsedFrame(
        baseCaption: prompt,
        coords: _legacyRecastPoints(task.coords),
        generationParams: task.generationParams,
        sourcePayload: {
          'legacyTokenizerTaskId': task.taskId,
          'parseStatus': task.parseStatus,
          if (task.resolution != null) 'resolution': task.resolution,
        },
      ),
      detectedSchema: prompt.trim().isEmpty
          ? ScriptSchema.unknown
          : ScriptSchema.baseInline,
      parseStatus: task.reviewStatus == TokenizerTaskReviewStatus.failed
          ? ScriptFrameParseStatus.error
          : ScriptFrameParseStatus.parsed,
      warnings: task.warnings,
    );
  }

  ScriptFrame _legacyFrameFromSource(
    TokenizerSourceFile sourceFile, {
    required int index,
  }) {
    return ScriptFrame(
      index: index,
      fileName: _fallback(
        sourceFile.fileName,
        _fileNameFromWorkspacePath(sourceFile.path),
      ),
      sourcePath: sourceFile.path,
      sourceImagePath: _legacyDefaultImagePath(sourceFile),
      rawJson: jsonEncode({'sourceFile': sourceFile.toJson()}),
      parsed: ParsedFrame(
        sourcePayload: {'legacyTokenizerSourceFile': sourceFile.toJson()},
      ),
      detectedSchema: ScriptSchema.unknown,
      parseStatus: ScriptFrameParseStatus.parsed,
      warnings: sourceFile.exists ? const [] : const ['源文件缺失'],
    );
  }

  List<RecastPoint> _legacyRecastPoints(List<Map<String, num>> coords) {
    return [
      for (final coord in coords)
        if (coord['x'] != null && coord['y'] != null)
          RecastPoint(
            x: coord['x']!.toDouble(),
            y: coord['y']!.toDouble(),
          ),
    ];
  }

  ScriptSchema _legacyDetectedSchema(List<ScriptFrame> frames) {
    for (final frame in frames) {
      if (frame.detectedSchema != ScriptSchema.unknown) {
        return frame.detectedSchema;
      }
    }
    return ScriptSchema.unknown;
  }

  String _legacyTokenizerSourceFingerprint(TokenizerScript script) {
    return fingerprintJson(jsonEncode([
      script.scriptId,
      script.sourceFolder,
      for (final sourceFile in script.sourceFiles)
        [
          sourceFile.fileId,
          sourceFile.path,
          sourceFile.defaultImagePath,
          sourceFile.hash,
          sourceFile.modifiedAt?.toIso8601String(),
        ],
    ]));
  }

  String _legacyTokenizerContentFingerprint(TokenizerScript script) {
    return fingerprintJson(jsonEncode([
      script.scriptId,
      for (final task in script.imageTasks)
        [
          task.taskId,
          task.originalPrompt,
          task.parsedPrompt,
          task.finalPrompt,
          task.generationParams,
        ],
    ]));
  }

  String _legacyDefaultImagePath(TokenizerSourceFile sourceFile) {
    final defaultImagePath = sourceFile.defaultImagePath.trim();
    if (defaultImagePath.isNotEmpty) {
      return defaultImagePath;
    }
    return sourceFile.kind == TokenizerScriptSourceKind.image
        ? sourceFile.path
        : '';
  }

  String _legacyScriptId(TokenizerScript script) {
    return stableIdFromText(
      prefix: 'script',
      text: _fallback(script.sourceFolder, script.name),
      label: _fallback(script.name, 'script'),
    );
  }

  String _fallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : value;
  }

  String? _firstText(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  bool _sameNonEmpty(String? left, String? right) {
    final normalizedLeft = left?.trim();
    final normalizedRight = right?.trim();
    return normalizedLeft != null &&
        normalizedLeft.isNotEmpty &&
        normalizedRight != null &&
        normalizedRight.isNotEmpty &&
        normalizedLeft == normalizedRight;
  }

  String _normalizedWorkspacePath(String? path) {
    final normalized =
        path?.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '') ??
            '';
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _fileNameFromWorkspacePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.trim().isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  Future<Map<String, dynamic>> loadRecastKnowledgeBase() async {
    final workspaceRoot = _root;
    if (workspaceRoot == null) {
      throw StateError('No workspace is open.');
    }
    final file = File(
      _resolveFrom(workspaceRoot, WorkspacePaths.scriptRecastKnowledge),
    );
    if (!await file.exists()) {
      return const <String, dynamic>{};
    }
    final json = await _readJsonFileFrom(
      workspaceRoot,
      WorkspacePaths.scriptRecastKnowledge,
    );
    return Map.unmodifiable(_jsonMap(json));
  }

  Future<void> saveRecastKnowledgeBase(Map<String, dynamic> knowledgeBase) {
    return _writeJsonFile(
      WorkspacePaths.scriptRecastKnowledge,
      WorkspaceSanitizer.sanitizeMap(knowledgeBase),
    );
  }

  Future<List<TokenizerScript>> loadTokenizerScripts() {
    return _readTokenizerScriptDirectory();
  }

  Future<void> saveTokenizerScripts(List<TokenizerScript> scripts) {
    return _writeEntityDirectory(
      WorkspacePaths.tokenizerScriptsDir,
      scripts,
      (entry) => entry.scriptId,
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
    final path = _resolveFrom(workspaceRoot, relativePath);
    return Isolate.run(() => _decodeJsonFileFromPath(path));
  }

  Future<void> _writeJsonFile(String relativePath, Object? value) {
    return _writeFileAtomically(relativePath, _encodedJsonFile(value));
  }

  Future<void> _writeFileAtomically(
    String relativePath,
    String contents,
  ) {
    final file = _file(relativePath);
    final previousWrite =
        _pendingWritesByRelativePath[relativePath] ?? Future<void>.value();
    final nextWrite = previousWrite
        .catchError((Object _) {})
        .then((_) => _writeFileAtomicallyNow(file, contents));
    _pendingWritesByRelativePath[relativePath] = nextWrite;
    nextWrite.then<void>(
      (_) => _clearPendingWrite(relativePath, nextWrite),
      onError: (_, __) => _clearPendingWrite(relativePath, nextWrite),
    );
    return nextWrite;
  }

  Future<void> _deleteFileIfExists(String relativePath) {
    final file = _file(relativePath);
    final previousWrite =
        _pendingWritesByRelativePath[relativePath] ?? Future<void>.value();
    final nextWrite = previousWrite.catchError((Object _) {}).then((_) async {
      if (!await file.exists()) {
        return;
      }
      try {
        await file.delete();
      } on FileSystemException {
        if (await file.exists()) {
          rethrow;
        }
      }
    });
    _pendingWritesByRelativePath[relativePath] = nextWrite;
    nextWrite.then<void>(
      (_) => _clearPendingWrite(relativePath, nextWrite),
      onError: (_, __) => _clearPendingWrite(relativePath, nextWrite),
    );
    return nextWrite;
  }

  void _clearPendingWrite(String relativePath, Future<void> write) {
    if (identical(_pendingWritesByRelativePath[relativePath], write)) {
      _pendingWritesByRelativePath.remove(relativePath);
    }
  }

  Future<void> _writeFileAtomicallyNow(
    File file,
    String contents,
  ) async {
    await file.parent.create(recursive: true);
    final tempFile = File(
      '${file.path}.tmp-${DateTime.now().toUtc().microsecondsSinceEpoch}',
    );
    try {
      await tempFile.writeAsString(contents);
      await _atomicFileCommitter(tempFile, file.path);
    } catch (_) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } on FileSystemException {
        // A failed save should not leave a temp cleanup failure as the error.
      }
      rethrow;
    }
  }

  Future<void> _ensureWorkspaceScaffold() async {
    for (final directory in WorkspacePaths.directories) {
      await _directory(directory).create(recursive: true);
    }

    for (final filePath in WorkspacePaths.emptyArrayFiles) {
      final file = _file(filePath);
      if (!await file.exists()) {
        await _writeJsonFile(filePath, <dynamic>[]);
      }
    }

    for (final filePath in WorkspacePaths.emptyObjectFiles) {
      final file = _file(filePath);
      if (!await file.exists()) {
        await _writeJsonFile(filePath, <String, dynamic>{});
      }
    }
  }

  Future<List<T>> _readEntityDirectory<T>(
    String relativePath,
    T Function(dynamic json) fromJson,
  ) async {
    final directory = _directory(relativePath);
    final decoded = await Isolate.run(
      () => _decodeJsonEntityDirectory(
        _JsonEntityDirectoryRequest(
          directoryPath: directory.path,
          skipInvalid: false,
          repairLegacyEntities: false,
        ),
      ),
    );
    final values = <T>[];
    for (final file in decoded.files) {
      values.add(fromJson(file.value));
    }
    return values;
  }

  Future<List<TokenizerScript>> _readTokenizerScriptDirectory() async {
    final directory = _directory(WorkspacePaths.tokenizerScriptsDir);
    if (!await directory.exists()) {
      return const [];
    }
    var hasJson = false;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && entry.path.endsWith('.json')) {
        hasJson = true;
        break;
      }
    }
    if (!hasJson) {
      return const [];
    }
    return _readEntityDirectorySkippingInvalid(
      WorkspacePaths.tokenizerScriptsDir,
      (json) => TokenizerScript.fromJson(Map<String, dynamic>.from(json)),
    );
  }

  Future<List<T>> _readEntityDirectorySkippingInvalid<T>(
    String relativePath,
    T Function(dynamic json) fromJson,
  ) async {
    final directory = _directory(relativePath);
    final decoded = await Isolate.run(
      () => _decodeJsonEntityDirectory(
        _JsonEntityDirectoryRequest(
          directoryPath: directory.path,
          skipInvalid: true,
          repairLegacyEntities: true,
        ),
      ),
    );
    for (final invalidPath in decoded.invalidPaths) {
      await _quarantineInvalidEntityFile(File(invalidPath), relativePath);
    }

    final values = <T>[];
    for (final file in decoded.files) {
      try {
        values.add(fromJson(file.value));
      } on FormatException {
        await _quarantineInvalidEntityFile(File(file.path), relativePath);
      }
    }
    return values;
  }

  Future<List<ProductionPlan>> _readProductionPlanDirectory() async {
    final directory = _directory(WorkspacePaths.deterministicPlansDir);
    final decoded = await Isolate.run(
      () => _readProductionPlansFromDirectoryPath(directory.path),
    );
    for (final invalidPath in decoded.invalidPaths) {
      await _quarantineInvalidEntityFile(
        File(invalidPath),
        WorkspacePaths.deterministicPlansDir,
      );
    }
    return decoded.plans;
  }

  Future<void> _quarantineInvalidEntityFile(
    File file,
    String relativeDirectory,
  ) async {
    final quarantineDirectory = _directory('$relativeDirectory/_invalid');
    await quarantineDirectory.create(recursive: true);
    final fileName = file.path.split(Platform.pathSeparator).last;
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final target = await _unusedFile(
      quarantineDirectory,
      '$timestamp-$fileName',
    );
    try {
      await file.rename(target.path);
    } on FileSystemException {
      try {
        await file.copy(target.path);
        await file.delete();
      } on FileSystemException {
        // Loading must keep going even when the bad file is temporarily locked.
      }
    }
  }

  Future<File> _unusedFile(Directory directory, String fileName) async {
    final separator = Platform.pathSeparator;
    for (var attempt = 0; attempt < 1000; attempt += 1) {
      final suffix = attempt == 0 ? '' : '-$attempt';
      final target = File('${directory.path}$separator$suffix$fileName');
      if (!await target.exists()) {
        return target;
      }
    }
    return File(
      '${directory.path}$separator${DateTime.now().microsecondsSinceEpoch}'
      '-$fileName',
    );
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
    final nextFileNames = <String>{};
    for (final value in values) {
      final fileName = '${idOf(value)}.json';
      nextFileNames.add(fileName);
      await _writeJsonFile('$relativePath/$fileName', toJson(value));
    }
    for (final file in existing) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      if (nextFileNames.contains(fileName)) continue;
      try {
        await file.delete();
      } on FileSystemException {
        // Another save/load pass may have already moved or removed it.
      }
    }
  }

  File _file(String relativePath) {
    return File(_resolve(relativePath));
  }

  Directory _directory(String relativePath) {
    return Directory(_resolve(relativePath));
  }

  String _scriptRecastCacheRelativePath(String scriptId) {
    final safeId = safeWorkspaceEntityId(prefix: 'script', id: scriptId);
    return WorkspacePaths.scriptRecastCacheFile(safeId);
  }

  void _checkBlock(String block) {
    if (!_isSafeLibraryBlock(block)) {
      throw ArgumentError.value(block, 'block', 'Unknown workspace block.');
    }
  }

  Future<List<String>> _listLibraryBlocks(String relativeDir) async {
    final blocks = <String>{...WorkspacePaths.blocks};
    final dir = _directory(relativeDir);
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.toLowerCase().endsWith('.json')) continue;
        final block = name.substring(0, name.length - 5);
        if (_isSafeLibraryBlock(block)) {
          blocks.add(block);
        }
      }
    }
    return List.unmodifiable(blocks.toList()..sort());
  }

  bool _isSafeLibraryBlock(String block) {
    final trimmed = block.trim();
    return trimmed.isNotEmpty &&
        trimmed != '.' &&
        trimmed != '..' &&
        !trimmed.contains('\u0000') &&
        !trimmed.contains('/') &&
        !trimmed.contains('\\');
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

class _WorkspaceFileFingerprint {
  final String name;
  final int length;
  final DateTime modifiedAt;

  const _WorkspaceFileFingerprint({
    required this.name,
    required this.length,
    required this.modifiedAt,
  });

  factory _WorkspaceFileFingerprint.fromJson(Map<String, dynamic> json) {
    return _WorkspaceFileFingerprint(
      name: json['name'] as String? ?? '',
      length: (json['length'] as num?)?.toInt() ?? -1,
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'length': length,
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
      };
}

bool _sameWorkspaceFingerprints(
  List<_WorkspaceFileFingerprint> left,
  List<_WorkspaceFileFingerprint> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final leftItem = left[index];
    final rightItem = right[index];
    if (leftItem.name != rightItem.name ||
        leftItem.length != rightItem.length ||
        leftItem.modifiedAt.toUtc() != rightItem.modifiedAt.toUtc()) {
      return false;
    }
  }
  return true;
}

List<String> _normalizedScriptExhibitionCategoryNames(
  Iterable<dynamic> rawValues,
) {
  final namesByKey = <String, String>{};
  for (final value in rawValues) {
    final rawName = value is Map
        ? value['name'] ?? value['title'] ?? value['categoryName']
        : value;
    final name = rawName?.toString().trim();
    if (name == null || name.isEmpty) {
      continue;
    }
    namesByKey.putIfAbsent(name.toLowerCase(), () => name);
  }
  final names = namesByKey.values.toList(growable: false)
    ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return List.unmodifiable(names);
}

Map<String, List<String>> _normalizedScriptExhibitionCategoryAssignments(
  Map<dynamic, dynamic> rawAssignments,
) {
  final assignmentsByCategoryKey = <String, MapEntry<String, Set<String>>>{};
  for (final entry in rawAssignments.entries) {
    final categoryName = entry.key.toString().trim();
    if (categoryName.isEmpty) {
      continue;
    }
    final ids = _normalizedScriptExhibitionScriptIds(
      entry.value is Iterable ? entry.value as Iterable : const [],
    );
    if (ids.isEmpty) {
      continue;
    }
    final categoryKey = categoryName.toLowerCase();
    final existing = assignmentsByCategoryKey[categoryKey];
    if (existing == null) {
      assignmentsByCategoryKey[categoryKey] =
          MapEntry(categoryName, ids.toSet());
    } else {
      existing.value.addAll(ids);
    }
  }
  final entries = assignmentsByCategoryKey.values.toList(growable: false)
    ..sort(
      (left, right) =>
          left.key.toLowerCase().compareTo(right.key.toLowerCase()),
    );
  return Map.unmodifiable({
    for (final entry in entries)
      entry.key: List<String>.unmodifiable(
        _normalizedScriptExhibitionScriptIds(entry.value),
      ),
  });
}

List<String> _normalizedScriptExhibitionScriptIds(Iterable<dynamic> rawValues) {
  final ids = <String>{};
  for (final value in rawValues) {
    final id = value.toString().trim();
    if (id.isNotEmpty) {
      ids.add(id);
    }
  }
  final sorted = ids.toList(growable: false)
    ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return List.unmodifiable(sorted);
}

class _RecastExhibitionIndexBuildResult {
  final List<_WorkspaceFileFingerprint> fingerprints;
  final List<RecastExhibitionScript> scripts;

  const _RecastExhibitionIndexBuildResult({
    required this.fingerprints,
    required this.scripts,
  });
}

class _RecastExhibitionSourceRootRebind {
  final String sourceRootPath;
  final List<RecastExhibitionFrame> frames;

  const _RecastExhibitionSourceRootRebind({
    required this.sourceRootPath,
    required this.frames,
  });
}

class _RecastExhibitionIndexLoadRequest {
  final String cacheDirectoryPath;
  final String indexPath;
  final bool summaryOnly;

  const _RecastExhibitionIndexLoadRequest({
    required this.cacheDirectoryPath,
    required this.indexPath,
    required this.summaryOnly,
  });
}

_RecastExhibitionIndexBuildResult _loadOrBuildRecastExhibitionIndex(
  _RecastExhibitionIndexLoadRequest request,
) {
  final fingerprints =
      _recastCacheFileFingerprintsFromDirectoryPath(request.cacheDirectoryPath);
  final indexed = request.summaryOnly
      ? _loadRecastExhibitionSummaryIndexFromFile(
          path: request.indexPath,
          expectedFingerprints: fingerprints,
        )
      : _loadRecastExhibitionIndexFromFile(
          path: request.indexPath,
          expectedFingerprints: fingerprints,
        );
  if (indexed != null) {
    return _RecastExhibitionIndexBuildResult(
      fingerprints: fingerprints,
      scripts: _latestRecastExhibitionScripts(indexed),
    );
  }

  final rebuilt = request.summaryOnly
      ? _buildRecastExhibitionSummaryIndexFromCacheDirectoryPath(
          request.cacheDirectoryPath,
        )
      : _buildRecastExhibitionIndexFromCacheDirectoryPath(
          request.cacheDirectoryPath,
        );
  final latestScripts = _latestRecastExhibitionScripts(rebuilt.scripts);
  if (request.summaryOnly) {
    _writeRecastExhibitionSummaryIndexFile(
      path: request.indexPath,
      fingerprints: rebuilt.fingerprints,
      scripts: latestScripts,
    );
  } else {
    _writeRecastExhibitionIndexFile(
      path: request.indexPath,
      fingerprints: rebuilt.fingerprints,
      scripts: latestScripts,
    );
  }
  return _RecastExhibitionIndexBuildResult(
    fingerprints: rebuilt.fingerprints,
    scripts: latestScripts,
  );
}

List<RecastExhibitionScript> _latestRecastExhibitionScripts(
  Iterable<RecastExhibitionScript> scripts,
) {
  final groups = <String, List<RecastExhibitionScript>>{};
  for (final script in scripts) {
    final sourceKey = _normalizedRecastExhibitionSourcePath(
      script.sourceRootPath,
    );
    final key = sourceKey.isNotEmpty
        ? 'source:$sourceKey'
        : 'id:${script.scriptId.trim().toLowerCase()}';
    groups.putIfAbsent(key, () => <RecastExhibitionScript>[]).add(script);
  }

  final result = <RecastExhibitionScript>[];
  for (final group in groups.values) {
    group.sort(_compareRecastExhibitionCacheFreshness);
    final latest = group.last;
    final categoryNames = <String, String>{};
    final versionLabels = <String, String>{};
    String? coverItemId;
    for (final script in group) {
      for (final category in script.categoryNames) {
        final trimmed = category.trim();
        if (trimmed.isNotEmpty) {
          categoryNames.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
        }
      }
      versionLabels.addAll(script.versionLabels);
      if (script.coverItemId?.trim().isNotEmpty == true) {
        coverItemId = script.coverItemId!.trim();
      }
    }
    result.add(
      RecastExhibitionScript(
        scriptId: latest.scriptId,
        scriptName: latest.scriptName,
        sourceRootPath: latest.sourceRootPath,
        updatedAt: latest.updatedAt,
        detectedSchema: latest.detectedSchema,
        frames: latest.frames,
        frameCount: latest.frameCount,
        summaryOnly: latest.summaryOnly,
        imageAttachments: latest.imageAttachments,
        categoryNames: List.unmodifiable(categoryNames.values),
        versionLabels: Map.unmodifiable(versionLabels),
        coverItemId: latest.coverItemId?.trim().isNotEmpty == true
            ? latest.coverItemId!.trim()
            : coverItemId,
      ),
    );
  }
  result.sort((left, right) => left.scriptId.compareTo(right.scriptId));
  return List.unmodifiable(result);
}

int _compareRecastExhibitionCacheFreshness(
  RecastExhibitionScript left,
  RecastExhibitionScript right,
) {
  final byUpdatedAt = left.updatedAt.compareTo(right.updatedAt);
  if (byUpdatedAt != 0) return byUpdatedAt;
  final leftCurrent = _isCurrentPathDerivedExhibitionId(left);
  final rightCurrent = _isCurrentPathDerivedExhibitionId(right);
  if (leftCurrent != rightCurrent) {
    return leftCurrent ? 1 : -1;
  }
  final byFrames = left.displayFrameCount.compareTo(right.displayFrameCount);
  if (byFrames != 0) return byFrames;
  return left.scriptId.compareTo(right.scriptId);
}

bool _isCurrentPathDerivedExhibitionId(RecastExhibitionScript script) {
  final sourceRootPath = script.sourceRootPath.trim();
  if (sourceRootPath.isEmpty) return false;
  return script.scriptId ==
      ScriptRecastParserService.scriptIdForDirectory(
        Directory(sourceRootPath),
      );
}

String _normalizedRecastExhibitionSourcePath(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

List<String> _matchingRecastScriptCacheIds({
  required String directoryPath,
  required String scriptId,
  required String scriptName,
  required String sourceRootPath,
}) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return const [];
  }
  final targetIdentities = {
    scriptId,
    scriptName,
    sourceRootPath,
  }
      .map(_normalizedRecastCacheIdentity)
      .where((value) => value.isNotEmpty)
      .toSet();
  if (targetIdentities.isEmpty) {
    return const [];
  }
  final matchingIds = <String>{};
  final files = directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.json'));
  for (final file in files) {
    try {
      final source = _readRecastCacheHeaderPrefix(
        file,
        _recastCacheHeaderReadBytes,
      );
      final cacheScriptId = _jsonStringField(source, 'scriptId')?.trim();
      if (cacheScriptId == null || cacheScriptId.isEmpty) {
        continue;
      }
      final cacheIdentities = [
        cacheScriptId,
        _jsonStringField(source, 'scriptName'),
        _jsonStringField(source, 'sourceRootPath'),
      ].map(_normalizedRecastCacheIdentity);
      if (cacheIdentities.any(targetIdentities.contains)) {
        matchingIds.add(cacheScriptId);
      }
    } on FileSystemException {
      // A concurrent cache writer may temporarily hide or replace one file.
    }
  }
  return matchingIds.toList(growable: false);
}

String _normalizedRecastCacheIdentity(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '')
      .toLowerCase();
}

List<_WorkspaceFileFingerprint> _recastCacheFileFingerprintsFromDirectoryPath(
  String directoryPath,
) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return const [];
  }
  final files = directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  return List.unmodifiable([
    for (final file in files)
      _WorkspaceFileFingerprint(
        name: _workspaceLeafName(file.path),
        length: file.lengthSync(),
        modifiedAt: file.lastModifiedSync().toUtc(),
      ),
  ]);
}

List<RecastExhibitionScript>? _loadRecastExhibitionIndexFromFile({
  required String path,
  required List<_WorkspaceFileFingerprint> expectedFingerprints,
}) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final decoded = _jsonMap(jsonDecode(File(path).readAsStringSync()));
    if (decoded['schemaVersion'] != _scriptRecastExhibitionIndexSchemaVersion) {
      return null;
    }
    final cachedFingerprints = [
      for (final value in decoded['cacheFiles'] as List? ?? const [])
        if (value is Map)
          _WorkspaceFileFingerprint.fromJson(value.cast<String, dynamic>()),
    ];
    if (!_sameWorkspaceFingerprints(cachedFingerprints, expectedFingerprints)) {
      return null;
    }
    return [
      for (final value in decoded['scripts'] as List? ?? const [])
        if (value is Map)
          RecastExhibitionScript.fromJson(value.cast<String, dynamic>()),
    ];
  } catch (_) {
    return null;
  }
}

List<RecastExhibitionScript>? _loadRecastExhibitionSummaryIndexFromFile({
  required String path,
  required List<_WorkspaceFileFingerprint> expectedFingerprints,
}) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final decoded = _jsonMap(jsonDecode(File(path).readAsStringSync()));
    if (decoded['schemaVersion'] !=
        _scriptRecastExhibitionSummaryIndexSchemaVersion) {
      return null;
    }
    final cachedFingerprints = [
      for (final value in decoded['cacheFiles'] as List? ?? const [])
        if (value is Map)
          _WorkspaceFileFingerprint.fromJson(value.cast<String, dynamic>()),
    ];
    if (!_sameWorkspaceFingerprints(cachedFingerprints, expectedFingerprints)) {
      return null;
    }
    return [
      for (final value in decoded['scripts'] as List? ?? const [])
        if (value is Map)
          RecastExhibitionScript.fromJson(value.cast<String, dynamic>()),
    ];
  } catch (_) {
    return null;
  }
}

_RecastExhibitionIndexBuildResult
    _buildRecastExhibitionIndexFromCacheDirectoryPath(String directoryPath) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return const _RecastExhibitionIndexBuildResult(
      fingerprints: [],
      scripts: [],
    );
  }

  final files = directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  final fingerprints = <_WorkspaceFileFingerprint>[];
  final scripts = <RecastExhibitionScript>[];
  for (final file in files) {
    final stat = file.statSync();
    fingerprints.add(
      _WorkspaceFileFingerprint(
        name: _workspaceLeafName(file.path),
        length: stat.size,
        modifiedAt: stat.modified.toUtc(),
      ),
    );
    final source = file.readAsStringSync();
    if (source.trim().isEmpty) {
      continue;
    }
    try {
      final decodedSource = _decodeWorkspaceEntityJson(source);
      final decoded = _jsonMap(decodedSource.value);
      final compacted = RecastCacheJsonCodec.compact(decoded);
      final cache = RecastScriptCache.fromJson(compacted.value);
      final script = RecastExhibitionScript.tryFromCache(cache);
      if (script != null) {
        scripts.add(_rebindRecastExhibitionScriptSourceRoot(script));
      }
    } catch (_) {
      // The exhibition index is a read-optimization path. Bad cache files are
      // ignored here so foreground navigation can still open with valid data.
    }
  }

  return _RecastExhibitionIndexBuildResult(
    fingerprints: List.unmodifiable(fingerprints),
    scripts: List.unmodifiable(scripts),
  );
}

_RecastExhibitionIndexBuildResult
    _buildRecastExhibitionSummaryIndexFromCacheDirectoryPath(
  String directoryPath,
) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return const _RecastExhibitionIndexBuildResult(
      fingerprints: [],
      scripts: [],
    );
  }

  final files = directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  final fingerprints = <_WorkspaceFileFingerprint>[];
  final scripts = <RecastExhibitionScript>[];
  for (final file in files) {
    final stat = file.statSync();
    fingerprints.add(
      _WorkspaceFileFingerprint(
        name: _workspaceLeafName(file.path),
        length: stat.size,
        modifiedAt: stat.modified.toUtc(),
      ),
    );
    final script = _readRecastExhibitionSummaryFromCacheFile(file) ??
        _readRecastExhibitionSummaryFromFullCacheFile(file);
    if (script != null) {
      scripts.add(script);
    }
  }

  return _RecastExhibitionIndexBuildResult(
    fingerprints: List.unmodifiable(fingerprints),
    scripts: List.unmodifiable(scripts),
  );
}

RecastExhibitionScript? _readRecastExhibitionSummaryFromFullCacheFile(
  File file,
) {
  final source = _tryReadTransientJsonFile(file);
  if (source == null || source.trim().isEmpty) {
    return null;
  }
  try {
    final decodedSource = _decodeWorkspaceEntityJson(source);
    final decoded = _jsonMap(decodedSource.value);
    final compacted = RecastCacheJsonCodec.compact(decoded);
    final cache = RecastScriptCache.fromJson(compacted.value);
    final detail = RecastExhibitionScript.tryFromCache(cache);
    if (detail == null) {
      return null;
    }
    final rebound = _rebindRecastExhibitionScriptSourceRoot(detail);
    return RecastExhibitionScript(
      scriptId: rebound.scriptId,
      scriptName: rebound.scriptName,
      sourceRootPath: rebound.sourceRootPath,
      updatedAt: rebound.updatedAt,
      detectedSchema: rebound.detectedSchema,
      frames: rebound.frames.isEmpty ? const [] : [rebound.frames.first],
      frameCount: rebound.frames.length,
      summaryOnly: true,
      categoryNames: rebound.categoryNames,
      versionLabels: rebound.versionLabels,
      coverItemId: rebound.coverItemId,
    );
  } catch (_) {
    return null;
  }
}

RecastExhibitionScript? _readRecastExhibitionSummaryFromCacheFile(File file) {
  try {
    final source = _readRecastCacheHeaderPrefix(
      file,
      _recastCacheHeaderReadBytes,
    );
    final scriptId = _jsonStringField(source, 'scriptId')?.trim();
    final scriptName = _jsonStringField(source, 'scriptName')?.trim();
    final sourceRootPath = _jsonStringField(source, 'sourceRootPath')?.trim();
    final updatedAtText = _jsonStringField(source, 'updatedAt')?.trim();
    final sourceFingerprint =
        _jsonStringField(source, 'sourceFingerprint')?.trim();
    final categoryNames = _summaryCategoryNamesFromRecastCacheFile(
      file: file,
      headerSource: source,
    );
    if (scriptId == null || scriptId.isEmpty) {
      return null;
    }
    final frames = _recastSummaryFramesWithSnapshotFallback(
      file: file,
      fingerprintFrames: _recastSummaryFramesFromFingerprint(
        sourceFingerprint,
        resolveSiblingImages: true,
      ),
    );
    final reboundSource = _rebindRecastExhibitionFramesSourceRoot(
      sourceRootPath: sourceRootPath ?? '',
      frames: frames,
    );
    return RecastExhibitionScript(
      scriptId: scriptId,
      scriptName: scriptName ?? '',
      sourceRootPath: reboundSource.sourceRootPath,
      updatedAt: DateTime.tryParse(updatedAtText ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      detectedSchema: ScriptSchema.unknown,
      frames: reboundSource.frames.isEmpty
          ? const []
          : [reboundSource.frames.first],
      frameCount: reboundSource.frames.length,
      summaryOnly: true,
      categoryNames: categoryNames,
    );
  } catch (_) {
    return null;
  }
}

List<String> _summaryCategoryNamesFromRecastCacheFile({
  required File file,
  required String headerSource,
}) {
  final topLevelCategories =
      _jsonStringArrayField(headerSource, 'exhibitionCategoryNames');
  if (topLevelCategories.isNotEmpty) {
    return _normalizedScriptExhibitionCategoryNames(topLevelCategories);
  }
  try {
    final tail = _readFileTailAsString(
      file,
      _recastCacheMetadataTailReadBytes,
    );
    return _normalizedScriptExhibitionCategoryNames(
      _jsonStringArrayField(tail, 'legacyCategoryNames'),
    );
  } catch (_) {
    return const [];
  }
}

String _readFileTailAsString(File file, int byteLimit) {
  final length = file.lengthSync();
  if (length <= 0) return '';
  final maxBytes = length < byteLimit ? length : byteLimit;
  final start = length - maxBytes;
  final handle = file.openSync();
  try {
    handle.setPositionSync(start);
    return utf8.decode(handle.readSync(maxBytes), allowMalformed: true);
  } finally {
    handle.closeSync();
  }
}

String _readRecastCacheHeaderPrefix(File file, int byteLimit) {
  final length = file.lengthSync();
  if (length <= 0) return '';
  final maxBytes = length < byteLimit ? length : byteLimit;
  final handle = file.openSync();
  final buffer = StringBuffer();
  var bytesRead = 0;
  try {
    while (bytesRead < maxBytes) {
      final remaining = maxBytes - bytesRead;
      final chunkSize = remaining < _recastCacheHeaderChunkBytes
          ? remaining
          : _recastCacheHeaderChunkBytes;
      final bytes = handle.readSync(chunkSize);
      if (bytes.isEmpty) break;
      bytesRead += bytes.length;
      buffer.write(utf8.decode(bytes, allowMalformed: true));
      final source = buffer.toString();
      if (_hasCompleteJsonStringField(source, 'sourceFingerprint') ||
          source.contains('"mapping"') ||
          source.contains('"scriptSnapshot"')) {
        return source;
      }
    }
    return buffer.toString();
  } finally {
    handle.closeSync();
  }
}

bool _hasCompleteJsonStringField(String source, String key) {
  final keyIndex = source.indexOf('"$key"');
  if (keyIndex < 0) return false;
  final colonIndex = source.indexOf(':', keyIndex + key.length + 2);
  if (colonIndex < 0) return false;
  final openingQuoteIndex = source.indexOf('"', colonIndex + 1);
  if (openingQuoteIndex < 0) return false;
  var escaped = false;
  for (var index = openingQuoteIndex + 1; index < source.length; index += 1) {
    final char = source[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') return true;
  }
  return false;
}

String? _jsonStringField(String source, String key) {
  final pattern = RegExp(
    '"${RegExp.escape(key)}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
  );
  final match = pattern.firstMatch(source);
  if (match == null) return null;
  try {
    return jsonDecode('"${match.group(1) ?? ''}"') as String;
  } catch (_) {
    return null;
  }
}

List<String> _jsonStringArrayField(String source, String key) {
  final pattern = RegExp('"${RegExp.escape(key)}"\\s*:\\s*\\[');
  final match = pattern.firstMatch(source);
  if (match == null) return const [];
  var index = match.end;
  final values = <String>[];
  while (index < source.length) {
    while (index < source.length) {
      final char = source[index];
      if (char == ' ' ||
          char == '\n' ||
          char == '\r' ||
          char == '\t' ||
          char == ',') {
        index += 1;
        continue;
      }
      break;
    }
    if (index >= source.length) return const [];
    final char = source[index];
    if (char == ']') {
      return List.unmodifiable(values);
    }
    if (char != '"') {
      return const [];
    }
    final start = index;
    index += 1;
    var escaped = false;
    while (index < source.length) {
      final current = source[index];
      if (escaped) {
        escaped = false;
      } else if (current == r'\') {
        escaped = true;
      } else if (current == '"') {
        index += 1;
        try {
          final decoded = jsonDecode(source.substring(start, index));
          if (decoded is String && decoded.trim().isNotEmpty) {
            values.add(decoded);
          }
        } catch (_) {
          return const [];
        }
        break;
      }
      index += 1;
    }
  }
  return const [];
}

List<RecastExhibitionFrame> _recastSummaryFramesFromFingerprint(
  String? sourceFingerprint, {
  bool resolveSiblingImages = false,
}) {
  final fingerprint = sourceFingerprint?.trim();
  if (fingerprint == null || fingerprint.isEmpty) {
    return const [];
  }
  final frames = <RecastExhibitionFrame>[];
  for (final part in fingerprint.split('|').skip(2)) {
    final firstSeparator = part.indexOf(':');
    if (firstSeparator <= 0) continue;
    final secondSeparator = part.indexOf(':', firstSeparator + 1);
    final lastSeparator = part.lastIndexOf(':');
    if (secondSeparator <= firstSeparator || lastSeparator <= secondSeparator) {
      continue;
    }
    final index = int.tryParse(part.substring(0, firstSeparator));
    final fileName = part.substring(firstSeparator + 1, secondSeparator).trim();
    final sourcePath =
        part.substring(secondSeparator + 1, lastSeparator).trim();
    if (index == null || fileName.isEmpty && sourcePath.isEmpty) {
      continue;
    }
    frames.add(
      RecastExhibitionFrame(
        index: index,
        fileName: fileName,
        sourcePath: sourcePath,
        sourceImagePath: resolveSiblingImages
            ? _existingRecastSummarySiblingImagePath(sourcePath) ?? ''
            : '',
        parseStatus: ScriptFrameParseStatus.parsed,
      ),
    );
  }
  return List.unmodifiable(frames);
}

List<RecastExhibitionFrame> _recastSummaryFramesWithSnapshotFallback({
  required File file,
  required List<RecastExhibitionFrame> fingerprintFrames,
}) {
  if (!_needsSnapshotImageFallback(fingerprintFrames)) {
    return fingerprintFrames;
  }
  final snapshotFrames = _recastSummaryFramesFromSnapshotFile(file);
  if (snapshotFrames.isEmpty) {
    return fingerprintFrames;
  }
  if (fingerprintFrames.isEmpty) {
    return snapshotFrames;
  }

  final snapshotFramesByKey = {
    for (final frame in snapshotFrames) _summaryFrameKey(frame): frame,
  };
  var changed = false;
  final fallbackFrames = <RecastExhibitionFrame>[];
  for (final (index, frame) in fingerprintFrames.indexed) {
    if (frame.sourceImagePath.trim().isNotEmpty ||
        _isRecastSummaryImagePath(frame.sourcePath)) {
      fallbackFrames.add(frame);
      continue;
    }
    final snapshotFrame = snapshotFramesByKey[_summaryFrameKey(frame)] ??
        (index < snapshotFrames.length ? snapshotFrames[index] : null);
    final sourceImagePath = snapshotFrame?.sourceImagePath.trim() ?? '';
    if (sourceImagePath.isEmpty) {
      fallbackFrames.add(frame);
      continue;
    }
    changed = true;
    fallbackFrames.add(
      RecastExhibitionFrame(
        index: frame.index,
        fileName: frame.fileName,
        sourcePath: frame.sourcePath,
        sourceImagePath: sourceImagePath,
        parseStatus: frame.parseStatus,
      ),
    );
  }
  return changed ? List.unmodifiable(fallbackFrames) : fingerprintFrames;
}

bool _needsSnapshotImageFallback(List<RecastExhibitionFrame> frames) {
  if (frames.isEmpty) {
    return true;
  }
  final firstFrame = frames.first;
  return firstFrame.sourceImagePath.trim().isEmpty &&
      !_isRecastSummaryImagePath(firstFrame.sourcePath);
}

List<RecastExhibitionFrame> _recastSummaryFramesFromSnapshotFile(File file) {
  try {
    final decoded = _jsonMap(jsonDecode(file.readAsStringSync()));
    final scriptSnapshot = decoded['scriptSnapshot'];
    if (scriptSnapshot is! Map) {
      return const [];
    }
    final script = Script.fromJson(scriptSnapshot.cast<String, dynamic>());
    return List.unmodifiable([
      for (final frame in script.frames)
        RecastExhibitionFrame(
          index: frame.index,
          fileName: frame.fileName,
          sourcePath: frame.sourcePath,
          sourceImagePath: frame.sourceImagePath,
          parseStatus: frame.parseStatus,
        ),
    ]);
  } catch (_) {
    return const [];
  }
}

RecastExhibitionScript _rebindRecastExhibitionScriptSourceRoot(
  RecastExhibitionScript script,
) {
  final rebound = _rebindRecastExhibitionFramesSourceRoot(
    sourceRootPath: script.sourceRootPath,
    frames: script.frames,
  );
  if (rebound.sourceRootPath == script.sourceRootPath &&
      identical(rebound.frames, script.frames)) {
    return script;
  }
  return script.copyWith(
    sourceRootPath: rebound.sourceRootPath,
    frames: rebound.frames,
  );
}

_RecastExhibitionSourceRootRebind _rebindRecastExhibitionFramesSourceRoot({
  required String sourceRootPath,
  required List<RecastExhibitionFrame> frames,
}) {
  final trimmedRoot = sourceRootPath.trim();
  final resolvedRoot = _resolveExistingRecastExhibitionSourceRoot(trimmedRoot);
  if (resolvedRoot == null) {
    return _RecastExhibitionSourceRootRebind(
      sourceRootPath: sourceRootPath,
      frames: frames,
    );
  }
  final needsFileRebind = _recastExhibitionFramesNeedFileRebind(frames);
  if (resolvedRoot == trimmedRoot && !needsFileRebind) {
    return _RecastExhibitionSourceRootRebind(
      sourceRootPath: sourceRootPath,
      frames: frames,
    );
  }
  final filesByLeaf = _recastExhibitionFilesByLeaf(resolvedRoot);
  if (filesByLeaf.isEmpty) {
    return _RecastExhibitionSourceRootRebind(
      sourceRootPath: sourceRootPath,
      frames: frames,
    );
  }
  return _RecastExhibitionSourceRootRebind(
    sourceRootPath: resolvedRoot,
    frames: List.unmodifiable([
      for (final frame in frames)
        _rebindRecastExhibitionFrameSourceRoot(
          frame,
          sourceRootPath: resolvedRoot,
          filesByLeaf: filesByLeaf,
        ),
    ]),
  );
}

String? _resolveExistingRecastExhibitionSourceRoot(String sourceRootPath) {
  final trimmed = sourceRootPath.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (Directory(trimmed).existsSync()) {
    return trimmed;
  }
  for (final candidate in _recastExhibitionMovedSourceRootCandidates(trimmed)) {
    if (Directory(candidate).existsSync()) {
      return Directory(candidate).path;
    }
  }
  return null;
}

Iterable<String> _recastExhibitionMovedSourceRootCandidates(
  String sourceRootPath,
) sync* {
  final segments = sourceRootPath
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  for (var index = 0; index < segments.length; index += 1) {
    if (segments[index] != '作品集') {
      continue;
    }
    if (index + 1 < segments.length && segments[index + 1] == '带图精品') {
      continue;
    }
    yield _pathFromSegments([
      ...segments.take(index + 1),
      '带图精品',
      ...segments.skip(index + 1),
    ]);
  }
}

RecastExhibitionFrame _rebindRecastExhibitionFrameSourceRoot(
  RecastExhibitionFrame frame, {
  required String sourceRootPath,
  required Map<String, File> filesByLeaf,
}) {
  final sourceLeaf = _firstNonEmptyString([
    _workspaceLeafName(frame.sourcePath),
    frame.fileName,
  ]);
  final sourceFile = _fileForRecastExhibitionLeaf(filesByLeaf, sourceLeaf);
  final imageLeaf = _workspaceLeafName(frame.sourceImagePath);
  final imageFile = _fileForRecastExhibitionLeaf(filesByLeaf, imageLeaf);
  final pairedImageFile = _pairedRecastExhibitionImageForLeaf(
    filesByLeaf,
    sourceLeaf,
  );
  final fallbackImageFile = imageFile ??
      (_isRecastSummaryImagePath(sourceFile?.path ?? '') ? sourceFile : null) ??
      pairedImageFile ??
      _indexedRecastExhibitionImageForFrame(filesByLeaf, frame.index);
  final reboundSourcePath = sourceFile?.path ??
      (_isRecastSummaryImagePath(frame.sourcePath)
          ? fallbackImageFile?.path
          : null) ??
      _joinPath(sourceRootPath, sourceLeaf);
  final reboundSourceImagePath = _firstNonEmptyString([
    fallbackImageFile?.path ?? '',
    _isRecastSummaryImagePath(reboundSourcePath) ? reboundSourcePath : '',
  ]);
  if (reboundSourcePath == frame.sourcePath &&
      reboundSourceImagePath == frame.sourceImagePath) {
    return frame;
  }
  return RecastExhibitionFrame(
    index: frame.index,
    fileName: frame.fileName,
    sourcePath: reboundSourcePath,
    sourceImagePath: reboundSourceImagePath,
    prompt: frame.prompt,
    parseStatus: frame.parseStatus,
    generationParams: frame.generationParams,
  );
}

bool _recastExhibitionFramesNeedFileRebind(
  List<RecastExhibitionFrame> frames,
) {
  for (final frame in frames.take(3)) {
    final imagePath = _firstNonEmptyString([
      frame.sourceImagePath,
      _isRecastSummaryImagePath(frame.sourcePath) ? frame.sourcePath : '',
    ]);
    if (imagePath.isNotEmpty && !File(imagePath).existsSync()) {
      return true;
    }
  }
  return false;
}

Map<String, File> _recastExhibitionFilesByLeaf(String sourceRootPath) {
  final directory = Directory(sourceRootPath);
  if (!directory.existsSync()) {
    return const {};
  }
  final files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList()
    ..sort((left, right) {
      final byDepth = _pathDepth(left.path).compareTo(_pathDepth(right.path));
      if (byDepth != 0) return byDepth;
      return left.path.compareTo(right.path);
    });
  final result = <String, File>{};
  for (final file in files) {
    result.putIfAbsent(
      _recastExhibitionFileKey(_workspaceLeafName(file.path)),
      () => file,
    );
  }
  return Map.unmodifiable(result);
}

File? _fileForRecastExhibitionLeaf(Map<String, File> filesByLeaf, String leaf) {
  final key = _recastExhibitionFileKey(leaf);
  return key.isEmpty ? null : filesByLeaf[key];
}

File? _pairedRecastExhibitionImageForLeaf(
  Map<String, File> filesByLeaf,
  String sourceLeaf,
) {
  final stem = _pathStem(sourceLeaf);
  if (stem.isEmpty) {
    return null;
  }
  for (final extension in _recastSummaryImageExtensions) {
    final file = _fileForRecastExhibitionLeaf(filesByLeaf, '$stem$extension');
    if (file != null) {
      return file;
    }
  }
  return null;
}

File? _indexedRecastExhibitionImageForFrame(
  Map<String, File> filesByLeaf,
  int frameIndex,
) {
  final images = [
    for (final file in filesByLeaf.values)
      if (_isRecastSummaryImagePath(file.path)) file,
  ]..sort(_compareRecastExhibitionImageFiles);
  if (images.isEmpty) {
    return null;
  }
  final index = frameIndex > 0 ? frameIndex - 1 : frameIndex;
  if (index >= 0 && index < images.length) {
    return images[index];
  }
  return images.first;
}

int _compareRecastExhibitionImageFiles(File left, File right) {
  final leftNumber = _lastNumberInPathLeaf(left.path);
  final rightNumber = _lastNumberInPathLeaf(right.path);
  if (leftNumber != null && rightNumber != null && leftNumber != rightNumber) {
    return leftNumber.compareTo(rightNumber);
  }
  return left.path.compareTo(right.path);
}

int? _lastNumberInPathLeaf(String path) {
  final match = RegExp(r'(\d+)(?!.*\d)').firstMatch(_workspaceLeafName(path));
  return match == null ? null : int.tryParse(match.group(1) ?? '');
}

String _recastExhibitionFileKey(String leaf) => leaf.trim().toLowerCase();

String _pathFromSegments(Iterable<String> segments) {
  final normalized = segments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  return normalized.join(Platform.pathSeparator);
}

String _joinPath(String rootPath, String leaf) {
  final trimmedLeaf = leaf.trim();
  if (trimmedLeaf.isEmpty) {
    return '';
  }
  return '$rootPath${Platform.pathSeparator}$trimmedLeaf';
}

String _pathStem(String path) {
  final leaf = _workspaceLeafName(path);
  final dot = leaf.lastIndexOf('.');
  return dot <= 0 ? leaf : leaf.substring(0, dot);
}

String _firstNonEmptyString(Iterable<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

int _pathDepth(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .length;
}

String _summaryFrameKey(RecastExhibitionFrame frame) {
  return '${frame.index}|${_workspaceLeafName(frame.fileName).toLowerCase()}';
}

String? _existingRecastSummarySiblingImagePath(String sourcePath) {
  final trimmed = sourcePath.trim();
  if (trimmed.isEmpty || _isRecastSummaryImagePath(trimmed)) {
    return _isRecastSummaryImagePath(trimmed) ? trimmed : null;
  }
  final lastForwardSlash = trimmed.lastIndexOf('/');
  final lastBackslash = trimmed.lastIndexOf('\\');
  final lastSeparator =
      lastForwardSlash > lastBackslash ? lastForwardSlash : lastBackslash;
  final dot = trimmed.lastIndexOf('.');
  if (dot <= lastSeparator) {
    return null;
  }
  final prefix = trimmed.substring(0, dot);
  for (final extension in _recastSummaryImageExtensions) {
    final candidate = '$prefix$extension';
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

bool _isRecastSummaryImagePath(String path) {
  final lower = path.toLowerCase();
  return _recastSummaryImageExtensions.any(lower.endsWith);
}

const _recastSummaryImageExtensions = ['.png', '.jpg', '.jpeg', '.webp'];

void _writeRecastExhibitionIndexFile({
  required String path,
  required List<_WorkspaceFileFingerprint> fingerprints,
  required List<RecastExhibitionScript> scripts,
}) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${jsonEncode({
          'schemaVersion': _scriptRecastExhibitionIndexSchemaVersion,
          'cacheFiles': [
            for (final fingerprint in fingerprints) fingerprint.toJson(),
          ],
          'scripts': [
            for (final script in scripts) script.toJson(),
          ],
        })}\n',
  );
}

void _writeRecastExhibitionSummaryIndexFile({
  required String path,
  required List<_WorkspaceFileFingerprint> fingerprints,
  required List<RecastExhibitionScript> scripts,
}) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${jsonEncode({
          'schemaVersion': _scriptRecastExhibitionSummaryIndexSchemaVersion,
          'cacheFiles': [
            for (final fingerprint in fingerprints) fingerprint.toJson(),
          ],
          'scripts': [
            for (final script in scripts) script.toJson(),
          ],
        })}\n',
  );
}

String _workspaceLeafName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

class _DecodedJsonSource {
  final dynamic value;
  final bool repaired;

  const _DecodedJsonSource({
    required this.value,
    required this.repaired,
  });
}

class _RecastScriptCacheSnapshotRestoreRequest {
  final String cacheFilePath;
  final String? importPath;

  const _RecastScriptCacheSnapshotRestoreRequest({
    required this.cacheFilePath,
    this.importPath,
  });
}

class _RecastScriptCacheSnapshotRestoreResult {
  final RecastScriptCacheSnapshotRestore? restore;
  final bool invalid;

  const _RecastScriptCacheSnapshotRestoreResult({
    this.restore,
    this.invalid = false,
  });
}

class _JsonEntityDirectoryRequest {
  final String directoryPath;
  final bool skipInvalid;
  final bool repairLegacyEntities;

  const _JsonEntityDirectoryRequest({
    required this.directoryPath,
    required this.skipInvalid,
    required this.repairLegacyEntities,
  });
}

class _DecodedJsonFile {
  final String path;
  final dynamic value;

  const _DecodedJsonFile({
    required this.path,
    required this.value,
  });
}

class _DecodedJsonEntityDirectory {
  final List<_DecodedJsonFile> files;
  final List<String> invalidPaths;

  const _DecodedJsonEntityDirectory({
    required this.files,
    required this.invalidPaths,
  });
}

class _DecodedProductionPlanDirectory {
  final List<ProductionPlan> plans;
  final List<String> invalidPaths;

  const _DecodedProductionPlanDirectory({
    required this.plans,
    required this.invalidPaths,
  });
}

dynamic _decodeJsonFileFromPath(String path) {
  return jsonDecode(File(path).readAsStringSync());
}

_RecastScriptCacheSnapshotRestoreResult
    _restoreRecastScriptCacheSnapshotFromFile(
  _RecastScriptCacheSnapshotRestoreRequest request,
) {
  final file = File(request.cacheFilePath);
  if (!file.existsSync()) {
    return const _RecastScriptCacheSnapshotRestoreResult();
  }
  final source = _tryReadTransientJsonFile(file);
  if (source == null) {
    return const _RecastScriptCacheSnapshotRestoreResult();
  }
  if (source.trim().isEmpty) {
    return const _RecastScriptCacheSnapshotRestoreResult(invalid: true);
  }
  try {
    final decodedSource = _decodeWorkspaceEntityJson(source);
    final decoded = _jsonMap(decodedSource.value);
    final compacted = RecastCacheJsonCodec.compact(decoded);
    if (decodedSource.repaired || compacted.changed) {
      file.writeAsStringSync(_encodedJsonFile(compacted.value));
    }
    final cache = RecastScriptCache.fromJson(compacted.value);
    final frames = cache.scriptSnapshot['frames'];
    if (frames is! List || frames.isEmpty) {
      return const _RecastScriptCacheSnapshotRestoreResult();
    }
    var script = Script.fromJson(cache.scriptSnapshot);
    final normalizedImportPath = request.importPath?.trim();
    if (normalizedImportPath != null && normalizedImportPath.isNotEmpty) {
      script = rebindCachedScriptToImportDirectory(
        script,
        Directory(normalizedImportPath),
      );
    }
    return _RecastScriptCacheSnapshotRestoreResult(
      restore: RecastScriptCacheSnapshotRestore(
        cache: _recastCacheWithoutScriptSnapshot(cache),
        script: script,
      ),
    );
  } on FormatException {
    return const _RecastScriptCacheSnapshotRestoreResult(invalid: true);
  }
}

RecastScriptCache _recastCacheWithoutScriptSnapshot(
  RecastScriptCache cache,
) {
  return cache.copyWith(
    scriptSnapshot: const {},
  );
}

String _encodedJsonFile(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(value)}\n';
}

_DecodedJsonEntityDirectory _decodeJsonEntityDirectory(
  _JsonEntityDirectoryRequest request,
) {
  final directory = Directory(request.directoryPath);
  if (!directory.existsSync()) {
    return const _DecodedJsonEntityDirectory(files: [], invalidPaths: []);
  }
  final entries = directory
      .listSync()
      .whereType<File>()
      .where((entry) => entry.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  final files = <_DecodedJsonFile>[];
  final invalidPaths = <String>[];
  for (final file in entries) {
    final source = _tryReadTransientJsonFile(file);
    if (source == null) continue;
    if (request.skipInvalid && source.trim().isEmpty) {
      invalidPaths.add(file.path);
      continue;
    }
    try {
      final value = request.repairLegacyEntities
          ? _decodeWorkspaceEntityJson(source).value
          : jsonDecode(source);
      files.add(_DecodedJsonFile(path: file.path, value: value));
    } on FormatException {
      if (!request.skipInvalid) rethrow;
      invalidPaths.add(file.path);
    }
  }
  return _DecodedJsonEntityDirectory(
    files: List.unmodifiable(files),
    invalidPaths: List.unmodifiable(invalidPaths),
  );
}

_DecodedProductionPlanDirectory _readProductionPlansFromDirectoryPath(
  String directoryPath,
) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return const _DecodedProductionPlanDirectory(plans: [], invalidPaths: []);
  }
  final entries = directory
      .listSync()
      .whereType<File>()
      .where((entry) => entry.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  final plans = <ProductionPlan>[];
  final invalidPaths = <String>[];
  for (final file in entries) {
    final source = _tryReadTransientJsonFile(file);
    if (source == null) continue;
    if (source.trim().isEmpty) {
      invalidPaths.add(file.path);
      continue;
    }
    try {
      plans.add(ProductionPlan.fromJson(jsonDecode(source)));
    } on FormatException {
      invalidPaths.add(file.path);
    }
  }
  return _DecodedProductionPlanDirectory(
    plans: List.unmodifiable(plans),
    invalidPaths: List.unmodifiable(invalidPaths),
  );
}

ProductionPlan? _readProductionPlanFromFilePath(String filePath) {
  final source = _tryReadTransientJsonFile(File(filePath));
  if (source == null) return null;
  if (source.trim().isEmpty) {
    throw const FormatException('Production plan file is empty.');
  }
  return ProductionPlan.fromJson(jsonDecode(source));
}

String? _tryReadTransientJsonFile(File file) {
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

Future<void> _renameFileWithTransientAccessRetries(
  File source,
  String targetPath,
) async {
  for (var attempt = 0;; attempt += 1) {
    try {
      await source.rename(targetPath);
      return;
    } on FileSystemException catch (error) {
      if (!_isTransientRenameAccessDenied(error) ||
          attempt >= _atomicRenameRetryDelays.length) {
        rethrow;
      }
      await Future<void>.delayed(_atomicRenameRetryDelays[attempt]);
    }
  }
}

bool _isTransientRenameAccessDenied(FileSystemException error) {
  final errorCode = error.osError?.errorCode;
  if (errorCode == 5 || errorCode == 32) {
    return true;
  }
  final detail = [
    error.message,
    error.osError?.message,
  ].whereType<String>().join(' ').toLowerCase();
  return detail.contains('cannot rename') &&
      (detail.contains('access') ||
          detail.contains('denied') ||
          detail.contains('sharing violation') ||
          detail.contains('used by another process') ||
          detail.contains('拒绝访问'));
}

_DecodedJsonSource _decodeWorkspaceEntityJson(String source) {
  try {
    return _DecodedJsonSource(value: jsonDecode(source), repaired: false);
  } on FormatException catch (error) {
    final repairedSource = _repairLegacyUnescapedBackslashes(source);
    if (repairedSource == source) {
      rethrow;
    }
    try {
      return _DecodedJsonSource(
        value: jsonDecode(repairedSource),
        repaired: true,
      );
    } on FormatException {
      throw error;
    }
  }
}

String _repairLegacyUnescapedBackslashes(String source) {
  final buffer = StringBuffer();
  var inString = false;
  var escaped = false;
  var changed = false;

  for (var index = 0; index < source.length; index += 1) {
    final char = source[index];
    if (!inString) {
      if (char == '"') {
        inString = true;
      }
      buffer.write(char);
      continue;
    }

    if (escaped) {
      escaped = false;
      buffer.write(char);
      continue;
    }

    if (char == '"') {
      inString = false;
      buffer.write(char);
      continue;
    }

    if (char == '\\') {
      if (_preserveJsonEscape(source, index)) {
        escaped = true;
        buffer.write(char);
      } else {
        changed = true;
        buffer.write(r'\\');
      }
      continue;
    }

    buffer.write(char);
  }

  return changed ? buffer.toString() : source;
}

bool _preserveJsonEscape(String source, int backslashIndex) {
  if (backslashIndex + 1 >= source.length) {
    return false;
  }
  final next = source[backslashIndex + 1];
  if (next == '"' || next == '\\' || next == '/') {
    return true;
  }
  if (next != 'u' || backslashIndex + 5 >= source.length) {
    return false;
  }
  for (var offset = 2; offset <= 5; offset += 1) {
    if (!_isHexDigit(source[backslashIndex + offset])) {
      return false;
    }
  }
  return true;
}

bool _isHexDigit(String char) {
  final codeUnit = char.codeUnitAt(0);
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);
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
