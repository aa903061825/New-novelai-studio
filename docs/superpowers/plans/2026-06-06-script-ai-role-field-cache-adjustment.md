# Script AI Role Field Cache Adjustment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a WYSIWYG AI role-extraction correction surface with a per-stage non-role prompt pool, tag-level manual cache adjustment, and visible cache-hit markers.

**Architecture:** Extend the AI role extraction stage draft with a persisted non-role field and a materialization flag, then route all six visible fields through the existing `PromptTagEditor` drag/drop system. Reuse `PromptTagClassificationCache` for manual tag-level placement; fresh AI extraction only highlights cache hits, while the new explicit cache-adjustment action performs repositioning.

**Tech Stack:** Flutter, Dart, existing Studio Script ViewModel/widgets, `PromptTagEditor`, `PromptTagClassificationCache`, `PromptTagProcessor`, Flutter widget tests.

---

## Repository Rule

This repository currently runs in stealth git mode from Beads project memory.
Do not create commits during implementation unless the user explicitly asks.
The plan still uses small test-first slices, but verification replaces commit
steps.

## File Structure

- Modify `lib/data/studio/models/script_ai_role_extraction.dart`
  - Add `nonRole` and `nonRoleMaterialized` to `ScriptAiExtractedStage`.
  - Preserve old JSON compatibility.
- Modify `test/data/studio/models/script_ai_role_extraction_test.dart`
  - Cover new stage JSON round-trip and old-cache fallback.
- Modify `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Add `StudioScriptRolePart.nonRole`.
  - Materialize non-role pools from covered positive prompt frames.
  - Remove automatic manual-cache repositioning after fresh AI extraction.
  - Add explicit `applyAiRoleExtractionCacheAdjustment`.
  - Record manual role classifications for all six fields.
- Modify `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Render the non-role field under every AI stage.
  - Add `按照缓存调整` beside the existing high-confidence apply button.
  - Pass cache-hit metadata into prompt editors.
- Modify `lib/ui/studio_core/widgets/prompt_tag_editor.dart`
  - Add optional per-tag highlight metadata for cache-hit markers.
- Modify `test/ui/studio_script/studio_script_page_test.dart`
  - Cover non-role materialization, WYSIWYG persistence, cache adjustment, button behavior, and cache-hit visuals.

## Task 1: Persist Non-role Stage Draft Data

**Files:**
- Modify: `test/data/studio/models/script_ai_role_extraction_test.dart`
- Modify: `lib/data/studio/models/script_ai_role_extraction.dart`

- [ ] **Step 1: Add failing model tests**

Add these tests inside the existing `group('ScriptAiRoleExtraction', () { ... })` block:

```dart
test('round trips stage non-role draft state', () {
  const extraction = ScriptAiRoleExtraction(
    status: ScriptAiRoleExtractionStatus.ready,
    roles: [
      ScriptAiExtractedRole(
        sourceRoleId: 'slot-0',
        stages: [
          ScriptAiExtractedStage(
            stageId: 'main-outfit',
            frameIndexes: [1, 2],
            identity: 'hero',
            upperBody: 'fox ears',
            upperClothing: 'blue jacket',
            nonRole: 'city street, smile',
            nonRoleMaterialized: true,
            confidence: 0.9,
          ),
        ],
      ),
    ],
  );

  final json = extraction.toJson();
  final restored = ScriptAiRoleExtraction.fromJson(json);
  final restoredStage = restored.roles.single.stages.single;

  expect(restoredStage.nonRole, 'city street, smile');
  expect(restoredStage.nonRoleMaterialized, isTrue);

  final roleJson = (json['roles'] as List).single as Map<String, dynamic>;
  final stageJson =
      (roleJson['stages'] as List).single as Map<String, dynamic>;
  expect(stageJson['non_role'], 'city street, smile');
  expect(stageJson['non_role_materialized'], isTrue);
});

test('old stage json without non-role remains readable', () {
  final extraction = ScriptAiRoleExtraction.fromJson({
    'status': 'ready',
    'roles': [
      {
        'source_role_id': 'slot-0',
        'stages': [
          {
            'stage_id': 'main-outfit',
            'frame_indexes': [1],
            'identity': 'hero',
            'upper_body': 'fox ears',
            'lower_body': '',
            'upper_clothing': 'blue jacket',
            'lower_clothing': '',
            'confidence': 0.9,
          },
        ],
      },
    ],
  });

  final stage = extraction.roles.single.stages.single;
  expect(stage.nonRole, '');
  expect(stage.nonRoleMaterialized, isFalse);
});
```

- [ ] **Step 2: Run the model tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_ai_role_extraction_test.dart -r expanded
```

Expected: failure because `ScriptAiExtractedStage` has no `nonRole` or `nonRoleMaterialized` fields.

- [ ] **Step 3: Add model fields and JSON support**

In `lib/data/studio/models/script_ai_role_extraction.dart`, update `ScriptAiExtractedStage`:

```dart
class ScriptAiExtractedStage {
  final String stageId;
  final String label;
  final double confidence;
  final List<int> frameIndexes;
  final String identity;
  final String upperBody;
  final String lowerBody;
  final String upperClothing;
  final String lowerClothing;
  final String nonRole;
  final bool nonRoleMaterialized;
  final List<String> evidenceTerms;
  final List<String> missingFields;
  final List<String> warnings;

  const ScriptAiExtractedStage({
    this.stageId = '',
    this.label = '',
    this.confidence = 0,
    this.frameIndexes = const [],
    this.identity = '',
    this.upperBody = '',
    this.lowerBody = '',
    this.upperClothing = '',
    this.lowerClothing = '',
    this.nonRole = '',
    this.nonRoleMaterialized = false,
    this.evidenceTerms = const [],
    this.missingFields = const [],
    this.warnings = const [],
  });

  factory ScriptAiExtractedStage.fromJson(Map<String, dynamic> json) {
    final hasNonRole = json.containsKey('non_role') ||
        json.containsKey('nonRole') ||
        json.containsKey('non_role_materialized') ||
        json.containsKey('nonRoleMaterialized');
    return ScriptAiExtractedStage(
      stageId: _stringValue(json['stage_id']),
      label: _stringValue(json['label']),
      confidence: _doubleValue(json['confidence']),
      frameIndexes: _intList(json['frame_indexes']),
      identity: _stringValue(json['identity']),
      upperBody: _stringValue(json['upper_body']),
      lowerBody: _stringValue(json['lower_body']),
      upperClothing: _stringValue(json['upper_clothing']),
      lowerClothing: _stringValue(json['lower_clothing']),
      nonRole: _stringValue(json['non_role'] ?? json['nonRole']),
      nonRoleMaterialized: _boolValue(
        json['non_role_materialized'] ?? json['nonRoleMaterialized'],
        fallback: hasNonRole,
      ),
      evidenceTerms: _stringList(json['evidence_terms']),
      missingFields: _stringList(json['missing_fields']),
      warnings: _stringList(json['warnings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'stage_id': stageId,
        'label': label,
        'confidence': confidence,
        'frame_indexes': frameIndexes,
        'identity': identity,
        'upper_body': upperBody,
        'lower_body': lowerBody,
        'upper_clothing': upperClothing,
        'lower_clothing': lowerClothing,
        if (nonRoleMaterialized || nonRole.trim().isNotEmpty)
          'non_role': nonRole,
        if (nonRoleMaterialized) 'non_role_materialized': true,
        'evidence_terms': evidenceTerms,
        'missing_fields': missingFields,
        'warnings': warnings,
      };
}
```

- [ ] **Step 4: Update every `ScriptAiExtractedStage(...)` copy site**

Search for constructor calls that manually rebuild stages:

```powershell
rg -n "ScriptAiExtractedStage\\(" lib test
```

For copy/rebuild sites in `studio_script_viewmodel.dart`, carry through:

```dart
nonRole: stage.nonRole,
nonRoleMaterialized: stage.nonRoleMaterialized,
```

When a stage is intentionally edited or materialized, set `nonRoleMaterialized: true`.

- [ ] **Step 5: Run the model tests**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_ai_role_extraction_test.dart -r expanded
```

Expected: all tests in that file pass.

## Task 2: Materialize Non-role From Covered Frames

**Files:**
- Modify: `test/ui/studio_script/studio_script_page_test.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`

- [ ] **Step 1: Add failing ViewModel test for initial non-role materialization**

Add this widget test near the existing AI role extraction draft tests:

```dart
testWidgets('AI role extraction materializes non-role from covered frames',
    (tester) async {
  final viewModel = StudioScriptViewModel(
    parserService: _FakeParserService([
      _scriptWithFrames([
        (
          index: 1,
          base: 'cinematic lighting, city street',
          chars: ['ai hero, fox ears, blue jacket, smile'],
        ),
        (
          index: 2,
          base: 'city street, rain',
          chars: ['ai hero, white skirt, looking at viewer'],
        ),
      ]),
    ]),
    scriptAiRoleExtractionService: const _FakeRoleExtractionService(
      ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        confidence: 0.9,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'AI Hero',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                label: 'main outfit',
                frameIndexes: [1, 2],
                identity: 'ai hero',
                upperBody: 'fox ears',
                upperClothing: 'blue jacket',
                lowerClothing: 'white skirt',
                confidence: 0.88,
              ),
            ],
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await viewModel.importScriptPath('stage-non-role-script');
    await viewModel.generateAiRoleExtraction();
  });

  final stage = viewModel.aiRoleExtraction.roles.single.stages.single;
  expect(stage.nonRoleMaterialized, isTrue);
  expect(
    stage.nonRole,
    'cinematic lighting, city street, smile, rain, looking at viewer',
  );
});
```

If `_scriptWithFrames` does not exist yet, add this helper near `_singleFrameScript`:

```dart
Script _scriptWithFrames(
  List<({int index, String base, List<String> chars})> frames,
) {
  return Script(
    id: 'script-stage-non-role',
    name: 'Stage Non-role Script',
    rootPath: 'stage-non-role-script',
    detectedSchema: ScriptSchema.v4Slotted,
    frames: [
      for (final frame in frames)
        ScriptFrame(
          index: frame.index,
          fileName: 'nai_${frame.index}.json',
          sourcePath: 'stage-non-role-script/nai_${frame.index}.json',
          rawJson: '{}',
          parsed: ParsedFrame(
            baseCaption: frame.base,
            charCaptions: frame.chars,
          ),
          detectedSchema: ScriptSchema.v4Slotted,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
    ],
  );
}
```

- [ ] **Step 2: Run the new test and confirm it fails**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction materializes non-role from covered frames" -r expanded
```

Expected: failure because no non-role materialization exists.

- [ ] **Step 3: Extend the role-part enum**

In `studio_script_viewmodel.dart`, add:

```dart
enum StudioScriptRolePart {
  identity,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
  nonRole,
}
```

- [ ] **Step 4: Add draft-parts helper**

Add this private helper class near the role part enum:

```dart
class _AiRoleDraftParts {
  final String identity;
  final String upperBody;
  final String lowerBody;
  final String upperClothing;
  final String lowerClothing;
  final String nonRole;

  const _AiRoleDraftParts({
    this.identity = '',
    this.upperBody = '',
    this.lowerBody = '',
    this.upperClothing = '',
    this.lowerClothing = '',
    this.nonRole = '',
  });

  factory _AiRoleDraftParts.fromStage(ScriptAiExtractedStage stage) {
    return _AiRoleDraftParts(
      identity: stage.identity,
      upperBody: stage.upperBody,
      lowerBody: stage.lowerBody,
      upperClothing: stage.upperClothing,
      lowerClothing: stage.lowerClothing,
      nonRole: stage.nonRole,
    );
  }

  String textFor(StudioScriptRolePart part) {
    return switch (part) {
      StudioScriptRolePart.identity => identity,
      StudioScriptRolePart.upperBody => upperBody,
      StudioScriptRolePart.lowerBody => lowerBody,
      StudioScriptRolePart.upperClothing => upperClothing,
      StudioScriptRolePart.lowerClothing => lowerClothing,
      StudioScriptRolePart.nonRole => nonRole,
    };
  }

  bool containsTag(String tag) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (key.isEmpty) return false;
    return _contains(identity, key) ||
        _contains(upperBody, key) ||
        _contains(lowerBody, key) ||
        _contains(upperClothing, key) ||
        _contains(lowerClothing, key) ||
        _contains(nonRole, key);
  }

  static bool _contains(String text, String key) {
    return PromptTagProcessor.splitWorkshopTags(text)
        .map(PromptTagProcessor.cleanTagDisplay)
        .map(PromptTagProcessor.normalizeMatchKey)
        .contains(key);
  }
}
```

- [ ] **Step 5: Add non-role materialization helpers**

Add these helpers inside `StudioScriptViewModel`:

```dart
ScriptAiRoleExtraction _roleExtractionWithMaterializedNonRoleFields({
  required ScriptAiRoleExtraction extraction,
  required Script script,
}) {
  if (!extraction.isReady || extraction.roles.isEmpty) {
    return extraction;
  }
  var changed = false;
  final roles = [
    for (final role in extraction.roles)
      ScriptAiExtractedRole(
        sourceRoleId: role.sourceRoleId,
        sourceKind: role.sourceKind,
        displayName: role.displayName,
        confidence: role.confidence,
        frameIndexes: role.frameIndexes,
        evidenceTerms: role.evidenceTerms,
        warnings: role.warnings,
        unassignedTerms: role.unassignedTerms,
        stages: [
          for (final stage in role.stages)
            _stageWithMaterializedNonRole(
              stage: stage,
              script: script,
              onChanged: () => changed = true,
            ),
        ],
      ),
  ];
  if (!changed) return extraction;
  return ScriptAiRoleExtraction(
    schemaVersion: extraction.schemaVersion,
    status: extraction.status,
    chunkId: extraction.chunkId,
    confidence: extraction.confidence,
    roles: List.unmodifiable(roles),
    artistChains: extraction.artistChains,
    strongFilterKeywords: extraction.strongFilterKeywords,
    attentionItems: extraction.attentionItems,
    unassignedTerms: extraction.unassignedTerms,
    evidenceRequests: extraction.evidenceRequests,
    rawResponse: extraction.rawResponse,
  );
}

ScriptAiExtractedStage _stageWithMaterializedNonRole({
  required ScriptAiExtractedStage stage,
  required Script script,
  required VoidCallback onChanged,
}) {
  if (stage.nonRoleMaterialized) {
    return stage;
  }
  final visible = _AiRoleDraftParts.fromStage(stage);
  final nonRole = _stageFramePositiveTags(
    script: script,
    frameIndexes: stage.frameIndexes,
    excluded: visible,
  ).join(', ');
  onChanged();
  return ScriptAiExtractedStage(
    stageId: stage.stageId,
    label: stage.label,
    confidence: stage.confidence,
    frameIndexes: stage.frameIndexes,
    identity: stage.identity,
    upperBody: stage.upperBody,
    lowerBody: stage.lowerBody,
    upperClothing: stage.upperClothing,
    lowerClothing: stage.lowerClothing,
    nonRole: nonRole,
    nonRoleMaterialized: true,
    evidenceTerms: stage.evidenceTerms,
    missingFields: stage.missingFields,
    warnings: stage.warnings,
  );
}

List<String> _stageFramePositiveTags({
  required Script script,
  required List<int> frameIndexes,
  required _AiRoleDraftParts excluded,
}) {
  final wanted = frameIndexes.toSet();
  final seen = <String>{};
  final result = <String>[];
  for (final frame in script.frames) {
    if (frame.parseStatus != ScriptFrameParseStatus.parsed ||
        !wanted.contains(frame.index)) {
      continue;
    }
    for (final caption in [
      frame.parsed.baseCaption,
      ...frame.parsed.charCaptions,
    ]) {
      for (final rawTag in PromptTagProcessor.splitWorkshopTags(caption)) {
        final clean = PromptTagProcessor.cleanTagDisplay(rawTag).trim();
        final key = PromptTagProcessor.normalizeMatchKey(clean);
        if (key.isEmpty || excluded.containsTag(clean) || !seen.add(key)) {
          continue;
        }
        result.add(clean);
      }
    }
  }
  return List.unmodifiable(result);
}
```

- [ ] **Step 6: Call materialization after fresh AI extraction and old-cache restore**

In `generateAiRoleExtraction`, replace the current automatic manual override assignment:

```dart
aiRoleExtraction = _roleExtractionWithManualClassificationOverrides(
  result.extraction,
);
```

with:

```dart
aiRoleExtraction = _roleExtractionWithMaterializedNonRoleFields(
  extraction: result.extraction,
  script: script,
);
```

In the cache restore/import path where `aiRoleExtraction` is assigned from a cache draft, apply the same helper only when `_script` is available:

```dart
final restoredExtraction = cacheDraft.aiRoleExtraction;
aiRoleExtraction = script == null
    ? restoredExtraction
    : _roleExtractionWithMaterializedNonRoleFields(
        extraction: restoredExtraction,
        script: script,
      );
```

This preserves `nonRoleMaterialized: true` drafts and only fills old caches.

- [ ] **Step 7: Run the focused test**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction materializes non-role from covered frames" -r expanded
```

Expected: pass.

## Task 3: Add Explicit Cache Adjustment Without Auto Replay

**Files:**
- Modify: `test/ui/studio_script/studio_script_page_test.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`

- [ ] **Step 1: Add failing test proving fresh AI extraction does not auto-move cached tags**

Add:

```dart
testWidgets('AI role extraction marks cache hits without auto-moving them',
    (tester) async {
  final classificationCache = PromptTagClassificationCache(
    clock: () => 1710000000,
  );
  classificationCache.setCategory(
    'fox tail',
    PromptTagCategory.lowerBody,
    source: 'manual-role-field',
  );

  final viewModel = StudioScriptViewModel(
    parserService: _FakeParserService([
      _scriptWithFrames([
        (
          index: 1,
          base: 'forest',
          chars: ['ai hero, fox tail, blue jacket'],
        ),
      ]),
    ]),
    classificationCache: classificationCache,
    scriptAiRoleExtractionService: const _FakeRoleExtractionService(
      ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                frameIndexes: [1],
                identity: 'ai hero',
                upperBody: 'fox tail',
                upperClothing: 'blue jacket',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await viewModel.importScriptPath('cached-no-auto-move');
    await viewModel.generateAiRoleExtraction();
  });

  final stage = viewModel.aiRoleExtraction.roles.single.stages.single;
  expect(stage.upperBody, 'fox tail');
  expect(stage.lowerBody, isEmpty);
  expect(viewModel.hasAiRoleExtractionCacheAdjustments, isTrue);
});
```

- [ ] **Step 2: Add failing test for explicit cache adjustment**

Add:

```dart
testWidgets('apply cache adjustment rearranges visible AI draft only',
    (tester) async {
  final classificationCache = PromptTagClassificationCache(
    clock: () => 1710000000,
  );
  classificationCache
    ..setCategory(
      'fox tail',
      PromptTagCategory.lowerBody,
      source: 'manual-role-field',
    )
    ..setCategory(
      'blue jacket',
      PromptTagCategory.other,
      source: 'manual-role-omit',
    );

  final viewModel = StudioScriptViewModel(
    parserService: _FakeParserService([
      _scriptWithFrames([
        (
          index: 1,
          base: 'forest',
          chars: ['ai hero, fox tail, blue jacket'],
        ),
      ]),
    ]),
    classificationCache: classificationCache,
    scriptAiRoleExtractionService: const _FakeRoleExtractionService(
      ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                frameIndexes: [1],
                identity: 'ai hero',
                upperBody: 'fox tail',
                upperClothing: 'blue jacket',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await viewModel.importScriptPath('cached-adjust-script');
    await viewModel.generateAiRoleExtraction();
    await viewModel.applyAiRoleExtractionCacheAdjustment();
  });

  final stage = viewModel.aiRoleExtraction.roles.single.stages.single;
  expect(stage.upperBody, isEmpty);
  expect(stage.lowerBody, 'fox tail');
  expect(stage.upperClothing, isEmpty);
  expect(stage.nonRole, contains('blue jacket'));
  expect(viewModel.isAiRoleExtractionDraftCollapsed, isFalse);
  expect(viewModel.roleMappings, isNotEmpty);
  expect(
    viewModel.roleMappings.first.selectedStage?.sourceParts.lowerBody,
    isEmpty,
  );
});
```

- [ ] **Step 3: Run the new cache tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction marks cache hits without auto-moving them" -r expanded
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "apply cache adjustment rearranges visible AI draft only" -r expanded
```

Expected: first test fails if existing auto replay still moves `fox tail`; second fails because `applyAiRoleExtractionCacheAdjustment` does not exist.

- [ ] **Step 4: Add cache-hit query helpers**

Inside `StudioScriptViewModel`, add:

```dart
bool get hasAiRoleExtractionCacheAdjustments {
  final script = _script;
  final extraction = aiRoleExtraction;
  if (script == null || !extraction.isReady) return false;
  for (final role in extraction.roles) {
    for (final stage in role.stages) {
      for (final tag in _cacheAdjustmentCandidateTags(
        script: script,
        stage: stage,
      )) {
        if (_manualRoleFieldClassificationEntryFor(tag) != null) {
          return true;
        }
      }
    }
  }
  return false;
}

PromptTagClassificationCacheEntry? manualRoleCacheEntryForTag(String tag) {
  return _manualRoleFieldClassificationEntryFor(tag);
}

PromptTagClassificationCacheEntry? _manualRoleFieldClassificationEntryFor(
  String tag,
) {
  final entry = classificationCache.entryFor(tag);
  if (entry == null || !entry.source.startsWith('manual-role')) {
    return null;
  }
  return entry;
}
```

- [ ] **Step 5: Add cache adjustment implementation**

Inside `StudioScriptViewModel`, add:

```dart
Future<void> applyAiRoleExtractionCacheAdjustment() async {
  final script = _script;
  final extraction = aiRoleExtraction;
  if (script == null || !extraction.isReady) {
    return;
  }
  var changed = false;
  final roles = [
    for (final role in extraction.roles)
      ScriptAiExtractedRole(
        sourceRoleId: role.sourceRoleId,
        sourceKind: role.sourceKind,
        displayName: role.displayName,
        confidence: role.confidence,
        frameIndexes: role.frameIndexes,
        evidenceTerms: role.evidenceTerms,
        warnings: role.warnings,
        unassignedTerms: role.unassignedTerms,
        stages: [
          for (final stage in role.stages)
            _stageWithCacheAdjustment(
              script: script,
              stage: stage,
              onChanged: () => changed = true,
            ),
        ],
      ),
  ];
  if (!changed) {
    return;
  }
  aiRoleExtraction = ScriptAiRoleExtraction(
    schemaVersion: extraction.schemaVersion,
    status: extraction.status,
    chunkId: extraction.chunkId,
    confidence: extraction.confidence,
    roles: List.unmodifiable(roles),
    artistChains: extraction.artistChains,
    strongFilterKeywords: extraction.strongFilterKeywords,
    attentionItems: extraction.attentionItems,
    unassignedTerms: extraction.unassignedTerms,
    evidenceRequests: extraction.evidenceRequests,
    rawResponse: extraction.rawResponse,
  );
  _aiRoleExtractionDraftDismissed = false;
  _refreshRecastPlan();
  await _saveCurrentCache();
  notifyListeners();
}

ScriptAiExtractedStage _stageWithCacheAdjustment({
  required Script script,
  required ScriptAiExtractedStage stage,
  required VoidCallback onChanged,
}) {
  final routed = <StudioScriptRolePart, List<String>>{
    for (final part in StudioScriptRolePart.values) part: <String>[],
  };
  final seen = <StudioScriptRolePart, Set<String>>{
    for (final part in StudioScriptRolePart.values) part: <String>{},
  };

  void add(StudioScriptRolePart part, String tag) {
    final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
    final key = PromptTagProcessor.normalizeMatchKey(clean);
    if (key.isEmpty || !seen[part]!.add(key)) return;
    routed[part]!.add(clean);
  }

  void routeVisible(StudioScriptRolePart currentPart, String text) {
    for (final tag in PromptTagProcessor.splitWorkshopTags(text)) {
      final entry = _manualRoleFieldClassificationEntryFor(tag);
      final target = entry == null
          ? currentPart
          : _rolePartForCacheAdjustment(entry.category);
      add(target ?? currentPart, tag);
    }
  }

  routeVisible(StudioScriptRolePart.identity, stage.identity);
  routeVisible(StudioScriptRolePart.upperBody, stage.upperBody);
  routeVisible(StudioScriptRolePart.lowerBody, stage.lowerBody);
  routeVisible(StudioScriptRolePart.upperClothing, stage.upperClothing);
  routeVisible(StudioScriptRolePart.lowerClothing, stage.lowerClothing);
  routeVisible(StudioScriptRolePart.nonRole, stage.nonRole);

  final current = _AiRoleDraftParts.fromStage(stage);
  for (final tag in _stageFramePositiveTags(
    script: script,
    frameIndexes: stage.frameIndexes,
    excluded: current,
  )) {
    final entry = _manualRoleFieldClassificationEntryFor(tag);
    final target = entry == null ? null : _rolePartForCacheAdjustment(entry.category);
    if (target != null) {
      add(target, tag);
    }
  }

  final next = ScriptAiExtractedStage(
    stageId: stage.stageId,
    label: stage.label,
    confidence: stage.confidence,
    frameIndexes: stage.frameIndexes,
    identity: routed[StudioScriptRolePart.identity]!.join(', '),
    upperBody: routed[StudioScriptRolePart.upperBody]!.join(', '),
    lowerBody: routed[StudioScriptRolePart.lowerBody]!.join(', '),
    upperClothing: routed[StudioScriptRolePart.upperClothing]!.join(', '),
    lowerClothing: routed[StudioScriptRolePart.lowerClothing]!.join(', '),
    nonRole: routed[StudioScriptRolePart.nonRole]!.join(', '),
    nonRoleMaterialized: true,
    evidenceTerms: stage.evidenceTerms,
    missingFields: _missingFieldsForPromptParts(
      stage.missingFields,
      RecastPromptParts(
        identity: routed[StudioScriptRolePart.identity]!.join(', '),
        upperBody: routed[StudioScriptRolePart.upperBody]!.join(', '),
        lowerBody: routed[StudioScriptRolePart.lowerBody]!.join(', '),
        upperClothing: routed[StudioScriptRolePart.upperClothing]!.join(', '),
        lowerClothing: routed[StudioScriptRolePart.lowerClothing]!.join(', '),
      ),
    ),
    warnings: _withUniqueString(
      stage.warnings,
      'manual_role_cache_adjustment',
    ),
  );
  if (_stageDraftEqual(stage, next)) {
    return stage;
  }
  onChanged();
  return next;
}

StudioScriptRolePart? _rolePartForCacheAdjustment(
  PromptTagCategory category,
) {
  return switch (category) {
    PromptTagCategory.character => StudioScriptRolePart.identity,
    PromptTagCategory.upperBody => StudioScriptRolePart.upperBody,
    PromptTagCategory.lowerBody => StudioScriptRolePart.lowerBody,
    PromptTagCategory.upperClothing => StudioScriptRolePart.upperClothing,
    PromptTagCategory.lowerClothing => StudioScriptRolePart.lowerClothing,
    PromptTagCategory.other => StudioScriptRolePart.nonRole,
    _ => null,
  };
}
```

Also add:

```dart
bool _stageDraftEqual(
  ScriptAiExtractedStage left,
  ScriptAiExtractedStage right,
) {
  return left.identity == right.identity &&
      left.upperBody == right.upperBody &&
      left.lowerBody == right.lowerBody &&
      left.upperClothing == right.upperClothing &&
      left.lowerClothing == right.lowerClothing &&
      left.nonRole == right.nonRole &&
      left.nonRoleMaterialized == right.nonRoleMaterialized;
}
```

- [ ] **Step 6: Update field edit helpers for non-role**

Update `_rolePartText`, `_promptCategoryForRolePart`, `_extractedStageWithEditedField`, and `_aiExtractionStageParts` or its replacement to include `nonRole`.

Use this category mapping:

```dart
PromptTagCategory _promptCategoryForRolePart(StudioScriptRolePart part) {
  return switch (part) {
    StudioScriptRolePart.identity => PromptTagCategory.character,
    StudioScriptRolePart.upperBody => PromptTagCategory.upperBody,
    StudioScriptRolePart.lowerBody => PromptTagCategory.lowerBody,
    StudioScriptRolePart.upperClothing => PromptTagCategory.upperClothing,
    StudioScriptRolePart.lowerClothing => PromptTagCategory.lowerClothing,
    StudioScriptRolePart.nonRole => PromptTagCategory.other,
  };
}
```

In stage rebuilding, always preserve or set:

```dart
nonRole: part == StudioScriptRolePart.nonRole ? value : stage.nonRole,
nonRoleMaterialized: part == StudioScriptRolePart.nonRole
    ? true
    : stage.nonRoleMaterialized,
```

- [ ] **Step 7: Keep old manual classification helper for non-AI flows**

Do not delete `_promptPartsWithManualClassificationOverrides` yet. It is still
used by source-part recovery paths. Fresh AI extraction must stop calling it,
but other code that uses it for source parts can remain.

- [ ] **Step 8: Run cache-focused tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction marks cache hits without auto-moving them" -r expanded
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "apply cache adjustment rearranges visible AI draft only" -r expanded
```

Expected: both pass.

## Task 4: Render Non-role Field And Cache Adjustment Action

**Files:**
- Modify: `test/ui/studio_script/studio_script_page_test.dart`
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`

- [ ] **Step 1: Update existing AI draft widget test expectations**

In `script page shows AI role extraction action and draft panel`, add:

```dart
expect(find.text('非角色'), findsWidgets);
expect(
  find.byKey(
    const ValueKey(
      'script-ai-role-field-slot-0-main-outfit-nonRole',
    ),
  ),
  findsOneWidget,
);
```

If the fixture frames make non-role visible, also assert one non-role tag:

```dart
expect(
  find.descendant(of: draftPanel, matching: find.text('city street')),
  findsWidgets,
);
```

- [ ] **Step 2: Add failing widget test for the cache adjustment button**

Add:

```dart
testWidgets('AI role draft shows apply cache adjustment before apply action',
    (tester) async {
  final classificationCache = PromptTagClassificationCache();
  classificationCache.setCategory(
    'fox tail',
    PromptTagCategory.lowerBody,
    source: 'manual-role-field',
  );
  final viewModel = StudioScriptViewModel(
    parserService: _FakeParserService([
      _scriptWithFrames([
        (
          index: 1,
          base: 'forest',
          chars: ['ai hero, fox tail'],
        ),
      ]),
    ]),
    classificationCache: classificationCache,
    scriptAiRoleExtractionService: const _FakeRoleExtractionService(
      ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                frameIndexes: [1],
                identity: 'ai hero',
                upperBody: 'fox tail',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await viewModel.importScriptPath('cache-button-script');
    await viewModel.generateAiRoleExtraction();
  });

  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pumpAndSettle();

  final cacheButton = find.byKey(
    const ValueKey('script-ai-role-apply-cache-adjustment'),
  );
  final applyButton = find.text('应用高置信字段');
  expect(cacheButton, findsOneWidget);
  expect(applyButton, findsWidgets);

  await tester.tap(cacheButton);
  await tester.pumpAndSettle();

  expect(
    viewModel.aiRoleExtraction.roles.single.stages.single.lowerBody,
    'fox tail',
  );
  expect(viewModel.isAiRoleExtractionDraftCollapsed, isFalse);
});
```

Use the actual localized button text in the file if the test helper compares mojibake-rendered strings; prefer the stable key for the new button.

- [ ] **Step 3: Run widget tests and confirm they fail**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "script page shows AI role extraction action and draft panel" -r expanded
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role draft shows apply cache adjustment before apply action" -r expanded
```

Expected: failures because UI does not render `nonRole` or the cache adjustment button.

- [ ] **Step 4: Add cache adjustment button**

In `_AiRoleExtractionDraftPanel`, add the new button before the existing high-confidence apply button:

```dart
if (viewModel.hasAiRoleExtractionCacheAdjustments) ...[
  const SizedBox(width: 8),
  StudioButton(
    key: const ValueKey('script-ai-role-apply-cache-adjustment'),
    label: '按照缓存调整',
    icon: Icons.auto_fix_high_outlined,
    tone: StudioButtonTone.secondary,
    onPressed: viewModel.isAiBusy
        ? null
        : () {
            unawaited(viewModel.applyAiRoleExtractionCacheAdjustment());
          },
  ),
],
```

Keep it to the left of the existing `应用高置信字段` action.

- [ ] **Step 5: Render the non-role editor**

In `_AiRoleExtractionStageCard`, after lower clothing, add:

```dart
_AiRoleExtractionFieldEditor(
  label: '非角色',
  sourceRoleId: sourceRoleId,
  stageId: stage.stageId,
  part: StudioScriptRolePart.nonRole,
  value: stage.nonRole,
  viewModel: viewModel,
),
```

In `_AiRoleExtractionFieldEditor`, no special-case code should be needed after `StudioScriptRolePart.nonRole` is supported by the ViewModel. The key becomes:

```dart
'script-ai-role-field-$sourceRoleId-$stageId-${part.name}'
```

which produces `...-nonRole`.

- [ ] **Step 6: Run widget tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "script page shows AI role extraction action and draft panel" -r expanded
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role draft shows apply cache adjustment before apply action" -r expanded
```

Expected: both pass.

## Task 5: Add Cache-hit Visuals To PromptTagEditor

**Files:**
- Modify: `lib/ui/studio_core/widgets/prompt_tag_editor.dart`
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Modify: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Add failing widget test for cache badge**

Add:

```dart
testWidgets('AI role draft marks manual role cache hit tags', (tester) async {
  final classificationCache = PromptTagClassificationCache();
  classificationCache.setCategory(
    'fox tail',
    PromptTagCategory.lowerBody,
    source: 'manual-role-field',
  );
  final viewModel = StudioScriptViewModel(
    parserService: _FakeParserService([
      _scriptWithFrames([
        (
          index: 1,
          base: 'forest',
          chars: ['ai hero, fox tail'],
        ),
      ]),
    ]),
    classificationCache: classificationCache,
    scriptAiRoleExtractionService: const _FakeRoleExtractionService(
      ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                frameIndexes: [1],
                identity: 'ai hero',
                upperBody: 'fox tail',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await viewModel.importScriptPath('cache-badge-script');
    await viewModel.generateAiRoleExtraction();
  });

  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('prompt-tag-editor-cache-hit-fox tail')),
    findsOneWidget,
  );
});
```

- [ ] **Step 2: Run the cache badge test and confirm it fails**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role draft marks manual role cache hit tags" -r expanded
```

Expected: failure because no cache-hit badge exists.

- [ ] **Step 3: Add optional highlight metadata to PromptTagEditor**

In `prompt_tag_editor.dart`, add near typedefs:

```dart
class PromptTagEditorHighlight {
  final String tooltip;

  const PromptTagEditorHighlight({
    required this.tooltip,
  });
}

typedef PromptTagEditorHighlightResolver = PromptTagEditorHighlight? Function(
  String tag,
);
```

Add a field to `PromptTagEditor`:

```dart
final PromptTagEditorHighlightResolver? highlightForTag;
```

Add it to the constructor:

```dart
this.highlightForTag,
```

- [ ] **Step 4: Pass highlight metadata into editable chips**

In `_tagChip`, compute:

```dart
final highlight = widget.highlightForTag?.call(item.displayLabel);
```

Pass it into `_EditablePromptTagChip`:

```dart
highlight: highlight,
```

Update `_EditablePromptTagChip`:

```dart
final PromptTagEditorHighlight? highlight;
```

and constructor:

```dart
this.highlight,
```

Change border/background selection:

```dart
final highlighted = highlight != null;
final borderColor = selected
    ? StudioTokens.primary
    : highlighted
        ? StudioTokens.info
        : previewed
            ? StudioTokens.info
            : StudioTokens.borderStrong;
```

Add a small marker in the chip stack:

```dart
if (highlighted)
  Positioned(
    top: -6,
    left: -5,
    child: Tooltip(
      message: highlight!.tooltip,
      child: DecoratedBox(
        key: ValueKey('prompt-tag-editor-cache-hit-$rawLabel'),
        decoration: const BoxDecoration(
          color: StudioTokens.info,
          shape: BoxShape.circle,
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: Center(
            child: Icon(
              Icons.cached_outlined,
              size: 10,
              color: StudioTokens.textPrimary,
            ),
          ),
        ),
      ),
    ),
  ),
```

- [ ] **Step 5: Pass cache highlights from AI role field editors**

In `_AiRoleExtractionFieldEditor`, add to `PromptTagEditor`:

```dart
highlightForTag: (tag) {
  final entry = viewModel.manualRoleCacheEntryForTag(tag);
  if (entry == null) return null;
  return PromptTagEditorHighlight(
    tooltip: '缓存字段：${_promptTagCategoryLabel(entry.category)}',
  );
},
```

Add a local label helper in `studio_script_page.dart` if one is not importable:

```dart
String _promptTagCategoryLabel(PromptTagCategory category) {
  return switch (category) {
    PromptTagCategory.character => '角色',
    PromptTagCategory.upperBody => '上身',
    PromptTagCategory.lowerBody => '下身',
    PromptTagCategory.upperClothing => '上装',
    PromptTagCategory.lowerClothing => '下装',
    PromptTagCategory.other => '非角色',
    _ => '其它',
  };
}
```

- [ ] **Step 6: Run the cache badge test**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role draft marks manual role cache hit tags" -r expanded
```

Expected: pass.

## Task 6: WYSIWYG Editing And Cache Persistence Tests

**Files:**
- Modify: `test/ui/studio_script/studio_script_page_test.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`

- [ ] **Step 1: Add failing test for editing non-role without background refill**

Add:

```dart
testWidgets('cleared non-role draft does not refill from stage evidence',
    (tester) async {
  var caches = <RecastScriptCache>[];
  final seedViewModel = StudioScriptViewModel(
    loadRecastCaches: () async => caches,
    saveRecastCaches: (next) async => caches = next,
    parserService: _FakeParserService([
      _scriptWithFrames([
        (
          index: 1,
          base: 'city street',
          chars: ['ai hero, blue jacket, smile'],
        ),
      ]),
    ]),
    scriptAiRoleExtractionService: const _FakeRoleExtractionService(
      ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                frameIndexes: [1],
                identity: 'ai hero',
                upperClothing: 'blue jacket',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await seedViewModel.importScriptPath('non-role-clear-script');
    await seedViewModel.generateAiRoleExtraction();
  });
  final stage = seedViewModel.aiRoleExtraction.roles.single.stages.single;
  seedViewModel.setAiRoleExtractionStageField(
    sourceRoleId: 'slot-0',
    stageId: 'main-outfit',
    part: StudioScriptRolePart.nonRole,
    value: '',
  );
  await tester.runAsync(seedViewModel.applyAiRoleExtractionCacheAdjustment);
  expect(stage.nonRoleMaterialized, isTrue);

  final restoredViewModel = StudioScriptViewModel(
    loadRecastCaches: () async => caches,
    saveRecastCaches: (next) async => caches = next,
    parserService: _FakeParserService([
      _scriptWithFrames([
        (
          index: 1,
          base: 'city street',
          chars: ['ai hero, blue jacket, smile'],
        ),
      ]),
    ]),
  );
  await tester.runAsync(() async {
    await restoredViewModel.importScriptPath('non-role-clear-script');
  });

  final restoredStage =
      restoredViewModel.aiRoleExtraction.roles.single.stages.single;
  expect(restoredStage.nonRoleMaterialized, isTrue);
  expect(restoredStage.nonRole, isEmpty);
});
```

If `applyAiRoleExtractionCacheAdjustment` is not the right way to flush a cache save after the field edit, use `await tester.pump(const Duration(milliseconds: 600))` after the edit in a widget-driven version, or expose/use the existing immediate save path already called by `setAiRoleExtractionStageField`.

- [ ] **Step 2: Add failing test for non-role classification persistence**

Add:

```dart
testWidgets('editing non-role records manual other classification',
    (tester) async {
  final classificationCache = PromptTagClassificationCache(
    clock: () => 1710000000,
  );
  final viewModel = StudioScriptViewModel(
    classificationCache: classificationCache,
  )..aiRoleExtraction = const ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.ready,
      roles: [
        ScriptAiExtractedRole(
          sourceRoleId: 'slot-0',
          stages: [
            ScriptAiExtractedStage(
              stageId: 'main-outfit',
              nonRoleMaterialized: true,
            ),
          ],
        ),
      ],
    );

  viewModel.setAiRoleExtractionStageField(
    sourceRoleId: 'slot-0',
    stageId: 'main-outfit',
    part: StudioScriptRolePart.nonRole,
    value: 'city street',
  );

  final entry = classificationCache.entryFor('city street');
  expect(entry?.category, PromptTagCategory.other);
  expect(entry?.source, 'manual-role-omit');
});
```

- [ ] **Step 3: Run the WYSIWYG tests and confirm they fail if gaps remain**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "cleared non-role draft does not refill from stage evidence" -r expanded
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "editing non-role records manual other classification" -r expanded
```

Expected: pass after Tasks 1-5; failures identify remaining WYSIWYG or classification gaps.

- [ ] **Step 4: Fix field override recording to use six-field draft parts**

If the non-role classification test fails, replace the five-field comparison used by `_recordManualRoleFieldOverride` with `_AiRoleDraftParts`.

Use:

```dart
void _recordManualRoleFieldOverride({
  required _AiRoleDraftParts beforeParts,
  required _AiRoleDraftParts afterParts,
  required StudioScriptRolePart editedPart,
}) {
  final before = _tagMapForText(beforeParts.textFor(editedPart));
  final after = _tagMapForText(afterParts.textFor(editedPart));
  var changed = false;

  for (final entry in after.entries) {
    if (before.containsKey(entry.key)) continue;
    changed = _setManualRoleClassification(
          entry.value,
          _promptCategoryForRolePart(editedPart),
          source: editedPart == StudioScriptRolePart.nonRole
              ? 'manual-role-omit'
              : 'manual-role-field',
        ) ||
        changed;
  }

  for (final entry in before.entries) {
    if (after.containsKey(entry.key) ||
        afterParts.containsTag(entry.value)) {
      continue;
    }
    changed = _setManualRoleClassification(
          entry.value,
          PromptTagCategory.other,
          source: 'manual-role-omit',
        ) ||
        changed;
  }

  if (changed) {
    unawaited(_saveClassificationCacheBestEffort());
  }
}
```

Update the caller in `setAiRoleExtractionStageField`:

```dart
final beforeParts = _aiExtractionStageDraftParts(
  extraction: extraction,
  sourceRoleId: sourceRoleId,
  stageId: stageId,
);
...
final afterParts = _aiExtractionStageDraftParts(
  extraction: aiRoleExtraction,
  sourceRoleId: sourceRoleId,
  stageId: stageId,
);
```

The helper returns `_AiRoleDraftParts.fromStage(stage)`.

- [ ] **Step 5: Run the WYSIWYG tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "cleared non-role draft does not refill from stage evidence" -r expanded
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "editing non-role records manual other classification" -r expanded
```

Expected: both pass.

## Task 7: Regression Verification

**Files:**
- No new source files.
- Verify modified model, ViewModel, widget, and Studio Script suites.

- [ ] **Step 1: Run model tests**

Run:

```powershell
flutter test --no-pub test/data/studio/models/script_ai_role_extraction_test.dart -r expanded
```

Expected: all tests pass.

- [ ] **Step 2: Run Script AI role extraction service tests**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_ai_role_extraction_service_test.dart -r expanded
```

Expected: all tests pass. If any failure expects automatic manual-cache replay, update that expectation to the new explicit-button behavior only when the failing test is specifically about draft placement after extraction.

- [ ] **Step 3: Run focused Studio Script widget tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction" -r expanded
```

Expected: all matching AI role extraction widget tests pass.

- [ ] **Step 4: Run full Studio Script page test if the focused set is clean**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart -r expanded
```

Expected: pass, except for any pre-existing unrelated failure already documented in Beads. If an unrelated pre-existing failure appears, capture the exact failing test name and error in the final implementation notes.

- [ ] **Step 5: Run analyzer**

Run:

```powershell
flutter analyze --no-pub
```

Expected: no new issues.

- [ ] **Step 6: Update Beads with implementation notes**

After implementation and verification, update `NAI_NEW-pu5r` with the exact tests run and any known residual unrelated failures:

```powershell
bd update NAI_NEW-pu5r --notes="Implemented WYSIWYG AI role field cache adjustment. Verification: <commands and results>."
```

Close only after the feature is implemented and verified:

```powershell
bd close NAI_NEW-pu5r --reason="Completed WYSIWYG AI role field cache adjustment with focused tests and analyzer."
```
