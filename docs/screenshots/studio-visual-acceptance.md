# Studio Visual Acceptance

Date: 2026-05-23
Beads issue: `NAI_NEW-frr`

## Goal

Provide a repeatable screenshot and visual acceptance path for Novel Studio UI
work without depending on the flaky local `toImage` widget screenshot flow.

This playbook is intentionally simple:

- use the static preview as the visual oracle
- use live Flutter pages for implementation verification
- store evidence screenshots in-repo under `docs/screenshots/`
- keep structural regression coverage in widget tests

## Sources Of Truth

Use these in order:

1. `novel-studio-ui-preview/index.html`
2. `novel-studio-ui-preview/preview-desktop.png`
3. `novel-studio-ui-preview/preview-mobile.png`
4. `docs/novel-studio-ui-direction.md`
5. `lib/ui/studio_core/theme/studio_tokens.dart`

The preview defines the intended information architecture and visual direction.
Flutter remains the real runtime implementation.

## Capture Flow

### 1. Capture The Preview Oracle

Open `novel-studio-ui-preview/index.html` directly in a browser and capture:

- desktop width: `1440 x 1024`
- compact/mobile width: `393 x 852`

Use these captures when:

- a page is being rebuilt for the first time
- the intended spacing or hierarchy is unclear
- reviewers need to compare the live Flutter page to the approved direction

### 2. Capture The Live Flutter Page

Run the app locally from the repo root:

```powershell
flutter run --no-pub -d windows
```

Navigate to the affected Studio page and capture the same two viewport classes:

- desktop/windowed reference
- compact/narrow reference

If a page is desktop-only for now, still verify that it does not break or clip
badly below `900px` width before marking the issue complete.

### 3. Store Evidence

Save evidence screenshots in `docs/screenshots/` using this format:

- `YYYY-MM-DD-<page>-preview-desktop.png`
- `YYYY-MM-DD-<page>-preview-compact.png`
- `YYYY-MM-DD-<page>-flutter-desktop.png`
- `YYYY-MM-DD-<page>-flutter-compact.png`

Example:

- `2026-05-23-gallery-flutter-desktop.png`
- `2026-05-23-gallery-flutter-compact.png`

Do not overwrite the canonical preview baselines:

- `novel-studio-ui-preview/preview-desktop.png`
- `novel-studio-ui-preview/preview-mobile.png`

## Acceptance Checklist

Every Studio UI change should be checked against all of the following:

- dark base surfaces remain dominant; no fallback light panels
- primary CTA stays yellow and readable against the dark background
- cards use black or very dark outlines instead of soft light borders
- decorative cards keep the sharp or near-right-angle lower-right corner
- buttons and chips stay pill-shaped
- CJK text is never italicized
- page spacing, radius, typography, and colors come from Studio tokens
- loading, empty, and error states match the same visual language
- desktop and compact captures both remain legible without overflow

## Minimum Verification Before Closing A UI Issue

Run the smallest relevant structural checks:

```powershell
flutter test --no-pub test/ui/studio_core/studio_theme_test.dart -r expanded
flutter test --no-pub test/ui/studio_core/studio_visual_acceptance_contract_test.dart -r expanded
```

Then run the page-specific widget tests for the surface you changed.

For large UI slices, also run:

```powershell
flutter analyze --no-pub
```

## Scope Notes

This workflow does not introduce automated pixel-perfect golden testing yet.

That is intentional:

- the local `toImage` path has already proven unreliable here
- manual OS-level screenshots are stable enough to unblock active Studio work
- widget tests and token contracts still guard against obvious structural drift

If the team later adds a reliable screenshot harness, this playbook should be
updated rather than replaced ad hoc.
