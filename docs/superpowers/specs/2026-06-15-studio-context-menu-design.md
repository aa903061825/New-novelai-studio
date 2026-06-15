# Studio Context Menu Design

Date: 2026-06-15

## Goal

Improve the right-click menu experience across Novel Studio so it feels like a
native part of the Studio tool surface rather than a default system popup.

The first implementation target is the prompt-tag right-click menu. The same
component should then be reusable by script review tokens, script shelf cards,
category cards, and version chips.

## Current State

Several high-frequency right-click surfaces currently use Flutter `showMenu`
with plain `PopupMenuItem` entries:

- prompt tag editor actions,
- prompt tag display actions,
- script review token actions,
- script exhibition script/category/version actions.

This works functionally, but the visual result is weak:

- the popup frame does not share the Studio card/tag geometry,
- menu items have little hierarchy,
- destructive actions do not stand apart enough,
- the menu does not visually point back to the right-click target,
- each menu repeats low-level `showMenu` setup instead of sharing one design.

## Design Direction

Use a shared `StudioContextMenu` component with compact command rows. The menu
keeps the lightweight right-click behavior, but gains a Studio-specific frame,
target context, icons, shortcut hints, dividers, hover treatment, and destructive
action styling.

The approved visual direction is option B from the preview, revised with a
zero-radius anchor corner:

- The menu surface uses `StudioTokens.surface3` or a slightly darker derivative.
- The border uses `StudioTokens.borderStrong`.
- The top-left corner is square when the menu opens down and to the right from
  the click position.
- The other three corners stay rounded, around 16-18 px, to remain compatible
  with the existing Studio card language.
- The menu has a dark offset shadow so it separates from dense tag/token grids.
- A small optional target label appears at the top, such as `city lights`.
- Rows use a leading icon, label, and optional trailing shortcut or hint.
- Destructive rows use the danger color and can be separated after a divider.

If the menu must flip because it is near a viewport edge, the square corner
should move to the corner nearest the original click anchor. For example, a menu
opening to the left should square its top-right corner instead of always using
top-left.

## Component Shape

The shared menu should expose a small API rather than leaking Flutter menu
plumbing into each screen.

Expected concepts:

- `StudioContextMenu.show<T>()` accepts the build context, global click
  position, optional target label, and typed menu items.
- `StudioContextMenuItem<T>` describes value, label, icon, optional shortcut,
  enabled state, and tone.
- Item tones should at least support normal and destructive. A highlighted or
  primary tone can be added for the first high-value action.
- A separator entry should be available without forcing each caller to remember
  spacing constants.

The implementation can use `showMenu` with a custom `PopupMenuTheme` and custom
item widgets if that is enough to control the frame. If Flutter's default popup
shape cannot support per-corner anchor geometry cleanly, use an `OverlayEntry`
or `MenuAnchor` implementation behind the same API.

## Rollout

1. Build the shared component in `lib/ui/studio_core/widgets/`.
2. Migrate the prompt-tag editor right-click menu first.
3. Migrate prompt-tag display after the editor behavior is verified.
4. Migrate script review token and script exhibition menus if the shared API
   works cleanly for the first two surfaces.

This keeps the first change narrow while still creating a reusable path for all
right-click menus.

## Testing Strategy

- Widget-test the prompt-tag editor menu still exposes the same actions.
- Widget-test the menu includes the target label when provided.
- Widget-test destructive items have a distinct style or semantic marker.
- Keep existing right-click tests passing for prompt tags and script menus.
- Add a targeted golden or screenshot-style check only if the project already
  has a reliable local pattern for visual assertions; otherwise rely on widget
  structure plus manual visual acceptance.

## Out Of Scope

- Changing the action set for each right-click menu.
- Reworking keyboard shortcuts globally.
- Replacing every popup/dropdown in the app.
- Changing prompt-tag chip styling beyond the hover/selection state needed to
  make the active right-click target clear.

## Self-Review

- The design is scoped to the right-click menu frame and row treatment.
- It avoids API-backed or cache-generation workflows.
- The first implementation slice can ship independently on prompt-tag editor.
- The shared API allows later script and gallery menus without forcing a large
  migration in the first pass.
- The zero-radius corner rule is explicit for both normal and flipped menus.
