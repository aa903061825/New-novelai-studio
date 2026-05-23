# Novel Studio Editable Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `NAI_NEW-nt1` into a real three-column Novel Studio workbench with catalog assets on the left, editable prompt blocks in the center, and the existing generation/parameter/reference loop on the right.

**Architecture:** Keep `PayloadConfig` and `GenerationPageViewmodel` as the real generation path. Upgrade `StudioWorkbenchAssetService` from a one-way prompt appender into the active workbench composition boundary, add explicit workspace save-back for source-backed blocks, then compose compact Studio widgets around the existing generation page instead of adding a parallel payload compiler.

**Tech Stack:** Flutter, Dart, GetIt, existing Studio widgets, `WorkspaceService`, Flutter widget/unit tests.

---

## Execution Note

`C:\Users\admin\Downloads\NAI_NEW` is not a Git repository on 2026-05-22, so this plan uses verification checkpoints instead of commit commands. If the workspace is put under Git before execution, commit after each green task.

## File Map

### Data And Composition

- Modify `lib/data/studio/services/studio_workbench_asset_service.dart`
  - Own active workbench prompt blocks, payload synchronization, editing order, removal, and explicit workspace save-back.
- Modify `lib/main.dart`
  - Inject the existing `WorkspaceService` into the workbench asset service.
- Modify `test/data/studio/studio_workbench_asset_service_test.dart`
  - Prove block editing remains local until save-back and that prompt composition stays ordered.

### Workbench UI

- Create `lib/ui/studio_workbench/widgets/workbench_asset_drawer.dart`
  - Compact left-rail asset chooser backed by `StudioAssetCatalogService`.
- Create `lib/ui/studio_workbench/widgets/prompt_composer_panel.dart`
  - Center prompt block editor and positive/negative preview.
- Create `lib/ui/studio_workbench/widgets/generation_preview_panel.dart`
  - Right-side result preview tab plus existing parameter/reference tabs.
- Modify `lib/ui/generation_page/widgets/generation_page_view.dart`
  - Replace the overview-first body with the three-column Studio workbench composition while preserving generation actions and dialogs.
- Keep `lib/ui/studio_workbench/widgets/workbench_overview_panel.dart`
  - Leave it intact until the new page lands; remove it only if no production use remains after task verification.

### Widget Tests

- Create `test/ui/studio_workbench/prompt_composer_panel_test.dart`
  - Cover inline block editing, order controls, removal, preview, and save-back affordance visibility.
- Create `test/ui/studio_workbench/workbench_asset_drawer_test.dart`
  - Cover catalog selection into the workbench service.
- Modify `test/ui/generation_page/generation_page_resume_controls_widget_test.dart`
  - Preserve generation FAB/dialog regression coverage after layout changes.
- Create `test/ui/generation_page/generation_page_workbench_layout_test.dart`
  - Prove the three-column workbench and reused generation tabs are present together.

## Task 1: Make Workbench Fragments Editable Composition Blocks

**Files:**
- Modify: `lib/data/studio/services/studio_workbench_asset_service.dart`
- Modify: `test/data/studio/studio_workbench_asset_service_test.dart`

- [ ] **Step 1: Write failing service tests for local editing, order, removal, manual prompt, and negative prompt sync**

Append tests like these to `test/data/studio/studio_workbench_asset_service_test.dart`:

```dart
test('editing and ordering workbench blocks recomposes override prompt', () {
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

  final tagId = service.fragments.first.id;
  final recipeId = service.fragments.last.id;
  service.updatePositiveText(tagId, 'golden hour lighting');
  service.moveFragment(recipeId, 0);

  expect(
    service.fragments.map((fragment) => fragment.name),
    ['Rain Street', 'cinematic lighting'],
  );
  expect(payload.overridePrompt, 'manual base, wet pavement, golden hour lighting');
});

test('manual prompt and negative prompt stay in the payload path', () {
  final payload = _payload(prompt: 'old manual');
  final service = StudioWorkbenchAssetService(payloadConfig: payload);

  service.setManualPositivePrompt('new manual');
  service.setManualNegativePrompt('bad anatomy');

  expect(payload.overridePrompt, 'new manual');
  expect(payload.useOverridePrompt, isTrue);
  expect(payload.paramConfig.negativePrompt, 'bad anatomy');
});

test('removing the last block preserves manual prompt text', () {
  final payload = _payload(prompt: 'manual base');
  final service = StudioWorkbenchAssetService(payloadConfig: payload);

  service.appendCharacter(
    const CharacterEntry(
      id: 'char-1',
      name: 'Heroine',
      traits: ViewVariantTexts(frontFull: 'silver hair'),
    ),
  );

  service.removeFragment(service.fragments.single.id);

  expect(service.fragments, isEmpty);
  expect(payload.overridePrompt, 'manual base');
});
```

- [ ] **Step 2: Run the focused service test and verify it fails**

Run:

```powershell
flutter test --no-pub test/data/studio/studio_workbench_asset_service_test.dart -r expanded
```

Expected: FAIL because fragments do not have stable ids and the service has no edit, reorder, remove, or manual prompt methods.

- [ ] **Step 3: Extend the fragment model and composition methods with one payload synchronization path**

Replace the current fragment-only shape in `lib/data/studio/services/studio_workbench_asset_service.dart` with the following direction:

```dart
enum StudioWorkbenchAssetKind { character, outfit, artistChain, recipe, tag }

class StudioWorkbenchAssetFragment {
  final String id;
  final StudioWorkbenchAssetKind kind;
  final String sourceId;
  final String? sourceBlock;
  final String? sourceParentId;
  final String typeLabel;
  final String name;
  String originalPositiveText;
  String positiveText;

  StudioWorkbenchAssetFragment({
    required this.id,
    required this.kind,
    required this.sourceId,
    required this.typeLabel,
    required this.name,
    required this.originalPositiveText,
    required this.positiveText,
    this.sourceBlock,
    this.sourceParentId,
  });

  String get prompt => positiveText;
  bool get isDirty => positiveText != originalPositiveText;
}
```

Add service state and mutation methods:

```dart
String get manualPositivePrompt => _manualPositivePrompt;
String get manualNegativePrompt => payloadConfig.paramConfig.negativePrompt;

void setManualPositivePrompt(String value) {
  _manualPositivePrompt = _normalizeFragment(value);
  _syncPayload();
}

void setManualNegativePrompt(String value) {
  payloadConfig.paramConfig.negativePrompt = value.trim();
  notifyListeners();
}

void updatePositiveText(String id, String value) {
  final fragment = _fragments.firstWhere((item) => item.id == id);
  fragment.positiveText = _normalizeFragment(value);
  _syncPayload();
}

void moveFragment(String id, int targetIndex) {
  final currentIndex = _fragments.indexWhere((item) => item.id == id);
  if (currentIndex < 0) return;
  final clampedIndex = targetIndex.clamp(0, _fragments.length - 1);
  final fragment = _fragments.removeAt(currentIndex);
  _fragments.insert(clampedIndex, fragment);
  _syncPayload();
}

void removeFragment(String id) {
  _fragments.removeWhere((fragment) => fragment.id == id);
  _syncPayload();
}
```

Initialize `_manualPositivePrompt` from `payloadConfig.overridePrompt.trim()` and have `_syncPayload()` be the only writer for composed positive prompt text:

```dart
void _syncPayload() {
  payloadConfig.overridePrompt = [
    if (_manualPositivePrompt.isNotEmpty) _manualPositivePrompt,
    ..._fragments
        .map((fragment) => fragment.positiveText)
        .where((text) => text.isNotEmpty),
  ].join(', ');
  payloadConfig.useOverridePrompt = payloadConfig.overridePrompt.isNotEmpty;
  notifyListeners();
}
```

Generate deterministic-enough runtime ids without adding a package:

```dart
int _nextFragmentNumber = 0;

String _nextFragmentId(StudioWorkbenchAssetKind kind, String sourceId) {
  _nextFragmentNumber++;
  return '${kind.name}:$sourceId:$_nextFragmentNumber';
}
```

Keep existing `appendCharacter`, `appendOutfit`, `appendArtistChain`, `appendRecipe`, `appendTag`, and `clearFragments` call sites green by rebuilding them on top of `_appendFragment(...)`.

- [ ] **Step 4: Run the focused service tests again**

Run:

```powershell
flutter test --no-pub test/data/studio/studio_workbench_asset_service_test.dart -r expanded
```

Expected: PASS.

## Task 2: Add Explicit Save-Back For Source-Backed Blocks

**Files:**
- Modify: `lib/data/studio/services/studio_workbench_asset_service.dart`
- Modify: `lib/main.dart`
- Modify: `test/data/studio/studio_workbench_asset_service_test.dart`

- [ ] **Step 1: Write failing save-back tests with a real temporary workspace**

Add tests that create a `WorkspaceService`, save source assets, edit a workbench block, and explicitly save it:

```dart
test('saveBack persists an edited tag only after explicit save', () async {
  final tempDir = await Directory.systemTemp.createTemp('workbench-save-tag-');
  addTearDown(() => tempDir.delete(recursive: true));
  final workspace = WorkspaceService();
  await workspace.createWorkspace(tempDir.path);
  await workspace.saveTags('camera', const [
    TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
  ]);
  final payload = _payload();
  final service = StudioWorkbenchAssetService(
    payloadConfig: payload,
    workspaceService: workspace,
  );

  service.appendTag(
    const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
  );
  service.updatePositiveText(service.fragments.single.id, 'golden rim light');

  expect((await workspace.loadTags('camera')).single.tag, 'cinematic lighting');

  await service.saveBack(service.fragments.single.id);

  expect((await workspace.loadTags('camera')).single.tag, 'golden rim light');
  expect(service.fragments.single.isDirty, isFalse);
});

test('saveBack persists a nested outfit when parent identity is known', () async {
  final tempDir = await Directory.systemTemp.createTemp('workbench-save-outfit-');
  addTearDown(() => tempDir.delete(recursive: true));
  final workspace = WorkspaceService();
  await workspace.createWorkspace(tempDir.path);
  final character = CharacterEntry(
    id: 'char-1',
    name: 'Heroine',
    traits: const ViewVariantTexts(frontFull: 'silver hair'),
    outfits: const [
      WorkspaceOutfit(
        id: 'outfit-1',
        name: 'Rain Coat',
        tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
      ),
    ],
  );
  await workspace.saveCharacters([character]);
  final service = StudioWorkbenchAssetService(
    payloadConfig: _payload(),
    workspaceService: workspace,
  );

  service.appendOutfit(character, character.outfits.single);
  service.updatePositiveText(service.fragments.single.id, 'red rain coat');
  await service.saveBack(service.fragments.single.id);

  expect(
    (await workspace.loadCharacters()).single.outfits.single.tags.frontFull,
    'red rain coat',
  );
});
```

Import `dart:io` and `WorkspaceService` in the test file when adding the cases.

- [ ] **Step 2: Run the focused service test and verify save-back is missing**

Run:

```powershell
flutter test --no-pub test/data/studio/studio_workbench_asset_service_test.dart -r expanded
```

Expected: FAIL because the service does not receive a workspace, `appendOutfit` does not keep parent identity, and `saveBack` does not exist.

- [ ] **Step 3: Add save-back persistence by source kind**

Update the service constructor and appenders:

```dart
final WorkspaceService? workspaceService;

StudioWorkbenchAssetService({
  required this.payloadConfig,
  this.workspaceService,
}) : _manualPositivePrompt = payloadConfig.overridePrompt.trim();

void appendOutfit(CharacterEntry character, WorkspaceOutfit outfit) {
  _appendPromptFragment(
    kind: StudioWorkbenchAssetKind.outfit,
    sourceId: outfit.id,
    sourceParentId: character.id,
    typeLabel: 'Outfit',
    name: outfit.name,
    fragment: outfit.tags.frontFull,
  );
}
```

Implement `saveBack` using the current workspace entity shapes:

```dart
bool canSaveBack(StudioWorkbenchAssetFragment fragment) =>
    workspaceService != null && fragment.isDirty;

Future<void> saveBack(String id) async {
  final workspace = workspaceService;
  if (workspace == null) {
    throw StateError('Workbench save-back needs an open workspace.');
  }
  final fragment = _fragments.firstWhere((item) => item.id == id);
  switch (fragment.kind) {
    case StudioWorkbenchAssetKind.character:
      await _saveCharacterPrompt(workspace, fragment);
      break;
    case StudioWorkbenchAssetKind.outfit:
      await _saveOutfitPrompt(workspace, fragment);
      break;
    case StudioWorkbenchAssetKind.artistChain:
      await _saveArtistChainPrompt(workspace, fragment);
      break;
    case StudioWorkbenchAssetKind.recipe:
      await _saveRecipePrompt(workspace, fragment);
      break;
    case StudioWorkbenchAssetKind.tag:
      await _saveTagPrompt(workspace, fragment);
      break;
  }
  fragment.originalPositiveText = fragment.positiveText;
  notifyListeners();
}
```

Use the existing immutable workspace entities when saving:

```dart
Future<void> _saveTagPrompt(
  WorkspaceService workspace,
  StudioWorkbenchAssetFragment fragment,
) async {
  final block = fragment.sourceBlock!;
  final tags = await workspace.loadTags(block);
  await workspace.saveTags(
    block,
    [
      for (final tag in tags)
        if (tag.id == fragment.sourceId)
          TagEntry(
            id: tag.id,
            tag: fragment.positiveText,
            zh: tag.zh,
            block: tag.block,
            category: tag.category,
            aliases: tag.aliases,
            imageRefs: tag.imageRefs,
            source: tag.source,
            note: tag.note,
          )
        else
          tag,
    ],
  );
}
```

Follow the same pattern for characters, nested outfits, artist chains, and recipes:

- character save-back writes `traits.frontFull`,
- outfit save-back finds `sourceParentId` and writes `tags.frontFull`,
- artist-chain save-back writes `prompt`,
- recipe save-back writes `tags`,
- tag save-back writes `tag`.

Wire the service in `lib/main.dart`:

```dart
GetIt.instance.registerLazySingleton(
  () => StudioWorkbenchAssetService(
    payloadConfig: payloadConfig,
    workspaceService: workspaceService,
  ),
);
```

- [ ] **Step 4: Update outfit call sites and run the focused tests**

Update the asset library send action from:

```dart
widget.workbenchAssetService.appendOutfit(outfitAsset.outfit)
```

to:

```dart
widget.workbenchAssetService.appendOutfit(
  outfitAsset.character,
  outfitAsset.outfit,
)
```

Update the existing direct outfit service test to call:

```dart
service.appendOutfit(
  const CharacterEntry(
    id: 'char-1',
    name: 'Heroine',
    traits: ViewVariantTexts(frontFull: 'silver hair'),
  ),
  const WorkspaceOutfit(
    id: 'outfit-1',
    name: 'Rain Coat',
    tags: ViewVariantTexts(frontFull: 'yellow rain coat, rubber boots'),
  ),
);
```

Run:

```powershell
flutter test --no-pub test/data/studio/studio_workbench_asset_service_test.dart test/ui/studio_shell/asset_library_page_test.dart -r expanded
```

Expected: PASS.

## Task 3: Build The Center Prompt Composer Panel

**Files:**
- Create: `lib/ui/studio_workbench/widgets/prompt_composer_panel.dart`
- Create: `test/ui/studio_workbench/prompt_composer_panel_test.dart`

- [ ] **Step 1: Write failing widget tests for block editing and explicit save affordance**

Create `test/ui/studio_workbench/prompt_composer_panel_test.dart` with these local helpers before the tests:

```dart
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
```

Then add the coverage:

```dart
testWidgets('composer edits blocks and keeps preview ordered', (tester) async {
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

  await tester.enterText(
    find.byKey(ValueKey('prompt-block-field-${service.fragments.first.id}')),
    'golden hour',
  );
  await tester.tap(find.byKey(ValueKey('prompt-block-down-${service.fragments.first.id}')));
  await tester.pump();

  expect(find.textContaining('manual base, wet pavement, golden hour'), findsOneWidget);
});

testWidgets('composer removes blocks and edits manual negative prompt', (tester) async {
  final payload = _payload();
  final service = StudioWorkbenchAssetService(payloadConfig: payload);
  service.appendTag(
    const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
  );

  await tester.pumpWidget(_studioApp(PromptComposerPanel(service: service)));
  await tester.enterText(find.byKey(const ValueKey('workbench-negative-field')), 'bad anatomy');
  await tester.tap(find.byKey(ValueKey('prompt-block-remove-${service.fragments.single.id}')));
  await tester.pump();

  expect(payload.paramConfig.negativePrompt, 'bad anatomy');
  expect(service.fragments, isEmpty);
});
```

Add one save-affordance test with a fake or temp-workspace-backed service:

```dart
expect(
  find.byKey(ValueKey('prompt-block-save-${service.fragments.single.id}')),
  findsNothing,
);
```

Then edit a save-backed block and expect the save icon to appear.

- [ ] **Step 2: Run the widget test and verify the composer does not exist**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/prompt_composer_panel_test.dart -r expanded
```

Expected: FAIL because `PromptComposerPanel` does not exist.

- [ ] **Step 3: Implement the composer with focused Studio widgets**

Create a `PromptComposerPanel` that:

- listens to `StudioWorkbenchAssetService`,
- renders manual positive and negative fields,
- renders each fragment as an editable block row,
- exposes up/down/remove icon buttons with stable `ValueKey`s,
- shows save-back only when `service.canSaveBack(fragment)` is true,
- shows the actual `payloadConfig.overridePrompt` and `paramConfig.negativePrompt` preview.

Use a structure like:

```dart
class PromptComposerPanel extends StatelessWidget {
  final StudioWorkbenchAssetService service;

  const PromptComposerPanel({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Prompt 编排', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('workbench-manual-positive-field'),
              initialValue: service.manualPositivePrompt,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '手写 Prompt'),
              onChanged: service.setManualPositivePrompt,
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < service.fragments.length; index++)
              _PromptBlockRow(
                fragment: service.fragments[index],
                canMoveUp: index > 0,
                canMoveDown: index < service.fragments.length - 1,
                service: service,
              ),
            TextFormField(
              key: const ValueKey('workbench-negative-field'),
              initialValue: service.manualNegativePrompt,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '负面词'),
              onChanged: service.setManualNegativePrompt,
            ),
            const SizedBox(height: 12),
            _PromptPreview(
              positive: service.payloadConfig.overridePrompt,
              negative: service.payloadConfig.paramConfig.negativePrompt,
            ),
          ],
        ),
      ),
    );
  }
}
```

Use `TextFormField(initialValue: ...)` rather than one controller per block in the first pass; only introduce controllers if widget tests reveal stale field state after reorder.

- [ ] **Step 4: Run the composer tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/prompt_composer_panel_test.dart -r expanded
```

Expected: PASS.

## Task 4: Add The Left Asset Drawer

**Files:**
- Create: `lib/ui/studio_workbench/widgets/workbench_asset_drawer.dart`
- Create: `test/ui/studio_workbench/workbench_asset_drawer_test.dart`

- [ ] **Step 1: Write failing drawer tests against a temporary workspace catalog**

Create `test/ui/studio_workbench/workbench_asset_drawer_test.dart` with these local helpers:

```dart
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
```

Then add a temporary workspace-backed `StudioAssetCatalogService` test:

```dart
testWidgets('drawer sends catalog assets into the workbench service', (tester) async {
  final tempDir = await Directory.systemTemp.createTemp('workbench-drawer-');
  addTearDown(() => tempDir.delete(recursive: true));
  final workspace = WorkspaceService();
  await workspace.createWorkspace(tempDir.path);
  await workspace.saveTags('camera', const [
    TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
  ]);
  final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

  await tester.pumpWidget(
    _studioApp(
      WorkbenchAssetDrawer(
        catalogService: StudioAssetCatalogService(workspaceService: workspace),
        workbenchAssetService: workbench,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('workbench-drawer-add-tag-tag-1')));
  await tester.pump();

  expect(workbench.fragments.single.positiveText, 'cinematic lighting');
});
```

- [ ] **Step 2: Run the drawer test and verify the widget is missing**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart -r expanded
```

Expected: FAIL because `WorkbenchAssetDrawer` does not exist.

- [ ] **Step 3: Implement a compact catalog drawer instead of duplicating the full asset library page**

Create `WorkbenchAssetDrawer` with a `FutureBuilder<StudioAssetCatalogSnapshot>` and compact rows:

```dart
class WorkbenchAssetDrawer extends StatefulWidget {
  final StudioAssetCatalogService catalogService;
  final StudioWorkbenchAssetService workbenchAssetService;

  const WorkbenchAssetDrawer({
    super.key,
    required this.catalogService,
    required this.workbenchAssetService,
  });

  @override
  State<WorkbenchAssetDrawer> createState() => _WorkbenchAssetDrawerState();
}
```

Render sections for the snapshot assets the catalog already exposes:

```dart
_AssetSection(
  title: 'Tag',
  children: [
    for (final tag in snapshot.tags)
      _DrawerAssetRow(
        key: ValueKey('workbench-drawer-add-tag-${tag.id}'),
        title: tag.zh.isEmpty ? tag.tag : tag.zh,
        subtitle: tag.tag,
        onAdd: () => widget.workbenchAssetService.appendTag(tag),
      ),
  ],
)
```

Use the same add calls already proven by `AssetLibraryPage`:

- `appendCharacter(character)`,
- `appendOutfit(outfitAsset.character, outfitAsset.outfit)`,
- `appendArtistChain(artistChain)`,
- `appendRecipe(recipe)`,
- `appendTag(tag)`.

Keep loading, empty, and error states inside the drawer so manual prompt editing remains available when catalog loading fails.

- [ ] **Step 4: Run drawer and existing asset catalog tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart test/data/studio/studio_asset_catalog_service_test.dart -r expanded
```

Expected: PASS.

## Task 5: Compose The Three-Column Workbench Around Existing Generation Surfaces

**Files:**
- Create: `lib/ui/studio_workbench/widgets/generation_preview_panel.dart`
- Modify: `lib/ui/generation_page/widgets/generation_page_view.dart`
- Create: `test/ui/generation_page/generation_page_workbench_layout_test.dart`
- Modify: `test/ui/generation_page/generation_page_resume_controls_widget_test.dart`

- [ ] **Step 1: Write failing layout coverage**

Add `test/ui/generation_page/generation_page_workbench_layout_test.dart`.

Start by copying the localization harness from `test/ui/generation_page/generation_page_resume_controls_widget_test.dart`:

- `_EnglishGenerationAssetLoader`,
- `_buildPayloadConfig`,
- `_LocalizedGenerationApp`,
- `_pumpGenerationPage`,
- the EasyLocalization and GetIt setup/teardown.

Then add these dependency helpers and the focused layout test:

```dart
class _WorkbenchLayoutViewmodel extends GenerationPageViewmodel {}

Future<void> _registerWorkbenchDependencies() async {
  final tempDir = await Directory.systemTemp.createTemp('workbench-layout-');
  addTearDown(() => tempDir.delete(recursive: true));
  final workspace = WorkspaceService();
  await workspace.createWorkspace(tempDir.path);
  GetIt.I.registerSingleton<WorkspaceService>(workspace);
  GetIt.I.registerSingleton(
    StudioAssetCatalogService(workspaceService: workspace),
  );
  GetIt.I.registerSingleton(
    StudioWorkbenchAssetService(
      payloadConfig: GetIt.I<PayloadConfig>(),
      workspaceService: workspace,
    ),
  );
  GetIt.I.registerSingleton(WorkbenchTransferService());
  GetIt.I.registerFactory(
    () => WorkbenchTransferViewModel(
      payloadConfig: GetIt.I<PayloadConfig>(),
      transferService: GetIt.I<WorkbenchTransferService>(),
    ),
  );
}

testWidgets('generation page hosts drawer composer and generation tabs', (tester) async {
  tester.view.physicalSize = const Size(1500, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await _registerWorkbenchDependencies();
  await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

  expect(find.text('素材抽屉'), findsOneWidget);
  expect(find.text('Prompt 编排'), findsOneWidget);
  expect(find.text('结果'), findsOneWidget);
  expect(find.text('参数'), findsOneWidget);
  expect(find.text('参考'), findsOneWidget);
});
```

Adjust the current resume-controls widget helper only as needed to register the dependencies now required by the workbench layout.

- [ ] **Step 2: Run the layout and resume-control tests**

Run:

```powershell
flutter test --no-pub test/ui/generation_page/generation_page_workbench_layout_test.dart test/ui/generation_page/generation_page_resume_controls_widget_test.dart -r expanded
```

Expected: FAIL because the generation page still mounts `WorkbenchOverviewPanel` and the drawer/composer/right panel do not exist together.

- [ ] **Step 3: Extract the right generation panel and keep current generation actions**

Move the current result `WaterfallFlow` into `GenerationPreviewPanel` and put it beside existing config surfaces:

```dart
class GenerationPreviewPanel extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const GenerationPreviewPanel({super.key, required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: StudioPanel(
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '结果'),
                Tab(text: '参数'),
                Tab(text: '参考'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _GenerationResultList(viewmodel: viewmodel),
                  ParametersConfigView(viewmodel: ParametersConfigViewmodel()),
                  I2iTabView(viewmodel: I2iTabViewmodel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Keep the current FAB actions, resume dialog, save-config-preview action, and display-settings dialog in `GenerationPageView` so existing generation behavior stays in one known place.

- [ ] **Step 4: Replace the overview-first page body with adaptive workbench columns**

In `GenerationPageView`, resolve the existing registered services:

```dart
final assetService = GetIt.I<StudioWorkbenchAssetService>();
final catalogService = GetIt.I<StudioAssetCatalogService>();
```

Build a wide layout that gives the composer breathing room:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final compact = constraints.maxWidth < 1180;
    final drawer = WorkbenchAssetDrawer(
      catalogService: catalogService,
      workbenchAssetService: assetService,
    );
    final composer = PromptComposerPanel(service: assetService);
    final generation = GenerationPreviewPanel(viewmodel: viewmodel);

    if (compact) {
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
)
```

Keep `WorkbenchTransferActions` reachable from the workbench surface. The smallest change is a top-right overlay row inside the new body or the composer header.

- [ ] **Step 5: Run layout regression coverage**

Run:

```powershell
flutter test --no-pub test/ui/generation_page/generation_page_workbench_layout_test.dart test/ui/generation_page/generation_page_resume_controls_widget_test.dart test/ui/studio_workbench/workbench_transfer_actions_test.dart -r expanded
```

Expected: PASS.

## Task 6: Verify End-To-End Regression Surface

**Files:**
- Review: `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Review: `lib/ui/studio_workbench/widgets/workbench_overview_panel.dart`
- Review: `docs/superpowers/specs/2026-05-22-novel-studio-editable-workbench-design.md`

- [ ] **Step 1: Run analyzer**

Run:

```powershell
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 2: Run focused workbench and generation tests**

Run:

```powershell
flutter test --no-pub test/data/studio test/ui/studio_workbench test/ui/generation_page -r expanded
```

Expected: PASS.

- [ ] **Step 3: Run the full suite before claiming completion**

Run:

```powershell
flutter test --no-pub -r expanded
```

Expected: PASS.

- [ ] **Step 4: Manually inspect the desktop workbench**

Start the app with the repo's usual Flutter desktop target and verify:

1. Studio shell still opens the workbench section.
2. A left drawer asset can be added into the center composer.
3. Editing a block changes positive prompt preview and actual override prompt state.
4. Negative prompt input updates the generation parameter negative prompt.
5. Save-back appears only on changed source-backed blocks and failures do not discard edits.
6. Result, parameter, and reference tabs remain usable on the right.
7. Generate, stop, resume, import/export, and save-preview actions are still reachable.

## Plan Self-Review

- Spec coverage:
  - Three-column workbench is covered by Tasks 4 and 5.
  - Editable prompt blocks, local edits, ordering, removal, and prompt preview are covered by Tasks 1 and 3.
  - Explicit save-back and persistence boundaries are covered by Task 2.
  - Existing generation, parameter, reference, transfer, and result paths are reused and regression-tested in Tasks 5 and 6.
- Placeholder scan:
  - No `TBD`, `TODO`, or unbounded implementation placeholders remain.
- Type consistency:
  - `StudioWorkbenchAssetFragment`, `StudioWorkbenchAssetKind`, `appendOutfit(character, outfit)`, `saveBack`, `PromptComposerPanel`, `WorkbenchAssetDrawer`, and `GenerationPreviewPanel` use the same names in tasks, tests, and wiring.
