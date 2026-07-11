# V4 Vibe Info Extracted Preservation

Status: pending user acceptance
Last verified: 2026-07-04

## Finding

V4 Vibe configs imported from `.naiv4vibe` files contained
`importInfo.information_extracted`, but `VibeConfigV4` discarded it. The
generation payload path then wrote `reference_information_extracted_multiple`
as `1.0` for every V4 Vibe. Artist-chain/workbench merging also preserved
`referenceStrength` but not `infoExtracted`.

## Change

- `VibeConfigV4` now stores `infoExtracted`, reads it from `.naiv4vibe`
  `importInfo`, and persists it as `info_extracted`.
- V4 generation payloads now emit each Vibe config's `infoExtracted`.
- V4 Vibe UI exposes an `Info Extracted` slider.
- Workspace Vibe references and artist-chain workbench merges preserve
  `infoExtracted`.

## Verification

- `flutter test test\data\use_cases\generate_payload_use_case_vibe_toggle_test.dart test\data\models\vibe_cache_serialization_test.dart test\data\studio\studio_workbench_asset_service_test.dart test\data\studio\services\workspace_vibe_import_service_test.dart`
- `flutter analyze lib\data\models\vibe_config_v4.dart lib\data\use_cases\generate_payload_use_case.dart lib\ui\vibe_config_v4\viewmodels\vibe_config_v4_viewmodel.dart lib\ui\vibe_config_v4\widgets\vibe_config_v4_view.dart lib\ui\vibe_config_v4\widgets\vibe_config_v4_list_view.dart lib\data\studio\services\workspace_vibe_import_service.dart lib\data\studio\services\studio_workbench_asset_service.dart test\data\use_cases\generate_payload_use_case_vibe_toggle_test.dart test\data\models\vibe_cache_serialization_test.dart test\data\studio\studio_workbench_asset_service_test.dart test\data\studio\services\workspace_vibe_import_service_test.dart`
