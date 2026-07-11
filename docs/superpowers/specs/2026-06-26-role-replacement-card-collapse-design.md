# Role Replacement Card Collapse Design

## Goal

Make Script Workbench role replacement cards collapsible so a dense replacement area can be scanned without losing mapping data.

## Scope

- Applies only to role replacement cards in the Script page replacement mapping section.
- Each card starts expanded, matching current behavior.
- A per-card icon button toggles between expanded and collapsed.
- Collapsed cards show the role icon, source role label, source preview, rule count, mapped rule count, and an expand button.
- Collapsed cards hide the target identity editor, rule action row, and rule grid.
- Collapse state is local UI state for the current page instance. It is not written to `RecastMapping`, script cache JSON, or workspace data.

## User Experience

Expanded cards keep the existing layout and controls. The header adds a collapse control in the upper-right corner.

Collapsed cards keep a compact summary row:

- source role label
- source preview
- total replacement rules
- mapped replacement rules

The user can expand the card again without losing rule selection or edited prompts.

## Architecture

The UI state belongs inside `_RoleReplacementCard`, because collapsing is presentation-only and per-card. `_RoleReplacementSection` continues to build cards from `StudioScriptViewModel.roleReplacementMappings` and does not gain persistence responsibilities.

## Testing

Add a widget test in `test/ui/studio_script/studio_script_page_test.dart` that imports a cached role replacement, verifies the expanded rule controls are visible, taps the collapse button, verifies the compact summary remains while the rule controls disappear, then taps expand and verifies the rule controls return.
