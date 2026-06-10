# Script Recast Role Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a card-based Script Recast role assembly editor that supports friendly role labels, detected outfit stages, manual prompt part edits, compositional character/outfit mapping, and separate Script AI / Translation AI settings.

**Architecture:** Extend the persisted mapping model with role assemblies while keeping legacy `roleSwaps` readable. Add a local heuristic stage detector now and keep it behind a detector boundary so AI recognition can plug in later. The engine, ViewModel, and UI consume the same role assembly model so manual edits are the final source of truth.

**Tech Stack:** Dart, Flutter, `flutter_test`, existing Studio Script models/services/widgets.

---

## File Structure

- Modify: `lib/data/studio/models/script_recast.dart`
  - Add `RecastPromptParts`, `RoleAssemblyStage`, `RoleAssembly`.
  - Add `roleAssemblies` to `RecastMapping`.
  - Keep `RoleSwap` compatibility.
- Create: `lib/data/studio/services/script_recast_role_stage_detector.dart`
  - Define `RecastRoleStageDetector`.
  - Implement `LocalHeuristicRoleStageDetector`.
- Modify: `lib/data/studio/services/script_recast_engine.dart`
  - Prefer `roleAssemblies` when available.
  - Resolve character/outfit/manual prompt parts per frame stage.
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Expose role cards with `角色 1`, stage chips, selected stage data, editable prompt fields.
  - Keep legacy setters but route them through stage assembly.
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Replace compact rows with role cards.
  - Keep artist chain in a separate full row/section.
- Modify: `lib/data/models/settings.dart`
  - Add Script AI and Translation AI base URL/token fields.
- Modify: `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`
  - Add setters for the four AI fields.
- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
  - Render a dedicated AI settings section with two cards.
- Test: `test/data/studio/models/script_recast_model_test.dart`
- Test: `test/data/studio/services/script_recast_role_stage_detector_test.dart`
- Test: `test/data/studio/services/script_recast_engine_test.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`
- Test: `test/data/models/settings_batch_interval_jitter_test.dart`
- Test: `test/ui/settings_page/settings_page_viewmodel_test.dart`
- Test: `test/ui/settings_page/settings_page_view_widget_test.dart`

---

### Task 1: Persist Role Assembly Model

**Files:**
- Modify: `lib/data/studio/models/script_recast.dart`
- Test: `test/data/studio/models/script_recast_model_test.dart`

- [ ] **Step 1: Write the failing model round-trip test**

Add this test inside `group('RecastMapping', ...)`:

```dart
test('round trips role assemblies with prompt parts and stages', () {
  final mapping = RecastMapping(
    id: 'mapping-assembly',
    scriptId: 'script-1',
    roleAssemblies: const [
      RoleAssembly(
        sourceRoleId: 'slot-0',
        displayLabel: '角色 1',
        sourceName: 'source heroine',
        stages: [
          RoleAssemblyStage(
            id: 'slot-0-stage-1',
            label: '服装 1',
            frameIndexes: [1, 2],
            sourceSummary: 'school uniform',
            targetCharacterId: 'char-hero',
            targetUpperOutfitId: 'school',
            targetLowerOutfitId: 'casual',
            manualParts: RecastPromptParts(
              identity: 'edited heroine',
              upperBody: 'animal ears',
              lowerBody: 'tail',
              upperClothing: 'white shirt',
              lowerClothing: 'black skirt',
            ),
          ),
        ],
      ),
    ],
  );

  final restored = RecastMapping.fromJson(mapping.toJson());

  expect(restored.toJson(), mapping.toJson());
  expect(restored.roleAssemblies.single.displayLabel, '角色 1');
  expect(restored.roleAssemblies.single.stages.single.label, '服装 1');
  expect(
    restored.roleAssemblies.single.stages.single.manualParts.upperClothing,
    'white shirt',
  );
});
```

- [ ] **Step 2: Run the model test to verify RED**

Run: `flutter test test/data/studio/models/script_recast_model_test.dart`

Expected: FAIL because `RoleAssembly`, `RoleAssemblyStage`, `RecastPromptParts`, and `RecastMapping.roleAssemblies` do not exist.

- [ ] **Step 3: Implement model classes and JSON support**

Add immutable classes with `fromJson`, `toJson`, and `copyWith` where later tasks need mutation:

```dart
class RecastPromptParts {
  final String identity;
  final String upperBody;
  final String lowerBody;
  final String upperClothing;
  final String lowerClothing;

  const RecastPromptParts({
    this.identity = '',
    this.upperBody = '',
    this.lowerBody = '',
    this.upperClothing = '',
    this.lowerClothing = '',
  });
}
```

Then add equivalent full implementations for `RoleAssemblyStage` and `RoleAssembly`, and add `List<RoleAssembly> roleAssemblies` to `RecastMapping`, `fromJson`, `copyWith`, and `toJson`.

- [ ] **Step 4: Run the model test to verify GREEN**

Run: `flutter test test/data/studio/models/script_recast_model_test.dart`

Expected: PASS.

---

### Task 2: Detect Local Outfit Stages

**Files:**
- Create: `lib/data/studio/services/script_recast_role_stage_detector.dart`
- Test: `test/data/studio/services/script_recast_role_stage_detector_test.dart`

- [ ] **Step 1: Write the failing detector test**

Create the test file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_recast_role_stage_detector.dart';

void main() {
  test('local detector groups one role into multiple outfit stages', () {
    final script = Script(
      id: 'script-1',
      name: 'Script',
      rootPath: '',
      detectedSchema: ScriptSchema.v4Slotted,
      frames: [
        _frame(1, ['alice, white shirt, black skirt, standing']),
        _frame(2, ['alice, white shirt, black skirt, sitting']),
        _frame(3, ['alice, red dress, thighhighs, fighting pose']),
      ],
    );

    final assemblies =
        const LocalHeuristicRoleStageDetector().detectRoleAssemblies(script);

    expect(assemblies, hasLength(1));
    expect(assemblies.single.displayLabel, '角色 1');
    expect(assemblies.single.sourceName, 'alice');
    expect(assemblies.single.stages.map((stage) => stage.label), [
      '服装 1',
      '服装 2',
    ]);
    expect(assemblies.single.stages.first.frameIndexes, [1, 2]);
    expect(assemblies.single.stages.last.frameIndexes, [3]);
    expect(assemblies.single.stages.first.sourceSummary, contains('white shirt'));
    expect(assemblies.single.stages.last.sourceSummary, contains('red dress'));
  });
}

ScriptFrame _frame(int index, List<String> charCaptions) {
  return ScriptFrame(
    index: index,
    fileName: 'nai_$index.json',
    sourcePath: '',
    rawJson: '{}',
    parsed: ParsedFrame(
      baseCaption: 'artist:test',
      charCaptions: charCaptions,
      sourcePayload: {
        'Comment': {
          'v4_prompt': {
            'caption': {
              'base_caption': 'artist:test',
              'char_captions': [
                for (final caption in charCaptions) {'char_caption': caption},
              ],
            },
          },
        },
      },
    ),
    detectedSchema: ScriptSchema.v4Slotted,
    parseStatus: ScriptFrameParseStatus.parsed,
  );
}
```

- [ ] **Step 2: Run the detector test to verify RED**

Run: `flutter test test/data/studio/services/script_recast_role_stage_detector_test.dart`

Expected: FAIL because the detector file/class does not exist.

- [ ] **Step 3: Implement detector boundary and local heuristic**

Implement:

```dart
abstract interface class RecastRoleStageDetector {
  List<RoleAssembly> detectRoleAssemblies(Script script);
}

class LocalHeuristicRoleStageDetector implements RecastRoleStageDetector {
  const LocalHeuristicRoleStageDetector();
}
```

The local implementation should:

- Inspect parsed frames only.
- Create source role IDs as `slot-$index`.
- Create user labels as `角色 ${index + 1}`.
- Use the first tag as `sourceName`.
- Group by normalized clothing signature from upper/lower-looking tags.
- Produce stage IDs as `slot-$index-stage-$stageNumber`.
- Produce stage labels as `服装 $stageNumber`.
- Store frame indexes in each stage.
- Store a short comma-joined source summary from detected clothing/body tags.

- [ ] **Step 4: Run the detector test to verify GREEN**

Run: `flutter test test/data/studio/services/script_recast_role_stage_detector_test.dart`

Expected: PASS.

---

### Task 3: Compose Engine Captions From Assemblies

**Files:**
- Modify: `lib/data/studio/services/script_recast_engine.dart`
- Test: `test/data/studio/services/script_recast_engine_test.dart`

- [ ] **Step 1: Write the failing engine test**

Add a test that maps one role to character identity plus separate upper/lower outfit selections plus manual edits:

```dart
test('role assembly composes character outfit parts and manual edits per stage', () {
  final script = _scriptWithCharacterCaption(
    'source heroine, old dress, standing, nose blush',
  );
  final result = ScriptRecastEngine().resolvePayloads(
    script: script,
    mapping: RecastMapping.defaults(script.id).copyWith(
      roleAssemblies: const [
        RoleAssembly(
          sourceRoleId: 'slot-0',
          displayLabel: '角色 1',
          sourceName: 'source heroine',
          stages: [
            RoleAssemblyStage(
              id: 'slot-0-stage-1',
              label: '服装 1',
              frameIndexes: [1],
              targetCharacterId: 'char-assembly',
              targetUpperOutfitId: 'upper-stage',
              targetLowerOutfitId: 'lower-stage',
              manualParts: RecastPromptParts(
                upperBody: 'manual animal ears',
                lowerClothing: 'manual boots',
              ),
            ),
          ],
        ),
      ],
    ),
    characters: const [_assemblyHeroine],
    artistChains: const [],
  );

  final charCaption = _resolvedCharCaption(result);
  expect(charCaption, contains('assembly_heroine'));
  expect(charCaption, contains('blue eyes'));
  expect(charCaption, contains('manual animal ears'));
  expect(charCaption, contains('white blouse'));
  expect(charCaption, contains('bare legs'));
  expect(charCaption, contains('manual boots'));
  expect(charCaption, contains('standing'));
  expect(charCaption, contains('nose blush'));
  expect(charCaption, isNot(contains('old dress')));
});
```

Add `_assemblyHeroine` with two outfits:

```dart
const _assemblyHeroine = CharacterEntry(
  id: 'char-assembly',
  name: 'Assembly Heroine',
  traits: ViewVariantTexts(frontFull: 'blue eyes'),
  anchorTags: ['assembly_heroine'],
  identityTags: ['blue eyes'],
  outfits: [
    WorkspaceOutfit(
      id: 'upper-stage',
      name: 'Upper Stage',
      tags: ViewVariantTexts(
        frontFull: 'white blouse, red ribbon',
        frontUpper: 'white blouse',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: ['white blouse'],
      ),
    ),
    WorkspaceOutfit(
      id: 'lower-stage',
      name: 'Lower Stage',
      tags: ViewVariantTexts(
        frontFull: 'bare legs, black boots',
        frontLower: 'bare legs, black boots',
      ),
      partTags: WorkspaceOutfitPartTags(
        lowerBodyTags: ['bare legs'],
        lowerClothingTags: ['black boots'],
      ),
    ),
  ],
);
```

- [ ] **Step 2: Run the engine test to verify RED**

Run: `flutter test test/data/studio/services/script_recast_engine_test.dart`

Expected: FAIL because the engine ignores `roleAssemblies`.

- [ ] **Step 3: Implement assembly resolution**

In `_resolveCharCaptions`, if `mapping.roleAssemblies.isNotEmpty`, resolve by assembly first:

- Parse slot index from `assembly.sourceRoleId`.
- Pick the stage containing `frame.index`; fallback to the first stage.
- Resolve `targetCharacterId`, `targetUpperOutfitId`, and `targetLowerOutfitId`.
- Build parts from character/outfit data.
- Overlay non-empty manual fields.
- Join deduped tags in the required order.
- Append `_sourceRoleTailTags(sourceCaption, character)`.

- [ ] **Step 4: Run the engine test to verify GREEN**

Run: `flutter test test/data/studio/services/script_recast_engine_test.dart`

Expected: PASS.

---

### Task 4: Expose Role Cards and Manual Edits in ViewModel

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing ViewModel tests**

Add tests in `StudioScriptViewModel` group:

```dart
test('role mappings expose friendly labels and detected outfit stages', () async {
  final viewModel = StudioScriptViewModel();

  await viewModel.importScriptPath(_fixturePath);

  expect(viewModel.roles, contains('角色 1 -> vulpisfoglia_(arknights)'));
  expect(viewModel.roles, isNot(contains(startsWith('slot-0'))));
  expect(viewModel.roleMappings.first.sourceLabel, '角色 1');
  expect(viewModel.roleMappings.first.stageItems.first.label, '服装 1');
});

test('manual role part edits update preview payload', () async {
  final viewModel = StudioScriptViewModel(
    loadCharacters: () async => const [
      CharacterEntry(
        id: 'char-hero',
        name: 'library character',
        traits: ViewVariantTexts(frontFull: 'green eyes'),
        anchorTags: ['library_hero'],
      ),
    ],
  );

  await viewModel.importScriptPath(_fixturePath);
  viewModel.setRoleCharacter('slot-0', 'char-hero');
  viewModel.setRoleStagePart(
    sourceRoleId: 'slot-0',
    stageId: viewModel.roleMappings.first.stageItems.first.id,
    part: StudioScriptRolePart.upperClothing,
    value: 'custom cape',
  );

  expect(viewModel.diff.recast, contains('custom cape'));
  expect(viewModel.roleMappings.first.stageItems.first.parts.upperClothing,
      'custom cape');
});
```

- [ ] **Step 2: Run the ViewModel tests to verify RED**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart`

Expected: FAIL because labels are still `slot-0`, stage items do not exist, and manual setters do not exist.

- [ ] **Step 3: Implement ViewModel role assembly state**

Add UI-facing classes:

```dart
enum StudioScriptRolePart {
  identity,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
}

class StudioScriptRoleStageItem {
  final String id;
  final String label;
  final List<int> frameIndexes;
  final String sourceSummary;
  final RecastPromptParts parts;
}
```

Extend `StudioScriptRoleMappingItem` with:

- `stageItems`
- `selectedStageId`
- `selectedStage`
- selected upper/lower outfit IDs

Initialize mappings from `LocalHeuristicRoleStageDetector` in `_applyScript`. Update `_applyCache` and `_refreshPreview` to keep assemblies and role card state in sync.

- [ ] **Step 4: Route existing setters through assemblies**

Update:

- `setRoleCharacter`
- `setRoleOutfit`
- `_syncCandidateRoleMapping`

They should update every stage for the role by default, filling empty manual parts from selected assets without erasing edited fields.

Add:

```dart
void selectRoleStage(String sourceRoleId, String stageId)
void setRoleUpperOutfit(String sourceRoleId, String stageId, String? outfitId)
void setRoleLowerOutfit(String sourceRoleId, String stageId, String? outfitId)
void setRoleStagePart({
  required String sourceRoleId,
  required String stageId,
  required StudioScriptRolePart part,
  required String value,
})
```

- [ ] **Step 5: Run ViewModel tests to verify GREEN**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart`

Expected: PASS for new ViewModel tests.

---

### Task 5: Replace Mapping Rows With Cards

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add widget assertions:

```dart
testWidgets('role mapping renders cards without slot labels and keeps artist separate',
    (tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final viewModel = StudioScriptViewModel();
  await tester.runAsync(() async {
    await viewModel.importScriptPath(_fixturePath);
  });

  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('role-card-slot-0')), findsOneWidget);
  expect(find.text('角色 1'), findsWidgets);
  expect(find.text('服装 1'), findsWidgets);
  expect(find.textContaining('slot-0'), findsNothing);
  expect(find.byKey(const ValueKey('script-artist-mapping-section')),
      findsOneWidget);
});
```

- [ ] **Step 2: Run widget tests to verify RED**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart`

Expected: FAIL because the UI still renders `_RoleMappingRow` with `slot-0`.

- [ ] **Step 3: Implement role cards**

Replace `_RoleMappingRow` with `_RoleMappingCard`:

- Header chip: `item.sourceLabel`.
- Subtitle: source name and target summary.
- Stage chips: `服装 N`.
- Character picker.
- Upper outfit picker.
- Lower outfit picker.
- Text fields for `角色身份`, `上身`, `下身`, `上装`, `下装`.
- Source evidence preview.
- Keys:
  - `role-card-${item.sourceRoleId}`
  - `role-drop-target-${item.sourceRoleId}`
  - `role-stage-${item.sourceRoleId}-${stage.id}`
  - `role-part-${item.sourceRoleId}-${stage.id}-${part.name}`

- [ ] **Step 4: Make artist mapping a separate row**

Change wide layout from side-by-side role/artist panels to a column:

```dart
final mainWorkspace = Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    _RoleMapping(viewModel: viewModel),
    const SizedBox(height: 16),
    _ArtistMapping(viewModel: viewModel),
  ],
);
```

Add `key: ValueKey('script-artist-mapping-section')` to `_ArtistMapping`.

- [ ] **Step 5: Update drag tests to use the same drop target keys**

Existing drag tests should still use `role-drop-target-slot-0`, because internal IDs remain stable; only visible text changes.

- [ ] **Step 6: Run widget tests to verify GREEN**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart`

Expected: PASS.

---

### Task 6: Add Script AI and Translation AI Settings

**Files:**
- Modify: `lib/data/models/settings.dart`
- Modify: `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`
- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
- Test: `test/data/models/settings_batch_interval_jitter_test.dart`
- Test: `test/ui/settings_page/settings_page_viewmodel_test.dart`
- Test: `test/ui/settings_page/settings_page_view_widget_test.dart`

- [ ] **Step 1: Write failing settings model test**

Add:

```dart
test('settings persists script and translation ai credentials', () {
  final settings = Settings.fromJson({
    'script_ai_base_url': 'https://script.example/v1',
    'script_ai_token': 'script-token',
    'translation_ai_base_url': 'https://translate.example/v1',
    'translation_ai_token': 'translation-token',
  });

  final json = settings.toJson();

  expect(settings.scriptAiBaseUrl, 'https://script.example/v1');
  expect(settings.scriptAiToken, 'script-token');
  expect(settings.translationAiBaseUrl, 'https://translate.example/v1');
  expect(settings.translationAiToken, 'translation-token');
  expect(json['script_ai_base_url'], 'https://script.example/v1');
  expect(json['script_ai_token'], 'script-token');
  expect(json['translation_ai_base_url'], 'https://translate.example/v1');
  expect(json['translation_ai_token'], 'translation-token');
});
```

- [ ] **Step 2: Write failing ViewModel test**

Add:

```dart
test('sets script and translation ai settings', () {
  final viewmodel = SettingsPageViewmodel();

  viewmodel.setScriptAiBaseUrl('https://script.example/v1');
  viewmodel.setScriptAiToken('script-token');
  viewmodel.setTranslationAiBaseUrl('https://translate.example/v1');
  viewmodel.setTranslationAiToken('translation-token');

  expect(viewmodel.settings.scriptAiBaseUrl, 'https://script.example/v1');
  expect(viewmodel.settings.scriptAiToken, 'script-token');
  expect(viewmodel.settings.translationAiBaseUrl,
      'https://translate.example/v1');
  expect(viewmodel.settings.translationAiToken, 'translation-token');
});
```

- [ ] **Step 3: Write failing widget test**

Add:

```dart
testWidgets('settings page exposes script and translation ai credentials',
    (tester) async {
  await _pumpLocalizedSettingsPage(tester);

  expect(find.text('AI 设置'), findsOneWidget);
  expect(find.text('剧本 AI'), findsOneWidget);
  expect(find.text('翻译 AI'), findsOneWidget);
  expect(find.byKey(const ValueKey('settings-script-ai-base-url')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('settings-script-ai-token')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('settings-translation-ai-base-url')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('settings-translation-ai-token')),
      findsOneWidget);
});
```

- [ ] **Step 4: Run settings tests to verify RED**

Run:

```bash
flutter test test/data/models/settings_batch_interval_jitter_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart test/ui/settings_page/settings_page_view_widget_test.dart
```

Expected: FAIL because the fields, setters, and UI are missing.

- [ ] **Step 5: Implement settings fields, setters, and UI cards**

Add fields to `Settings` constructor/fromJson/toJson:

- `scriptAiBaseUrl`
- `scriptAiToken`
- `translationAiBaseUrl`
- `translationAiToken`

Add setters in `SettingsPageViewmodel`.

Add an `_buildAiSettingsSection` to `SettingsPageView` with two cards and text fields keyed as in the test. Tokens use `obscureText: true`.

- [ ] **Step 6: Run settings tests to verify GREEN**

Run:

```bash
flutter test test/data/models/settings_batch_interval_jitter_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart test/ui/settings_page/settings_page_view_widget_test.dart
```

Expected: PASS.

---

### Task 7: Regression Suite and Formatting

**Files:**
- All files changed above.

- [ ] **Step 1: Format changed Dart files**

Run:

```bash
dart format lib/data/studio/models/script_recast.dart lib/data/studio/services/script_recast_engine.dart lib/data/studio/services/script_recast_role_stage_detector.dart lib/ui/studio_script/view_models/studio_script_viewmodel.dart lib/ui/studio_script/widgets/studio_script_page.dart lib/data/models/settings.dart lib/ui/settings_page/view_models/settings_page_viewmodel.dart lib/ui/settings_page/widgets/settings_page_view.dart test/data/studio/models/script_recast_model_test.dart test/data/studio/services/script_recast_role_stage_detector_test.dart test/data/studio/services/script_recast_engine_test.dart test/ui/studio_script/studio_script_page_test.dart test/data/models/settings_batch_interval_jitter_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart test/ui/settings_page/settings_page_view_widget_test.dart
```

- [ ] **Step 2: Run focused regression tests**

Run:

```bash
flutter test test/data/studio/models/script_recast_model_test.dart test/data/studio/services/script_recast_role_stage_detector_test.dart test/data/studio/services/script_recast_engine_test.dart test/ui/studio_script/studio_script_page_test.dart test/data/models/settings_batch_interval_jitter_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart test/ui/settings_page/settings_page_view_widget_test.dart
```

Expected: PASS.

- [ ] **Step 3: Update Beads**

Run:

```bash
bd update NAI_NEW-vf7 --notes "Implemented role assembly mapping, outfit stage cards, manual prompt parts, and split AI settings. Focused tests pass."
```

Do not close `NAI_NEW-vf7` until all focused tests pass.

---

## Self-Review

- Spec coverage: friendly labels, card UI, stage chips, manual prompt parts, compositional role/outfit mapping, multiple outfit handling, AI-ready detector boundary, separate settings credentials, and artist separation each map to a task.
- Placeholder scan: no `TBD`, `TODO`, `implement later`, or unnamed edge-case tasks are required for execution.
- Type consistency: `RecastPromptParts`, `RoleAssemblyStage`, `RoleAssembly`, `roleAssemblies`, and `StudioScriptRolePart` are named consistently across tasks.
