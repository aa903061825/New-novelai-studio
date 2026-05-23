# Neo-Brutalism UI Design

## Goal

Restyle the Flutter application from default Material polish to a neo-brutalist interface: cream canvas, pure black ink structure, high-saturation accents, heavy typography, square corners, thick borders, hard offset shadows, and tactile pressed/lifted controls.

## Current Context

The app is a Flutter 3.41 Material app using `adaptive_theme`, with the global theme defined in `lib/main.dart`. Most screens rely on stock Material widgets (`Card`, `ListTile`, `TextButton`, `FloatingActionButton`, `InputDecoration`, `AppBar`, `NavigationRail`, `BottomNavigationBar`), so a centralized theme can move most of the UI quickly. High-impact custom widgets include generation result cards, prompt dashboard cards, page backgrounds, and floating action buttons.

This workspace is not a git repository, so the design can be written to `docs/superpowers/specs/`, but it cannot be committed from this directory.

## Recommended Approach

Use a centralized theme module plus a few reusable neo-brutalist primitives.

Alternative 1, theme-only, is the smallest change but cannot create real hard offset shadows for cards and floating action buttons. Alternative 2, hand-edit every page, would be visually thorough but brittle. The recommended middle path is to put tokens and Material component defaults in one theme file, then upgrade the highest-frequency UI surfaces with reusable `NeoBrutalSurface`, `NeoBrutalBackground`, and `NeoBrutalFloatingActionButton` widgets.

## Design

Create `lib/ui/core/theme/neo_brutal_theme.dart` with definitive tokens: canvas `#FFFDF5`, ink `#000000`, accent `#FF6B6B`, secondary `#FFD93D`, muted `#C4B5FD`, and white `#FFFFFF`. The theme keeps a light neo-brutalist palette for both light and dark adaptive modes because the requested style is explicitly a single light-mode palette.

Apply global Material defaults: heavy Space Grotesk text, zero-radius shapes, black outlines, cream scaffold background, yellow/red action colors, bordered app bars, bordered inputs, black dividers, and square button/FAB/dialog/list tile styling.

Add reusable surface primitives for the parts Material theme cannot express: zero-blur offset box shadows, mechanical press translation, hover lift, and grid/dot page texture.

Update key UI surfaces first: the root navigation background, app bar logo/title area, generation floating controls, settings floating controls, result cards, prompt dashboard cards, and prompt editor panel. This gives the whole app the new visual language without rewriting business logic.

## Testing

Add a theme unit test that verifies the token palette, thick borders, square corners, zero elevation, and hard-shadow decoration contract. Then run `flutter test` and `flutter analyze`. For visual verification, run the app in a browser/device and inspect the main generation, prompt config, and settings pages.
