# Script Recast Role Term Category Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split Script Recast role replacement terms into precise AI-driven categories so terms like `inverted nipples` enter the replacement area as `upperBody`, while clothing/exposure states like `no panties` and `strap slip` appear under a separate `clothingState` group.

**Architecture:** Extend the shared `PromptTagCategory` taxonomy with `accessory` and `clothingState`, keep legacy category parsing compatible, and update the project AI contract to emit the new categories directly. UI grouping should read the persisted category values instead of collapsing accessories and clothing states into one mixed `clothing` bucket.

**Tech Stack:** Flutter/Dart, existing `PromptTagCategory`, `ScriptAiRoleExtraction`, `RecastMapping`, Script Recast view model/page tests, local Node audit tooling. No project API, NAI token, proxy, or stored credential may be used for cache repair or verification.

## Global Constraints

- Do not use local semantic rules as the source of truth for whether a term enters the replacement area.
- AI receives complete `source_terms`; AI/Codex decides role prompt terms, scene terms, category, and cache suggestions.
- Existing manual/user-confirmed mappings, target prompts, match modes, and actions must be preserved.
- Existing manual/user-confirmed translation/classification cache entries must not be overwritten.
- `clothing_state` and `clothingState` legacy strings must parse as the new `PromptTagCategory.clothingState`.
- `accessory` legacy strings must parse as the new `PromptTagCategory.accessory`.
- `inverted nipples`, `large breasts`, and `small breasts` must classify as `upperBody`.
- `no panties`, `strap slip`, `completely nude`, and clothing pull/lift/remove terms must classify as `clothingState`.
- Codex offline work must not call project-configured API endpoints, NAI tokens, proxies, or stored credentials.

---

## File Structure

- `lib/data/studio/tools/prompt_tag_classifier.dart`: owns `PromptTagCategory`, classifier rules, group definitions, and classification cache merge semantics.
- `lib/data/studio/models/script_recast.dart`: owns persisted replacement category parsing for mapping source terms.
- `lib/data/studio/models/script_ai_role_extraction.dart`: owns AI prompt term parsing/serialization and category aliases through `promptTagCategoryFromReplacementValue`.
- `lib/data/studio/services/script_ai_role_extraction_client.dart`: owns the AI prompt contract and examples.
- `lib/ui/studio_script/widgets/studio_script_page.dart`: owns visible replacement rule grouping and labels.
- `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`: owns category-to-role-part routing used by UI edit/materialization helpers.
- `tool/script_recast_complete_term_repair_schema.md`: documents offline schema category names.
- `test/data/studio/tools/prompt_tag_classifier_test.dart`: classifier and cache tests.
- `test/data/studio/models/script_ai_role_extraction_test.dart`: AI model parsing and serialization tests.
- `test/data/studio/models/script_recast_model_test.dart`: replacement mapping category round-trip tests.
- `test/data/studio/services/script_ai_role_extraction_client_test.dart`: prompt contract tests.
- `test/ui/studio_script/studio_script_page_test.dart`: visible replacement grouping tests.

---

### Task 1: Add Precise PromptTagCategory Values And Legacy Parsing

**Files:**
- Modify: `lib/data/studio/tools/prompt_tag_classifier.dart`
- Modify: `lib/data/studio/models/script_recast.dart`
- Test: `test/data/studio/models/script_ai_role_extraction_test.dart`
- Test: `test/data/studio/models/script_recast_model_test.dart`

**Interfaces:**
- Produces: `PromptTagCategory.accessory`
- Produces: `PromptTagCategory.clothingState`
- Preserves: `promptTagCategoryFromReplacementValue(Object? value, {required PromptTagCategory fallback})`
- Consumes: existing category strings from JSON and AI output.

- [ ] **Step 1: Write failing AI category alias test**

Add this test to `test/data/studio/models/script_ai_role_extraction_test.dart` near the existing prompt term category parsing tests:

```dart
test('prompt term category parsing keeps accessory and clothing state distinct',
    () {
  final accessory = ScriptAiExtractedPromptTerm.fromJson({
    'text': 'black collar',
    'category': 'accessory',
  });
  final snakeState = ScriptAiExtractedPromptTerm.fromJson({
    'text': 'strap slip',
    'category': 'clothing_state',
  });
  final camelState = ScriptAiExtractedPromptTerm.fromJson({
    'text': 'no panties',
    'category': 'clothingState',
  });

  expect(accessory.category, PromptTagCategory.accessory);
  expect(snakeState.category, PromptTagCategory.clothingState);
  expect(camelState.category, PromptTagCategory.clothingState);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test --no-pub test\data\studio\models\script_ai_role_extraction_test.dart --plain-name "prompt term category parsing keeps accessory and clothing state distinct" --reporter expanded
```

Expected: FAIL because `PromptTagCategory.accessory` and `PromptTagCategory.clothingState` do not exist yet.

- [ ] **Step 3: Add enum values**

In `lib/data/studio/tools/prompt_tag_classifier.dart`, change the enum to:

```dart
enum PromptTagCategory {
  character,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
  accessory,
  clothingState,
  clothing,
  action,
  scene,
  camera,
  artist,
  style,
  quality,
  negativeQuality,
  negativeBody,
  negativeArtist,
  negativeContent,
  promptSyntax,
  other,
}
```

Keep `clothing` for legacy/generic persisted values. Do not delete it in this task.

- [ ] **Step 4: Update replacement category parser**

In `lib/data/studio/models/script_recast.dart`, update `promptTagCategoryFromReplacementValue`:

```dart
switch (key) {
  case 'identity':
    return PromptTagCategory.character;
  case 'body':
    return PromptTagCategory.upperBody;
  case 'clothingstate':
    return PromptTagCategory.clothingState;
  case 'accessory':
    return PromptTagCategory.accessory;
  case 'clothing':
    return PromptTagCategory.clothing;
  case 'scene':
    return PromptTagCategory.scene;
}
```

Do not map `accessory` or `clothingState` back to `clothing`.

- [ ] **Step 5: Update existing category alias test expectations**

In `test/data/studio/models/script_ai_role_extraction_test.dart`, update the existing `prompt term category parsing accepts clothing state aliases` test so it expects `PromptTagCategory.clothingState` instead of `PromptTagCategory.clothing`.

- [ ] **Step 6: Add mapping round-trip test**

Add this test to `test/data/studio/models/script_recast_model_test.dart`:

```dart
test('replacement term categories preserve accessory and clothingState', () {
  final mapping = RecastMapping.fromJson({
    'id': 'mapping-a',
    'scriptId': 'script-a',
    'roleSwaps': [],
    'artistSwap': null,
    'rolePromptReplacements': [
      {
        'sourceRoleId': 'slot-0',
        'displayLabel': 'Role',
        'rules': [
          {
            'id': 'rule-accessory',
            'sourceTerms': [
              {
                'id': 'term-collar',
                'text': 'black collar',
                'category': 'accessory',
              },
            ],
          },
          {
            'id': 'rule-state',
            'sourceTerms': [
              {
                'id': 'term-strap-slip',
                'text': 'strap slip',
                'category': 'clothing_state',
              },
            ],
          },
        ],
      },
    ],
  });

  final terms = mapping.rolePromptReplacements.single.rules
      .expand((rule) => rule.sourceTerms)
      .toList();
  expect(terms[0].category, PromptTagCategory.accessory);
  expect(terms[1].category, PromptTagCategory.clothingState);
  expect(
    mapping.toJson()['rolePromptReplacements'][0]['rules'][0]['sourceTerms'][0]
        ['category'],
    'accessory',
  );
  expect(
    mapping.toJson()['rolePromptReplacements'][0]['rules'][1]['sourceTerms'][0]
        ['category'],
    'clothingState',
  );
});
```

- [ ] **Step 7: Run task tests**

Run:

```powershell
flutter test --no-pub test\data\studio\models\script_ai_role_extraction_test.dart test\data\studio\models\script_recast_model_test.dart --reporter expanded
```

Expected: PASS.

---

### Task 2: Update Local Classification Hints And Cache Suggestions

**Files:**
- Modify: `lib/data/studio/tools/prompt_tag_classifier.dart`
- Test: `test/data/studio/tools/prompt_tag_classifier_test.dart`

**Interfaces:**
- Consumes: `PromptTagClassifier.classify(String tag, {bool negative, PromptTagClassificationCache? cache})`
- Produces: rule-derived classifications for UI hints and cache suggestions only.
- Does not produce: replacement membership decisions.

- [ ] **Step 1: Write failing classifier tests**

Add these tests to `test/data/studio/tools/prompt_tag_classifier_test.dart`:

```dart
test('classifies explicit upper body traits as upperBody', () {
  expect(
    PromptTagClassifier.classify('inverted nipples').category,
    PromptTagCategory.upperBody,
  );
  expect(
    PromptTagClassifier.classify('large breasts').category,
    PromptTagCategory.upperBody,
  );
  expect(
    PromptTagClassifier.classify('small breasts').category,
    PromptTagCategory.upperBody,
  );
});

test('classifies accessories separately from clothing state', () {
  expect(
    PromptTagClassifier.classify('black collar').category,
    PromptTagCategory.accessory,
  );
  expect(
    PromptTagClassifier.classify('animal collar').category,
    PromptTagCategory.accessory,
  );
  expect(
    PromptTagClassifier.classify('strap slip').category,
    PromptTagCategory.clothingState,
  );
  expect(
    PromptTagClassifier.classify('no panties').category,
    PromptTagCategory.clothingState,
  );
  expect(
    PromptTagClassifier.classify('completely nude').category,
    PromptTagCategory.clothingState,
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```powershell
flutter test --no-pub test\data\studio\tools\prompt_tag_classifier_test.dart --plain-name "classifies explicit upper body traits as upperBody" --reporter expanded
flutter test --no-pub test\data\studio\tools\prompt_tag_classifier_test.dart --plain-name "classifies accessories separately from clothing state" --reporter expanded
```

Expected: FAIL until classifier words and enum handling are updated.

- [ ] **Step 3: Update classifier group definitions**

In `PromptTagClassifier.groups`, keep the coarse groups for existing generic prompt UI but add the new categories:

```dart
PromptTagGroup(
  id: 'clothing',
  label: '服装/身体',
  categories: [
    PromptTagCategory.upperBody,
    PromptTagCategory.lowerBody,
    PromptTagCategory.upperClothing,
    PromptTagCategory.lowerClothing,
    PromptTagCategory.accessory,
    PromptTagCategory.clothingState,
    PromptTagCategory.clothing,
    PromptTagCategory.negativeBody,
  ],
),
```

In `PromptTagClassifier.layeredGroups`, split them:

```dart
PromptTagGroup(
  id: 'accessory',
  label: '饰品',
  categories: [PromptTagCategory.accessory],
),
PromptTagGroup(
  id: 'clothingState',
  label: '服装状态/动作',
  categories: [PromptTagCategory.clothingState],
),
PromptTagGroup(
  id: 'clothing',
  label: '其它服装',
  categories: [PromptTagCategory.clothing, PromptTagCategory.negativeBody],
),
```

- [ ] **Step 4: Add classifier word lists**

In `lib/data/studio/tools/prompt_tag_classifier.dart`, add two lists near the existing clothing lists:

```dart
const _accessoryWords = [
  'collar',
  'choker',
  'necklace',
  'earring',
  'earrings',
  'hair ornament',
  'hairclip',
  'hair clip',
  'headband',
  'hairband',
  'crown',
  'bracelet',
  'anklet',
  'glasses',
  'halo',
];

const _clothingStateWords = [
  'strap slip',
  'slipping strap',
  'no panties',
  'topless',
  'bottomless',
  'completely nude',
  'completly nude',
  'nude',
  'naked',
  'shirt lift',
  'clothes lift',
  'dress lift',
  'skirt lift',
  'open clothes',
  'open shirt',
  'open jacket',
  'panties aside',
  'bikini aside',
  'pulling down',
  'pulled down',
  'taking off',
  'take off',
  'undressing',
  'partially undressed',
];
```

Add upper-body explicit terms to `_upperBodyWords`:

```dart
'inverted nipples',
'large breasts',
'small breasts',
'breasts',
'nipples',
'areola',
```

- [ ] **Step 5: Route classifier before generic clothing**

In `_classifyByRules`, insert accessory and clothing state before upper/lower clothing and generic clothing:

```dart
if (_containsAny(key, _upperBodyWords)) {
  return PromptTagCategory.upperBody;
}
if (_containsAny(key, _lowerBodyWords)) {
  return PromptTagCategory.lowerBody;
}
if (_containsAny(key, _accessoryWords)) {
  return PromptTagCategory.accessory;
}
if (_containsAny(key, _clothingStateWords)) {
  return PromptTagCategory.clothingState;
}
if (_containsAny(key, _upperClothingWords)) {
  return PromptTagCategory.upperClothing;
}
```

Keep `_actionWords` later so clothing manipulation goes to `clothingState`, not pure `action`.

- [ ] **Step 6: Run classifier tests**

Run:

```powershell
flutter test --no-pub test\data\studio\tools\prompt_tag_classifier_test.dart --reporter expanded
```

Expected: PASS.

---

### Task 3: Update AI Prompt Contract And Parser Expectations

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_extraction_client.dart`
- Modify: `tool/script_recast_complete_term_repair_schema.md`
- Test: `test/data/studio/services/script_ai_role_extraction_client_test.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_parser_test.dart`

**Interfaces:**
- Consumes: complete `source_terms`.
- Produces: AI prompt that asks for `character`, `upperBody`, `lowerBody`, `upperClothing`, `lowerClothing`, `accessory`, `clothingState`, `other`, and `scene`.

- [ ] **Step 1: Write failing prompt contract assertions**

In `test/data/studio/services/script_ai_role_extraction_client_test.dart`, add expectations to the existing prompt contract test:

```dart
expect(systemPrompt, contains('inverted nipples'));
expect(systemPrompt, contains('large breasts'));
expect(systemPrompt, contains('upperBody'));
expect(systemPrompt, contains('accessory'));
expect(systemPrompt, contains('clothingState'));
expect(systemPrompt, contains('no panties'));
expect(systemPrompt, contains('strap slip'));
expect(systemPrompt, isNot(contains('identity, body, clothing, clothing_state, accessory')));
```

- [ ] **Step 2: Run the prompt contract test**

Run:

```powershell
flutter test --no-pub test\data\studio\services\script_ai_role_extraction_client_test.dart --reporter expanded
```

Expected: FAIL until the prompt text changes.

- [ ] **Step 3: Update AI prompt category instructions**

In `lib/data/studio/services/script_ai_role_extraction_client.dart`, replace the old category wording with:

```text
- For each role, return prompt_terms only for character replacement source terms: character identity, upper-body traits, lower-body traits, worn upper clothing, worn lower clothing, accessories, and replacement-relevant clothingState terms.
- Valid role prompt term category strings are character, upperBody, lowerBody, upperClothing, lowerClothing, accessory, clothingState, and other.
- Use upperBody for head/hair/face/eyes/horns/wings/chest/breasts/nipples/areola/shoulders/arms and explicit upper-body traits such as inverted nipples, large breasts, small breasts, flat chest, or cleavage.
- Use lowerBody for waist/hips/tail/legs/thighs/feet/toes and stable lower-body traits.
- Use accessory for detachable or decorative items such as collar, choker, necklace, hair ornament, halo, bracelet, glasses, or headband.
- Use clothingState for clothing manipulation, body-exposure state, absence state, and garment-position terms the user may replace or delete independently, including no panties, topless, bottomless, completely nude, nude, shirt lift, dress tug, strap slip, open clothes, pulling down panties, panties aside, bikini aside, taking off top, and partially undressed.
- Pure pose/action/expression/camera/background terms such as standing, looking at viewer, smile, blush, holding, grabbing, or side view must be excluded or audited unless they directly describe a replacement-relevant clothing/body exposure state.
```

Update output JSON example category strings from:

```json
"category": "identity, body, clothing, clothing_state, or accessory"
```

to:

```json
"category": "character, upperBody, lowerBody, upperClothing, lowerClothing, accessory, clothingState, or other"
```

- [ ] **Step 4: Update parser fixture**

In `test/data/studio/services/script_ai_role_extraction_parser_test.dart`, update or add a parser fixture that includes:

```json
{
  "id": "term-inverted-nipples",
  "text": "inverted nipples",
  "category": "upperBody",
  "source_phrase": "inverted nipples",
  "frame_indexes": [1]
}
```

and:

```json
{
  "id": "term-strap-slip",
  "text": "strap slip",
  "category": "clothingState",
  "source_phrase": "strap slip",
  "frame_indexes": [1]
}
```

Assert:

```dart
expect(
  extraction.roles.single.promptTerms
      .firstWhere((term) => term.text == 'inverted nipples')
      .category,
  PromptTagCategory.upperBody,
);
expect(
  extraction.roles.single.promptTerms
      .firstWhere((term) => term.text == 'strap slip')
      .category,
  PromptTagCategory.clothingState,
);
```

- [ ] **Step 5: Update offline schema doc**

In `tool/script_recast_complete_term_repair_schema.md`, replace example categories:

```json
"category": "upperBody"
```

and add examples for:

```json
{
  "id": "term-inverted-nipples",
  "text": "inverted nipples",
  "category": "upperBody"
},
{
  "id": "term-strap-slip",
  "text": "strap slip",
  "category": "clothingState"
},
{
  "id": "term-black-collar",
  "text": "black collar",
  "category": "accessory"
}
```

- [ ] **Step 6: Run task tests**

Run:

```powershell
flutter test --no-pub test\data\studio\services\script_ai_role_extraction_client_test.dart test\data\studio\services\script_ai_role_extraction_parser_test.dart --reporter expanded
```

Expected: PASS.

---

### Task 4: Split Role Replacement UI Groups

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

**Interfaces:**
- Consumes: `StudioScriptReplacementRuleItem.sourceTerms`.
- Produces: visible role replacement groups ordered as character, upperBody, lowerBody, upperClothing, lowerClothing, accessory, clothingState, other.

- [ ] **Step 1: Write failing UI grouping test**

Add a widget test to `test/ui/studio_script/studio_script_page_test.dart` near the role replacement UI tests:

```dart
testWidgets('role prompt replacement terms are grouped by precise category',
    (tester) async {
  final viewModel = StudioScriptViewModel()
    ..mapping = RecastMapping(
      id: 'mapping-a',
      scriptId: 'script-a',
      rolePromptReplacements: const [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          displayLabel: 'Role A',
          rules: [
            ScriptPromptReplacementRule(
              id: 'rule-identity',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'term-gyaru',
                  text: 'gyaru',
                  category: PromptTagCategory.character,
                ),
              ],
            ),
            ScriptPromptReplacementRule(
              id: 'rule-upper',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'term-inverted-nipples',
                  text: 'inverted nipples',
                  category: PromptTagCategory.upperBody,
                ),
              ],
            ),
            ScriptPromptReplacementRule(
              id: 'rule-accessory',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'term-collar',
                  text: 'black collar',
                  category: PromptTagCategory.accessory,
                ),
              ],
            ),
            ScriptPromptReplacementRule(
              id: 'rule-state',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'term-no-panties',
                  text: 'no panties',
                  category: PromptTagCategory.clothingState,
                ),
              ],
            ),
          ],
        ),
      ],
    );

  await pumpStudioScriptPage(tester, viewModel: viewModel);

  expect(find.text('角色身份'), findsOneWidget);
  expect(find.text('上身'), findsOneWidget);
  expect(find.text('饰品'), findsOneWidget);
  expect(find.text('服装状态/动作'), findsOneWidget);
  expect(find.text('服装状态/饰品'), findsNothing);
});
```

If this project uses a different test pump helper, adapt only the helper call and keep the assertions.

- [ ] **Step 2: Run UI test to verify it fails**

Run:

```powershell
flutter test --no-pub test\ui\studio_script\studio_script_page_test.dart --plain-name "role prompt replacement terms are grouped by precise category" --reporter expanded
```

Expected: FAIL until UI grouping supports the new categories.

- [ ] **Step 3: Update role replacement group order**

In `lib/ui/studio_script/widgets/studio_script_page.dart`, update `_replacementRuleGroups` role order:

```dart
PromptTagCategory.character,
PromptTagCategory.upperBody,
PromptTagCategory.lowerBody,
PromptTagCategory.upperClothing,
PromptTagCategory.lowerClothing,
PromptTagCategory.accessory,
PromptTagCategory.clothingState,
PromptTagCategory.clothing,
PromptTagCategory.other,
```

Update the exclusion predicate in the trailing dynamic category loop to include `accessory`, `clothingState`, and `clothing`.

- [ ] **Step 4: Update replacement rule category detection**

In `_replacementRuleCategory`, include:

```dart
term.category == PromptTagCategory.accessory ||
term.category == PromptTagCategory.clothingState ||
term.category == PromptTagCategory.clothing
```

Keep `clothing` as legacy fallback.

- [ ] **Step 5: Update role category labels**

In `_replacementRuleCategoryLabel`, return:

```dart
PromptTagCategory.character => '角色身份',
PromptTagCategory.upperBody => '上身',
PromptTagCategory.lowerBody => '下身',
PromptTagCategory.upperClothing => '上装',
PromptTagCategory.lowerClothing => '下装',
PromptTagCategory.accessory => '饰品',
PromptTagCategory.clothingState => '服装状态/动作',
PromptTagCategory.clothing => '其它服装',
_ => '其它角色词',
```

- [ ] **Step 6: Update any token/review labels that show the mixed name**

In `lib/ui/studio_script/widgets/studio_script_page.dart`, replace role replacement labels:

```dart
PromptTagCategory.clothing => '服装状态/饰品'
```

with:

```dart
PromptTagCategory.accessory => '饰品',
PromptTagCategory.clothingState => '服装状态/动作',
PromptTagCategory.clothing => '其它服装',
```

Do not change scene replacement labels in this task.

- [ ] **Step 7: Update view-model category routing**

In `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`, update category routing helpers:

```dart
PromptTagCategory.accessory => StudioScriptRolePart.upperBody,
PromptTagCategory.clothingState => StudioScriptRolePart.upperClothing,
PromptTagCategory.clothing => StudioScriptRolePart.upperClothing,
```

Rationale: role stage five fields do not have an accessory/state field; routing is only for manual materialization helpers. Replacement UI grouping remains category-based and does not depend on this routing.

- [ ] **Step 8: Run UI test**

Run:

```powershell
flutter test --no-pub test\ui\studio_script\studio_script_page_test.dart --plain-name "role prompt replacement terms are grouped by precise category" --reporter expanded
```

Expected: PASS.

---

### Task 5: Preserve Mappings Across Category Migration

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_assembly_application.dart`
- Modify: `tool/normalize_script_recast_ai_cache.dart`
- Test: `test/data/studio/services/script_ai_role_assembly_application_test.dart`
- Test: `test/tool/normalize_script_recast_ai_cache_test.dart`

**Interfaces:**
- Consumes: existing replacement rules with legacy `clothing` category.
- Produces: refreshed source terms with new category while preserving target fields.

- [ ] **Step 1: Write failing assembly merge test**

Add this test to `test/data/studio/services/script_ai_role_assembly_application_test.dart`:

```dart
test('reuses confirmed replacement rule when AI refines legacy clothing category',
    () {
  final result = const ScriptAiRoleAssemblyApplication().apply(
    mapping: RecastMapping(
      id: 'mapping-a',
      scriptId: 'script-a',
      rolePromptReplacements: [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          displayLabel: 'Role',
          rules: [
            ScriptPromptReplacementRule(
              id: 'legacy-state-rule',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'legacy-no-panties',
                  text: 'no panties',
                  category: PromptTagCategory.clothing,
                ),
              ],
              targetPrompt: 'black panties',
            ),
          ],
        ),
      ],
    ),
    extraction: ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.ready,
      roles: [
        ScriptAiExtractedRole(
          sourceRoleId: 'slot-0',
          displayName: 'Role',
          promptTerms: [
            ScriptAiExtractedPromptTerm(
              id: 'term-no-panties',
              text: 'no panties',
              category: PromptTagCategory.clothingState,
              frameIndexes: [1],
            ),
          ],
        ),
      ],
    ),
  );

  final rule = result.mapping.rolePromptReplacements.single.rules.single;
  expect(rule.id, 'legacy-state-rule');
  expect(rule.targetPrompt, 'black panties');
  expect(rule.sourceTerms.single.id, 'term-no-panties');
  expect(rule.sourceTerms.single.category, PromptTagCategory.clothingState);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test --no-pub test\data\studio\services\script_ai_role_assembly_application_test.dart --plain-name "reuses confirmed replacement rule when AI refines legacy clothing category" --reporter expanded
```

Expected: FAIL if merge key still requires category equality.

- [ ] **Step 3: Add compatible replacement term key helper**

In `lib/data/studio/services/script_ai_role_assembly_application.dart`, change rule lookup so legacy `clothing` rules can match refined categories by normalized text. Add:

```dart
String _promptReplacementCompatibleTermKey(
  String text,
  PromptTagCategory category,
) {
  final normalized = PromptTagProcessor.normalizeMatchKey(text);
  if (normalized.isEmpty) return '';
  final categoryKey = switch (category) {
    PromptTagCategory.accessory ||
    PromptTagCategory.clothingState ||
    PromptTagCategory.upperClothing ||
    PromptTagCategory.lowerClothing =>
      'legacy-clothing-compatible',
    _ => category.name,
  };
  return '$categoryKey\u001f$normalized';
}
```

Use this helper only for finding existing user rules. Keep persisted refreshed source term category as the new AI category.

- [ ] **Step 4: Apply same compatibility to normalizer mapping refresh**

In `tool/normalize_script_recast_ai_cache.dart`, update `_promptReplacementTermKey` or add a separate compatible lookup key so existing `clothing` rules match AI `accessory` or `clothingState` terms by normalized text.

Use this behavior only when reusing old rules; do not rewrite unrelated legacy rules.

- [ ] **Step 5: Add normalizer regression fixture**

Add a fixture test to `test/tool/normalize_script_recast_ai_cache_test.dart` that starts with:

```dart
ScriptPromptReplacementRule(
  id: 'legacy-strap-slip-rule',
  sourceTerms: [
    ScriptPromptReplacementTerm(
      id: 'legacy-strap-slip',
      text: 'strap slip',
      category: PromptTagCategory.clothing,
    ),
  ],
  targetPrompt: 'secure straps',
)
```

and AI `promptTerms` containing:

```dart
ScriptAiExtractedPromptTerm(
  id: 'term-strap-slip',
  text: 'strap slip',
  category: PromptTagCategory.clothingState,
  frameIndexes: [1],
)
```

Assert after normalization:

```dart
expect(rule.id, 'legacy-strap-slip-rule');
expect(rule.targetPrompt, 'secure straps');
expect(rule.sourceTerms.single.id, 'term-strap-slip');
expect(rule.sourceTerms.single.category, PromptTagCategory.clothingState);
```

- [ ] **Step 6: Run merge tests**

Run:

```powershell
flutter test --no-pub test\data\studio\services\script_ai_role_assembly_application_test.dart --reporter expanded
dart --packages=.dart_tool/package_config.json tool\normalize_script_recast_ai_cache.dart --cache-dir "$env:TEMP\empty-recast-cache"
```

Expected: assembly tests PASS; normalizer CLI compiles and runs on an empty cache dir. If the full normalizer Flutter test still hangs at the runner layer, record that as a tool-runner issue and rely on targeted fixture plus CLI compile.

---

### Task 6: Update Offline Audit Schema And Tests

**Files:**
- Modify: `tool/script_recast_complete_term_audit.mjs`
- Modify: `tool/script_recast_complete_term_repair_schema.md`
- Test: `test/tool/script_recast_complete_term_audit_test.dart`

**Interfaces:**
- Consumes: explicit offline repair schema categories.
- Produces: dry-run report and schema apply preserving mappings.

- [ ] **Step 1: Write failing offline schema apply test**

In `test/tool/script_recast_complete_term_audit_test.dart`, extend the explicit schema test so schema contains:

```dart
_term('term-inverted-nipples', 'inverted nipples', 'upperBody'),
_term('term-strap-slip', 'strap slip', 'clothingState'),
_term('term-black-collar', 'black collar', 'accessory'),
```

Assert the updated cache contains those exact category strings in `aiRoleExtraction.roles[].prompt_terms` and `mapping.rolePromptReplacements[].rules[].sourceTerms`.

- [ ] **Step 2: Run offline tool test to verify failure or current gap**

Run:

```powershell
flutter test --no-pub test\tool\script_recast_complete_term_audit_test.dart --reporter expanded
```

Expected: FAIL if the tool test currently only covers old category strings.

- [ ] **Step 3: Update Node merge compatibility if needed**

If `script_recast_complete_term_audit.mjs` matches replacement rules by category and text, change `replacementTermKey` lookup to allow old `clothing` source rules to match incoming `accessory` and `clothingState` schema terms by normalized text.

Keep output source term category from the incoming schema.

- [ ] **Step 4: Update repair schema doc**

In `tool/script_recast_complete_term_repair_schema.md`, ensure examples use:

```json
"category": "upperBody"
"category": "accessory"
"category": "clothingState"
```

Do not document `clothing_state` as the preferred output; mention it only as accepted legacy input.

- [ ] **Step 5: Run offline tool checks**

Run:

```powershell
node --check tool\script_recast_complete_term_audit.mjs
flutter test --no-pub test\tool\script_recast_complete_term_audit_test.dart --reporter expanded
```

Expected: PASS.

---

### Task 7: End-To-End Verification And Dry-Run Audit

**Files:**
- No source changes expected.
- Report: `build/script_recast_complete_term_audit_20260627_category_split.json`

**Interfaces:**
- Consumes: all tasks above.
- Produces: verification evidence.

- [ ] **Step 1: Format changed Dart files**

Run:

```powershell
dart format lib\data\studio\tools\prompt_tag_classifier.dart lib\data\studio\models\script_recast.dart lib\data\studio\models\script_ai_role_extraction.dart lib\data\studio\services\script_ai_role_extraction_client.dart lib\data\studio\services\script_ai_role_assembly_application.dart lib\ui\studio_script\widgets\studio_script_page.dart lib\ui\studio_script\view_models\studio_script_viewmodel.dart test\data\studio\tools\prompt_tag_classifier_test.dart test\data\studio\models\script_ai_role_extraction_test.dart test\data\studio\models\script_recast_model_test.dart test\data\studio\services\script_ai_role_extraction_client_test.dart test\data\studio\services\script_ai_role_extraction_parser_test.dart test\data\studio\services\script_ai_role_assembly_application_test.dart test\ui\studio_script\studio_script_page_test.dart test\tool\script_recast_complete_term_audit_test.dart
```

Expected: command exits 0.

- [ ] **Step 2: Run focused test suite**

Run:

```powershell
flutter test --no-pub test\data\studio\tools\prompt_tag_classifier_test.dart test\data\studio\models\script_ai_role_extraction_test.dart test\data\studio\models\script_recast_model_test.dart test\data\studio\services\script_ai_role_extraction_client_test.dart test\data\studio\services\script_ai_role_extraction_parser_test.dart test\data\studio\services\script_ai_role_assembly_application_test.dart test\tool\script_recast_complete_term_audit_test.dart --reporter expanded
```

Expected: PASS.

- [ ] **Step 3: Run targeted UI test**

Run:

```powershell
flutter test --no-pub test\ui\studio_script\studio_script_page_test.dart --plain-name "role prompt replacement terms are grouped by precise category" --reporter expanded
```

Expected: PASS.

- [ ] **Step 4: Run normalizer CLI compile check**

Run:

```powershell
$temp = Join-Path $env:TEMP ('empty-recast-cache-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  dart --packages=.dart_tool/package_config.json tool\normalize_script_recast_ai_cache.dart --cache-dir $temp
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
```

Expected: stdout contains `Scanned 0 cache files; changed_files=0`.

- [ ] **Step 5: Run source/cache dry-run audit without applying**

Run:

```powershell
node tool\script_recast_complete_term_audit.mjs --cache-dir "$env:APPDATA\Novel Studio\Novel Studio\novel_studio\script_recast\cache" --source-root "E:\NAI的脚本群\作品集\带图精品" --report build\script_recast_complete_term_audit_20260627_category_split.json > build\script_recast_complete_term_audit_20260627_category_split.stdout.json
```

Expected:

- `api_used=false`
- `apply=false`
- `files_changed=0`
- no cache files are written

- [ ] **Step 6: Summarize audit report**

Run:

```powershell
@'
const fs=require('fs');
const r=JSON.parse(fs.readFileSync('build/script_recast_complete_term_audit_20260627_category_split.json','utf8'));
console.log(JSON.stringify({
  api_used:r.api_used,
  apply:r.apply,
  files_scanned:r.files_scanned,
  eligible_cache_files:r.eligible_cache_files,
  source_dirs_without_cache_count:r.source_dirs_without_cache_count,
  duplicate_script_id_count:(r.duplicate_script_ids||[]).length,
  files_changed:r.files_changed,
  files_with_target_regression_candidates:r.files_with_target_regression_candidates
}, null, 2));
'@ | node -
```

Expected: report summary prints with `api_used=false`, `apply=false`, and `files_changed=0`.

- [ ] **Step 7: Whitespace check**

Run:

```powershell
git diff --check -- lib\data\studio\tools\prompt_tag_classifier.dart lib\data\studio\models\script_recast.dart lib\data\studio\models\script_ai_role_extraction.dart lib\data\studio\services\script_ai_role_extraction_client.dart lib\data\studio\services\script_ai_role_assembly_application.dart lib\ui\studio_script\widgets\studio_script_page.dart lib\ui\studio_script\view_models\studio_script_viewmodel.dart test\data\studio\tools\prompt_tag_classifier_test.dart test\data\studio\models\script_ai_role_extraction_test.dart test\data\studio\models\script_recast_model_test.dart test\data\studio\services\script_ai_role_extraction_client_test.dart test\data\studio\services\script_ai_role_extraction_parser_test.dart test\data\studio\services\script_ai_role_assembly_application_test.dart test\ui\studio_script\studio_script_page_test.dart test\tool\script_recast_complete_term_audit_test.dart tool\script_recast_complete_term_audit.mjs tool\script_recast_complete_term_repair_schema.md docs\superpowers\specs\2026-06-27-script-recast-complete-ai-term-contract-design.md docs\superpowers\plans\2026-06-27-script-recast-role-term-category-split.md
```

Expected: no output, exit 0.

---

## Self-Review Notes

- Spec coverage: the plan covers new taxonomy, AI prompt contract, cache/schema compatibility, UI grouping, mapping preservation, and dry-run verification.
- Placeholder scan: no `TBD`, `TODO`, or unspecified "add tests" steps are present.
- Type consistency: category names are `accessory` and `clothingState`; legacy inputs `clothing_state` and `accessory` parse through `promptTagCategoryFromReplacementValue`.
- Scope: this plan does not rewrite real active cache files. It changes future generation/merge behavior and validates dry-run audit only.
