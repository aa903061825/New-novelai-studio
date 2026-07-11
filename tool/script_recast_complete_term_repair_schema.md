# Script Recast Complete Term Repair Schema

`script_recast_complete_term_audit.mjs` is local-only. It never calls project
API settings, OpenAI-compatible endpoints, NAI tokens, proxies, or stored
credentials.

The tool audits complete deduplicated prompt terms from `scriptSnapshot.frames`
and compares them with:

- `aiRoleExtraction.roles[].prompt_terms`
- `aiRoleExtraction.scene_terms`
- `mapping.rolePromptReplacements`
- `mapping.scenePromptReplacements`

It does not decide whether a source tag is a role term, clothing term, scene
term, or action term. Classification must come from the project AI pipeline or
from a Codex-produced offline schema.

## Schema

```json
{
  "version": 1,
  "caches": [
    {
      "scriptId": "script-id",
      "rolePromptTerms": [
        {
          "sourceRoleId": "slot-0",
          "displayLabel": "Role name",
          "terms": [
            {
              "id": "term-double-bun",
              "text": "double bun",
              "category": "upperBody",
              "source_phrase": "double bun",
              "source_location": "slot-0 prompt",
              "frame_indexes": [1, 2]
            }
          ]
        }
      ],
      "sceneTerms": [
        {
          "id": "scene-bedroom",
          "text": "bedroom",
          "category": "scene",
          "source_phrase": "bedroom",
          "source_location": "base prompt",
          "frame_indexes": [1, 2]
        }
      ],
      "termCacheSuggestions": [
        {
          "text": "double bun",
          "translation": "双丸子头",
          "category": "upperBody",
          "source": "codex_offline"
        }
      ]
    }
  ]
}
```

## Merge Rules

- Existing user-confirmed replacement mappings are preserved.
- If a schema term matches an existing replacement rule by normalized text and
  category, the rule keeps its target/manual fields and only refreshes source
  term metadata.
- Missing role and scene replacement rules are appended with empty targets.
- Existing AI extraction terms are kept unless the schema supplies the same
  normalized text/category, in which case metadata is merged.
- `--apply` requires `--schema`; dry-run audit does not write cache files.
- `--apply` writes a backup before modifying any cache file.
