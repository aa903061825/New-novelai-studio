# Global Generation Params Design

## Goal

Add per-parameter global overrides for generation settings so the parameter page can quickly switch specific fields between:
- using the current config's saved value, or
- using a machine-local global value remembered across app restarts.

This feature applies to these five parameters only:
- `negative_prompt`
- `steps`
- `scale`
- `cfg_rescale`
- `sampler`

## Scope

Included:
- Add one small `global` toggle for each of the five parameters on the parameter page.
- When a parameter's toggle is enabled, the parameter page shows and edits the global value for that field.
- When a parameter's toggle is disabled, the parameter page shows and edits the current config's value for that field.
- Persist global values and toggle states locally across app restarts.
- Keep global values fully independent from imported/exported config JSON and saved config entries.
- Use the effective value selected by each toggle during payload generation.
- Apply the same source-selection rule when importing image metadata into parameters.

Not included:
- A single master switch for all parameters.
- Writing global values back into saved configs.
- Migrating all generation parameters to a global system.
- Separate global-parameter editing UI in the settings page.

## Current Problem

Today all five target fields live only inside `param_config`, so they are always tied to the current config. This makes it inconvenient to keep a shared negative prompt and shared sampling settings while still switching between different prompt/config presets.

The user wants a faster workflow:
- keep config-specific parameter values intact,
- optionally promote specific fields to global usage at runtime,
- edit those global values directly from the existing parameter page,
- and keep that preference after restarting the app.

## Design

### 1. Separate machine-local global parameter state

Introduce a dedicated model for the global generation parameter feature, separate from `ParamConfig` and separate from `Settings`.

Proposed fields:
- `useGlobalSteps`
- `useGlobalScale`
- `useGlobalCfgRescale`
- `useGlobalSampler`
- `useGlobalNegativePrompt`
- `steps`
- `scale`
- `cfgRescale`
- `sampler`
- `negativePrompt`

Design rules:
- This model represents machine-local runtime preference, not config content.
- It must persist locally across restarts.
- It must not be serialized into exported config JSON.
- It must not be overwritten when switching saved configs or importing configs.

### 2. Attach the global state to app runtime, not config files

Add the new global-parameter model to `PayloadConfig` as runtime state so the UI and generation flow can access it through the same shared container already used by the app.

Important boundary:
- `PayloadConfig.toJson()` must continue to serialize only config-owned data.
- The new global-parameter state must be excluded from config export/import payloads.

This keeps a clean separation:
- `ParamConfig` remains config-owned state.
- global generation params remain machine-local app state.

### 3. Persist global state via dedicated local storage keys

Persist the new global-parameter model through `ConfigService` using a dedicated storage key, for example `globalGenerationParams`.

Behavior rules:
- On app startup, load the current saved config as before.
- Separately load the global-generation-params state from local storage.
- If no saved global state exists yet, initialize defaults from the existing `ParamConfig` defaults.
- Whenever a global value or its corresponding toggle changes, save the global state immediately.

This persistence must be independent from:
- `savedConfig-<uuid>` entries
- imported config files
- exported config files
- config index metadata

### 4. Parameter-page interaction model

Keep the existing parameter page as the only editing entrypoint.

For each of the five target parameter rows, add a small trailing toggle labeled `global`.

Behavior rules per field:
- Toggle off:
  - the row displays the current config's value
  - editing changes `payloadConfig.paramConfig.<field>`
- Toggle on:
  - the row displays the global value
  - editing changes `payloadConfig.globalGenerationParams.<field>`

The page should not try to show both values at once. The visible/editable value always matches the currently selected source.

Recommended presentation:
- keep the existing row layout,
- place the small toggle on the right side of the row title area,
- reuse the same pattern consistently for sliders, selector rows, and negative-prompt editing.

### 5. Effective-value resolution for generation

Generation must stop reading these five fields directly from `ParamConfig` without source resolution.

Instead, compute an effective value for each field using the corresponding toggle:
- if `useGlobalSteps` is true, use global `steps`, else config `steps`
- if `useGlobalScale` is true, use global `scale`, else config `scale`
- if `useGlobalCfgRescale` is true, use global `cfgRescale`, else config `cfgRescale`
- if `useGlobalSampler` is true, use global `sampler`, else config `sampler`
- if `useGlobalNegativePrompt` is true, use global `negativePrompt`, else config `negativePrompt`

These effective values must drive:
- `ParamConfig.getPayload()` data used for request parameters
- NAI4 negative prompt construction in `GeneratePayloadUseCase`
- any other payload assembly path that currently reads the raw config-owned fields

Implementation direction:
- prefer one central resolution helper instead of scattering toggle checks throughout UI and payload code.

### 6. Metadata import behavior

Metadata import from image files currently writes directly into `ParamConfig`.

New behavior:
- if a target field's `global` toggle is off, importing metadata for that field updates the current config value
- if a target field's `global` toggle is on, importing metadata for that field updates the global value instead

This applies to:
- per-field import from the metadata dialog
- bulk import of all metadata

This rule keeps the parameter page behavior internally consistent:
- the user edits what they currently see,
- and metadata import updates the same source that the page is currently using for that field.

### 7. Reusable UI component support

The current parameter widgets do not expose a convenient trailing slot for the new small toggles.

Expected UI adjustments:
- extend the slider tile widget to support a trailing widget in the title row
- extend editable/selectable list-tile wrappers similarly if needed
- keep the change minimal and backward-compatible for existing call sites

This avoids ad hoc duplicated row layouts in the parameter page.

## UI

Parameter-page examples:
- `Sampling Steps: 28` with a small `global` checkbox/switch on the right
- `Prompt Guidance: 7.0` with its own `global` toggle
- `Prompt Guidance Rescale: 0.65` with its own `global` toggle
- `Sampler: k_euler_ancestral` with its own `global` toggle
- `UC` / negative prompt row with its own `global` toggle

Display rules:
- each field toggles independently
- no master switch
- when toggled on, the row immediately reflects the global stored value
- when toggled off, the row immediately reflects the config-owned value

## Files Expected To Change

- `lib/data/models/payload_config.dart`
  - hold the runtime global-generation-params state without serializing it into config JSON
- `lib/data/models/param_config.dart`
  - add effective-value helpers or accept resolved values for payload generation
- `lib/data/models/settings.dart`
  - no new global-generation fields should be added here in the recommended design
- `lib/data/services/config_service.dart`
  - load/save the dedicated machine-local global-generation-params state
- `lib/main.dart`
  - initialize the global-generation-params state during startup
- `lib/ui/parameters_config/view_models/parameters_config_viewmodel.dart`
  - read/write either config or global state based on each field's toggle
  - route metadata import to the active source per field
- `lib/ui/parameters_config/widgets/parameters_conifg_view.dart`
  - render the five small per-field global toggles
- `lib/ui/core/widgets/slider_list_tile.dart`
  - support trailing content for parameter-row controls
- `lib/ui/core/widgets/editable_list_tile.dart`
  - support trailing content if needed for consistent row layout
- `lib/data/use_cases/generate_payload_use_case.dart`
  - use effective resolved values instead of directly trusting config-owned raw fields

## Testing

Add or update tests for:
- loading default global-generation-params state when no local cache exists
- persisting and restoring global-generation-params state across restarts
- ensuring config import/export does not include or overwrite global-generation state
- ensuring saved-config switching does not change global values or toggle states
- resolving each of the five effective generation fields correctly
- updating config-owned fields when a field's global toggle is off
- updating global-owned fields when a field's global toggle is on
- metadata single-field import respecting the active source
- metadata bulk import respecting the active source for each relevant field

## Risks

- `ParamConfig.getPayload()` currently assumes the config object itself owns all generation values, so source resolution must be introduced carefully to avoid partial adoption.
- Metadata import currently writes raw parameter keys directly into `ParamConfig`, so per-field routing logic must be explicit to avoid inconsistent behavior.
- UI component changes should remain backward-compatible because slider/list-tile wrappers are used elsewhere.

## Acceptance Criteria

- Each of the five target parameters has its own `global` toggle on the parameter page.
- Enabling a field's toggle makes the page edit and display the machine-local global value for that field.
- Disabling a field's toggle makes the page edit and display the current config's value for that field.
- Global values and toggle states survive app restart.
- Switching saved configs does not change global values or toggle states.
- Importing/exporting config files does not include and does not overwrite global values or toggle states.
- Generation requests use the effective per-field source selected by the toggles.
- Existing config-specific parameter values remain intact and are not rewritten by this feature.
