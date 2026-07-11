import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

void main() {
  test('codex index returns UI-compatible grouped slices', () async {
    final sourceCategoryKey =
        StudioLegacyCodexCategories.sourceCategoryKeyForPath(
      ['基础涩涩', '各种体位', '正身位'],
    )!;
    final index = StudioCodexIndex(
      workspaceService: WorkspaceService(),
      legacyCodexLoader: () async => const [
        InspirationEntry(
          id: 'regular-parent',
          name: 'Regular Parent',
          prompt: 'artist:wlop, fantasy armor',
          source: SourceRef(type: 'legacy_codex'),
        ),
        InspirationEntry(
          id: 'adult-parent',
          name: 'Adult Parent',
          prompt: 'pov, close-up, smile',
          sourceCategoryPath: ['基础涩涩', '各种体位', '正身位'],
          source: SourceRef(type: 'novalai_codex_adult_docx'),
        ),
        InspirationEntry(
          id: 'adult-variant',
          name: 'Adult Variant',
          prompt: 'alternate angle',
          sourceCategoryPath: ['基础涩涩', '各种体位', '正身位'],
          sourceParentId: 'adult-parent',
          sourceVariantLabel: '差分',
          source: SourceRef(type: 'novalai_codex_adult_docx'),
        ),
      ],
    );

    final slice = await index.loadSlice(
      workspaceCodexEntries: const [],
      limit: 10,
      query: 'alternate',
      categoryKey: StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceAdultKey,
        categoryKey: StudioLegacyCodexCategories.allKey,
      ),
    );

    expect(slice.entries, hasLength(1));
    expect(slice.entries.single.id, 'adult-parent');
    expect(slice.entries.single.variants.map((entry) => entry.id), [
      'adult-variant',
    ]);
    expect(slice.totalCount, 1);
    expect(slice.loadedCount, 1);
    expect(slice.categoryCounts[sourceCategoryKey], 1);
  });

  test('codex index reuses bundled codex entries across pages', () async {
    var loadCount = 0;
    final index = StudioCodexIndex(
      workspaceService: WorkspaceService(),
      legacyCodexLoader: () async {
        loadCount += 1;
        return [
          for (var index = 1; index <= 3; index++)
            InspirationEntry(
              id: 'regular-$index',
              name: 'Regular $index',
              prompt: 'artist:wlop, fantasy $index',
              source: const SourceRef(type: 'legacy_codex'),
            ),
        ];
      },
    );

    final first = await index.loadSlice(
      workspaceCodexEntries: const [],
      limit: 1,
      query: '',
      categoryKey: StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceRegularKey,
        categoryKey: StudioLegacyCodexCategories.allKey,
      ),
    );
    final second = await index.loadSlice(
      workspaceCodexEntries: const [],
      limit: 3,
      query: '',
      categoryKey: StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceRegularKey,
        categoryKey: StudioLegacyCodexCategories.allKey,
      ),
    );

    expect(loadCount, 1);
    expect(first.entries.map((entry) => entry.id), ['regular-1']);
    expect(second.entries.map((entry) => entry.id), [
      'regular-1',
      'regular-2',
      'regular-3',
    ]);
    expect(second.totalCount, 3);
  });
}
