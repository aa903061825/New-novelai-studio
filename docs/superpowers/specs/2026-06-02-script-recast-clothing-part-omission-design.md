# Script Recast Clothing Part Omission Design

## Goal

Define the UI and generation rule for clothing parts that are not detected in a Script Recast outfit stage. The rule should preserve the source script, avoid false clothing inheritance, and keep manual correction lightweight.

## Decision

An undetected clothing part is omitted from generation by default, but it remains editable in the UI. The UI must present this as a grey inactive-looking row, not a disabled control.

If the user types, selects, or drops a value into the grey row, that part becomes enabled and is included in the formal generation payload. If the user clears the value, the row returns to the grey omitted state.

## Terms

- Outfit stage: a meaningful core outfit category, such as school uniform, sleepwear, towel wrap, armor, or dress.
- Clothing state: a modifier on an existing outfit, such as torn, damaged, wet, dirty, pulled up, half removed, or stained.
- Clothing part omission: a missing part such as no detected upper clothing, no shoes, no socks, or no coat. Omission is not a separate outfit stage and is not itself a clothing state.

## UI Rules

Each outfit stage should show editable part rows for identity, upper body, lower body, upper clothing, and lower clothing.

For a clothing part with detected content:

```text
上装  white shirt
```

For a clothing part with no detected content:

```text
上装  未检测到，默认不传入
```

The undetected row is visually grey, but the input/drop target remains active. User-provided content immediately enables the row.

If an entire outfit stage has no detected upper clothing across all of its frames and state variants, the upper clothing row is grey at the stage level.

If only some frames omit a part while the stage has a detected core part, the stage row stays normal and the exception appears under frame overrides:

```text
上装  white shirt

帧覆盖
12-14：上装不传入，证据 no shirt
```

## Generation Rules

Formal generation is deterministic. AI extraction may suggest fields and evidence, but final payload assembly decides what is sent.

For each frame:

1. Select the source role and outfit stage by `frameIndexes`.
2. Start with the target role identity.
3. Include enabled body and clothing fields from the current stage.
4. Omit grey undetected clothing parts.
5. Apply frame overrides, including per-frame omissions and clothing state terms.
6. Preserve source action, expression, scene, camera, composition, quality, negative prompt, coordinates, and generation parameters.

Part inclusion rules:

```text
field has user or detected value -> include it
field is grey undetected -> omit it
field has per-frame omission -> omit it for those frames
field has explicit source missing evidence -> omit it and preserve the evidence cue
```

This means an empty upper clothing field does not inherit from the target outfit automatically. If the user wants a default upper clothing item, they can add it to the role, outfit, or grey row; adding content enables transmission.

## AI Handling

AI should classify clothing evidence into:

- core outfit stage,
- clothing state terms,
- missing or omitted part evidence,
- uncertain terms for review.

AI should not invent clothing parts to fill blanks. When no upper clothing evidence exists, it should leave upper clothing empty and may add a missing-field note. The application displays that as a grey omitted row.

AI should not create a new outfit stage solely because one part is absent. A new outfit stage is created only when the core outfit category changes.

## Examples

### Entire Stage Has No Upper Clothing

Source evidence:

```text
pleated skirt, black boots
```

UI:

```text
上装  未检测到，默认不传入
下装  pleated skirt, black boots
```

Generation includes lower clothing and omits upper clothing.

### Some Frames Omit Upper Clothing

Stage:

```text
上装  white shirt
下装  pleated skirt
```

Frame override:

```text
12-14：上装不传入，证据 no shirt
```

Frames 1-11 include `white shirt`. Frames 12-14 omit `white shirt` and preserve `no shirt`.

### User Enables A Grey Row

Initial UI:

```text
上装  未检测到，默认不传入
```

After user entry:

```text
上装  white blouse
```

Generation includes `white blouse`.

## Non-Goals

- Do not add a full four-state clothing part model in this decision.
- Do not create extra outfit stages for simple part omissions.
- Do not block editing of grey rows.
- Do not let AI directly rewrite final production prompts.

## Testing Notes

- ViewModel tests should verify grey undetected rows are editable and become enabled when filled.
- Payload tests should verify omitted parts are not sent when the row is empty.
- Payload tests should verify user-filled grey rows are sent.
- Frame override tests should verify a detected stage part can be omitted only for specific frames.
