import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_asset_drawer.dart';

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService(this.snapshot) : super(workspaceService: WorkspaceService());

  final StudioAssetCatalogSnapshot snapshot;

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot() async => snapshot;
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

void main() {
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

    await tester.tap(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-1')));
    await tester.pump();

    expect(workbench.fragments.single.positiveText, 'cinematic lighting');
    expect(workbench.payloadConfig.overridePrompt, 'cinematic lighting');
  });
}
