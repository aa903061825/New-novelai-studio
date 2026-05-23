# Config Preview Gallery Design

## Goal

Let the user turn the latest generated images on the home page into a visual preview for the current saved config. The saved config list should stay easy to scan even when there are many presets.

## User Experience

- The home page gets a compact action for saving the latest generated images as the current config preview.
- The action uses the most recent generated images that have image bytes, up to 9 images.
- If no generated images are available, the action is disabled or shows a short error message.
- When a preview set is saved, one image is chosen randomly as the card cover.
- Each saved config card shows only the selected cover image, not a 9-image grid.
- Each card keeps a preview button. Clicking it opens a preview panel/dialog.
- The preview panel shows all saved preview images for that config.
- In the preview panel, clicking an image sets it as the card cover for that config.
- Existing configs without previews continue to show the current fallback card layout.

## Data Model

Extend `SavedConfigInfo` with preview metadata:

- `previewImages`: persisted base64 PNG thumbnail strings for up to 9 images.
- `previewCoverIndex`: the currently selected cover image index.

The preview data belongs in the config index because it is metadata about the saved config card. This keeps previews available after restart and avoids relying on generated output files remaining on disk.

## Image Handling

The source images come from `GenerationPageViewmodel.commandList`, which already contains recent generated `InfoCardContent.imageBytes`.

Before saving, images should be converted into compact thumbnails with a maximum side length of 320px so the config index does not grow with full PNG files. This is large enough for card covers and the preview dialog while staying small enough for many presets.

Saving a new preview set replaces the previous preview set for the current config and randomly chooses a new cover index. Manual cover selection only changes `previewCoverIndex` and persists until the user saves a new preview set.

## Components

- `GenerationPageViewmodel`
  - Exposes whether preview images are available.
  - Saves the latest preview images for `ConfigService.currentUuid`.
- `ConfigService`
  - Persists preview data in `SavedConfigInfo`.
  - Provides a method to update preview images and cover index.
- Generation page UI
  - Adds a save-preview action near the existing home-page actions.
- Config selection page
  - Shows a cover thumbnail on cards when available.
  - Adds a preview button to open the preview dialog.
  - Lets the user choose a different cover from the dialog.

## Error Handling

- If there are no generated images, do not write preview data.
- If preview metadata is missing or malformed, fall back to no-preview display.
- If the selected cover index is out of range, use the first preview image.

## Testing

- Unit test `SavedConfigInfo` JSON round-trip with preview data.
- Unit test config preview update behavior.
- Widget test saved config cards with and without preview images.
- Widget test preview dialog cover selection updates the visible card cover.
