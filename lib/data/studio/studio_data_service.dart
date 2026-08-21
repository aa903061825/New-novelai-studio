import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/studio/services/studio_cache_import_service.dart';
import 'package:novel_studio/data/studio/studio_codex_source.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:path_provider/path_provider.dart';

const _codexMigrationStateSchemaVersion = 1;
const _codexMigrationStatePath =
    'library/codex/inspirations_migration_state.json';

class StudioDataService {
  final WorkspaceService workspaceService;
  final StudioCacheImportService cacheImportService;
  final Directory? bundledCacheRoot;
  final Future<Map<String, dynamic>?> Function()? legacyArtistSeedLoader;
  final Future<Map<String, dynamic>?> Function()? legacyCodexSeedLoader;

  StudioDataService({
    required this.workspaceService,
    StudioCacheImportService? cacheImportService,
    this.bundledCacheRoot,
    this.legacyArtistSeedLoader,
    this.legacyCodexSeedLoader,
  }) : cacheImportService = cacheImportService ?? StudioCacheImportService();

  Future<void> initializeForApp() async {
    final supportDir = await getApplicationSupportDirectory();
    final studioDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}novel_studio',
    );
    await initializeAt(studioDir);
  }

  Future<void> initializeAt(
    Directory root, {
    List<Directory> legacyWorkspaceRoots = const [],
  }) async {
    var manifest = File(
      '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    );
    if (!await manifest.exists() && await _hasWorkspaceData(root)) {
      await workspaceService.recoverWorkspace(root.path);
      manifest = File(
        '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
      );
    }
    await _restoreRicherLegacyWorkspaceIfNeeded(
      targetRoot: root,
      legacyWorkspaceRoots: legacyWorkspaceRoots,
    );
    manifest = File(
      '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    );
    if (!await manifest.exists()) {
      await cacheImportService.autoImportBundledCache(
        targetRoot: root,
        bundledCacheRoot: bundledCacheRoot,
      );
      manifest = File(
        '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
      );
    }
    if (await manifest.exists()) {
      await workspaceService.openWorkspace(root.path);
      await _seedLegacyArtistDataIfEmpty();
      await _backfillLegacyArtistImages();
      if (await _backfillLegacyArtistPreviewFamilies()) {
        await _deleteAssetCatalogCache(root);
      }
      await _migrateCodexOutOfWorkspaceInspirations();
      return;
    }
    await workspaceService.createWorkspace(root.path);
    await _seedLegacyArtistDataIfEmpty();
    await _backfillLegacyArtistImages();
    if (await _backfillLegacyArtistPreviewFamilies()) {
      await _deleteAssetCatalogCache(root);
    }
  }

  Future<bool> _hasWorkspaceData(Directory root) async {
    if (!await root.exists()) return false;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          entity.path !=
              '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}') {
        return true;
      }
    }
    return false;
  }

  Future<void> _restoreRicherLegacyWorkspaceIfNeeded({
    required Directory targetRoot,
    required List<Directory> legacyWorkspaceRoots,
  }) async {
    final targetPath = _normalizedPath(targetRoot);
    final seen = <String>{};
    for (final legacyRoot in legacyWorkspaceRoots) {
      final legacyPath = _normalizedPath(legacyRoot);
      if (legacyPath == targetPath || !seen.add(legacyPath)) {
        continue;
      }
      if (!await _hasWorkspaceManifest(legacyRoot)) {
        continue;
      }
      if (!await _shouldRestoreLegacyWorkspace(targetRoot, legacyRoot)) {
        continue;
      }
      await cacheImportService.importFromDirectory(
        legacyRoot,
        targetRoot: targetRoot,
        createBackup: await _hasWorkspaceManifest(targetRoot),
      );
      await _deleteAssetCatalogCache(targetRoot);
      return;
    }
  }

  Future<bool> _shouldRestoreLegacyWorkspace(
    Directory targetRoot,
    Directory legacyRoot,
  ) async {
    final legacy = await _workspaceAssetSignature(legacyRoot);
    if (!legacy.hasManifest || !legacy.hasAssets) {
      return false;
    }

    final target = await _workspaceAssetSignature(targetRoot);
    if (!target.hasManifest) {
      return true;
    }
    if (target.characterAndOutfitPreviewRefCount == 0 &&
        legacy.characterAndOutfitPreviewRefCount > 0) {
      return true;
    }
    if (target.previewRefCount == 0 && legacy.previewRefCount > 0) {
      return true;
    }
    if (target.lastDataModifiedMicros > legacy.lastDataModifiedMicros &&
        target.previewRefCount > 0) {
      return false;
    }
    if (legacy.assetCount > target.assetCount &&
        legacy.previewRefCount > target.previewRefCount) {
      return true;
    }
    return target.referenceFileCount == 0 &&
        legacy.referenceFileCount > 0 &&
        legacy.previewRefCount >= target.previewRefCount;
  }

  Future<_WorkspaceAssetSignature> _workspaceAssetSignature(
    Directory root,
  ) async {
    final hasManifest = await _hasWorkspaceManifest(root);
    final characterFile = _workspaceFile(root, WorkspacePaths.characters);
    final artistFile = _workspaceFile(root, WorkspacePaths.artistChains);
    final characters = await _readJsonList(characterFile);
    final artistChains = await _readJsonList(artistFile);
    var outfitCount = 0;
    var characterPreviewRefCount = 0;
    var outfitPreviewRefCount = 0;
    var artistPreviewRefCount = 0;

    for (final entry in characters.whereType<Map>()) {
      characterPreviewRefCount += _imageRefCount(entry['imageRefs']);
      final outfits = entry['outfits'];
      if (outfits is List) {
        outfitCount += outfits.length;
        for (final outfit in outfits.whereType<Map>()) {
          outfitPreviewRefCount += _imageRefCount(outfit['imageRefs']);
        }
      }
    }
    for (final entry in artistChains.whereType<Map>()) {
      artistPreviewRefCount += _imageRefCount(entry['imageRefs']);
    }

    return _WorkspaceAssetSignature(
      hasManifest: hasManifest,
      characterCount: characters.length,
      outfitCount: outfitCount,
      artistChainCount: artistChains.length,
      characterPreviewRefCount: characterPreviewRefCount,
      outfitPreviewRefCount: outfitPreviewRefCount,
      artistPreviewRefCount: artistPreviewRefCount,
      referenceFileCount: await _referenceFileCount(root),
      lastDataModifiedMicros: await _lastModifiedMicros([
        characterFile,
        artistFile,
      ]),
    );
  }

  Future<List<dynamic>> _readJsonList(File file) async {
    if (!await file.exists()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  int _imageRefCount(dynamic value) {
    if (value is! List) {
      return 0;
    }
    return value
        .whereType<String>()
        .where((ref) => ref.trim().isNotEmpty)
        .length;
  }

  Future<int> _referenceFileCount(Directory root) async {
    final referencesRoot = Directory(
      '${root.path}${Platform.pathSeparator}assets'
      '${Platform.pathSeparator}references',
    );
    if (!await referencesRoot.exists()) {
      return 0;
    }
    var count = 0;
    await for (final entity in referencesRoot.list(recursive: true)) {
      if (entity is File) {
        count += 1;
      }
    }
    return count;
  }

  Future<int> _lastModifiedMicros(List<File> files) async {
    var latest = 0;
    for (final file in files) {
      if (!await file.exists()) {
        continue;
      }
      final modified = (await file.stat()).modified.microsecondsSinceEpoch;
      if (modified > latest) {
        latest = modified;
      }
    }
    return latest;
  }

  Future<bool> _hasWorkspaceManifest(Directory root) {
    return _workspaceFile(root, WorkspacePaths.manifest).exists();
  }

  File _workspaceFile(Directory root, String relativePath) {
    return File(
      '${root.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
  }

  Future<void> _deleteAssetCatalogCache(Directory root) async {
    final cache = _workspaceFile(root, WorkspacePaths.assetCatalogCache);
    if (await cache.exists()) {
      await cache.delete();
    }
  }

  String _normalizedPath(Directory directory) {
    return directory.absolute.path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator)
        .toLowerCase();
  }

  Future<void> _seedLegacyArtistDataIfEmpty() async {
    final artistChains = await workspaceService.loadArtistChains();
    final characters = await workspaceService.loadCharacters();
    if (artistChains.isNotEmpty || characters.isNotEmpty) {
      return;
    }

    final seed = await _loadLegacyArtistSeed();
    if (seed == null) return;

    final seedArtistChains = _decodeList<ArtistChain>(
      seed['artistChains'],
      ArtistChain.fromJson,
    );
    final seedCharacters = _decodeList<CharacterEntry>(
      seed['characters'],
      CharacterEntry.fromJson,
    );
    if (seedArtistChains.isEmpty && seedCharacters.isEmpty) return;

    if (seedArtistChains.isNotEmpty) {
      await workspaceService.saveArtistChains(seedArtistChains);
    }
    if (seedCharacters.isNotEmpty) {
      await workspaceService.saveCharacters(seedCharacters);
    }
  }

  Future<Map<String, dynamic>?> _loadLegacyArtistSeed() async {
    return _loadJsonSeed(
      customLoader: legacyArtistSeedLoader,
      assetPath: 'assets/json/legacy_artist_studio_seed.json',
    );
  }

  Future<void> _backfillLegacyArtistImages() async {
    final artistChains = await workspaceService.loadArtistChains();
    if (artistChains.every((artistChain) => artistChain.imageRefs.isNotEmpty)) {
      return;
    }

    final seed = await _loadLegacyArtistSeed();
    if (seed == null) return;

    final seedArtistChains = _decodeList<ArtistChain>(
      seed['artistChains'],
      ArtistChain.fromJson,
    );
    if (seedArtistChains.isEmpty) return;

    final seedById = {
      for (final artistChain in seedArtistChains) artistChain.id: artistChain,
    };
    final seedByPrompt = {
      for (final artistChain in seedArtistChains)
        if (artistChain.prompt.trim().isNotEmpty)
          artistChain.prompt.trim(): artistChain,
    };

    var changed = false;
    final updated = [
      for (final artistChain in artistChains)
        if (artistChain.allPreviewRefs.isNotEmpty)
          artistChain
        else
          _withSeedImages(
            artistChain,
            seedById[artistChain.id] ?? seedByPrompt[artistChain.prompt.trim()],
            onChanged: () => changed = true,
          ),
    ];

    if (changed) {
      await workspaceService.saveArtistChains(updated);
    }
  }

  Future<bool> _backfillLegacyArtistPreviewFamilies() async {
    final artistChains = await workspaceService.loadArtistChains();
    var changed = false;
    final updated = [
      for (final artistChain in artistChains)
        _classifyLegacyArtistPreviewRefs(
          artistChain,
          onChanged: () => changed = true,
        ),
    ];
    if (changed) {
      await workspaceService.saveArtistChains(updated);
    }
    return changed;
  }

  ArtistChain _classifyLegacyArtistPreviewRefs(
    ArtistChain artistChain, {
    required void Function() onChanged,
  }) {
    if (artistChain.imageRefs.isEmpty) return artistChain;
    final modelPreviewRefs = <String, List<String>>{
      for (final entry in artistChain.modelPreviewRefs.entries)
        entry.key: [...entry.value],
    };
    final v45Refs = modelPreviewRefs.putIfAbsent(
      generationPreviewFamilyV45,
      () => <String>[],
    );
    var chainChanged = false;
    final classified = modelPreviewRefs.values.expand((refs) => refs).toSet();
    for (final ref in artistChain.imageRefs) {
      final trimmed = ref.trim();
      if (trimmed.isEmpty || classified.contains(trimmed)) continue;
      v45Refs.add(trimmed);
      classified.add(trimmed);
      chainChanged = true;
    }
    if (!chainChanged) return artistChain;
    onChanged();
    return artistChain.copyWith(modelPreviewRefs: modelPreviewRefs);
  }

  ArtistChain _withSeedImages(
    ArtistChain artistChain,
    ArtistChain? seed, {
    required void Function() onChanged,
  }) {
    if (seed == null || seed.imageRefs.isEmpty) return artistChain;
    onChanged();
    return artistChain.copyWith(imageRefs: seed.imageRefs);
  }

  Future<void> _migrateCodexOutOfWorkspaceInspirations() async {
    if (await _isCodexMigrationStateCurrent()) {
      return;
    }

    final inspirations = await workspaceService.loadInspirations();
    final retained = <InspirationEntry>[];
    final migrated = <InspirationEntry>[];
    for (final entry in inspirations) {
      if (isStudioCodexSourceType(entry.source.type)) {
        migrated.add(entry);
      } else {
        retained.add(entry);
      }
    }
    if (migrated.isEmpty) {
      await _writeCodexMigrationState();
      return;
    }

    final existingCodex = await workspaceService.loadCodexEntries();
    final mergedCodex = _mergeCodexEntries(existingCodex, migrated);
    await workspaceService.saveCodexEntries(mergedCodex);
    await workspaceService.saveInspirations(retained);
    final root = workspaceService.root;
    if (root != null) {
      await _deleteAssetCatalogCache(root);
    }
    await _writeCodexMigrationState();
  }

  Future<bool> _isCodexMigrationStateCurrent() async {
    final root = workspaceService.root;
    if (root == null) return false;
    final inspirationsFile = _workspaceFile(root, WorkspacePaths.inspirations);
    if (!await inspirationsFile.exists()) return true;

    final stateFile = _workspaceFile(root, _codexMigrationStatePath);
    if (!await stateFile.exists()) return false;

    try {
      final decoded = jsonDecode(await stateFile.readAsString());
      if (decoded is! Map) return false;
      final stat = await inspirationsFile.stat();
      return decoded['schemaVersion'] == _codexMigrationStateSchemaVersion &&
          decoded['inspirationsModifiedMicros'] ==
              stat.modified.microsecondsSinceEpoch;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeCodexMigrationState() async {
    final root = workspaceService.root;
    if (root == null) return;
    final inspirationsFile = _workspaceFile(root, WorkspacePaths.inspirations);
    if (!await inspirationsFile.exists()) return;

    final stat = await inspirationsFile.stat();
    final stateFile = _workspaceFile(root, _codexMigrationStatePath);
    await stateFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await stateFile.writeAsString(
      '${encoder.convert({
            'schemaVersion': _codexMigrationStateSchemaVersion,
            'inspirationsModifiedMicros': stat.modified.microsecondsSinceEpoch,
          })}\n',
    );
  }

  List<InspirationEntry> _mergeCodexEntries(
    List<InspirationEntry> existingEntries,
    List<InspirationEntry> migratedEntries,
  ) {
    final byKey = <String, InspirationEntry>{};
    void addEntry(InspirationEntry entry) {
      byKey.putIfAbsent(_codexEntryKey(entry), () => entry);
    }

    for (final entry in existingEntries) {
      addEntry(entry);
    }
    for (final entry in migratedEntries) {
      addEntry(entry);
    }
    return List.unmodifiable(byKey.values);
  }

  String _codexEntryKey(InspirationEntry entry) {
    final id = entry.id.trim();
    if (id.isNotEmpty) return id;
    return [
      normalizeStudioCodexSourceType(entry.source.type),
      entry.source.id ?? '',
      entry.source.path ?? '',
      entry.name,
      entry.prompt,
    ].join('\n');
  }

  Future<List<InspirationEntry>> loadLegacyCodexSeedEntries() async {
    final seed = await _loadLegacyCodexSeed();
    if (seed == null) return const [];
    return _decodeList<InspirationEntry>(
      seed['inspirations'],
      InspirationEntry.fromJson,
    );
  }

  Future<Map<String, dynamic>?> _loadLegacyCodexSeed() {
    return _loadJsonSeed(
      customLoader: legacyCodexSeedLoader,
      assetPath: 'assets/json/legacy_codex_seed.json',
    );
  }

  Future<Map<String, dynamic>?> _loadJsonSeed({
    required Future<Map<String, dynamic>?> Function()? customLoader,
    required String assetPath,
  }) async {
    if (customLoader != null) {
      return customLoader.call();
    }
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  List<T> _decodeList<T>(
    dynamic value,
    T Function(dynamic json) fromJson,
  ) {
    if (value is! List) return const [];
    return value.map(fromJson).toList(growable: false);
  }
}

class _WorkspaceAssetSignature {
  final bool hasManifest;
  final int characterCount;
  final int outfitCount;
  final int artistChainCount;
  final int characterPreviewRefCount;
  final int outfitPreviewRefCount;
  final int artistPreviewRefCount;
  final int referenceFileCount;
  final int lastDataModifiedMicros;

  const _WorkspaceAssetSignature({
    required this.hasManifest,
    required this.characterCount,
    required this.outfitCount,
    required this.artistChainCount,
    required this.characterPreviewRefCount,
    required this.outfitPreviewRefCount,
    required this.artistPreviewRefCount,
    required this.referenceFileCount,
    required this.lastDataModifiedMicros,
  });

  int get assetCount => characterCount + outfitCount + artistChainCount;

  int get characterAndOutfitPreviewRefCount =>
      characterPreviewRefCount + outfitPreviewRefCount;

  int get previewRefCount =>
      characterPreviewRefCount + outfitPreviewRefCount + artistPreviewRefCount;

  bool get hasAssets => assetCount > 0 || previewRefCount > 0;
}
