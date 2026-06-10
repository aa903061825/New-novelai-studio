# Prompt Tag Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for implementation and superpowers:verification-before-completion before claiming completion. Track durable work in Beads issue `NAI_NEW-1w7b`.

**Goal:** Finish the prompt tag cleanup by removing the remaining duplicated presentation and request orchestration logic between `PromptTagDisplay` and `PromptTagEditor`, while preserving existing user-facing behavior, menu actions, drag/selection behavior, and widget test keys.

**Architecture:** Keep feature-specific behavior inside the owning widgets. Extract shared, low-risk primitives:

- `PromptTagChip`: one reusable visual chip widget with configurable keys, states, badges, and gestures.
- `PromptTagAutoTranslationQueue`: one shared queued translator that deduplicates concurrent tag translation requests and persists online results.
- prompt tag presentation helpers for weight text and weighted raw tag formatting.

**Constraints:**

- Preserve current public widget APIs.
- Preserve existing `ValueKey` strings used by tests and drag/selection flows.
- Keep Display and Editor menu action lists local because their side effects differ.
- Do not change unrelated project files or normalize mojibake strings in this pass.

---

### Task 1: RED Tests For Shared Rules

**Files:**
- Modify: `test/ui/studio_core/prompt_tag_presentation_test.dart`
- Create: `test/ui/studio_core/prompt_tag_chip_test.dart`

- [ ] Add tests for shared weight formatting and weighted tag raw value generation.
- [ ] Add widget tests for the shared chip's body key, marker key, weight badge, delete action, selected check, highlight badge, and loading secondary label.
- [ ] Verify focused new tests fail before implementation.

### Task 2: Shared Presentation Helpers

**Files:**
- Modify: `lib/ui/studio_core/services/prompt_tag_presentation.dart`

- [ ] Add `formatPromptTagWeightText`.
- [ ] Add `formatPromptTagWeightedValue`.
- [ ] Replace duplicated Display/Editor helpers with the shared helpers.

### Task 3: Shared Auto Translation Queue

**Files:**
- Create: `lib/ui/studio_core/services/prompt_tag_auto_translation_queue.dart`
- Modify: `lib/ui/studio_core/widgets/prompt_tag_display.dart`
- Modify: `lib/ui/studio_core/widgets/prompt_tag_editor.dart`

- [ ] Move the editor's private queued translator into the shared service.
- [ ] Migrate editor auto-translation and manual retranslate calls to the shared service.
- [ ] Migrate display bulk auto-translation and manual retranslate calls to the shared service while keeping display-local pending state.
- [ ] Preserve cache persistence and local fallback behavior.

### Task 4: Shared Chip Widget

**Files:**
- Create: `lib/ui/studio_core/widgets/prompt_tag_chip.dart`
- Modify: `lib/ui/studio_core/widgets/prompt_tag_display.dart`
- Modify: `lib/ui/studio_core/widgets/prompt_tag_editor.dart`

- [ ] Implement a configurable reusable tag chip visual.
- [ ] Replace `_PromptTagChip` in Display.
- [ ] Replace `_EditablePromptTagChip` in Editor.
- [ ] Keep all existing key names stable.

### Task 5: Verification

- [ ] Run `dart format` on modified Dart files and new tests.
- [ ] Run focused tag tests:
  `flutter test test/ui/studio_core/prompt_tag_presentation_test.dart test/ui/studio_core/prompt_tag_chip_test.dart test/ui/studio_core/prompt_tag_display_test.dart test/ui/studio_core/prompt_tag_editor_test.dart`
- [ ] Run `flutter test test/code_health`.
- [ ] Run `flutter analyze`.
- [ ] Close `NAI_NEW-1w7b` only after verification passes.
