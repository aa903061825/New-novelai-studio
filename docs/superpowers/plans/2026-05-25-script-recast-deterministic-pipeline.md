# 剧本 Recast + 确定性批量产线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for multi-agent execution. Steps use checkbox (`- [ ]`) syntax for local execution tracking only; Beads remains the durable task source of truth.

**Goal:** Build the full `剧本 Recast -> 确定性批量产线` workflow while preserving the existing single-image `工作台`.

**Architecture:** Recast imports a read-only `nai_*.json` script folder, parses each frame into a stable logical view, applies semantic role/artist/parameter policies into complete per-frame NAI payloads, and enqueues those payloads as deterministic production tasks. The production queue executes stored payloads directly; it does not regenerate payloads from `PayloadConfig`, `GeneratePayloadUseCase`, `PromptReplaceRule`, or the old random CasRand config tree.

**Tech Stack:** Flutter/Dart, hand-written JSON models, `WorkspaceService` directory storage, existing `NaiMetadataParser`, existing `ImageService`/`FileService` execution utilities, Flutter widget tests, real script fixtures.

---

## Truth Sources And Known Gap

Read before executing any task:

- `AGENTS.md`
- `docs/plans/2026-05-25-script-recast-user-requirements.md`
- `docs/plans/codex交接搞.md`
- `docs/superpowers/specs/2026-05-25-script-recast-deterministic-pipeline-design.md`
- `bd show NAI_NEW-r2k`

The requested `docs/plans/2026-05-25-script-recast-prd.md` is currently missing from the repository. Do not invent a replacement PRD. Treat the user requirements, handoff brief, design spec, and Beads issue as the active source of truth until the PRD appears.

Stealth mode is active: do not commit, push, create a PR, or run destructive git commands unless the user explicitly asks.

## Current Code Boundaries

Keep:

- Single-image workbench: `lib/ui/generation_page/`, `lib/ui/studio_workbench/`.
- Existing metadata base: `lib/data/studio/tools/nai_metadata_parser.dart`.
- Low-level prompt helpers: `lib/data/studio/tools/prompt_tag_processor.dart`, but only as token utilities.
- Existing asset-library models: `CharacterEntry` and `ArtistChain` in `lib/data/workspace/models/workspace_entities.dart`.

Reshape:

- `lib/data/studio/models/tokenizer_script.dart`
- `lib/data/studio/services/tokenizer_script_service.dart`
- `lib/ui/studio_tokenizer_script/widgets/tokenizer_script_page.dart`
- `lib/ui/studio_batch/widgets/studio_batch_page.dart`
- `lib/data/studio/services/studio_batch_plan_service.dart`
- `lib/ui/studio_shell/models/studio_shell_section.dart`
- `lib/ui/studio_shell/widgets/studio_shell_view.dart`

Do not use for Recast payload creation:

- `lib/data/use_cases/generate_payload_use_case.dart`
- `lib/data/models/prompt_replace_rule.dart`
- `StudioBatchPlanService.applyQueueItem(...)`

## Parallel Execution Waves

Wave 1 can run in parallel because write sets are disjoint:

- Task 1: real fixture + parser baseline.
- Task 3: `CharacterEntry` / `ArtistChain` Recast fields.
- Task 5: deterministic production task spine.

Wave 2 starts after Wave 1:

- Task 2: Recast mapping/run model, if Task 1 did not already create it.
- Task 4: Recast engine resolving parsed frames into full payloads.
- Task 7: navigation + script UI shell contracts.

Wave 3 starts after Task 4 and Task 5:

- Task 6: production execution, retry, resume, single-frame rerun.
- Task 8: production queue UI.

Wave 4:

- Task 9: local full-script acceptance and regression sweep.

Each worker must state its owned files, avoid reverting others' edits, and keep implementation TDD-first.

---

## Task 1: Real Fixture And Script Parser Baseline

**Ownership:** Parser worker only.

**Files:**

- Create: `test/fixtures/script_recast/v4_slotted/nai_1.json`
- Create: `test/fixtures/script_recast/v4_slotted/nai_2.json`
- Create: `test/fixtures/script_recast/base_inline/nai_1.json`
- Create: `test/fixtures/script_recast/mixed/nai_1.json`
- Create: `test/fixtures/script_recast/broken/nai_1.json`
- Create: `test/fixtures/script_recast/broken/nai_2.json`
- Create: `lib/data/studio/models/script_recast.dart`
- Create: `lib/data/studio/services/script_recast_parser_service.dart`
- Create: `test/data/studio/services/script_recast_parser_service_test.dart`
- Reuse: `lib/data/studio/tools/nai_metadata_parser.dart`
- Reuse: `lib/data/studio/tools/prompt_tag_processor.dart`

- [ ] **Step 1: Write parser fixture tests first**

Create `test/data/studio/services/script_recast_parser_service_test.dart` with tests that express the wanted API:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_recast_parser_service.dart';

void main() {
  group('ScriptRecastParserService', () {
    test('scans nai json frames in natural order without hardcoded frame count',
        () async {
      final service = ScriptRecastParserService();

      final script = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );

      expect(script.name, 'v4_slotted');
      expect(script.frames.map((frame) => frame.fileName), [
        'nai_1.json',
        'nai_2.json',
      ]);
      expect(script.detectedSchema, ScriptSchema.v4Slotted);
      expect(script.frames.every((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed), isTrue);
    });

    test('extracts parsed frame prompt, negative, coords, seed and source',
        () async {
      final service = ScriptRecastParserService();

      final script = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );
      final frame = script.frames.first;

      expect(frame.parsed.baseCaption, contains('city lights'));
      expect(frame.parsed.charCaptions, hasLength(2));
      expect(frame.parsed.negativeBase, contains('lowres'));
      expect(frame.parsed.negativeCharCaptions, ['bad hands']);
      expect(frame.parsed.coords, [
        const RecastPoint(x: 0.25, y: 0.55),
        const RecastPoint(x: 0.75, y: 0.45),
      ]);
      expect(frame.parsed.generationParams['seed'], 123456);
      expect(frame.parsed.generationParams['sampler'], 'k_euler_ancestral');
      expect(frame.parsed.sourcePayload['Comment'], isNotNull);
    });

    test('detects base inline and mixed schemas by frame voting', () async {
      final service = ScriptRecastParserService();

      final inline = await service.parseDirectory(
        Directory('test/fixtures/script_recast/base_inline'),
      );
      final mixed = await service.parseDirectory(
        Directory('test/fixtures/script_recast/mixed'),
      );

      expect(inline.detectedSchema, ScriptSchema.baseInline);
      expect(mixed.detectedSchema, ScriptSchema.v4Partial);
    });

    test('marks broken frames as error without aborting the script', () async {
      final service = ScriptRecastParserService();

      final script = await service.parseDirectory(
        Directory('test/fixtures/script_recast/broken'),
      );

      expect(script.frames, hasLength(2));
      expect(script.frames.first.parseStatus, ScriptFrameParseStatus.error);
      expect(script.frames.first.warnings, isNotEmpty);
      expect(script.frames.last.parseStatus, ScriptFrameParseStatus.parsed);
    });

    test('parsing is stable across two runs', () async {
      final service = ScriptRecastParserService();

      final first = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );
      final second = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );

      expect(first.toJson(), second.toJson());
    });
  });
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/data/studio/services/script_recast_parser_service_test.dart
```

Expected: fails because `script_recast.dart` and `ScriptRecastParserService` do not exist.

- [ ] **Step 3: Add real-structure fixtures**

Use small, real-shaped JSON. Keep source files read-only in behavior; fixture files are test inputs only.

`v4_slotted/nai_1.json` shape:

```json
{
  "Description": "two girls, city lights",
  "Source": "NovelAI Diffusion V4.5",
  "Comment": {
    "seed": 123456,
    "steps": 28,
    "scale": 6,
    "sampler": "k_euler_ancestral",
    "width": 1216,
    "height": 832,
    "v4_prompt": {
      "caption": {
        "base_caption": "two girls, city lights, 0.8::artist:terasu_mc::",
        "char_captions": [
          {"char_caption": "vulpisfoglia_(arknights), fox_tail", "centers": [{"x": 0.25, "y": 0.55}]},
          {"char_caption": "suzuran_(arknights), bell collar", "centers": [{"x": 0.75, "y": 0.45}]}
        ]
      }
    },
    "v4_negative_prompt": {
      "caption": {
        "base_caption": "lowres, bad anatomy",
        "char_captions": [{"char_caption": "bad hands"}]
      }
    }
  }
}
```

- [ ] **Step 4: Implement minimal models**

Add `Script`, `ScriptFrame`, `ParsedFrame`, `ScriptSchema`, `ScriptFrameParseStatus`, and `RecastPoint` in `script_recast.dart`. Keep constructors immutable and JSON deterministic:

```dart
enum ScriptSchema { v4Slotted, baseInline, v4Partial, unknown }
enum ScriptFrameParseStatus { parsed, error }

class RecastPoint {
  final double x;
  final double y;
  const RecastPoint({required this.x, required this.y});
}
```

Full implementation must include equality for `RecastPoint`, `toJson()` for stable test comparison, and sorted map output when computing stability later.

- [ ] **Step 5: Implement parser service**

Add `parseDirectory(Directory directory)` that:

- includes only files matching `nai_<number>.json`;
- sorts with natural numeric order;
- reads JSON without writing back;
- calls `NaiMetadataParser.parseMap`;
- stores raw JSON in `ParsedFrame.sourcePayload`;
- marks a frame `error` on malformed JSON and continues.

- [ ] **Step 6: Run GREEN and focused regression tests**

Run:

```powershell
flutter test test/data/studio/services/script_recast_parser_service_test.dart test/data/studio/tools/nai_metadata_parser_test.dart test/data/studio/tools/prompt_tag_processor_test.dart
```

Expected: all tests pass.

---

## Task 2: Recast Data Model And Tri-State Policy

**Ownership:** Recast model worker only. If Task 1 already created `script_recast.dart`, coordinate by appending only mapping/run classes.

**Files:**

- Modify: `lib/data/studio/models/script_recast.dart`
- Create: `test/data/studio/models/script_recast_model_test.dart`

- [ ] **Step 1: Write model tests first**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';

void main() {
  test('RecastMapping round trips tri-state policies and frame overrides', () {
    final mapping = RecastMapping(
      id: 'mapping-1',
      scriptId: 'script-1',
      roleSwaps: const [
        RoleSwap(sourceRoleId: 'slot-0', targetCharacterId: 'char-x'),
      ],
      artistSwap: const ArtistSwap(targetArtistChainId: 'artist-chain-x'),
      segmentPolicies: const {
        RecastSegmentKind.characterAnchor: TriStatePolicy.follow(),
        RecastSegmentKind.sceneBackground: TriStatePolicy.lock(),
        RecastSegmentKind.qualityTail: TriStatePolicy.override('masterpiece'),
      },
      paramPolicies: const {
        'seed': TriStatePolicy.lock(),
        'width': TriStatePolicy.override(1216),
        'height': TriStatePolicy.override(832),
      },
      frameOverrides: const [
        FrameOverride(frameIndex: 50, paramPolicies: {'sampler': TriStatePolicy.override('k_dpmpp_2m')}),
      ],
    );

    final restored = RecastMapping.fromJson(mapping.toJson());

    expect(restored.toJson(), mapping.toJson());
    expect(restored.paramPolicies['seed']!.mode, TriStateMode.lock);
    expect(restored.frameOverrides.single.frameIndex, 50);
  });

  test('RecastRun records per-frame results and config fingerprint', () {
    final run = RecastRun(
      id: 'run-1',
      scriptId: 'script-1',
      mappingId: 'mapping-1',
      productionPlanId: 'plan-1',
      status: RecastRunStatus.queued,
      configFingerprint: 'abc123',
      frameResults: const [
        FrameResult(frameIndex: 1, sourceFileName: 'nai_1.json', taskId: 'task-1', status: FrameResultStatus.queued, payloadFingerprint: 'payload-1'),
      ],
    );

    expect(RecastRun.fromJson(run.toJson()).toJson(), run.toJson());
  });
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/data/studio/models/script_recast_model_test.dart
```

Expected: fails on missing mapping/run classes.

- [ ] **Step 3: Implement immutable mapping/run classes**

Required public types:

```dart
enum TriStateMode { lock, follow, override }
enum RecastSegmentKind { characterAnchor, characterIdentity, characterDecoration, characterState, sceneBackground, cameraComposition, actionPose, artistMix, styleBias, nsfwFlavor, qualityTail, negativeBase, negativeCharacter }

class TriStatePolicy {
  final TriStateMode mode;
  final Object? overrideValue;
  const TriStatePolicy.lock();
  const TriStatePolicy.follow();
  const TriStatePolicy.override(this.overrideValue);
}
```

Include `RoleSwap`, `ArtistSwap`, `FrameOverride`, `RecastMapping`, `RecastRun`, `FrameResult`, and status enums. JSON must be stable and must omit empty collections only if tests account for it.

- [ ] **Step 4: Run GREEN**

Run:

```powershell
flutter test test/data/studio/models/script_recast_model_test.dart
```

Expected: pass.

---

## Task 3: Extend CharacterEntry And ArtistChain

**Ownership:** Asset model worker only.

**Files:**

- Modify: `lib/data/workspace/models/workspace_entities.dart`
- Modify: `test/data/workspace/workspace_models_test.dart`
- Modify: `test/data/workspace/workspace_service_test.dart`
- Modify after tests require it: `lib/data/studio/services/studio_workbench_asset_service.dart`
- Modify after tests require it: `test/data/studio/studio_workbench_asset_service_test.dart`

- [ ] **Step 1: Write compatibility and round-trip tests first**

Add tests proving old JSON still loads and new fields round-trip:

```dart
test('CharacterEntry Recast fields default empty for old JSON', () {
  final character = CharacterEntry.fromJson({
    'id': 'char-1',
    'name': 'Heroine',
    'traits': {'front_full': 'blue eyes'},
  });

  expect(character.anchorTags, isEmpty);
  expect(character.identityTags, isEmpty);
  expect(character.conflictTags, isEmpty);
  expect(character.defaultCenters, isEmpty);
  expect(character.aliases, isEmpty);
  expect(character.recastNotes, '');
});

test('CharacterEntry Recast fields round trip', () {
  final character = CharacterEntry.fromJson({
    'id': 'char-1',
    'name': 'Heroine',
    'traits': {'front_full': 'blue eyes'},
    'anchorTags': ['vulpisfoglia_(arknights)'],
    'identityTags': ['fox_tail'],
    'conflictTags': ['cat_tail'],
    'defaultCenters': [{'x': 0.25, 'y': 0.55}],
    'aliases': ['vulpisfoglia'],
    'recastNotes': 'source script extraction',
  });

  final restored = CharacterEntry.fromJson(character.toJson());

  expect(restored.anchorTags, ['vulpisfoglia_(arknights)']);
  expect(restored.defaultCenters.single.x, 0.25);
  expect(restored.toJson(), character.toJson());
});

test('ArtistChain structured Recast fields round trip', () {
  final chain = ArtistChain.fromJson({
    'id': 'artist-1',
    'name': 'Painter Mix',
    'artists': [
      {'name': 'terasu_mc', 'prefix': 'artist:', 'weight': 0.8, 'groupedWith': 'main'}
    ],
    'globalNegatives': [
      {'tag': 'artist:collaboration', 'weight': -6}
    ],
    'styleHintsWeighted': [
      {'tag': 'year 2024', 'weight': 1}
    ],
  });

  final restored = ArtistChain.fromJson(chain.toJson());

  expect(restored.artists.single.name, 'terasu_mc');
  expect(restored.globalNegatives.single.weight, -6);
  expect(restored.styleHintsWeighted.single.tag, 'year 2024');
});
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/data/workspace/workspace_models_test.dart
```

Expected: fails because new fields and value models do not exist.

- [ ] **Step 3: Implement fields and value models**

Add to `workspace_entities.dart`:

```dart
class WorkspacePoint {
  final double x;
  final double y;
  const WorkspacePoint({required this.x, required this.y});
}

class WorkspaceWeightedTag {
  final String tag;
  final double weight;
  const WorkspaceWeightedTag({required this.tag, required this.weight});
}

class ArtistEntry {
  final String name;
  final String prefix;
  final double weight;
  final String? groupedWith;
  const ArtistEntry({required this.name, this.prefix = 'artist:', this.weight = 1, this.groupedWith});
}
```

Extend `CharacterEntry` with `anchorTags`, `identityTags`, `conflictTags`, `defaultCenters`, `aliases`, `recastNotes`. Extend `ArtistChain` with `artists`, `globalNegatives`, `styleHintsWeighted`. Add `copyWith` to both models so save-back code can preserve fields.

- [ ] **Step 4: Add storage preservation tests**

In `workspace_service_test.dart`, save and reload one character and one artist chain with the new fields using `WorkspaceService.saveCharacters/loadCharacters` and `saveArtistChains/loadArtistChains`.

- [ ] **Step 5: Protect save-back paths**

Add regression coverage for these field-loss risks:

- `_saveCharacterPrompt`
- `_saveOutfitPrompt`
- `_saveArtistChainPrompt`
- `_withSeedImages`

Then update those call sites to use `copyWith` or pass through all new fields.

- [ ] **Step 6: Run GREEN**

Run:

```powershell
flutter test test/data/workspace/workspace_models_test.dart test/data/workspace/workspace_service_test.dart test/data/studio/studio_workbench_asset_service_test.dart
```

Expected: pass.

---

## Task 4: Recast Engine

**Ownership:** Engine worker only. Start after Task 1, Task 2, and Task 3 have green tests.

**Files:**

- Create: `lib/data/studio/services/script_recast_engine.dart`
- Create: `test/data/studio/services/script_recast_engine_test.dart`
- Reuse: `lib/data/studio/models/script_recast.dart`
- Reuse: `lib/data/workspace/models/workspace_entities.dart`

- [ ] **Step 1: Write deterministic transform tests first**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/services/script_recast_engine.dart';
import 'package:nai_casrand/data/studio/services/script_recast_parser_service.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

void main() {
  test('role swap replaces character identity while preserving seed and scene',
      () async {
    final parser = ScriptRecastParserService();
    final script = await parser.parseDirectory(
      Directory('test/fixtures/script_recast/v4_slotted'),
    );
    final engine = ScriptRecastEngine();

    final result = engine.resolvePayloads(
      script: script,
      mapping: RecastMapping.defaults(script.id).copyWith(
        roleSwaps: const [RoleSwap(sourceRoleId: 'slot-0', targetCharacterId: 'char-x')],
      ),
      characters: [
        CharacterEntry(
          id: 'char-x',
          name: 'New Heroine',
          traits: const ViewVariantTexts(frontFull: 'green eyes'),
          anchorTags: const ['new_heroine'],
          identityTags: const ['green eyes', 'long hair'],
          conflictTags: const ['fox_tail'],
        ),
      ],
      artistChains: const [],
    );

    final payload = result.frames.first.payload;
    expect(payload['parameters']['seed'], 123456);
    expect(payload.toString(), contains('city lights'));
    expect(payload.toString(), contains('new_heroine'));
    expect(payload.toString(), isNot(contains('fox_tail')));
  });

  test('same script and mapping resolve to the same fingerprints', () async {
    final parser = ScriptRecastParserService();
    final script = await parser.parseDirectory(
      Directory('test/fixtures/script_recast/v4_slotted'),
    );
    final engine = ScriptRecastEngine();
    final mapping = RecastMapping.defaults(script.id);

    final first = engine.resolvePayloads(script: script, mapping: mapping, characters: const [], artistChains: const []);
    final second = engine.resolvePayloads(script: script, mapping: mapping, characters: const [], artistChains: const []);

    expect(first.toJson(), second.toJson());
  });
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/data/studio/services/script_recast_engine_test.dart
```

Expected: fails because `ScriptRecastEngine` does not exist.

- [ ] **Step 3: Implement resolver without GeneratePayloadUseCase**

`ScriptRecastEngine.resolvePayloads(...)` must:

- accept parsed `Script`, `RecastMapping`, existing `CharacterEntry` list, existing `ArtistChain` list;
- produce full payload maps per frame;
- keep source frame JSON untouched;
- apply `lock/follow/override` at segment and param level;
- default `seed` to lock;
- inherit hidden high-end NAI fields (`sm`, `cfg_rescale`, `noise_schedule`, etc.) without exposing them as policies;
- compute stable payload fingerprints from canonical JSON.

- [ ] **Step 4: Run GREEN and guard forbidden paths**

Run:

```powershell
flutter test test/data/studio/services/script_recast_engine_test.dart test/data/use_cases/generate_payload_use_case_global_replace_test.dart
```

Expected: Recast engine tests pass; existing `GeneratePayloadUseCase` tests still pass for the workbench/legacy path.

---

## Task 5: Deterministic Production Task Spine

**Ownership:** Production model worker only.

**Files:**

- Create: `lib/data/studio/models/production_task.dart`
- Create: `lib/data/studio/services/production_queue_service.dart`
- Modify: `lib/data/workspace/workspace_paths.dart`
- Modify: `lib/data/workspace/workspace_service.dart`
- Create: `test/data/studio/models/production_task_model_test.dart`
- Create: `test/data/studio/services/production_queue_service_test.dart`

- [ ] **Step 1: Write production model tests first**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';

void main() {
  test('ProductionTask preserves complete payload and stable fingerprint', () {
    final task = ProductionTask.scriptRecastFrame(
      id: 'task-1',
      planId: 'plan-1',
      title: 'nai_1',
      scriptId: 'script-1',
      recastRunId: 'run-1',
      frameIndex: 1,
      sourceFileName: 'nai_1.json',
      payload: const {
        'input': 'city lights',
        'parameters': {'seed': 123456, 'width': 1216, 'height': 832}
      },
    );

    final restored = ProductionTask.fromJson(task.toJson());

    expect(restored.payload, task.payload);
    expect(restored.payloadFingerprint, task.payloadFingerprint);
    expect(restored.source.scriptId, 'script-1');
    expect(restored.source.frameIndex, 1);
  });
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/data/studio/models/production_task_model_test.dart
```

Expected: fails because production models do not exist.

- [ ] **Step 3: Implement production models**

Required types:

```dart
enum ProductionTaskType { scriptRecastFrame, manualSingleFrame }
enum ProductionTaskStatus { queued, running, completed, failed, skipped }

class ProductionTaskSource {
  final String? scriptId;
  final String? recastRunId;
  final int? frameIndex;
  final String? sourceFileName;
}
```

`ProductionTask` must store complete `payload`, `payloadFingerprint`, `suggestedFileName`, `status`, `attempts`, `outputImagePath`, `error`, timestamps. `ProductionPlan` must store tasks and a plan fingerprint derived from task fingerprints.

- [ ] **Step 4: Add workspace service tests**

`ProductionQueueService` should persist plans under a new path such as `production/deterministic_plans`, leaving old `production/batch_plans` available for legacy reads during transition.

Test:

```dart
test('ProductionQueueService saves and loads deterministic plans', () async {
  final service = ProductionQueueService(workspaceService: workspaceService);
  final plan = ProductionPlan(
    id: 'plan-1',
    name: 'Script Recast',
    tasks: [task1, task2],
    createdAt: DateTime.utc(2026, 5, 25),
    updatedAt: DateTime.utc(2026, 5, 25),
  );

  await service.savePlans([plan]);

  final restored = await service.loadPlans();
  expect(restored.single.toJson(), plan.toJson());
});
```

- [ ] **Step 5: Run GREEN**

Run:

```powershell
flutter test test/data/studio/models/production_task_model_test.dart test/data/studio/services/production_queue_service_test.dart
```

Expected: pass.

---

## Task 6: Production Execution, Retry, Resume, Single-Frame Rerun

**Ownership:** Production execution worker only. Start after Task 5.

**Files:**

- Create: `lib/data/studio/services/production_executor_service.dart`
- Modify: `lib/data/studio/models/production_task.dart`
- Modify: `lib/data/studio/models/studio_gallery_record.dart`
- Modify: `lib/data/studio/services/studio_gallery_service.dart`
- Create: `test/data/studio/services/production_executor_service_test.dart`
- Modify: `test/data/studio/studio_gallery_service_test.dart`

- [ ] **Step 1: Write executor tests first with fake API**

The executor must accept injectable functions for API request, image processing, file save, and clock. Do not hit the real NAI API in tests.

```dart
test('failed frame does not block later queued frames', () async {
  final executor = ProductionExecutorService(
    requestImage: (payload) async {
      if (payload['input'] == 'bad frame') throw StateError('boom');
      return fakePngBytes;
    },
    saveImage: (bytes, fileName) async => 'C:/out/$fileName.png',
    now: () => DateTime.utc(2026, 5, 25),
  );

  final result = await executor.runPlan(planWithThreeTasks, maxRetries: 1);

  expect(result.tasks[0].status, ProductionTaskStatus.completed);
  expect(result.tasks[1].status, ProductionTaskStatus.failed);
  expect(result.tasks[2].status, ProductionTaskStatus.completed);
});

test('rerunFrame executes only the selected task fingerprint', () async {
  final result = await executor.rerunFrame(plan, frameIndex: 2);

  expect(result.changedTaskIds, ['task-2']);
});
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/data/studio/services/production_executor_service_test.dart
```

Expected: fails because executor does not exist.

- [ ] **Step 3: Implement task-state execution**

Executor must:

- run stored payload maps directly;
- never call `GeneratePayloadUseCase`;
- never call `StudioBatchPlanService.applyQueueItem`;
- increment attempts per task;
- mark failed tasks without blocking later tasks;
- support `retryFailed(planId)`;
- support `rerunFrame(planId, frameIndex)`;
- resume by `productionPlanId`, `recastRunId`, and plan fingerprint, not by count.

- [ ] **Step 4: Add gallery provenance**

Extend gallery records so generated PNGs can trace:

- `productionTaskId`
- `recastRunId`
- `scriptId`
- `frameIndex`
- `sourceFileName`
- `payloadFingerprint`
- `outputImagePath`

- [ ] **Step 5: Run GREEN**

Run:

```powershell
flutter test test/data/studio/services/production_executor_service_test.dart test/data/studio/studio_gallery_service_test.dart
```

Expected: pass.

---

## Task 7: Script Entry, Recast UI Shell, And Navigation

**Ownership:** Script UI worker only.

**Files:**

- Modify: `lib/ui/studio_shell/models/studio_shell_section.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Create or reshape: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Create: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify or replace: `test/ui/navigation/novel_studio_navigation_test.dart`
- Create: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write navigation test first**

```dart
testWidgets('studio navigation exposes script as first-level entry', (tester) async {
  await pumpStudioShell(tester);

  expect(find.text('主页'), findsOneWidget);
  expect(find.text('素材库'), findsOneWidget);
  expect(find.text('工作台'), findsOneWidget);
  expect(find.text('剧本'), findsOneWidget);
  expect(find.text('批量产线'), findsOneWidget);
  expect(find.text('画廊'), findsOneWidget);
  expect(find.text('设置'), findsOneWidget);
  expect(find.text('分词剧本'), findsNothing);
});
```

- [ ] **Step 2: Write script page visible-state test first**

The page must not be a placeholder. Test required controls:

```dart
testWidgets('script page shows import, role mapping, artist mapping, tri-state and diff surfaces', (tester) async {
  await tester.pumpWidget(buildScriptPage());

  expect(find.text('导入剧本文件夹'), findsOneWidget);
  expect(find.text('角色映射'), findsOneWidget);
  expect(find.text('画师串'), findsOneWidget);
  expect(find.text('保留'), findsWidgets);
  expect(find.text('跟随'), findsWidgets);
  expect(find.text('覆盖'), findsWidgets);
  expect(find.text('Diff 预览'), findsOneWidget);
  expect(find.text('发送到批量产线'), findsOneWidget);
  expect(find.textContaining('sm'), findsNothing);
  expect(find.textContaining('cfg_rescale'), findsNothing);
  expect(find.textContaining('noise_schedule'), findsNothing);
});
```

- [ ] **Step 3: Run tests and verify RED**

Run:

```powershell
flutter test test/ui/navigation/novel_studio_navigation_test.dart test/ui/studio_script/studio_script_page_test.dart
```

Expected: fails because current UI still says `分词剧本` and script page does not exist.

- [ ] **Step 4: Implement navigation and UI shell**

Rename `tokenizerScript` conceptually to `script` in navigation while preserving route position. The first page can use parsed fixture data or a view model stub only if all tested controls are real widgets with real state callbacks; do not add dead buttons.

- [ ] **Step 5: Run GREEN and protect workbench**

Run:

```powershell
flutter test test/ui/navigation/novel_studio_navigation_test.dart test/ui/studio_script/studio_script_page_test.dart test/ui/generation_page/generation_page_workbench_layout_test.dart test/ui/studio_workbench/workbench_single_image_parameters_viewmodel_test.dart
```

Expected: pass.

---

## Task 8: Deterministic Production UI

**Ownership:** Production UI worker only. Start after Task 5.

**Files:**

- Modify or replace: `lib/ui/studio_batch/widgets/studio_batch_page.dart`
- Create: `lib/ui/studio_batch/view_models/production_queue_viewmodel.dart`
- Modify: `test/ui/studio_batch/studio_batch_page_test.dart`

- [ ] **Step 1: Replace legacy config-tree widget test first**

```dart
testWidgets('batch page shows deterministic production queue not config tree', (tester) async {
  await tester.pumpWidget(buildProductionBatchPageWithFakePlan());

  expect(find.text('队列总览'), findsOneWidget);
  expect(find.text('执行设置'), findsOneWidget);
  expect(find.text('Frame 1'), findsOneWidget);
  expect(find.text('重跑'), findsWidgets);
  expect(find.text('Payload'), findsOneWidget);
  expect(find.byKey(const ValueKey('config-tree-editor-probe')), findsNothing);
});
```

- [ ] **Step 2: Run test and verify RED**

Run:

```powershell
flutter test test/ui/studio_batch/studio_batch_page_test.dart
```

Expected: fails because current batch page expects old config editor.

- [ ] **Step 3: Implement queue UI**

The page must show:

- production plan list;
- task counts and status;
- execution settings: token reference, concurrency, interval, retry count, output directory;
- task rows with frame index, status, output/error, retry/rerun action;
- selected task payload summary;
- optional JSON export action.

It must not show old random config tree controls for Recast tasks.

- [ ] **Step 4: Run GREEN**

Run:

```powershell
flutter test test/ui/studio_batch/studio_batch_page_test.dart
```

Expected: pass.

---

## Task 9: Acceptance Tests And Full Local Validation

**Ownership:** Acceptance worker only. Start after Tasks 1-8.

**Files:**

- Create: `test/integration/script_recast_acceptance_test.dart`
- Create: `tool/script_recast_acceptance.dart`
- Modify: README or docs only if user asks; do not create markdown TODO.

- [ ] **Step 1: Write repository-fixture acceptance tests**

Cover:

- v4 slotted role swap;
- base inline parse;
- mixed parse;
- broken frame tolerance;
- same mapping produces same payload JSON/fingerprint;
- high-end hidden params inherited but absent from UI policy metadata.

Run:

```powershell
flutter test test/integration/script_recast_acceptance_test.dart
```

- [ ] **Step 2: Add local full-script acceptance tool**

`tool/script_recast_acceptance.dart` should scan these paths if present:

```text
E:\NAI的脚本群\作品集\vulpisfoglia suzuran 忍冬x铃兰 BBC
E:\NAI的脚本群\作品集\Chino
E:\NAI的脚本群\作品集\1战败
E:\NAI的脚本群\作品集\ある輪廻のトリスビアスの物語
```

It must not hardcode frame counts. It must print actual detected frame counts, schema votes, parse error counts, and deterministic payload fingerprint summaries.

- [ ] **Step 3: Run full local validation**

Run:

```powershell
dart run tool/script_recast_acceptance.dart
```

Expected: all present local scripts scan; failures are reported per-frame, not as process crashes.

- [ ] **Step 4: Run focused regression suite**

Run:

```powershell
flutter test test/data/studio test/data/workspace test/ui/studio_script test/ui/studio_batch test/ui/navigation test/ui/generation_page test/ui/studio_workbench
```

Expected: pass, or report exact failing tests with reason.

## First Batch Execution Recommendation

Create and claim Beads issues for these three independent Wave 1 tasks:

- real fixture + parser baseline;
- character/artist model extension;
- deterministic production task spine.

Dispatch one worker per issue with the owned file list above. Do not dispatch UI workers until at least the model/parser spine exists, because otherwise UI tests will either become placeholders or force unstable fake contracts.

## Self-Review

- Spec coverage: includes parser, Recast models, existing character/artist extension, engine, deterministic production queue, execution/rerun, script UI, production UI, and acceptance tests.
- Conflict check: the plan preserves single-image workbench; does not create parallel card models; does not route Recast through `GeneratePayloadUseCase`; does not default JSON folder export; does not expose high-end NAI params in Recast UI.
- Missing PRD handling: documented as a known repository gap instead of inventing requirements.
- Beads: plan is not task tracking source of truth; implementation issues must be created/claimed in Beads.
- Git: no commit/push steps because stealth mode is active.
