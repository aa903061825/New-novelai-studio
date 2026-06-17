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
  final String? selectedBlock;
  final String? selectedCustomCategory;
  final Set<String> favoriteKeys;

  const AssetLibraryQuery({
    this.query = '',
    this.filter = AssetLibraryFilter.all,
    this.selectedBlock,
    this.selectedCustomCategory,
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
      final blockMatches = selectedBlock == null || item.block == selectedBlock;
      final customCategoryMatches = selectedCustomCategory == null ||
          item.customCategory == selectedCustomCategory;
      final queryMatches =
          normalizedQuery.isEmpty || item.matchesQuery(normalizedQuery);
      return typeMatches &&
          blockMatches &&
          customCategoryMatches &&
          queryMatches;
    }).toList(growable: false);
    return filtered
      ..sort((a, b) {
        final aFavorite = favoriteKeys.contains(a.favoriteKey);
        final bFavorite = favoriteKeys.contains(b.favoriteKey);
        if (aFavorite == bFavorite) return 0;
        return aFavorite ? -1 : 1;
      });
  }
}

class AssetLibraryQueryItem<T> {
  final T value;
  final AssetLibraryKind kind;
  final bool isLegacyCodex;
  final String? block;
  final String? customCategory;
  final String favoriteKey;
  final bool Function(String normalizedQuery) matchesQuery;

  const AssetLibraryQueryItem({
    required this.value,
    required this.kind,
    this.isLegacyCodex = false,
    this.block,
    this.customCategory,
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
