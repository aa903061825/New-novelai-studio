# Script AI Evidence Follow-Up Compression Design

## Goal

Improve Script AI role extraction accuracy without sending every frame prompt in full. The current evidence builder compresses each script chunk into per-source tag frequency evidence. That is token efficient, but it loses important co-occurrence and timeline information, so the AI must infer outfit stages from sparse tag statistics.

This design combines a lightweight richer first request with a controlled second pass where the AI can ask for specific frame evidence.

## Decision

Use a two-pass protocol:

1. First pass: send `chunk_extract_v2`, which includes the existing tag statistics plus timeline segments and representative captions.
2. Optional second pass: if the AI returns `needs_more_evidence`, the app reads only the requested frames from the already parsed `Script` object and sends `evidence_followup`.
3. Final output: the AI returns the same role extraction shape already used by Script Recast: roles, stages, five fields, artist-chain evidence, strong filter keywords, attention items, and unassigned terms.

The AI never receives filesystem paths and never gets permission to read arbitrary local files. Follow-up evidence is served only from the current imported script's parsed frames.

## First Pass Request

`ScriptAiRoleEvidenceBuilder` should keep the existing source-level tag statistics and add a compact timeline summary for each source.

Shape:

```json
{
  "schema_version": 2,
  "request_kind": "chunk_extract_v2",
  "chunk_id": "chunk-1",
  "script": {
    "id": "script-id",
    "name": "script name",
    "detected_schema": "v4Slotted",
    "frame_count": 91
  },
  "chunk": {
    "start_frame_index": 1,
    "end_frame_index": 80,
    "frame_count": 80
  },
  "sources": [
    {
      "source_id": "slot-0",
      "source_kind": "slot",
      "timeline_segments": [
        {
          "frame_range": [1, 8],
          "representative_caption": "school uniform, black pantyhose, shoes",
          "stable_tags": ["school uniform", "black pantyhose"],
          "variant_tags": ["shoes"],
          "frame_indexes": [1, 2, 3, 4, 5, 6, 7, 8]
        }
      ],
      "tag_evidence": [
        {
          "tag": "school uniform",
          "count": 8,
          "frame_indexes": [1, 2, 3, 4, 5, 6, 7, 8],
          "samples": ["school uniform, black pantyhose, shoes"]
        }
      ]
    }
  ]
}
```

Timeline segments should be built deterministically from normalized caption changes. Adjacent frames with the same normalized caption collapse into one segment. If a source has too many unique captions, the builder keeps the earliest segments, major recurring segments, and segments near high-change boundaries.

Per source limits:

- Maximum timeline segments: 12.
- Maximum representative captions per segment: 1.
- Maximum frame indexes per segment: 24.
- Existing tag limits stay in place unless tests show they are too tight.

## Segment Tag Split

For each timeline segment:

- `stable_tags`: tags that appear in every sampled caption for the segment.
- `variant_tags`: tags that appear in only some sampled captions, or differ from neighboring segments.
- `representative_caption`: one complete original caption from the segment.

The builder must not pre-filter action, camera, pose, expression, wetness, damage, residue, or other uncertain terms. Those terms are useful because the AI must decide that they are not outfit stages.

## Follow-Up Request

If the first pass is insufficient, the AI may return:

```json
{
  "schema_version": 2,
  "status": "needs_more_evidence",
  "chunk_id": "chunk-1",
  "evidence_requests": [
    {
      "id": "slot-0-stage-ambiguity",
      "source_id": "slot-0",
      "frame_indexes": [8, 9, 10, 16, 17],
      "wanted_fields": [
        "base_caption",
        "char_caption",
        "negative_caption"
      ],
      "reason": "Need to decide whether no shoes and black coat are outfit stages or state variants."
    }
  ],
  "attention_items": []
}
```

The app responds with:

```json
{
  "schema_version": 2,
  "request_kind": "evidence_followup",
  "chunk_id": "chunk-1",
  "evidence": [
    {
      "frame_index": 16,
      "source_id": "slot-0",
      "base_caption": "full base caption",
      "char_caption": "full slot-0 caption",
      "negative_base": "full negative base caption",
      "negative_char_caption": "full negative slot-0 caption"
    }
  ]
}
```

The service should then parse the follow-up response as a normal `ScriptAiRoleExtraction`.

## Guardrails

Follow-up evidence is intentionally limited.

- Maximum evidence request groups per chunk: 3.
- Maximum frames per request group: 12.
- Maximum total follow-up frames per chunk: 24.
- Only parsed frames from the current imported script are eligible.
- Unknown `source_id` values are ignored and recorded as non-blocking attention items.
- Requested frame indexes outside the current chunk are ignored unless the service is running a script-level merge follow-up.
- The service performs at most one follow-up round per chunk. If the AI is still unsure, it must return low confidence and attention items.

The AI must not ask for file paths, directories, images, arbitrary JSON files, or external assets. If it does, the request is rejected and converted into an attention item.

## Service Flow

`DefaultScriptAiRoleExtractionService.extractRoles` should become:

```text
build chunk_extract_v2 requests
for each chunk:
  send first pass
  parse response
  if ready:
    keep extraction
  if needs_more_evidence:
    validate evidence requests
    collect follow-up frame evidence from parsed Script
    send evidence_followup
    parse final extraction
  if failed:
    keep failure
if multiple chunk extractions:
  send merge_extractions
  fallback to deterministic merger if merge fails
normalize outfit state variants
return result and trace data
```

The UI progress trace should show both the first request and any follow-up requests, including source IDs and frame ranges, but not dump huge prompt text into the compact status banner. Full details can remain in the existing AI processing dialog.

## Model Changes

Extend `script_ai_role_extraction.dart` with:

- `ScriptAiRoleExtractionStatus.needsMoreEvidence`, serialized as `needs_more_evidence`.
- `ScriptAiEvidenceRequest`.
- Optional `evidenceRequests` on `ScriptAiRoleExtraction`.

Existing ready and failed extraction JSON remains backward compatible.

## Prompt Changes

The role extraction system prompt should add:

- The first-pass request may contain `timeline_segments`.
- If evidence is insufficient, return `status: "needs_more_evidence"` with bounded `evidence_requests`.
- Request only frame/source evidence, never file paths or external assets.
- Prefer returning low confidence over over-requesting or inventing tags.
- After an `evidence_followup`, return a final ready or failed extraction, not another follow-up request.

The prompt should preserve the current rules:

- Do not invent tags.
- Missing upper/lower clothing fields are valid.
- Do not split stages for state variants.
- Extract official art/style as artist-chain evidence.
- Extract mosaic/censor terms as strong filter keywords.

## Why This Improves Accuracy

The first pass gives the AI co-occurrence and continuity signals that raw tag statistics lose. Timeline segments help distinguish a stable outfit from a transient state. Representative captions preserve enough original context for common cases.

The follow-up pass handles hard cases without sending the whole script. If `black coat`, `no shoes`, and `school uniform` are ambiguous, the AI can request the exact nearby frames where the change occurs and make a better stage decision.

## Non-Goals

- Do not add image understanding in this change.
- Do not expose arbitrary local file access to AI.
- Do not send the asset catalog, character cards, outfit cards, or vibes in this workflow.
- Do not replace deterministic payload assembly.
- Do not perform unlimited multi-turn AI tool loops.

## Testing

Add focused tests for:

- `ScriptAiRoleEvidenceBuilder` emits `chunk_extract_v2` with `timeline_segments`.
- Repeated identical captions collapse into one segment.
- Meaningful caption changes create separate segments.
- Segment limits are enforced deterministically.
- Parser supports `needs_more_evidence`.
- Service sends follow-up evidence when the first response requests it.
- Invalid frame/source requests are ignored with attention items.
- The service performs only one follow-up round per chunk.
- Existing ready extraction tests continue to pass.
- ViewModel trace shows follow-up request count and request summaries.

## Rollout

Keep the current v1 path readable for cached responses and tests. New live AI requests should use `schema_version: 2` and `chunk_extract_v2`.

If v2 causes provider compatibility issues, a temporary setting or constructor flag can force the builder to emit the existing v1 shape for tests and fallback diagnostics. The default should be v2 once tests pass.

## Self-Review

- No placeholders or TODO markers remain.
- The AI has no arbitrary local file access.
- The design preserves current five-field extraction and omitted clothing semantics.
- The follow-up loop is bounded to avoid runaway token use.
- This scope is limited to request compression, parsing, service orchestration, trace UI, and tests.
