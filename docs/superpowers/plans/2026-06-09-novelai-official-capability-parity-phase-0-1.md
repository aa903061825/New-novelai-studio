# NovelAI Official Capability Parity Phase 0-1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the first high-impact parity gap between Studio Workbench and the official NovelAI image workflow by adding a model capability contract, persisting Image2Image state, emitting Image2Image payloads, and exposing Image2Image controls inside the workbench reference panel.

**Architecture:** Keep Studio Workbench as the primary creation surface. Add a small capability contract in the data layer, keep I2I state inside `PayloadConfig`, serialize it through workbench documents, and route request assembly through `GeneratePayloadUseCase` so UI, transfer, and generation all share the same source of truth.

**Tech Stack:** Flutter, Dart, Provider/GetIt, existing `PayloadConfig`/`ParamConfig` models, existing workbench widgets, `flutter test`, `dart analyze`, Beads issue tracking.

---

## Source Context

Design spec: `docs/superpowers/specs/2026-06-09-novelai-official-capability-parity-design.md`

Parent Beads issue: `NAI_NEW-kfle`

Current findings to preserve:

- `I2IConfig`, `I2iVibeViewmodel`, and `I2iConfigView` already exist and support source image, dimensions, Strength, Noise, and metadata import.
- `I2iTabView` currently exposes Vibe Transfer or Precise Reference only; it does not render `I2iConfigView`.
- `GeneratePayloadUseCase` builds Vibe Transfer and Precise Reference payload fields, but does not merge `payloadConfig.i2iConfig`.
- `PayloadConfig` and `WorkbenchDocument` do not currently persist `i2i_config`.
- `WorkbenchSingleImageParametersViewmodel` already counts I2I state, so the product model expects I2I to be part of the workbench reference loop.

## Constraints

- Do not run git stage, commit, push, branch, reset, or checkout commands for this slice. Beads prime reported stealth mode for this repository.
- Use Beads for durable tracking. The checkbox list in this plan is an execution checklist and is mirrored into Beads child issues.
- Keep all changes scoped to Phase 0/1. Do not start Enhance, Upscale, Director Tools, Canvas, Inpaint, or prompt productivity implementation in this slice.
- Prefer existing workbench and model patterns over new infrastructure.
- If the actual NovelAI request protocol for I2I differs from the legacy code assumptions, update the failing payload tests and implementation together with a short note in the Beads issue.

## Phase 0: Capability Contract And Payload Baseline

- [ ] Add generation capability model contract.
  - Create `lib/data/models/generation_capabilities.dart`.
  - Add `enum GenerationMode { textToImage, imageToImage, enhance, upscale, inpaint, directorTool }`.
  - Add immutable `GenerationModelCapabilities` with at least:
    - `model`
    - `isV4`
    - `isV45`
    - `isV3`
    - `supportsVibeTransfer`
    - `supportsPreciseReference`
    - `supportsMultiCharacterPrompts`
    - `supportsPromptMixing`
    - `supportsSmeaControls`
  - Add `GenerationModelCapabilities.fromModel(String model)` using the existing model string constants and helper patterns in `lib/core/constants/parameters.dart`.
  - Default unknown models conservatively: no V4.5-only features, no Precise Reference, no Multi-Character prompts.

- [ ] Cover capability behavior with tests.
  - Add `test/data/models/generation_capabilities_test.dart`.
  - Verify V4.5 models support Vibe Transfer, Precise Reference, and Multi-Character prompts.
  - Verify V3-style anime/furry models keep legacy prompt mixing and SMEA behavior.
  - Verify unknown models do not accidentally expose advanced official-only controls.

- [ ] Persist I2I state in data models.
  - Update `lib/data/models/i2i_config.dart`.
  - Add `toJson`, `fromJson`, and `loadJson` or equivalent local loading helpers consistent with the surrounding model style.
  - Persist `imageB64`, `width`, `height`, `strength`, `noise`, `overridePromptEnabled`, and `overridePrompt`.
  - Add explicit clear/update helpers if needed so UI mutations call `notifyListeners`.
  - Fix `getConfigResult()` so `overridePrompts` is only populated when `overridePromptEnabled` is true and the prompt is non-empty.

- [ ] Persist I2I through payload config and workbench documents.
  - Update `lib/data/models/payload_config.dart` so `toJson`, `fromJson`, and `loadJson` include `i2i_config`.
  - Update `lib/data/studio/models/workbench_document.dart` so `_payloadKeys` includes `i2i_config`.
  - Keep document compatibility: old documents without `i2i_config` must still load with a blank I2I config.

- [ ] Cover persistence with tests.
  - Add or extend `test/data/models/i2i_config_test.dart`.
  - Extend `test/data/studio/workbench_document_test.dart`.
  - Extend `test/data/studio/workbench_transfer_service_test.dart` if transfer export/import coverage does not already pass through the document model deeply enough.
  - Include an old-document compatibility test where `i2i_config` is absent.

## Phase 1: Workbench I2I Closure

- [ ] Emit Image2Image payloads from `GeneratePayloadUseCase`.
  - Update `lib/data/use_cases/generate_payload_use_case.dart`.
  - When `payloadConfig.i2iConfig.imageB64` is present:
    - Set request `action` to `img2img`.
    - Add `parameters.image`.
    - Add clamped `parameters.strength`.
    - Add clamped `parameters.noise`.
    - Add `parameters.extra_noise_seed` when the existing config result provides one.
    - Use the I2I override prompt as request `input` only when override is enabled and non-empty.
  - When no I2I image is present, preserve the existing `generate` action and do not add I2I-only parameters.
  - Keep existing Vibe Transfer and Precise Reference behavior unchanged unless tests expose an explicit conflict.

- [ ] Cover I2I payload assembly with tests.
  - Add `test/data/use_cases/generate_payload_use_case_i2i_test.dart`.
  - Verify source image switches the action from `generate` to `img2img`.
  - Verify source image, Strength, Noise, and extra noise seed are present in parameters.
  - Verify Strength and Noise are clamped to the valid range.
  - Verify disabled override prompt does not replace the normal prompt.
  - Verify enabled override prompt replaces request `input`.
  - Verify Vibe Transfer fields can still be emitted with I2I unless a known API constraint says otherwise.
  - Keep existing Vibe and Precise Reference tests green.

- [ ] Expose I2I controls in the workbench reference panel.
  - Update `lib/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart` with an accessor or factory for `I2iVibeViewmodel(config: payloadConfig.i2iConfig, paramConfig: paramConfig)`.
  - Update `lib/ui/i2i_tab/widgets/i2i_tab_view.dart` so the compact workbench reference editor renders `I2iConfigView` alongside Vibe Transfer or Precise Reference.
  - Give the I2I surface stable test keys such as `workbench-i2i-config-view`, `workbench-i2i-source-image`, `workbench-i2i-strength-slider`, and `workbench-i2i-noise-slider`.
  - Keep the Vibe/Precise Reference controls available in the same panel. Do not hide them behind an unrelated new screen.

- [ ] Ensure I2I UI mutations notify the workbench summary.
  - Update `lib/ui/i2i_config/view_models/i2i_config_viewmodel.dart` if direct model field assignments bypass `notifyListeners`.
  - Update `lib/data/models/i2i_config.dart` with notifier-safe setters where useful.
  - If the parent workbench chips do not refresh from I2I changes, update `lib/ui/studio_workbench/widgets/workbench_single_image_console.dart` or the relevant parameter view model listener wiring so `I2I 0/1` reflects source-image changes.

- [ ] Cover workbench UI integration.
  - Extend `test/ui/i2i_tab/i2i_tab_viewmodel_test.dart` to prove the I2I view model points at the active `PayloadConfig.i2iConfig`.
  - Extend `test/ui/i2i_config/i2i_config_viewmodel_test.dart` to verify remove/clear operations notify and reset dimensions.
  - Extend `test/ui/generation_page/generation_page_workbench_layout_test.dart` to verify the workbench reference editor renders the I2I config surface and keeps Vibe/Precise controls.
  - Use existing widget harnesses and avoid broad golden-test churn.

## Verification Commands

Run targeted tests:

```powershell
flutter test test/data/models/generation_capabilities_test.dart test/data/models/i2i_config_test.dart test/data/use_cases/generate_payload_use_case_i2i_test.dart test/data/use_cases/generate_payload_use_case_vibe_toggle_test.dart test/data/use_cases/generate_payload_use_case_precise_reference_test.dart test/data/studio/workbench_document_test.dart test/data/studio/workbench_transfer_service_test.dart test/ui/i2i_config/i2i_config_viewmodel_test.dart test/ui/i2i_tab/i2i_tab_viewmodel_test.dart test/ui/generation_page/generation_page_workbench_layout_test.dart -r expanded
```

Run focused analysis:

```powershell
dart analyze lib/data/models/generation_capabilities.dart lib/data/models/i2i_config.dart lib/data/models/payload_config.dart lib/data/studio/models/workbench_document.dart lib/data/use_cases/generate_payload_use_case.dart lib/ui/i2i_config/view_models/i2i_config_viewmodel.dart lib/ui/i2i_config/widgets/i2i_config_view.dart lib/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart lib/ui/i2i_tab/widgets/i2i_tab_view.dart lib/ui/studio_workbench/widgets/workbench_single_image_console.dart
```

If UI changes are visually meaningful, also run the relevant local app target and inspect the workbench reference panel manually.

## Self-Review Checklist

- [ ] I2I state survives workbench export/import.
- [ ] I2I generation request contains the expected action and parameters.
- [ ] Existing text-to-image, Vibe Transfer, and Precise Reference tests still pass.
- [ ] Workbench reference panel exposes I2I without removing Vibe or Precise Reference.
- [ ] Missing `i2i_config` in older documents does not break import.
- [ ] No Phase 2+ features were partially implemented.
- [ ] Beads child issues are updated with the actual verification results.

## Beads Mapping

Mirror this plan into child issues under `NAI_NEW-kfle`:

- Capability contract and tests.
- I2I persistence through payload and workbench documents.
- I2I payload assembly in `GeneratePayloadUseCase`.
- Workbench I2I controls and notifier wiring.
- Phase 0/1 verification pass.

Close child issues only after their tests or equivalent verification commands pass.
