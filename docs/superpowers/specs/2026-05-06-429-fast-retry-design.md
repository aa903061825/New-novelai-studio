# 429 Fast Retry Design

## Goal

Add a dedicated retry behavior for HTTP 429 responses so users can optionally retry after a fixed short delay instead of following the normal batch cooldown.

## Scope

Included:
- Add a settings toggle to enable special retry handling for 429 responses.
- Add a settings input field for the retry delay in seconds.
- Default the retry delay to 10 seconds.
- When enabled and a request returns 429, wait the configured seconds and retry the same cached payload.
- Keep existing behavior for non-429 failures.

Not included:
- Retry limits.
- Per-status custom delays beyond 429.
- Changes to prompt generation or saved image contents.

## Design

### Settings

Extend `Settings` with:
- `retryOn429Enabled` as `bool`, default `false`
- `retryOn429DelaySec` as `int`, default `10`

Expose both in batch settings UI:
- Checkbox toggle
- Integer input field shown when the toggle is enabled
- Short descriptive copy explaining that this only applies to HTTP 429 and retries the current request after the configured delay

### Runtime behavior

When a request finishes:
- If status is 2xx, keep current success behavior
- If status is 429 and the toggle is enabled:
  - mark the payload as pending retry
  - schedule a dedicated cooldown using the configured delay
  - after cooldown, retry the same cached payload
  - do not use normal batch interval + jitter for this path
- For all other failures, keep current behavior

### Implementation approach

Avoid broad refactors:
- Add a lightweight API error type carrying the status code
- Detect 429 in `GenerationPageViewmodel`
- Reuse existing cooldown scheduling machinery with an optional override duration for the 429 path

## Acceptance Criteria

- New settings are persisted in config JSON.
- Batch settings UI shows the 429 toggle and delay input.
- With the toggle disabled, 429 follows existing behavior.
- With the toggle enabled, 429 waits the configured seconds and retries the same cached payload.
- Non-429 failures still follow current behavior.
