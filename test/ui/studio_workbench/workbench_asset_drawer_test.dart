import 'dart:io';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_drawer_motion.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_drawer_shell.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_hover_preview_thumbnail.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/prompt_composer_panel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_asset_drawer.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_single_image_console.dart';

const _sharedPreferencesChannel =
    MethodChannel('plugins.flutter.io/shared_preferences');

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService(
    this.snapshot, {
    this.previewPath,
    this.previewPathsByRef = const {},
    Set<String> favoriteKeys = const {},
    WorkspaceService? workspaceService,
  })  : favoriteKeys = {...favoriteKeys},
        super(workspaceService: workspaceService ?? WorkspaceService());

  StudioAssetCatalogSnapshot snapshot;
  final String? previewPath;
  final Map<String, String> previewPathsByRef;
  final Set<String> favoriteKeys;
  var snapshotLoadCount = 0;
  var summaryLoadCount = 0;
  var tagLoadCount = 0;

  @override
  Future<StudioAssetCatalogSummary> loadSummary() async {
    summaryLoadCount++;
    return snapshot.summary;
  }

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    snapshotLoadCount++;
    return snapshot;
  }

  @override
  Future<List<CharacterEntry>> loadWorkbenchCharacters() async {
    return snapshot.characters;
  }

  @override
  Future<List<StudioOutfitAsset>> loadWorkbenchOutfits() async {
    return snapshot.outfits;
  }

  @override
  Future<List<ArtistChain>> loadWorkbenchArtistChains() async {
    return snapshot.artistChains;
  }

  @override
  Future<List<Recipe>> loadWorkbenchRecipes() async {
    return snapshot.recipes;
  }

  @override
  Future<List<TagEntry>> loadWorkbenchTags() async {
    tagLoadCount++;
    return snapshot.tags;
  }

  @override
  String? resolveImagePath(List<String> refs) {
    for (final ref in refs) {
      final mappedPath = previewPathsByRef[ref.trim()];
      if (mappedPath != null) return mappedPath;
    }
    return refs.isEmpty ? null : previewPath;
  }

  @override
  Future<Set<String>> loadAssetFavoriteKeys() async {
    return {...favoriteKeys};
  }

  @override
  Future<void> setAssetFavorite(String key, bool isFavorite) async {
    if (isFavorite) {
      favoriteKeys.add(key);
    } else {
      favoriteKeys.remove(key);
    }
  }
}

class _WorkbenchAssetLoader extends AssetLoader {
  const _WorkbenchAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return const {};
  }
}

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

Widget _studioApp(Widget child) {
  return MaterialApp(
    theme: StudioTheme.build(),
    home: Scaffold(body: child),
  );
}

Widget _workbenchApp({
  required StudioAssetCatalogService catalogService,
  required StudioWorkbenchAssetService workbench,
}) {
  return MaterialApp(
    theme: StudioTheme.build(),
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 620,
        child: Row(
          children: [
            SizedBox(
              width: 320,
              child: WorkbenchAssetDrawer(
                catalogService: catalogService,
                workbenchAssetService: workbench,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: PromptComposerPanel(service: workbench)),
          ],
        ),
      ),
    ),
  );
}

Widget _characterDropWorkbenchApp({
  required StudioAssetCatalogService catalogService,
  required StudioWorkbenchAssetService workbench,
  required WorkbenchSingleImageParametersViewmodel parameters,
}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/l10n',
    assetLoader: const _WorkbenchAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    saveLocale: false,
    child: Builder(
      builder: (context) {
        return MaterialApp(
          theme: StudioTheme.build(),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 620,
              child: Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: WorkbenchAssetDrawer(
                      catalogService: catalogService,
                      workbenchAssetService: workbench,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: WorkbenchCreativeInputsPanel(
                      parametersViewmodel: parameters,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, (call) async {
      if (call.method == 'getAll') {
        return <String, Object>{};
      }
      return true;
    });
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('drawer sends catalog assets into the workbench service',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-1')));
    await tester.pump();

    expect(workbench.fragments.single.positiveText, 'cinematic lighting');
    expect(workbench.payloadConfig.overridePrompt, 'cinematic lighting');
  });

  testWidgets('open artist category refreshes after artist chain save',
      (tester) async {
    final workspace = WorkspaceService();

    const initialSnapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter',
          prompt: 'old artist prompt',
        ),
      ],
      recipes: [],
      tags: [],
    );
    final catalog = _FakeCatalogService(
      initialSnapshot,
      workspaceService: workspace,
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: catalog,
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('workbench-drawer-category-artist')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('old artist prompt'), findsOneWidget);

    const updatedSnapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter',
          prompt: 'latest artist prompt',
        ),
      ],
      recipes: [],
      tags: [],
    );
    catalog.snapshot = updatedSnapshot;
    workspace.notifyArtistChainsChanged();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('latest artist prompt'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('workbench-drawer-add-artist-artist-1')),
    );
    await tester.pump();

    expect(workbench.fragments.single.positiveText, 'latest artist prompt');
  });

  testWidgets('drawer expands sectioned tag assets into prompt parts',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(
          id: 'tag-1',
          tag: 'cinematic lighting',
          block: 'camera',
          sections: {'armor': 'armored plates, pauldrons'},
        ),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('workbench-drawer-add-part-tag-tag-1-armor')),
    );
    await tester.pump();

    expect(workbench.fragments, hasLength(1));
    expect(
        workbench.fragments.single.kind, StudioWorkbenchAssetKind.assetSection);
    expect(workbench.fragments.single.typeLabel, 'armor');
    expect(
        workbench.fragments.single.positiveText, 'armored plates, pauldrons');
    expect(workbench.payloadConfig.overridePrompt, 'armored plates, pauldrons');
  });

  testWidgets('drawer shows category cards before loading category details',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 2,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 2},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
        TagEntry(id: 'tag-2', tag: 'low angle', block: 'camera'),
      ],
    );
    final catalog = _FakeCatalogService(snapshot);
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: catalog,
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('workbench-drawer-category-tag')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-1')),
        findsNothing);
    expect(catalog.summaryLoadCount, 1);
    expect(catalog.snapshotLoadCount, 0);
    expect(catalog.tagLoadCount, 0);

    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-2')),
        findsOneWidget);
    expect(catalog.tagLoadCount, 1);
  });

  testWidgets('drawer cards use event-triggered motion surfaces',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();

    final categoryCard =
        find.byKey(const ValueKey('workbench-drawer-category-tag'));
    expect(
      find.ancestor(
        of: categoryCard,
        matching: find.byType(StudioInteractiveSurface),
      ),
      findsOneWidget,
    );

    final categoryScale = find.ancestor(
      of: categoryCard,
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(categoryScale).scale, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(categoryCard));
    await tester.pump(StudioMotionTokens.fast);

    expect(tester.widget<AnimatedScale>(categoryScale).scale, greaterThan(1));

    await mouse.moveTo(Offset.zero);
    await tester.pump(StudioMotionTokens.fast);
    await tester.tap(categoryCard);
    await tester.pump();
    await tester.pump();

    final assetCard =
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1'));
    expect(
      find.ancestor(
        of: assetCard,
        matching: find.byType(StudioInteractiveSurface),
      ),
      findsOneWidget,
    );
  });

  testWidgets('drawer category hover reserves horizontal drawer space',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: '角色',
          traits: ViewVariantTexts(frontFull: 'girl'),
        ),
      ],
      artistChains: [
        ArtistChain(id: 'artist-1', name: '画师串', prompt: 'artist'),
      ],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        SizedBox(
          key: const ValueKey('narrow-drawer-frame'),
          width: 280,
          height: 360,
          child: WorkbenchAssetDrawer(
            catalogService: _FakeCatalogService(snapshot),
            workbenchAssetService: workbench,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final categoryCard =
        find.byKey(const ValueKey('workbench-drawer-category-artist'));
    expect(categoryCard, findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(categoryCard));
    await tester.pump(StudioMotionTokens.fast);

    final categoryList = find.ancestor(
      of: categoryCard,
      matching: find.byType(ListView),
    );
    expect(categoryList, findsOneWidget);

    final viewportRect = tester.getRect(categoryList);
    final cardRect = tester.getRect(categoryCard);

    expect(cardRect.left, greaterThanOrEqualTo(viewportRect.left + 2));
    expect(cardRect.right, lessThanOrEqualTo(viewportRect.right - 2));
  });

  testWidgets('drawer detail list reserves top hover outline space',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        SizedBox(
          width: 320,
          height: 360,
          child: WorkbenchAssetDrawer(
            catalogService: _FakeCatalogService(snapshot),
            workbenchAssetService: workbench,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pumpAndSettle();

    final assetCard =
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1'));
    expect(assetCard, findsOneWidget);
    expect(find.byType(StudioAssetDrawerShell), findsOneWidget);

    final detailList = find.ancestor(
      of: assetCard,
      matching: find.byType(ListView),
    );
    expect(detailList, findsOneWidget);

    final viewportRect = tester.getRect(detailList);
    final cardRect = tester.getRect(assetCard);

    expect(
      cardRect.top,
      greaterThanOrEqualTo(viewportRect.top + studioAssetDrawerHoverInset),
    );
  });

  testWidgets('drawer detail rows use visible shared hover feedback',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'library character',
          traits: ViewVariantTexts(frontFull: 'green eyes'),
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        SizedBox(
          width: 320,
          height: 360,
          child: WorkbenchAssetDrawer(
            catalogService: _FakeCatalogService(snapshot),
            workbenchAssetService: workbench,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('workbench-drawer-category-character')),
    );
    await tester.pumpAndSettle();

    final characterCard = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1'),
    );
    expect(characterCard, findsOneWidget);

    final surfaceFinder = find
        .ancestor(
          of: characterCard,
          matching: find.byType(StudioInteractiveSurface),
        )
        .first;
    final surface = tester.widget<StudioInteractiveSurface>(surfaceFinder);
    expect(surface.hoverOverlayColor, isNotNull);
    expect(surface.hoverBorderColor, isNotNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(characterCard));
    await tester.pump(StudioMotionTokens.fast);

    final hoverChrome = tester.widget<AnimatedContainer>(
      find.descendant(
        of: surfaceFinder,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = hoverChrome.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.top.color, surface.hoverBorderColor);
  });

  testWidgets('drawer back navigation restores category cards without flash',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();

    final categoryCard =
        find.byKey(const ValueKey('workbench-drawer-category-tag'));
    await tester.tap(categoryCard);
    await tester.pump();
    await tester.pumpAndSettle();

    final assetCard =
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1'));
    expect(assetCard, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workbench-drawer-back')));
    await tester.pump();

    expect(categoryCard, findsOneWidget);
    expect(assetCard, findsNothing);

    final categoryFades = tester
        .widgetList<FadeTransition>(
          find.ancestor(
            of: categoryCard,
            matching: find.byType(FadeTransition),
          ),
        )
        .map((transition) => transition.opacity.value)
        .toList(growable: false);
    expect(categoryFades, isNotEmpty);
    expect(categoryFades, everyElement(moreOrLessEquals(1)));
  });

  testWidgets('drawer category and detail content avoid stacked push motion',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 2,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 2},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
        TagEntry(id: 'tag-2', tag: 'low angle', block: 'camera'),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();

    final categoryCard =
        find.byKey(const ValueKey('workbench-drawer-category-tag'));
    expect(
      find.ancestor(
        of: categoryCard,
        matching: find.byType(StudioDrawerPushTransition),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: categoryCard,
        matching: find.byType(StudioMotionSequenceRegion),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: categoryCard,
        matching: find.byType(StudioStaggeredReveal),
      ),
      findsOneWidget,
    );

    await tester.tap(categoryCard);
    await tester.pump();
    await tester.pump();

    final detailRow =
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1'));
    expect(
      find.ancestor(
        of: detailRow,
        matching: find.byType(StudioDrawerPushTransition),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: detailRow,
        matching: find.byType(StudioStaggeredReveal),
      ),
      findsOneWidget,
    );
  });

  testWidgets('drawer filters the selected category details by search text',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 2,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 2},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
        TagEntry(id: 'tag-2', tag: 'low angle', block: 'camera'),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workbench-drawer-category-search')),
      'low',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-1')),
        findsNothing);
    expect(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-2')),
        findsOneWidget);
  });

  testWidgets('drawer favorites pin assets in the selected category',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 2,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 2},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
        TagEntry(id: 'tag-2', tag: 'low angle', block: 'camera'),
      ],
    );
    final catalog = _FakeCatalogService(snapshot);
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: catalog,
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pumpAndSettle();

    final firstCard =
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1'));
    final secondCard =
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-2'));
    expect(
      tester.getTopLeft(firstCard).dy,
      lessThan(tester.getTopLeft(secondCard).dy),
    );

    await tester.tap(
      find.byKey(const ValueKey('workbench-drawer-favorite-tag-tag-2')),
    );
    await tester.pumpAndSettle();

    expect(catalog.favoriteKeys, contains('tag:camera/tag-2'));
    expect(
      tester.getTopLeft(secondCard).dy,
      lessThan(tester.getTopLeft(firstCard).dy),
    );
  });

  testWidgets('drawer expands character rows into outfit cards with split tags',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: '璃夏',
          traits: ViewVariantTexts(
            frontFull: 'silver hair, blue eyes',
            frontUpper: 'blue eyes',
            frontLower: 'fox tail',
          ),
          outfits: [
            WorkspaceOutfit(
              id: 'outfit-1',
              name: '雨披',
              tags: ViewVariantTexts(
                frontFull: 'yellow rain coat',
                frontUpper: 'yellow jacket',
                frontLower: 'rain skirt',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperClothingTags: ['yellow jacket'],
                lowerClothingTags: ['rain skirt'],
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-character')));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workbench-drawer-card-character-char-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
            'workbench-drawer-card-character-char-1-outfit-outfit-1'),
      ),
      findsNothing,
    );

    await tester.tap(
        find.byKey(const ValueKey('workbench-drawer-card-character-char-1')));
    await tester.pumpAndSettle();

    final outfitCard = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-outfit-1'),
    );
    expect(outfitCard, findsOneWidget);
    expect(
      find.ancestor(
        of: outfitCard,
        matching: find.byType(StudioDrawerShelf),
      ),
      findsOneWidget,
    );
    expect(find.text('雨披'), findsOneWidget);
    expect(find.text('上装'), findsNothing);
    expect(find.text('上身'), findsNothing);

    await tester.ensureVisible(outfitCard);
    await tester.pumpAndSettle();
    await tester.tap(outfitCard);
    await tester.pumpAndSettle();

    expect(find.text('上身'), findsWidgets);
    final upperClothingPart = find.byKey(
      const ValueKey(
        'workbench-drawer-part-character-char-1-outfit-outfit-1-upper-clothing',
      ),
    );
    expect(
      find.ancestor(
        of: upperClothingPart,
        matching: find.byType(StudioDrawerShelf),
      ),
      findsWidgets,
    );
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('上装'), findsWidgets);
    expect(find.text('yellow jacket'), findsWidgets);
    expect(find.text('下身'), findsWidgets);
    expect(find.text('fox tail'), findsNothing);
    expect(find.text('下装'), findsWidgets);
    expect(find.text('rain skirt'), findsWidgets);

    await tester.tap(
      find.byKey(
        const ValueKey('workbench-drawer-add-character-char-1-outfit-outfit-1'),
      ),
    );
    await tester.pump();

    expect(workbench.fragments.single.positiveText, 'yellow rain coat');
  });

  testWidgets(
      'drawer outfit interaction bounds stay on the header when motion is disabled',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
          outfits: [
            WorkspaceOutfit(
              id: 'outfit-1',
              name: 'Default Outfit',
              tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
              partTags: WorkspaceOutfitPartTags(
                upperClothingTags: ['yellow jacket'],
                lowerClothingTags: ['rain skirt'],
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        StudioMotionScope(
          disableAnimations: true,
          child: WorkbenchAssetDrawer(
            catalogService: _FakeCatalogService(snapshot),
            workbenchAssetService: workbench,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-character')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('workbench-drawer-card-character-char-1')));
    await tester.pumpAndSettle();

    final outfitCard = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-outfit-1'),
    );
    expect(outfitCard, findsOneWidget);
    await tester.tap(outfitCard);
    await tester.pumpAndSettle();

    final outfitSurface = find.ancestor(
      of: outfitCard,
      matching: find.byType(StudioInteractiveSurface),
    );
    expect(outfitSurface, findsOneWidget);
    expect(tester.getSize(outfitSurface).height, lessThan(132));

    final upperClothingPart = find.byKey(
      const ValueKey(
        'workbench-drawer-part-character-char-1-outfit-outfit-1-upper-clothing',
      ),
    );
    expect(upperClothingPart, findsOneWidget);
    expect(
      tester
          .widgetList<StudioDrawerShelf>(
            find.ancestor(
              of: upperClothingPart,
              matching: find.byType(StudioDrawerShelf),
            ),
          )
          .map((shelf) => shelf.railOpacity),
      everyElement(0),
    );
  });

  testWidgets(
      'outfit part rows without partTags do not use frontUpper fallback',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
          outfits: [
            WorkspaceOutfit(
              id: 'outfit-1',
              name: 'Front Fields Only',
              tags: ViewVariantTexts(
                frontFull: 'skin identity, white dress, purple skirt',
                frontUpper: 'white dress',
                frontLower: 'purple skirt',
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-character')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('workbench-drawer-card-character-char-1')));
    await tester.pumpAndSettle();

    final outfitCard = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-outfit-1'),
    );
    await tester.ensureVisible(outfitCard);
    await tester.pumpAndSettle();
    await tester.tap(outfitCard);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'workbench-drawer-add-part-character-char-1-outfit-outfit-1-upper-clothing',
        ),
      ),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(workbench.fragments, isEmpty);
  });

  testWidgets(
      'expanded character rows list explicit outfits without synthetic defaults',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(
            frontFull: 'silver hair, blue eyes',
            frontUpper: 'silver hair, blue eyes',
            frontLower: 'fox tail',
          ),
          imageRefs: ['heroine.png'],
          outfits: [
            WorkspaceOutfit(
              id: 'outfit-1',
              name: 'Rain Coat',
              tags: ViewVariantTexts(
                frontFull: 'yellow rain coat',
                frontUpper: 'yellow jacket',
                frontLower: 'rain skirt',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperClothingTags: ['yellow jacket'],
                lowerClothingTags: ['rain skirt'],
              ),
              imageRefs: ['rain.png'],
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(
            snapshot,
            previewPath: '${Uri.base.toFilePath()}assets/appicon.png',
          ),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-character')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('workbench-drawer-card-character-char-1')));
    await tester.pumpAndSettle();

    final originalCard = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-original'),
    );
    final outfitCard = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-outfit-1'),
    );
    expect(originalCard, findsNothing);
    expect(outfitCard, findsOneWidget);
    expect(find.text('默认服装'), findsNothing);

    await tester.ensureVisible(outfitCard);
    await tester.pumpAndSettle();
    await tester.tap(outfitCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-part-character-char-1-outfit-outfit-1-upper-body',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-part-character-char-1-outfit-outfit-1-upper-clothing',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-part-character-char-1-outfit-outfit-1-lower-body',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-part-character-char-1-outfit-outfit-1-lower-clothing',
        ),
      ),
      findsOneWidget,
    );

    final copyPartButton = find.byKey(
      const ValueKey(
        'workbench-drawer-copy-part-character-char-1-outfit-outfit-1-lower-clothing',
      ),
    );
    await tester.scrollUntilVisible(
      copyPartButton,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(copyPartButton);
    await tester.pump();

    expect(clipboardText, 'rain skirt');
    expect(find.text('已复制提示词'), findsOneWidget);
  });

  testWidgets(
      'expanded character rows do not duplicate explicit default outfit',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 2,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(
            frontFull: 'cat ears, blue eyes, fox tail',
            frontUpper: 'cat ears, blue eyes',
            frontLower: 'fox tail',
          ),
          defaultOutfitId: 'default-outfit',
          outfits: [
            WorkspaceOutfit(
              id: 'default-outfit',
              name: '默认服装',
              tags: ViewVariantTexts(
                frontFull: 'black jacket, black shorts',
                frontUpper: 'black jacket',
                frontLower: 'black shorts',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperClothingTags: ['black jacket'],
                lowerClothingTags: ['black shorts'],
              ),
            ),
            WorkspaceOutfit(
              id: 'dress',
              name: 'Red Dress',
              tags: ViewVariantTexts(frontFull: 'red dress'),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(snapshot),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-character')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('workbench-drawer-card-character-char-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
            'workbench-drawer-card-character-char-1-outfit-original'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-card-character-char-1-outfit-default-outfit',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('workbench-drawer-card-character-char-1-outfit-dress'),
      ),
      findsOneWidget,
    );
    expect(find.text('默认服装'), findsOneWidget);
  });

  testWidgets(
      'expanded outfit rows show a hover preview only over that outfit thumbnail',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
          outfits: [
            WorkspaceOutfit(
              id: 'outfit-1',
              name: 'Rain Coat',
              tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
              imageRefs: ['rain.png'],
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(
            snapshot,
            previewPath: '${Uri.base.toFilePath()}assets/appicon.png',
          ),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-character')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('workbench-drawer-card-character-char-1')));
    await tester.pumpAndSettle();

    final outfitCard = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-outfit-1'),
    );
    final outfitPreview = find.byKey(
      const ValueKey(
          'workbench-drawer-preview-character-char-1-outfit-outfit-1'),
    );
    final outfitAddButton = find.byKey(
      const ValueKey('workbench-drawer-add-character-char-1-outfit-outfit-1'),
    );
    await tester.ensureVisible(outfitCard);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(outfitAddButton));
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-preview-character-char-1-outfit-outfit-1-overlay',
        ),
      ),
      findsNothing,
    );

    await mouse.moveTo(tester.getCenter(outfitPreview));
    await tester.pump(kStudioHoverPreviewActivationDelay);

    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-preview-character-char-1-outfit-outfit-1-overlay',
        ),
      ),
      findsOneWidget,
    );

    await mouse.moveTo(Offset.zero);
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey(
          'workbench-drawer-preview-character-char-1-outfit-outfit-1-overlay',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'drawer character assets can be dropped onto a target character card',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final payload = _payload();
    payload.characterConfigList = [
      CharacterConfig.fromEmpty(name: '角色 1'),
      CharacterConfig.fromEmpty(name: '角色 2'),
    ];
    final workbench = StudioWorkbenchAssetService(payloadConfig: payload);
    final parameters = WorkbenchSingleImageParametersViewmodel(payload);
    if (GetIt.I.isRegistered<PayloadConfig>()) {
      GetIt.I.unregister<PayloadConfig>();
    }
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    addTearDown(() {
      if (GetIt.I.isRegistered<PayloadConfig>()) {
        GetIt.I.unregister<PayloadConfig>();
      }
    });

    await tester.pumpWidget(
      _characterDropWorkbenchApp(
        catalogService: _FakeCatalogService(snapshot),
        workbench: workbench,
        parameters: parameters,
      ),
    );
    await tester.pumpAndSettle();
    final categoryCard =
        find.byKey(const ValueKey('workbench-drawer-category-character'));
    if (categoryCard.evaluate().isNotEmpty) {
      await tester.tap(categoryCard);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    final source =
        find.byKey(const ValueKey('workbench-drawer-card-character-char-1'));
    final target = find.byKey(const ValueKey('workbench-character-card-1'));
    await tester.dragFrom(
      tester.getCenter(source),
      tester.getCenter(target) - tester.getCenter(source),
    );
    await tester.pumpAndSettle();

    expect(payload.characterConfigList[1].name, 'Heroine');
    expect(payload.characterConfigList[1].positivePromptConfig.strs,
        ['silver hair, blue eyes']);
    expect(
      find.byKey(const ValueKey('workbench-character-expanded-card-1')),
      findsOneWidget,
    );
  });

  testWidgets('workbench character cards use hover motion surfaces',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final payload = _payload();
    payload.characterConfigList = [
      CharacterConfig.fromEmpty(name: '瑙掕壊 1'),
    ];
    final workbench = StudioWorkbenchAssetService(payloadConfig: payload);
    final parameters = WorkbenchSingleImageParametersViewmodel(payload);
    if (GetIt.I.isRegistered<PayloadConfig>()) {
      GetIt.I.unregister<PayloadConfig>();
    }
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    addTearDown(() {
      if (GetIt.I.isRegistered<PayloadConfig>()) {
        GetIt.I.unregister<PayloadConfig>();
      }
    });

    await tester.pumpWidget(
      _characterDropWorkbenchApp(
        catalogService: _FakeCatalogService(snapshot),
        workbench: workbench,
        parameters: parameters,
      ),
    );
    await tester.pumpAndSettle();

    final characterCard =
        find.byKey(const ValueKey('workbench-character-card-0'));
    expect(
      find.ancestor(
        of: characterCard,
        matching: find.byType(StudioInteractiveSurface),
      ),
      findsOneWidget,
    );

    final characterScale = find.ancestor(
      of: characterCard,
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(characterScale).scale, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(characterCard));
    await tester.pump(StudioMotionTokens.fast);

    expect(tester.widget<AnimatedScale>(characterScale).scale, greaterThan(1));
  });

  testWidgets('expanded character prompt stack accepts drawer outfit drops',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
          outfits: [
            WorkspaceOutfit(
              id: 'dress',
              name: 'Red Dress',
              tags: ViewVariantTexts(frontFull: 'red dress'),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final payload = _payload();
    payload.characterConfigList = [
      CharacterConfig.fromEmpty(name: '角色 1')
        ..positivePromptConfig.strs = ['base character'],
    ];
    final workbench = StudioWorkbenchAssetService(payloadConfig: payload);
    final parameters = WorkbenchSingleImageParametersViewmodel(payload);
    if (GetIt.I.isRegistered<PayloadConfig>()) {
      GetIt.I.unregister<PayloadConfig>();
    }
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    addTearDown(() {
      if (GetIt.I.isRegistered<PayloadConfig>()) {
        GetIt.I.unregister<PayloadConfig>();
      }
    });

    await tester.pumpWidget(
      _characterDropWorkbenchApp(
        catalogService: _FakeCatalogService(snapshot),
        workbench: workbench,
        parameters: parameters,
      ),
    );
    await tester.pumpAndSettle();
    final categoryCard =
        find.byKey(const ValueKey('workbench-drawer-category-character'));
    if (categoryCard.evaluate().isNotEmpty) {
      await tester.tap(categoryCard);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    await tester.tap(
      find.byKey(const ValueKey('workbench-drawer-card-character-char-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-character-card-0')));
    await tester.pumpAndSettle();

    final source = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-dress'),
    );
    final target =
        find.byKey(const ValueKey('workbench-character-prompt-drop-0-1'));
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getCenter(source),
      tester.getCenter(target) - tester.getCenter(source),
    );
    await tester.pumpAndSettle();

    expect(payload.characterConfigList.single.name, '角色 1');
    expect(payload.characterConfigList.single.positivePromptConfig.strs, [
      'base character',
      'silver hair, blue eyes, red dress',
    ]);
  });

  testWidgets('synthetic default outfit card is not draggable', (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-1',
          name: 'Heroine',
          traits: ViewVariantTexts(
            frontFull: 'cat ears, blue eyes, fox tail',
            frontUpper: 'cat ears, blue eyes',
            frontLower: 'fox tail',
          ),
          outfits: [
            WorkspaceOutfit(
              id: 'dress',
              name: 'Red Dress',
              tags: ViewVariantTexts(frontFull: 'red dress'),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _workbenchApp(
        catalogService: _FakeCatalogService(snapshot),
        workbench: workbench,
      ),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-character')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('workbench-drawer-card-character-char-1')),
    );
    await tester.pumpAndSettle();

    final source = find.byKey(
      const ValueKey('workbench-drawer-card-character-char-1-outfit-original'),
    );
    expect(source, findsNothing);
    expect(workbench.fragments, isEmpty);
  });

  testWidgets(
      'drawer shows mini hover preview only when hovering image thumbnails',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(
          id: 'tag-1',
          tag: 'cinematic lighting',
          block: 'camera',
          imageRefs: ['preview.png'],
        ),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());
    final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(
            snapshot,
            previewPath: previewPath,
          ),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final preview = find.byKey(
      const ValueKey('workbench-drawer-preview-tag-tag-1'),
    );
    expect(preview, findsOneWidget);
    expect(tester.getSize(preview), const Size(72, 96));
    expect(
      find.descendant(of: preview, matching: find.byType(Image)),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1')),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('workbench-drawer-preview-tag-tag-1-overlay'),
      ),
      findsNothing,
    );

    await mouse.moveTo(tester.getCenter(preview));
    await tester.pump(kStudioHoverPreviewActivationDelay);

    final overlay = find.byKey(
      const ValueKey('workbench-drawer-preview-tag-tag-1-overlay'),
    );
    expect(overlay, findsOneWidget);
    final overlaySize = tester.getSize(overlay);
    expect(overlaySize.width, lessThanOrEqualTo(kStudioHoverPreviewWidth));
    expect(overlaySize.height, lessThanOrEqualTo(kStudioHoverPreviewHeight));
    final viewportSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    final overlayRect = tester.getRect(overlay);
    expect(
      overlayRect.left,
      greaterThanOrEqualTo(kStudioHoverPreviewViewportPadding),
    );
    expect(
      overlayRect.top,
      greaterThanOrEqualTo(kStudioHoverPreviewViewportPadding),
    );
    expect(
      overlayRect.right,
      lessThanOrEqualTo(
        viewportSize.width - kStudioHoverPreviewViewportPadding,
      ),
    );
    expect(
      overlayRect.bottom,
      lessThanOrEqualTo(
        viewportSize.height - kStudioHoverPreviewViewportPadding,
      ),
    );

    await mouse.moveTo(Offset.zero);
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('workbench-drawer-preview-tag-tag-1-overlay'),
      ),
      findsNothing,
    );
  });

  testWidgets('hovered drawer previews cycle with the mouse wheel',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(
          id: 'tag-1',
          tag: 'cinematic lighting',
          block: 'camera',
          imageRefs: ['first.png', 'second.png'],
        ),
      ],
    );
    final tempDir = Directory.systemTemp.createTempSync(
      'drawer-preview-wheel-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final source = File('${Uri.base.toFilePath()}assets/appicon.png');
    final first = File('${tempDir.path}${Platform.pathSeparator}first.png')
      ..writeAsBytesSync(source.readAsBytesSync());
    final second = File('${tempDir.path}${Platform.pathSeparator}second.png')
      ..writeAsBytesSync(source.readAsBytesSync());
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(
            snapshot,
            previewPathsByRef: {
              'first.png': first.path,
              'second.png': second.path,
            },
          ),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    String imagePathFor(Finder root) {
      final image = tester
          .widgetList<Image>(
            find.descendant(of: root, matching: find.byType(Image)),
          )
          .single;
      return (image.image as FileImage).file.path;
    }

    final preview = find.byKey(
      const ValueKey('workbench-drawer-preview-tag-tag-1'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(preview));
    await tester.pump(kStudioHoverPreviewActivationDelay);

    final overlay = find.byKey(
      const ValueKey('workbench-drawer-preview-tag-tag-1-overlay'),
    );
    expect(overlay, findsOneWidget);
    expect(imagePathFor(preview), first.path);
    expect(imagePathFor(overlay), first.path);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(preview),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();

    expect(imagePathFor(preview), second.path);
    expect(imagePathFor(overlay), second.path);

    await mouse.moveTo(Offset.zero);
    await tester.pump();

    expect(overlay, findsNothing);
    expect(imagePathFor(preview), second.path);
  });

  testWidgets('hovered drawer preview wheel events do not scroll the drawer',
      (tester) async {
    final snapshot = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 24,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 24},
      ),
      characters: const [],
      artistChains: const [],
      recipes: const [],
      tags: [
        const TagEntry(
          id: 'tag-1',
          tag: 'cinematic lighting',
          block: 'camera',
          imageRefs: ['first.png', 'second.png'],
        ),
        for (var index = 2; index <= 24; index++)
          TagEntry(
            id: 'tag-$index',
            tag: 'camera tag $index',
            block: 'camera',
          ),
      ],
    );
    final tempDir = Directory.systemTemp.createTempSync(
      'drawer-preview-no-scroll-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final source = File('${Uri.base.toFilePath()}assets/appicon.png');
    final first = File('${tempDir.path}${Platform.pathSeparator}first.png')
      ..writeAsBytesSync(source.readAsBytesSync());
    final second = File('${tempDir.path}${Platform.pathSeparator}second.png')
      ..writeAsBytesSync(source.readAsBytesSync());
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _studioApp(
        WorkbenchAssetDrawer(
          catalogService: _FakeCatalogService(
            snapshot,
            previewPathsByRef: {
              'first.png': first.path,
              'second.png': second.path,
            },
          ),
          workbenchAssetService: workbench,
        ),
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    String imagePathFor(Finder root) {
      final image = tester
          .widgetList<Image>(
            find.descendant(of: root, matching: find.byType(Image)),
          )
          .single;
      return (image.image as FileImage).file.path;
    }

    final preview = find.byKey(
      const ValueKey('workbench-drawer-preview-tag-tag-1'),
    );
    final scrollableState =
        tester.state<ScrollableState>(find.byType(Scrollable).last);
    final offsetBefore = scrollableState.position.pixels;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(preview));
    await tester.pump(kStudioHoverPreviewActivationDelay);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(preview),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();

    expect(scrollableState.position.pixels, offsetBefore);
    expect(imagePathFor(preview), second.path);
  });

  testWidgets('drawer cards can be dragged into a composer drop position',
      (tester) async {
    const snapshot = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'camera': 1},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
      ],
    );
    final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

    await tester.pumpWidget(
      _workbenchApp(
        catalogService: _FakeCatalogService(snapshot),
        workbench: workbench,
      ),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-drawer-category-tag')));
    await tester.pump();
    await tester.pump();

    final source =
        find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1'));
    final target =
        find.byKey(const ValueKey('workbench-manual-positive-editor'));
    final insertionSlot = find.byKey(const ValueKey('prompt-drop-target-0'));
    expect(tester.getSize(insertionSlot).height, 0);

    final gesture = await tester.startGesture(tester.getCenter(source));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.getSize(insertionSlot).height, greaterThan(0));
    expect(find.text('松开插入到这里'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(workbench.fragments.single.positiveText, 'cinematic lighting');
    expect(workbench.payloadConfig.overridePrompt, 'cinematic lighting');
    final promptBlock = find.byKey(
      ValueKey('prompt-block-editor-${workbench.fragments.single.id}'),
    );
    expect(
      find.ancestor(
        of: promptBlock,
        matching: find.byType(StudioStaggeredReveal),
      ),
      findsOneWidget,
    );
  });
}
