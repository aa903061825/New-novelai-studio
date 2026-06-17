# Script Prompt Replacement Mapping Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use Beads as the durable tracker during execution; this document is the implementation handoff.

**Goal:** Replace the current outfit-stage / upper-lower role mapping flow with explicit role prompt replacement and scene prompt replacement workflows that reuse the existing compare-row, tag editor, quick sync, and drag interactions.

**Architecture:** Keep the script workbench screen and asset drawer, but replace `RoleAssemblyStage` as the UI driver with prompt replacement groups and rules. Character terms and scene terms come from the same AI extraction source, but the UI and stored mapping expose them as two separate sections: role replacement and scene replacement. The recast engine applies role rules to character captions and scene rules to base/global captions with exact tag matching, explicit delete actions, and match modes.

**Tech Stack:** Flutter/Dart, existing `PromptTagDisplay`, `PromptTagEditor`, `PromptTagSelectionController`, `ScriptRecastEngine`, script recast cache JSON, fake AI extraction JSON in tests only.

---

## Current System To Clean

- `lib/data/studio/models/script_recast.dart`
  - Keep `RoleAssembly` JSON reading only as a legacy input during migration.
  - Stop using `RoleAssemblyStage.targetUpperOutfitId`, `targetLowerOutfitId`, `manualParts`, and `omittedParts` as the primary mapping model.
- `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Replace `StudioScriptRoleStageItem` and stage-selection state with replacement group/rule items.
  - Remove stage label, stage frame edit, copy target to all outfits, upper outfit, and lower outfit operations from the new role replacement flow.
- `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Reuse `_RolePromptComparePanel`, `_RolePromptCompareRow`, `_CompareCell`, `_ReplacementCompareCell` ideas, but convert them into rule-row widgets.
  - Keep drag cards, `PromptTagEditor`, `PromptTagDisplay`, selection rectangle, source-to-target copy, dropped tag batch handling, and clear/quick-sync controls.
- `lib/data/studio/services/script_recast_engine.dart`
  - Replace `_roleAssemblyCaption` application path with rule application for role and scene scopes.

## New File Structure

- Modify: `lib/data/studio/models/script_recast.dart`
  - Add replacement enums and JSON models.
  - Add `rolePromptReplacements` and `scenePromptReplacements` to `RecastMapping`.
- Modify: `lib/data/studio/models/script_ai_role_extraction.dart`
  - Add extracted prompt term models for role and scene source terms.
  - Keep old stage fields readable for migration and existing tests during the first slice.
- Create: `lib/data/studio/services/script_prompt_replacement_engine.dart`
  - Exact token/phrase matching, delete, replace, merge, and frame matching.
- Modify: `lib/data/studio/services/script_recast_engine.dart`
  - Apply new role replacement groups to char captions and scene replacement groups to base captions.
- Modify: `lib/data/studio/services/script_ai_role_assembly_application.dart`
  - Convert AI extraction into replacement groups instead of outfit stages.
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Expose separate `roleReplacementMappings` and `sceneReplacementMappings`.
  - Add operations for rule target edits, delete toggles, mode changes, merge, quick sync, and drag/drop.
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Replace role stage card UI with role replacement cards.
  - Add a separate scene replacement panel; do not include an "全部" filter.
- Tests:
  - Modify: `test/data/studio/models/script_recast_model_test.dart`
  - Modify: `test/data/studio/models/script_ai_role_extraction_test.dart`
  - Create: `test/data/studio/services/script_prompt_replacement_engine_test.dart`
  - Modify: `test/data/studio/services/script_recast_engine_test.dart`
  - Modify: `test/data/studio/services/script_ai_role_assembly_application_test.dart`
  - Modify: `test/ui/studio_script/studio_script_page_test.dart`
  - Remove or rewrite obsolete outfit-stage-only expectations in `test/ui/studio_script/studio_script_stage_label_test.dart`

---

### Task 1: Add Replacement Mapping Models

**Files:**
- Modify: `lib/data/studio/models/script_recast.dart`
- Modify: `test/data/studio/models/script_recast_model_test.dart`

- [ ] **Step 1: Write the failing JSON round-trip tests**

Add tests that prove the new mapping stores role and scene rules separately and that empty replacement targets do not mean delete.

```dart
test('recast mapping round trips role and scene prompt replacement rules', () {
  const mapping = RecastMapping(
    id: 'mapping-script-1',
    scriptId: 'script-1',
    rolePromptReplacements: [
      ScriptRolePromptReplacement(
        sourceRoleId: 'slot-0',
        displayLabel: '角色 1',
        targetCharacterId: 'lily',
        targetIdentityPrompt: 'lily, silver hair, blue eyes',
        rules: [
          ScriptPromptReplacementRule(
            id: 'rule-jacket-skirt',
            sourceTerms: [
              ScriptPromptReplacementTerm(
                id: 'term-red-jacket',
                text: 'red jacket',
                category: ScriptPromptReplacementCategory.clothing,
                frameIndexes: [1, 2, 3],
              ),
              ScriptPromptReplacementTerm(
                id: 'term-black-skirt',
                text: 'black skirt',
                category: ScriptPromptReplacementCategory.clothing,
                frameIndexes: [1, 2, 3],
              ),
            ],
            targetPrompt: 'white dress, lace trim',
            action: ScriptPromptReplacementAction.replace,
            matchMode: ScriptPromptReplacementMatchMode.any,
          ),
        ],
      ),
    ],
    scenePromptReplacements: [
      ScriptScenePromptReplacement(
        id: 'scene-base',
        label: 'base prompt',
        rules: [
          ScriptPromptReplacementRule(
            id: 'rule-night',
            sourceTerms: [
              ScriptPromptReplacementTerm(
                id: 'term-night',
                text: 'night',
                category: ScriptPromptReplacementCategory.scene,
                sourceLocation: 'base prompt',
                frameIndexes: [1, 2],
              ),
            ],
            action: ScriptPromptReplacementAction.delete,
            matchMode: ScriptPromptReplacementMatchMode.anchor,
          ),
        ],
      ),
    ],
  );

  final restored = RecastMapping.fromJson(mapping.toJson());

  expect(restored.rolePromptReplacements.single.targetIdentityPrompt,
      'lily, silver hair, blue eyes');
  expect(restored.rolePromptReplacements.single.rules.single.targetPrompt,
      'white dress, lace trim');
  expect(restored.scenePromptReplacements.single.rules.single.action,
      ScriptPromptReplacementAction.delete);
});

test('blank target prompt keeps a replacement rule inactive', () {
  const rule = ScriptPromptReplacementRule(
    id: 'rule-keep',
    sourceTerms: [
      ScriptPromptReplacementTerm(
        id: 'term-glasses',
        text: 'round glasses',
        category: ScriptPromptReplacementCategory.accessory,
      ),
    ],
  );

  expect(rule.hasEffect, isFalse);
  expect(rule.action, ScriptPromptReplacementAction.none);
});
```

- [ ] **Step 2: Run the model tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_recast_model_test.dart -r expanded
```

Expected: compile failure because `ScriptPromptReplacementRule`, `ScriptRolePromptReplacement`, and `ScriptScenePromptReplacement` are not defined.

- [ ] **Step 3: Add the new data types and mapping fields**

Add these public model shapes in `script_recast.dart` near the existing recast mapping classes:

```dart
enum ScriptPromptReplacementCategory {
  identity,
  body,
  clothing,
  clothingState,
  accessory,
  scene,
}

enum ScriptPromptReplacementAction {
  none,
  replace,
  delete,
}

enum ScriptPromptReplacementMatchMode {
  any,
  all,
  anchor,
}

class ScriptPromptReplacementTerm {
  final String id;
  final String text;
  final ScriptPromptReplacementCategory category;
  final String sourcePhrase;
  final String sourceLocation;
  final List<int> frameIndexes;

  const ScriptPromptReplacementTerm({
    required this.id,
    required this.text,
    required this.category,
    this.sourcePhrase = '',
    this.sourceLocation = '',
    this.frameIndexes = const [],
  });
}

class ScriptPromptReplacementRule {
  final String id;
  final List<ScriptPromptReplacementTerm> sourceTerms;
  final List<String> excludedTermIds;
  final ScriptPromptReplacementAction action;
  final ScriptPromptReplacementMatchMode matchMode;
  final String targetPrompt;
  final String manualPhrase;
  final String anchorTermId;

  const ScriptPromptReplacementRule({
    required this.id,
    this.sourceTerms = const [],
    this.excludedTermIds = const [],
    this.action = ScriptPromptReplacementAction.none,
    this.matchMode = ScriptPromptReplacementMatchMode.any,
    this.targetPrompt = '',
    this.manualPhrase = '',
    this.anchorTermId = '',
  });

  bool get hasEffect =>
      action == ScriptPromptReplacementAction.delete ||
      targetPrompt.trim().isNotEmpty ||
      manualPhrase.trim().isNotEmpty;
}

class ScriptRolePromptReplacement {
  final String sourceRoleId;
  final String displayLabel;
  final String sourcePreview;
  final String? targetCharacterId;
  final String targetIdentityPrompt;
  final List<ScriptPromptReplacementRule> rules;

  const ScriptRolePromptReplacement({
    required this.sourceRoleId,
    required this.displayLabel,
    this.sourcePreview = '',
    this.targetCharacterId,
    this.targetIdentityPrompt = '',
    this.rules = const [],
  });
}

class ScriptScenePromptReplacement {
  final String id;
  final String label;
  final List<ScriptPromptReplacementRule> rules;

  const ScriptScenePromptReplacement({
    required this.id,
    required this.label,
    this.rules = const [],
  });
}
```

Add `fromJson`, `copyWith`, and `toJson` for these classes using the existing model style. Add `rolePromptReplacements` and `scenePromptReplacements` to `RecastMapping`. Keep old `roleAssemblies` readable for legacy caches, but make new writes use the replacement lists once they are populated.

- [ ] **Step 4: Run the model tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_recast_model_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/studio/models/script_recast.dart test/data/studio/models/script_recast_model_test.dart
git commit -m "feat: add script prompt replacement mapping models"
```

---

### Task 2: Extend AI Extraction With Role And Scene Terms

**Files:**
- Modify: `lib/data/studio/models/script_ai_role_extraction.dart`
- Modify: `lib/data/studio/services/script_ai_role_extraction_parser.dart`
- Modify: `lib/data/studio/services/script_ai_role_extraction_client.dart`
- Modify: `test/data/studio/models/script_ai_role_extraction_test.dart`
- Modify: `test/data/studio/services/script_ai_role_extraction_parser_test.dart`

- [ ] **Step 1: Write failing tests for scene terms and role term categories**

Add a parser test with JSON shaped like:

```dart
const raw = '''
{
  "status": "ready",
  "roles": [
    {
      "source_role_id": "slot-0",
      "display_name": "alice",
      "prompt_terms": [
        {
          "id": "slot-0-identity-alice",
          "text": "alice (wonder story)",
          "category": "identity",
          "source_phrase": "alice (wonder story), brown hair",
          "frame_indexes": [1, 2, 3]
        },
        {
          "id": "slot-0-clothing-jacket",
          "text": "red jacket",
          "category": "clothing",
          "source_phrase": "wearing a red jacket and black skirt",
          "frame_indexes": [1, 2, 3]
        }
      ]
    }
  ],
  "scene_terms": [
    {
      "id": "scene-rainy-street",
      "text": "rainy city street",
      "category": "scene",
      "source_phrase": "in a rainy city street at night",
      "source_location": "base prompt",
      "frame_indexes": [1, 2]
    }
  ]
}
''';
```

Assert that role terms and scene terms are parsed separately, and assert that `1girl` and `solo` are absent when they are not emitted as role/scene terms.

- [ ] **Step 2: Run parser/model tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_ai_role_extraction_test.dart test/data/studio/services/script_ai_role_extraction_parser_test.dart -r expanded
```

Expected: compile failure or empty parsed scene terms.

- [ ] **Step 3: Add extracted prompt term models**

Add a model class in `script_ai_role_extraction.dart`:

```dart
class ScriptAiExtractedPromptTerm {
  final String id;
  final String text;
  final ScriptPromptReplacementCategory category;
  final String sourcePhrase;
  final String sourceLocation;
  final List<int> frameIndexes;

  const ScriptAiExtractedPromptTerm({
    required this.id,
    required this.text,
    required this.category,
    this.sourcePhrase = '',
    this.sourceLocation = '',
    this.frameIndexes = const [],
  });
}
```

Add `promptTerms` to `ScriptAiExtractedRole` and `sceneTerms` to `ScriptAiRoleExtraction`. Parser input keys:

- Role terms: `prompt_terms`, fallback `promptTerms`.
- Scene terms: `scene_terms`, fallback `sceneTerms`.
- Category strings: `identity`, `body`, `clothing`, `clothing_state`, `accessory`, `scene`.

- [ ] **Step 4: Update the AI extraction prompt contract**

In `script_ai_role_extraction_client.dart`, update the system/user prompt so the AI returns:

- Role terms only for character identity, character body/appearance, clothing, clothing state, and accessories.
- Scene terms only for environment/place/time/lighting/weather/background objects.
- No count/composition/action/quality terms such as `1girl`, `solo`, `looking at viewer`, `masterpiece`.
- Exact source phrases and frame indexes for each term.

Keep tests fake-only; do not call user-configured APIs.

- [ ] **Step 5: Run parser/model tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_ai_role_extraction_test.dart test/data/studio/services/script_ai_role_extraction_parser_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/data/studio/models/script_ai_role_extraction.dart lib/data/studio/services/script_ai_role_extraction_parser.dart lib/data/studio/services/script_ai_role_extraction_client.dart test/data/studio/models/script_ai_role_extraction_test.dart test/data/studio/services/script_ai_role_extraction_parser_test.dart
git commit -m "feat: extract role and scene prompt terms"
```

---

### Task 3: Build Exact Prompt Replacement Engine

**Files:**
- Create: `lib/data/studio/services/script_prompt_replacement_engine.dart`
- Create: `test/data/studio/services/script_prompt_replacement_engine_test.dart`

- [ ] **Step 1: Write failing engine tests**

Cover exact token replacement, non-substring matching, explicit delete, and match modes:

```dart
test('replaces exact comma token without touching 1girl', () {
  const engine = ScriptPromptReplacementEngine();
  const rule = ScriptPromptReplacementRule(
    id: 'rule-girl',
    sourceTerms: [
      ScriptPromptReplacementTerm(
        id: 'term-girl',
        text: 'girl',
        category: ScriptPromptReplacementCategory.identity,
      ),
    ],
    action: ScriptPromptReplacementAction.replace,
    targetPrompt: 'lily',
  );

  final result = engine.applyRules(
    prompt: '1girl, girl, solo',
    frameIndex: 1,
    rules: [rule],
  );

  expect(result, '1girl, lily, solo');
});

test('delete requires explicit delete action', () {
  const engine = ScriptPromptReplacementEngine();
  const blankRule = ScriptPromptReplacementRule(
    id: 'blank',
    sourceTerms: [
      ScriptPromptReplacementTerm(
        id: 'term-glasses',
        text: 'round glasses',
        category: ScriptPromptReplacementCategory.accessory,
      ),
    ],
  );
  const deleteRule = ScriptPromptReplacementRule(
    id: 'delete',
    sourceTerms: [
      ScriptPromptReplacementTerm(
        id: 'term-glasses',
        text: 'round glasses',
        category: ScriptPromptReplacementCategory.accessory,
      ),
    ],
    action: ScriptPromptReplacementAction.delete,
  );

  expect(
    engine.applyRules(
      prompt: 'round glasses, brown hair',
      frameIndex: 1,
      rules: [blankRule],
    ),
    'round glasses, brown hair',
  );
  expect(
    engine.applyRules(
      prompt: 'round glasses, brown hair',
      frameIndex: 1,
      rules: [deleteRule],
    ),
    'brown hair',
  );
});
```

- [ ] **Step 2: Run the new engine tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_prompt_replacement_engine_test.dart -r expanded
```

Expected: compile failure because the engine file does not exist.

- [ ] **Step 3: Implement the engine**

Implement this public API:

```dart
class ScriptPromptReplacementEngine {
  const ScriptPromptReplacementEngine();

  String applyRules({
    required String prompt,
    required int frameIndex,
    required List<ScriptPromptReplacementRule> rules,
  }) {
    var current = prompt;
    for (final rule in rules) {
      if (!_ruleAppliesToFrame(rule, frameIndex)) {
        continue;
      }
      current = _applyRule(current, rule);
    }
    return sanitizeGenerationPrompt(current);
  }
}
```

Rules:

- Split prompts with `PromptTagProcessor.splitWorkshopTags`.
- Compare by `PromptTagProcessor.normalizeMatchKey`.
- Never use substring matching.
- `any`: at least one included source term must be present.
- `all`: every included source term must be present.
- `anchor`: `anchorTermId` when present, otherwise first included source term.
- Frame indexes restrict rule application when any included source term has non-empty `frameIndexes`.
- `none`: no mutation.
- `replace`: remove matched source terms and append `manualPhrase` if non-empty, otherwise `targetPrompt`.
- `delete`: remove matched source terms and append nothing.

- [ ] **Step 4: Run the engine tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_prompt_replacement_engine_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/studio/services/script_prompt_replacement_engine.dart test/data/studio/services/script_prompt_replacement_engine_test.dart
git commit -m "feat: add exact script prompt replacement engine"
```

---

### Task 4: Convert AI Extraction Into Replacement Groups

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_assembly_application.dart`
- Modify: `test/data/studio/services/script_ai_role_assembly_application_test.dart`

- [ ] **Step 1: Write failing application tests**

Add tests that prove AI role terms become role replacement rules and scene terms become scene replacement rules:

```dart
test('applies AI role and scene terms as replacement groups', () {
  const application = ScriptAiRoleAssemblyApplication();
  const extraction = ScriptAiRoleExtraction(
    status: ScriptAiRoleExtractionStatus.ready,
    roles: [
      ScriptAiExtractedRole(
        sourceRoleId: 'slot-0',
        displayName: 'alice',
        promptTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'term-red-jacket',
            text: 'red jacket',
            category: ScriptPromptReplacementCategory.clothing,
            frameIndexes: [1, 2],
          ),
        ],
      ),
    ],
    sceneTerms: [
      ScriptAiExtractedPromptTerm(
        id: 'term-night',
        text: 'night',
        category: ScriptPromptReplacementCategory.scene,
        sourceLocation: 'base prompt',
        frameIndexes: [1, 2],
      ),
    ],
  );

  final result = application.apply(
    mapping: RecastMapping.defaults('script-1'),
    extraction: extraction,
    stageLabelFor: (_, __) => 'unused',
  );

  expect(result.mapping.rolePromptReplacements.single.sourceRoleId, 'slot-0');
  expect(result.mapping.rolePromptReplacements.single.rules.single
      .sourceTerms.single.text, 'red jacket');
  expect(result.mapping.scenePromptReplacements.single.rules.single
      .sourceTerms.single.text, 'night');
});
```

- [ ] **Step 2: Run application tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_ai_role_assembly_application_test.dart -r expanded
```

Expected: missing or empty replacement groups.

- [ ] **Step 3: Implement conversion while preserving user edits**

Update `ScriptAiRoleAssemblyApplication.apply`:

- If new replacement groups already exist, merge AI source terms by stable rule id and keep user target fields.
- Stable role rule id: `role-$sourceRoleId-${term.id}` for single terms and `role-$sourceRoleId-phrase-${safeSourcePhrase}` when AI groups multiple terms from the same phrase.
- Stable scene rule id: `scene-${term.id}` for single terms and `scene-phrase-${safeSourcePhrase}` for phrases.
- Keep `targetPrompt`, `manualPhrase`, `action`, `matchMode`, `excludedTermIds`, `targetCharacterId`, and `targetIdentityPrompt`.
- Do not create a combined "all" group.

- [ ] **Step 4: Run application tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_ai_role_assembly_application_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/studio/services/script_ai_role_assembly_application.dart test/data/studio/services/script_ai_role_assembly_application_test.dart
git commit -m "feat: materialize AI prompt terms as replacement groups"
```

---

### Task 5: Wire Replacement Rules Into Script Recast Engine

**Files:**
- Modify: `lib/data/studio/services/script_recast_engine.dart`
- Modify: `test/data/studio/services/script_recast_engine_test.dart`

- [ ] **Step 1: Write failing recast engine tests**

Add one role replacement test and one scene replacement test:

```dart
test('role prompt replacements mutate only matching character captions', () async {
  final result = await engine.resolvePayloadsAsync(
    script: scriptWithTwoFrames(
      charCaptions: [
        ['alice, red jacket, black skirt'],
        ['alice, blue coat'],
      ],
      baseCaptions: ['rainy city street', 'rainy city street'],
    ),
    mapping: RecastMapping(
      id: 'mapping-script',
      scriptId: 'script',
      rolePromptReplacements: const [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          targetIdentityPrompt: 'lily, silver hair',
          rules: [
            ScriptPromptReplacementRule(
              id: 'rule-outfit',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'term-red-jacket',
                  text: 'red jacket',
                  category: ScriptPromptReplacementCategory.clothing,
                  frameIndexes: [1],
                ),
              ],
              action: ScriptPromptReplacementAction.replace,
              targetPrompt: 'white dress',
            ),
          ],
        ),
      ],
    ),
  );

  expect(characterCaption(result, frame: 1, slot: 0),
      contains('white dress'));
  expect(characterCaption(result, frame: 1, slot: 0),
      isNot(contains('red jacket')));
  expect(characterCaption(result, frame: 2, slot: 0), contains('blue coat'));
});

test('scene prompt replacements mutate base caption separately', () async {
  final result = await engine.resolvePayloadsAsync(
    script: scriptWithTwoFrames(
      charCaptions: [
        ['alice, red jacket'],
        ['alice, red jacket'],
      ],
      baseCaptions: ['rainy city street, night', 'warm indoor light'],
    ),
    mapping: RecastMapping(
      id: 'mapping-script',
      scriptId: 'script',
      scenePromptReplacements: const [
        ScriptScenePromptReplacement(
          id: 'scene-base',
          label: 'base prompt',
          rules: [
            ScriptPromptReplacementRule(
              id: 'rule-night',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'term-night',
                  text: 'night',
                  category: ScriptPromptReplacementCategory.scene,
                  frameIndexes: [1],
                ),
              ],
              action: ScriptPromptReplacementAction.delete,
            ),
          ],
        ),
      ],
    ),
  );

  expect(baseCaption(result, frame: 1), 'rainy city street');
  expect(baseCaption(result, frame: 2), 'warm indoor light');
});
```

- [ ] **Step 2: Run recast engine tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_recast_engine_test.dart -r expanded
```

Expected: role/scene replacements are not applied yet.

- [ ] **Step 3: Apply replacement rules in the engine**

In `script_recast_engine.dart`:

- Construct one `ScriptPromptReplacementEngine` inside `ScriptRecastEngine`.
- Apply role replacement rules after source char captions are read and before artist/global writes.
- Apply scene replacement rules to `baseCaption`.
- Keep the old `roleAssemblies` path only when `rolePromptReplacements` is empty, so old caches can still render during the transition.
- When `targetIdentityPrompt` is non-empty, apply it as an identity replacement rule for the role group. Do not infer identity from `1girl`, `solo`, or generic count terms.

- [ ] **Step 4: Run recast engine tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_recast_engine_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/studio/services/script_recast_engine.dart test/data/studio/services/script_recast_engine_test.dart
git commit -m "feat: apply role and scene prompt replacement rules"
```

---

### Task 6: Replace ViewModel Stage State With Rule State

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing view model/widget-facing tests**

Add tests through `StudioScriptViewModel` that cover:

- Role and scene mappings are exposed separately.
- No `stageItems` are needed for replacement editing.
- Dropping a character fills `targetIdentityPrompt`.
- Editing a rule target sets action to `replace`.
- Toggling delete sets action to `delete`.
- Merging selected role rules produces one rule with combined source terms.

Use fake cache data with `rolePromptReplacements` and `scenePromptReplacements`.

- [ ] **Step 2: Run focused UI/view model tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "script prompt replacement" -r expanded
```

Expected: missing view model fields and methods.

- [ ] **Step 3: Add replacement view items**

Add view model items:

```dart
class StudioScriptReplacementRuleItem {
  final String id;
  final List<ScriptPromptReplacementTerm> sourceTerms;
  final List<String> excludedTermIds;
  final ScriptPromptReplacementAction action;
  final ScriptPromptReplacementMatchMode matchMode;
  final String targetPrompt;
  final String manualPhrase;
  final bool selected;

  const StudioScriptReplacementRuleItem({
    required this.id,
    this.sourceTerms = const [],
    this.excludedTermIds = const [],
    this.action = ScriptPromptReplacementAction.none,
    this.matchMode = ScriptPromptReplacementMatchMode.any,
    this.targetPrompt = '',
    this.manualPhrase = '',
    this.selected = false,
  });
}

class StudioScriptRoleReplacementItem {
  final String sourceRoleId;
  final String sourceLabel;
  final String sourcePreview;
  final String? targetCharacterId;
  final String targetIdentityPrompt;
  final List<StudioScriptReplacementRuleItem> rules;

  const StudioScriptRoleReplacementItem({
    required this.sourceRoleId,
    required this.sourceLabel,
    this.sourcePreview = '',
    this.targetCharacterId,
    this.targetIdentityPrompt = '',
    this.rules = const [],
  });
}

class StudioScriptSceneReplacementItem {
  final String id;
  final String label;
  final List<StudioScriptReplacementRuleItem> rules;

  const StudioScriptSceneReplacementItem({
    required this.id,
    required this.label,
    this.rules = const [],
  });
}
```

Expose:

```dart
List<StudioScriptRoleReplacementItem> roleReplacementMappings = const [];
List<StudioScriptSceneReplacementItem> sceneReplacementMappings = const [];
```

- [ ] **Step 4: Add mutation methods**

Add methods with these responsibilities:

- `setRoleReplacementTargetCharacter(String sourceRoleId, String characterId)`
- `setRoleReplacementIdentityPrompt(String sourceRoleId, String value)`
- `setRoleReplacementRuleTarget(String sourceRoleId, String ruleId, String value)`
- `setRoleReplacementRuleDeleted(String sourceRoleId, String ruleId, bool deleted)`
- `setRoleReplacementRuleMatchMode(String sourceRoleId, String ruleId, ScriptPromptReplacementMatchMode mode)`
- `setRoleReplacementRuleTermExcluded(String sourceRoleId, String ruleId, String termId, bool excluded)`
- `mergeSelectedRoleReplacementRules(String sourceRoleId)`
- `syncRoleReplacementTargetToSelectedRules(String sourceRoleId)`
- `setSceneReplacementRuleTarget(String groupId, String ruleId, String value)`
- `setSceneReplacementRuleDeleted(String groupId, String ruleId, bool deleted)`
- `mergeSelectedSceneReplacementRules(String groupId)`

Each method updates `currentCache.mapping`, refreshes the view item lists, and saves with `_saveCurrentCache()`.

- [ ] **Step 5: Run focused tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "script prompt replacement" -r expanded
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/studio_script/view_models/studio_script_viewmodel.dart test/ui/studio_script/studio_script_page_test.dart
git commit -m "feat: expose script replacement rule state"
```

---

### Task 7: Rebuild Role And Scene UI As Separate Sections

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Modify: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing widget tests for the new interaction**

Add widget tests that assert:

- Role replacement section exists.
- Scene replacement section exists.
- There is no visible `全部` filter inside replacement editing.
- Character card drop/click fills the role identity area.
- Scene rules appear only in the scene section.
- Source-to-target copy works on a rule row.
- `PromptTagEditor` still backs target editing.

- [ ] **Step 2: Run widget tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "role and scene replacement sections" -r expanded
```

Expected: old stage UI is still rendered.

- [ ] **Step 3: Replace the role card body**

In `_RoleMappingCard`:

- Remove `_RoleStageSelector`.
- Remove stage rename, edit frames, delete stage, upper outfit, and lower outfit UI.
- Keep the role card shell, source label, source preview, and drag target.
- Add a `目标身份` drop area that accepts character cards and writes all target identity tags into `targetIdentityPrompt`.
- Render a role rule list with source chips on the left and target editor on the right.

- [ ] **Step 4: Add the scene replacement section**

Add `_SceneReplacementSection` beside or below role replacements:

- It receives `List<StudioScriptSceneReplacementItem>`.
- It uses the same row widget as role rules.
- It does not accept character cards.
- It accepts tag drops into target editors.
- It has merge selected rows and clear selection actions.

- [ ] **Step 5: Extract reusable rule-row widgets**

Create private widgets in `studio_script_page.dart`:

- `_ScriptReplacementRuleList`
- `_ScriptReplacementRuleRow`
- `_ScriptReplacementSourceCell`
- `_ScriptReplacementTargetCell`
- `_ScriptReplacementModeSelector`

Reuse `PromptTagDisplay`, `PromptTagEditor`, and `PromptTagSelectionController`. Keep selection rectangle behavior from `_RolePromptComparePanelState`.

- [ ] **Step 6: Run widget tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "role and scene replacement sections" -r expanded
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add lib/ui/studio_script/widgets/studio_script_page.dart test/ui/studio_script/studio_script_page_test.dart
git commit -m "feat: separate role and scene replacement UI"
```

---

### Task 8: Preserve Quick Sync, Tag Editing, And Drag Adjustment

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing interaction tests**

Add tests for:

- Quick sync target identity to selected role rules.
- Dragging tags from source to target does not remove the source chip when the drag came from the same rule source.
- Dragging tags from another editable field removes from the source when existing `PromptTagEditor` rules say it should.
- Reordering tags inside target editor still changes target prompt order.
- Scene target editor supports dropped tags from tag assets.

- [ ] **Step 2: Run interaction tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "replacement interactions" -r expanded
```

Expected: missing quick sync or drag callbacks.

- [ ] **Step 3: Reuse existing interaction callbacks**

Wire the new replacement rows to existing mechanics:

- Use `PromptTagDropBatch` for batched tag drops.
- Use `PromptTagSelectionController` for source and target selection.
- Use the same `_shouldRemoveDroppedTagsFromSource` rule as `_ReplacementCompareCellState`.
- Keep `_SourceToTargetCopyButton` behavior as rule-level copy.
- Keep `Draggable<_ScriptAssetDragData>` from the asset drawer.

- [ ] **Step 4: Run interaction tests and confirm they pass**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "replacement interactions" -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/studio_script/widgets/studio_script_page.dart lib/ui/studio_script/view_models/studio_script_viewmodel.dart test/ui/studio_script/studio_script_page_test.dart
git commit -m "feat: preserve replacement tag and drag interactions"
```

---

### Task 9: Remove Obsolete Stage-Centric UI Tests And Update Acceptance

**Files:**
- Modify: `test/ui/studio_script/studio_script_stage_label_test.dart`
- Modify: `test/ui/studio_script/studio_script_page_test.dart`
- Modify: `test/integration/script_recast_acceptance_test.dart`
- Modify: `test/integration/script_recast_acceptance_smoke_test.dart`

- [ ] **Step 1: Rewrite old stage expectations**

Replace assertions for these old keys:

- `script-ai-role-stage-tab-*`
- `role-stage-*`
- `role-rename-stage-*`
- `role-edit-stage-frames-*`
- `role-copy-target-to-all-outfits-*`

with assertions for:

- `role-replacement-card-$sourceRoleId`
- `role-replacement-identity-drop-$sourceRoleId`
- `role-replacement-rule-$sourceRoleId-$ruleId`
- `scene-replacement-section`
- `scene-replacement-rule-$groupId-$ruleId`

- [ ] **Step 2: Run affected tests and confirm failures are gone**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_stage_label_test.dart test/ui/studio_script/studio_script_page_test.dart -r expanded
```

Expected: PASS after obsolete stage tests are rewritten or removed.

- [ ] **Step 3: Run recast acceptance tests**

Run:

```powershell
flutter test --no-pub test/integration/script_recast_acceptance_test.dart test/integration/script_recast_acceptance_smoke_test.dart -r expanded
```

Expected: PASS. No project API calls are made by these tests.

- [ ] **Step 4: Commit**

```powershell
git add test/ui/studio_script/studio_script_stage_label_test.dart test/ui/studio_script/studio_script_page_test.dart test/integration/script_recast_acceptance_test.dart test/integration/script_recast_acceptance_smoke_test.dart
git commit -m "test: update script replacement workflow coverage"
```

---

### Task 10: Final Verification And Prototype Cleanup

**Files:**
- Modify or delete: `docs/prototypes/script-replacement-table-prototype/`
- Modify: `docs/superpowers/plans/2026-06-14-script-prompt-replacement-mapping-redesign.md`

- [ ] **Step 1: Decide prototype fate**

If the formal UI is implemented and verified, delete the prototype directory:

```powershell
Remove-Item -LiteralPath 'docs/prototypes/script-replacement-table-prototype' -Recurse
```

If the prototype is still useful as a visual reference during review, keep it until the next checkpoint and do not ship it as product code.

- [ ] **Step 2: Run focused regression suite**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_recast_model_test.dart test/data/studio/models/script_ai_role_extraction_test.dart test/data/studio/services/script_prompt_replacement_engine_test.dart test/data/studio/services/script_ai_role_assembly_application_test.dart test/data/studio/services/script_recast_engine_test.dart test/ui/studio_script/studio_script_page_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 4: Manual UI smoke**

Run the app, open the script workbench, and verify:

- Role replacement and scene replacement are separate.
- No "全部" filter is shown in the replacement sections.
- Dropping a character card fills target identity.
- Filling target text replaces the matching source term.
- Empty target keeps the source unchanged.
- Delete button explicitly deletes the source term.
- Merge selected rows produces one rule.
- Prompt tag editor still supports drag/reorder.

- [ ] **Step 5: Commit cleanup**

```powershell
git add docs/superpowers/plans/2026-06-14-script-prompt-replacement-mapping-redesign.md docs/prototypes/script-replacement-table-prototype
git commit -m "docs: finalize script replacement mapping plan"
```

---

## Self-Review

- Spec coverage:
  - Role and scene are formally separate: Tasks 1, 4, 6, and 7.
  - No "全部" filter: Task 7.
  - Clean old mapping system: Tasks 1, 5, 6, 7, and 9.
  - Reuse quick sync: Tasks 6 and 8.
  - Reuse tag system: Tasks 7 and 8.
  - Reuse drag adjustment: Tasks 7 and 8.
  - Exact point-to-point replacement: Tasks 3 and 5.
  - Empty target means no replacement, explicit delete means delete: Tasks 1, 3, and 7.
  - Avoid `1girl` / `girl` substring mistakes: Task 3.
  - Natural language source evidence and manual phrase override: Tasks 1, 2, 3, and 7.
  - Scene replacement groundwork: Tasks 2, 4, 5, 6, and 7.
- Placeholder scan: no deferred implementation placeholders remain.
- Type consistency:
  - Stored model uses `ScriptPromptReplacementRule`.
  - AI model uses `ScriptAiExtractedPromptTerm`.
  - UI model uses `StudioScriptReplacementRuleItem`.
  - Engine uses `ScriptPromptReplacementEngine.applyRules`.
