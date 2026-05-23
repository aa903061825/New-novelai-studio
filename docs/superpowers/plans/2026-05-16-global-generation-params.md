# Global Generation Params Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-parameter global generation overrides for `steps`, `scale`, `cfg_rescale`, `sampler`, and `negative_prompt`, with local persistence and runtime source switching on the parameter page.

**Architecture:** Keep config-owned values in `ParamConfig`, add a separate runtime `GlobalGenerationParams` model stored locally through `ConfigService`, and resolve effective values at generation time based on one toggle per parameter. Reuse the existing parameter page as the only editing entrypoint so users edit either the config value or the global value depending on each row's toggle.

**Tech Stack:** Flutter, Dart, Hive-backed local storage, Flutter widget/unit tests

---

### Task 1: Lock down the new runtime global state and storage

**Files:**
- Create: `lib/data/models/global_generation_params.dart`
- Modify: `lib/data/models/payload_config.dart`
- Modify: `lib/data/services/config_service.dart`
- Modify: `lib/main.dart`
- Modify: `test/data/models/payload_config_prompt_replace_rules_test.dart`

- [ ] **Step 1: Write the failing tests**

Add tests to `test/data/models/payload_config_prompt_replace_rules_test.dart` that:
- prove `PayloadConfig.toJson()` does not serialize the new runtime global-generation state
- prove `PayloadConfig.fromJson()` leaves the runtime global-generation state out of config serialization concerns

Use assertions shaped like:

```dart
test('PayloadConfig does not serialize runtime global generation params', () {
  final payload = _buildPayloadConfig();
  payload.globalGenerationParams.steps = 15;
  payload.globalGenerationParams.useGlobalSteps = true;

  final json = payload.toJson();

  expect(json.containsKey('global_generation_params'), isFalse);
});
```

- [ ] **Step 2: Run the targeted tests to verify RED**

Run:

```powershell
flutter test test/data/models/payload_config_prompt_replace_rules_test.dart
```

Expected:
- FAIL because `globalGenerationParams` does not exist yet

- [ ] **Step 3: Implement the minimal runtime model and storage hooks**

Create `lib/data/models/global_generation_params.dart` with fields:

```dart
class GlobalGenerationParams {
  bool useGlobalSteps;
  bool useGlobalScale;
  bool useGlobalCfgRescale;
  bool useGlobalSampler;
  bool useGlobalNegativePrompt;

  int steps;
  double scale;
  double cfgRescale;
  String sampler;
  String negativePrompt;
}
```

Then:
- add `globalGenerationParams` to `PayloadConfig` runtime state
- exclude it from `PayloadConfig.toJson()`
- add `ConfigService.loadGlobalGenerationParams()` and `saveGlobalGenerationParams(...)`
- initialize the runtime state from `main.dart`

- [ ] **Step 4: Run the targeted tests to verify GREEN**

Run:

```powershell
flutter test test/data/models/payload_config_prompt_replace_rules_test.dart
```

Expected:
- PASS

- [ ] **Step 5: Save progress**

Because this workspace is not a git repository, do not commit. Continue with verified local changes only.

### Task 2: Add effective-value resolution and metadata routing

**Files:**
- Modify: `lib/data/models/global_generation_params.dart`
- Modify: `lib/data/models/param_config.dart`
- Modify: `lib/data/use_cases/generate_payload_use_case.dart`
- Modify: `lib/ui/parameters_config/view_models/parameters_config_viewmodel.dart`
- Modify: `test/data/use_cases/generate_payload_use_case_global_replace_test.dart`
- Modify: `test/ui/settings_page/settings_page_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

Add tests that:
- verify generation uses global `steps`, `scale`, `cfgRescale`, `sampler`, and `negativePrompt` when their toggles are enabled
- verify generation falls back to config-owned values when toggles are disabled
- verify metadata import writes into the global value when the corresponding toggle is enabled

Use assertions shaped like:

```dart
expect(params['steps'], 15);
expect(params['scale'], 8.2);
expect(params['cfg_rescale'], 0.45);
expect(params['sampler'], 'k_euler');
expect(params['negative_prompt'], 'global bad stuff');
```

- [ ] **Step 2: Run the targeted tests to verify RED**

Run:

```powershell
flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart
```

Expected:
- FAIL because the generation path and metadata import path still read only `ParamConfig`

- [ ] **Step 3: Implement minimal effective-value resolution**

Implement one central resolution path that:
- picks each effective field from global state or config state based on its toggle
- drives request payload generation
- drives NAI4 negative prompt construction
- routes metadata-import updates to the currently active source for each relevant field

Keep the rest of the generation logic unchanged.

- [ ] **Step 4: Run the targeted tests to verify GREEN**

Run:

```powershell
flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart
```

Expected:
- PASS

- [ ] **Step 5: Save progress**

Because this workspace is not a git repository, do not commit. Continue with verified local changes only.

### Task 3: Add per-row UI toggles on the parameter page

**Files:**
- Modify: `lib/ui/core/widgets/slider_list_tile.dart`
- Modify: `lib/ui/core/widgets/editable_list_tile.dart`
- Modify: `lib/ui/parameters_config/widgets/parameters_conifg_view.dart`
- Modify: `lib/ui/parameters_config/view_models/parameters_config_viewmodel.dart`
- Create: `test/ui/parameters_config/parameters_config_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

Add viewmodel-focused tests that:
- verify editing `steps` updates `globalGenerationParams.steps` when `useGlobalSteps` is on
- verify editing `steps` updates `paramConfig.steps` when `useGlobalSteps` is off
- verify the same source-selection behavior for `scale`, `cfgRescale`, `sampler`, and `negativePrompt`

Use assertions shaped like:

```dart
viewmodel.setUseGlobalSteps(true);
viewmodel.setSteps(15);
expect(viewmodel.payloadConfig.globalGenerationParams.steps, 15);
expect(viewmodel.payloadConfig.paramConfig.steps, isNot(15));
```

- [ ] **Step 2: Run the targeted tests to verify RED**

Run:

```powershell
flutter test test/ui/parameters_config/parameters_config_viewmodel_test.dart
```

Expected:
- FAIL because the toggle setters and source-switching logic do not exist yet

- [ ] **Step 3: Implement the minimal UI and viewmodel support**

Implement:
- one toggle setter per parameter in `ParametersConfigViewmodel`
- immediate persistence when toggles or global values change
- trailing widget support in reusable tiles
- a small `global` toggle on each of the five target rows in the parameter page

- [ ] **Step 4: Run the targeted tests to verify GREEN**

Run:

```powershell
flutter test test/ui/parameters_config/parameters_config_viewmodel_test.dart
```

Expected:
- PASS

- [ ] **Step 5: Save progress**

Because this workspace is not a git repository, do not commit. Continue with verified local changes only.

### Task 4: Regression verification

**Files:**
- No code changes expected

- [ ] **Step 1: Run the combined relevant test set**

Run:

```powershell
flutter test test/data/models/payload_config_prompt_replace_rules_test.dart test/data/use_cases/generate_payload_use_case_global_replace_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart test/ui/parameters_config/parameters_config_viewmodel_test.dart
```

Expected:
- PASS

- [ ] **Step 2: Run a broader sanity pass**

Run:

```powershell
flutter test test/data/models/param_config_batch_resolution_behavior_test.dart test/ui/prompt_tab/prompt_tab_viewmodel_test.dart
```

Expected:
- PASS
