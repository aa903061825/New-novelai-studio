# Prompt Display Translation Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tag-style prompt display with opt-in hovered-card translation, focused-detail default translation, and settings-visible shortcut guidance.

**Architecture:** Add a small reusable prompt tag display widget that parses comma-delimited prompt text with the existing `PromptTagProcessor` and resolves translations with the existing `TranslationCache`. Use a global display shortcut trigger so prompt cards can register hover state and translate only the hovered card. Keep copy/generation payloads raw.

**Tech Stack:** Flutter, widget tests, existing `PromptTagProcessor`, existing `TranslationCache`, `GetIt`.

---

### Task 1: Core Prompt Display Widget

**Files:**
- Create: `lib/ui/studio_core/widgets/prompt_tag_display.dart`
- Test: `test/ui/studio_core/prompt_tag_display_test.dart`

- [ ] Write tests for raw tag rendering, translated default rendering, and hovered shortcut translation.
- [ ] Verify the new tests fail because the widget does not exist.
- [ ] Implement `PromptTagDisplay` and a hover shortcut trigger in `AppDisplaySettings`.
- [ ] Verify the new tests pass.

### Task 2: App Shortcut And Settings Surface

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
- Test: `test/ui/settings_page/settings_page_view_widget_test.dart`

- [ ] Write a widget test that settings shows `Ctrl+Shift+T` as the prompt translation shortcut.
- [ ] Verify the settings test fails.
- [ ] Wire a global `Ctrl+Shift+T` shortcut to `AppDisplaySettings.translateHoveredPromptCard()`.
- [ ] Add a settings tile documenting the shortcut and a button that triggers the same action.
- [ ] Verify the settings test passes.

### Task 3: Asset Library Integration

**Files:**
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`
- Test: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] Write tests proving waterfall cards render prompt text as tags without default translation.
- [ ] Write tests proving selected asset details default to translated tags and expose a top-right translation toggle.
- [ ] Verify those tests fail.
- [ ] Replace prompt summary/detail text widgets with `PromptTagDisplay`.
- [ ] Mark prompt-like detail lines so only prompt/tag values use tag translation.
- [ ] Verify asset library tests pass.

### Task 4: Workbench And Generated Result Integration

**Files:**
- Modify: `lib/ui/studio_workbench/widgets/workbench_overview_panel.dart`
- Modify: `lib/ui/generation_page/widgets/info_card.dart`
- Test: `test/ui/studio_workbench/prompt_display_shortcut_test.dart`

- [ ] Write tests for hovering a workbench prompt preview and pressing the shortcut.
- [ ] Verify the tests fail.
- [ ] Use `PromptTagDisplay` for workbench prompt previews and generated result info values.
- [ ] Verify focused/hovered prompt display behavior passes.

### Task 5: Script/Tokenizer Default Translation

**Files:**
- Modify: `lib/ui/studio_tokenizer_script/widgets/tokenizer_script_page.dart`
- Test: `test/ui/studio_tokenizer_script/tokenizer_script_page_test.dart`

- [ ] Add tests proving final/original prompt summary cards render translated tag chips by default.
- [ ] Verify the tests fail.
- [ ] Replace rule/prompt summary text with `PromptTagDisplay(defaultTranslated: true)`.
- [ ] Verify tokenizer tests pass.

### Verification

- [ ] Run focused widget tests for prompt display, settings, asset library, workbench, and tokenizer.
- [ ] Run `flutter test` if focused tests are green.
- [ ] Close Beads issue `NAI_NEW-32o` only after tests pass or report exact blockers.
