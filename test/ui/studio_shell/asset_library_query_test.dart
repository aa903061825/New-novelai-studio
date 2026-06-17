import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_shell/models/asset_library_query.dart';

void main() {
  group('AssetLibraryQuery', () {
    test('all filter hides codex and batch plan entries', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.all,
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['character', 'tag']);
    });

    test('codex filter only returns legacy codex entries', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.codex,
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['codex']);
    });

    test('query block and custom category narrow tag results', () {
      final result = const AssetLibraryQuery(
        filter: AssetLibraryFilter.tag,
        query: 'rain',
        selectedBlock: 'scene',
        selectedCustomCategory: 'weather',
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['tag']);
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
        favoriteKeys: {'tag:favorite'},
      ).filterItems(_items());

      expect(result.map((item) => item.value), ['tag', 'character']);
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
      value: 'tag',
      kind: AssetLibraryKind.tag,
      block: 'scene',
      customCategory: 'weather',
      favoriteKey: 'tag:favorite',
      matchesQuery: (query) => 'rain street'.contains(query),
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
