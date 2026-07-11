import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/command_status.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_exhibition_recast_summary.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/data/studio/services/production_executor_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_capture_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/studio/services/tokenizer_script_service.dart';
import 'package:novel_studio/data/studio/services/workbench_transfer_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:novel_studio/ui/navigation/view_models/navigation_view_model.dart';
import 'package:novel_studio/ui/navigation/widgets/navigation_view.dart';
import 'package:novel_studio/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:novel_studio/ui/studio_shell/models/studio_startup_open_request.dart';
import 'package:novel_studio/ui/studio_shell/models/studio_shell_section.dart';
import 'package:novel_studio/ui/studio_shell/widgets/asset_library_page.dart';
import 'package:novel_studio/ui/studio_shell/widgets/script_exhibition_room_page.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_shell_view.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

class _NavigationAssetLoader extends AssetLoader {
  const _NavigationAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'generation_settings': 'Generation settings',
      'generate_one_prompt': 'Generate one prompt',
      'save_config_preview': 'Save preview',
      'toggle_generation': 'Toggle generation',
      'workbench_import': 'Import workbench',
      'workbench_export': 'Export workbench',
      'press_again_to_exit': 'Press again to exit',
      'welcome_message_title': 'Welcome',
      'welcome_message_markdown': 'Welcome',
      'dont_show_again': 'Do not show again',
      'confirm': 'Confirm',
    };
  }
}

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService() : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    return const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
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
  }

  @override
  Future<StudioAssetCatalogSummary?> loadCachedSummary() async {
    return (await loadSnapshot()).summary;
  }

  @override
  Future<StudioAssetCatalogSummary> loadSummary() async {
    return (await loadSnapshot()).summary;
  }

  @override
  Future<Set<String>> loadAssetFavoriteKeys() async => const {};

  @override
  Future<void> setAssetFavorite(String key, bool isFavorite) async {}
}

class _AssetNavigationCatalogService extends StudioAssetCatalogService {
  _AssetNavigationCatalogService()
      : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    return const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'library-char',
          name: 'Library Character',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
          outfits: [
            WorkspaceOutfit(
              id: 'library-outfit',
              name: 'Library Outfit',
              tags: ViewVariantTexts(frontFull: 'white jacket'),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
  }

  @override
  Future<StudioAssetCatalogSummary?> loadCachedSummary() async {
    return (await loadSnapshot()).summary;
  }

  @override
  Future<StudioAssetCatalogSummary> loadSummary() async {
    return (await loadSnapshot()).summary;
  }

  @override
  Future<Set<String>> loadAssetFavoriteKeys() async => const {};

  @override
  Future<void> setAssetFavorite(String key, bool isFavorite) async {}
}

class _CountingAssetNavigationCatalogService
    extends _AssetNavigationCatalogService {
  int snapshotRequestCount = 0;

  @override
  Future<StudioAssetCatalogCacheLoadResult> loadSnapshotWithCache({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool checkStaleness = true,
    bool persistCacheBeforeReturn = true,
  }) async {
    snapshotRequestCount += 1;
    return StudioAssetCatalogCacheLoadResult(
      snapshot: await loadSnapshot(
        includeLegacyCodex: includeLegacyCodex,
        legacyCodexLimit: legacyCodexLimit,
        legacyCodexQuery: legacyCodexQuery,
        legacyCodexCategoryKey: legacyCodexCategoryKey,
      ),
      fromCache: false,
      isStale: false,
    );
  }
}

class _CountingHomeCatalogService extends _AssetNavigationCatalogService {
  _CountingHomeCatalogService({this.cachedSummary});

  final StudioAssetCatalogSummary? cachedSummary;
  int cachedSummaryRequestCount = 0;
  int summaryRequestCount = 0;

  @override
  Future<StudioAssetCatalogSummary?> loadCachedSummary() async {
    cachedSummaryRequestCount += 1;
    return cachedSummary;
  }

  @override
  Future<StudioAssetCatalogSummary> loadSummary() async {
    summaryRequestCount += 1;
    return (await loadSnapshot()).summary;
  }
}

class _FakeGalleryService extends StudioGalleryService {
  _FakeGalleryService([List<StudioGalleryRecord> records = const []])
      : records = List.unmodifiable(records),
        super(workspaceService: WorkspaceService());

  List<StudioGalleryRecord> records;

  @override
  Future<List<StudioGalleryRecord>> loadRecords() async {
    return records;
  }

  @override
  Future<List<StudioGalleryRecord>> loadRecastRecords() async {
    return [
      for (final record in records)
        if (record.provenance != null) record,
    ];
  }

  @override
  Future<StudioGalleryCreativeSummary> loadCreativeRecordSummary({
    int recentLimit = 4,
  }) async {
    final creativeRecords = await loadCreativeRecords();
    return StudioGalleryCreativeSummary(
      totalCount: creativeRecords.length,
      recentRecords: creativeRecords.take(recentLimit).toList(growable: false),
    );
  }

  @override
  Future<void> saveRecords(List<StudioGalleryRecord> records) async {
    this.records = List.unmodifiable(records);
  }

  @override
  Future<void> removeRecord(String id, {bool deleteImageFile = false}) async {
    records = List.unmodifiable(
      records.where((record) => record.id != id),
    );
  }
}

class _CountingHomeGalleryService extends _FakeGalleryService {
  int creativeSummaryLoadCount = 0;

  @override
  Future<StudioGalleryCreativeSummary> loadCreativeRecordSummary({
    int recentLimit = 4,
  }) async {
    creativeSummaryLoadCount += 1;
    final records = await super.loadCreativeRecords();
    return StudioGalleryCreativeSummary(
      totalCount: records.length,
      recentRecords: records.take(recentLimit).toList(growable: false),
    );
  }
}

class _FakeTokenizerScriptService extends TokenizerScriptService {
  _FakeTokenizerScriptService(this.scripts)
      : super(workspaceService: WorkspaceService());

  final List<TokenizerScript> scripts;

  @override
  Future<List<TokenizerScript>> loadScripts() async => scripts;
}

class _FakeWorkspaceService extends WorkspaceService {
  _FakeWorkspaceService({
    List<RecastScriptCache> caches = const [],
    List<RecastExhibitionScript> summaryScripts = const [],
    Directory? root,
  })  : _root = root,
        caches = List.unmodifiable(caches),
        summaryScripts = List.unmodifiable(summaryScripts);

  final Directory? _root;
  List<RecastScriptCache> caches;
  List<RecastExhibitionScript> summaryScripts;
  int summaryLoadCount = 0;

  @override
  Directory? get root => _root;

  @override
  Future<List<RecastScriptCache>> loadRecastScriptCaches() async => caches;

  @override
  Future<RecastScriptCache?> loadRecastScriptCache(String scriptId) async {
    final normalized = scriptId.trim();
    for (final cache in caches) {
      if (cache.scriptId == normalized) {
        return cache;
      }
    }
    return null;
  }

  @override
  Future<List<RecastExhibitionScript>> loadRecastExhibitionSummaries() async {
    summaryLoadCount += 1;
    return summaryScripts;
  }

  @override
  Future<List<String>> loadScriptExhibitionCategories() async => const [];

  @override
  Future<Map<String, List<String>>>
      loadScriptExhibitionCategoryAssignments() async => const {};

  @override
  Future<void> saveRecastScriptCache(RecastScriptCache cache) async {
    caches = List.unmodifiable([
      for (final existing in caches)
        if (existing.scriptId != cache.scriptId) existing,
      cache,
    ]);
  }

  @override
  Future<void> saveRecastScriptCaches(List<RecastScriptCache> caches) async {
    this.caches = List.unmodifiable(caches);
  }
}

class _FakeProductionQueueService extends ProductionQueueService {
  _FakeProductionQueueService(this.plans)
      : super(workspaceService: WorkspaceService());

  List<ProductionPlan> plans;
  int loadCount = 0;

  @override
  Future<List<ProductionPlan>> loadPlans() async {
    loadCount += 1;
    return plans;
  }

  int readOnlyLoadCount = 0;

  @override
  Future<List<ProductionPlan>> loadPlansReadOnly() async {
    readOnlyLoadCount += 1;
    return plans;
  }

  @override
  Future<void> savePlans(List<ProductionPlan> plans) async {
    this.plans = List.unmodifiable(plans);
  }

  @override
  Future<ProductionPlanExecutionSettings?> loadLastExecutionSettings() async {
    return null;
  }

  @override
  Future<void> saveLastExecutionSettings(
    ProductionPlanExecutionSettings settings,
  ) async {}
}

class _SendReadyScriptViewModel extends StudioScriptViewModel {
  int sendCount = 0;

  @override
  Future<bool> sendToProduction() async {
    sendCount += 1;
    return true;
  }
}

class _RecordingScriptViewModel extends StudioScriptViewModel {
  final importedPaths = <String>[];
  final openedExhibitionScripts = <({String scriptId, String sourceFolder})>[];
  int? selectedFrame;

  @override
  Future<void> importScriptPath(String path) async {
    importedPaths.add(path);
  }

  @override
  Future<void> openScriptFromExhibition({
    required String scriptId,
    required String sourceFolder,
    int? frameIndex,
  }) async {
    openedExhibitionScripts.add((
      scriptId: scriptId,
      sourceFolder: sourceFolder,
    ));
    if (frameIndex != null) {
      selectedFrame = frameIndex;
    }
  }

  @override
  void selectFrame(int frameIndex) {
    selectedFrame = frameIndex;
  }
}

class _RecordingWorkbenchTransferViewModel extends WorkbenchTransferViewModel {
  final importedFileNames = <String>[];
  final importedBytes = <Uint8List>[];

  _RecordingWorkbenchTransferViewModel({
    required super.payloadConfig,
  }) : super(
          transferService: WorkbenchTransferService(),
        );

  @override
  Future<void> importBytes(
    BuildContext context,
    String fileName,
    Uint8List bytes,
  ) async {
    importedFileNames.add(fileName);
    importedBytes.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> importFile(
    BuildContext context,
    File file, {
    bool showFeedback = true,
  }) async {
    importedFileNames.add(file.uri.pathSegments.last);
    importedBytes.add(Uint8List.fromList(file.readAsBytesSync()));
  }
}

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({'welcome_message_version': '1.0.0'}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

Uint8List _transparentPngBytes() {
  return Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l2Kc9wAAAABJRU5ErkJggg==',
    ),
  );
}

Widget _buildNavigationApp({NavigationViewModel? viewModel}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/l10n',
    assetLoader: const _NavigationAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    saveLocale: false,
    child: Builder(
      builder: (context) => MaterialApp(
        theme: StudioTheme.build(),
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: NavigationView(viewModel: viewModel ?? NavigationViewModel()),
      ),
    ),
  );
}

Widget _buildStudioShellApp({
  NavigationViewModel? viewModel,
  void Function(StudioShellSection section)? debugOnCreatePage,
  StudioStartupOpenRequest? startupOpenRequest,
}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/l10n',
    assetLoader: const _NavigationAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    saveLocale: false,
    child: Builder(
      builder: (context) => MaterialApp(
        theme: StudioTheme.build(),
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: StudioShellView(
          viewModel: viewModel ?? NavigationViewModel(),
          debugOnCreatePage: debugOnCreatePage,
          startupOpenRequest: startupOpenRequest,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return true;
    });
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await GetIt.I.reset();
    final configService = ConfigService();
    configService.packageInfo = PackageInfo(
      appName: 'Novel Studio',
      packageName: 'novel.studio',
      version: '1.0.0',
      buildNumber: '1',
    );
    final payload = _payload();
    GetIt.I.registerSingleton<ConfigService>(configService);
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
    GetIt.I.registerSingleton<WorkspaceService>(_FakeWorkspaceService());
    GetIt.I.registerSingleton<StudioAssetCatalogService>(_FakeCatalogService());
    GetIt.I.registerSingleton<StudioWorkbenchAssetService>(
      StudioWorkbenchAssetService(payloadConfig: payload),
    );
    GetIt.I.registerSingleton<StudioGalleryService>(_FakeGalleryService());
    GetIt.I.registerSingleton<StudioAssetCaptureService>(
      StudioAssetCaptureService(workspaceService: WorkspaceService()),
    );
    GetIt.I.registerSingleton<StudioAssetPreviewGenerationService>(
      StudioAssetPreviewGenerationService(
        workspaceService: WorkspaceService(),
        requestImage: (_) async => Uint8List(0),
        saveImage: (_, fileName) async => 'C:/preview/$fileName',
      ),
    );
    GetIt.I.registerSingleton<TokenizerScriptService>(
      _FakeTokenizerScriptService(const []),
    );
    GetIt.I.registerSingleton<ProductionQueueService>(
      _FakeProductionQueueService(const []),
    );
    GetIt.I.registerSingleton<WorkbenchTransferService>(
      WorkbenchTransferService(),
    );
    GetIt.I.registerFactory(
      () => WorkbenchTransferViewModel(
        payloadConfig: payload,
        transferService: GetIt.I<WorkbenchTransferService>(),
      ),
    );
    GetIt.I.registerSingleton<GenerationPageViewmodel>(
      GenerationPageViewmodel(),
    );
    GetIt.I.registerFactory<StudioScriptViewModel>(
      () => StudioScriptViewModel(),
    );
    GetIt.I.registerFactory<ProductionQueueViewModel>(
      () => ProductionQueueViewModel(plans: [_productionPlan()]),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('navigation exposes the studio product areas', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-page-cache-host')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-hero-reveal')), findsOneWidget);

    final navKeys = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              ((widget.key! as ValueKey<String>).value)
                  .startsWith('studio-nav-'),
        )
        .evaluate()
        .map((element) => (element.widget.key! as ValueKey<String>).value)
        .toList();

    expect(navKeys, [
      'studio-nav-home',
      'studio-nav-workbench',
      'studio-nav-assets',
      'studio-nav-script',
      'studio-nav-batch',
      'studio-nav-scriptExhibition',
      'studio-nav-gallery',
      'studio-nav-settings',
    ]);
    expect(find.byKey(const ValueKey('studio-nav-tools')), findsNothing);
  });

  testWidgets('desktop main navigation exposes animated tab indicator',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-side-nav-selection-indicator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-side-nav-selection-liquid-pulse')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-bottom-nav-selection-indicator')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-side-nav-selection-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('compact main navigation exposes animated tab indicator',
      (tester) async {
    tester.view.physicalSize = const Size(760, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-bottom-nav-selection-indicator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-bottom-nav-selection-liquid-pulse')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-side-nav-selection-indicator')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-bottom-nav-selection-indicator')),
      findsOneWidget,
    );
  });

  testWidgets(
      'home data load waits until after startup and uses cached summary',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const cachedSummary = StudioAssetCatalogSummary(
      characterCount: 3,
      outfitCount: 2,
      artistChainCount: 1,
      recipeCount: 4,
      tagCount: 5,
      recipeCountsByBlock: {},
      tagCountsByBlock: {},
    );
    final catalogService =
        _CountingHomeCatalogService(cachedSummary: cachedSummary);
    final galleryService = _CountingHomeGalleryService();
    await GetIt.I.unregister<StudioAssetCatalogService>();
    await GetIt.I.unregister<StudioGalleryService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(catalogService);
    GetIt.I.registerSingleton<StudioGalleryService>(galleryService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    expect(catalogService.cachedSummaryRequestCount, 0);
    expect(catalogService.summaryRequestCount, 0);
    expect(galleryService.creativeSummaryLoadCount, 0);

    await tester.pump(const Duration(milliseconds: 410));

    expect(catalogService.cachedSummaryRequestCount, 0);
    expect(catalogService.summaryRequestCount, 0);
    expect(galleryService.creativeSummaryLoadCount, 0);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(catalogService.cachedSummaryRequestCount, 1);
    expect(catalogService.summaryRequestCount, 0);
    expect(galleryService.creativeSummaryLoadCount, 1);
  });

  testWidgets('asset navigation mounts the first heavy page on the click frame',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogService = _CountingAssetNavigationCatalogService();
    await GetIt.I.unregister<StudioAssetCatalogService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(catalogService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pump();

    expect(catalogService.snapshotRequestCount, 1);
    expect(find.byKey(const ValueKey('home-hero-reveal')), findsNothing);
    expect(
      find.byKey(const ValueKey('studio-page-pending-assets')),
      findsNothing,
    );
    expect(find.byType(AssetLibraryPage), findsOneWidget);

    await tester.pumpAndSettle();
    expect(catalogService.snapshotRequestCount, 1);
    expect(
        find.byKey(const ValueKey('studio-page-cache-host')), findsOneWidget);
    expect(find.text('Library Character'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('studio-nav-home')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-hero-reveal')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pump();
    expect(catalogService.snapshotRequestCount, 1);
    expect(
      find.byKey(const ValueKey('studio-page-pending-assets')),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(catalogService.snapshotRequestCount, 1);
    expect(find.text('Library Character'), findsOneWidget);
  });

  testWidgets('asset navigation starts loading on the first selected frame',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogService = _CountingAssetNavigationCatalogService();
    await GetIt.I.unregister<StudioAssetCatalogService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(catalogService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pump();

    expect(catalogService.snapshotRequestCount, 1);
    expect(find.byKey(const ValueKey('home-hero-reveal')), findsNothing);
    expect(
      find.byKey(const ValueKey('studio-page-pending-assets')),
      findsNothing,
    );
    expect(find.byType(AssetLibraryPage), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Library Character'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('studio-page-transition')),
      findsOneWidget,
    );
  });

  testWidgets('asset navigation hover does not mount heavy target before click',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogService = _CountingAssetNavigationCatalogService();
    await GetIt.I.unregister<StudioAssetCatalogService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(catalogService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('studio-nav-assets')).first,
      ),
    );
    await tester.pump();

    expect(catalogService.snapshotRequestCount, 0);
    expect(find.byType(AssetLibraryPage), findsNothing);
    expect(
      find.byType(AssetLibraryPage, skipOffstage: false),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pump();

    expect(catalogService.snapshotRequestCount, 1);
    expect(find.byType(AssetLibraryPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('studio-page-pending-assets')),
      findsNothing,
    );
  });

  testWidgets('studio shell does not idle prewarm during startup',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogService = _CountingAssetNavigationCatalogService();
    await GetIt.I.unregister<StudioAssetCatalogService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(catalogService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    expect(catalogService.snapshotRequestCount, 0);
    expect(find.byKey(const ValueKey('home-hero-reveal')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump();

    expect(catalogService.snapshotRequestCount, 0);
    expect(find.byType(AssetLibraryPage), findsNothing);
    expect(
      find.byType(AssetLibraryPage, skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('studio shell startup does not prewarm production-backed pages',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final productionService = _FakeProductionQueueService([
      _exhibitionProductionPlan(),
    ]);
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3600));

    expect(productionService.loadCount, 0);
    expect(productionService.readOnlyLoadCount, 0);
  });

  testWidgets('studio shell does not prewarm script exhibition summaries',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspaceRoot =
        Directory.systemTemp.createTempSync('script-exhibition-warmup-test-');
    addTearDown(() {
      if (workspaceRoot.existsSync()) {
        workspaceRoot.deleteSync(recursive: true);
      }
    });
    final workspaceService = _FakeWorkspaceService(root: workspaceRoot);
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(workspaceService);

    final created = <StudioShellSection>[];
    await tester.pumpWidget(
      _buildStudioShellApp(debugOnCreatePage: created.add),
    );
    await tester.pump();

    expect(workspaceService.summaryLoadCount, 0);
    expect(find.byType(ScriptExhibitionRoomPage), findsNothing);

    await tester.pump(const Duration(milliseconds: 751));
    await tester.pump();

    expect(workspaceService.summaryLoadCount, 0);
    expect(created, isNot(contains(StudioShellSection.scriptExhibition)));
    expect(find.byType(ScriptExhibitionRoomPage), findsNothing);
    expect(
      find.byType(ScriptExhibitionRoomPage, skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('script exhibition first navigation loads on the click frame',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspaceRoot = Directory.systemTemp
        .createTempSync('script-exhibition-click-nav-test-');
    addTearDown(() {
      if (workspaceRoot.existsSync()) {
        workspaceRoot.deleteSync(recursive: true);
      }
    });
    final workspaceService = _FakeWorkspaceService(root: workspaceRoot);
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(workspaceService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('script-exhibition-room-page')),
        findsOneWidget);
    expect(workspaceService.summaryLoadCount, 1);
    expect(
      find.byKey(const ValueKey('studio-page-pending-scriptExhibition')),
      findsNothing,
    );
  });

  testWidgets('script exhibition reloads when re-entering cached page',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspaceRoot = Directory.systemTemp
        .createTempSync('script-exhibition-reenter-refresh-test-');
    addTearDown(() {
      if (workspaceRoot.existsSync()) {
        workspaceRoot.deleteSync(recursive: true);
      }
    });
    final image = File('${workspaceRoot.path}${Platform.pathSeparator}001.png');
    image.writeAsBytesSync([1, 2, 3]);
    final workspaceService = _FakeWorkspaceService(root: workspaceRoot);
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(workspaceService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(workspaceService.summaryLoadCount, 1);
    expect(
      find.byKey(const ValueKey('script-exhibition-draggable-script-fresh')),
      findsNothing,
    );

    workspaceService.summaryScripts = [
      RecastExhibitionScript(
        scriptId: 'script-fresh',
        scriptName: 'Fresh visible script',
        sourceRootPath: workspaceRoot.path,
        updatedAt: DateTime.parse('2026-06-28T09:00:00Z'),
        detectedSchema: ScriptSchema.unknown,
        frames: [
          RecastExhibitionFrame(
            index: 1,
            fileName: '001.png',
            sourcePath: image.path,
            sourceImagePath: image.path,
          ),
        ],
        frameCount: 1,
        summaryOnly: true,
      ),
    ];

    await tester.tap(find.byKey(const ValueKey('studio-nav-home')).first);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pump();
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i += 1) {
      final page = tester.widget<ScriptExhibitionRoomPage>(
        find.byType(ScriptExhibitionRoomPage).first,
      );
      if (page.viewModel.snapshot.scripts
          .any((script) => script.scriptId == 'script-fresh')) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(workspaceService.summaryLoadCount, 2);
    final page = tester.widget<ScriptExhibitionRoomPage>(
      find.byType(ScriptExhibitionRoomPage).first,
    );
    expect(page.viewModel.loadError, isNull);
    expect(
      page.viewModel.snapshot.scripts.map((script) => script.scriptId),
      contains('script-fresh'),
    );
    expect(
      page.viewModel.visibleScripts.map((script) => script.scriptId),
      contains('script-fresh'),
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-draggable-script-fresh')),
      findsOneWidget,
    );
  });

  testWidgets('studio shell reuses cached stable pages across navigation',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final created = <StudioShellSection, int>{};
    await tester.pumpWidget(
      _buildStudioShellApp(
        debugOnCreatePage: (section) {
          created.update(section, (value) => value + 1, ifAbsent: () => 1);
        },
      ),
    );
    await tester.pump();

    Future<void> open(StudioShellSection section) async {
      await tester
          .tap(find.byKey(ValueKey('studio-nav-${section.name}')).first);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }

    await open(StudioShellSection.assets);
    await open(StudioShellSection.workbench);
    await open(StudioShellSection.script);
    await open(StudioShellSection.gallery);
    await open(StudioShellSection.assets);
    await open(StudioShellSection.workbench);
    await open(StudioShellSection.script);

    expect(created[StudioShellSection.assets], 1);
    expect(created[StudioShellSection.workbench], 1);
    expect(created[StudioShellSection.script], 1);
    expect(created[StudioShellSection.gallery], 1);
  });

  testWidgets('batch navigation uses registered deterministic production queue',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final batchViewModel = ProductionQueueViewModel(plans: [_productionPlan()]);
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueViewModel>(batchViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Injected Recast Queue'), findsOneWidget);
    expect(batchViewModel.selectedTask?.title, 'Frame 1');
  });

  testWidgets('batch navigation refreshes persisted queue settings',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final productionService = _FakeProductionQueueService([
      _productionPlan(
        executionSettings: const ProductionPlanExecutionSettings(
          model: 'persisted-model',
          sampler: 'persisted-sampler',
          requestIntervalSeconds: 17,
        ),
      ),
    ]);
    final batchViewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: productionService,
      settings: const ProductionQueueExecutionSettings(
        model: 'default-model',
        sampler: 'default-sampler',
        requestIntervalSeconds: 3,
      ),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);
    GetIt.I.registerFactory<ProductionQueueViewModel>(() => batchViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('studio-nav-batch')).first);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(productionService.loadCount, 0);
    expect(productionService.readOnlyLoadCount, 1);
    expect(batchViewModel.batchModel, 'persisted-model');
    expect(batchViewModel.batchSampler, 'persisted-sampler');
    expect(batchViewModel.requestIntervalSeconds, 17);
    expect(find.text('Injected Recast Queue'), findsOneWidget);
  });

  testWidgets('script send refreshes batch production without auto-starting',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestedPayloads = <Map<String, dynamic>>[];
    final productionService = _FakeProductionQueueService([
      _productionPlan(),
    ]);
    final scriptViewModel = _SendReadyScriptViewModel();
    final batchViewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: productionService,
      executorService: ProductionExecutorService(
        queueService: productionService,
        requestImage: (payload) async {
          requestedPayloads.add(payload);
          return Uint8List.fromList([1, 2, 3]);
        },
        saveImage: (_, fileName) async => 'C:/generated/$fileName',
        now: () => DateTime.utc(2026, 6, 7, 12),
      ),
    );
    await GetIt.I.unregister<StudioScriptViewModel>();
    GetIt.I.registerSingleton<StudioScriptViewModel>(scriptViewModel);
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueViewModel>(batchViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('studio-nav-script')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('script-send-production')));
    await tester.pumpAndSettle();

    expect(scriptViewModel.sendCount, 1);
    expect(productionService.loadCount, 0);
    expect(productionService.readOnlyLoadCount, 1);
    expect(requestedPayloads, isEmpty);
    expect(batchViewModel.completedTasks, 0);
    expect(batchViewModel.selectedTask?.status, ProductionTaskStatus.queued);
    expect(batchViewModel.isExecuting, isFalse);
    expect(find.text('Injected Recast Queue'), findsOneWidget);
  });

  testWidgets('settings navigation opens the knowledge and rules workspace',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('studio-nav-settings')).first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-knowledge-and-rules-section')),
      findsNothing,
    );

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-knowledge-and-rules-section')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('studio-tool-card-knowledge-base')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('studio-tools-open-script-review')),
        findsNothing);
    expect(find.text('快速入口'), findsNothing);
  });

  testWidgets('script exhibition navigation opens its standalone room',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('script-exhibition-room-page')),
        findsOneWidget);
    expect(find.text('剧本展览室'), findsWidgets);
    expect(
      find.byKey(const ValueKey('script-exhibition-send-to-workbench')),
      findsNothing,
    );
  });

  testWidgets('script exhibition navigation does not refresh batch display',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final productionService = _FakeProductionQueueService([
      _exhibitionProductionPlan(),
    ]);
    final batchViewModel = ProductionQueueViewModel(
      plans: [_productionPlan()],
      queueService: productionService,
    );
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(caches: [_exhibitionRecastCache()]),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueViewModel>(batchViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();

    expect(productionService.loadCount, 0);
    expect(productionService.readOnlyLoadCount, 1);
    expect(batchViewModel.selectedPlan?.id, 'injected-plan');
    expect(batchViewModel.selectedTask?.id, 'injected-task-1');
  });

  testWidgets('script exhibition refreshes after batch task completes',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final outputDirectory = await Directory.systemTemp.createTemp(
      'script-exhibition-live-production-',
    );
    addTearDown(() async {
      if (await outputDirectory.exists()) {
        await outputDirectory.delete(recursive: true);
      }
    });
    final productionService = _FakeProductionQueueService([
      _exhibitionProductionPlan(
        outputImagePath: '',
        status: ProductionTaskStatus.queued,
      ),
    ]);
    final batchViewModel = ProductionQueueViewModel(
      plans: productionService.plans,
      queueService: productionService,
      executorService: ProductionExecutorService(
        queueService: productionService,
        requestImage: (_) async => _transparentPngBytes(),
        saveImage: (bytes, fileName) async {
          final file = File(
            '${outputDirectory.path}${Platform.pathSeparator}$fileName',
          );
          await file.writeAsBytes(bytes);
          return file.path;
        },
        now: () => DateTime.utc(2026, 6, 2, 9),
      ),
    );
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(caches: [_exhibitionRecastCache()]),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueViewModel>(batchViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-1')),
    );
    await tester.pumpAndSettle();

    final productionImage = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.key ==
              const ValueKey(
                  'script-exhibition-image-production-plan-1-task-1'),
    );
    expect(productionImage, findsNothing);

    await batchViewModel.start();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(batchViewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(productionImage, findsOneWidget);
    expect(productionService.readOnlyLoadCount, greaterThanOrEqualTo(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('script exhibition pending item opens its batch production task',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final productionService = _FakeProductionQueueService([
      _productionPlan(),
      _exhibitionProductionPlan(
        outputImagePath: '',
        status: ProductionTaskStatus.queued,
      ),
    ]);
    final batchViewModel = ProductionQueueViewModel(
      plans: [_productionPlan()],
      queueService: productionService,
    );
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(caches: [_exhibitionRecastCache()]),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueViewModel>(batchViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-metric-needs-action')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-detail-open-production')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('studio-batch-queue-panel')),
      findsOneWidget,
    );
    expect(batchViewModel.selectedPlan?.id, 'plan-1');
    expect(batchViewModel.selectedTask?.id, 'task-1');
    expect(batchViewModel.selectedTask?.status, ProductionTaskStatus.queued);
    expect(batchViewModel.isExecuting, isFalse);
  });

  testWidgets('script exhibition rerun gives immediate queue feedback',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final productionService = _FakeProductionQueueService([
      _exhibitionProductionPlan(),
    ]);
    final batchViewModel = ProductionQueueViewModel(
      plans: [_productionPlan()],
      queueService: productionService,
    );
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(caches: [_exhibitionRecastCache()]),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueViewModel>(batchViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-rerun-production-plan-1-task-1'),
      ),
    );
    await tester.pump();

    expect(find.text('已加入重跑队列，原图会保留'), findsOneWidget);
    expect(
      batchViewModel.selectedTask?.id,
      startsWith('task-1-rerun'),
    );
  });

  testWidgets('script exhibition detail sends script to script workbench',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scriptViewModel = _RecordingScriptViewModel();
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(caches: [_exhibitionRecastCache()]),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(
      _FakeProductionQueueService([_exhibitionProductionPlan()]),
    );
    await GetIt.I.unregister<StudioScriptViewModel>();
    GetIt.I.registerSingleton<StudioScriptViewModel>(scriptViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-detail-send-script-workbench'),
      ),
    );
    await tester.pump();
    await tester.idle();

    expect(scriptViewModel.importedPaths, isEmpty);
    expect(scriptViewModel.openedExhibitionScripts, [
      (scriptId: 'script-1', sourceFolder: r'C:\stories\rain'),
    ]);
    expect(scriptViewModel.selectedFrame, isNull);
  });

  testWidgets('startup open request opens cached script in script workbench',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigationViewModel = NavigationViewModel();
    final scriptViewModel = _RecordingScriptViewModel();
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(
        caches: [
          _exhibitionRecastCache(
            scriptId: 'script-startup',
            rootPath: r'C:\stories\startup',
          ),
        ],
      ),
    );
    await GetIt.I.unregister<StudioScriptViewModel>();
    GetIt.I.registerSingleton<StudioScriptViewModel>(scriptViewModel);

    await tester.pumpWidget(
      _buildStudioShellApp(
        viewModel: navigationViewModel,
        startupOpenRequest: const StudioStartupOpenRequest(
          scriptId: 'script-startup',
          frameIndex: 3,
        ),
      ),
    );
    await tester.pump();
    await tester.idle();
    await tester.pumpAndSettle();

    expect(navigationViewModel.currentPageIndex, 3);
    expect(scriptViewModel.importedPaths, isEmpty);
    expect(scriptViewModel.openedExhibitionScripts, [
      (scriptId: 'script-startup', sourceFolder: r'C:\stories\startup'),
    ]);
    expect(scriptViewModel.selectedFrame, 3);
  });

  testWidgets(
      'script exhibition delete removes normalized-path production leftovers',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspaceService = _FakeWorkspaceService(
      caches: [
        _exhibitionRecastCache(rootPath: r'C:\Stories\Rain\'),
      ],
    );
    final productionService = _FakeProductionQueueService([
      _exhibitionProductionPlan(
        scriptId: 'script-regenerated',
        scriptName: 'Generated Rain',
        scriptPath: 'c:/stories/rain',
      ),
    ]);
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(workspaceService);
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-delete-script-script-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-script')),
    );
    await tester.pumpAndSettle();

    expect(workspaceService.caches, isEmpty);
    expect(productionService.plans, isEmpty);
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('script-exhibition-script-card-script-regenerated'),
      ),
      findsNothing,
    );
  });

  testWidgets('script exhibition image reruns instead of sending to workbench',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = Directory.systemTemp.createTempSync(
      'nai_exhibition_route_',
    );
    addTearDown(() {
      try {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // Image decoding can briefly hold the file on Windows test runners.
      }
    });
    final imageFile = File('${directory.path}\\frame-01.png');
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
    );
    imageFile.writeAsBytesSync(pngBytes);

    final productionService = _FakeProductionQueueService([
      _exhibitionProductionPlan(outputImagePath: imageFile.path),
    ]);
    final batchViewModel = ProductionQueueViewModel(
      plans: [_productionPlan()],
      queueService: productionService,
    );
    final scriptViewModel = _RecordingScriptViewModel();
    final workbenchViewModel = _RecordingWorkbenchTransferViewModel(
      payloadConfig: GetIt.I<PayloadConfig>(),
    );
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(caches: [_exhibitionRecastCache()]),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(productionService);
    await GetIt.I.unregister<ProductionQueueViewModel>();
    GetIt.I.registerSingleton<ProductionQueueViewModel>(batchViewModel);
    await GetIt.I.unregister<StudioScriptViewModel>();
    GetIt.I.registerSingleton<StudioScriptViewModel>(scriptViewModel);
    await GetIt.I.unregister<WorkbenchTransferViewModel>();
    GetIt.I.registerSingleton<WorkbenchTransferViewModel>(workbenchViewModel);

    final navigationViewModel = NavigationViewModel();
    await tester
        .pumpWidget(_buildNavigationApp(viewModel: navigationViewModel));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-rerun-production-plan-1-task-1',
        ),
      ),
    );
    await tester.pump();

    expect(navigationViewModel.currentPageIndex, isNot(1));
    expect(workbenchViewModel.importedFileNames, isEmpty);
    expect(workbenchViewModel.importedBytes, isEmpty);
    expect(scriptViewModel.importedPaths, isEmpty);
    expect(batchViewModel.selectedTask?.id, startsWith('task-1-rerun'));
    expect(find.text('已加入重跑队列，原图会保留'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('asset library sends to script after loading drawer assets',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loadCount = 0;
    await GetIt.I.unregister<StudioAssetCatalogService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(
      _AssetNavigationCatalogService(),
    );
    await GetIt.I.unregister<StudioScriptViewModel>();
    GetIt.I.registerSingleton<StudioScriptViewModel>(
      StudioScriptViewModel(
        loadCharacters: () async {
          loadCount += 1;
          return const [
            CharacterEntry(
              id: 'library-char',
              name: 'Library Character',
              traits: ViewVariantTexts(frontFull: 'silver hair'),
              outfits: [
                WorkspaceOutfit(
                  id: 'library-outfit',
                  name: 'Library Outfit',
                  tags: ViewVariantTexts(frontFull: 'white jacket'),
                ),
              ],
            ),
          ];
        },
        loadArtistChains: () async => const [],
      ),
    );

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-library-char')),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('asset-detail-add-outfit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('asset-detail-send-script')));
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(
      find.byKey(const ValueKey('script-asset-character-library-char')),
      findsOneWidget,
    );
  });

  testWidgets(
      'asset library send refreshes already loaded script drawer assets',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loadCount = 0;
    final scriptViewModel = StudioScriptViewModel(
      loadCharacters: () async {
        loadCount += 1;
        return const [
          CharacterEntry(
            id: 'library-char',
            name: 'Library Character',
            traits: ViewVariantTexts(frontFull: 'silver hair'),
            outfits: [
              WorkspaceOutfit(
                id: 'library-outfit',
                name: 'Library Outfit',
                tags: ViewVariantTexts(frontFull: 'white jacket'),
              ),
            ],
          ),
        ];
      },
      loadArtistChains: () async => const [],
    );
    await scriptViewModel.ensureAssetsLoaded();
    expect(loadCount, 1);

    await GetIt.I.unregister<StudioAssetCatalogService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(
      _AssetNavigationCatalogService(),
    );
    await GetIt.I.unregister<StudioScriptViewModel>();
    GetIt.I.registerSingleton<StudioScriptViewModel>(scriptViewModel);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-nav-assets')).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-library-char')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-send-script')));
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(
      find.byKey(const ValueKey('script-asset-character-library-char')),
      findsOneWidget,
    );
  });
}

RecastScriptCache _exhibitionRecastCache({
  String scriptId = 'script-1',
  String scriptName = '雨夜档案',
  String rootPath = r'C:\stories\rain',
}) {
  final now = DateTime.utc(2026, 6, 1, 9);
  final sourceRoot = rootPath.replaceAll('/', r'\').replaceFirst(
        RegExp(r'\\+$'),
        '',
      );
  final script = Script(
    id: scriptId,
    name: scriptName,
    rootPath: rootPath,
    frames: [
      ScriptFrame(
        index: 1,
        fileName: '001.json',
        sourcePath: '$sourceRoot\\001.json',
        sourceImagePath: '$sourceRoot\\001.png',
        rawJson: '{"input":"library entrance, rainy night"}',
        parsed: const ParsedFrame(
          baseCaption: 'library entrance, rainy night',
        ),
        detectedSchema: ScriptSchema.baseInline,
        parseStatus: ScriptFrameParseStatus.parsed,
      ),
    ],
    detectedSchema: ScriptSchema.baseInline,
  );
  return RecastScriptCache(
    scriptId: script.id,
    scriptName: script.name,
    sourceRootPath: script.rootPath,
    sourceFingerprint: 'script-1-source',
    sourceContentFingerprint: 'script-1-content',
    updatedAt: now,
    mapping: RecastMapping.defaults(script.id),
    scriptSnapshot: script.toJson(),
  );
}

ProductionPlan _exhibitionProductionPlan({
  String outputImagePath = r'C:\out\frame-01.png',
  String scriptId = 'script-1',
  String scriptName = '雨夜档案',
  String scriptPath = r'C:\stories\rain',
  ProductionTaskStatus status = ProductionTaskStatus.completed,
}) {
  final now = DateTime.utc(2026, 6, 2, 8);
  return ProductionPlan(
    id: 'plan-1',
    name: '主角版 A',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-1',
        title: '入口雨幕',
        scriptId: scriptId,
        scriptName: scriptName,
        scriptPath: scriptPath,
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {
          'input': 'library entrance, generated heroine',
        },
        status: status,
        outputImagePath: outputImagePath,
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _productionPlan({
  ProductionPlanExecutionSettings? executionSettings,
}) {
  final now = DateTime.utc(2026, 5, 26);
  return ProductionPlan(
    id: 'injected-plan',
    name: 'Injected Recast Queue',
    createdAt: now,
    updatedAt: now,
    executionSettings: executionSettings,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'injected-task-1',
        planId: 'injected-plan',
        title: 'Frame 1',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payload: const {
          'input': 'injected frame',
          'parameters': {'seed': 1},
        },
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}
