# Config Presets Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the saved-config long list with a searchable, card-based preset workbench that remains usable when many presets exist.

**Architecture:** Keep existing `ConfigSelectionPageViewmodel` operations and rewrite only the view layer in `ConfigSelectionPageView`. The page owns transient UI state for search text and sort mode; persistence still lives in `ConfigService`.

**Tech Stack:** Flutter widgets, EasyLocalization, existing Playful Geometric theme/widgets, widget tests.

---

### Task 1: Add Coverage For The New Workbench

**Files:**
- Create: `test/ui/settings_page/config_selection_page_view_widget_test.dart`

- [ ] Write a widget test that registers a fake `ConfigService` with multiple saved configs, pumps `ConfigSelectionPageView`, verifies a search field and card actions exist, then types a query and verifies unmatched presets disappear.
- [ ] Run: `flutter test --no-pub -r expanded test/ui/settings_page/config_selection_page_view_widget_test.dart`
- [ ] Expected before implementation: fail because the page has no search field or card actions.

### Task 2: Implement The Workbench View

**Files:**
- Modify: `lib/ui/settings_page/widgets/config_selection_page_view.dart`
- Modify: `assets/l10n/en.json`
- Modify: `assets/l10n/zh-CN.json`

- [ ] Convert the page to a `StatefulWidget` with a `TextEditingController` and `_ConfigSortMode`.
- [ ] Add a top `PlayfulGeometricSurface` toolbar containing search, sort, copy-current, and import-file actions.
- [ ] Replace the long `ListTile` list with a responsive `GridView.builder` of preset cards.
- [ ] Put `Use`, rename, export, and delete controls inside each card. Card tap should also load the config and call `notificationCallback`.
- [ ] Keep delete disabled for the active preset.

### Task 3: Verify And Ship

**Files:**
- Test: `test/ui/settings_page/config_selection_page_view_widget_test.dart`
- Test: existing setting and prompt widget tests

- [ ] Run targeted `dart analyze` on touched files.
- [ ] Run targeted widget tests.
- [ ] Run full `flutter test --no-pub -r expanded`.
- [ ] Build Windows release and launch `build/windows/x64/runner/Release/NAI_CasRand.exe`.
