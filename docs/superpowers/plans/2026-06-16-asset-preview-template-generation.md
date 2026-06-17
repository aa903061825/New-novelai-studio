# Asset Preview Template Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable template-driven asset preview generation for artist chains and character cards.

**Architecture:** Keep prompt construction in `StudioAssetPreviewGenerationService`; the asset library UI only gathers generation options and passes them through. Existing image request/save and keep/discard behavior remains unchanged.

**Tech Stack:** Flutter/Dart, existing workspace models, existing NovelAI adapter, Flutter widget tests.

---

### Task 1: Service Options And Prompt Templates

**Files:**
- Modify: `lib/data/studio/services/studio_asset_preview_generation_service.dart`
- Test: `test/data/studio/services/studio_asset_preview_generation_service_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests that call the service with the desired API:

```dart
await service.generateCharacterPreview(
  'char-1',
  options: const StudioAssetPreviewGenerationOptions(
    artistChainId: 'chain-1',
  ),
);

await service.generateArtistChainPreview(
  'chain-1',
  options: const StudioAssetPreviewGenerationOptions(
    customPrompt: 'sparkling dust',
    customPromptMode: StudioPreviewCustomPromptMode.append,
  ),
);
```

Expected assertions:

- selected artist-chain prompt parts appear in character previews,
- `1girl` and `solo` appear,
- `single character` does not appear,
- append mode includes template and custom text,
- replace mode uses only custom positive text,
- generated `imageRefs` are still appended.

- [ ] **Step 2: Verify red**

Run:

```powershell
flutter test test/data/studio/services/studio_asset_preview_generation_service_test.dart
```

Expected: compile failure because `StudioAssetPreviewGenerationOptions` and the
new optional parameters do not exist.

- [ ] **Step 3: Implement minimal service API**

Add:

```dart
enum StudioPreviewCustomPromptMode { append, replace }

class StudioAssetPreviewGenerationOptions {
  final String? artistChainId;
  final String customPrompt;
  final StudioPreviewCustomPromptMode customPromptMode;

  const StudioAssetPreviewGenerationOptions({
    this.artistChainId,
    this.customPrompt = '',
    this.customPromptMode = StudioPreviewCustomPromptMode.append,
  });
}
```

Then add `options` parameters to the preview-generation methods and route prompt
construction through helper methods.

- [ ] **Step 4: Verify green**

Run the same service test command and confirm the new tests pass.

### Task 2: Random Artist Chain And Scene-Only Codex Inputs

**Files:**
- Modify: `lib/data/studio/services/studio_asset_preview_generation_service.dart`
- Test: `test/data/studio/services/studio_asset_preview_generation_service_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests for:

```dart
await service.generateCharacterPreview('char-1');
await service.generateArtistChainPreview('chain-1');
```

Expected assertions:

- when no character-preview artist chain is selected, the service chooses a
  deterministic random chain from workspace chains,
- artist-chain preview uses a deterministic random character from workspace
  characters,
- artist-chain preview uses only codex scene entries as scene text,
- non-scene codex entries do not leak into the prompt.

- [ ] **Step 2: Verify red**

Run:

```powershell
flutter test test/data/studio/services/studio_asset_preview_generation_service_test.dart
```

Expected: tests fail because random artist and scene codex behavior has not been
implemented yet.

- [ ] **Step 3: Implement random selection**

Use the existing injected `randomInt` function for all random pool choices.
Filter scene entries through `StudioLegacyCodexCategories.matches(entry,
StudioLegacyCodexCategories.scene.key)`.

- [ ] **Step 4: Verify green**

Run the same service test command and confirm the service suite passes.

### Task 3: Preview Options Dialog

**Files:**
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`
- Test: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add tests that:

- tap character preview,
- see a generation-options dialog before the loading dialog,
- choose a specific artist chain,
- enter custom prompt text,
- select replace mode,
- continue and verify the fake service receives those options.

Also add a light artist-chain test that confirms append-mode custom text is
passed through.

- [ ] **Step 2: Verify red**

Run:

```powershell
flutter test test/ui/studio_shell/asset_library_page_test.dart
```

Expected: tests fail because the options dialog does not exist.

- [ ] **Step 3: Implement UI wiring**

Add a small dialog near `_PreviewGenerationDialog` that returns
`StudioAssetPreviewGenerationOptions`. Use the current local catalog or snapshot
artist chains for the dropdown. Keep controls compact:

- artist-chain dropdown for character previews,
- prompt mode segmented control,
- custom prompt text field,
- primary action starts generation.

- [ ] **Step 4: Verify green**

Run the widget test command and confirm the new widget tests pass.

### Task 4: Final Verification

**Files:**
- Modify only files touched above if failures reveal small integration issues.

- [ ] **Step 1: Run targeted service tests**

```powershell
flutter test test/data/studio/services/studio_asset_preview_generation_service_test.dart
```

- [ ] **Step 2: Run targeted widget tests**

```powershell
flutter test test/ui/studio_shell/asset_library_page_test.dart
```

- [ ] **Step 3: Run targeted analysis**

```powershell
flutter analyze lib/data/studio/services/studio_asset_preview_generation_service.dart lib/ui/studio_shell/widgets/asset_library_page.dart
```

- [ ] **Step 4: Update Beads**

Close `NAI_NEW-431f` only if implementation and verification succeed.
