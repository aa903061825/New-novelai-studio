import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nai_casrand/data/studio/services/studio_cache_import_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:path_provider/path_provider.dart';

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

  Future<void> initializeAt(Directory root) async {
    var manifest = File(
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
      await _removeLegacyCodexFromWorkspaceInspirations();
      return;
    }
    await workspaceService.createWorkspace(root.path);
    await _seedLegacyArtistDataIfEmpty();
    await _backfillLegacyArtistImages();
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

    final artistChains = await workspaceService.loadArtistChains();
    var changed = false;
    final updated = [
      for (final artistChain in artistChains)
        if (artistChain.imageRefs.isNotEmpty)
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

  ArtistChain _withSeedImages(
    ArtistChain artistChain,
    ArtistChain? seed, {
    required void Function() onChanged,
  }) {
    if (seed == null || seed.imageRefs.isEmpty) return artistChain;
    onChanged();
    return ArtistChain(
      id: artistChain.id,
      name: artistChain.name,
      tags: artistChain.tags,
      prompt: artistChain.prompt,
      styleTags: artistChain.styleTags,
      imageRefs: seed.imageRefs,
      translations: artistChain.translations,
      source: artistChain.source,
      note: artistChain.note,
    );
  }

  Future<void> _removeLegacyCodexFromWorkspaceInspirations() async {
    final inspirations = await workspaceService.loadInspirations();
    final retained = inspirations
        .where((entry) => entry.source.type != 'legacy_codex')
        .toList(growable: false);
    if (retained.length == inspirations.length) return;
    await workspaceService.saveInspirations(retained);
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
