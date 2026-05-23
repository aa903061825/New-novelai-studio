import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/prompt_composer_panel.dart';

PayloadConfig _payload({String prompt = ''}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: prompt,
    useOverridePrompt: prompt.isNotEmpty,
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
  testWidgets('composer edits blocks and keeps preview ordered',
      (tester) async {
    final payload = _payload(prompt: 'manual base');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);
    service.appendTag(
      const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
    );
    service.appendRecipe(
      const Recipe(
        id: 'recipe-1',
        name: 'Rain Street',
        block: 'scene',
        tags: 'wet pavement',
      ),
    );

    await tester.pumpWidget(_studioApp(PromptComposerPanel(service: service)));

    final firstId = service.fragments.first.id;
    await tester.enterText(
      find.byKey(ValueKey('prompt-block-field-$firstId')),
      'golden hour',
    );
    await tester.tap(find.byKey(ValueKey('prompt-block-down-$firstId')));
    await tester.pump();

    expect(
      payload.overridePrompt,
      'manual base, wet pavement, golden hour',
    );
    expect(
      find.textContaining('manual base, wet pavement, golden hour'),
      findsOneWidget,
    );
  });

  testWidgets('composer removes blocks and edits manual negative prompt',
      (tester) async {
    final payload = _payload();
    final service = StudioWorkbenchAssetService(payloadConfig: payload);
    service.appendTag(
      const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
    );

    await tester.pumpWidget(_studioApp(PromptComposerPanel(service: service)));
    final blockId = service.fragments.single.id;
    await tester.enterText(
      find.byKey(const ValueKey('workbench-negative-field')),
      'bad anatomy',
    );
    await tester.tap(find.byKey(ValueKey('prompt-block-remove-$blockId')));
    await tester.pump();

    expect(payload.paramConfig.negativePrompt, 'bad anatomy');
    expect(service.fragments, isEmpty);
    expect(find.byKey(ValueKey('prompt-block-field-$blockId')), findsNothing);
  });

  testWidgets('composer shows save action only for dirty source-backed blocks',
      (tester) async {
    final payload = _payload();
    final noWorkspaceService =
        StudioWorkbenchAssetService(payloadConfig: payload);
    noWorkspaceService.appendTag(
      const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
    );
    noWorkspaceService.updatePositiveText(
      noWorkspaceService.fragments.single.id,
      'golden rim light',
    );

    await tester.pumpWidget(
      _studioApp(PromptComposerPanel(service: noWorkspaceService)),
    );

    expect(
      find.byKey(
        ValueKey('prompt-block-save-${noWorkspaceService.fragments.single.id}'),
      ),
      findsNothing,
    );

    final sourceBackedService = StudioWorkbenchAssetService(
      payloadConfig: _payload(),
      workspaceService: WorkspaceService(),
    );
    sourceBackedService.appendTag(
      const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
    );
    sourceBackedService.updatePositiveText(
      sourceBackedService.fragments.single.id,
      'golden rim light',
    );

    await tester.pumpWidget(
      _studioApp(PromptComposerPanel(service: sourceBackedService)),
    );

    expect(
      find.byKey(
        ValueKey('prompt-block-save-${sourceBackedService.fragments.single.id}'),
      ),
      findsOneWidget,
    );
  });
}
