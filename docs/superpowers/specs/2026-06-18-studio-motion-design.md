# Studio Motion Design

Date: 2026-06-18

## Goal

Add a reusable Studio motion layer to Novel Studio so the app feels more alive
without making dense creative workflows distracting.

The final direction is expressive in showcase surfaces, but bounded:

- Home, Gallery, Asset Library previews, image viewers, and Studio overlays may
  use visible reveal, slide-fade, light scale, lift, and highlight motion.
- Script Workbench also gets motion, but only as event-triggered operation
  feedback.
- Dense card grids may use a bounded row/column reveal wave for newly mounted
  visible batches, but not for every rebuild or every offscreen item.
- Workbench multi-component screens use layered choreography: drawer first,
  editor next, controls/results last; inner lists and chip flows get local
  stagger only when their content changes.
- Batch production, prompt editing, and other dense long-session tools stay
  stable and only use light feedback.

## Current Context

The app is a Flutter desktop Studio shell using `StudioTheme`,
`StudioTokens`, and reusable widgets under `lib/ui/studio_core`. Existing
motion is local and inconsistent: `AnimatedContainer`, `AnimatedOpacity`,
hover colors, and a few preview-specific behaviors. There is no animation
package dependency, and one is not needed for the first pass.

The old `PlayfulGeometricSurface` has hover/press animation patterns, but the
current UI direction says new work should use the Studio shell and Studio
tokens rather than the old product exterior.

## Recommended Approach

Create a small `lib/ui/studio_core/motion/` layer and use native Flutter
animation primitives. This avoids a new dependency and gives a single place to
control durations, curves, reduced-motion behavior, and page-specific intensity.

Alternatives considered:

- Page-local hand-written animations: faster initially, but would spread
  inconsistent motion rules across large widgets.
- Add an animation package such as `flutter_animate`: convenient but unnecessary
  for the needed fade, scale, slide, hover, and one-shot effects.

## Motion Principles

1. Motion must not change final layout geometry.
   Use opacity, transform, border, shadow, and color rather than dynamic sizes.

2. Dense editing surfaces must remain readable.
   Avoid default looping motion in Script Workbench, Prompt editors, and Batch
   production.

3. Showcase areas can be expressive.
   Home, Gallery, Asset Library details, image previews, and overlays can use
   stronger entrance and preview motion.

4. Script Workbench uses V2.3 event-triggered motion.
   Default state is still. Motion appears only after hover, click, selection,
   drag/drop affordance, or field focus changes.

5. Respect platform reduced-motion settings.
   When `MediaQuery.disableAnimations` is true, motion widgets should render
   their final state without animated transforms.

6. Stagger dense surfaces by visible batch, not by total collection size.
   The animation budget should cover the first visible items or the next
   paged-in window. It must not create a long cascade across hundreds of assets.

7. Large tool pages need choreography, not uniform motion.
   Shell panels, drawers, editors, controls, rows, and prompt chips have
   different visual weight. Animate them with small offsets in their natural
   directions instead of applying the same upward fade to every child.

## Motion Components

Add:

- `studio_motion_tokens.dart`
  Durations and curves:
  - fast feedback: around 120-160 ms
  - medium reveal: around 220-280 ms
  - expressive reveal: around 360-520 ms
  - utility curve for dense surfaces
  - expressive curve for showcase surfaces

- `studio_motion_scope.dart`
  Helpers for checking reduced-motion state and resolving zero-duration/static
  behavior.

- `studio_page_transition.dart`
  Shell-level section transition. Showcase sections can use slide-fade; dense
  sections use fade only or static transitions.

- `studio_reveal.dart`
  One-shot reveal wrapper for home panels, gallery/detail panels, and overlay
  contents. Supports optional small delay and intensity.

- `studio_interactive_surface.dart`
  Hover/press wrapper for showcase cards and previews. Keeps existing tap
  handlers outside or inside without replacing behavior ownership.

- `studio_staggered_reveal.dart`
  One-shot reveal wrapper for repeated visible children. It supports row/column
  or index-based delay, small scale overshoot, optional lightweight highlight,
  and a maximum stagger window so dense lists stay responsive.

- `studio_motion_sequence.dart`
  A small helper for multi-region surfaces. It gives page regions stable
  entrance slots such as drawer, editor, controls, and result, while still
  rendering the final state immediately when motion is disabled.

## Page Integration

### Studio Shell

Wrap `_buildCurrentPage()` output in `StudioPageTransition`.

Use stronger transition for:

- Home
- Assets
- Gallery
- Settings knowledge/tools page

Use lighter transition for:

- Workbench
- Script
- Batch
- Script Exhibition if it is showing dense lists

### Home

Use `StudioReveal` for:

- hero panel
- metric strip
- recent gallery panel
- action panel

Home can have the most visible opening motion because it is the app entry
surface.

### Asset Library

Use showcase motion for:

- asset detail panel/dialog content
- main preview stage
- outfit/icon tiles on hover or selection
- image hover preview shell
- visible asset-card batches when filters, source tabs, or rendered windows
  change

Use the approved row/column wave for dense card grids: cards start with a small
offset and scale, ease into place with a short overshoot, and may show a subtle
highlight pass. Cap the stagger so the visible batch settles quickly. Do not
animate every asset-grid item on load, and do not replay card entrance motion on
selection, favorite toggles, hover, or unrelated state changes.

### Script Exhibition Room

Use the same row/column wave for the script bookshelf. The wave should follow
the grid geometry instead of raw list order so multiple visible rows feel like a
coherent shelf being laid out.

Constraints:

- reveal only newly mounted visible script cards or newly expanded render
  windows
- preserve marquee-selection rect reporting and drag/drop hit targets
- keep selection borders, context menus, and cover action buttons stable
- reduced-motion mode renders all cards in final state

### Gallery And Image Viewer

Use expressive motion for:

- fullscreen toolbar/footer fade and scale
- image switch fade
- generated image card hover/lift
- result detail overlay entrance

### Script Workbench V2.3

Script Workbench is not fully static, but it must not idle-animate.

Allowed:

- panel reveal when navigating into Script Workbench or changing a major mode
- multi-region workbench entrance using layered choreography: asset drawer from
  the left, prompt/editor sections from below, generation controls from the
  right, and result/output surfaces after controls
- asset drawer category/detail changes where the panel switches first and the
  visible rows follow with a short row wave
- prompt chip flows entering after a category switch, block expansion, or
  explicit insertion
- card hover lift
- active mapping card emphasis after user focus/selection
- prompt chip one-shot pop on selection
- drag/drop target highlight only while a drag/drop or equivalent action is
  active
- field focus one-shot scan/highlight
- asset drawer card hover lift and preview brightening

Not allowed:

- idle breathing on active cards
- looping glow on selected chips
- constantly floating asset cards
- scan-line loops when the user is not interacting
- motion triggered by every text edit or every frame rebuild
- uniform waves across the whole workbench where drawer rows, prompt chips,
  sliders, and result panels all compete for attention

### Workbench Asset Drawer

The approved direction is the B option from the visual companion:

- the drawer shell enters as a region, not as many independent children
- category cards and detail rows use a bounded local row wave
- expanded outfits reveal below their parent with a smaller stagger
- prompt part cards use hover/drag affordance, not idle motion
- category/detail switches keep the existing `AnimatedSwitcher`, but replace the
  plain slide-fade feel with drawer-specific left-to-right region motion plus
  local row reveals

### Prompt Editing And Chip Flows

Prompt editors remain dense tools, so they should not animate every rebuild.
Allowed chip motion is event-driven:

- first render after switching into a panel
- inserting a chip from the drawer
- expanding a prompt block
- toggling translated/raw grouping where the chip list is materially replaced

The motion is a short pop/cascade, not a long wave. Text cursor movement,
classification refreshes, and hover-only changes must not replay chip entrance
motion.

### Generation Controls

The generation control column should enter as a stable right-side region. The
start button may get a short emphasis when the page appears or a generation
becomes ready, but sliders, steppers, model menus, and size chips should not
move during routine value changes.

### Batch And Prompt Editing

Keep these surfaces restrained:

- hover and pressed states
- selected state color/border transitions
- short status changes where they clarify state

Avoid animated layout changes in task lists, prompt fields, and production logs.

## Testing

Add focused widget tests for:

- motion components render final state when animations are disabled
- `StudioPageTransition` keeps keyed page content findable
- Home reveal wrappers do not remove visible text or alter layout constraints
- Script Workbench V2.3 interaction feedback is event-triggered, not always
  running by default
- dense card row/column reveals cap their stagger window and render final state
  when animations are disabled
- workbench layered choreography keeps drawer, editor, controls, and result
  content findable without changing layout constraints
- prompt chip reveal does not replay on ordinary text edits or classification
  refreshes
- Asset detail hover/preview interactions still expose existing click targets

Run page-specific tests around changed surfaces:

- `test/ui/navigation/novel_studio_navigation_test.dart`
- `test/ui/studio_shell/asset_library_page_test.dart`
- `test/ui/studio_shell/script_exhibition_room_page_test.dart`
- `test/ui/studio_workbench/workbench_asset_drawer_test.dart`
- `test/ui/studio_workbench/workbench_single_image_console_test.dart` or the
  closest existing workbench console coverage
- `test/ui/studio_shell/studio_gallery_page_test.dart` or the closest existing
  generated-image viewer tests
- `test/ui/studio_script/studio_script_page_test.dart` targeted interaction
  tests

Also run:

```powershell
flutter test --no-pub test/ui/studio_core/studio_theme_test.dart -r expanded
flutter test --no-pub test/ui/studio_core/studio_visual_acceptance_contract_test.dart -r expanded
flutter analyze --no-pub
```

## Non-Goals

- No new animation package in the first pass.
- No global route transition override for every `showDialog`.
- No golden/pixel-perfect screenshot harness.
- No large-scale rewrite of page structure.
- No idle looping motion in dense editing pages.
- No unbounded entrance cascade across all assets, all scripts, or all prompt
  chips.

## Approval Notes

User selected the expressive showcase direction, then scoped it to showcase
areas while keeping dense workflows stable. After reviewing samples, the final
Script Workbench direction is V2.3: default stillness with event-triggered
interaction motion.

2026-06-20 update: User selected the second visual option for dense card grids:
row/column wave with light overshoot and subtle highlight. For workbench and
asset-drawer multi-component screens, user selected option B: layered
choreography. The drawer, prompt/editor area, and generation controls enter as
separate regions; local lists and chip flows use the approved wave only for
newly mounted or materially replaced visible content.
