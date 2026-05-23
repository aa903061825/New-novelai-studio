# Novel Studio UI Direction

Date: 2026-05-22

## Project Rule

Future Novel Studio production work must use `novel-studio-ui-preview` as the visual and information-architecture source of truth.

- Do not keep or extend the old CasRand / Playful Geometric shell as the product exterior.
- Do not embed the preview as a WebView.
- Port the preview into native Flutter: shared theme tokens, reusable Studio components, a Studio shell, and page-level Flutter widgets.
- Keep existing services and models as the real data source. The preview is a design reference, not a runtime dependency.
- User-visible navigation is `主页 / 素材库 / 工作台 / 批量产线 / 画廊 / 设置`.
- Do not expose Workspace, Health, source-loader, migration, or diagnostics concepts in normal user flows.
- Treat source import and three-source consolidation as internal data preparation; users should work through workbench import/export.

## Implementation Order

1. Add `lib/ui/studio_core/theme` and `lib/ui/studio_core/widgets`.
2. Replace the app entry theme and shell with a native Studio shell.
3. Move existing real data pages into the Studio shell.
4. Rebuild pages visually against the preview while preserving existing data flow.
5. Verify with widget tests and screenshots after each major page.

Visual QA playbook:

- `docs/screenshots/studio-visual-acceptance.md`

Canonical preview docs:

- `novel-studio-ui-preview/docs/00-production-integration-overview.md`
- `novel-studio-ui-preview/docs/01-flutter-page-map.md`
- `novel-studio-ui-preview/docs/02-design-system-port.md`
- `novel-studio-ui-preview/docs/03-data-contracts.md`
- `novel-studio-ui-preview/docs/04-implementation-slices.md`
