enum AssetLibraryFilter {
  all,
  character,
  outfit,
  artistChain,
  recipe,
  tag,
  codex,
  inspiration,
  lora,
  workflow,
  batchPlan,
  assemblyPreset,
}

enum AssetLibraryKind {
  character,
  outfit,
  artistChain,
  recipe,
  tag,
  inspiration,
  lora,
  workflow,
  batchPlan,
  assemblyPreset,
}

class AssetLibraryQuery {
  final String query;
  final AssetLibraryFilter filter;
  final Set<String> favoriteKeys;

  const AssetLibraryQuery({
    this.query = '',
    this.filter = AssetLibraryFilter.all,
    this.favoriteKeys = const {},
  });

  List<AssetLibraryQueryItem<T>> filterItems<T>(
    Iterable<AssetLibraryQueryItem<T>> items,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = items.where((item) {
      final typeMatches = switch (filter) {
        AssetLibraryFilter.all =>
          !item.isLegacyCodex && item.kind != AssetLibraryKind.batchPlan,
        AssetLibraryFilter.codex => item.isLegacyCodex,
        AssetLibraryFilter.inspiration =>
          item.kind == AssetLibraryKind.inspiration && !item.isLegacyCodex,
        _ => _filterForKind(item.kind) == filter && !item.isLegacyCodex,
      };
      final queryMatches =
          normalizedQuery.isEmpty || item.matchesQuery(normalizedQuery);
      return typeMatches && queryMatches;
    }).toList(growable: false);
    final indexed = filtered.indexed.toList(growable: false)
      ..sort((a, b) {
        final aFavorite = favoriteKeys.contains(a.$2.favoriteKey);
        final bFavorite = favoriteKeys.contains(b.$2.favoriteKey);
        if (aFavorite != bFavorite) return aFavorite ? -1 : 1;
        return a.$1.compareTo(b.$1);
      });
    return [
      for (final entry in indexed) entry.$2,
    ];
  }
}

class AssetLibraryQueryItem<T> {
  final T value;
  final AssetLibraryKind kind;
  final bool isLegacyCodex;
  final String favoriteKey;
  final bool Function(String normalizedQuery) matchesQuery;

  const AssetLibraryQueryItem({
    required this.value,
    required this.kind,
    this.isLegacyCodex = false,
    required this.favoriteKey,
    required this.matchesQuery,
  });
}

AssetLibraryFilter _filterForKind(AssetLibraryKind kind) {
  return switch (kind) {
    AssetLibraryKind.character => AssetLibraryFilter.character,
    AssetLibraryKind.outfit => AssetLibraryFilter.outfit,
    AssetLibraryKind.artistChain => AssetLibraryFilter.artistChain,
    AssetLibraryKind.recipe => AssetLibraryFilter.recipe,
    AssetLibraryKind.tag => AssetLibraryFilter.tag,
    AssetLibraryKind.inspiration => AssetLibraryFilter.inspiration,
    AssetLibraryKind.lora => AssetLibraryFilter.lora,
    AssetLibraryKind.workflow => AssetLibraryFilter.workflow,
    AssetLibraryKind.batchPlan => AssetLibraryFilter.batchPlan,
    AssetLibraryKind.assemblyPreset => AssetLibraryFilter.assemblyPreset,
  };
}
