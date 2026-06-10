# Script Recast Clothing Part Omission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the agreed Script Recast behavior where undetected clothing parts are grey editable rows and are omitted from formal generation unless the user supplies a value.

**Architecture:** Keep the change local to the Script Recast model, payload engine, Script page ViewModel, and existing Script page widgets. Add per-part detection metadata to role stages so the UI can show grey omitted rows without disabling editing, and so the generation engine can decide whether a selected target outfit part should be auto-filled.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing Script Recast domain models, existing `PromptTagEditor`, Beads for task tracking. Git commits are intentionally omitted because project memory says this repository is in stealth mode.

---

## File Structure

- Modify `lib/data/studio/models/script_recast.dart`
  - Add stage-level detected clothing part metadata.
  - Preserve backward compatibility by defaulting missing metadata to detected/legacy behavior.
- Modify `lib/data/studio/services/script_recast_engine.dart`
  - Omit target outfit fallback for undetected clothing rows unless the row has a manual value.
- Modify `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Surface omitted state on `StudioScriptRoleStageItem`.
  - Mark AI-extracted empty clothing fields as undetected/omitted.
  - Mark user edits as enabled when non-empty and omitted when cleared.
- Modify `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Render omitted clothing rows grey with an explicit empty hint.
  - Keep `PromptTagEditor` and drag targets active.
- Test `test/data/studio/services/script_recast_engine_test.dart`
  - Verify target outfit upper clothing is not inherited for an omitted row.
  - Verify user-filled clothing is included.
- Test `test/ui/studio_script/studio_script_page_test.dart`
  - Verify omitted row is grey/editable and becomes enabled after entry.

## Task 1: Model Omitted Clothing Parts

**Files:**
- Modify: `lib/data/studio/models/script_recast.dart`
- Test: `test/data/studio/services/script_recast_engine_test.dart`

- [ ] **Step 1: Write the failing payload tests**

Add two tests to the `ScriptRecastEngine` group:

```dart
test('role assembly omits undetected upper clothing instead of inheriting target outfit', () {
  final script = _scriptWithCharacterCaption(
    'source heroine, pleated skirt, standing',
  );
  final result = ScriptRecastEngine().resolvePayloads(
    script: script,
    mapping: RecastMapping.defaults(script.id).copyWith(
      roleAssemblies: const [
        RoleAssembly(
          sourceRoleId: 'slot-0',
          displayLabel: 'Role 1',
          sourceName: 'source heroine',
          stages: [
            RoleAssemblyStage(
              id: 'slot-0-stage-1',
              label: 'Outfit 1',
              frameIndexes: [1],
              targetCharacterId: 'char-assembly',
              targetUpperOutfitId: 'upper-stage',
              targetLowerOutfitId: 'lower-stage',
              omittedParts: {RecastPromptPart.upperClothing},
              manualParts: RecastPromptParts(
                lowerClothing: 'manual skirt',
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
  expect(charCaption, contains('manual skirt'));
  expect(charCaption, contains('standing'));
  expect(charCaption, isNot(contains('white blouse')));
});

test('manual value enables an omitted upper clothing row for generation', () {
  final script = _scriptWithCharacterCaption(
    'source heroine, pleated skirt, standing',
  );
  final result = ScriptRecastEngine().resolvePayloads(
    script: script,
    mapping: RecastMapping.defaults(script.id).copyWith(
      roleAssemblies: const [
        RoleAssembly(
          sourceRoleId: 'slot-0',
          displayLabel: 'Role 1',
          sourceName: 'source heroine',
          stages: [
            RoleAssemblyStage(
              id: 'slot-0-stage-1',
              label: 'Outfit 1',
              frameIndexes: [1],
              targetCharacterId: 'char-assembly',
              targetUpperOutfitId: 'upper-stage',
              targetLowerOutfitId: 'lower-stage',
              omittedParts: {RecastPromptPart.upperClothing},
              manualParts: RecastPromptParts(
                upperClothing: 'manual blouse',
                lowerClothing: 'manual skirt',
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
  expect(charCaption, contains('manual blouse'));
  expect(charCaption, isNot(contains('white blouse')));
});
```

- [ ] **Step 2: Run the failing payload tests**

Run:

```powershell
flutter test test/data/studio/services/script_recast_engine_test.dart --plain-name "role assembly omits undetected upper clothing instead of inheriting target outfit"
flutter test test/data/studio/services/script_recast_engine_test.dart --plain-name "manual value enables an omitted upper clothing row for generation"
```

Expected: the first test fails because `RecastPromptPart` and `omittedParts` do not exist, or because `white blouse` is still inherited.

- [ ] **Step 3: Implement minimal model support**

In `script_recast.dart`, add:

```dart
enum RecastPromptPart {
  identity,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
}
```

Add to `RoleAssemblyStage`:

```dart
final Set<RecastPromptPart> omittedParts;
```

Default it to `const {}`. Parse `omittedParts` from JSON string names, copy it in `copyWith`, and serialize it when non-empty.

- [ ] **Step 4: Implement generation omission**

In `script_recast_engine.dart`, pass `stage.omittedParts` into `_promptPartsFor`.

Change resolved outfit fallback so:

```dart
upperClothing: _manualOrResolved(
  manualParts.upperClothing,
  omittedParts.contains(RecastPromptPart.upperClothing) ? '' : resolved.upperClothing,
),
lowerClothing: _manualOrResolved(
  manualParts.lowerClothing,
  omittedParts.contains(RecastPromptPart.lowerClothing) ? '' : resolved.lowerClothing,
),
```

Keep identity and body behavior unchanged.

- [ ] **Step 5: Run payload tests**

Run:

```powershell
flutter test test/data/studio/services/script_recast_engine_test.dart --plain-name "role assembly omits undetected upper clothing instead of inheriting target outfit"
flutter test test/data/studio/services/script_recast_engine_test.dart --plain-name "manual value enables an omitted upper clothing row for generation"
```

Expected: both pass.

## Task 2: Surface Omitted Rows In ViewModel

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write the failing ViewModel/widget test**

Add a widget test near `replacement output parts can be edited as tags`:

```dart
testWidgets('undetected upper clothing row is grey but editable', (tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const extraction = ScriptAiRoleExtraction(
    status: ScriptAiRoleExtractionStatus.ready,
    confidence: 0.9,
    roles: [
      ScriptAiExtractedRole(
        sourceRoleId: 'slot-0',
        displayName: 'AI Hero',
        confidence: 0.9,
        stages: [
          ScriptAiExtractedStage(
            stageId: 'slot-0-stage-1',
            label: 'main outfit',
            frameIndexes: [1],
            identity: 'ai hero',
            upperClothing: '',
            lowerClothing: 'pleated skirt',
            confidence: 0.9,
            missingFields: ['missing_upper_clothing'],
          ),
        ],
      ),
    ],
  );
  final viewModel = StudioScriptViewModel(
    scriptAiRoleExtractionService: const _FakeRoleExtractionService(extraction),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await viewModel.importScriptPath(_fixturePath);
    await viewModel.generateAiRoleExtraction();
    await viewModel.applyHighConfidenceAiRoleExtraction();
  });
  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pumpAndSettle();

  final field = find.byKey(
    const ValueKey('role-output-part-slot-0-slot-0-stage-1-upperClothing'),
  );
  expect(field, findsOneWidget);
  expect(find.descendant(of: field, matching: find.textContaining('默认不传入')), findsOneWidget);

  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: field,
      matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: field,
      matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
    ),
    'manual blouse',
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  final stage = viewModel.roleMappings.first.selectedStage!;
  expect(stage.parts.upperClothing, 'manual blouse');
  expect(stage.omittedParts, isNot(contains(RecastPromptPart.upperClothing)));
});
```

- [ ] **Step 2: Run the failing widget test**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "undetected upper clothing row is grey but editable"
```

Expected: fails because `StudioScriptRoleStageItem.omittedParts` and omitted row UI do not exist.

- [ ] **Step 3: Add ViewModel omitted metadata**

Add to `StudioScriptRoleStageItem`:

```dart
final Set<RecastPromptPart> omittedParts;
```

Default to `const {}`. Populate from `RoleAssemblyStage.omittedParts` in `_roleMappingItemFromAssembly`.

When creating `RoleAssemblyStage` from `ScriptAiExtractedStage`, set:

```dart
omittedParts: _omittedPartsFromAiStage(stage),
```

where `_omittedPartsFromAiStage` returns upper/lower clothing omissions when the value is empty and the AI stage has `missing_upper_clothing`, `upper_clothing`, `missing_lower_clothing`, or `lower_clothing` in `missingFields`.

In `setRoleStagePart`, remove the changed part from `omittedParts` when `value.trim().isNotEmpty`, and add it back for clothing parts when `value.trim().isEmpty`.

- [ ] **Step 4: Add grey editable UI**

In `_ReplacementCompareCell`, add an `omitted` boolean parameter. Pass it from the role output part builder using `stage.omittedParts.contains(part)`.

When `omitted` and `value.trim().isEmpty`, set:

```dart
emptyText: '未检测到，默认不传入'
```

Use muted colors for the container and label, but keep `enabled` unchanged so editing and drag/drop still work.

- [ ] **Step 5: Run the widget test**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "undetected upper clothing row is grey but editable"
```

Expected: pass.

## Task 3: Focused Regression Verification

**Files:**
- Existing tests only.

- [ ] **Step 1: Run focused engine suite**

Run:

```powershell
flutter test test/data/studio/services/script_recast_engine_test.dart
```

Expected: pass.

- [ ] **Step 2: Run focused Script page suite**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "replacement output parts can be edited as tags"
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "undetected upper clothing row is grey but editable"
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "applying role extraction preserves empty clothing fields"
```

Expected: pass.

- [ ] **Step 3: Close Beads issue**

Run:

```powershell
bd close NAI_NEW-xlwf --reason="Implemented clothing part omission UI and generation behavior"
```

Expected: issue closes after tests pass.
