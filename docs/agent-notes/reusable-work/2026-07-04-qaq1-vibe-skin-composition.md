# QAQ1 Vibe Skin And Composition Record

## Trigger

Use this note when iterating QAQ1 / QAQ artist-chain Vibe experiments, especially when the user says the goal is skin quality, sheer stockings, or reducing Vibe dependency.

## User Goal

The core objective is not "skin only" and not "legs only". The goal is to keep the desired soft luminous skin, warm skin tone, and sheer stocking material across full-body and lower-body areas while preventing Vibe from changing composition, outfit, or character layout.

## Working Hypothesis

Vibe composition drift comes mostly from source encodings that include strong pose/camera/layout signals, especially low-angle lower-body crops. A better Vibe bank should be multi-scale:

- one full-body or head-to-toe source,
- one balanced full-body/half-body source with visible skin and stockings,
- one lower-body material source,
- low `reference_information_extracted_multiple` and modest strength.

## Experiment Notes

Initial skin-source Vibes improved skin but still encoded too much lower-body crop/sitting/wardrobe bias. V2 sources were cleaner for composition, though one "fullbody" source still collapsed into a lower-body material crop. The balanced V2 source was the cleanest full-body Vibe source.

The user later fixed the allowed control surface to pure text-to-image plus Vibe only: no img2img, no Director, and no direct image initialization. Under that constraint, the strongest pattern is to use a material-swatch Vibe rather than a human-pose Vibe, then add a very low-strength composition-anchor Vibe encoded from a no-Vibe text-to-image baseline using the same prompt and seed.

For visible white-stocking tests, a synthetic warm-white nylon material swatch worked better than a pure-white swatch. Pure-white swatches made the whole image too washed out; the warmer swatch kept the nylon glow while preserving more skin warmth.

## Useful Paths

- V2 skin Vibes: `C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest\skin-vibes`
- Best pure text-to-image candidate: `hanabi-p1-qaq1-skinvibe-multiscale-v2-t2i-i006-s014-seed544884037.png`
- Guarded text-to-image candidate: `hanabi-p1-qaq1-skinvibe-multiscale-v2-t2i-i008-s016-guard-seed544884037.png`
- White-stocking material swatch: `qaq1-material-swatch-white-stockings-v2.naiv4vibe`
- White-stocking full-body test folder: `C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest\white-stockings-low-angle-fullbody`
- Best pure Vibe white-stocking tradeoff so far: `white-fullbody-lowangle-vibe-v2-anchor-i002-s018-a022-seed544888547.png`

## Reuse Guidance

For future tests, judge success by this order:

1. Composition and character layout are preserved.
2. Outfit is not rewritten.
3. Skin and stocking material improve.
4. Artist-chain style remains close to QAQ1.

Avoid judging by skin alone; a beautiful skin result that changes the composition has failed the core goal.

Current pure Vibe recipe to reuse first:

- material Vibe: `qaq1-material-swatch-white-stockings-v2.naiv4vibe`, `information_extracted` around `0.02`, strength around `0.18-0.20`;
- composition anchor Vibe: no-Vibe baseline generated from the same prompt and seed, `information_extracted` around `0.04-0.05`, strength around `0.16-0.22`;
- prefer prompt-level framing such as `entire full body visible from head to shoes`, `shoes fully visible near bottom of frame`, and negative `cropped feet`, `feet out of frame`, instead of increasing Vibe strength.

## Pepe Multi-Angle 0.33 Source Vibe Test

The user switched the character test to Pepe / Pecorine-inspired adult styling and requested multiple camera angles plus a `0.33` source Vibe as a skin-color benchmark. Outputs are in `C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\assets\references\qaq1-abtest\pepe-multi-angle`.

The generated benchmark source is `pepe-skin-source-033.naiv4vibe`, encoded from `pepe-skin-source-033-seed544890134.png`, with default `information_extracted: 0.33` and `strength: 0.33`.

Findings:

- `0.33` source Vibe alone makes the warm skin and white nylon transition easier to see, so it is useful as an effect baseline.
- It also pulls the result toward the source image's studio/full-body layout, simplifies or rewrites backgrounds, and changes outfit structure.
- For final use, keep the `0.33` source Vibe as a visual benchmark or use it only very weakly. Prefer material swatch plus per-angle composition anchor for composition-sensitive prompts.
- In the Pepe test, the material-anchor recipe was `qaq1-material-swatch-white-stockings-v2.naiv4vibe` at `info 0.02 / strength 0.20` plus the same-angle no-Vibe anchor at `info 0.06 / strength 0.26`.
