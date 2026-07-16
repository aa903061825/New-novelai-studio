# Batch Production Default Negative Prompt

## Purpose

Prepend the requested batch-production negative prompt to each frame's
existing negative prompt without dropping frame-specific terms or duplicating
the default on retries and reruns.

## Entry Points

- `ScriptRecastPayloadAdapter.toNaiRequestPayload`
- `ProductionQueueViewModel.start`

## Key Files

- `lib/core/constants/defaults.dart`
- `lib/data/studio/services/script_recast_payload_adapter.dart`
- `test/data/studio/services/script_recast_payload_adapter_test.dart`
- `test/ui/studio_batch/production_queue_viewmodel_test.dart`

## Behavior

- New Script Recast production tasks receive the batch default when they are
  normalized for enqueueing.
- Existing queued tasks receive the same compatibility normalization before
  their request is sent.
- `negative_prompt` and `v4_negative_prompt.caption.base_caption` carry the
  same merged base prompt; V4 character-specific negative captions remain
  unchanged.
- Re-normalizing an already merged request keeps one copy of the batch
  default.

## Verification

- `flutter test --no-pub test/data/studio/services/script_recast_payload_adapter_test.dart test/ui/studio_batch/production_queue_viewmodel_test.dart -r expanded`
- `flutter test --no-pub test/data/studio/services/script_recast_production_service_test.dart -r expanded`
- `flutter analyze --no-pub`

Last verified locally: 2026-07-13. Pending user acceptance in the desktop app.
