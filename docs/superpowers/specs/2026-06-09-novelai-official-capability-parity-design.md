# NovelAI Official Image Capability Parity Design

Date: 2026-06-09
Beads issue: `NAI_NEW-kfle`

## Goal

Bring Studio Workbench into functional parity with the official NovelAI image
generation workflow, while preserving the stronger local CasRand, KAMIA, asset
library, and script-recast systems that already exist in this project.

Parity means the user can start from the workbench, use the same major creation
paths that NovelAI exposes, and round-trip generated results back into the
workbench without losing prompt, parameter, reference, or source-image context.

This design is intentionally staged. The first slices close the highest-impact
gaps in the current workbench generation loop. Heavy editor features such as a
full canvas and inpaint mask editor are placed later because they require a
separate interaction surface and a larger amount of visual QA.

## Official Source Baseline

The capability list is based on the current NovelAI documentation pages checked
on 2026-06-09:

- Image Generation overview: https://docs.novelai.net/en/image/
- Image Upload / Image2Image: https://docs.novelai.net/en/image/uploadimage/
- Strength and Noise: https://docs.novelai.net/en/image/strengthnoise/
- Vibe Transfer: https://docs.novelai.net/en/image/vibetransfer
- Precise Reference: https://docs.novelai.net/en/image/precisereference/
- Director Tools: https://docs.novelai.net/en/image/directortools/
- Canvas: https://docs.novelai.net/en/image/editimagecanvas/
- Inpaint: https://docs.novelai.net/en/image/inpaint
- Enhance: https://docs.novelai.net/en/image/enhance
- Upscale: https://docs.novelai.net/en/image/upscale
- Multi-Character Prompting:
  https://docs.novelai.net/en/image/multiplecharacters
- Prompt Randomizer: https://docs.novelai.net/en/image/promptrandomizer/
- Prompt Chunks: https://docs.novelai.net/en/image/promptchunks
- Add Quality Tags: https://docs.novelai.net/en/image/qualitytags/
- Undesired Content: https://docs.novelai.net/en/image/undesiredcontent/
- Seed: https://docs.novelai.net/en/image/seed
- Sampling: https://docs.novelai.net/en/image/sampling/
- Text Rendering: https://docs.novelai.net/en/image/textrendering
- Advanced Prompt Mixing: https://docs.novelai.net/en/image/promptmixing/

## Current State

The project already has many useful pieces:

- `ParamConfig` stores model, size, steps, sampler, scale, cfg rescale, noise
  schedule, seed, negative prompt, SMEA flags, dynamic thresholding, and related
  fields.
- `GeneratePayloadUseCase` builds the main `generate-image` payload and already
  handles V4 prompt structure, character prompts, Vibe Transfer, and Precise
  Reference.
- `I2IConfig`, `I2iVibeViewmodel`, and `I2iConfigView` already support a source
  image, source-image dimensions, Strength, Noise, metadata import, and target
  size suggestions.
- `I2iTabView` currently renders Vibe Transfer or Precise Reference, but does
  not render `I2iConfigView`.
- `WorkbenchSingleImageParametersViewmodel` counts I2I as a reference input and
  can report `hasI2iImage`, but does not own a complete I2I editing surface.
- `StudioGalleryService` and generation result cards already provide a local
  foundation for history, metadata, and result reuse.
- `WorkbenchTransferViewModel` and the workbench document model already cover
  import/export for many creative-state fields.
- Asset-library artist chains can bind Vibe references and merge those Vibes
  into the workbench.

The most important current gap is not lack of code, but lack of a complete
product loop. Several capabilities exist as isolated legacy widgets or fields,
while the workbench does not expose, persist, generate, and round-trip them as
official NovelAI-style workflows.

## Product Principles

- The workbench is the main creation surface. Official generation modes should
  appear there or flow there from the gallery.
- Preserve local project strengths. CasRand prompt trees, KAMIA blocks, asset
  library entries, artist-chain Vibes, and script-recast evidence should remain
  first-class local capabilities.
- Do not expose raw protocol complexity when a guided workflow is clearer.
  Advanced payload fields can exist in models and metadata without becoming
  noisy default UI.
- Every generated result must be reusable. The gallery should know enough about
  the prompt, parameters, source images, reference images, and mode to restore or
  continue a workflow.
- Mutually exclusive official features should be explicit. For example,
  Precise Reference and Vibe Transfer already have model-specific behavior; I2I,
  Enhance, and Inpaint also need clear mode boundaries.

## Capability Matrix

| Official capability | Current project state | Target state | Phase |
|---|---|---|---|
| Model selection for V4.5, V4, V3, Furry | Model constants exist | Model catalog follows official current models and drives feature availability | 0 |
| Resolution, image count, steps, guidance, sampler, seed | Mostly in `ParamConfig`; workbench exposes a subset | Workbench and batch profiles expose stable core settings and validate by model | 0-2 |
| Undesired Content and UC presets | Negative prompt exists; presets are incomplete | Model-aware UC presets plus custom negative prompt merge | 2 |
| Add Quality Tags | Field exists, payload currently forces false | Restored toggle with model-specific injected tags and metadata visibility | 2 |
| Multi-Character Prompting | V4 prompt structures and character cards exist | Up to six character cards with order, position, per-character UC, and metadata import | 1-2 |
| Image2Image | Models and legacy widget exist; workbench and payload are incomplete | Upload/drop source image, Strength, Noise, target size, metadata import, payload emission | 1 |
| Vibe Transfer | Existing V3/V4 payload support | Unified reference panel, enable switch, V4 strength normalization, asset-bound defaults | 1 |
| Precise Reference | Existing V4.5 payload support | Type, strength, fidelity, cost hint, import/export, gallery reuse | 1 |
| Prompt Randomizer | CasRand has stronger random trees; official syntax not first-class | Preserve and import official `||a|b||` syntax; show actual prompt after generation | 6 |
| Prompt Chunks | Local snippets/assets exist in other forms | Reusable chunk panel backed by local library, insert/search/nesting awareness | 6 |
| Tag suggestions and tag knowledge | Local tag/classification cache exists | Prompt editor suggestions with category and confidence cues | 6 |
| Text Rendering | Plain prompt only | Dedicated `Text:` helper that enforces final-position text rendering rules | 2 |
| Advanced Sampling, SMEA, SMEA DYN | Fields exist | Model-aware controls and safe metadata import without overexposing script-only fields | 2 |
| Prompt Mixing | No dedicated workflow | V3-or-lower helper and validation for `prompt|prompt:weight` syntax | 6 |
| Director Tools | Not implemented as workflows | Tool panel for Remove BG, Line Art, Sketch, Colorize, Emotion, and Declutter | 4 |
| Canvas / Edit Image | Not implemented | Separate editor surface for draw, erase, fill, select, lasso, crop, export, save as I2I base | 5 |
| Inpaint | Not implemented | Mask editor and inpaint generation mode with gallery/workbench entry points | 5 |
| Enhance | Not implemented | Result action that reruns image through diffusion with magnitude or individual settings | 3 |
| Upscale | Not implemented | Result action with size-limit validation and no prompt influence | 3 |
| History / metadata inspect / reuse | Gallery and metadata foundation exists | Official-style restore, seed reuse, use as base image, actual prompt import | 3 |

## Phased Design

### Phase 0: Capability Contracts And Payload Baseline

Create a shared generation-mode contract before building more UI. The mode
should distinguish at least:

- `textToImage`
- `imageToImage`
- `enhance`
- `upscale`
- `inpaint`
- `directorTool`

The contract should define:

- which source images are required,
- which reference systems are allowed,
- which parameters are visible,
- which parameters are emitted,
- what metadata must be recorded for gallery reuse,
- what validation errors block generation.

Phase 0 also updates model metadata so the UI can ask whether a feature is
available for the selected model instead of scattering string checks across
widgets.

Acceptance:

- Unit tests cover payload generation for text-to-image, I2I source image,
  Vibe, Precise Reference, quality tags, UC presets, and model-gated fields.
- Existing Vibe and Precise Reference tests keep passing.
- Workbench import/export schema has a stable place for generation mode and
  source-image metadata.

### Phase 1: Workbench Reference And Control Loop

Make the workbench reference panel match the official creation loop. The first
ship target is Image2Image because it is currently the clearest broken promise:
the project has legacy I2I pieces, but the workbench does not present or submit
them as a complete mode.

This phase includes:

- a source-image drop/upload area inside `Workbench > Reference and Control`,
- source-image preview, dimensions, and clear action,
- Strength and Noise controls shown only when a source image is present,
- target-size suggestions based on the source image,
- metadata import from uploaded NAI PNGs,
- payload emission for I2I,
- gallery result metadata that records source image, Strength, Noise, and mode,
- a single unified visual summary for I2I, Vibe, and Precise Reference counts.

Vibe Transfer and Precise Reference remain in this phase because they share the
same reference panel and import/export story.

Acceptance:

- Dropping or picking an image sets the I2I source on the active workbench
  payload.
- Generation sends the source image and Strength/Noise in the request.
- Clearing the source image returns generation to text-to-image behavior.
- Metadata import can update model, size, sampler, steps, scale, seed, and UC
  without destroying the uploaded source image.
- Vibe and Precise Reference remain usable and their mutual-exclusion behavior
  is visible to the user.

### Phase 2: Official Core Settings

After the reference loop is working, fill in the official settings that affect
ordinary generation quality and reproducibility.

This phase includes:

- model-aware Add Quality Tags,
- model-aware Undesired Content presets,
- seed reuse and seed lock behavior,
- model-aware sampler and schedule controls,
- SMEA and SMEA DYN behavior where supported,
- Text Rendering helper for `Text:` sections,
- clearer metadata import choices for original prompt versus actual prompt.

Acceptance:

- The generated payload and metadata explain whether quality tags and UC presets
  were active.
- Switching models updates available presets and sampler controls.
- Text Rendering helper keeps the text block at the end of the base prompt.
- Seed copied from a gallery item can be applied to the workbench.

### Phase 3: Result Reuse, Enhance, And Upscale

Add official-style actions to generated images and gallery records. This phase
does not need a full canvas. It turns the result cards into a creation loop:

- use as base image,
- apply seed,
- restore prompt and settings,
- import actual prompt,
- enhance,
- upscale.

Enhance uses prompt-aware diffusion and should expose magnitude plus an
individual Strength/Noise option. Upscale is a separate, non-prompt action with
size validation and different metadata.

Acceptance:

- A generated image can become the I2I source with one action.
- Enhance creates a new gallery item linked to the source image and source
  parameters.
- Upscale rejects unsupported source sizes before calling the service.
- Gallery records display enough lineage to understand what operation produced
  them.

### Phase 4: Director Tools

Director Tools are image operations, not normal prompt generation settings.
They should use a separate tool panel launched from a gallery item or current
workbench source image.

The first Director Tools set:

- Remove Background, with Masked, Generated, and Blend result variants.
- Line Art.
- Sketch.
- Colorize, with prompt and defry controls.
- Emotion, with emotion level and prompt.
- Declutter.

Acceptance:

- Each Director Tool has a typed request model and result record.
- Tool results can be saved to gallery and reused as an I2I source.
- Failures preserve the original image and record the failed action in a
  recoverable task/result state.

### Phase 5: Canvas And Inpaint

Canvas and Inpaint need a dedicated editing surface. They should not be squeezed
into the existing compact reference panel.

Canvas minimum viable scope:

- open from workbench source image, gallery image, or blank canvas,
- draw, erase, fill, color picker,
- basic selection or crop,
- undo and redo,
- crop or resize to the closest valid generation size,
- download/export,
- save and return as I2I source image.

Inpaint minimum viable scope:

- open from gallery or current I2I source,
- draw mask,
- preview masked area,
- generate inpaint result,
- save result and allow use as base image.

3D model layers are explicitly a later extension after the 2D editor is stable.

Acceptance:

- Canvas images can be round-tripped into I2I generation.
- Inpaint requires a source image and a non-empty mask.
- Editor actions are visually verified on desktop and a constrained viewport.
- No source image is overwritten without an explicit save/replace action.

### Phase 6: Prompt Productivity Parity

This phase aligns official prompt-writing helpers with the project's stronger
local prompt and asset systems.

This phase includes:

- official Prompt Randomizer syntax support,
- visible actual-prompt output after randomization,
- Prompt Chunks stored locally as reusable assets,
- chunk search and insertion with `@`,
- safe nested chunk expansion,
- tag suggestions from the local tag/classification cache,
- V3-or-lower Prompt Mixing helper and validation.

Acceptance:

- Prompt editor can preserve official syntax when importing NAI metadata.
- User can save selected prompt text as a local chunk and insert it later.
- Prompt Randomizer content does not break Multi-Character prompt separators.
- Prompt Mixing helper is hidden or disabled for V4 models.

## Data Model Notes

The workbench export/import schema should include these stable concepts:

- `generationMode`
- `sourceImage`, stored as base64 or a durable local reference depending on the
  existing document policy
- `sourceImageWidth` and `sourceImageHeight`
- `imageToImageStrength`
- `imageToImageNoise`
- `qualityTagsEnabled`
- `undesiredContentPreset`
- `actualPrompt`, when available after randomizer expansion
- `lineage`, for generated results that come from Enhance, Upscale, Inpaint, or
  Director Tools

Avoid duplicating source images unnecessarily in long-lived gallery indexes. The
gallery can keep path references and lightweight thumbnails where possible, but
portable workbench exports need enough information to restore the active
creative state on another machine.

## Testing Strategy

- Unit tests for payload generation by mode.
- Widget tests for workbench reference panel state transitions.
- Import/export round-trip tests for workbench documents with source images and
  official prompt features.
- Gallery lineage tests for result reuse, Enhance, Upscale, and Director Tools.
- Service tests for validation before sending expensive or invalid API calls.
- Visual tests or screenshots for Canvas and Inpaint when those phases begin.

## Out Of Scope For This Roadmap

- NovelAI account management, billing, subscription, or web session sync.
- Server-side Prompt Chunk sync. Local chunks are enough for this project.
- Recreating every official UI detail pixel-for-pixel.
- Public cloud storage for source images or gallery records.
- 3D model layers in the initial Canvas/Inpaint implementation.

## Rollout Order

1. Phase 0, because later UI should depend on shared feature availability and
   payload contracts.
2. Phase 1, because I2I is currently partially present but functionally broken
   in the workbench loop.
3. Phase 2, because official core settings influence every generation mode.
4. Phase 3, because result reuse makes existing generated images productive.
5. Phase 4, because Director Tools are independent image actions.
6. Phase 5, because Canvas/Inpaint are large visual tools and should be built
   on the source-image/result-reuse foundation.
7. Phase 6, because prompt productivity benefits from the stable generation
   modes and metadata import behavior established earlier.

## Self-Review

- No implementation phase depends on an unspecified external service beyond the
  existing NovelAI image API path already used by the project.
- The first implementation slice is narrow enough to ship independently:
  contracts plus Image2Image closure.
- Later heavy visual tools are separated from payload and settings work.
- The design keeps local asset/library strengths instead of replacing them with
  a literal copy of the official UI.
- The roadmap does not require git operations and can be tracked through
  `NAI_NEW-kfle` plus follow-up Beads issues.
