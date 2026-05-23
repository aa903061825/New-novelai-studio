import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/ui/core/utils/flushbar.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/core/widgets/slider_list_tile.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/generation_preview_panel.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/prompt_composer_panel.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_asset_drawer.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_transfer_actions.dart';

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
    final buttons = ListenableBuilder(
      listenable:
          Listenable.merge([viewmodel, viewmodel.commandStatus.isBatchActive]),
      builder: (context, _) {
        final isBatchActive = viewmodel.commandStatus.isBatchActive.value;
        final hasPendingResume = viewmodel
            .payloadConfig.generationRuntimeState.hasPendingBatchResume;
        final canResumeFromNumber =
            viewmodel.payloadConfig.settings.numberOfRequests > 0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'gpfab1',
              onPressed: () => _showDisplaySettingsDialog(context),
              tooltip: tr('generation_settings'),
              child: const Icon(Icons.handyman_outlined),
            ),
            const SizedBox(height: 20.0),
            FloatingActionButton(
              heroTag: 'gpfab2',
              onPressed: () => viewmodel.addTestPromptInfoCardContent(),
              tooltip: tr('generate_one_prompt'),
              child: const Icon(Icons.add),
            ),
            const SizedBox(height: 20.0),
            FloatingActionButton(
              heroTag: 'gpfab-preview',
              onPressed: () => _saveConfigPreview(context),
              tooltip: tr('save_config_preview'),
              child: const Icon(Icons.add_photo_alternate_outlined),
            ),
            if (hasPendingResume) ...[
              const SizedBox(height: 20.0),
              FloatingActionButton(
                heroTag: 'gpfab3',
                onPressed: isBatchActive ? null : viewmodel.resumeBatchFromLast,
                tooltip: tr('continue_from_last_time'),
                child: const Icon(Icons.history),
              ),
            ],
            if (canResumeFromNumber) ...[
              const SizedBox(height: 20.0),
              FloatingActionButton(
                heroTag: 'gpfab4',
                onPressed: isBatchActive
                    ? null
                    : () => _showResumeFromNumberDialog(context),
                tooltip: tr('continue_from_number'),
                child: const Icon(Icons.format_list_numbered),
              ),
            ],
            const SizedBox(height: 20.0),
            FloatingActionButton(
              heroTag: 'gpfab5',
              onPressed: () => viewmodel.toggleBatch(),
              tooltip: tr('toggle_generation'),
              child: Icon(
                isBatchActive ? Icons.stop : Icons.play_arrow,
              ),
            ),
          ],
        );
      },
    );
    return Scaffold(
      backgroundColor: StudioTokens.surface1,
      body: Column(
        children: [
          if (transferViewModel != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: WorkbenchTransferActions(
                  viewModel: transferViewModel,
                ),
              ),
            ),
          Expanded(
            child: _WorkbenchLayout(
              viewmodel: viewmodel,
              assetService: assetService,
              catalogService: catalogService,
            ),
          ),
        ],
      ),
      floatingActionButton: buttons,
    );
  }

  void _saveConfigPreview(BuildContext context) {
    final savedCount = viewmodel.saveCurrentConfigPreview();
    if (savedCount == 0) {
      showWarningBar(context, tr('config_preview_no_images'));
      return;
    }
    showInfoBar(
      context,
      tr(
        'config_preview_saved',
        namedArgs: {'num': savedCount.toString()},
      ),
    );
  }

  void _showDisplaySettingsDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(tr('generation_settings')),
              content: DisplaySettingsView(viewmodel: viewmodel),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('confirm')))
              ],
            ));
  }

  Future<void> _showResumeFromNumberDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    final totalCount = viewmodel.payloadConfig.settings.numberOfRequests;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('continue_from_number_title')),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: tr('continue_from_number_hint'),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('cancel')),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed <= 0) {
                  setState(() {
                    errorText = tr('continue_from_number_invalid');
                  });
                  return;
                }
                if (totalCount > 0 && parsed > totalCount) {
                  setState(() {
                    errorText = tr(
                      'continue_from_number_out_of_range',
                      namedArgs: {
                        'total': totalCount.toString(),
                      },
                    );
                  });
                  return;
                }
                Navigator.of(context).pop(parsed);
              },
              child: Text(tr('confirm')),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      viewmodel.resumeBatchFromNumber(result);
    }
  }
}

class _WorkbenchLayout extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;
  final StudioWorkbenchAssetService assetService;
  final StudioAssetCatalogService catalogService;

  const _WorkbenchLayout({
    required this.viewmodel,
    required this.assetService,
    required this.catalogService,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final drawer = WorkbenchAssetDrawer(
          catalogService: catalogService,
          workbenchAssetService: assetService,
        );
        final composer = PromptComposerPanel(service: assetService);
        final generation = GenerationPreviewPanel(viewmodel: viewmodel);

        if (constraints.maxWidth < 1180) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              SizedBox(height: 360, child: drawer),
              const SizedBox(height: 12),
              composer,
              const SizedBox(height: 12),
              SizedBox(height: 640, child: generation),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(width: 300, child: drawer),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: composer),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: generation),
            ],
          ),
        );
      },
    );
  }
}

class DisplaySettingsView extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const DisplaySettingsView({super.key, required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: viewmodel,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderListTile(
                title: '${tr('column_number')}: ${viewmodel.colNum.toString()}',
                sliderValue: viewmodel.colNum.toDouble(),
                min: 1.0,
                max: 5.0,
                divisions: 4,
                onChanged: (value) => viewmodel.setCardsPerCol(value.toInt()),
              ),
              ListTile(
                title: Text(tr('clear_list')),
                leading: const Icon(Icons.clear_all),
                onTap: viewmodel.clearCommandList,
              ),
              CheckboxListTile(
                title: Text(tr('override_random_prompts')),
                secondary: const Icon(Icons.edit),
                value: viewmodel.payloadConfig.useOverridePrompt,
                onChanged: (value) => viewmodel.setOverride(value),
              ),
              if (viewmodel.payloadConfig.useOverridePrompt)
                CheckboxListTile(
                  title: Text(tr('use_character_prompt')),
                  secondary: const Icon(Icons.edit),
                  value: viewmodel.payloadConfig.useCharacterPromptWithOverride,
                  onChanged: (value) => viewmodel.setCharacterOverride(value),
                ),
            ],
          );
        });
  }
}
