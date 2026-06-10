# Script AI Evidence Follow-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Script AI role extraction from tag-stat chunks to a bounded two-pass v2 protocol with timeline summaries and optional exact-frame evidence follow-up.

**Architecture:** Keep the current role extraction model, evidence builder, parser, client, service, ViewModel, and Script page integration. Add schema v2 timeline evidence to the first request, let the model return `needs_more_evidence`, and have the service serve one bounded `evidence_followup` request from the current parsed `Script` object only. Existing deterministic merging, omitted clothing semantics, and high-confidence apply behavior remain the final authority.

**Tech Stack:** Flutter/Dart, existing Script Recast models, existing OpenAI-compatible Script AI client, existing `PromptTagProcessor`, `flutter_test`, `dart analyze`, Beads. Git operations are intentionally omitted because Beads context says this repository is in stealth mode.

---

## Source Spec

Implement the design in:

- `docs/superpowers/specs/2026-06-02-script-ai-evidence-followup-design.md`

The implementation must keep these boundaries:

- The AI can request more evidence only by `source_id` and frame indexes.
- The app serves evidence only from the current parsed `Script` object.
- No file paths, image paths, directories, arbitrary JSON files, external assets, character cards, outfit cards, vibes, or asset catalogs are exposed to the AI.
- The service performs at most one follow-up round per chunk.
- New live chunk requests use `schema_version: 2` and `request_kind: "chunk_extract_v2"`.
- Existing cached ready and failed extraction JSON remains readable.

## File Structure

- Modify `lib/data/studio/models/script_ai_role_extraction.dart`
  - Add `needsMoreEvidence` status.
  - Add `ScriptAiEvidenceRequest`.
  - Add optional `evidenceRequests` on `ScriptAiRoleExtraction`.
  - Keep v1 ready/failed cache parsing intact.

- Modify `lib/data/studio/services/script_ai_role_evidence_builder.dart`
  - Emit `schema_version: 2`.
  - Emit `request_kind: "chunk_extract_v2"`.
  - Preserve current `tag_evidence`.
  - Add deterministic `timeline_segments` per source.

- Modify `lib/data/studio/services/script_ai_role_extraction_client.dart`
  - Update the system prompt for `chunk_extract_v2`, `timeline_segments`, `needs_more_evidence`, and `evidence_followup`.
  - Preserve JSON-object response formatting and streaming behavior.

- Modify `lib/data/studio/services/script_ai_role_extraction_parser.dart`
  - No major structural change expected after model status support.
  - Keep tolerant object recovery tests passing.

- Modify `lib/data/studio/services/script_ai_role_extraction_service.dart`
  - Detect `needsMoreEvidence`.
  - Validate and cap evidence requests.
  - Build and send one `evidence_followup` request per chunk when valid evidence exists.
  - Convert invalid follow-up loops into failed extraction objects with attention items.

- Modify `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Ensure request preview, request count, and trace data handle first-pass plus follow-up requests.
  - Preserve current high-confidence apply behavior.

- Modify `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Ensure compact progress/details labels can display `chunk_extract_v2` and `evidence_followup`.

- Test `test/data/studio/models/script_ai_role_extraction_test.dart`
- Test `test/data/studio/services/script_ai_role_evidence_builder_test.dart`
- Test `test/data/studio/services/script_ai_role_extraction_client_test.dart`
- Test `test/data/studio/services/script_ai_role_extraction_parser_test.dart`
- Test `test/data/studio/services/script_ai_role_extraction_service_test.dart`
- Test `test/ui/studio_script/studio_script_page_test.dart`

## Protocol Constants

Use these exact protocol strings:

```dart
const scriptAiSchemaVersionV2 = 2;
const scriptAiRequestKindChunkExtractV2 = 'chunk_extract_v2';
const scriptAiRequestKindEvidenceFollowup = 'evidence_followup';
const scriptAiStatusNeedsMoreEvidence = 'needs_more_evidence';
```

The constants can be private to the files that need them unless a shared constant already exists in the local style.

## Task 1: Model Follow-Up Status And Request Shape

**Files:**
- Modify: `lib/data/studio/models/script_ai_role_extraction.dart`
- Test: `test/data/studio/models/script_ai_role_extraction_test.dart`

- [ ] **Step 1: Add failing model tests**

Add tests beside the existing ready/failed parse tests:

```dart
test('parses needs_more_evidence response with evidence requests', () {
  final extraction = ScriptAiRoleExtraction.fromJson({
    'schema_version': 2,
    'status': 'needs_more_evidence',
    'chunk_id': 'chunk-1',
    'evidence_requests': [
      {
        'id': 'slot-0-stage-ambiguity',
        'source_id': 'slot-0',
        'frame_indexes': [8, '9', 10],
        'wanted_fields': [
          'base_caption',
          'char_caption',
          'negative_caption',
        ],
        'reason': 'Need exact nearby captions.',
      },
    ],
  });

  expect(extraction.schemaVersion, 2);
  expect(
    extraction.status,
    ScriptAiRoleExtractionStatus.needsMoreEvidence,
  );
  expect(extraction.isNeedsMoreEvidence, isTrue);
  expect(extraction.evidenceRequests, hasLength(1));
  expect(extraction.evidenceRequests.single.id, 'slot-0-stage-ambiguity');
  expect(extraction.evidenceRequests.single.sourceId, 'slot-0');
  expect(extraction.evidenceRequests.single.frameIndexes, [8, 9, 10]);
  expect(
    extraction.evidenceRequests.single.wantedFields,
    contains('char_caption'),
  );
});

test('serializes evidence requests with snake case status', () {
  const extraction = ScriptAiRoleExtraction(
    schemaVersion: 2,
    status: ScriptAiRoleExtractionStatus.needsMoreEvidence,
    chunkId: 'chunk-1',
    evidenceRequests: [
      ScriptAiEvidenceRequest(
        id: 'slot-0-stage-ambiguity',
        sourceId: 'slot-0',
        frameIndexes: [8, 9],
        wantedFields: ['base_caption', 'char_caption'],
        reason: 'Need exact nearby captions.',
      ),
    ],
  );

  final json = extraction.toJson();

  expect(json['schema_version'], 2);
  expect(json['status'], 'needs_more_evidence');
  expect(json['evidence_requests'], isA<List>());
  expect(
    (json['evidence_requests'] as List).single,
    containsPair('source_id', 'slot-0'),
  );
});

test('old ready cache json remains readable', () {
  final extraction = ScriptAiRoleExtraction.fromJson({
    'schema_version': 1,
    'status': 'ready',
    'confidence': 0.8,
    'roles': [],
  });

  expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
  expect(extraction.evidenceRequests, isEmpty);
});
```

- [ ] **Step 2: Run model tests and verify the new tests fail**

Run:

```powershell
flutter test test/data/studio/models/script_ai_role_extraction_test.dart --plain-name "parses needs_more_evidence response with evidence requests"
flutter test test/data/studio/models/script_ai_role_extraction_test.dart --plain-name "serializes evidence requests with snake case status"
```

Expected: FAIL because `needsMoreEvidence`, `ScriptAiEvidenceRequest`, `evidenceRequests`, and `isNeedsMoreEvidence` do not exist yet.

- [ ] **Step 3: Implement status and request model**

In `lib/data/studio/models/script_ai_role_extraction.dart`, change the enum and add the evidence request class:

```dart
enum ScriptAiRoleExtractionStatus {
  idle,
  ready,
  failed,
  needsMoreEvidence,
}

class ScriptAiEvidenceRequest {
  final String id;
  final String sourceId;
  final List<int> frameIndexes;
  final List<String> wantedFields;
  final String reason;

  const ScriptAiEvidenceRequest({
    this.id = '',
    this.sourceId = '',
    this.frameIndexes = const [],
    this.wantedFields = const [],
    this.reason = '',
  });

  factory ScriptAiEvidenceRequest.fromJson(Map<String, dynamic> json) {
    return ScriptAiEvidenceRequest(
      id: _stringValue(json['id']),
      sourceId: _stringValue(json['source_id']),
      frameIndexes: _intList(json['frame_indexes']),
      wantedFields: _stringList(json['wanted_fields']),
      reason: _stringValue(json['reason']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_id': sourceId,
        'frame_indexes': frameIndexes,
        'wanted_fields': wantedFields,
        'reason': reason,
      };
}
```

Add a field to `ScriptAiRoleExtraction`:

```dart
final List<ScriptAiEvidenceRequest> evidenceRequests;
```

Add it to the constructor:

```dart
this.evidenceRequests = const [],
```

Parse it in `fromJson`:

```dart
evidenceRequests: _mapList(json['evidence_requests'])
    .map(ScriptAiEvidenceRequest.fromJson)
    .toList(growable: false),
```

Add a convenience getter:

```dart
bool get isNeedsMoreEvidence =>
    status == ScriptAiRoleExtractionStatus.needsMoreEvidence;
```

Add it to `toJson` only when non-empty:

```dart
if (evidenceRequests.isNotEmpty)
  'evidence_requests':
      evidenceRequests.map((request) => request.toJson()).toList(),
```

Update status serialization:

```dart
String _statusJsonValue(ScriptAiRoleExtractionStatus status) {
  return switch (status) {
    ScriptAiRoleExtractionStatus.needsMoreEvidence => 'needs_more_evidence',
    _ => status.name,
  };
}
```

Use it in `toJson`:

```dart
'status': _statusJsonValue(status),
```

Update `_statusValue`:

```dart
ScriptAiRoleExtractionStatus _statusValue(Object? value) {
  if (value is! String) return ScriptAiRoleExtractionStatus.idle;
  final normalized = value.trim();
  if (normalized == 'needs_more_evidence' ||
      normalized == 'needsMoreEvidence') {
    return ScriptAiRoleExtractionStatus.needsMoreEvidence;
  }
  for (final status in ScriptAiRoleExtractionStatus.values) {
    if (status.name == normalized) return status;
  }
  return ScriptAiRoleExtractionStatus.idle;
}
```

Update `_normalizeOutfitStageVariants` in `script_ai_role_extraction_service.dart` later in Task 4 so it preserves `evidenceRequests`.

- [ ] **Step 4: Run model tests**

Run:

```powershell
flutter test test/data/studio/models/script_ai_role_extraction_test.dart
```

Expected: PASS.

## Task 2: Evidence Builder Timeline Segments

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_evidence_builder.dart`
- Test: `test/data/studio/services/script_ai_role_evidence_builder_test.dart`

- [ ] **Step 1: Add failing v2 evidence tests**

Update existing expectations from v1 to v2 and add timeline coverage:

```dart
test('builds v2 chunks with timeline segments and tag evidence', () {
  final script = _script([
    _frame(
      1,
      baseCaption: 'school uniform, classroom',
      charCaptions: ['black coat, black pantyhose, shoes'],
    ),
    _frame(
      2,
      baseCaption: 'school uniform, classroom',
      charCaptions: ['black coat, black pantyhose, shoes'],
    ),
  ]);

  final chunks = const ScriptAiRoleEvidenceBuilder().buildChunks(
    script: script,
  );
  final chunk = chunks.single;
  final slot = (chunk['sources'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((source) => source['source_id'] == 'slot-0');

  expect(chunk['schema_version'], 2);
  expect(chunk['request_kind'], 'chunk_extract_v2');
  expect(slot['tag_evidence'], isA<List>());
  expect(slot['timeline_segments'], isA<List>());
  expect(slot['timeline_segments'], hasLength(1));
  expect(
    (slot['timeline_segments'] as List).single,
    containsPair(
      'representative_caption',
      'black coat, black pantyhose, shoes',
    ),
  );
  expect(
    (slot['timeline_segments'] as List).single,
    containsPair('frame_indexes', [1, 2]),
  );
});

test('caption changes create separate timeline segments', () {
  final script = _script([
    _frame(1, charCaptions: ['school uniform, black pantyhose, shoes']),
    _frame(2, charCaptions: ['school uniform, black pantyhose, shoes']),
    _frame(3, charCaptions: ['school uniform, black pantyhose, no shoes']),
  ]);

  final chunk = const ScriptAiRoleEvidenceBuilder().buildChunks(
    script: script,
  ).single;
  final slot = (chunk['sources'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((source) => source['source_id'] == 'slot-0');
  final segments =
      (slot['timeline_segments'] as List).cast<Map<String, dynamic>>();

  expect(segments, hasLength(2));
  expect(segments[0]['frame_range'], [1, 2]);
  expect(segments[1]['frame_range'], [3, 3]);
  expect(segments[1]['variant_tags'], contains('no shoes'));
});

test('timeline segment count is capped deterministically', () {
  final frames = [
    for (var index = 1; index <= 20; index += 1)
      _frame(index, charCaptions: ['outfit tag $index']),
  ];

  final chunk = const ScriptAiRoleEvidenceBuilder(
    maxTimelineSegmentsPerSource: 12,
  ).buildChunks(script: _script(frames)).single;
  final slot = (chunk['sources'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((source) => source['source_id'] == 'slot-0');
  final segments =
      (slot['timeline_segments'] as List).cast<Map<String, dynamic>>();

  expect(segments, hasLength(12));
  expect(segments.first['frame_range'], [1, 1]);
  expect(segments.last['frame_range'], [20, 20]);
});
```

- [ ] **Step 2: Run builder tests and verify failure**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart
```

Expected: FAIL because the builder still emits schema v1, `chunk_extract`, and no `timeline_segments`.

- [ ] **Step 3: Implement v2 request metadata**

In `ScriptAiRoleEvidenceBuilder`, add a timeline cap:

```dart
final int maxTimelineSegmentsPerSource;
```

Add constructor wiring:

```dart
this.maxTimelineSegmentsPerSource = 12,
```

Pass it into `_SourceAccumulator`.

Change `_chunkMap` request metadata:

```dart
'schema_version': 2,
'request_kind': 'chunk_extract_v2',
```

- [ ] **Step 4: Store caption events once per source**

Change `_addCaption` so the source is created before the tag loop, then record the full caption once:

```dart
final source = sources.putIfAbsent(
  sourceId,
  () => _SourceAccumulator(
    sourceId: sourceId,
    sourceKind: sourceKind,
    maxFrameIndexesPerTag: maxFrameIndexesPerTag,
    maxSamplesPerTag: maxSamplesPerTag,
    maxTimelineSegments: maxTimelineSegmentsPerSource,
  ),
);
source.addCaption(frameIndex: frameIndex, caption: rawCaption);

for (final rawTag in PromptTagProcessor.splitWorkshopTags(rawCaption)) {
  final display = PromptTagProcessor.cleanTagDisplay(rawTag);
  final key = PromptTagProcessor.normalizeMatchKey(display);
  if (display.isEmpty || key.isEmpty) {
    continue;
  }
  source.addTag(
    tagKey: key,
    tagDisplay: display,
    frameIndex: frameIndex,
    sample: rawCaption,
  );
}
```

Rename the old `_SourceAccumulator.add` to `addTag`.

- [ ] **Step 5: Add caption event and segment builders**

Add private classes in `script_ai_role_evidence_builder.dart`:

```dart
class _CaptionEvent {
  final int frameIndex;
  final String caption;
  final String normalizedCaption;
  final List<String> tags;
  final Set<String> tagKeys;

  const _CaptionEvent({
    required this.frameIndex,
    required this.caption,
    required this.normalizedCaption,
    required this.tags,
    required this.tagKeys,
  });
}

class _TimelineSegment {
  final int startFrameIndex;
  final int endFrameIndex;
  final String representativeCaption;
  final List<String> tags;
  final Set<String> tagKeys;
  final List<int> frameIndexes;

  const _TimelineSegment({
    required this.startFrameIndex,
    required this.endFrameIndex,
    required this.representativeCaption,
    required this.tags,
    required this.tagKeys,
    required this.frameIndexes,
  });

  Map<String, dynamic> toJson({
    required Set<String> previousKeys,
    required Set<String> nextKeys,
  }) {
    final neighborKeys = {...previousKeys, ...nextKeys};
    final variantTags = [
      for (final tag in tags)
        if (!neighborKeys.contains(PromptTagProcessor.normalizeMatchKey(tag)))
          tag,
    ];
    return {
      'frame_range': [startFrameIndex, endFrameIndex],
      'representative_caption': representativeCaption,
      'stable_tags': tags,
      'variant_tags': variantTags,
      'frame_indexes': frameIndexes,
    };
  }
}
```

Add helpers:

```dart
String _normalizedCaptionKey(String caption) {
  final tags = PromptTagProcessor.splitWorkshopTags(caption)
      .map(PromptTagProcessor.cleanTagDisplay)
      .map(PromptTagProcessor.normalizeMatchKey)
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false)
    ..sort();
  return tags.join('|');
}

List<String> _captionTags(String caption) {
  final seen = <String>{};
  final tags = <String>[];
  for (final rawTag in PromptTagProcessor.splitWorkshopTags(caption)) {
    final display = PromptTagProcessor.cleanTagDisplay(rawTag).trim();
    final key = PromptTagProcessor.normalizeMatchKey(display);
    if (display.isEmpty || key.isEmpty || !seen.add(key)) {
      continue;
    }
    tags.add(display);
  }
  return List.unmodifiable(tags);
}

List<int> _limitedFrameIndexes(List<int> indexes, int limit) {
  final seen = <int>{};
  final result = <int>[];
  for (final index in indexes) {
    if (limit > 0 && result.length >= limit) break;
    if (seen.add(index)) result.add(index);
  }
  return List.unmodifiable(result);
}
```

- [ ] **Step 6: Emit timeline segments from `_SourceAccumulator`**

Add fields to `_SourceAccumulator`:

```dart
final int maxTimelineSegments;
final List<_CaptionEvent> _captionEvents = [];
```

Add:

```dart
void addCaption({
  required int frameIndex,
  required String caption,
}) {
  final tags = _captionTags(caption);
  if (tags.isEmpty) {
    return;
  }
  _captionEvents.add(
    _CaptionEvent(
      frameIndex: frameIndex,
      caption: caption,
      normalizedCaption: _normalizedCaptionKey(caption),
      tags: tags,
      tagKeys: tags
          .map(PromptTagProcessor.normalizeMatchKey)
          .where((tag) => tag.isNotEmpty)
          .toSet(),
    ),
  );
}
```

Add segment construction:

```dart
List<_TimelineSegment> _timelineSegments() {
  if (_captionEvents.isEmpty) return const [];
  final segments = <_TimelineSegment>[];
  var current = <_CaptionEvent>[];
  for (final event in _captionEvents) {
    if (current.isEmpty ||
        current.first.normalizedCaption == event.normalizedCaption) {
      current.add(event);
      continue;
    }
    segments.add(_segmentFromEvents(current));
    current = [event];
  }
  if (current.isNotEmpty) {
    segments.add(_segmentFromEvents(current));
  }
  return _limitedSegments(segments);
}

_TimelineSegment _segmentFromEvents(List<_CaptionEvent> events) {
  final first = events.first;
  final frameIndexes = _limitedFrameIndexes(
    [for (final event in events) event.frameIndex],
    maxFrameIndexesPerTag,
  );
  return _TimelineSegment(
    startFrameIndex: first.frameIndex,
    endFrameIndex: events.last.frameIndex,
    representativeCaption: first.caption,
    tags: first.tags,
    tagKeys: first.tagKeys,
    frameIndexes: frameIndexes,
  );
}

List<_TimelineSegment> _limitedSegments(List<_TimelineSegment> segments) {
  if (maxTimelineSegments <= 0 || segments.length <= maxTimelineSegments) {
    return List.unmodifiable(segments);
  }
  final selected = <_TimelineSegment>[];
  void addSegment(_TimelineSegment segment) {
    if (!selected.any((item) =>
        item.startFrameIndex == segment.startFrameIndex &&
        item.endFrameIndex == segment.endFrameIndex)) {
      selected.add(segment);
    }
  }

  final firstCount = maxTimelineSegments ~/ 3;
  final lastCount = maxTimelineSegments ~/ 3;
  for (final segment in segments.take(firstCount)) {
    addSegment(segment);
  }
  for (final segment in segments.reversed.take(lastCount).toList().reversed) {
    addSegment(segment);
  }

  final remaining = [...segments]
    ..sort((left, right) =>
        right.frameIndexes.length.compareTo(left.frameIndexes.length));
  for (final segment in remaining) {
    if (selected.length >= maxTimelineSegments) break;
    addSegment(segment);
  }
  selected.sort((left, right) =>
      left.startFrameIndex.compareTo(right.startFrameIndex));
  return List.unmodifiable(selected);
}
```

Update `toJson`:

```dart
final segments = _timelineSegments();
return {
  'source_id': sourceId,
  'source_kind': sourceKind,
  'timeline_segments': [
    for (final (index, segment) in segments.indexed)
      segment.toJson(
        previousKeys: index == 0 ? const {} : segments[index - 1].tagKeys,
        nextKeys:
            index + 1 >= segments.length ? const {} : segments[index + 1].tagKeys,
      ),
  ],
  'tag_evidence': [
    for (final tag in _tags.values) tag.toJson(),
  ],
};
```

- [ ] **Step 7: Run builder tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart
```

Expected: PASS.

## Task 3: Parser And Client Prompt Updates

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_extraction_parser.dart`
- Modify: `lib/data/studio/services/script_ai_role_extraction_client.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_parser_test.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_client_test.dart`

- [ ] **Step 1: Add parser coverage for follow-up status**

Add:

```dart
test('parser accepts needs_more_evidence response', () {
  const parser = ScriptAiRoleExtractionParser();
  final extraction = parser.parse('''
  {
    "schema_version": 2,
    "status": "needs_more_evidence",
    "chunk_id": "chunk-1",
    "evidence_requests": [
      {
        "id": "slot-0-stage-ambiguity",
        "source_id": "slot-0",
        "frame_indexes": [1, 2],
        "wanted_fields": ["base_caption", "char_caption"],
        "reason": "Need exact captions."
      }
    ]
  }
  ''');

  expect(extraction.isNeedsMoreEvidence, isTrue);
  expect(extraction.evidenceRequests.single.sourceId, 'slot-0');
});
```

- [ ] **Step 2: Add client prompt assertions**

In `script_ai_role_extraction_client_test.dart`, update the request JSON from `chunk_extract` to `chunk_extract_v2` in existing tests and assert the prompt contains the new protocol:

```dart
expect(systemPrompt, contains('chunk_extract_v2'));
expect(systemPrompt, contains('timeline_segments'));
expect(systemPrompt, contains('needs_more_evidence'));
expect(systemPrompt, contains('evidence_followup'));
expect(systemPrompt, contains('Request only frame/source evidence'));
expect(systemPrompt, contains('never file paths'));
```

Also keep existing assertions for:

```dart
expect(systemPrompt, contains('strong_filter_keywords'));
expect(systemPrompt, contains('official art'));
expect(systemPrompt, isNot(contains('asset catalog')));
```

- [ ] **Step 3: Run parser and client tests and verify failure**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_parser_test.dart test/data/studio/services/script_ai_role_extraction_client_test.dart
```

Expected: FAIL until the model from Task 1 and the client prompt are updated.

- [ ] **Step 4: Update the system prompt**

In `_systemPrompt` inside `OpenAiCompatibleScriptAiRoleExtractionClient`, replace the request-kind section with content that includes:

```text
If request_kind is chunk_extract_v2:
- The input contains source-level tag_evidence plus timeline_segments.
- timeline_segments contain frame_range, representative_caption, stable_tags, variant_tags, and frame_indexes.
- Return one chunk-local extraction object when evidence is sufficient.
- Include chunk_id from input.
- If evidence is insufficient, return status "needs_more_evidence" with bounded evidence_requests.

If returning status "needs_more_evidence":
- Request only source_id plus frame_indexes from the current chunk.
- Request only frame/source evidence; never file paths, directories, images, external assets, arbitrary JSON files, character cards, outfit cards, or vibe data.
- Use at most 3 evidence request groups.
- Use at most 12 frames per request group.
- Prefer low confidence over over-requesting or inventing tags.

If request_kind is evidence_followup:
- Use the supplied exact frame evidence to return final status "ready" or "failed".
- Do not return another needs_more_evidence response.
```

Keep the current rules that say:

```text
Do not invent tags.
Missing fields are valid.
Do not split stages for action, pose, expression, camera, damage, wetness, stains, lighting, background, or temporary quality noise.
Extract official art/style as artist-chain evidence.
Extract mosaic/censor terms as strong filter keywords.
```

Update any client test input request kind:

```dart
'request_kind': 'chunk_extract_v2',
```

- [ ] **Step 5: Run parser and client tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_parser_test.dart test/data/studio/services/script_ai_role_extraction_client_test.dart
```

Expected: PASS.

## Task 4: Service Follow-Up Orchestration

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_extraction_service.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_service_test.dart`

- [ ] **Step 1: Update existing service tests for v2**

Change existing chunk request expectations:

```dart
expect(
  fakeClient.requests.single.requestJson['request_kind'],
  'chunk_extract_v2',
);
expect(result.requestPreview['request_kind'], 'chunk_extract_v2');
```

Update `_isChunkRequest`:

```dart
bool _isChunkRequest(ScriptAiRoleExtractionClientRequest request) {
  return request.requestJson['request_kind'] == 'chunk_extract_v2';
}
```

Keep `_isMergeRequest` as `merge_extractions`.

- [ ] **Step 2: Add failing follow-up happy-path test**

Add:

```dart
test('needs_more_evidence sends one evidence_followup request', () async {
  final fakeClient = _FakeRoleExtractionClient((request) {
    if (request.requestJson['request_kind'] == 'chunk_extract_v2') {
      return ScriptAiRoleExtractionClientResult(
        rawJson: _needsEvidenceRawExtraction(),
      );
    }
    expect(request.requestJson['request_kind'], 'evidence_followup');
    expect(request.requestJson['schema_version'], 2);
    expect(request.requestJson['chunk_id'], 'chunk-1');
    final evidence = (request.requestJson['evidence'] as List)
        .cast<Map<String, dynamic>>();
    expect(evidence, hasLength(2));
    expect(evidence.first['source_id'], 'slot-0');
    expect(evidence.first['frame_index'], 1);
    expect(evidence.first['base_caption'], contains('school uniform'));
    expect(evidence.first['char_caption'], contains('black coat'));
    expect(evidence.first['negative_base'], contains('bad anatomy'));
    expect(evidence.first['negative_char_caption'], contains('lowres'));
    return ScriptAiRoleExtractionClientResult(rawJson: _rawExtraction());
  });
  final service = DefaultScriptAiRoleExtractionService(
    client: fakeClient,
    retryDelays: const [],
  );

  final result = await service.extractRoles(
    request: _request(
      script: _script([
        _frame(
          1,
          baseCaption: 'school uniform',
          charCaptions: ['black coat, black pantyhose'],
          negativeBase: 'bad anatomy',
          negativeCharCaptions: ['lowres'],
        ),
        _frame(
          2,
          baseCaption: 'school uniform',
          charCaptions: ['black coat, no shoes'],
          negativeBase: 'bad anatomy',
          negativeCharCaptions: ['lowres'],
        ),
      ]),
    ),
  );

  expect(fakeClient.requests, hasLength(2));
  expect(fakeClient.requests.last.requestJson['request_kind'], 'evidence_followup');
  expect(result.aiRequestCount, 2);
  expect(result.extraction.isReady, isTrue);
  expect(result.requestPreview['request_kind'], 'evidence_followup');
});
```

Add helper:

```dart
String _needsEvidenceRawExtraction({
  List<int> frameIndexes = const [1, 2],
  String sourceId = 'slot-0',
}) {
  return '''
  {
    "schema_version": 2,
    "status": "needs_more_evidence",
    "chunk_id": "chunk-1",
    "evidence_requests": [
      {
        "id": "slot-0-stage-ambiguity",
        "source_id": "$sourceId",
        "frame_indexes": $frameIndexes,
        "wanted_fields": ["base_caption", "char_caption", "negative_caption"],
        "reason": "Need exact nearby captions."
      }
    ]
  }
  ''';
}
```

- [ ] **Step 3: Add failing guardrail tests**

Add:

```dart
test('follow-up caps request groups and total frames', () async {
  final fakeClient = _FakeRoleExtractionClient((request) {
    if (request.requestJson['request_kind'] == 'chunk_extract_v2') {
      return ScriptAiRoleExtractionClientResult(
        rawJson: '''
        {
          "schema_version": 2,
          "status": "needs_more_evidence",
          "chunk_id": "chunk-1",
          "evidence_requests": [
            {"id":"a","source_id":"slot-0","frame_indexes":[1,2,3,4,5,6,7,8,9,10,11,12,13],"wanted_fields":[],"reason":"a"},
            {"id":"b","source_id":"slot-0","frame_indexes":[14,15,16,17,18,19,20,21,22,23,24,25],"wanted_fields":[],"reason":"b"},
            {"id":"c","source_id":"slot-0","frame_indexes":[26,27,28,29,30,31,32,33,34,35,36,37],"wanted_fields":[],"reason":"c"},
            {"id":"d","source_id":"slot-0","frame_indexes":[38],"wanted_fields":[],"reason":"d"}
          ]
        }
        ''',
      );
    }
    final evidence = (request.requestJson['evidence'] as List)
        .cast<Map<String, dynamic>>();
    expect(evidence, hasLength(24));
    expect(
      evidence.map((row) => row['frame_index']),
      isNot(contains(25)),
    );
    return ScriptAiRoleExtractionClientResult(rawJson: _rawExtraction());
  });

  final service = DefaultScriptAiRoleExtractionService(
    client: fakeClient,
    retryDelays: const [],
  );

  await service.extractRoles(
    request: _request(script: _script([
      for (var index = 1; index <= 40; index += 1)
        _frame(index, charCaptions: ['slot frame $index']),
    ])),
  );

  expect(fakeClient.requests, hasLength(2));
});

test('invalid follow-up source is returned as failed extraction', () async {
  final fakeClient = _FakeRoleExtractionClient((request) {
    return ScriptAiRoleExtractionClientResult(
      rawJson: _needsEvidenceRawExtraction(sourceId: '../secret.json'),
    );
  });
  final service = DefaultScriptAiRoleExtractionService(
    client: fakeClient,
    retryDelays: const [],
  );

  final result = await service.extractRoles(
    request: _request(script: _script([
      _frame(1, charCaptions: ['black coat']),
    ])),
  );

  expect(fakeClient.requests, hasLength(1));
  expect(result.extraction.isFailed, isTrue);
  expect(
    result.extraction.attentionItems.map((item) => item.kind),
    contains('invalid_evidence_request'),
  );
});

test('follow-up response cannot request another follow-up', () async {
  final fakeClient = _FakeRoleExtractionClient((request) {
    return ScriptAiRoleExtractionClientResult(
      rawJson: _needsEvidenceRawExtraction(),
    );
  });
  final service = DefaultScriptAiRoleExtractionService(
    client: fakeClient,
    retryDelays: const [],
  );

  final result = await service.extractRoles(
    request: _request(script: _script([
      _frame(1, charCaptions: ['black coat']),
      _frame(2, charCaptions: ['black coat, no shoes']),
    ])),
  );

  expect(fakeClient.requests, hasLength(2));
  expect(result.extraction.isFailed, isTrue);
  expect(
    result.extraction.attentionItems.map((item) => item.kind),
    contains('followup_limit_reached'),
  );
});
```

- [ ] **Step 4: Run service tests and verify failure**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_service_test.dart
```

Expected: FAIL until service orchestration and v2 request naming are implemented.

- [ ] **Step 5: Add follow-up helper types inside service file**

Add private constants:

```dart
const _maxEvidenceRequestGroupsPerChunk = 3;
const _maxFramesPerEvidenceRequestGroup = 12;
const _maxTotalFollowUpFramesPerChunk = 24;
```

Add private source descriptor:

```dart
class _EvidenceSourceRef {
  final String sourceId;
  final int? slotIndex;

  const _EvidenceSourceRef({
    required this.sourceId,
    required this.slotIndex,
  });
}
```

Add source parsing:

```dart
_EvidenceSourceRef? _parseEvidenceSource(String sourceId) {
  final normalized = sourceId.trim();
  if (normalized == 'base' || normalized == 'negative-base') {
    return _EvidenceSourceRef(sourceId: normalized, slotIndex: null);
  }
  final slotMatch = RegExp(r'^(negative-)?slot-(\d+)$').firstMatch(normalized);
  if (slotMatch == null) {
    return null;
  }
  return _EvidenceSourceRef(
    sourceId: normalized,
    slotIndex: int.tryParse(slotMatch.group(2) ?? ''),
  );
}
```

- [ ] **Step 6: Build follow-up request JSON from parsed script frames**

Add:

```dart
Map<String, dynamic> _evidenceFollowUpRequest({
  required Script script,
  required Map<String, dynamic> chunk,
  required ScriptAiRoleExtraction extraction,
}) {
  final chunkMap = (chunk['chunk'] as Map?)?.cast<String, dynamic>() ?? const {};
  final startFrameIndex = _intValue(chunkMap['start_frame_index'], fallback: 0);
  final endFrameIndex = _intValue(chunkMap['end_frame_index'], fallback: 0);
  final framesByIndex = {
    for (final frame in script.frames)
      if (frame.parseStatus == ScriptFrameParseStatus.parsed)
        frame.index: frame,
  };

  final evidenceRows = <Map<String, dynamic>>[];
  final seenRows = <String>{};
  var usedGroups = 0;

  for (final request in extraction.evidenceRequests) {
    if (usedGroups >= _maxEvidenceRequestGroupsPerChunk) break;
    final source = _parseEvidenceSource(request.sourceId);
    if (source == null) {
      continue;
    }
    usedGroups += 1;
    var usedFramesInGroup = 0;
    for (final frameIndex in request.frameIndexes) {
      if (usedFramesInGroup >= _maxFramesPerEvidenceRequestGroup) break;
      if (evidenceRows.length >= _maxTotalFollowUpFramesPerChunk) break;
      if (startFrameIndex > 0 && frameIndex < startFrameIndex) continue;
      if (endFrameIndex > 0 && frameIndex > endFrameIndex) continue;
      final frame = framesByIndex[frameIndex];
      if (frame == null) continue;
      final key = '${request.sourceId}:$frameIndex';
      if (!seenRows.add(key)) continue;
      evidenceRows.add(
        _evidenceRowForFrame(
          frame: frame,
          source: source,
        ),
      );
      usedFramesInGroup += 1;
    }
  }

  return {
    'schema_version': 2,
    'request_kind': 'evidence_followup',
    'chunk_id': chunk['chunk_id'],
    'script': _scriptSummary(script),
    'chunk': chunk['chunk'],
    'evidence': evidenceRows,
  };
}

Map<String, dynamic> _evidenceRowForFrame({
  required ScriptFrame frame,
  required _EvidenceSourceRef source,
}) {
  final slotIndex = source.slotIndex;
  final parsed = frame.parsed;
  return {
    'frame_index': frame.index,
    'source_id': source.sourceId,
    'base_caption': parsed.baseCaption,
    'char_caption': slotIndex == null
        ? ''
        : _listValue(parsed.charCaptions, slotIndex),
    'negative_base': parsed.negativeBase,
    'negative_char_caption': slotIndex == null
        ? ''
        : _listValue(parsed.negativeCharCaptions, slotIndex),
  };
}

String _listValue(List<String> values, int index) {
  if (index < 0 || index >= values.length) return '';
  return values[index];
}
```

Use the existing `_intValue` helper if the file has one; otherwise add a private copy:

```dart
int _intValue(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value)?.toInt() ?? fallback;
  return fallback;
}
```

- [ ] **Step 7: Add attention item creation for invalid follow-up requests**

Add:

```dart
List<ScriptAiExtractionAttentionItem> _invalidEvidenceRequestItems(
  ScriptAiRoleExtraction extraction,
) {
  final items = <ScriptAiExtractionAttentionItem>[];
  for (final request in extraction.evidenceRequests) {
    if (_parseEvidenceSource(request.sourceId) != null) {
      continue;
    }
    items.add(
      ScriptAiExtractionAttentionItem(
        id: request.id.trim().isEmpty
            ? 'invalid-evidence-request-${items.length + 1}'
            : request.id,
        kind: 'invalid_evidence_request',
        message:
            'Ignored unsupported evidence source "${request.sourceId}".',
        frameIndexes: request.frameIndexes,
        blocking: false,
      ),
    );
  }
  return List.unmodifiable(items);
}

ScriptAiRoleExtraction _failedEvidenceRequestExtraction({
  required ScriptAiRoleExtraction extraction,
  required List<ScriptAiExtractionAttentionItem> attentionItems,
}) {
  return ScriptAiRoleExtraction(
    schemaVersion: extraction.schemaVersion,
    status: ScriptAiRoleExtractionStatus.failed,
    chunkId: extraction.chunkId,
    confidence: extraction.confidence,
    attentionItems: [
      ...extraction.attentionItems,
      ...attentionItems,
      const ScriptAiExtractionAttentionItem(
        id: 'ai-role-extraction-no-valid-followup-evidence',
        kind: 'invalid_evidence_request',
        message: 'AI requested follow-up evidence, but no valid frame evidence could be served.',
        blocking: true,
      ),
    ],
    unassignedTerms: extraction.unassignedTerms,
    rawResponse: extraction.rawResponse,
  );
}
```

- [ ] **Step 8: Orchestrate follow-up in the chunk loop**

In `extractRoles`, after parsing the first chunk extraction, replace the current ready/failed branching with:

```dart
final extraction = _normalizeOutfitStageVariants(
  parser.parse(result.rawJson),
);
if (extraction.isFailed) {
  return ScriptAiRoleExtractionServiceResult(
    extraction: extraction,
    requestPreview: chunk,
    aiRequestCount: aiRequestCount,
    reasoningContent: _joinReasoning(reasoningParts),
  );
}
if (extraction.isNeedsMoreEvidence) {
  final followUpResult = await _resolveFollowUp(
    serviceRequest: request,
    chunk: chunk,
    firstExtraction: extraction,
    reasoningParts: reasoningParts,
  );
  aiRequestCount += followUpResult.aiRequestCount;
  if (followUpResult.extraction.isFailed) {
    return ScriptAiRoleExtractionServiceResult(
      extraction: followUpResult.extraction,
      requestPreview: followUpResult.requestPreview,
      aiRequestCount: aiRequestCount,
      reasoningContent: _joinReasoning(reasoningParts),
    );
  }
  chunkExtractions.add(followUpResult.extraction);
  lastRequestPreview = followUpResult.requestPreview;
  continue;
}
chunkExtractions.add(extraction);
lastRequestPreview = chunk;
```

Before the chunk loop, add:

```dart
Map<String, dynamic>? lastRequestPreview;
```

When returning a single extraction, use:

```dart
requestPreview: lastRequestPreview ?? chunks.single,
```

Add result helper:

```dart
class _FollowUpResolution {
  final ScriptAiRoleExtraction extraction;
  final Map<String, dynamic> requestPreview;
  final int aiRequestCount;

  const _FollowUpResolution({
    required this.extraction,
    required this.requestPreview,
    required this.aiRequestCount,
  });
}
```

Add `_resolveFollowUp`:

```dart
Future<_FollowUpResolution> _resolveFollowUp({
  required ScriptAiRoleExtractionServiceRequest serviceRequest,
  required Map<String, dynamic> chunk,
  required ScriptAiRoleExtraction firstExtraction,
  required List<String> reasoningParts,
}) async {
  final invalidItems = _invalidEvidenceRequestItems(firstExtraction);
  final followUpRequest = _evidenceFollowUpRequest(
    script: serviceRequest.script,
    chunk: chunk,
    extraction: firstExtraction,
  );
  final evidence = (followUpRequest['evidence'] as List?) ?? const [];
  if (evidence.isEmpty) {
    return _FollowUpResolution(
      extraction: _failedEvidenceRequestExtraction(
        extraction: firstExtraction,
        attentionItems: invalidItems,
      ),
      requestPreview: followUpRequest,
      aiRequestCount: 0,
    );
  }

  serviceRequest.onRequestStarted?.call(followUpRequest);
  final clientRequest = ScriptAiRoleExtractionClientRequest(
    baseUrl: serviceRequest.baseUrl,
    token: serviceRequest.token,
    model: serviceRequest.model,
    proxy: serviceRequest.proxy,
    requestJson: followUpRequest,
    onStreamDelta: serviceRequest.onStreamDelta,
  );
  final result = await _extractWithRetry(clientRequest);
  _addReasoningPart(
    reasoningParts,
    title: '${chunk['chunk_id'] ?? 'chunk'} evidence_followup',
    content: result.reasoningContent,
  );
  final followUpExtraction = _normalizeOutfitStageVariants(
    parser.parse(result.rawJson),
  );
  if (followUpExtraction.isNeedsMoreEvidence) {
    return _FollowUpResolution(
      extraction: ScriptAiRoleExtraction(
        schemaVersion: followUpExtraction.schemaVersion,
        status: ScriptAiRoleExtractionStatus.failed,
        chunkId: followUpExtraction.chunkId,
        confidence: followUpExtraction.confidence,
        attentionItems: [
          ...followUpExtraction.attentionItems,
          const ScriptAiExtractionAttentionItem(
            id: 'ai-role-extraction-followup-limit-reached',
            kind: 'followup_limit_reached',
            message: 'AI requested more evidence after the single allowed follow-up round.',
            blocking: true,
          ),
        ],
        unassignedTerms: followUpExtraction.unassignedTerms,
        rawResponse: followUpExtraction.rawResponse,
      ),
      requestPreview: followUpRequest,
      aiRequestCount: 1,
    );
  }
  if (invalidItems.isEmpty || !followUpExtraction.isReady) {
    return _FollowUpResolution(
      extraction: followUpExtraction,
      requestPreview: followUpRequest,
      aiRequestCount: 1,
    );
  }
  return _FollowUpResolution(
    extraction: ScriptAiRoleExtraction(
      schemaVersion: followUpExtraction.schemaVersion,
      status: followUpExtraction.status,
      chunkId: followUpExtraction.chunkId,
      confidence: followUpExtraction.confidence,
      roles: followUpExtraction.roles,
      artistChains: followUpExtraction.artistChains,
      strongFilterKeywords: followUpExtraction.strongFilterKeywords,
      attentionItems: [
        ...followUpExtraction.attentionItems,
        ...invalidItems,
      ],
      unassignedTerms: followUpExtraction.unassignedTerms,
      rawResponse: followUpExtraction.rawResponse,
    ),
    requestPreview: followUpRequest,
    aiRequestCount: 1,
  );
}
```

- [ ] **Step 9: Preserve evidence requests during normalization**

Update `_normalizeOutfitStageVariants` return:

```dart
return ScriptAiRoleExtraction(
  schemaVersion: extraction.schemaVersion,
  status: extraction.status,
  chunkId: extraction.chunkId,
  confidence: extraction.confidence,
  roles: List.unmodifiable([
    for (final role in extraction.roles) _roleWithMergedStageVariants(role),
  ]),
  artistChains: extraction.artistChains,
  strongFilterKeywords: extraction.strongFilterKeywords,
  attentionItems: extraction.attentionItems,
  unassignedTerms: extraction.unassignedTerms,
  evidenceRequests: extraction.evidenceRequests,
  rawResponse: extraction.rawResponse,
);
```

Also preserve `evidenceRequests` in any new `ScriptAiRoleExtraction` copies created in service when carrying a parsed object through.

- [ ] **Step 10: Run service tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_service_test.dart
```

Expected: PASS.

## Task 5: ViewModel And Script Page Trace

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Add or update focused UI/ViewModel test**

Add a fake service test around the AI progress/details UI:

```dart
testWidgets('AI role extraction trace shows follow-up request summary', (tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final service = _FakeRoleExtractionService.withRequestTrace(
    extraction: const ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.ready,
      confidence: 0.9,
    ),
    requestPreviews: const [
      {
        'schema_version': 2,
        'request_kind': 'chunk_extract_v2',
        'chunk_id': 'chunk-1',
      },
      {
        'schema_version': 2,
        'request_kind': 'evidence_followup',
        'chunk_id': 'chunk-1',
        'evidence': [
          {'frame_index': 1, 'source_id': 'slot-0'},
        ],
      },
    ],
    aiRequestCount: 2,
  );

  final viewModel = StudioScriptViewModel(
    scriptAiRoleExtractionService: service,
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await tester.runAsync(() async {
    await viewModel.importScriptPath(_fixturePath);
    await viewModel.generateAiRoleExtraction();
  });
  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pumpAndSettle();

  expect(viewModel.aiRoleExtractionRequestCount, 2);
  expect(
    viewModel.aiRoleExtractionRequestPreview['request_kind'],
    'evidence_followup',
  );
  expect(find.textContaining('evidence_followup'), findsWidgets);
});
```

If `_FakeRoleExtractionService.withRequestTrace` does not exist, add a named constructor to the test fake that calls `request.onRequestStarted` for every preview and returns the configured `aiRequestCount`.

- [ ] **Step 2: Run the focused UI test and verify failure**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction trace shows follow-up request summary"
```

Expected: FAIL if the fake helper, labels, or preview handling do not support multiple request kinds.

- [ ] **Step 3: Keep ViewModel preview and count based on service result**

In `generateAiRoleExtraction`, keep the existing `onRequestStarted` trace append. Ensure the final assignment uses the service result:

```dart
aiRoleExtractionRequestPreview = result.requestPreview;
aiRoleExtractionRequestCount = result.aiRequestCount;
```

Do not change `applyHighConfidenceAiRoleExtraction` except to keep compiling with the model constructor changes from Task 1.

- [ ] **Step 4: Add request-kind labels in the page**

Find the existing UI helper that displays request kind in `_AiProgressPanel` or the AI details dialog. Add mapping:

```dart
String _aiRoleRequestKindLabel(String kind) {
  return switch (kind) {
    'chunk_extract_v2' => 'chunk_extract_v2',
    'evidence_followup' => 'evidence_followup',
    'merge_extractions' => 'merge_extractions',
    'chunk_extract' => 'chunk_extract',
    _ => kind,
  };
}
```

Use this helper wherever compact request-kind text is displayed. Keep full preview JSON in the existing details dialog.

- [ ] **Step 5: Run UI test**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction trace shows follow-up request summary"
```

Expected: PASS.

## Task 6: Backward Compatibility And Full Focused Verification

**Files:**
- Modify production files only if tests expose a real compile or behavior issue.

- [ ] **Step 1: Run model and parser compatibility tests**

Run:

```powershell
flutter test test/data/studio/models/script_ai_role_extraction_test.dart test/data/studio/services/script_ai_role_extraction_parser_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run builder/client/service tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart test/data/studio/services/script_ai_role_extraction_client_test.dart test/data/studio/services/script_ai_role_extraction_service_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run Script page tests touched by trace and apply behavior**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction trace shows follow-up request summary"
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "applying role extraction preserves empty clothing fields"
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "undetected upper clothing row is grey but editable"
```

Expected: PASS.

- [ ] **Step 4: Analyze touched files**

Run:

```powershell
dart analyze lib/data/studio/models/script_ai_role_extraction.dart lib/data/studio/services/script_ai_role_evidence_builder.dart lib/data/studio/services/script_ai_role_extraction_parser.dart lib/data/studio/services/script_ai_role_extraction_client.dart lib/data/studio/services/script_ai_role_extraction_service.dart lib/ui/studio_script/view_models/studio_script_viewmodel.dart lib/ui/studio_script/widgets/studio_script_page.dart
```

Expected: PASS.

- [ ] **Step 5: Update Beads without git operations**

Run:

```powershell
bd update NAI_NEW-lwm2 --notes="Implementation completed for Script AI evidence follow-up v2: chunk_extract_v2 timeline summaries, needs_more_evidence parsing, bounded evidence_followup service orchestration, trace display, and focused verification."
```

If the executor creates a separate implementation issue, use that issue id instead. Do not run `git add`, `git commit`, `git branch`, `git push`, `git reset`, or `git checkout` in this repository.

## Self-Review

- Spec coverage: Tasks 1-5 cover schema status, v2 compression, prompt rules, one-round follow-up, service guardrails, and UI trace. Task 6 covers compatibility and verification.
- Type consistency: `ScriptAiEvidenceRequest`, `evidenceRequests`, `needsMoreEvidence`, `chunk_extract_v2`, and `evidence_followup` are named consistently across tasks.
- Security boundary: The plan only serves frame evidence from `ScriptFrame.parsed` and rejects unsupported source IDs.
- Token boundary: Follow-up is capped at 3 groups, 12 frames per group, and 24 total rows per chunk.
- Stealth boundary: Git operations are excluded.
