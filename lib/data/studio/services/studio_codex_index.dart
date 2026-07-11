part of 'studio_asset_catalog_service.dart';

class StudioCodexSlice {
  final List<InspirationEntry> entries;
  final int totalCount;
  final Map<String, int> categoryCounts;

  const StudioCodexSlice({
    required this.entries,
    required this.totalCount,
    required this.categoryCounts,
  });

  const StudioCodexSlice.empty()
      : entries = const [],
        totalCount = 0,
        categoryCounts = const {};

  int get loadedCount => entries.length;
}

class StudioCodexIndex {
  final WorkspaceService workspaceService;
  final Future<List<InspirationEntry>> Function()? legacyCodexLoader;

  List<InspirationEntry>? _bundledCodexCache;
  bool? _bundledCodexAvailabilityCache;
  _CodexIndexCache? _indexCache;
  final Map<String, List<String>> _categoryKeyCache = {};

  StudioCodexIndex({
    required this.workspaceService,
    this.legacyCodexLoader,
  });

  Future<StudioCodexSlice> loadSlice({
    required List<InspirationEntry> workspaceCodexEntries,
    required int limit,
    required String query,
    required String categoryKey,
  }) async {
    final allEntries = _mergedCodexEntries(
      workspaceCodexEntries,
      await _loadBundledCodexEntries(),
    );
    final requestFilter =
        StudioLegacyCodexCategories.requestFilterFor(categoryKey);
    final index = _indexFor(allEntries);
    final sourceGroups = index.groupsForSource(requestFilter.sourceScopeKey);
    final normalizedQuery = query.trim().toLowerCase();
    final queryFiltered = normalizedQuery.isEmpty
        ? sourceGroups
        : sourceGroups
            .where((group) => group.matchesQuery(normalizedQuery))
            .toList(growable: false);
    final categoryCounts = _categoryCountsForGroups(
      queryFiltered,
      sourceScopeKey: requestFilter.sourceScopeKey,
    );
    final filtered = _filterGroupsByCategory(
      queryFiltered,
      requestFilter.categoryKey,
      requestFilter.sourceScopeKey,
    );
    final safeLimit = limit < 1 ? 1 : limit;
    return StudioCodexSlice(
      entries: filtered
          .take(safeLimit)
          .map((group) => group.entry)
          .toList(growable: false),
      totalCount: filtered.length,
      categoryCounts: Map.unmodifiable(categoryCounts),
    );
  }

  Future<bool> hasBundledCodexSource() async {
    if (legacyCodexLoader != null) return true;
    final cached = _bundledCodexCache;
    if (cached != null) return cached.isNotEmpty;
    final cachedAvailability = _bundledCodexAvailabilityCache;
    if (cachedAvailability != null) return cachedAvailability;
    try {
      final raw = await rootBundle.loadString(
        'assets/json/legacy_codex_seed.json',
      );
      final available = raw.trim().isNotEmpty;
      _bundledCodexAvailabilityCache = available;
      return available;
    } catch (_) {
      _bundledCodexAvailabilityCache = false;
      return false;
    }
  }

  Future<List<InspirationEntry>> _loadBundledCodexEntries() async {
    final cached = _bundledCodexCache;
    if (cached != null) return cached;
    if (legacyCodexLoader != null) {
      final entries = await legacyCodexLoader!.call();
      _bundledCodexCache = entries;
      return entries;
    }
    try {
      final raw = await rootBundle.loadString(
        'assets/json/legacy_codex_seed.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final entries = await StudioDataService(
        workspaceService: workspaceService,
        legacyCodexSeedLoader: () async => decoded,
      ).loadLegacyCodexSeedEntries();
      _bundledCodexCache = entries;
      return entries;
    } catch (_) {
      return const [];
    }
  }

  _CodexIndex _indexFor(List<InspirationEntry> entries) {
    final signature = _entriesSignature(entries);
    final cached = _indexCache;
    if (cached != null && cached.signature == signature) {
      return cached.index;
    }
    final index = _CodexIndex(entries);
    _indexCache = _CodexIndexCache(signature: signature, index: index);
    return index;
  }

  List<_IndexedCodexGroup> _filterGroupsByCategory(
    List<_IndexedCodexGroup> groups,
    String categoryKey,
    String sourceScopeKey,
  ) {
    if (categoryKey == StudioLegacyCodexCategories.allKey) return groups;
    return [
      for (final group in groups)
        if (_categoryKeysForGroup(group, sourceScopeKey).contains(categoryKey))
          group,
    ];
  }

  Map<String, int> _categoryCountsForGroups(
    List<_IndexedCodexGroup> groups, {
    required String sourceScopeKey,
  }) {
    final counts = <String, int>{
      StudioLegacyCodexCategories.allKey: groups.length,
    };
    final sawSourceCategories = groups.any(
      (group) => _categoryKeysForGroup(group, sourceScopeKey).any(
        StudioLegacyCodexCategories.isSourceCategoryKey,
      ),
    );
    if (!sawSourceCategories) {
      for (final category
          in StudioLegacyCodexCategories.filtersForSource(sourceScopeKey)
              .skip(1)) {
        counts[category.key] = 0;
      }
    }
    for (final group in groups) {
      for (final key in _categoryKeysForGroup(group, sourceScopeKey)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<String> _categoryKeysForGroup(
    _IndexedCodexGroup group,
    String sourceScopeKey,
  ) {
    final keys = <String>{};
    for (final entry in group.entries) {
      keys.addAll(_categoryKeysFor(entry, sourceScopeKey));
    }
    return List.unmodifiable(keys);
  }

  List<String> _categoryKeysFor(
    InspirationEntry entry,
    String sourceScopeKey,
  ) {
    final normalizedSourceScopeKey =
        StudioLegacyCodexCategories.normalizedSourceScopeKey(sourceScopeKey);
    final cacheKey = _categoryCacheKey(entry, normalizedSourceScopeKey);
    return _categoryKeyCache.putIfAbsent(
      cacheKey,
      () => StudioLegacyCodexCategories.keysForSource(
        entry,
        normalizedSourceScopeKey,
      ),
    );
  }

  String _categoryCacheKey(InspirationEntry entry, String sourceScopeKey) {
    return [
      sourceScopeKey,
      entry.id,
      entry.name,
      entry.prompt,
      entry.negativePrompt,
      entry.tags.join('\u0001'),
      entry.note,
      entry.sourceCategoryPath.join('\u0001'),
      entry.sourceParentId ?? '',
      entry.sourceParentName ?? '',
      entry.sourceVariantLabel ?? '',
      entry.source.type,
      entry.source.id ?? '',
      entry.source.path ?? '',
    ].join('\u0002');
  }

  List<InspirationEntry> _mergedCodexEntries(
    List<InspirationEntry> workspaceEntries,
    List<InspirationEntry> bundledEntries,
  ) {
    if (workspaceEntries.isEmpty) return bundledEntries;
    if (bundledEntries.isEmpty) return workspaceEntries;

    final byKey = <String, InspirationEntry>{};
    void addEntry(InspirationEntry entry) {
      final id = entry.id.trim();
      final key = id.isNotEmpty
          ? id
          : [
              entry.source.type,
              entry.source.id ?? '',
              entry.name,
              entry.prompt,
            ].join('\n');
      byKey.putIfAbsent(key, () => entry);
    }

    for (final entry in workspaceEntries) {
      addEntry(entry);
    }
    for (final entry in bundledEntries) {
      addEntry(entry);
    }
    return List.unmodifiable(byKey.values);
  }

  String _entriesSignature(List<InspirationEntry> entries) {
    if (entries.isEmpty) return 'empty';
    return [
      entries.length,
      for (final entry in entries)
        [
          entry.id,
          entry.source.type,
          entry.source.id ?? '',
          entry.source.path ?? '',
          entry.sourceParentId ?? '',
          entry.sourceVariantLabel ?? '',
        ].join('\u0003'),
    ].join('\u0004');
  }
}

class _CodexIndex {
  final List<InspirationEntry> entries;
  final Map<String, List<_IndexedCodexGroup>> _groupsBySourceScope = {};

  _CodexIndex(this.entries);

  List<_IndexedCodexGroup> groupsForSource(String sourceScopeKey) {
    final normalizedScope =
        StudioLegacyCodexCategories.normalizedSourceScopeKey(sourceScopeKey);
    return _groupsBySourceScope.putIfAbsent(
      normalizedScope,
      () => _groupEntriesForSource(normalizedScope),
    );
  }

  List<_IndexedCodexGroup> _groupEntriesForSource(String sourceScopeKey) {
    final filtered = entries
        .where((entry) => _matchesSourceScope(entry, sourceScopeKey))
        .toList(growable: false);
    final groups = <_MutableIndexedCodexGroup>[];
    final groupsByParentId = <String, _MutableIndexedCodexGroup>{};
    final pendingByParentId = <String, List<InspirationEntry>>{};

    void addParent(InspirationEntry entry) {
      final group = _MutableIndexedCodexGroup(entry);
      final pending = pendingByParentId.remove(entry.id);
      if (pending != null) {
        group.variants.addAll(pending);
      }
      groups.add(group);
      groupsByParentId[entry.id] = group;
    }

    for (final entry in filtered) {
      final parentId = entry.sourceParentId?.trim();
      if (parentId == null || parentId.isEmpty) {
        addParent(entry);
        continue;
      }
      final group = groupsByParentId[parentId];
      if (group != null) {
        group.variants.add(entry);
      } else {
        pendingByParentId.putIfAbsent(parentId, () => []).add(entry);
      }
    }
    for (final pending in pendingByParentId.values) {
      for (final entry in pending) {
        addParent(entry);
      }
    }
    return List.unmodifiable([
      for (final group in groups)
        _IndexedCodexGroup(
          parent: group.parent,
          variants: List.unmodifiable(group.variants),
        ),
    ]);
  }

  bool _matchesSourceScope(InspirationEntry entry, String sourceScopeKey) {
    if (sourceScopeKey == StudioLegacyCodexCategories.sourceAllKey) {
      return true;
    }
    final isAdult =
        StudioAssetCatalogService.isAdultCodexSourceType(entry.source.type);
    return sourceScopeKey == StudioLegacyCodexCategories.sourceAdultKey
        ? isAdult
        : !isAdult;
  }
}

class _CodexIndexCache {
  final String signature;
  final _CodexIndex index;

  const _CodexIndexCache({
    required this.signature,
    required this.index,
  });
}

class _MutableIndexedCodexGroup {
  final InspirationEntry parent;
  final List<InspirationEntry> variants = [];

  _MutableIndexedCodexGroup(this.parent);
}

class _IndexedCodexGroup {
  final InspirationEntry parent;
  final List<InspirationEntry> variants;
  late final String _searchText = _buildSearchText(entries);

  _IndexedCodexGroup({
    required this.parent,
    required this.variants,
  });

  List<InspirationEntry> get entries => [parent, ...variants];

  InspirationEntry get entry {
    if (variants.isEmpty && parent.variants.isEmpty) return parent;
    return InspirationEntry(
      id: parent.id,
      name: parent.name,
      prompt: parent.prompt,
      negativePrompt: parent.negativePrompt,
      tags: parent.tags,
      imageRefs: parent.imageRefs,
      source: parent.source,
      note: parent.note,
      sourceCategoryPath: parent.sourceCategoryPath,
      sourceParentId: parent.sourceParentId,
      sourceParentName: parent.sourceParentName,
      sourceVariantLabel: parent.sourceVariantLabel,
      variants: [
        ...parent.variants,
        ...variants,
      ],
    );
  }

  bool matchesQuery(String normalizedQuery) {
    return _searchText.contains(normalizedQuery);
  }

  String _buildSearchText(List<InspirationEntry> entries) {
    return [
      for (final entry in entries) ...[
        entry.name,
        entry.prompt,
        entry.negativePrompt,
        entry.tags.join(' '),
        entry.sourceCategoryPath.join(' '),
        entry.sourceParentName ?? '',
        entry.sourceVariantLabel ?? '',
        entry.note,
      ],
    ].join('\n').toLowerCase();
  }
}
