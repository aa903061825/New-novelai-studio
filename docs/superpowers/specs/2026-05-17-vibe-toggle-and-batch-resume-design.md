# Vibe Toggle And Batch Resume Design

## Goal

Add two related runtime workflow features:
- a single master `vibe` enable/disable switch that can temporarily disable vibe transfer without deleting vibe lists
- resumable batch generation controls that can continue an unfinished batch from the last stop point or from a user-specified generation number

Also bump the app version from `0.9.4` to `0.9.5`.

## Scope

Included:
- Add one unified `vibe` master switch for vibe transfer.
- Place that switch inside the vibe-list editing experience, not on the generation page.
- When `vibe` is disabled, keep existing vibe lists intact but visually dim and disable the list UI.
- Make payload generation ignore vibe data entirely while the master switch is off.
- Record unfinished batch progress for both manual stop and app/process closure before normal completion.
- Make the normal start action always begin from the start of a new batch.
- Add a dedicated `continue from last time` action.
- Add a dedicated `continue from specified number` action.
- Allow resumed runs to be stopped again and resumed again later.
- Use the current UI/config values when resuming instead of replaying an old frozen payload snapshot.
- Persist the new runtime state locally across restarts.
- Bump the app version to `0.9.5`.

Not included:
- Deleting or rewriting existing vibe lists when disabling vibe.
- Saving the `vibe` enabled/disabled state into exported config JSON.
- Replaying an exact historical batch snapshot with old prompt/parameter values.
- Changing saved prompt/config semantics.
- Changing current file-naming format beyond what is required to continue sequence progress.

## Current Problem

Two workflow gaps exist today:

1. Vibe transfer is effectively on whenever the relevant vibe list is populated, so there is no quick way to keep the list but temporarily disable its effect.
2. Batch generation progress is only tracked in live memory. If the user stops manually or closes the app before a finite batch finishes, there is no dedicated resume workflow. The normal start button also needs to stop behaving like an implicit resume path.

The requested behavior is:
- `start` should always mean `start from the beginning`
- `continue from last time` should continue only the unfinished remainder
- `continue from specified number` should generate from user-facing generation number `N` up to the target total count
- an unfinished resumed batch can be stopped again and resumed again later

## Design

### 1. Separate machine-local runtime state

Introduce a dedicated runtime state model for local workflow state, separate from config-owned content.

This state should hold:
- `vibeEnabled`
- `hasPendingBatchResume`
- `resumeTargetTotalCount`
- `resumeCompletedCount`
- `resumeStartedAt` or equivalent diagnostic timestamp

Design rules:
- This model is machine-local runtime state, not exported config content.
- It must persist locally across restarts.
- It must not be serialized into saved config JSON or imported/exported config files.
- It must remain stable when switching saved prompt/config entries.

Recommended defaults:
- `vibeEnabled = true` to preserve current behavior for existing users
- no pending resume record by default

### 2. Unified vibe master switch

Add one unified master switch for vibe transfer regardless of whether the app is currently using:
- legacy vibe config
- V4 vibe config
- V4.5 vibe config while in vibe mode

Placement rule:
- render the switch inside the vibe-list editing view, at the top of the list content
- do not move it to the generation page

Behavior rules:
- switch on:
  - vibe list UI is fully interactive
  - generation may use vibe payload data as usual
- switch off:
  - vibe list UI stays visible but dimmed
  - add/edit/delete/import interactions are disabled
  - the underlying lists remain untouched
  - generation must behave as if no vibe list were present

For V4.5:
- existing `precise reference` switching behavior stays intact
- if `precise reference` is active, the current precise-reference path still takes precedence
- if the user is in vibe mode and `vibeEnabled` is false, vibe payload data is skipped entirely

### 3. Explicit batch resume record

Persist unfinished finite-batch progress using successful-generation count, not a brittle file-name index.

Recommended semantics:
- `resumeTargetTotalCount` stores the intended finite total for that batch
- `resumeCompletedCount` stores how many images were successfully completed
- the next resume point is therefore `resumeCompletedCount + 1` in user-facing terms

This avoids ambiguity:
- the user-facing `from specified number` input is 1-based
- internal command counters can still use the app's existing zero-based counters as needed

Persistence rules:
- create/update the resume record when a finite batch starts
- update it after every successful image generation
- keep it when the user manually stops an unfinished batch
- keep it across app restart if the batch was unfinished
- clear it only when the batch finishes normally

Out-of-scope simplification:
- resume support is defined only for finite batches where `numberOfRequests > 0`
- unlimited generation mode does not create a resumable target record in this design

### 4. Start versus continue behavior

The app must separate `start from scratch` from `continue`.

Normal start action:
- always resets in-memory batch progress to zero
- always starts a fresh batch from generation `1`
- if an old pending resume record exists, starting a new batch replaces it with the new active batch state

`Continue from last time` action:
- available only when a pending finite resume record exists
- resumes from the next unfinished user-facing generation number
- runs only until the saved target total count is reached

`Continue from specified number` action:
- opens an input flow for a user-facing generation number `N`
- interprets `N` as `start generating from the Nth image`
- uses the current UI-configured finite total count as the end point
- with total `100` and input `50`, the run generates `50` through `100`
- validates `1 <= N <= current target total`

Both continue actions:
- use the current UI/config values at execution time
- do not restore an old frozen payload snapshot
- may be manually stopped again
- update the pending resume record again after that stop

### 5. Generation flow changes

`GenerationPageViewmodel` should gain explicit entrypoints instead of routing everything through the current toggle behavior alone.

Recommended command entrypoints:
- `startBatchFromScratch()`
- `resumeBatchFromLast()`
- `resumeBatchFromNumber(int startNumber)`
- `stopBatch()`

Behavior changes:
- the existing start/stop floating control should call `startBatchFromScratch()` when idle
- `toggleBatch()` may remain as a thin wrapper, but its idle path must never reuse pending resume state
- resume entrypoints must initialize `currentTotalCount` from the requested start position instead of always from zero
- the generation-completion path must clear the saved resume record on normal finish

To support app closure recovery:
- persist resume state eagerly during batch progress instead of relying only on graceful shutdown hooks
- graceful stop/close hooks can still flush the latest state, but they are not the only protection

### 6. Generation page UI

Add two new dedicated controls on the generation page:
- `continue from last time`
- `continue from specified number`

UI rules:
- these are separate actions, not hidden behind the default start button
- `continue from last time` is disabled or hidden when no pending resume record exists
- `continue from specified number` should prompt for a numeric start value
- `continue from specified number` is available only when the current configured total count is finite and greater than zero
- the existing start/stop control remains the main fresh-start control

This keeps the three meanings explicit:
- start fresh
- continue last unfinished batch
- continue from a chosen generation number

### 7. Local persistence boundary

Persist the new runtime state through dedicated local storage keys, separate from config serialization.

This state must not travel through:
- `PayloadConfig.toJson()`
- saved config export/import
- saved prompt config lists

This keeps the feature aligned with user intent:
- vibe toggling is a quick runtime workflow switch
- batch resume is a local convenience state
- neither should silently mutate saved config data

### 8. Version bump

Update the app version to `0.9.5` in the release metadata used by the Flutter app packaging flow.

## UI

Vibe page:
- show one master `enable vibe` switch at the top of the vibe-list content
- when off, the existing list remains visible but visually disabled/dimmed

Generation page:
- keep the existing main start/stop button
- add one new control for `continue from last time`
- add one new control for `continue from specified number`

Input semantics:
- the specified-number dialog uses user-facing 1-based numbering
- invalid input should be rejected with a clear validation message

## Files Expected To Change

- `lib/data/models/payload_config.dart`
  - hold or expose the new local runtime state without exporting it as config JSON
- `lib/data/models/command_status.dart`
  - support clearer start-versus-resume runtime progress semantics if needed
- `lib/data/services/config_service.dart`
  - load/save the new runtime state through dedicated local storage keys
- `lib/main.dart`
  - initialize the runtime state during app startup
- `lib/ui/i2i_tab/widgets/i2i_tab_view.dart`
  - place or coordinate the unified vibe switch with the current vibe/precise-reference layout
- `lib/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart`
  - expose unified vibe-enabled state and update actions
- `lib/ui/vibe_config/widgets/vibe_config_list_view.dart`
  - render the master vibe switch and disabled-list state for legacy vibe mode
- `lib/ui/vibe_config_v4/widgets/vibe_config_v4_list_view.dart`
  - render the master vibe switch and disabled-list state for V4 vibe mode
- `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
  - split fresh-start and resume flows
  - persist unfinished progress
  - clear progress only on normal completion
- `lib/ui/generation_page/widgets/generation_page_view.dart`
  - add the two new continue controls
- `lib/data/use_cases/generate_payload_use_case.dart`
  - skip vibe payload assembly when the master switch is off
- `pubspec.yaml`
  - bump version to `0.9.5`
- localization files under `assets/l10n/`
  - add labels, hints, validation messages, and button text for the new controls

## Testing

Add or update tests for:
- default `vibeEnabled` state for existing users
- persisting and restoring `vibeEnabled` across restarts
- ensuring vibe payload data is skipped when the switch is off
- ensuring vibe lists are preserved when the switch is off
- ensuring the vibe list UI becomes disabled/dimmed while the switch is off
- creating a pending resume record for finite batches
- updating the saved completed count after each successful generation
- keeping the pending resume record after manual stop
- restoring the pending resume record after app restart
- clearing the pending resume record after normal batch completion
- ensuring normal start always begins from zero and does not implicitly resume
- ensuring `continue from last time` resumes from the next unfinished generation
- ensuring `continue from specified number` uses 1-based input semantics and stops at the target total
- ensuring a resumed batch can be stopped and resumed again

## Risks

- V4.5 currently switches between vibe and precise reference in one tab, so the master vibe switch should not accidentally interfere with precise-reference-only behavior.
- Resume state must be persisted eagerly enough that app closure does not lose too much progress information.
- The current generation flow assumes `currentTotalCount = 0` on every idle-to-start transition, so resume entrypoints need explicit initialization to avoid off-by-one mistakes.
- The app currently supports unlimited batches, but this design intentionally limits resume support to finite batches to keep semantics predictable.

## Acceptance Criteria

- The user can disable vibe transfer without deleting existing vibe lists.
- Disabling vibe visibly dims and disables the vibe list UI.
- When vibe is disabled, generation requests omit vibe payload data.
- The default start action always starts from the beginning of a new batch.
- If a finite batch is stopped manually before completion, the app records enough progress to continue later.
- If the app is closed before a finite batch completes, the unfinished progress is still available after restart.
- The generation page provides a dedicated `continue from last time` action.
- The generation page provides a dedicated `continue from specified number` action.
- With total `100` and specified start `50`, the app generates from `50` through `100`.
- A resumed batch can be stopped again and resumed again later.
- The app version is updated to `0.9.5`.
