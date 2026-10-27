import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_drawer_shell.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/generation_preview_panel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/prompt_composer_panel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_asset_drawer.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_single_image_console.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class GenerationPageView extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const GenerationPageView({super.key, required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final transferViewModel = GetIt.I.isRegistered<WorkbenchTransferViewModel>()
        ? GetIt.I<WorkbenchTransferViewModel>()
        : null;
    final assetService = GetIt.I<StudioWorkbenchAssetService>();
    final catalogService = GetIt.I<StudioAssetCatalogService>();
    return Scaffold(
      backgroundColor: StudioTokens.surface1,
      body: ScrollConfiguration(
        key: const ValueKey('workbench-scrollbar-suppression'),
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: _WorkbenchImportDropZone(
          transferViewModel: transferViewModel,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              assetService,
              transferViewModel,
            ]),
            builder: (context, _) {
              return _WorkbenchLayout(
                viewmodel: viewmodel,
                transferViewModel: transferViewModel,
                assetService: assetService,
                catalogService: catalogService,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkbenchLayout extends StatefulWidget {
  final GenerationPageViewmodel viewmodel;
  final WorkbenchTransferViewModel? transferViewModel;
  final StudioWorkbenchAssetService assetService;
  final StudioAssetCatalogService catalogService;

  const _WorkbenchLayout({
    required this.viewmodel,
    required this.transferViewModel,
    required this.assetService,
    required this.catalogService,
  });

  @override
  State<_WorkbenchLayout> createState() => _WorkbenchLayoutState();
}

class _WorkbenchLayoutState extends State<_WorkbenchLayout> {
  late WorkbenchSingleImageParametersViewmodel _parametersViewmodel;

  @override
  void initState() {
    super.initState();
    _parametersViewmodel = WorkbenchSingleImageParametersViewmodel(
      widget.viewmodel.payloadConfig,
    );
  }

  @override
  void didUpdateWidget(covariant _WorkbenchLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewmodel.payloadConfig != widget.viewmodel.payloadConfig) {
      _parametersViewmodel.dispose();
      _parametersViewmodel = WorkbenchSingleImageParametersViewmodel(
        widget.viewmodel.payloadConfig,
      );
    }
  }

  @override
  void dispose() {
    _parametersViewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    final transferViewModel = widget.transferViewModel;
    final assetService = widget.assetService;
    final catalogService = widget.catalogService;
    return LayoutBuilder(
      builder: (context, constraints) {
        final drawer = WorkbenchAssetDrawer(
          catalogService: catalogService,
          workbenchAssetService: assetService,
        );
        final composer = PromptComposerPanel(service: assetService);
        final parametersViewmodel = _parametersViewmodel;
        final creativeInputs = WorkbenchCreativeInputsPanel(
          parametersViewmodel: parametersViewmodel,
        );
        final generation = GenerationPreviewPanel(viewmodel: viewmodel);
        final console = WorkbenchSingleImageConsole(
          generationViewmodel: viewmodel,
          parametersViewmodel: parametersViewmodel,
          workbenchAssetService: assetService,
          transferViewModel: transferViewModel,
          showExecutionControls: constraints.maxWidth >= 1180,
        );

        if (constraints.maxWidth < 820) {
          return DefaultTabController(
            length: 3,
            child: Padding(
              key: const ValueKey('workbench-compact-layout'),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: _assetButton(context, drawer)),
                  ]),
                  const TabBar(tabs: [
                    Tab(text: '画面输入'),
                    Tab(text: '出图参数'),
                    Tab(text: '生成结果'),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(children: [
                      Column(children: [
                        Expanded(flex: 2, child: composer),
                        const SizedBox(height: 12),
                        Expanded(flex: 3, child: creativeInputs),
                      ]),
                      WorkbenchSingleImageConsole(
                        generationViewmodel: viewmodel,
                        parametersViewmodel: parametersViewmodel,
                        workbenchAssetService: assetService,
                        transferViewModel: transferViewModel,
                        showExecutionControls: false,
                      ),
                      generation,
                    ]),
                  ),
                  const SizedBox(height: 12),
                  WorkbenchGenerationActions(
                    key: const ValueKey('workbench-pinned-generation-actions'),
                    generationViewmodel: viewmodel,
                    parametersViewmodel: parametersViewmodel,
                    workbenchAssetService: assetService,
                    transferViewModel: transferViewModel,
                  ),
                ],
              ),
            ),
          );
        }

        if (constraints.maxWidth < 1180) {
          return Padding(
            key: const ValueKey('workbench-medium-layout'),
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _assetButton(context, drawer),
              ),
              const SizedBox(height: 12),
              Expanded(
                  child: Row(children: [
                Expanded(
                    flex: 6,
                    child: Column(children: [
                      Expanded(flex: 2, child: composer),
                      const SizedBox(height: 12),
                      Expanded(flex: 3, child: creativeInputs),
                    ])),
                const SizedBox(width: 12),
                Expanded(
                    flex: 5,
                    child: Column(children: [
                      Expanded(flex: 5, child: console),
                      const SizedBox(height: 12),
                      Expanded(flex: 6, child: generation),
                    ])),
              ])),
              const SizedBox(height: 12),
              WorkbenchGenerationActions(
                key: const ValueKey('workbench-pinned-generation-actions'),
                generationViewmodel: viewmodel,
                parametersViewmodel: parametersViewmodel,
                workbenchAssetService: assetService,
                transferViewModel: transferViewModel,
              ),
            ]),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: studioAssetDrawerWidth, child: drawer),
              const SizedBox(width: studioAssetDrawerGap),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.34,
                      ),
                      child: composer,
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: creativeInputs),
                  ],
                ),
              ),
              const SizedBox(width: studioAssetDrawerGap),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: console),
                    const SizedBox(height: 12),
                    Expanded(flex: 6, child: generation),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _assetButton(BuildContext context, Widget drawer) {
    return OutlinedButton.icon(
      key: const ValueKey('workbench-open-assets'),
      icon: const Icon(Icons.inventory_2_outlined),
      label: const Text('选择素材'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 520,
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '关闭素材',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(child: drawer),
            ]),
          ),
        ),
      ),
    );
  }
}

class _WorkbenchImportDropZone extends StatefulWidget {
  final WorkbenchTransferViewModel? transferViewModel;
  final Widget child;

  const _WorkbenchImportDropZone({
    required this.transferViewModel,
    required this.child,
  });

  @override
  State<_WorkbenchImportDropZone> createState() =>
      _WorkbenchImportDropZoneState();
}

class _WorkbenchImportDropZoneState extends State<_WorkbenchImportDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final transferViewModel = widget.transferViewModel;
    if (transferViewModel == null) {
      return widget.child;
    }

    return DropRegion(
      formats: Formats.standardFormats,
      onDropOver: (_) => DropOperation.copy,
      onDropEnter: (_) => setState(() => _dragging = true),
      onDropLeave: (_) => setState(() => _dragging = false),
      onPerformDrop: (event) => _handleDrop(context, event, transferViewModel),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _dragging ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  color: StudioTokens.surfaceBase.withValues(alpha: 0.84),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: StudioTokens.surface2,
                        borderRadius: BorderRadius.circular(
                          StudioTokens.radiusPanel,
                        ),
                        border: StudioTokens.cardBorder,
                      ),
                      child: Text(
                        '拖入 NovelAI PNG / JSON 导入到工作台',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDrop(
    BuildContext context,
    PerformDropEvent event,
    WorkbenchTransferViewModel transferViewModel,
  ) async {
    setState(() => _dragging = false);
    if (event.session.items.isEmpty) return;
    final item = event.session.items.first;
    final reader = item.dataReader;
    if (reader == null) return;
    reader.getFile(null, (file) async {
      final bytes = await file.readAll();
      if (!context.mounted) return;
      await transferViewModel.importBytes(
        context,
        file.fileName ?? 'dropped-file',
        bytes,
      );
    });
  }
}
