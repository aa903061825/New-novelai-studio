# Global API And Content Order Badge Design

## Goal

Make the NovelAI API key behave as a machine-local global setting instead of a per-config field, and show the selected order index from the `内容` prompt group on the generation homepage cards without modifying saved images or metadata.

## Scope

Included:
- Keep one active API key in the current app state.
- Ignore imported or loaded per-config `api_key` values.
- Preserve the current local API key when importing config files and loading saved configs.
- Track which string positions were selected from the prompt group whose comment is exactly `内容`.
- Show those selected positions on homepage result cards only.

Not included:
- New auth methods.
- Changes to image files, PNG metadata, or output filenames.
- New settings toggles for the badge.
- General prompt provenance tracking outside the `内容` group.

## Current Problem

Today every saved config carries its own `settings.api_key`, so switching saved configs can also switch the API key. This is inconvenient for single-user usage where the API key should be shared globally.

The homepage also does not expose which item from the `内容` prompt list was used for a generated image, even though that information is useful when reviewing generated batches.

## Design

### 1. Global API behavior

Treat the in-memory `PayloadConfig.settings.apiKey` as the only active API key for the local app session.

Behavior rules:
- Editing the API key in settings updates the current in-memory global value as it does today.
- Saving the current config to local storage should continue to serialize the current payload config shape, but loading a config must not replace the current in-memory API key.
- Importing a config file must ignore the file's `settings.api_key` and keep the current in-memory API key.
- Loading a saved config from the saved-config list must ignore the saved config's `settings.api_key` and keep the current in-memory API key.
- Creating a copy of the current config should use the current in-memory API key value.

Implementation direction:
- Extend config loading paths with a "preserve current API key" behavior instead of refactoring the entire data model.
- Keep file format compatibility with existing exported JSON.

### 2. `内容` order tracking

Track selected indexes during prompt generation, not by reverse-parsing the final prompt string.

Behavior rules:
- Only the prompt config whose `comment` is exactly `内容` participates.
- If selection picks the 1st string, show `1`.
- If selection picks multiple strings, show all selected positions in display order, such as `2,5`.
- If no `内容` strings are selected, show nothing.
- The badge is only shown on homepage result cards and detail view data if convenient, but it does not alter image bytes, metadata, or filenames.

Implementation direction:
- Extend prompt generation to carry selection metadata for `内容`.
- Preserve existing prompt text generation behavior.
- Reuse the metadata when creating `InfoCardContent` for success and failure cards.

## UI

Homepage cards will show a small text marker near the card title when `内容` selection indexes are available.

Display format:
- Prefix-free numeric list such as `1` or `2,5`.
- Hidden entirely when no `内容` selection exists.

No new buttons or dialogs are required.

## Files Expected To Change

- `lib/data/models/payload_config.dart`
  - Add load behavior that preserves the current API key.
- `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`
  - Use preserve-current-API behavior when importing config files.
- `lib/ui/settings_page/view_models/config_selection_page_viewmodel.dart`
  - Use preserve-current-API behavior when loading saved configs and importing external config files into local saves.
- `lib/data/models/prompt_config.dart`
  - Return enough selection metadata to identify which `内容` strings were chosen.
- `lib/data/use_cases/generate_payload_use_case.dart`
  - Include selected `内容` indexes in the payload generation result.
- `lib/data/models/info_card_content.dart`
  - Carry optional homepage-only content-order display text.
- `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
  - Pass the content-order display text into generated cards.
- `lib/ui/generation_page/widgets/info_card.dart`
  - Render the content-order marker on homepage cards.

## Testing

Add or update tests for:
- Loading JSON while preserving the current API key.
- Importing config JSON while preserving the current API key.
- Loading saved config JSON while preserving the current API key.
- Returning `内容` selection indexes for single and multi-select cases.
- Omitting the badge when no `内容` strings are selected.
- Passing the badge text into generated `InfoCardContent`.

## Risks

- Prompt generation currently returns only prompt text/comment trees, so adding selection metadata must avoid changing existing prompt output semantics.
- Some configs may contain nested `内容` groups. The intended behavior is to track any prompt config whose `comment` is exactly `内容`; if multiple such groups contribute selections in one generation, their selected indexes should be combined in encounter order.

## Acceptance Criteria

- Changing configs no longer changes the active API key.
- Importing configs no longer overwrites the active API key.
- Generations that use the `内容` group show the selected position numbers on homepage cards.
- Generations without `内容` selections show no extra marker.
- Existing prompt generation, batch generation, and saved-config flows continue to work.
