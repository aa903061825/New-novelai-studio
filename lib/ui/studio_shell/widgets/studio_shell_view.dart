import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/data/studio/services/prompt_translation_service.dart';
import 'package:nai_casrand/data/studio/services/prompt_workshop_bridge.dart';
import 'package:nai_casrand/data/studio/services/production_queue_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/services/tokenizer_script_service.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/ui/generation_page/widgets/generation_page_view.dart';
import 'package:nai_casrand/ui/navigation/view_models/navigation_view_model.dart';
import 'package:nai_casrand/ui/navigation/widgets/metadata_drop_area.dart';
import 'package:nai_casrand/ui/settings_page/widgets/settings_page_view.dart';
import 'package:nai_casrand/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:nai_casrand/ui/studio_batch/widgets/studio_batch_page.dart';
import 'package:nai_casrand/ui/studio_script/models/studio_script_asset_focus.dart';
import 'package:nai_casrand/ui/studio_shell/models/studio_shell_section.dart';
import 'package:nai_casrand/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/asset_library_page.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/script_exhibition_room_page.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_gallery_page.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_home_page.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_tools_page.dart';
import 'package:nai_casrand/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:nai_casrand/ui/studio_script/widgets/studio_script_page.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

class StudioShellView extends StatefulWidget {
  final NavigationViewModel viewModel;

  const StudioShellView({super.key, required this.viewModel});

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
    return switch (_currentSection) {
      StudioShellSection.home => StudioHomePage(
          catalogService: GetIt.I(),
          galleryService: GetIt.I(),
          workbenchAssetService: GetIt.I<StudioWorkbenchAssetService>(),
          payloadConfig: GetIt.I(),
          onNavigate: _changeSection,
        ),
      StudioShellSection.assets => _withAssetCapture(
          StudioShellSection.assets,
          AssetLibraryPage(
            catalogService: GetIt.I(),
            workbenchAssetService: GetIt.I<StudioWorkbenchAssetService>(),
            previewGenerationService:
                GetIt.I<StudioAssetPreviewGenerationService>(),
            onSendToScript: _openScriptAsset,
          )),
      StudioShellSection.workbench => GenerationPageView(viewmodel: GetIt.I()),
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
            viewModel: GetIt.I(),
            galleryService: GetIt.I(),
            payloadConfig: GetIt.I(),
          )),
      StudioShellSection.settings => SettingsPageView(
          knowledgeAndRulesSection: _buildKnowledgeAndRulesPage(),
        ),
    };
  }

  Widget _withAssetCapture(StudioShellSection section, Widget child) {
    return StudioAssetCaptureHost(
      key: ValueKey('asset-capture-host-${section.name}'),
      service: GetIt.I<StudioAssetCaptureService>(),
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
      loadScripts: GetIt.I<TokenizerScriptService>().loadScripts,
      loadProductionPlans: GetIt.I<ProductionQueueService>().loadPlans,
      loadGalleryRecords: GetIt.I<StudioGalleryService>().loadRecords,
      importScriptFolder: _importScriptExhibitionFolder,
      importScriptImages: _importScriptImagesForExhibitionScript,
      deleteScriptRecord: _deleteScriptExhibitionScript,
      deleteItemRecord: _deleteScriptExhibitionItem,
      renameScriptRecord: _renameScriptExhibitionScript,
      assignScriptCategory: _assignScriptExhibitionScriptCategory,
      renameImageAttachment: _renameScriptImageAttachment,
      renameVersionLabel: _renameScriptExhibitionVersionLabel,
    );
  }

  TranslationCache? _translationCacheFromGetIt() {
    if (GetIt.I.isRegistered<TranslationCache>()) {
      return GetIt.I<TranslationCache>();
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
    await _scriptViewModel.ensureAssetsLoaded();
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
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final result = await tokenizerService.scanDirectory(directory);
    if (result.sources.isEmpty) {
      throw const FormatException('没有找到可导入的剧本 JSON 或图片。');
    }
    final script = tokenizerService.createDraftFromSources(
      name: _folderName(path),
      sourceFolder: path,
      sources: result.sources,
    );
    await tokenizerService.saveScript(script);
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
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final tokenizerScript = await _findTokenizerScriptForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    if (tokenizerScript == null) {
      throw StateError('Cannot find tokenizer script for ${script.title}.');
    }
    final updated = tokenizerService.addImageAttachments(
      tokenizerScript,
      imagePaths: paths,
      labelPrefix: '\u9ed8\u8ba4',
    );
    await tokenizerService.saveScript(updated);
  }

  Future<void> _renameScriptImageAttachment(
    ScriptExhibitionItem item,
    String label,
  ) async {
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final tokenizerScript = await _findTokenizerScriptForExhibition(
      scriptId: item.scriptId,
      title: item.scriptTitle,
      sourceFolder: item.sourceFolder,
    );
    final attachmentId = item.imageAttachmentId?.trim();
    if (tokenizerScript == null ||
        attachmentId == null ||
        attachmentId.isEmpty) {
      return;
    }
    final updated = tokenizerService.renameImageAttachment(
      tokenizerScript,
      attachmentId: attachmentId,
      label: label,
    );
    await tokenizerService.saveScript(updated);
  }

  Future<void> _renameScriptExhibitionScript(
    ScriptExhibitionScript script,
    String label,
  ) async {
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final tokenizerScript = await _findTokenizerScriptForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final trimmed = label.trim();
    if (tokenizerScript == null || trimmed.isEmpty) {
      return;
    }
    await tokenizerService.saveScript(
      tokenizerScript.copyWith(name: trimmed),
    );
  }

  Future<void> _renameScriptExhibitionVersionLabel(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
    String label,
  ) async {
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final tokenizerScript = await _findTokenizerScriptForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final trimmed = label.trim();
    if (tokenizerScript == null ||
        version.id.trim().isEmpty ||
        trimmed.isEmpty) {
      return;
    }
    await tokenizerService.saveScript(
      tokenizerScript.copyWith(
        exhibitionVersionLabels: {
          ...tokenizerScript.exhibitionVersionLabels,
          version.id: trimmed,
        },
      ),
    );
  }

  Future<void> _assignScriptExhibitionScriptCategory(
    ScriptExhibitionScript script,
    String categoryName,
  ) async {
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final tokenizerScript = await _findTokenizerScriptForExhibition(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
    );
    final trimmed = categoryName.trim();
    if (tokenizerScript == null || trimmed.isEmpty) {
      return;
    }
    final nextCategories = [
      ...tokenizerScript.categoryNames.where(
        (name) => name.trim().toLowerCase() != trimmed.toLowerCase(),
      ),
      trimmed,
    ];
    await tokenizerService.saveScript(
      tokenizerScript.copyWith(categoryNames: nextCategories),
    );
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

  Future<TokenizerScript?> _findTokenizerScriptForExhibition({
    required String scriptId,
    required String title,
    required String sourceFolder,
  }) async {
    final scripts = await GetIt.I<TokenizerScriptService>().loadScripts();
    for (final script in scripts) {
      if (_sameNonEmpty(script.scriptId, scriptId) ||
          _sameNonEmpty(script.sourceFolder, sourceFolder) ||
          _sameNonEmpty(script.name, title)) {
        return script;
      }
    }
    return null;
  }

  Future<void> _deleteScriptExhibitionScript(
    ScriptExhibitionScript script,
  ) async {
    final tokenizerService = GetIt.I<TokenizerScriptService>();
    final productionService = GetIt.I<ProductionQueueService>();
    final galleryService = GetIt.I<StudioGalleryService>();

    await tokenizerService.removeScript(script.scriptId);

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
    unawaited(_productionQueueViewModel.load());
  }

  Future<void> _deleteScriptExhibitionItem(
    ScriptExhibitionItem item,
  ) async {
    final attachmentId = item.imageAttachmentId?.trim();
    if (attachmentId != null && attachmentId.isNotEmpty) {
      final tokenizerService = GetIt.I<TokenizerScriptService>();
      final tokenizerScript = await _findTokenizerScriptForExhibition(
        scriptId: item.scriptId,
        title: item.scriptTitle,
        sourceFolder: item.sourceFolder,
      );
      if (tokenizerScript == null) {
        return;
      }
      final updated = tokenizerService.removeImageAttachment(
        tokenizerScript,
        attachmentId: attachmentId,
      );
      await tokenizerService.saveScript(updated);
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

  bool _productionTaskMatchesScript(
    ProductionTask task,
    ScriptExhibitionScript script,
  ) {
    final source = task.source;
    return _sameNonEmpty(source.scriptId, script.scriptId) ||
        _sameNonEmpty(source.scriptPath, script.sourceFolder) ||
        _sameNonEmpty(source.scriptName, script.title);
  }

  bool _galleryRecordMatchesScript(
    StudioGalleryRecord record,
    ScriptExhibitionScript script,
  ) {
    final provenance = record.provenance;
    if (provenance == null) return false;
    return _sameNonEmpty(provenance.scriptId, script.scriptId) ||
        _sameNonEmpty(provenance.scriptPath, script.sourceFolder) ||
        _sameNonEmpty(provenance.scriptName, script.title);
  }

  bool _sameNonEmpty(String? left, String? right) {
    final normalizedLeft = left?.trim();
    final normalizedRight = right?.trim();
    return normalizedLeft != null &&
        normalizedLeft.isNotEmpty &&
        normalizedRight != null &&
        normalizedRight.isNotEmpty &&
        normalizedLeft == normalizedRight;
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
