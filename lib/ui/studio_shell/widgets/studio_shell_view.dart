import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/command_status.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/services/prompt_workshop_bridge.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/services/tokenizer_script_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/generation_page/widgets/generation_page_view.dart';
import 'package:novel_studio/ui/navigation/view_models/navigation_view_model.dart';
import 'package:novel_studio/ui/navigation/widgets/metadata_drop_area.dart';
import 'package:novel_studio/ui/settings_page/widgets/settings_page_view.dart';
import 'package:novel_studio/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_batch/widgets/studio_batch_page.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_asset_focus.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_page_transition.dart';
import 'package:novel_studio/ui/studio_shell/studio_shell_dependencies.dart';
import 'package:novel_studio/ui/studio_shell/models/studio_shell_section.dart';
import 'package:novel_studio/ui/studio_shell/models/studio_startup_open_request.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';
import 'package:novel_studio/ui/studio_shell/widgets/asset_library_page.dart';
import 'package:novel_studio/ui/studio_shell/widgets/script_exhibition_room_page.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_gallery_page.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_home_page.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_tools_page.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:novel_studio/ui/studio_script/widgets/studio_script_page.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

class StudioShellView extends StatefulWidget {
  final NavigationViewModel viewModel;
  final StudioShellDependencies? dependencies;
  final void Function(StudioShellSection section)? debugOnCreatePage;
  final StudioStartupOpenRequest? startupOpenRequest;

  const StudioShellView({
    super.key,
    required this.viewModel,
    this.dependencies,
    this.debugOnCreatePage,
    this.startupOpenRequest,
  });

  @override
  State<StudioShellView> createState() => _StudioShellViewState();
}

class _StudioShellViewState extends State<StudioShellView> {
  StudioShellSection _currentSection = StudioShellSection.home;
  StudioShellSection _pageSection = StudioShellSection.home;
  bool _skipNextBatchInitialLoad = false;
  final Set<StudioShellSection> _mountedSections = {StudioShellSection.home};
  final Map<StudioShellSection, Widget> _stablePageCache = {};
  final List<StudioShellSection> _sectionHistory = [];
  DateTime? _lastBackButtonPressTime;
  StudioScriptAssetFocus? _scriptAssetFocus;
  int _scriptAssetFocusNonce = 0;
  int _scriptExhibitionOpenNonce = 0;
  Timer? _scriptExhibitionProductionRefreshTimer;
  bool _scriptExhibitionProductionRefreshInFlight = false;
  bool _scriptExhibitionProductionRefreshQueued = false;
  late String _scriptExhibitionProductionRevision;
  final ValueNotifier<StudioScriptAssetFocus?> _scriptAssetFocusNotifier =
      ValueNotifier<StudioScriptAssetFocus?>(null);
  late final StudioScriptViewModel _scriptViewModel =
      _scriptViewModelFromGetIt();
  late final ProductionQueueViewModel _productionQueueViewModel =
      _productionQueueViewModelFromGetIt();
  late final ScriptExhibitionRoomViewModel _scriptExhibitionRoomViewModel;

  StudioShellDependencies get _dependencies =>
      widget.dependencies ?? StudioShellDependencies(getIt: GetIt.I);

  @override
  void initState() {
    super.initState();
    _scriptExhibitionRoomViewModel = _scriptExhibitionRoomViewModelFromGetIt();
    _scriptExhibitionProductionRevision =
        _scriptExhibitionProductionRevisionFor(_productionQueueViewModel.plans);
    _productionQueueViewModel.addListener(_handleProductionQueueChanged);
    final request = widget.startupOpenRequest;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openStartupScriptRequest(request));
      });
    }
  }

  @override
  void dispose() {
    _productionQueueViewModel.removeListener(_handleProductionQueueChanged);
    _scriptExhibitionProductionRefreshTimer?.cancel();
    _scriptExhibitionRoomViewModel.dispose();
    _scriptAssetFocusNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StudioShellView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dependencies != widget.dependencies) {
      _stablePageCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        backgroundColor: StudioTokens.surface1,
        body: MetadataDropArea(
          childBuilder: (context) => _buildShell(context),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final page = _buildPageHost();
        if (compact) {
          return Column(
            children: [
              _StudioTopBar(
                currentSection: _currentSection,
                compact: true,
                onBack: _canGoBack ? () => _handleBack(false, null) : null,
              ),
              Expanded(child: page),
              _BottomStudioNavigation(
                currentSection: _currentSection,
                onSelected: _changeSection,
                onPreview: _previewSection,
              ),
            ],
          );
        }

        return Row(
          children: [
            _SideStudioNavigation(
              currentSection: _currentSection,
              onSelected: _changeSection,
              onPreview: _previewSection,
            ),
            Expanded(
              child: Column(
                children: [
                  _StudioTopBar(
                    currentSection: _currentSection,
                    onBack: _canGoBack ? () => _handleBack(false, null) : null,
                  ),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pageForSection(StudioShellSection section) {
    if (!_shouldCachePage(section)) {
      return _createPage(section);
    }
    return _stablePageCache.putIfAbsent(section, () => _createPage(section));
  }

  bool _shouldCachePage(StudioShellSection section) {
    return switch (section) {
      StudioShellSection.assets ||
      StudioShellSection.workbench ||
      StudioShellSection.script ||
      StudioShellSection.scriptExhibition ||
      StudioShellSection.gallery ||
      StudioShellSection.settings =>
        true,
      StudioShellSection.home || StudioShellSection.batch => false,
    };
  }

  Widget _createPage(StudioShellSection section) {
    widget.debugOnCreatePage?.call(section);
    final dependencies = _dependencies;
    return switch (section) {
      StudioShellSection.home => StudioHomePage(
          catalogService: dependencies.catalogService,
          galleryService: dependencies.galleryService,
          workbenchAssetService: dependencies.workbenchAssetService,
          payloadConfig: dependencies.payloadConfig,
          onNavigate: _changeSection,
        ),
      StudioShellSection.assets => _withAssetCapture(
          StudioShellSection.assets,
          AssetLibraryPage(
            catalogService: dependencies.catalogService,
            workbenchAssetService: dependencies.workbenchAssetService,
            previewGenerationService: dependencies.previewGenerationService,
            onSendToScript: _openScriptAsset,
            saveArtistChains: dependencies.workspaceService.saveArtistChains,
            saveCharacters: dependencies.workspaceService.saveCharacters,
            saveRecipes: dependencies.workspaceService.saveRecipes,
            saveTags: dependencies.workspaceService.saveTags,
            savePromptAssetCategories:
                dependencies.workspaceService.savePromptAssetCategories,
            onPromptAssetsChanged: () {
              unawaited(
                _scriptViewModel.ensureAssetsLoaded(forceRefresh: true),
              );
            },
          )),
      StudioShellSection.workbench =>
        GenerationPageView(viewmodel: dependencies.generationPageViewModel),
      StudioShellSection.script => ValueListenableBuilder(
          valueListenable: _scriptAssetFocusNotifier,
          builder: (context, assetFocus, _) => _withAssetCapture(
            StudioShellSection.script,
            StudioScriptPage(
              viewModel: _scriptViewModel,
              assetFocus: assetFocus,
              onSentToProduction: _handleScriptProductionSend,
            ),
          ),
        ),
      StudioShellSection.batch => _buildBatchPage(),
      StudioShellSection.scriptExhibition => _withAssetCapture(
          StudioShellSection.scriptExhibition,
          ScriptExhibitionRoomPage(
            viewModel: _scriptExhibitionRoomViewModel,
            onSendToScriptWorkbench: _openScriptExhibitionFocus,
            onSendToWorkbench: (focus) {
              unawaited(_openScriptExhibitionImageInWorkbench(focus));
            },
            onQuickRerunProductionTask: (focus) {
              unawaited(_quickRerunScriptExhibitionProductionTask(focus));
            },
            onOpenProductionTask: (focus) {
              unawaited(_openScriptExhibitionProductionTask(focus));
            },
          )),
      StudioShellSection.gallery => _withAssetCapture(
          StudioShellSection.gallery,
          StudioGalleryPage(
            viewModel: dependencies.generationPageViewModel,
            galleryService: dependencies.galleryService,
            payloadConfig: dependencies.payloadConfig,
            onRestoredToWorkbench: _openRestoredGalleryRecordInWorkbench,
          )),
      StudioShellSection.settings => SettingsPageView(
          knowledgeAndRulesBuilder: (_) => _buildKnowledgeAndRulesPage(),
        ),
    };
  }

  Widget _buildPageHost() {
    return StudioPageTransition(
      transitionKey: ValueKey('studio-page-${_pageSection.name}'),
      motion: _pageMotionFor(_pageSection),
      keyChild: false,
      child: Stack(
        key: const ValueKey('studio-page-cache-host'),
        fit: StackFit.expand,
        children: [
          for (final destination in _destinations)
            if (_mountedSections.contains(destination.section))
              _StudioPageKeepAlive(
                key: ValueKey('studio-page-cache-${destination.section.name}'),
                child: Offstage(
                  offstage: destination.section != _pageSection,
                  child: TickerMode(
                    enabled: destination.section == _pageSection,
                    child: RepaintBoundary(
                      child: _pageForSection(destination.section),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  void _previewSection(StudioShellSection _) {
    // Hovering across the navigation should stay cheap. Heavy pages are
    // mounted only after selection so hover movement cannot trigger I/O or
    // large offstage widget builds on the interaction path.
  }

  StudioPageMotion _pageMotionFor(StudioShellSection _) {
    return StudioPageMotion.showcase;
  }

  Widget _withAssetCapture(StudioShellSection section, Widget child) {
    return StudioAssetCaptureHost(
      key: ValueKey('asset-capture-host-${section.name}'),
      service: _dependencies.assetCaptureService,
      child: child,
    );
  }

  Widget _buildKnowledgeAndRulesPage() {
    return StudioToolsPage(
      payloadConfig: GetIt.I(),
      loadFilterRuleConfig: _scriptViewModel.loadFilterRuleConfig,
      saveFilterRuleConfig: _scriptViewModel.saveFilterRuleConfig,
      loadRecastKnowledgeBase: _scriptViewModel.loadRecastKnowledgeBase,
      translationCache: _translationCacheFromGetIt(),
      classificationCache: _classificationCacheFromGetIt(),
      saveTranslationCache: _translationCacheSaverFromGetIt(),
      translationService: _translationServiceFromGetIt(),
      loadRecastCaches: _scriptViewModel.loadRecastCaches,
      saveRecastCaches: _scriptViewModel.saveRecastCaches,
      embedded: true,
    );
  }

  Future<void> _handleScriptProductionSend(Future<bool> sendFuture) async {
    _skipNextBatchInitialLoad = true;
    _changeSection(StudioShellSection.batch);
    final sent = await sendFuture;
    if (!sent) {
      return;
    }
    await _productionQueueViewModel.load(
      preferredPlanId: _scriptViewModel.lastProductionPlanId,
    );
  }

  Widget _buildBatchPage() {
    final skipInitialLoad = _skipNextBatchInitialLoad;
    if (skipInitialLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_skipNextBatchInitialLoad) return;
        setState(() {
          _skipNextBatchInitialLoad = false;
        });
      });
    }
    return StudioBatchPage(
      viewModel: _productionQueueViewModel,
      skipInitialLoad: skipInitialLoad,
    );
  }

  StudioScriptViewModel _scriptViewModelFromGetIt() {
    if (GetIt.I.isRegistered<StudioScriptViewModel>()) {
      return GetIt.I<StudioScriptViewModel>();
    }
    return StudioScriptViewModel();
  }

  ProductionQueueViewModel _productionQueueViewModelFromGetIt() {
    if (GetIt.I.isRegistered<ProductionQueueViewModel>()) {
      return GetIt.I<ProductionQueueViewModel>();
    }
    return ProductionQueueViewModel.empty();
  }

  ScriptExhibitionRoomViewModel _scriptExhibitionRoomViewModelFromGetIt() {
    final workspaceService = GetIt.I<WorkspaceService>();
    return ScriptExhibitionRoomViewModel(
      loadScripts: GetIt.I.isRegistered<TokenizerScriptService>()
          ? GetIt.I<TokenizerScriptService>().loadScripts
          : null,
      loadRecastCaches: workspaceService.loadRecastScriptCaches,
      loadRecastScripts: workspaceService.root == null
          ? null
          : workspaceService.loadRecastExhibitionSummaries,
      loadRecastScript: workspaceService.root == null
          ? null
          : workspaceService.loadRecastExhibitionScript,
      recastCacheChanges: workspaceService.root == null
          ? null
          : workspaceService.watchRecastScriptCacheChanges(),
      loadProductionPlans:
          GetIt.I<ProductionQueueService>().loadPlansForScriptExhibition,
      loadGalleryRecords: GetIt.I<StudioGalleryService>().loadRecords,
      saveProductionPlans:
          GetIt.I<ProductionQueueService>().savePlansForScriptExhibition,
      saveGalleryRecords: GetIt.I<StudioGalleryService>().mergeImagePaths,
      defaultGeneratedImageRoot: _defaultGeneratedImageRootForScriptExhibition,
      importScriptFolder: _importScriptExhibitionFolder,
      importScriptImages: _importScriptImagesForExhibitionScript,
      deleteScriptRecord: _deleteScriptExhibitionScript,
      deleteItemRecord: _deleteScriptExhibitionItem,
      deleteItemsRecord: _deleteScriptExhibitionItems,
      renameScriptRecord: _renameScriptExhibitionScript,
      assignScriptCategory: _assignScriptExhibitionScriptCategory,
      assignScriptsCategory: _assignScriptExhibitionScriptsCategory,
      removeScriptCategory: _removeScriptExhibitionScriptCategory,
      loadCustomCategories: workspaceService.root == null
          ? null
          : () => _loadScriptExhibitionUserCategories(workspaceService),
      loadCustomCategoryScriptIds: workspaceService.root == null
          ? null
          : () => _loadScriptExhibitionCategoryAssignments(workspaceService),
      createCategoryRecord: workspaceService.root == null
          ? null
          : _createScriptExhibitionCategory,
      deleteCategoryRecord: _deleteScriptExhibitionCategory,
      renameImageAttachment: _renameScriptImageAttachment,
      renameVersionLabel: _renameScriptExhibitionVersionLabel,
      deleteVersionRecord: _deleteScriptExhibitionVersion,
      deleteVersionsRecord: _deleteScriptExhibitionVersions,
      setCoverItemRecord: _setScriptExhibitionCoverItem,
    );
  }

  Future<String> _defaultGeneratedImageRootForScriptExhibition() async {
    final probePath = await FileService().resolvePictureSavePath(
      '__script_exhibition_root_probe__.png',
      '',
    );
    return File(probePath).parent.path;
  }

  Future<List<ScriptExhibitionUserCategory>>
      _loadScriptExhibitionUserCategories(
    WorkspaceService workspaceService,
  ) async {
    final names = await workspaceService.loadScriptExhibitionCategories();
    return [
      for (final name in names)
        if (name.trim().isNotEmpty) _scriptExhibitionUserCategoryFromName(name),
    ];
  }

  Future<Map<String, List<String>>> _loadScriptExhibitionCategoryAssignments(
    WorkspaceService workspaceService,
  ) async {
    final assignments =
        await workspaceService.loadScriptExhibitionCategoryAssignments();
    return Map.unmodifiable({
      for (final entry in assignments.entries)
        if (entry.key.trim().isNotEmpty)
          'custom:${entry.key.trim()}': List<String>.unmodifiable(entry.value),
    });
  }

  Future<void> _createScriptExhibitionCategory(String categoryName) {
    return GetIt.I<WorkspaceService>().addScriptExhibitionCategory(
      categoryName,
    );
  }

  ScriptExhibitionUserCategory _scriptExhibitionUserCategoryFromName(
    String categoryName,
  ) {
    final normalized = categoryName.trim();
    return ScriptExhibitionUserCategory(
      id: 'custom:$normalized',
      title: normalized,
      description: '手动归入的剧本。',
      tags: const ['自由分类'],
    );
  }

  TranslationCache? _translationCacheFromGetIt() {
    if (GetIt.I.isRegistered<TranslationCache>()) {
      return GetIt.I<TranslationCache>();
    }
    return null;
  }

  PromptTagClassificationCache? _classificationCacheFromGetIt() {
    if (GetIt.I.isRegistered<PromptTagClassificationCache>()) {
      return GetIt.I<PromptTagClassificationCache>();
    }
    return null;
  }

  StudioTranslationCacheSaver? _translationCacheSaverFromGetIt() {
    if (GetIt.I.isRegistered<TranslationCache>()) {
      return PromptWorkshopBridge.saveTranslationCache;
    }
    return null;
  }

  PromptTranslationService? _translationServiceFromGetIt() {
    if (GetIt.I.isRegistered<PromptTranslationService>()) {
      return GetIt.I<PromptTranslationService>();
    }
    return null;
  }

  bool get _canGoBack =>
      _sectionHistory.isNotEmpty || _currentSection != StudioShellSection.home;

  void _changeSection(StudioShellSection section, {bool recordHistory = true}) {
    if (section == _currentSection && section == _pageSection) {
      if (section == StudioShellSection.scriptExhibition) {
        unawaited(_scriptExhibitionRoomViewModel.load());
      }
      return;
    }
    final wasMounted = _mountedSections.contains(section);
    final index = _destinations.indexWhere(
      (destination) => destination.section == section,
    );
    if (index < 0) {
      return;
    }
    if (recordHistory) {
      _sectionHistory.add(_currentSection);
    }
    widget.viewModel.changeIndex(index);
    setState(() {
      _currentSection = section;
      _pageSection = section;
      _mountedSections.add(section);
    });
    if (section == StudioShellSection.scriptExhibition && wasMounted) {
      unawaited(_scriptExhibitionRoomViewModel.load());
    }
  }

  void _openRestoredGalleryRecordInWorkbench() {
    _dependencies.workbenchAssetService.refreshFromPayload();
    _changeSection(StudioShellSection.workbench);
  }

  Future<void> _openScriptAsset(StudioScriptAssetFocus focus) async {
    _scriptAssetFocusNonce += 1;
    final nextFocus = _focusWithNonce(focus, _scriptAssetFocusNonce);
    _setScriptAssetFocus(nextFocus);
    _changeSection(StudioShellSection.script);
    await _scriptViewModel.ensureAssetsLoaded(forceRefresh: true);
    if (!mounted || _scriptAssetFocus?.nonce != nextFocus.nonce) return;
    _scriptAssetFocusNonce += 1;
    _setScriptAssetFocus(_focusWithNonce(focus, _scriptAssetFocusNonce));
  }

  void _setScriptAssetFocus(StudioScriptAssetFocus? focus) {
    _scriptAssetFocus = focus;
    _scriptAssetFocusNotifier.value = focus;
  }

  Future<void> _openScriptExhibitionFocus(
    ScriptExhibitionFocus focus,
  ) async {
    final sourceFolder = focus.sourceFolder.trim();
    if (sourceFolder.isEmpty) {
      return;
    }
    _scriptExhibitionOpenNonce += 1;
    final openNonce = _scriptExhibitionOpenNonce;
    final openFuture = _scriptViewModel.openScriptFromExhibition(
      scriptId: focus.scriptId,
      sourceFolder: sourceFolder,
      frameIndex: focus.frameIndex,
    );
    if (!mounted || openNonce != _scriptExhibitionOpenNonce) return;
    _changeSection(StudioShellSection.script);
    await openFuture;
  }

  Future<void> _openStartupScriptRequest(
    StudioStartupOpenRequest request,
  ) async {
    if (!mounted) {
      return;
    }
    final scriptId = request.scriptId.trim();
    if (scriptId.isEmpty) {
      return;
    }
    final sourceFolder = await _startupSourceFolderFor(request);
    if (!mounted || sourceFolder.isEmpty) {
      return;
    }
    await _openScriptExhibitionFocus(
      ScriptExhibitionFocus(
        scriptId: scriptId,
        scriptTitle: scriptId,
        sourceFolder: sourceFolder,
        frameIndex: request.frameIndex,
      ),
    );
  }

  Future<String> _startupSourceFolderFor(
    StudioStartupOpenRequest request,
  ) async {
    final explicit = request.sourceFolder?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    final scriptId = request.scriptId.trim();
    final workspaceService = _dependencies.workspaceService;
    final cache = await workspaceService.loadRecastScriptCache(scriptId);
    final cacheRoot = cache?.sourceRootPath.trim();
    if (cacheRoot != null && cacheRoot.isNotEmpty) {
      return cacheRoot;
    }

    final exhibitionScript =
        await workspaceService.loadRecastExhibitionScript(scriptId);
    return exhibitionScript?.sourceRootPath.trim() ?? '';
  }

  Future<void> _openScriptExhibitionImageInWorkbench(
    ScriptExhibitionFocus focus,
  ) async {
    final path = _workbenchImportPathForFocus(focus);
    if (path == null) {
      return;
    }
    final transferViewModel = GetIt.I.isRegistered<WorkbenchTransferViewModel>()
        ? GetIt.I<WorkbenchTransferViewModel>()
        : null;
    if (transferViewModel == null) {
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return;
    }
    _changeSection(StudioShellSection.workbench);
    if (!mounted) return;
    await transferViewModel.importFile(
      context,
      file,
    );
  }

  String? _workbenchImportPathForFocus(ScriptExhibitionFocus focus) {
    final imagePath = focus.imagePath?.trim();
    if (imagePath != null && imagePath.isNotEmpty) {
      return imagePath;
    }
    final sourcePath = focus.sourcePath?.trim();
    if (sourcePath != null && sourcePath.isNotEmpty) {
      return sourcePath;
    }
    return null;
  }

  Future<void> _openScriptExhibitionProductionTask(
    ScriptExhibitionFocus focus,
  ) async {
    final planId = focus.productionPlanId?.trim();
    final taskId = focus.taskId?.trim();
    if (planId == null || planId.isEmpty || taskId == null || taskId.isEmpty) {
      return;
    }
    _skipNextBatchInitialLoad = true;
    _changeSection(StudioShellSection.batch);
    await _productionQueueViewModel.loadAndFocusProductionTask(
      planId: planId,
      taskId: taskId,
    );
  }

  Future<void> _quickRerunScriptExhibitionProductionTask(
    ScriptExhibitionFocus focus,
  ) async {
    final planId = focus.productionPlanId?.trim();
    final taskId = focus.taskId?.trim();
    if (planId == null || planId.isEmpty || taskId == null || taskId.isEmpty) {
      _showShellSnackBar('重跑失败：缺少产线任务信息');
      return;
    }
    _showShellSnackBar('正在准备重跑...');
    try {
      final focused =
          await _productionQueueViewModel.loadAndFocusProductionTask(
        planId: planId,
        taskId: taskId,
      );
      if (!mounted) return;
      if (!focused) {
        _showShellSnackBar('重跑失败：找不到原任务');
        return;
      }
      final task = _productionQueueViewModel.selectedTask;
      if (task == null || task.id != taskId) {
        _showShellSnackBar('重跑失败：找不到原任务');
        return;
      }
      final wasExecuting = _productionQueueViewModel.isExecuting;
      final hasOriginalImage = focus.imagePath?.trim().isNotEmpty ?? false;
      if (!hasOriginalImage) {
        if (wasExecuting &&
            (task.status == ProductionTaskStatus.queued ||
                task.status == ProductionTaskStatus.running)) {
          _showShellSnackBar('任务已在生成队列中，当前没有原图');
          await _refreshScriptExhibitionDynamicVersions();
          return;
        }
        if (!wasExecuting) {
          _showShellSnackBar('已开始补跑，当前没有原图');
          await _productionQueueViewModel.rerunTask(task);
          if (!mounted) return;
          await _refreshScriptExhibitionDynamicVersions();
          return;
        }
      }
      final rerunTask = await _productionQueueViewModel.queueRerunTask(task);
      if (!mounted) return;
      if (rerunTask == null) {
        _showShellSnackBar('重跑失败：无法加入队列');
        return;
      }
      _showShellSnackBar(hasOriginalImage ? '已加入重跑队列，原图会保留' : '已加入补跑队列，当前没有原图');
      if (wasExecuting) {
        await _refreshScriptExhibitionDynamicVersions();
        return;
      }
      unawaited(_runScriptExhibitionQueuedRerun());
    } catch (error) {
      if (!mounted) return;
      _showShellSnackBar('重跑失败：$error');
    }
  }

  Future<void> _runScriptExhibitionQueuedRerun() async {
    try {
      await _productionQueueViewModel.start();
      if (!mounted) return;
      await _refreshScriptExhibitionDynamicVersions();
    } catch (error) {
      if (!mounted) return;
      _showShellSnackBar('重跑失败：$error');
    }
  }

  void _showShellSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshScriptExhibitionDynamicVersions() async {
    await _scriptExhibitionRoomViewModel.refreshDynamicVersions(
      reloadProductionPlans: true,
      reloadGalleryRecords: true,
    );
  }

  void _handleProductionQueueChanged() {
    final nextRevision =
        _scriptExhibitionProductionRevisionFor(_productionQueueViewModel.plans);
    if (nextRevision == _scriptExhibitionProductionRevision) {
      return;
    }
    _scriptExhibitionProductionRevision = nextRevision;
    if (!_mountedSections.contains(StudioShellSection.scriptExhibition)) {
      return;
    }
    _scriptExhibitionProductionRefreshTimer?.cancel();
    _scriptExhibitionProductionRefreshTimer =
        Timer(const Duration(milliseconds: 80), () {
      unawaited(_refreshScriptExhibitionDynamicVersionsFromProductionQueue());
    });
  }

  Future<void>
      _refreshScriptExhibitionDynamicVersionsFromProductionQueue() async {
    if (_scriptExhibitionProductionRefreshInFlight) {
      _scriptExhibitionProductionRefreshQueued = true;
      return;
    }
    _scriptExhibitionProductionRefreshInFlight = true;
    try {
      do {
        _scriptExhibitionProductionRefreshQueued = false;
        if (!mounted ||
            !_mountedSections.contains(StudioShellSection.scriptExhibition)) {
          return;
        }
        await _refreshScriptExhibitionDynamicVersions();
      } while (mounted && _scriptExhibitionProductionRefreshQueued);
    } finally {
      _scriptExhibitionProductionRefreshInFlight = false;
    }
  }

  Future<void> _importScriptExhibitionFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) {
      return;
    }
    assert(_folderName(path).isNotEmpty);
    final directory = Directory(path);
    final script = await ScriptRecastParserService().parseDirectory(directory);
    if (script.frames.isEmpty) {
      throw const FormatException('没有找到可导入的剧本 JSON 或图片。');
    }
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _recastCacheFromScript(script),
    );
  }

  Future<void> _importScriptImagesForExhibitionScript(
    ScriptExhibitionScript script,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final paths = result?.files
            .map((file) => file.path?.trim() ?? '')
            .where((path) => path.isNotEmpty)
            .toList(growable: false) ??
        const [];
    if (paths.isEmpty) {
      return;
    }
    final cache = await _findRecastCacheForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
    if (cache == null || snapshot == null) {
      return;
    }
    final updated = _scriptWithLegacyImageAttachments(
      snapshot,
      imagePaths: paths,
    );
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _cacheWithScriptSnapshot(cache, updated),
    );
  }

  Future<void> _renameScriptImageAttachment(
    ScriptExhibitionItem item,
    String label,
  ) async {
    final attachmentId = item.imageAttachmentId?.trim();
    final cache = await _findRecastCacheForExhibition(
      scriptId: item.scriptId,
      title: item.scriptTitle,
      sourceFolder: item.sourceFolder,
    );
    final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
    if (cache == null ||
        snapshot == null ||
        attachmentId == null ||
        attachmentId.isEmpty) {
      return;
    }
    final updated = _scriptWithRenamedLegacyImageAttachment(
      snapshot,
      attachmentId: attachmentId,
      label: label,
    );
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _cacheWithScriptSnapshot(cache, updated),
    );
  }

  Future<void> _renameScriptExhibitionScript(
    ScriptExhibitionScript script,
    String label,
  ) async {
    final cache = await _findRecastCacheForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
    final trimmed = label.trim();
    if (cache == null || snapshot == null || trimmed.isEmpty) {
      return;
    }
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _cacheWithScriptSnapshot(
        cache,
        _scriptWithName(snapshot, trimmed),
        scriptName: trimmed,
      ),
    );
  }

  Future<void> _renameScriptExhibitionVersionLabel(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
    String label,
  ) async {
    final cache = await _findRecastCacheForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
    final trimmed = label.trim();
    if (cache == null ||
        snapshot == null ||
        version.id.trim().isEmpty ||
        trimmed.isEmpty) {
      return;
    }
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _cacheWithScriptSnapshot(
        cache,
        _scriptWithLegacyVersionLabel(
          snapshot,
          versionId: version.id,
          label: trimmed,
        ),
      ),
    );
  }

  Future<void> _setScriptExhibitionCoverItem(
    ScriptExhibitionItem item,
  ) async {
    final cache = await _findRecastCacheForExhibition(
      scriptId: item.scriptId,
      title: item.scriptTitle,
      sourceFolder: item.sourceFolder,
    );
    final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
    if (cache == null || snapshot == null || !item.hasImage) {
      return;
    }
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _cacheWithScriptSnapshot(
        cache,
        _scriptWithLegacyCoverItemId(snapshot, item.id),
      ),
    );
  }

  Future<void> _assignScriptExhibitionScriptCategory(
    ScriptExhibitionScript script,
    String categoryName,
  ) async {
    final cache = await _findRecastCacheForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
    final trimmed = categoryName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final workspaceService = GetIt.I<WorkspaceService>();
    await workspaceService.assignScriptExhibitionCategoryScripts(
      trimmed,
      [script.scriptId],
    );
    if (cache == null || snapshot == null) {
      return;
    }
    await workspaceService.saveRecastScriptCache(
      _cacheWithScriptSnapshot(
        cache,
        _scriptWithLegacyCategory(snapshot, trimmed),
      ),
    );
  }

  Future<void> _assignScriptExhibitionScriptsCategory(
    Iterable<ScriptExhibitionScript> scripts,
    String categoryName,
  ) async {
    final trimmed = categoryName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final uniqueScripts = <String, ScriptExhibitionScript>{};
    for (final script in scripts) {
      uniqueScripts[_exhibitionScriptPersistenceKey(script)] = script;
    }
    if (uniqueScripts.isEmpty) {
      return;
    }

    final workspaceService = GetIt.I<WorkspaceService>();
    await workspaceService.assignScriptExhibitionCategoryScripts(
      trimmed,
      [
        for (final script in uniqueScripts.values)
          if (script.scriptId.trim().isNotEmpty) script.scriptId,
      ],
    );
    final updatedCaches = <String, RecastScriptCache>{};
    List<RecastScriptCache>? fallbackCaches;

    for (final script in uniqueScripts.values) {
      var cache = await _findDirectRecastCacheForExhibition(
        workspaceService: workspaceService,
        scriptId: script.scriptId,
        title: script.title,
        sourceFolder: script.sourceFolder,
      );
      if (cache == null) {
        fallbackCaches ??= await workspaceService.loadRecastScriptCaches();
        cache = _findRecastCacheForExhibitionIn(
          fallbackCaches,
          scriptId: script.scriptId,
          title: script.title,
          sourceFolder: script.sourceFolder,
        );
      }
      if (cache == null) {
        continue;
      }
      final updated = _cacheWithExhibitionCategory(cache, trimmed);
      if (!identical(updated, cache)) {
        updatedCaches[updated.scriptId] = updated;
      }
    }

    await workspaceService.saveRecastScriptCacheUpdates(updatedCaches.values);
  }

  Future<void> _removeScriptExhibitionScriptCategory(
    ScriptExhibitionScript script,
    String categoryName,
  ) async {
    final cache = await _findRecastCacheForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final trimmed = categoryName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final workspaceService = GetIt.I<WorkspaceService>();
    await workspaceService.removeScriptExhibitionCategoryFromScript(
      trimmed,
      script.scriptId,
    );
    if (cache == null) {
      return;
    }
    final updated = _cacheWithoutExhibitionCategory(cache, trimmed);
    if (!identical(updated, cache)) {
      await workspaceService.saveRecastScriptCache(updated);
    }
  }

  Future<void> _deleteScriptExhibitionCategory(String categoryName) async {
    final trimmed = categoryName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final workspaceService = GetIt.I<WorkspaceService>();
    await workspaceService.removeScriptExhibitionCategory(trimmed);
    await workspaceService.removeScriptExhibitionCategoryAssignments(trimmed);
    final caches = await workspaceService.loadRecastScriptCaches();
    var changed = false;
    final nextCaches = [
      for (final cache in caches)
        if (_cacheWithoutExhibitionCategory(cache, trimmed) case final updated
            when !identical(updated, cache))
          () {
            changed = true;
            return updated;
          }()
        else
          cache,
    ];
    if (!changed) {
      return;
    }
    await workspaceService.saveRecastScriptCaches(nextCaches);
  }

  String _folderName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.trim().isNotEmpty);
    return parts.isEmpty ? '导入剧本' : parts.last;
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.trim().isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  RecastScriptCache _recastCacheFromScript(Script script) {
    final now = DateTime.now().toUtc();
    const cacheRestoreService = ScriptRecastCacheRestoreService();
    return RecastScriptCache(
      scriptId: script.id,
      scriptName: script.name,
      sourceRootPath: script.rootPath,
      sourceFingerprint: cacheRestoreService.sourceFingerprint(script),
      sourceContentFingerprint:
          cacheRestoreService.sourceContentFingerprint(script),
      updatedAt: now,
      mapping: RecastMapping.defaults(script.id),
      scriptSnapshot: script.toJson(),
    );
  }

  Future<RecastScriptCache?> _findRecastCacheForExhibition({
    required String scriptId,
    required String title,
    required String sourceFolder,
  }) async {
    final workspaceService = GetIt.I<WorkspaceService>();
    final direct = await _findDirectRecastCacheForExhibition(
      workspaceService: workspaceService,
      scriptId: scriptId,
      title: title,
      sourceFolder: sourceFolder,
    );
    if (direct != null) {
      return direct;
    }
    return _findRecastCacheForExhibitionIn(
      await workspaceService.loadRecastScriptCaches(),
      scriptId: scriptId,
      title: title,
      sourceFolder: sourceFolder,
    );
  }

  Future<RecastScriptCache?> _findDirectRecastCacheForExhibition({
    required WorkspaceService workspaceService,
    required String scriptId,
    required String title,
    required String sourceFolder,
  }) async {
    final normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.isEmpty) {
      return null;
    }
    final cache = await workspaceService.loadRecastScriptCache(
      normalizedScriptId,
    );
    if (cache == null) {
      return null;
    }
    return _recastCacheMatchesExhibitionScript(
      cache,
      scriptId: scriptId,
      title: title,
      sourceFolder: sourceFolder,
    )
        ? cache
        : null;
  }

  RecastScriptCache? _findRecastCacheForExhibitionIn(
    Iterable<RecastScriptCache> caches, {
    required String scriptId,
    required String title,
    required String sourceFolder,
  }) {
    for (final cache in caches) {
      if (_recastCacheMatchesExhibitionScript(
        cache,
        scriptId: scriptId,
        title: title,
        sourceFolder: sourceFolder,
      )) {
        return cache;
      }
    }
    return null;
  }

  String _exhibitionScriptPersistenceKey(ScriptExhibitionScript script) {
    final scriptId = script.scriptId.trim();
    if (scriptId.isNotEmpty) {
      return 'id:$scriptId';
    }
    final sourceFolder = script.sourceFolder.trim();
    if (sourceFolder.isNotEmpty) {
      return 'source:${sourceFolder.toLowerCase()}';
    }
    return 'title:${script.title.trim().toLowerCase()}';
  }

  String _exhibitionItemPersistenceKey(ScriptExhibitionItem item) {
    final scriptId = item.scriptId.trim();
    if (scriptId.isNotEmpty) {
      return 'id:$scriptId';
    }
    final sourceFolder = item.sourceFolder.trim();
    if (sourceFolder.isNotEmpty) {
      return 'source:${sourceFolder.toLowerCase()}';
    }
    return 'title:${item.scriptTitle.trim().toLowerCase()}';
  }

  bool _recastCacheMatchesExhibitionScript(
    RecastScriptCache cache, {
    required String scriptId,
    required String title,
    required String sourceFolder,
  }) {
    if (_sameNonEmpty(cache.scriptId, scriptId) ||
        _sameNonEmpty(cache.sourceRootPath, sourceFolder) ||
        _sameNonEmpty(cache.scriptName, title)) {
      return true;
    }
    final snapshot = _scriptFromRecastCache(cache);
    return snapshot != null &&
        (_sameNonEmpty(snapshot.id, scriptId) ||
            _sameNonEmpty(snapshot.rootPath, sourceFolder) ||
            _sameNonEmpty(snapshot.name, title));
  }

  Script? _scriptFromRecastCache(RecastScriptCache cache) {
    if (cache.scriptSnapshot.isEmpty) {
      return null;
    }
    try {
      return Script.fromJson(cache.scriptSnapshot);
    } catch (_) {
      return null;
    }
  }

  RecastScriptCache _cacheWithScriptSnapshot(
    RecastScriptCache cache,
    Script script, {
    String? scriptName,
  }) {
    final snapshot = script.toJson();
    return cache.copyWith(
      scriptName: scriptName ?? cache.scriptName,
      updatedAt: DateTime.now().toUtc(),
      scriptSnapshot: snapshot,
    );
  }

  RecastScriptCache _cacheWithExhibitionCategory(
    RecastScriptCache cache,
    String categoryName,
  ) {
    final normalized = categoryName.trim();
    if (normalized.isEmpty ||
        cache.exhibitionCategoryNames.any(
          (name) => name.trim().toLowerCase() == normalized.toLowerCase(),
        )) {
      return cache;
    }
    return cache.copyWith(
      updatedAt: DateTime.now().toUtc(),
      exhibitionCategoryNames: List.unmodifiable([
        ...cache.exhibitionCategoryNames.where(
          (name) => name.trim().isNotEmpty,
        ),
        normalized,
      ]),
    );
  }

  RecastScriptCache _cacheWithoutExhibitionCategory(
    RecastScriptCache cache,
    String categoryName,
  ) {
    final normalized = categoryName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return cache;
    }
    final nextTopLevelCategories = cache.exhibitionCategoryNames
        .where((name) => name.trim().toLowerCase() != normalized)
        .toList(growable: false);
    final snapshot = _scriptFromRecastCache(cache);
    final nextSnapshot = snapshot == null
        ? null
        : _scriptWithoutLegacyCategory(snapshot, categoryName);
    final legacyCategories =
        snapshot == null ? const <String>[] : _legacyCategoryNames(snapshot);
    final nextLegacyCategories = nextSnapshot == null
        ? const <String>[]
        : _legacyCategoryNames(nextSnapshot);
    final snapshotChanged = nextSnapshot != null &&
        legacyCategories.length != nextLegacyCategories.length;
    final topLevelChanged =
        nextTopLevelCategories.length != cache.exhibitionCategoryNames.length;
    if (!snapshotChanged && !topLevelChanged) {
      return cache;
    }
    final nextSnapshotJson = nextSnapshot?.toJson() ?? cache.scriptSnapshot;
    return cache.copyWith(
      updatedAt: DateTime.now().toUtc(),
      exhibitionCategoryNames: List.unmodifiable(nextTopLevelCategories),
      scriptSnapshot: nextSnapshotJson,
    );
  }

  Script _scriptWithName(Script script, String name) {
    return Script(
      id: script.id,
      name: name,
      rootPath: script.rootPath,
      frames: script.frames,
      detectedSchema: script.detectedSchema,
      parseWarnings: script.parseWarnings,
      meta: script.meta,
    );
  }

  Script _scriptWithLegacyImageAttachments(
    Script script, {
    required List<String> imagePaths,
  }) {
    final sortedPaths = imagePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList()
      ..sort((left, right) => _fileName(left).compareTo(_fileName(right)));
    if (sortedPaths.isEmpty) {
      return script;
    }

    final now = DateTime.now().toUtc();
    final versionId = _id('script-image-version', now);
    final versionLabel =
        'Imported Image ${_nextImageAttachmentVersionNumber(script)}';
    final attachments = [
      ..._legacyImageAttachments(script),
      for (final (index, path) in sortedPaths.indexed)
        _legacyImageAttachmentFromPath(
          script: script,
          path: path,
          createdAt: now.add(Duration(microseconds: index)),
          index: index,
          versionId: versionId,
          versionLabel: versionLabel,
        ),
    ];
    return _scriptWithLegacyImageAttachmentList(script, attachments);
  }

  TokenizerScriptImageAttachment _legacyImageAttachmentFromPath({
    required Script script,
    required String path,
    required DateTime createdAt,
    required int index,
    required String versionId,
    required String versionLabel,
  }) {
    final frame = index < script.frames.length ? script.frames[index] : null;
    return TokenizerScriptImageAttachment(
      attachmentId: _id('script-image', createdAt),
      imagePath: path,
      label: 'Frame ${index + 1}',
      versionId: versionId,
      versionLabel: versionLabel,
      frameIndex: frame?.index ?? index + 1,
      sourceFileName: frame?.fileName ?? _fileName(path),
      prompt: frame == null ? '' : _promptFromRecastFrame(frame),
      payload: const {},
      createdAt: createdAt,
    );
  }

  Script _scriptWithRenamedLegacyImageAttachment(
    Script script, {
    required String attachmentId,
    required String label,
  }) {
    final normalizedId = attachmentId.trim();
    final normalizedLabel = label.trim();
    if (normalizedId.isEmpty || normalizedLabel.isEmpty) {
      return script;
    }
    return _scriptWithLegacyImageAttachmentList(
      script,
      [
        for (final attachment in _legacyImageAttachments(script))
          attachment.attachmentId == normalizedId
              ? attachment.copyWith(label: normalizedLabel)
              : attachment,
      ],
    );
  }

  Script _scriptWithoutLegacyImageAttachment(
    Script script, {
    required String attachmentId,
  }) {
    final normalizedId = attachmentId.trim();
    if (normalizedId.isEmpty) {
      return script;
    }
    return _scriptWithLegacyImageAttachmentList(
      script,
      _legacyImageAttachments(script)
          .where((attachment) => attachment.attachmentId != normalizedId)
          .toList(growable: false),
    );
  }

  Script _scriptWithoutLegacyImageAttachments(
    Script script, {
    required Set<String> attachmentIds,
  }) {
    if (attachmentIds.isEmpty) {
      return script;
    }
    return _scriptWithLegacyImageAttachmentList(
      script,
      _legacyImageAttachments(script)
          .where(
            (attachment) => !attachmentIds.contains(attachment.attachmentId),
          )
          .toList(growable: false),
    );
  }

  Script _scriptWithLegacyImageAttachmentList(
    Script script,
    List<TokenizerScriptImageAttachment> attachments,
  ) {
    return _scriptWithMetaValue(
      script,
      'legacyImageAttachments',
      [
        for (final attachment in attachments)
          if (attachment.imagePath.trim().isNotEmpty) attachment.toJson(),
      ],
    );
  }

  Script _scriptWithLegacyCategory(
    Script script,
    String categoryName,
  ) {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) {
      return script;
    }
    final categories = <String>[
      ..._legacyCategoryNames(script),
      if (!_legacyCategoryNames(script).any(
        (name) => name.trim().toLowerCase() == normalized.toLowerCase(),
      ))
        normalized,
    ];
    return _scriptWithMetaValue(
      script,
      'legacyCategoryNames',
      categories,
    );
  }

  Script _scriptWithoutLegacyCategory(
    Script script,
    String categoryName,
  ) {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) {
      return script;
    }
    final categories = _legacyCategoryNames(script)
        .where(
          (name) => name.trim().toLowerCase() != normalized.toLowerCase(),
        )
        .toList(growable: false);
    return _scriptWithMetaValue(
      script,
      'legacyCategoryNames',
      categories,
    );
  }

  Script _scriptWithLegacyVersionLabel(
    Script script, {
    required String versionId,
    required String label,
  }) {
    final normalizedId = versionId.trim();
    final normalizedLabel = label.trim();
    if (normalizedId.isEmpty || normalizedLabel.isEmpty) {
      return script;
    }
    return _scriptWithMetaValue(
      script,
      'legacyExhibitionVersionLabels',
      {
        ..._legacyVersionLabels(script),
        normalizedId: normalizedLabel,
      },
    );
  }

  Script _scriptWithLegacyCoverItemId(
    Script script,
    String itemId,
  ) {
    final normalized = itemId.trim();
    if (normalized.isEmpty) {
      return script;
    }
    return _scriptWithMetaValue(
      script,
      'legacyExhibitionCoverItemId',
      normalized,
    );
  }

  Script _scriptWithMetaValue(
    Script script,
    String key,
    dynamic value,
  ) {
    return Script(
      id: script.id,
      name: script.name,
      rootPath: script.rootPath,
      frames: script.frames,
      detectedSchema: script.detectedSchema,
      parseWarnings: script.parseWarnings,
      meta: {
        ...script.meta,
        key: value,
      },
    );
  }

  List<TokenizerScriptImageAttachment> _legacyImageAttachments(Script script) {
    final raw = script.meta['legacyImageAttachments'];
    if (raw is! List) {
      return const [];
    }
    final attachments = <TokenizerScriptImageAttachment>[];
    for (final value in raw) {
      if (value is! Map) {
        continue;
      }
      try {
        attachments.add(
          TokenizerScriptImageAttachment.fromJson(
            value.cast<String, dynamic>(),
          ),
        );
      } catch (_) {
        // Ignore malformed legacy attachment records.
      }
    }
    return attachments;
  }

  int _nextImageAttachmentVersionNumber(Script script) {
    final existingVersionIds = {
      for (final attachment in _legacyImageAttachments(script))
        if (attachment.versionId.trim().isNotEmpty) attachment.versionId.trim(),
    };
    return existingVersionIds.length + 1;
  }

  String _id(String prefix, DateTime time) {
    return '$prefix-${time.microsecondsSinceEpoch}';
  }

  List<String> _legacyCategoryNames(Script script) {
    final raw = script.meta['legacyCategoryNames'];
    if (raw is! List) {
      return const [];
    }
    return [
      for (final value in raw)
        if (value.toString().trim().isNotEmpty) value.toString(),
    ];
  }

  Map<String, String> _legacyVersionLabels(Script script) {
    final raw = script.meta['legacyExhibitionVersionLabels'];
    if (raw is! Map) {
      return const {};
    }
    return {
      for (final entry in raw.entries)
        if (entry.key.toString().trim().isNotEmpty &&
            entry.value.toString().trim().isNotEmpty)
          entry.key.toString(): entry.value.toString(),
    };
  }

  String _promptFromRecastFrame(ScriptFrame frame) {
    final rows = [
      if (frame.parsed.baseCaption.trim().isNotEmpty)
        frame.parsed.baseCaption.trim(),
      for (final caption in frame.parsed.charCaptions)
        if (caption.trim().isNotEmpty) caption.trim(),
    ];
    return rows.join(', ');
  }

  Future<void> _deleteScriptExhibitionScript(
    ScriptExhibitionScript script, {
    bool deleteLocalFiles = false,
  }) async {
    final workspaceService = GetIt.I<WorkspaceService>();
    final productionService = GetIt.I<ProductionQueueService>();
    final galleryService = GetIt.I<StudioGalleryService>();
    final localImagePaths = deleteLocalFiles
        ? _localImagePathsForExhibitionScript(script)
        : const <String>[];

    await Future.wait([
      _deleteTokenizerScriptsForExhibitionScript(script),
      workspaceService.removeRecastScriptCachesMatching(
        scriptId: script.scriptId,
        scriptName: script.title,
        sourceRootPath: script.sourceFolder,
      ),
      () async {
        final productionItems = script.items
            .where(_hasProductionTaskIdentity)
            .toList(growable: false);
        final deletedAt = DateTime.now().toUtc();
        final deletedProductionItems =
            await deleteScriptExhibitionProductionItems(
          items: productionItems,
          loadPlans: productionService.loadPlansReadOnly,
          savePlans: productionService.savePlans,
          loadPlan: productionService.loadPlanReadOnly,
          savePlanChanges: productionService.savePlanChanges,
          updatedAt: deletedAt,
        );
        if (deletedProductionItems) {
          _applyPersistedProductionTaskDeletions(
            productionItems,
            updatedAt: deletedAt,
          );
        }
      }(),
      () async {
        final records = await galleryService.loadRecords();
        final retainedRecords = records
            .where((record) => !_galleryRecordMatchesScript(record, script))
            .toList(growable: false);
        if (retainedRecords.length != records.length) {
          await galleryService.saveRecords(retainedRecords);
        }
      }(),
    ]);
    if (deleteLocalFiles) {
      await _deleteLocalImageFiles(localImagePaths);
    }
  }

  Future<void> _deleteTokenizerScriptsForExhibitionScript(
    ScriptExhibitionScript script,
  ) async {
    if (!GetIt.I.isRegistered<TokenizerScriptService>()) {
      return;
    }
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final tokenizerScripts = await tokenizerService.loadScripts();
    final scriptIds = tokenizerScripts
        .where((tokenizerScript) => _tokenizerScriptMatchesExhibitionScript(
              tokenizerScript,
              script,
            ))
        .map((tokenizerScript) => tokenizerScript.scriptId.trim())
        .where((scriptId) => scriptId.isNotEmpty)
        .toSet();
    await tokenizerService.removeScripts(scriptIds);
  }

  Future<void> _deleteScriptExhibitionItem(
    ScriptExhibitionItem item, {
    bool deleteLocalFiles = false,
  }) async {
    final localImagePaths = deleteLocalFiles
        ? _localImagePathsForExhibitionItems([item])
        : const <String>[];
    final attachmentId = item.imageAttachmentId?.trim();
    if (attachmentId != null && attachmentId.isNotEmpty) {
      final cache = await _findRecastCacheForExhibition(
        scriptId: item.scriptId,
        title: item.scriptTitle,
        sourceFolder: item.sourceFolder,
      );
      final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
      if (cache == null || snapshot == null) {
        return;
      }
      final updated = _scriptWithoutLegacyImageAttachment(
        snapshot,
        attachmentId: attachmentId,
      );
      await GetIt.I<WorkspaceService>().saveRecastScriptCache(
        _cacheWithScriptSnapshot(cache, updated),
      );
      if (deleteLocalFiles) {
        await _deleteLocalImageFiles(localImagePaths);
      }
      return;
    }

    final galleryService = GetIt.I<StudioGalleryService>();
    final galleryRecordId = item.galleryRecordId?.trim();
    if (galleryRecordId != null && galleryRecordId.isNotEmpty) {
      await galleryService.removeRecord(galleryRecordId);
      if (deleteLocalFiles) {
        await _deleteLocalImageFiles(localImagePaths);
      }
      return;
    }

    if (!_hasProductionTaskIdentity(item)) {
      return;
    }

    final deletedAt = DateTime.now().toUtc();
    final deletedProductionItems = await deleteScriptExhibitionProductionItems(
      items: [item],
      loadPlans: GetIt.I<ProductionQueueService>().loadPlansReadOnly,
      savePlans: GetIt.I<ProductionQueueService>().savePlans,
      loadPlan: GetIt.I<ProductionQueueService>().loadPlanReadOnly,
      savePlanChanges: GetIt.I<ProductionQueueService>().savePlanChanges,
      updatedAt: deletedAt,
    );
    if (deletedProductionItems) {
      _applyPersistedProductionTaskDeletions(
        [item],
        updatedAt: deletedAt,
      );
    }
    if (deleteLocalFiles) {
      await _deleteLocalImageFiles(localImagePaths);
    }
  }

  Future<void> _deleteScriptExhibitionItems(
    List<ScriptExhibitionItem> items, {
    bool deleteLocalFiles = false,
  }) async {
    final uniqueItems = <String, ScriptExhibitionItem>{
      for (final item in items)
        if (item.canDelete) item.id: item,
    }.values.toList(growable: false);
    if (uniqueItems.isEmpty) return;

    final localImagePaths = deleteLocalFiles
        ? _localImagePathsForExhibitionItems(uniqueItems)
        : const <String>[];
    final attachmentItems = <ScriptExhibitionItem>[];
    final productionItems = <ScriptExhibitionItem>[];
    final galleryRecordIds = <String>{};
    for (final item in uniqueItems) {
      final attachmentId = item.imageAttachmentId?.trim();
      if (attachmentId != null && attachmentId.isNotEmpty) {
        attachmentItems.add(item);
        continue;
      }
      final galleryRecordId = item.galleryRecordId?.trim();
      if (galleryRecordId != null && galleryRecordId.isNotEmpty) {
        galleryRecordIds.add(galleryRecordId);
      }
      final linkedGalleryRecordId = item.galleryRecord?.id.trim();
      if (linkedGalleryRecordId != null && linkedGalleryRecordId.isNotEmpty) {
        galleryRecordIds.add(linkedGalleryRecordId);
      }
      if (_hasProductionTaskIdentity(item)) {
        productionItems.add(item);
      }
    }

    final attachmentDeletion =
        _deleteScriptExhibitionImageAttachments(attachmentItems);
    final galleryDeletion = () async {
      if (galleryRecordIds.isEmpty) return;
      final galleryService = GetIt.I<StudioGalleryService>();
      final records = await galleryService.loadRecords();
      final retainedRecords = records
          .where((record) => !galleryRecordIds.contains(record.id))
          .toList(growable: false);
      if (retainedRecords.length != records.length) {
        await galleryService.saveRecords(retainedRecords);
      }
    }();
    final deletedAt = DateTime.now().toUtc();
    final productionDeletion = deleteScriptExhibitionProductionItems(
      items: productionItems,
      loadPlans: GetIt.I<ProductionQueueService>().loadPlansReadOnly,
      savePlans: GetIt.I<ProductionQueueService>().savePlans,
      loadPlan: GetIt.I<ProductionQueueService>().loadPlanReadOnly,
      savePlanChanges: GetIt.I<ProductionQueueService>().savePlanChanges,
      updatedAt: deletedAt,
    );
    await Future.wait<void>([
      attachmentDeletion,
      galleryDeletion,
      productionDeletion.then<void>((_) {}),
    ]);
    final deletedProductionItems = await productionDeletion;
    if (deletedProductionItems) {
      _applyPersistedProductionTaskDeletions(
        productionItems,
        updatedAt: deletedAt,
      );
    }
    if (deleteLocalFiles) {
      await _deleteLocalImageFiles(localImagePaths);
    }
  }

  Future<void> _deleteScriptExhibitionImageAttachments(
    List<ScriptExhibitionItem> items,
  ) async {
    if (items.isEmpty) return;
    final itemsByScript = <String, List<ScriptExhibitionItem>>{};
    for (final item in items) {
      itemsByScript
          .putIfAbsent(_exhibitionItemPersistenceKey(item), () => [])
          .add(item);
    }
    final updatedCaches = <String, RecastScriptCache>{};
    for (final scriptItems in itemsByScript.values) {
      final firstItem = scriptItems.first;
      final cache = await _findRecastCacheForExhibition(
        scriptId: firstItem.scriptId,
        title: firstItem.scriptTitle,
        sourceFolder: firstItem.sourceFolder,
      );
      final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
      if (cache == null || snapshot == null) {
        continue;
      }
      final attachmentIds = <String>{};
      for (final item in scriptItems) {
        final attachmentId = item.imageAttachmentId?.trim();
        if (attachmentId != null && attachmentId.isNotEmpty) {
          attachmentIds.add(attachmentId);
        }
      }
      if (attachmentIds.isEmpty) {
        continue;
      }
      updatedCaches[cache.scriptId] = _cacheWithScriptSnapshot(
        cache,
        _scriptWithoutLegacyImageAttachments(
          snapshot,
          attachmentIds: attachmentIds,
        ),
      );
    }
    await GetIt.I<WorkspaceService>()
        .saveRecastScriptCacheUpdates(updatedCaches.values);
  }

  void _applyPersistedProductionTaskDeletions(
    Iterable<ScriptExhibitionItem> items, {
    required DateTime updatedAt,
  }) {
    final taskIdsByPlanId = <String, Set<String>>{};
    for (final item in items) {
      final planId = item.productionPlanId?.trim();
      final taskId = item.taskId?.trim();
      if (planId == null ||
          planId.isEmpty ||
          taskId == null ||
          taskId.isEmpty) {
        continue;
      }
      taskIdsByPlanId.putIfAbsent(planId, () => <String>{}).add(taskId);
    }
    _productionQueueViewModel.applyPersistedTaskDeletions(
      taskIdsByPlanId: taskIdsByPlanId,
      updatedAt: updatedAt,
    );
  }

  Future<void> _deleteScriptExhibitionVersion(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version, {
    bool deleteLocalFiles = false,
  }) async {
    await _deleteScriptExhibitionVersions(
      script,
      [version],
      deleteLocalFiles: deleteLocalFiles,
    );
  }

  Future<void> _deleteScriptExhibitionVersions(
    ScriptExhibitionScript _,
    List<ScriptExhibitionVersion> versions, {
    bool deleteLocalFiles = false,
  }) async {
    final items = <ScriptExhibitionItem>[];
    for (final version in versions) {
      if (version.id == ScriptExhibitionVersion.originalId) {
        continue;
      }
      items.addAll(version.items.where((item) => item.canDelete));
    }
    await _deleteScriptExhibitionItems(
      items,
      deleteLocalFiles: deleteLocalFiles,
    );
  }

  bool _galleryRecordMatchesScript(
    StudioGalleryRecord record,
    ScriptExhibitionScript script,
  ) {
    final provenance = record.provenance;
    if (provenance == null) return false;
    return _matchesExhibitionScriptIdentity(
      script,
      scriptId: provenance.scriptId,
      sourceFolder: provenance.scriptPath,
      title: provenance.scriptName,
    );
  }

  bool _tokenizerScriptMatchesExhibitionScript(
    TokenizerScript tokenizerScript,
    ScriptExhibitionScript script,
  ) {
    return _matchesExhibitionScriptIdentity(
      script,
      scriptId: tokenizerScript.scriptId,
      sourceFolder: tokenizerScript.sourceFolder,
      title: tokenizerScript.name,
    );
  }

  bool _matchesExhibitionScriptIdentity(
    ScriptExhibitionScript target, {
    required String? scriptId,
    required String? sourceFolder,
    required String? title,
  }) {
    return _sameNonEmpty(scriptId, target.scriptId) ||
        _sameNonEmpty(sourceFolder, target.sourceFolder) ||
        _sameNonEmpty(title, target.title);
  }

  List<String> _localImagePathsForExhibitionScript(
    ScriptExhibitionScript script,
  ) {
    return _localImagePathsForExhibitionItems(
      script.items.where(
        (item) => item.sourceKind != ScriptExhibitionItemSourceKind.original,
      ),
    );
  }

  List<String> _localImagePathsForExhibitionItems(
    Iterable<ScriptExhibitionItem> items,
  ) {
    return scriptExhibitionLocalImagePathsForItems(items);
  }

  Future<void> _deleteLocalImageFiles(List<String> paths) async {
    await deleteScriptExhibitionLocalImageFiles(paths);
  }

  bool _sameNonEmpty(String? left, String? right) {
    final normalizedLeft = _normalizedComparisonText(left);
    final normalizedRight = _normalizedComparisonText(right);
    return normalizedLeft != null &&
        normalizedRight != null &&
        normalizedLeft == normalizedRight;
  }

  String? _normalizedComparisonText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();
  }

  StudioScriptAssetFocus _focusWithNonce(
    StudioScriptAssetFocus focus,
    int nonce,
  ) {
    return switch (focus.kind) {
      StudioScriptAssetFocusKind.character => StudioScriptAssetFocus.character(
          characterId: focus.characterId,
          nonce: nonce,
        ),
      StudioScriptAssetFocusKind.outfit => StudioScriptAssetFocus.outfit(
          characterId: focus.characterId,
          outfitId: focus.outfitId,
          nonce: nonce,
        ),
      StudioScriptAssetFocusKind.artistChain =>
        StudioScriptAssetFocus.artistChain(
          artistChainId: focus.artistChainId,
          nonce: nonce,
        ),
    };
  }

  void _handleBack(bool didPop, Object? result) {
    if (_currentSection == StudioShellSection.scriptExhibition &&
        _scriptExhibitionRoomViewModel.selectedScriptId != null) {
      _scriptExhibitionRoomViewModel.clearScriptSelection();
      return;
    }
    if (_sectionHistory.isNotEmpty) {
      _changeSection(_sectionHistory.removeLast(), recordHistory: false);
      return;
    }
    if (_currentSection != StudioShellSection.home) {
      _changeSection(StudioShellSection.home);
      return;
    }

    final now = DateTime.now();
    final timeDiff = _lastBackButtonPressTime == null
        ? null
        : now.difference(_lastBackButtonPressTime!);
    if (timeDiff == null || timeDiff > const Duration(seconds: 2)) {
      _lastBackButtonPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('press_again_to_exit'))),
      );
      return;
    }
    SystemNavigator.pop();
  }
}

String _scriptExhibitionProductionRevisionFor(List<ProductionPlan> plans) {
  final buffer = StringBuffer();
  for (final plan in plans) {
    var wrotePlan = false;
    for (final task in plan.tasks) {
      if (task.taskType != ProductionTaskType.scriptRecastFrame) {
        continue;
      }
      if (!wrotePlan) {
        buffer
          ..write('plan:')
          ..write(plan.id)
          ..write('|');
        wrotePlan = true;
      }
      buffer
        ..write(task.id)
        ..write(':')
        ..write(task.status.name)
        ..write(':')
        ..write(task.outputImagePath ?? '')
        ..write(';');
    }
  }
  return buffer.toString();
}

@visibleForTesting
List<String> scriptExhibitionLocalImagePathsForItems(
  Iterable<ScriptExhibitionItem> items,
) {
  final paths = <String>{};
  for (final item in items) {
    _addScriptExhibitionLocalImagePath(paths, item.imagePath);
    _addScriptExhibitionLocalImagePath(paths, item.galleryRecord?.imagePath);
    _addScriptExhibitionLocalImagePath(
      paths,
      item.galleryRecord?.provenance?.outputImagePath,
    );
  }
  return paths.toList(growable: false);
}

void _addScriptExhibitionLocalImagePath(Set<String> paths, String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) return;
  if (trimmed.contains('://')) return;
  paths.add(trimmed);
}

@visibleForTesting
Future<void> deleteScriptExhibitionLocalImageFiles(
  Iterable<String> paths,
) async {
  final uniquePaths = paths
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toSet()
      .toList(growable: false);
  const batchSize = 12;
  for (var start = 0; start < uniquePaths.length; start += batchSize) {
    final end = math.min(start + batchSize, uniquePaths.length);
    await Future.wait([
      for (final path in uniquePaths.sublist(start, end))
        () async {
          try {
            final type = await FileSystemEntity.type(path, followLinks: false);
            if (type == FileSystemEntityType.file) {
              await File(path).delete();
            }
          } on FileSystemException {
            // Best effort: stale or locked images should not restore deleted
            // exhibition metadata.
          }
        }(),
    ]);
  }
}

@visibleForTesting
Future<bool> deleteScriptExhibitionProductionItems({
  required Iterable<ScriptExhibitionItem> items,
  required Future<List<ProductionPlan>> Function() loadPlans,
  required Future<void> Function(List<ProductionPlan>) savePlans,
  Future<ProductionPlan?> Function(String planId)? loadPlan,
  Future<void> Function({
    required List<ProductionPlan> updatedPlans,
    required Set<String> deletedPlanIds,
  })? savePlanChanges,
  required DateTime updatedAt,
}) async {
  final itemsByPlanId = <String, Map<String, ScriptExhibitionItem>>{};
  for (final item in items) {
    final planId = item.productionPlanId?.trim();
    final taskId = item.taskId?.trim();
    if (planId == null || planId.isEmpty || taskId == null || taskId.isEmpty) {
      continue;
    }
    itemsByPlanId.putIfAbsent(planId, () => {})[taskId] = item;
  }
  if (itemsByPlanId.isEmpty) {
    return false;
  }

  final useTargetedPlanIo = loadPlan != null && savePlanChanges != null;
  final plans = useTargetedPlanIo
      ? (await Future.wait([
          for (final planId in itemsByPlanId.keys) loadPlan(planId),
        ]))
          .whereType<ProductionPlan>()
          .toList(growable: false)
      : await loadPlans();
  var changed = false;
  final nextPlans = <ProductionPlan>[];
  final updatedPlans = <ProductionPlan>[];
  final deletedPlanIds = <String>{};
  for (final plan in plans) {
    final itemsByTaskId = itemsByPlanId[plan.id];
    if (itemsByTaskId == null || itemsByTaskId.isEmpty) {
      nextPlans.add(plan);
      continue;
    }
    final nextTasks = <ProductionTask>[];
    var planChanged = false;
    for (final task in plan.tasks) {
      final targetItem = itemsByTaskId[task.id];
      if (targetItem == null) {
        nextTasks.add(task);
        continue;
      }
      planChanged = true;
    }
    if (!planChanged) {
      nextPlans.add(plan);
      continue;
    }
    changed = true;
    if (nextTasks.isEmpty) {
      deletedPlanIds.add(plan.id);
      continue;
    }
    final updatedPlan = plan.copyWith(tasks: nextTasks, updatedAt: updatedAt);
    nextPlans.add(updatedPlan);
    updatedPlans.add(updatedPlan);
  }
  if (!changed) {
    return false;
  }
  if (useTargetedPlanIo) {
    await savePlanChanges(
      updatedPlans: updatedPlans,
      deletedPlanIds: deletedPlanIds,
    );
  } else {
    await savePlans(nextPlans);
  }
  return true;
}

bool _hasProductionTaskIdentity(ScriptExhibitionItem item) {
  final planId = item.productionPlanId?.trim();
  final taskId = item.taskId?.trim();
  return planId != null &&
      planId.isNotEmpty &&
      taskId != null &&
      taskId.isNotEmpty;
}

class _StudioTopBar extends StatelessWidget {
  final StudioShellSection currentSection;
  final bool compact;
  final VoidCallback? onBack;

  const _StudioTopBar({
    required this.currentSection,
    this.compact = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final destination = _destinations.firstWhere(
      (item) => item.section == currentSection,
    );
    final packageInfo = GetIt.I<ConfigService>().packageInfo;
    final commandStatus = GetIt.I<CommandStatus>();

    return Container(
      height: compact ? 58 : 64,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22),
      decoration: const BoxDecoration(
        color: StudioTokens.surface1,
        border: Border(
          bottom: BorderSide(color: StudioTokens.border),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              key: const ValueKey('studio-back-button'),
              tooltip: '返回上一步',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
          ],
          Image.asset(
            'assets/appicon.png',
            width: 30,
            height: 30,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!compact)
                  Text(
                    'Novel Studio ${packageInfo.version}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([
              commandStatus.isBatchActive,
              commandStatus.isCoolingDown,
            ]),
            builder: (context, _) {
              final label = commandStatus.isCoolingDown.value
                  ? '冷却中'
                  : commandStatus.isBatchActive.value
                      ? '生成中'
                      : '待机';
              final color = commandStatus.isCoolingDown.value
                  ? StudioTokens.warning
                  : commandStatus.isBatchActive.value
                      ? StudioTokens.active
                      : StudioTokens.textMuted;
              return StudioChip(
                label: label,
                icon: Icons.circle,
                selected: commandStatus.isBatchActive.value ||
                    commandStatus.isCoolingDown.value,
                accentColor: color,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SideStudioNavigation extends StatelessWidget {
  final StudioShellSection currentSection;
  final ValueChanged<StudioShellSection> onSelected;
  final ValueChanged<StudioShellSection> onPreview;

  const _SideStudioNavigation({
    required this.currentSection,
    required this.onSelected,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedDestinationIndex(currentSection);
    const itemExtent = _studioSideNavItemHeight + _studioSideNavItemGap;
    final navHeight = itemExtent * _destinations.length;

    return Container(
      width: StudioTokens.sidebarWidth,
      decoration: const BoxDecoration(
        color: StudioTokens.surfaceBase,
        border: Border(
          right: BorderSide(color: StudioTokens.border),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StudioBrandBlock(),
              const SizedBox(height: 18),
              SizedBox(
                height: navHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedPositioned(
                      key: const ValueKey(
                        'studio-side-nav-selection-indicator',
                      ),
                      duration: StudioMotionScope.duration(
                        context,
                        StudioMotionTokens.expressive,
                      ),
                      curve: StudioMotionTokens.expressiveCurve,
                      left: 0,
                      right: 0,
                      top: selectedIndex * itemExtent,
                      height: _studioSideNavItemHeight,
                      child: _StudioNavSelectionIndicator(
                        axis: Axis.vertical,
                        pulseKey: currentSection.name,
                        pulseWidgetKey: const ValueKey(
                          'studio-side-nav-selection-liquid-pulse',
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final destination in _destinations)
                          _SideStudioNavigationItem(
                            destination: destination,
                            selected: destination.section == currentSection,
                            onTap: () => onSelected(destination.section),
                            onPreview: () => onPreview(destination.section),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const _LocalOnlyNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioBrandBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: StudioTokens.primary,
              borderRadius: StudioTokens.radiusPill,
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: StudioTokens.onPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Novel Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideStudioNavigationItem extends StatelessWidget {
  final _StudioDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  const _SideStudioNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('studio-nav-${destination.section.name}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => onPreview(),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1 : 0),
          duration: StudioMotionScope.duration(
            context,
            StudioMotionTokens.showcase,
          ),
          curve: StudioMotionTokens.showcaseCurve,
          builder: (context, selection, _) {
            final foreground = _navForeground(selection);
            return SizedBox(
              height: _studioSideNavItemHeight,
              child: Material(
                color: Colors.transparent,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(destination.icon, color: foreground, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: foreground,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BottomStudioNavigation extends StatelessWidget {
  final StudioShellSection currentSection;
  final ValueChanged<StudioShellSection> onSelected;
  final ValueChanged<StudioShellSection> onPreview;

  const _BottomStudioNavigation({
    required this.currentSection,
    required this.onSelected,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedDestinationIndex(currentSection);

    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: StudioTokens.surfaceBase,
        border: Border(
          top: BorderSide(color: StudioTokens.border),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / _destinations.length;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                key: const ValueKey('studio-bottom-nav-selection-indicator'),
                duration: StudioMotionScope.duration(
                  context,
                  StudioMotionTokens.expressive,
                ),
                curve: StudioMotionTokens.expressiveCurve,
                left: itemWidth * selectedIndex,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: _StudioNavSelectionIndicator(
                  axis: Axis.horizontal,
                  pulseKey: currentSection.name,
                  pulseWidgetKey: const ValueKey(
                    'studio-bottom-nav-selection-liquid-pulse',
                  ),
                ),
              ),
              Row(
                children: [
                  for (final destination in _destinations)
                    Expanded(
                      child: _BottomStudioNavigationItem(
                        destination: destination,
                        selected: destination.section == currentSection,
                        onTap: () => onSelected(destination.section),
                        onPreview: () => onPreview(destination.section),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BottomStudioNavigationItem extends StatelessWidget {
  final _StudioDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  const _BottomStudioNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      key: ValueKey('studio-nav-${destination.section.name}'),
      onEnter: (_) => onPreview(),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: selected ? 1 : 0),
        duration: StudioMotionScope.duration(
          context,
          StudioMotionTokens.showcase,
        ),
        curve: StudioMotionTokens.showcaseCurve,
        builder: (context, selection, _) {
          final foreground = _navForeground(selection);
          return Material(
            color: Colors.transparent,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(destination.icon, color: foreground, size: 20),
                    const SizedBox(height: 4),
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: foreground,
                            fontSize: 10,
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
}

const _studioSideNavItemHeight = 44.0;
const _studioSideNavItemGap = 8.0;

Color _navForeground(double selection) {
  return Color.lerp(
    StudioTokens.textSecondary,
    StudioTokens.onPrimary,
    selection,
  )!;
}

int _selectedDestinationIndex(StudioShellSection section) {
  final index = _destinations.indexWhere(
    (destination) => destination.section == section,
  );
  return index < 0 ? 0 : index;
}

class _StudioNavSelectionIndicator extends StatelessWidget {
  final Axis axis;
  final String pulseKey;
  final Key pulseWidgetKey;

  const _StudioNavSelectionIndicator({
    required this.axis,
    required this.pulseKey,
    required this.pulseWidgetKey,
  });

  @override
  Widget build(BuildContext context) {
    if (StudioMotionScope.animationsDisabled(context)) {
      return KeyedSubtree(
        key: pulseWidgetKey,
        child: const _StudioNavSelectionFill(),
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey('studio-selection-pulse-${axis.name}-$pulseKey'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: StudioMotionScope.duration(
        context,
        StudioMotionTokens.expressive,
      ),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) {
        final wave = math.sin(progress.clamp(0, 1) * math.pi);
        final stretch = 1 + wave * 0.18;
        final counterStretch = 1 - wave * 0.035;
        return Transform.scale(
          key: pulseWidgetKey,
          alignment: Alignment.center,
          scaleX: axis == Axis.horizontal ? stretch : counterStretch,
          scaleY: axis == Axis.vertical ? stretch : counterStretch,
          child: child,
        );
      },
      child: const _StudioNavSelectionFill(),
    );
  }
}

class _StudioNavSelectionFill extends StatelessWidget {
  const _StudioNavSelectionFill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            StudioTokens.primary,
            StudioTokens.primary.withValues(alpha: 0.86),
          ],
          stops: const [0, 0.42, 1],
        ),
        borderRadius: StudioTokens.radiusPill,
        boxShadow: [
          BoxShadow(
            color: StudioTokens.primary.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
    );
  }
}

class _StudioPageKeepAlive extends StatefulWidget {
  final Widget child;

  const _StudioPageKeepAlive({
    super.key,
    required this.child,
  });

  @override
  State<_StudioPageKeepAlive> createState() => _StudioPageKeepAliveState();
}

class _StudioPageKeepAliveState extends State<_StudioPageKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _LocalOnlyNote extends StatelessWidget {
  const _LocalOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      '个人本地创作工具',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _StudioDestination {
  final StudioShellSection section;
  final IconData icon;
  final String label;

  const _StudioDestination({
    required this.section,
    required this.icon,
    required this.label,
  });
}

const _destinations = [
  _StudioDestination(
    section: StudioShellSection.home,
    icon: Icons.home_outlined,
    label: '主页',
  ),
  _StudioDestination(
    section: StudioShellSection.workbench,
    icon: Icons.dashboard_customize_outlined,
    label: '工作台',
  ),
  _StudioDestination(
    section: StudioShellSection.assets,
    icon: Icons.inventory_2_outlined,
    label: '素材库',
  ),
  _StudioDestination(
    section: StudioShellSection.script,
    icon: Icons.document_scanner_outlined,
    label: '剧本工作台',
  ),
  _StudioDestination(
    section: StudioShellSection.batch,
    icon: Icons.account_tree_outlined,
    label: '批量产线',
  ),
  _StudioDestination(
    section: StudioShellSection.scriptExhibition,
    icon: Icons.auto_stories_outlined,
    label: '剧本展览室',
  ),
  _StudioDestination(
    section: StudioShellSection.gallery,
    icon: Icons.photo_library_outlined,
    label: '画廊',
  ),
  _StudioDestination(
    section: StudioShellSection.settings,
    icon: Icons.tune,
    label: '设置',
  ),
];
