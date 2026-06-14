import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/global_generation_params.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/studio/services/production_executor_service.dart';
import 'package:nai_casrand/data/studio/services/production_nai_adapter_service.dart';
import 'package:nai_casrand/data/studio/services/production_queue_service.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_client.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:nai_casrand/data/studio/services/asset_tag_cache_prewarm_service.dart';
import 'package:nai_casrand/data/studio/services/prompt_translation_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:nai_casrand/data/studio/services/studio_batch_plan_service.dart';
import 'package:nai_casrand/data/studio/services/prompt_workshop_bridge.dart';
import 'package:nai_casrand/data/studio/services/script_recast_asset_context_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/services/script_recast_production_service.dart';
import 'package:nai_casrand/data/studio/services/tokenizer_script_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/data/studio/services/workspace_vibe_import_service.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/core/app_display_settings.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/navigation/widgets/navigation_view.dart';
import 'package:nai_casrand/ui/navigation/view_models/navigation_view_model.dart';
import 'package:nai_casrand/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_filter_rules.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:get_it/get_it.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (_) => const SizedBox.shrink();
  await EasyLocalization.ensureInitialized();

  GetIt.instance.registerLazySingleton<ConfigService>(() => ConfigService());
  final workspaceService = WorkspaceService();
  final studioDataService = StudioDataService(
    workspaceService: workspaceService,
  );
  await studioDataService.initializeForApp();
  GetIt.instance.registerSingleton<WorkspaceService>(workspaceService);
  GetIt.instance.registerSingleton<StudioDataService>(studioDataService);
  GetIt.instance.registerLazySingleton(
    () => StudioAssetCatalogService(workspaceService: workspaceService),
  );
  GetIt.instance.registerLazySingleton(
    () => StudioAssetCaptureService(workspaceService: workspaceService),
  );
  GetIt.instance.registerLazySingleton(
    () => ScriptRecastAssetContextService(
      catalogService: GetIt.I<StudioAssetCatalogService>(),
    ),
  );
  GetIt.instance.registerLazySingleton(
    () => StudioBatchPlanService(workspaceService: workspaceService),
  );
  final promptWorkshopTranslationCache =
      await PromptWorkshopBridge.loadTranslationCache();
  final promptTagClassificationCache =
      await PromptWorkshopBridge.loadTagClassificationCache();
  GetIt.instance.registerSingleton<TranslationCache>(
    promptWorkshopTranslationCache,
  );
  GetIt.instance.registerSingleton<PromptTagClassificationCache>(
    promptTagClassificationCache,
  );
  GetIt.instance.registerSingleton<PromptTagFilterRulesController>(
    PromptTagFilterRulesController(
      addTags: (tags, target) => appendTagsToFilterRules(
        loadFilterRules: workspaceService.loadFilterRules,
        saveFilterRules: workspaceService.saveFilterRules,
        tags: tags,
        target: target,
      ),
    ),
  );
  GetIt.instance.registerLazySingleton(
    () => TokenizerScriptService(
      workspaceService: workspaceService,
      translationCache: promptWorkshopTranslationCache,
    ),
  );
  GetIt.instance.registerLazySingleton(
    () => StudioGalleryService(workspaceService: workspaceService),
  );
  GetIt.instance.registerLazySingleton(
    () => ProductionQueueService(workspaceService: workspaceService),
  );
  GetIt.instance.registerLazySingleton(
    () => ScriptRecastProductionService(
      queueService: GetIt.I<ProductionQueueService>(),
      now: () => DateTime.now().toUtc(),
    ),
  );
  final configService = GetIt.instance<ConfigService>();
  configService.packageInfo = await PackageInfo.fromPlatform();
  final savedConfig = await configService.loadSavedConfig();
  final payloadConfig = PayloadConfig.fromJson(savedConfig);
  final externalizedV4VibeImages =
      await configService.externalizeV4VibeSourceImages(payloadConfig);
  final normalizedSavedConfig =
      externalizedV4VibeImages ? payloadConfig.toJson() : savedConfig;
  if (externalizedV4VibeImages) {
    await configService.saveConfig(normalizedSavedConfig);
  }
  AppDisplaySettings.setTextScale(payloadConfig.settings.uiTextScale);
  AppDisplaySettings.setImagePreviewDialogHeight(
    payloadConfig.settings.imagePreviewDialogHeight,
    persist: false,
  );
  final batchPayloadConfig = PayloadConfig.fromJson(normalizedSavedConfig);
  AppDisplaySettings.configureImagePreviewDialogHeightPersistence((height) {
    payloadConfig.settings.imagePreviewDialogHeight = height;
    batchPayloadConfig.settings.imagePreviewDialogHeight = height;
    return configService.saveConfig(payloadConfig.toJson());
  });
  final loadedGlobalParams = configService.loadGlobalGenerationParams();
  payloadConfig.globalGenerationParams = loadedGlobalParams ??
      GlobalGenerationParams.fromParamConfig(payloadConfig.paramConfig);
  batchPayloadConfig.globalGenerationParams = loadedGlobalParams == null
      ? GlobalGenerationParams.fromParamConfig(batchPayloadConfig.paramConfig)
      : GlobalGenerationParams.fromJson(loadedGlobalParams.toJson());
  final loadedRuntimeState =
      configService.loadGenerationRuntimeState() ?? GenerationRuntimeState();
  payloadConfig.generationRuntimeState =
      GenerationRuntimeState.fromJson(loadedRuntimeState.toJson())
        ..clearPendingBatchResume();
  batchPayloadConfig.generationRuntimeState =
      GenerationRuntimeState.fromJson(loadedRuntimeState.toJson());
  final workbenchCommandStatus = CommandStatus();
  final batchCommandStatus = CommandStatus();

  GetIt.instance.registerLazySingleton(() => payloadConfig);
  GetIt.instance.registerLazySingleton(
    () => WorkspaceVibeImportService(
      payloadConfig: payloadConfig,
      configService: configService,
    ),
  );
  GetIt.instance.registerLazySingleton<PromptTranslationService>(
    () => DefaultPromptTranslationService(
      translationCache: promptWorkshopTranslationCache,
      settingsProvider: () => payloadConfig.settings,
      translationCacheReloader: PromptWorkshopBridge.loadTranslationCache,
    ),
  );
  GetIt.instance.registerLazySingleton(
    () => AssetTagCachePrewarmService(
      catalogService: GetIt.I<StudioAssetCatalogService>(),
      translationService: GetIt.I<PromptTranslationService>(),
      translationCache: promptWorkshopTranslationCache,
      classificationCache: promptTagClassificationCache,
    ),
  );
  GetIt.instance.registerLazySingleton(() => workbenchCommandStatus);
  GetIt.instance.registerLazySingleton(
    () => StudioWorkbenchAssetService(
      payloadConfig: payloadConfig,
      workspaceService: workspaceService,
    ),
  );
  GetIt.instance.registerLazySingleton(() => WorkbenchTransferService());
  GetIt.instance.registerFactory(
    () => WorkbenchTransferViewModel(
      payloadConfig: GetIt.I<PayloadConfig>(),
      transferService: GetIt.I<WorkbenchTransferService>(),
    ),
  );

  GetIt.instance.registerLazySingleton(
    () => GenerationPageViewmodel(
      payloadConfig: payloadConfig,
      commandStatus: workbenchCommandStatus,
      configService: configService,
      galleryService: GetIt.I<StudioGalleryService>(),
    ),
  );
  GetIt.instance.registerLazySingleton<GenerationPageViewmodel>(
    () => GenerationPageViewmodel(
      payloadConfig: batchPayloadConfig,
      commandStatus: batchCommandStatus,
      configService: configService,
      galleryService: GetIt.I<StudioGalleryService>(),
    ),
    instanceName: 'batch',
  );
  GetIt.instance.registerLazySingleton(
    () => ProductionNaiAdapterService(
      endpoint: _productionEndpoint(payloadConfig),
      proxy: payloadConfig.settings.proxy,
      headers: payloadConfig.getHeaders(),
      outputDirectory: payloadConfig.settings.outputFolderPath,
    ),
  );
  GetIt.instance.registerLazySingleton(
    () {
      final adapter = GetIt.I<ProductionNaiAdapterService>();
      return StudioAssetPreviewGenerationService(
        workspaceService: workspaceService,
        requestImage: adapter.requestImage,
        saveImage: adapter.saveImage,
      );
    },
  );
  GetIt.instance.registerLazySingleton(
    () {
      final adapter = GetIt.I<ProductionNaiAdapterService>();
      return ProductionExecutorService(
        queueService: GetIt.I<ProductionQueueService>(),
        requestImage: adapter.requestImage,
        saveImage: adapter.saveImage,
        savePlanImage: adapter.savePlanImage,
        now: () => DateTime.now().toUtc(),
      );
    },
  );
  GetIt.instance.registerFactory<StudioScriptViewModel>(
    () => StudioScriptViewModel(
      pickScriptDirectory: () => FilePicker.platform.getDirectoryPath(),
      productionService: GetIt.I<ScriptRecastProductionService>(),
      loadAssetContext: GetIt.I<ScriptRecastAssetContextService>().loadContext,
      loadCharacters: workspaceService.loadCharacters,
      loadArtistChains: workspaceService.loadArtistChains,
      loadVibes: () async => _scriptVibesFromPayload(payloadConfig),
      importVibes: GetIt.I<WorkspaceVibeImportService>().pickAndImport,
      loadFilterRules: workspaceService.loadFilterRules,
      saveFilterRules: workspaceService.saveFilterRules,
      loadRecastCaches: workspaceService.loadRecastScriptCaches,
      saveRecastCaches: workspaceService.saveRecastScriptCaches,
      loadRecastCacheByScriptId: workspaceService.loadRecastScriptCache,
      saveRecastCache: workspaceService.saveRecastScriptCache,
      loadRecastKnowledgeBase: workspaceService.loadRecastKnowledgeBase,
      saveRecastKnowledgeBase: workspaceService.saveRecastKnowledgeBase,
      scriptAiRoleExtractionService: DefaultScriptAiRoleExtractionService(
        client: OpenAiCompatibleScriptAiRoleExtractionClient(),
      ),
      scriptAiBaseUrlProvider: () => payloadConfig.settings.scriptAiBaseUrl,
      scriptAiTokenProvider: () => payloadConfig.settings.scriptAiToken,
      scriptAiModelProvider: () => payloadConfig.settings.scriptAiModel,
      scriptAiReasoningEffortProvider: () =>
          payloadConfig.settings.scriptAiReasoningEffort,
      scriptAiProxyProvider: () => payloadConfig.settings.proxy,
      translationCache: promptWorkshopTranslationCache,
      classificationCache: promptTagClassificationCache,
      saveClassificationCache: PromptWorkshopBridge.saveTagClassificationCache,
    ),
  );
  GetIt.instance.registerFactory<ProductionQueueViewModel>(
    () => ProductionQueueViewModel(
      plans: const [],
      queueService: GetIt.I<ProductionQueueService>(),
      executorService: GetIt.I<ProductionExecutorService>(),
      loadRecastKnowledgeBase: workspaceService.loadRecastKnowledgeBase,
      saveRecastKnowledgeBase: workspaceService.saveRecastKnowledgeBase,
      pickOutputDirectory: () => FilePicker.platform.getDirectoryPath(),
      settings: ProductionQueueExecutionSettings(
        model: payloadConfig.paramConfig.model,
        sampler: payloadConfig.paramConfig.sampler,
        steps: payloadConfig.paramConfig.steps,
        scale: payloadConfig.paramConfig.scale,
        width: payloadConfig.paramConfig.sizes.isEmpty
            ? null
            : payloadConfig.paramConfig.sizes.first.width,
        height: payloadConfig.paramConfig.sizes.isEmpty
            ? null
            : payloadConfig.paramConfig.sizes.first.height,
        seed: payloadConfig.paramConfig.randomSeed
            ? -1
            : payloadConfig.paramConfig.seed,
        tokenReference: _tokenReference(payloadConfig),
        requestIntervalSeconds: payloadConfig.settings.batchIntervalSec,
        requestIntervalRandomRangeSeconds: 0,
        retryCount: payloadConfig.settings.retryOn429Enabled ? 2 : 1,
        outputDirectory: payloadConfig.settings.outputFolderPath,
      ),
    ),
  );

  final appWithLocales = EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/l10n',
    child: const MyApp(),
  );

  runApp(appWithLocales);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = GetIt.I<PayloadConfig>();
    final studioTheme = StudioTheme.build();
    return AdaptiveTheme(
      light: studioTheme,
      dark: studioTheme,
      initial: config.settings.theme,
      builder: (theme, darkTheme) => ValueListenableBuilder<double>(
        valueListenable: AppDisplaySettings.textScale,
        builder: (context, textScale, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: _PromptTranslationShortcutScope(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: NavigationView(viewModel: NavigationViewModel()),
        ),
      ),
    );
  }
}

class _TranslateHoveredPromptIntent extends Intent {
  const _TranslateHoveredPromptIntent();
}

class _PromptTranslationShortcutScope extends StatelessWidget {
  final Widget child;

  const _PromptTranslationShortcutScope({required this.child});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(
          LogicalKeyboardKey.keyT,
          control: true,
          shift: true,
        ): _TranslateHoveredPromptIntent(),
      },
      child: Actions(
        actions: {
          _TranslateHoveredPromptIntent:
              CallbackAction<_TranslateHoveredPromptIntent>(
            onInvoke: (_) {
              AppDisplaySettings.translateHoveredPromptCard();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}

String _productionEndpoint(PayloadConfig payloadConfig) {
  return payloadConfig.settings.imageGenerationEndpoint;
}

String _tokenReference(PayloadConfig payloadConfig) {
  final token = payloadConfig.settings.apiKey.trim();
  if (token.isEmpty || token == 'pst-abcd') {
    return 'unset';
  }
  return 'configured';
}

List<WorkspaceVibeReference> _scriptVibesFromPayload(
  PayloadConfig payloadConfig,
) {
  return [
    for (final (index, vibe) in payloadConfig.vibeConfigListV4.indexed)
      if (vibe.vibeB64.trim().isNotEmpty)
        WorkspaceVibeReference(
          id: 'v4-vibe-$index-${_stableVibeId(vibe.fileName)}',
          name: vibe.fileName.trim().isEmpty
              ? 'Vibe ${index + 1}'
              : vibe.fileName,
          vibeB64: vibe.vibeB64,
          referenceStrength: vibe.referenceStrength,
        ),
  ];
}

String _stableVibeId(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'vibe' : slug;
}
