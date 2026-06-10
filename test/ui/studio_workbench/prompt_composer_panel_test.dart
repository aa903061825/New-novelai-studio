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
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_editor.dart';
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

Future<void> _addPromptTags(
  WidgetTester tester,
  Finder editor,
  String text,
) async {
  await tester.tap(
    find.descendant(
      of: editor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: editor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
    ),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('composer manual prompt uses the plus-driven tag editor',
      (tester) async {
    final payload = _payload(prompt: 'manual base');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    await tester.pumpWidget(_studioApp(PromptComposerPanel(service: service)));

    final editor =
        find.byKey(const ValueKey('workbench-manual-positive-editor'));
    expect(editor, findsOneWidget);
    expect(find.descendant(of: editor, matching: find.byType(PromptTagEditor)),
        findsOneWidget);
    expect(
      find.descendant(
        of: editor,
        matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
      ),
      findsNothing,
    );

    await _addPromptTags(tester, editor, 'golden hour, rim light');

    expect(payload.overridePrompt, 'manual base, golden hour, rim light');
    expect(find.text('golden hour'), findsOneWidget);
    expect(find.text('rim light'), findsOneWidget);
  });

  testWidgets('composer edits blocks and keeps payload ordered',
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
    final editor = find.byKey(ValueKey('prompt-block-editor-$firstId'));
    expect(editor, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: editor,
        matching: find.byKey(const ValueKey('prompt-tag-editor-delete-0')),
      ),
    );
    await tester.pumpAndSettle();
    await _addPromptTags(tester, editor, 'golden hour');
    await tester.tap(find.byKey(ValueKey('prompt-block-down-$firstId')));
    await tester.pump();

    expect(
      payload.overridePrompt,
      'manual base, wet pavement, golden hour',
    );
  });

  testWidgets('composer removes blocks and leaves negative prompt to console',
      (tester) async {
    final payload = _payload();
    final service = StudioWorkbenchAssetService(payloadConfig: payload);
    service.appendTag(
      const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
    );

    await tester.pumpWidget(_studioApp(PromptComposerPanel(service: service)));
    final blockId = service.fragments.single.id;
    await tester.tap(find.byKey(ValueKey('prompt-block-remove-$blockId')));
    await tester.pump();

    expect(
        find.byKey(const ValueKey('workbench-negative-field')), findsNothing);
    expect(service.fragments, isEmpty);
    expect(find.byKey(ValueKey('prompt-block-editor-$blockId')), findsNothing);
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
        ValueKey(
            'prompt-block-save-${sourceBackedService.fragments.single.id}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('composer blocks can be dragged to another drop position',
      (tester) async {
    final payload = _payload();
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

    final source = find.text('Rain Street');
    final target = find.byKey(const ValueKey('prompt-drop-target-0'));
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      payload.overridePrompt,
      'wet pavement, cinematic lighting',
    );
  });
}
