# Novel Studio UI Preview

This folder is a standalone static UI preview for `docs/novel-studio-integrated-prd.md`.

- Open `index.html` directly in a browser.
- The preview is pure UI: no backend, no NAI calls, no local file writes.
- The layout follows the referenced ZZZ Studio rules: dark surfaces, yellow primary CTA, pill controls, and sharp bottom-right cards.
- Existing repository files are not changed by this preview.

## Integration Docs

If this preview is going to be folded into the real Flutter product, read these in order:

1. `docs/00-production-integration-overview.md`
2. `docs/01-flutter-page-map.md`
3. `docs/02-design-system-port.md`
4. `docs/03-data-contracts.md`
5. `docs/04-implementation-slices.md`

## Visual QA

When a Flutter Studio page is rebuilt against this preview, use the repo-local
playbook at `../docs/screenshots/studio-visual-acceptance.md`.

That playbook defines:

- the fixed capture path that replaces the flaky `toImage` widget screenshot flow
- the desktop and compact viewport targets
- the ZZZ Studio acceptance checklist for colors, card outlines, pill controls,
  sharp lower-right corners, and CJK-safe typography
- where to save evidence screenshots inside the repo
