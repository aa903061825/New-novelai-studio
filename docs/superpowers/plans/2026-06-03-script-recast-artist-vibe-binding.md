# Script Recast Artist Vibe Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add default artist-chain Vibe bindings plus inline per-script Vibe additions for Script Recast artist swaps.

**Architecture:** Reuse the existing `ArtistChain.vibeRefs` and `RecastMapping.manualVibeRefs` data flow. The generation engine already merges those sources, so implementation focuses on asset-library persistence UI and script artist mapping row display/control.

**Tech Stack:** Flutter/Dart, widget tests, existing `WorkspaceService`, `StudioAssetCatalogService`, and `StudioScriptViewModel` patterns.

---

### Task 1: Script Mapping Row Vibe Slot

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write the failing widget/model tests**

Add tests that create an artist chain with `vibeRefs`, select it in the script page, and assert the row shows inherited Vibe chips. Add a second assertion path for manual Vibe selection in the same row using the existing `setManualVibe` API.

- [ ] **Step 2: Run the new tests and verify RED**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "artist mapping row shows paired vibes"`

Expected: FAIL because the row does not yet render inherited Vibe chips.

- [ ] **Step 3: Implement the row slot**

Add a compact widget under `_ArtistMappingRow` that receives the selected artist chain, `viewModel.vibeOptions`, `viewModel.selectedManualVibes`, and `viewModel.setManualVibe`. It renders inherited Vibes read-only and available manual Vibes as checkboxes.

- [ ] **Step 4: Run the target script test**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "artist mapping row shows paired vibes"`

Expected: PASS.

### Task 2: Asset Library Default Binding Surface

**Files:**
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Write the failing asset-library widget test**

Add a test that opens an artist-chain detail drawer, sees available Vibe V4 entries, toggles one, and verifies the supplied save callback receives the artist chain with that `vibeRefs` entry.

- [ ] **Step 2: Run the new test and verify RED**

Run: `flutter test test/ui/studio_shell/asset_library_page_test.dart --plain-name "artist chain detail toggles default vibe binding"`

Expected: FAIL because `AssetLibraryPage` has no Vibe binding surface or save callback.

- [ ] **Step 3: Add page dependencies**

Extend `AssetLibraryPage` with optional `loadVibes` and `saveArtistChains` callbacks. Wire `StudioShellView` and `main.dart` to pass Vibe V4 references from the current payload and `WorkspaceService.saveArtistChains`.

- [ ] **Step 4: Implement default binding UI**

Pass the selected `ArtistChain` through `_AssetDisplayItem`, render a default Vibe section in `_AssetDetailDrawer`, and call a page-level toggle method that updates the catalog's artist chains and refreshes the selected item.

- [ ] **Step 5: Run the target asset-library test**

Run: `flutter test test/ui/studio_shell/asset_library_page_test.dart --plain-name "artist chain detail toggles default vibe binding"`

Expected: PASS.

### Task 3: Payload and Regression Verification

**Files:**
- Test: `test/data/studio/services/script_recast_engine_test.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`
- Test: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Add or confirm payload regression tests**

Confirm existing `ScriptRecastEngine` tests cover bound Vibes, manual Vibes, and ordering. Add a duplicate-encoding test if missing.

- [ ] **Step 2: Run focused tests**

Run:

```powershell
flutter test test/data/studio/services/script_recast_engine_test.dart
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "vibe"
flutter test test/ui/studio_shell/asset_library_page_test.dart --plain-name "vibe"
```

Expected: all focused tests PASS.

- [ ] **Step 3: Run formatting and analyze**

Run:

```powershell
dart format lib/ui/studio_script/widgets/studio_script_page.dart lib/ui/studio_script/view_models/studio_script_viewmodel.dart lib/ui/studio_shell/widgets/asset_library_page.dart lib/ui/studio_shell/widgets/studio_shell_view.dart lib/main.dart test/ui/studio_script/studio_script_page_test.dart test/ui/studio_shell/asset_library_page_test.dart test/data/studio/services/script_recast_engine_test.dart
flutter analyze
```

Expected: formatter succeeds; analyzer has no new errors from touched files.

### Task 4: Beads Closeout

**Files:**
- Modify: `.beads/issues.jsonl`
- Modify: `.beads/interactions.jsonl`

- [ ] **Step 1: Update Beads notes**

Run: `bd update NAI_NEW-2iw3 --notes "Implemented artist-chain default Vibe binding and script row manual Vibe additions; focused tests passing."`

- [ ] **Step 2: Close Beads issue**

Run: `bd close NAI_NEW-2iw3 --reason "Implemented and verified"`

Expected: issue status is closed.
