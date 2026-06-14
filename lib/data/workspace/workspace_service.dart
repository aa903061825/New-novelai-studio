import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/workspace/importers/artist_studio_importer.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/models/script_recast_knowledge.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/data/studio/tools/stable_id.dart';
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

  Future<void> saveArtistChains(List<ArtistChain> artistChains) {
    return _writeJsonFile(
      WorkspacePaths.artistChains,
      artistChains.map((artistChain) => artistChain.toJson()).toList(),
    );
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

  Future<List<ProductionPlan>> loadProductionPlans() {
    return _readProductionPlanDirectory();
  }

  Future<void> saveProductionPlans(List<ProductionPlan> plans) {
    return _writeEntityDirectory(
      WorkspacePaths.deterministicPlansDir,
      plans,
      (entry) => entry.id,
      (entry) => entry.toJson(),
    );
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
      final compacted = _compactRecastScriptCacheJson(decoded);
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

  Future<void> saveRecastScriptCache(RecastScriptCache cache) {
    return _writeJsonFile(
      _scriptRecastCacheRelativePath(cache.scriptId),
      _compactRecastScriptCacheJson(cache.toJson()).value,
    );
  }

  Future<void> saveRecastScriptCaches(List<RecastScriptCache> caches) {
    return _writeEntityDirectory(
      WorkspacePaths.scriptRecastCacheDir,
      caches,
      (entry) => safeWorkspaceEntityId(prefix: 'script', id: entry.scriptId),
      (entry) => _compactRecastScriptCacheJson(entry.toJson()).value,
    );
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
        final compacted = _compactRecastScriptCacheJson(decoded);
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
      _sanitizeKnowledgeMap(knowledgeBase),
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

  Future<List<TokenizerScript>> _readTokenizerScriptDirectory() {
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
      final source = await file.readAsString();
      if (source.trim().isEmpty) {
        await _quarantineInvalidEntityFile(file, relativePath);
        continue;
      }
      try {
        values.add(fromJson(_decodeWorkspaceEntityJson(source).value));
      } on FormatException {
        await _quarantineInvalidEntityFile(file, relativePath);
      }
    }
    return values;
  }

  Future<List<ProductionPlan>> _readProductionPlanDirectory() async {
    final directory = _directory(WorkspacePaths.deterministicPlansDir);
    if (!await directory.exists()) {
      return const [];
    }

    final entries = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
    entries.sort((left, right) => left.path.compareTo(right.path));

    final values = <ProductionPlan>[];
    for (final file in entries) {
      final source = await file.readAsString();
      if (source.trim().isEmpty) {
        await _quarantineInvalidEntityFile(
          file,
          WorkspacePaths.deterministicPlansDir,
        );
        continue;
      }
      try {
        values.add(ProductionPlan.fromJson(jsonDecode(source)));
      } on FormatException {
        await _quarantineInvalidEntityFile(
          file,
          WorkspacePaths.deterministicPlansDir,
        );
      }
    }
    return values;
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

  String _scriptRecastCacheRelativePath(String scriptId) {
    final safeId = safeWorkspaceEntityId(prefix: 'script', id: scriptId);
    return WorkspacePaths.scriptRecastCacheFile(safeId);
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

class _DecodedJsonSource {
  final dynamic value;
  final bool repaired;

  const _DecodedJsonSource({
    required this.value,
    required this.repaired,
  });
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

const _recastHeavyPayloadKeys = <String>{
  'director_reference_descriptions',
  'director_reference_images',
  'director_reference_information_extracted',
  'director_reference_secondary_strength_values',
  'director_reference_strength_values',
  'reference_image',
  'reference_image_multiple',
  'reference_images',
  'reference_information_extracted',
  'reference_information_extracted_multiple',
  'reference_strength',
  'reference_strength_multiple',
};

const _recastHeavyPayloadKeyNames = <String>{
  'directorreferencedescriptions',
  'directorreferenceimages',
  'directorreferenceinformationextracted',
  'directorreferencesecondarystrengthvalues',
  'directorreferencestrengthvalues',
  'referenceimage',
  'referenceimagemultiple',
  'referenceimages',
  'referenceinformationextracted',
  'referenceinformationextractedmultiple',
  'referencestrength',
  'referencestrengthmultiple',
};

class _CompactedJsonMap {
  final Map<String, dynamic> value;
  final bool changed;

  const _CompactedJsonMap(this.value, this.changed);
}

class _CompactedJsonValue {
  final dynamic value;
  final bool changed;

  const _CompactedJsonValue(this.value, this.changed);
}

_CompactedJsonMap _compactRecastScriptCacheJson(Map<String, dynamic> json) {
  var changed = false;
  final result = Map<String, dynamic>.from(json);
  final scriptSnapshot = result['scriptSnapshot'];
  if (scriptSnapshot is Map) {
    final compacted = _compactRecastScriptSnapshot(_jsonMap(scriptSnapshot));
    if (compacted.changed) {
      result['scriptSnapshot'] = compacted.value;
      changed = true;
    }
  }
  return _CompactedJsonMap(result, changed);
}

_CompactedJsonMap _compactRecastScriptSnapshot(Map<String, dynamic> json) {
  var changed = false;
  final result = Map<String, dynamic>.from(json);
  final frames = result['frames'];
  if (frames is List) {
    var framesChanged = false;
    final nextFrames = <dynamic>[];
    for (final frame in frames) {
      if (frame is Map) {
        final compacted = _compactRecastFrameJson(_jsonMap(frame));
        nextFrames.add(compacted.value);
        framesChanged = framesChanged || compacted.changed;
      } else {
        nextFrames.add(frame);
      }
    }
    if (framesChanged) {
      result['frames'] = nextFrames;
      changed = true;
    }
  }

  final meta = result['meta'];
  if (meta is Map) {
    final compacted = _compactRecastPayloadMap(_jsonMap(meta));
    if (compacted.changed) {
      result['meta'] = compacted.value;
      changed = true;
    }
  }

  return _CompactedJsonMap(result, changed);
}

_CompactedJsonMap _compactRecastFrameJson(Map<String, dynamic> json) {
  var changed = false;
  final result = Map<String, dynamic>.from(json);

  final rawJson = _compactRecastRawJson(result['rawJson']);
  if (rawJson.changed) {
    result['rawJson'] = rawJson.value;
    changed = true;
  }

  final parsed = result['parsed'];
  if (parsed is Map) {
    final compacted = _compactRecastParsedFrameJson(_jsonMap(parsed));
    if (compacted.changed) {
      result['parsed'] = compacted.value;
      changed = true;
    }
  }

  return _CompactedJsonMap(result, changed);
}

_CompactedJsonMap _compactRecastParsedFrameJson(Map<String, dynamic> json) {
  var changed = false;
  final result = Map<String, dynamic>.from(json);

  for (final key in const ['generationParams', 'sourcePayload']) {
    final compacted = _compactRecastPayloadValue(result[key]);
    if (compacted.changed) {
      result[key] = compacted.value;
      changed = true;
    }
  }

  return _CompactedJsonMap(result, changed);
}

_CompactedJsonMap _compactRecastPayloadMap(Map<String, dynamic> json) {
  final compacted = _compactRecastPayloadValue(json);
  return _CompactedJsonMap(
    Map<String, dynamic>.from(compacted.value as Map),
    compacted.changed,
  );
}

_CompactedJsonValue _compactRecastPayloadValue(dynamic value) {
  if (value is Map) {
    var changed = false;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final rawKey = entry.key;
      final key = rawKey is String ? rawKey : rawKey.toString();
      if (rawKey is! String) {
        changed = true;
      }
      if (_isHeavyRecastPayloadKey(key)) {
        changed = true;
        continue;
      }

      final compacted = key == 'Comment'
          ? _compactRecastCommentValue(entry.value)
          : _compactRecastPayloadValue(entry.value);
      result[key] = compacted.value;
      changed = changed || compacted.changed;
    }
    return _CompactedJsonValue(result, changed);
  }

  if (value is List) {
    var changed = false;
    final result = <dynamic>[];
    for (final item in value) {
      final compacted = _compactRecastPayloadValue(item);
      result.add(compacted.value);
      changed = changed || compacted.changed;
    }
    return _CompactedJsonValue(changed ? result : value, changed);
  }

  return _CompactedJsonValue(value, false);
}

_CompactedJsonValue _compactRecastCommentValue(dynamic value) {
  if (value is! String) {
    return _compactRecastPayloadValue(value);
  }
  if (!_containsHeavyRecastPayloadKey(value)) {
    return _CompactedJsonValue(value, false);
  }

  try {
    final decoded = jsonDecode(value);
    final compacted = _compactRecastPayloadValue(decoded);
    if (compacted.changed) {
      return _CompactedJsonValue(jsonEncode(compacted.value), true);
    }
  } on FormatException {
    if (value.length > 32768) {
      return const _CompactedJsonValue('', true);
    }
  }

  return _CompactedJsonValue(value, false);
}

_CompactedJsonValue _compactRecastRawJson(dynamic value) {
  if (value is! String || !_containsHeavyRecastPayloadKey(value)) {
    return _CompactedJsonValue(value, false);
  }

  try {
    final decoded = jsonDecode(value);
    final compacted = _compactRecastPayloadValue(decoded);
    if (compacted.changed) {
      return _CompactedJsonValue(jsonEncode(compacted.value), true);
    }
  } on FormatException {
    if (value.length > 32768) {
      return const _CompactedJsonValue('', true);
    }
  }

  return _CompactedJsonValue(value, false);
}

bool _containsHeavyRecastPayloadKey(String value) {
  for (final key in _recastHeavyPayloadKeys) {
    if (value.contains(key)) {
      return true;
    }
  }
  return false;
}

bool _isHeavyRecastPayloadKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return _recastHeavyPayloadKeys.contains(key) ||
      _recastHeavyPayloadKeyNames.contains(normalized);
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

Map<String, dynamic> _sanitizeKnowledgeMap(Map<String, dynamic> value) {
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
