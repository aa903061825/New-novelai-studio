import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/models/script_recast_knowledge.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/data/studio/services/production_executor_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/services/production_queue_service.dart';
import 'package:nai_casrand/data/studio/services/tokenizer_script_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/navigation/view_models/navigation_view_model.dart';
import 'package:nai_casrand/ui/navigation/widgets/navigation_view.dart';
import 'package:nai_casrand/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
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
  Future<Set<String>> loadAssetFavoriteKeys() async => const {};

  @override
  Future<void> setAssetFavorite(String key, bool isFavorite) async {}
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
  Future<void> saveRecords(List<StudioGalleryRecord> records) async {
    this.records = List.unmodifiable(records);
  }

  @override
  Future<void> removeRecord(String id) async {
    records = List.unmodifiable(
      records.where((record) => record.id != id),
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
  _FakeWorkspaceService({List<RecastScriptCache> caches = const []})
      : caches = List.unmodifiable(caches);

  List<RecastScriptCache> caches;

  @override
  Future<List<RecastScriptCache>> loadRecastScriptCaches() async => caches;

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
  int? selectedFrame;

  @override
  Future<void> importScriptPath(String path) async {
    importedPaths.add(path);
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

  testWidgets('batch navigation uses registered deterministic production queue',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildNavigationApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();

    expect(find.text('Injected Recast Queue'), findsOneWidget);
    expect(find.text('Frame 1'), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 20));

    expect(productionService.loadCount, 1);
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('script-send-production')));
    await tester.pumpAndSettle();

    expect(scriptViewModel.sendCount, 1);
    expect(productionService.loadCount, greaterThanOrEqualTo(1));
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
    await tester.idle();

    expect(scriptViewModel.importedPaths, [r'C:\stories\rain']);
    expect(scriptViewModel.selectedFrame, isNull);
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

  testWidgets('script exhibition image sends to single-image workbench',
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

    final scriptViewModel = _RecordingScriptViewModel();
    final workbenchViewModel = _RecordingWorkbenchTransferViewModel(
      payloadConfig: GetIt.I<PayloadConfig>(),
    );
    await GetIt.I.unregister<WorkspaceService>();
    GetIt.I.registerSingleton<WorkspaceService>(
      _FakeWorkspaceService(caches: [_exhibitionRecastCache()]),
    );
    await GetIt.I.unregister<ProductionQueueService>();
    GetIt.I.registerSingleton<ProductionQueueService>(
      _FakeProductionQueueService([
        _exhibitionProductionPlan(outputImagePath: imageFile.path),
      ]),
    );
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
          'script-exhibition-send-workbench-production-plan-1-task-1',
        ),
      ),
    );

    expect(navigationViewModel.currentPageIndex, 1);
    expect(workbenchViewModel.importedFileNames, ['frame-01.png']);
    expect(workbenchViewModel.importedBytes.single, pngBytes);
    expect(scriptViewModel.importedPaths, isEmpty);
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
        status: ProductionTaskStatus.completed,
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
