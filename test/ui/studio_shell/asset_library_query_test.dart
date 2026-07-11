import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_shell/models/asset_library_query.dart';

void main() {
  group('AssetLibraryQuery', () {
    test('all filter hides codex and batch plan entries', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.all,
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['character', 'artist']);
    });

    test('codex filter only returns legacy codex entries', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.codex,
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['codex']);
    });

    test('query narrows reusable asset results', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.artistChain,
        query: 'rain',
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['artist']);
    });

    test('batch plan filter exposes batch plan entries', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.batchPlan,
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['batch-plan']);
    });

    test('favorite entries are promoted before non favorites', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.all,
        favoriteKeys: {'artist:favorite'},
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['artist', 'character']);
    });

    test('favorite promotion keeps non favorite entries in source order', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.artistChain,
        favoriteKeys: {'artist:favorite-2'},
      ).filterItems([
        _artistItem('first', 'artist:first'),
        _artistItem('second', 'artist:favorite-2'),
        _artistItem('third', 'artist:plain-3'),
      ]);

      expect(result.map((item) => item.value), ['second', 'first', 'third']);
    });
  });
}

List<AssetLibraryQueryItem<String>> _items() {
  return [
    AssetLibraryQueryItem(
      value: 'character',
      kind: AssetLibraryKind.character,
      favoriteKey: 'character:plain',
      matchesQuery: (query) => 'alice silver hair'.contains(query),
    ),
    AssetLibraryQueryItem(
      value: 'artist',
      kind: AssetLibraryKind.artistChain,
      favoriteKey: 'artist:favorite',
      matchesQuery: (query) => 'rain watercolor wash'.contains(query),
    ),
    AssetLibraryQueryItem(
      value: 'codex',
      kind: AssetLibraryKind.inspiration,
      isLegacyCodex: true,
      favoriteKey: 'codex:plain',
      matchesQuery: (query) => true,
    ),
    AssetLibraryQueryItem(
      value: 'batch-plan',
      kind: AssetLibraryKind.batchPlan,
      favoriteKey: 'batch:plain',
      matchesQuery: (query) => true,
    ),
  ];
}

AssetLibraryQueryItem<String> _artistItem(String value, String favoriteKey) {
  return AssetLibraryQueryItem(
    value: value,
    kind: AssetLibraryKind.artistChain,
    favoriteKey: favoriteKey,
    matchesQuery: (_) => true,
  );
}
