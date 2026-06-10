# Workbench Single Image Parameters Design

Date: 2026-05-24
Beads issue: `NAI_NEW-dwo`

## Goal

Reframe the workbench parameter surface as a complete single-image creation console.

The workbench should help the user compose one image at a time: pick assets, write and arrange prompts, tune the next request, add reference inputs, generate one result, and inspect that result. It must not expose batch production controls or environment settings.

## Scope

### In Scope

- Replace the workbench's generic parameter/reference tab feel with a single-image generation console.
- Keep the existing workbench layout intent: asset drawer on the left, prompt composition in the center, generation controls and results on the right.
- Expose the parameters that a user naturally adjusts while iterating on one image.
- Keep positive prompt editing in the center prompt composer.
- Keep negative prompt and request-shaping controls in the right generation console.
- Make reference inputs available from the workbench because they affect the next single image.
- Keep workbench state separate from the batch pipeline payload and execution state.

### Out of Scope

- Batch counts, request pacing, retry timing, resume state, queue plans, and batch resolution lists.
- NAI token, output directory, proxy, file prefix, metadata erase, or other production-environment settings.
- Reintroducing per-field `Global` toggles to the workbench.
- Changing the actual NovelAI request API beyond using the already supported payload fields.
- Rebuilding the whole prompt composer or asset library.

## Product Shape

The right side of the workbench becomes a "single image generation console" instead of a reused configuration page.

Recommended structure:

1. recent results and current generation status,
2. generate button and core request parameters,
3. reference input section,
4. advanced section for less common single-image switches.

This supports the intended work loop:

1. pick material from the left asset drawer,
2. assemble or edit the prompt in the center composer,
3. tune one image request on the right,
4. generate and inspect the latest result.

## Parameter Groups

### Core Output

These controls should be directly visible because they are the high-frequency knobs for a single image:

- generation model,
- image size,
- sampling steps,
- Prompt Guidance / scale,
- Prompt Guidance Rescale / cfg rescale,
- sampler,
- noise schedule.

The UI should favor compact controls over long list rows. The user should be able to see the current effective request without reading a settings page.

### Randomness

These controls shape variation for the next image only:

- random seed toggle,
- fixed seed input when random seed is disabled,
- Variety+ toggle.

Default behavior should remain random seed enabled. Turning it off reveals the fixed seed value. This state belongs to workbench single-image generation, not batch resume or queue progression.

### Prompt Control

The center composer owns the positive prompt.

The right console owns prompt controls that shape the request around that composition:

- negative prompt / UC,
- Legacy Prompt Conditioning Mode,
- automatic character position when supported by the selected model.

The workbench should avoid a second positive prompt field in the right console. That prevents the user from wondering which positive prompt will be sent.

### Reference Inputs

Reference inputs remain part of the workbench because they are creative inputs for the next single image:

- Vibe Transfer enable state and entries,
- image-to-image source and strength,
- precise reference images and their strength/fidelity/type controls.

The section can be collapsed, but the collapsed state should show whether references are active and how many are attached.

### Advanced

Advanced single-image controls can be grouped below the common controls:

- Legacy Prompt Conditioning Mode,
- noise schedule when it is not already promoted into the core group for the selected model,
- SMEA / SMEA DYN for models that still support them,
- dynamic thresholding if the existing payload path still exposes it.

Advanced does not include batch or environment settings.

## Explicitly Removed From Workbench

The workbench must not show:

- batch resolution enable/list/mode,
- batch total count,
- request count per batch,
- interval and jitter controls,
- 429 retry delay and retry toggle,
- pending batch resume controls,
- batch queue or plan controls,
- per-parameter `Global` toggles,
- NAI token,
- output folder,
- HTTP proxy,
- output file name prefix,
- metadata erase/custom metadata controls.

These belong to the batch pipeline or the broader application environment, not single-image creation.

## State And Boundaries

The workbench should keep using its own `PayloadConfig` and `CommandStatus` instance.

Parameter editing rules:

- workbench controls write to the workbench payload only,
- batch pipeline controls write to the named batch payload only,
- settings page does not mutate generation or batch execution fields,
- saved workbench documents include creative request state but not secrets or batch execution state.

The implementation should avoid using `ParametersConfigView` unchanged in the workbench if that widget continues to include batch-only or global-override controls. A dedicated workbench parameter view, or a filtered single-image mode for the parameter view, is preferred.

## Error Handling

The design keeps existing generation error behavior from `GenerationPageViewmodel`.

Additional behavior:

- invalid manual size input should be ignored or normalized to a valid 64-pixel multiple, consistent with existing size handling,
- disabling random seed should not clear the current seed,
- reference sections should show an empty state without blocking text-to-image generation,
- unsupported controls for the selected model should be hidden or disabled rather than silently sent.

## Testing

### Widget Coverage

- workbench renders a single-image parameter console instead of the reused batch/global parameter surface,
- batch-only controls are absent from the workbench,
- core output controls are visible in the workbench,
- positive prompt remains in the center composer and is not duplicated in the right console,
- random seed toggle reveals fixed seed input only when disabled,
- reference section shows active status and attached count.

### View Model Coverage

- editing workbench parameters updates the workbench payload instance,
- editing batch parameters does not update the workbench payload instance,
- workbench generation still uses the workbench payload and command status,
- metadata import into workbench parameters updates the workbench payload only.

### Regression Coverage

- batch pipeline still owns batch count, pacing, retry, output, proxy, token, and metadata settings,
- settings page does not expose generation or batch execution settings,
- existing single-image generation command path still works,
- saved workbench transfer preserves creative request state without transferring secrets or batch execution state.

## Acceptance Criteria

`NAI_NEW-dwo` is complete when:

1. the approved workbench parameter boundary is documented,
2. the design identifies the workbench parameter groups and removed batch/environment controls,
3. the design keeps positive prompt ownership in the center composer,
4. the design preserves reference inputs as single-image creative inputs,
5. the design states that workbench and batch pipeline payloads remain separate,
6. the next implementation plan can be written without re-litigating which controls belong to the workbench.
