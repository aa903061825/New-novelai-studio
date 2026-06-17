import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/command_status.dart';
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
import 'package:novel_studio/ui/studio_shell/studio_shell_dependencies.dart';
import 'package:novel_studio/ui/studio_shell/models/studio_shell_section.dart';
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

  const StudioShellView({
    super.key,
    required this.viewModel,
    this.dependencies,
  });

  @override
  State<StudioShellView> createState() => _StudioShellViewState();
}

class _StudioShellViewState extends State<StudioShellView> {
  StudioShellSection _currentSection = StudioShellSection.home;
  DateTime? _lastBackButtonPressTime;
  StudioScriptAssetFocus? _scriptAssetFocus;
  int _scriptAssetFocusNonce = 0;
  late final StudioScriptViewModel _scriptViewModel =
      _scriptViewModelFromGetIt();
  late final ProductionQueueViewModel _productionQueueViewModel =
      _productionQueueViewModelFromGetIt();
  late final ScriptExhibitionRoomViewModel _scriptExhibitionRoomViewModel =
      _scriptExhibitionRoomViewModelFromGetIt();

  StudioShellDependencies get _dependencies =>
      widget.dependencies ?? StudioShellDependencies(getIt: GetIt.I);

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
        final page = _buildCurrentPage();
        if (compact) {
          return Column(
            children: [
              _StudioTopBar(
                currentSection: _currentSection,
                compact: true,
              ),
              Expanded(child: page),
              _BottomStudioNavigation(
                currentSection: _currentSection,
                onSelected: _changeSection,
              ),
            ],
          );
        }

        return Row(
          children: [
            _SideStudioNavigation(
              currentSection: _currentSection,
              onSelected: _changeSection,
            ),
            Expanded(
              child: Column(
                children: [
                  _StudioTopBar(currentSection: _currentSection),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCurrentPage() {
    final dependencies = _dependencies;
    return switch (_currentSection) {
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
            saveCharacters: dependencies.workspaceService.saveCharacters,
          )),
      StudioShellSection.workbench =>
        GenerationPageView(viewmodel: dependencies.generationPageViewModel),
      StudioShellSection.script => _withAssetCapture(
          StudioShellSection.script,
          StudioScriptPage(
            viewModel: _scriptViewModel,
            assetFocus: _scriptAssetFocus,
            onSentToProduction: _handleScriptProductionSend,
          )),
      StudioShellSection.batch => _buildBatchPage(),
      StudioShellSection.scriptExhibition => _withAssetCapture(
          StudioShellSection.scriptExhibition,
          ScriptExhibitionRoomPage(
            viewModel: _scriptExhibitionRoomViewModel,
            onSendToScriptWorkbench: (focus) {
              unawaited(_openScriptExhibitionFocus(focus));
            },
            onSendToWorkbench: (focus) {
              unawaited(_openScriptExhibitionImageInWorkbench(focus));
            },
          )),
      StudioShellSection.gallery => _withAssetCapture(
          StudioShellSection.gallery,
          StudioGalleryPage(
            viewModel: dependencies.generationPageViewModel,
            galleryService: dependencies.galleryService,
            payloadConfig: dependencies.payloadConfig,
          )),
      StudioShellSection.settings => SettingsPageView(
          knowledgeAndRulesSection: _buildKnowledgeAndRulesPage(),
        ),
    };
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
    _changeSection(StudioShellSection.batch);
    final sent = await sendFuture;
    if (!sent) {
      return;
    }
    await _productionQueueViewModel.load();
  }

  Widget _buildBatchPage() {
    return StudioBatchPage(
      viewModel: _productionQueueViewModel,
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
    return ScriptExhibitionRoomViewModel(
      loadScripts: GetIt.I.isRegistered<TokenizerScriptService>()
          ? GetIt.I<TokenizerScriptService>().loadScripts
          : null,
      loadRecastCaches: GetIt.I<WorkspaceService>().loadRecastScriptCaches,
      loadProductionPlans: GetIt.I<ProductionQueueService>().loadPlansReadOnly,
      loadGalleryRecords: GetIt.I<StudioGalleryService>().loadRecords,
      importScriptFolder: _importScriptExhibitionFolder,
      importScriptImages: _importScriptImagesForExhibitionScript,
      deleteScriptRecord: _deleteScriptExhibitionScript,
      deleteItemRecord: _deleteScriptExhibitionItem,
      renameScriptRecord: _renameScriptExhibitionScript,
      assignScriptCategory: _assignScriptExhibitionScriptCategory,
      removeScriptCategory: _removeScriptExhibitionScriptCategory,
      deleteCategoryRecord: _deleteScriptExhibitionCategory,
      renameImageAttachment: _renameScriptImageAttachment,
      renameVersionLabel: _renameScriptExhibitionVersionLabel,
      deleteVersionRecord: _deleteScriptExhibitionVersion,
      setCoverItemRecord: _setScriptExhibitionCoverItem,
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

  void _changeSection(StudioShellSection section) {
    widget.viewModel.changeIndex(_destinations.indexWhere(
      (destination) => destination.section == section,
    ));
    setState(() {
      _currentSection = section;
    });
  }

  Future<void> _openScriptAsset(StudioScriptAssetFocus focus) async {
    _scriptAssetFocusNonce += 1;
    final nextFocus = _focusWithNonce(focus, _scriptAssetFocusNonce);
    _scriptAssetFocus = nextFocus;
    _changeSection(StudioShellSection.script);
    await _scriptViewModel.ensureAssetsLoaded(forceRefresh: true);
    if (!mounted || _scriptAssetFocus?.nonce != nextFocus.nonce) return;
    _scriptAssetFocusNonce += 1;
    setState(() {
      _scriptAssetFocus = _focusWithNonce(focus, _scriptAssetFocusNonce);
    });
  }

  Future<void> _openScriptExhibitionFocus(
    ScriptExhibitionFocus focus,
  ) async {
    final sourceFolder = focus.sourceFolder.trim();
    if (sourceFolder.isEmpty) {
      return;
    }
    _changeSection(StudioShellSection.script);
    await _scriptViewModel.importScriptPath(sourceFolder);
    final frameIndex = focus.frameIndex;
    if (frameIndex != null) {
      _scriptViewModel.selectFrame(frameIndex);
    }
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
    final bytes = file.readAsBytesSync();
    _changeSection(StudioShellSection.workbench);
    if (!mounted) return;
    await transferViewModel.importBytes(
      context,
      _fileName(path),
      bytes,
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
    if (cache == null || snapshot == null || trimmed.isEmpty) {
      return;
    }
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _cacheWithScriptSnapshot(
        cache,
        _scriptWithLegacyCategory(snapshot, trimmed),
      ),
    );
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
    final snapshot = cache == null ? null : _scriptFromRecastCache(cache);
    final trimmed = categoryName.trim();
    if (cache == null || snapshot == null || trimmed.isEmpty) {
      return;
    }
    await GetIt.I<WorkspaceService>().saveRecastScriptCache(
      _cacheWithScriptSnapshot(
        cache,
        _scriptWithoutLegacyCategory(snapshot, trimmed),
      ),
    );
  }

  Future<void> _deleteScriptExhibitionCategory(String categoryName) async {
    final trimmed = categoryName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final workspaceService = GetIt.I<WorkspaceService>();
    final caches = await workspaceService.loadRecastScriptCaches();
    var changed = false;
    final nextCaches = [
      for (final cache in caches)
        if (_scriptFromRecastCache(cache) case final snapshot?)
          if (_legacyCategoryNames(snapshot).any(
            (name) => name.trim().toLowerCase() == trimmed.toLowerCase(),
          ))
            () {
              changed = true;
              return _cacheWithScriptSnapshot(
                cache,
                _scriptWithoutLegacyCategory(snapshot, trimmed),
              );
            }()
          else
            cache
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
    final sourceFingerprint = fingerprintJson(jsonEncode([
      script.id,
      script.rootPath,
      for (final frame in script.frames)
        [
          frame.index,
          frame.fileName,
          frame.sourcePath,
          frame.sourceImagePath,
          frame.rawJson,
        ],
    ]));
    return RecastScriptCache(
      scriptId: script.id,
      scriptName: script.name,
      sourceRootPath: script.rootPath,
      sourceFingerprint: sourceFingerprint,
      sourceContentFingerprint: fingerprintJson(jsonEncode(script.toJson())),
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
    final caches = await GetIt.I<WorkspaceService>().loadRecastScriptCaches();
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
    return RecastScriptCache(
      scriptId: cache.scriptId,
      scriptName: scriptName ?? cache.scriptName,
      sourceRootPath: cache.sourceRootPath,
      sourceFingerprint: cache.sourceFingerprint,
      sourceContentFingerprint: fingerprintJson(jsonEncode(snapshot)),
      updatedAt: DateTime.now().toUtc(),
      roleCandidates: cache.roleCandidates,
      mapping: cache.mapping,
      aiRoleExtraction: cache.aiRoleExtraction,
      aiRoleExtractionChunks: cache.aiRoleExtractionChunks,
      aiRoleExtractionDraftCollapsed: cache.aiRoleExtractionDraftCollapsed,
      scriptBlockWords: cache.scriptBlockWords,
      knowledgeSnapshot: cache.knowledgeSnapshot,
      scriptSnapshot: snapshot,
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

    await _deleteTokenizerScriptsForExhibitionScript(script);

    final caches = await workspaceService.loadRecastScriptCaches();
    await workspaceService.saveRecastScriptCaches(
      caches
          .where(
            (cache) => !_recastCacheMatchesExhibitionScript(
              cache,
              scriptId: script.scriptId,
              title: script.title,
              sourceFolder: script.sourceFolder,
            ),
          )
          .toList(growable: false),
    );

    final plans = await productionService.loadPlans();
    final now = DateTime.now().toUtc();
    final nextPlans = <ProductionPlan>[];
    for (final plan in plans) {
      final nextTasks = plan.tasks
          .where((task) => !_productionTaskMatchesScript(task, script))
          .toList(growable: false);
      if (nextTasks.isEmpty) {
        continue;
      }
      nextPlans.add(
        nextTasks.length == plan.tasks.length
            ? plan
            : plan.copyWith(tasks: nextTasks, updatedAt: now),
      );
    }
    await productionService.savePlans(nextPlans);

    final records = await galleryService.loadRecords();
    await galleryService.saveRecords(
      records
          .where((record) => !_galleryRecordMatchesScript(record, script))
          .toList(growable: false),
    );
    if (deleteLocalFiles) {
      await _deleteLocalImageFiles(localImagePaths);
    }
    unawaited(_productionQueueViewModel.load());
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
    for (final scriptId in scriptIds) {
      await tokenizerService.removeScript(scriptId);
    }
  }

  Future<void> _deleteScriptExhibitionItem(
    ScriptExhibitionItem item,
  ) async {
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
      return;
    }

    final galleryService = GetIt.I<StudioGalleryService>();
    final galleryRecordId = item.galleryRecordId?.trim();
    if (galleryRecordId != null && galleryRecordId.isNotEmpty) {
      await galleryService.removeRecord(galleryRecordId);
      return;
    }

    final planId = item.productionPlanId?.trim();
    final taskId = item.taskId?.trim();
    if (planId == null || planId.isEmpty || taskId == null || taskId.isEmpty) {
      return;
    }

    final productionService = GetIt.I<ProductionQueueService>();
    final plans = await productionService.loadPlans();
    final now = DateTime.now().toUtc();
    final nextPlans = <ProductionPlan>[];
    for (final plan in plans) {
      if (plan.id != planId) {
        nextPlans.add(plan);
        continue;
      }
      final nextTasks =
          plan.tasks.where((task) => task.id != taskId).toList(growable: false);
      if (nextTasks.isEmpty) {
        continue;
      }
      nextPlans.add(plan.copyWith(tasks: nextTasks, updatedAt: now));
    }
    await productionService.savePlans(nextPlans);
    unawaited(_productionQueueViewModel.load());
  }

  Future<void> _deleteScriptExhibitionVersion(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  ) async {
    if (version.id == ScriptExhibitionVersion.originalId) {
      return;
    }
    final items = [
      for (final item in version.items)
        if (item.canDelete) item,
    ];
    for (final item in items) {
      await _deleteScriptExhibitionItem(item);
    }
  }

  bool _productionTaskMatchesScript(
    ProductionTask task,
    ScriptExhibitionScript script,
  ) {
    final source = task.source;
    return _matchesExhibitionScriptIdentity(
      script,
      scriptId: source.scriptId,
      sourceFolder: source.scriptPath,
      title: source.scriptName,
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
    final paths = <String>{};
    for (final item in script.items) {
      if (item.sourceKind == ScriptExhibitionItemSourceKind.original) {
        continue;
      }
      _addLocalImagePath(paths, item.imagePath);
      _addLocalImagePath(paths, item.galleryRecord?.imagePath);
      _addLocalImagePath(
        paths,
        item.galleryRecord?.provenance?.outputImagePath,
      );
    }
    return paths.toList(growable: false);
  }

  void _addLocalImagePath(Set<String> paths, String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (trimmed.contains('://')) return;
    paths.add(trimmed);
  }

  Future<void> _deleteLocalImageFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.file) {
          await File(path).delete();
        }
      } on FileSystemException {
        // Best effort: a stale or locked image should not restore deleted
        // exhibition metadata.
      }
    }
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

class _StudioTopBar extends StatelessWidget {
  final StudioShellSection currentSection;
  final bool compact;

  const _StudioTopBar({
    required this.currentSection,
    this.compact = false,
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

  const _SideStudioNavigation({
    required this.currentSection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
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
              for (final destination in _destinations)
                _SideStudioNavigationItem(
                  destination: destination,
                  selected: destination.section == currentSection,
                  onTap: () => onSelected(destination.section),
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

  const _SideStudioNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? StudioTokens.onPrimary : StudioTokens.textSecondary;
    final background = selected ? StudioTokens.primary : Colors.transparent;

    return Padding(
      key: ValueKey('studio-nav-${destination.section.name}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: background,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(destination.icon, color: foreground, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: foreground,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomStudioNavigation extends StatelessWidget {
  final StudioShellSection currentSection;
  final ValueChanged<StudioShellSection> onSelected;

  const _BottomStudioNavigation({
    required this.currentSection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: StudioTokens.surfaceBase,
        border: Border(
          top: BorderSide(color: StudioTokens.border),
        ),
      ),
      child: Row(
        children: [
          for (final destination in _destinations)
            Expanded(
              child: _BottomStudioNavigationItem(
                destination: destination,
                selected: destination.section == currentSection,
                onTap: () => onSelected(destination.section),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomStudioNavigationItem extends StatelessWidget {
  final _StudioDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _BottomStudioNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? StudioTokens.onPrimary : StudioTokens.textSecondary;
    final background = selected ? StudioTokens.primary : Colors.transparent;
    return Tooltip(
      key: ValueKey('studio-nav-${destination.section.name}'),
      message: destination.label,
      child: Material(
        color: background,
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
      ),
    );
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
