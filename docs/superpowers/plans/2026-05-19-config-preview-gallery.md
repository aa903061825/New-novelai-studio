# Config Preview Gallery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a home-page action that saves the latest generated images as the active config preview, then show and manage a single cover image on saved config cards.

**Architecture:** Persist preview thumbnails on `SavedConfigInfo` inside the existing config index. `GenerationPageViewmodel` collects recent generated image bytes, converts them to compact thumbnails through `ImageService`, and asks `ConfigService` to save them. The config list renders one cover image per card and opens a dialog for choosing another cover from the saved preview set.

**Tech Stack:** Flutter, Dart, Hive-backed `ConfigService`, `image` package for thumbnail resizing, widget/unit tests with `flutter_test`.

---

### Task 1: Persist Preview Metadata

**Files:**
- Modify: `lib/data/services/config_service.dart`
- Test: `test/data/services/config_service_preview_test.dart`

- [ ] Write failing tests for `SavedConfigInfo` preview JSON round-trip and `ConfigService` preview updates.
- [ ] Run `flutter test --no-pub test/data/services/config_service_preview_test.dart -r expanded` and confirm the new API is missing.
- [ ] Add `previewImages`, `previewCoverIndex`, safe cover lookup, and config service update methods.
- [ ] Re-run the config preview tests until they pass.

### Task 2: Thumbnail and Home Save Action

**Files:**
- Modify: `lib/data/services/image_service.dart`
- Modify: `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- Modify: `lib/ui/generation_page/widgets/generation_page_view.dart`
- Modify: `assets/l10n/en.json`
- Modify: `assets/l10n/zh-CN.json`
- Test: `test/ui/generation_page/view_models/generation_page_config_preview_test.dart`
- Test: `test/ui/generation_page/generation_page_resume_controls_widget_test.dart`

- [ ] Write failing tests for collecting the latest image cards, limiting to 9, and saving thumbnail strings with a random cover.
- [ ] Run the targeted generation tests and confirm the new behavior is missing.
- [ ] Add thumbnail encoding to `ImageService`.
- [ ] Add preview availability and save behavior to `GenerationPageViewmodel`.
- [ ] Add a compact floating action button on the home page.
- [ ] Re-run the targeted generation tests until they pass.

### Task 3: Card Cover and Preview Dialog

**Files:**
- Modify: `lib/ui/settings_page/view_models/config_selection_page_viewmodel.dart`
- Modify: `lib/ui/settings_page/widgets/config_selection_page_view.dart`
- Modify: `assets/l10n/en.json`
- Modify: `assets/l10n/zh-CN.json`
- Test: `test/ui/settings_page/config_selection_page_view_widget_test.dart`

- [ ] Write failing widget tests for card cover display and choosing a cover from the preview dialog.
- [ ] Run the config selection widget test and confirm the new UI is missing.
- [ ] Render a cover thumbnail on cards that have preview images.
- [ ] Add a preview icon button that opens a dialog with the saved preview images.
- [ ] Persist cover selection through the config selection viewmodel.
- [ ] Re-run the config selection widget test until it passes.

### Task 4: Verification

**Files:**
- No new source files expected.

- [ ] Run targeted analyze for modified source and test files.
- [ ] Run targeted tests for config service, generation preview behavior, generation page controls, and config selection.
- [ ] Run `flutter build windows --release --no-pub`.
- [ ] Launch the built Windows exe so the user can test the actual app.
