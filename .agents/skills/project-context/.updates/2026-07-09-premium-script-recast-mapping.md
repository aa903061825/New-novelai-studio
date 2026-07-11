# Premium Script Recast Mapping Batch

Status: proposal, pending user acceptance.

Purpose: record the offline cache-mapping workflow used for `E:\NAI的脚本群\作品集\带图精品` without calling project APIs or stored credentials.

Entry point: `tool/apply_ntr_story_target_mapping_offline.mjs`.

Key details:
- Scope is controlled by `--source-root`; the 2026-07-09 batch used `E:\NAI的脚本群\作品集\带图精品`.
- Existing active caches are updated in `%APPDATA%\Novel Studio\Novel Studio\novel_studio\script_recast\cache`.
- Pepe replacement tags use `1.5:: cat_ears ::` and `-3:: hood ::, -3:: wearing hood ::, -3:: animal hood ::`.
- Female-role detection prioritizes identity fields before broad evidence text, so terms like `male pants unzipping` do not cause female roles to be skipped.

Verification from 2026-07-09:
- `node --check tool\apply_ntr_story_target_mapping_offline.mjs`
- `build/premium_all_mapping_final_dry_run_20260709_c.json`: `files_matched = 151`, `files_changed = 0`.
- `build/premium_all_mapping_validation_20260709.json`: old Pepe cat-ear and hood weights `0`, missing new Pepe weights `0`, body/action mis-maps `0`, black-clothing wrong conversions `0`, non-black swimwear clothing maps `0`, male-role maps `0`.
