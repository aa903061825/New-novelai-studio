# Architecture Hardening Next Slices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deepen the next set of Novel Studio Modules so payload parsing, script cache restore, asset library editing, workspace JSON handling, and app composition are easier to test and harder to regress.

**Architecture:** Keep current screens and view models as adapters. Extract repeated rules into small domain Modules with narrow Interfaces, then replace call sites one slice at a time while preserving current behavior. Start with pure data Modules because they give the highest test leverage and lowest UI risk.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `GetIt`, existing Novel Studio models/services, Beads issue `NAI_NEW-6nt7`.

---

## Scope

In scope:

- Extract a typed generation payload document for prompt, negative prompt, and visible parameter rules.
- Extract Script Recast source fingerprint and cache restore selection rules.
- Extract asset library query and character/outfit edit rules out of the page implementation.
- Move workspace JSON compaction/sanitization into focused codec/document Modules.
- Add an app composition root around `GetIt` registration and Shell page construction.
- Add structured operation status types for import/cache/catalog failures.

Out of scope:

- Full visual redesign of Script Studio, Asset Library, Gallery, or Batch Production.
- Rewriting all `GetIt` usage across the app in one pass.
- Renaming persisted workspace files or changing JSON schema without migration tests.
- Touching Script Recast cache generation scripts or API-backed translation/cache tools.
- Broad localization cleanup beyond text touched by the refactors.

## File Structure

Create:

- `lib/data/studio/models/generation_payload_document.dart`
  - Owns prompt extraction, negative prompt extraction, visible generation parameters, and fallback order for production/gallery/workbench payload maps.
- `test/data/studio/models/generation_payload_document_test.dart`
  - Pure data tests for v4 prompt, legacy prompt, visible parameter grouping, and malformed payloads.
- `lib/data/studio/services/script_recast_cache_restore_service.dart`
  - Owns source fingerprints, source content fingerprints, cache candidate scoring, exact/current cache matching, and stale snapshot fallback decisions.
- `test/data/studio/services/script_recast_cache_restore_service_test.dart`
  - Pure service tests for exact cache wins, content fingerprint fallback, AI draft score ordering, stale path rejection, and invalid snapshot tolerance.
- `lib/ui/studio_shell/models/asset_library_query.dart`
  - Owns asset filter/query/custom-category/codex paging request state and item sorting policy.
- `lib/ui/studio_shell/services/asset_library_edit_document.dart`
  - Owns character/outfit prompt edits, identity tag derivation, copy IDs, and preview reference removal.
- `test/ui/studio_shell/asset_library_query_test.dart`
- `test/ui/studio_shell/asset_library_edit_document_test.dart`
- `lib/data/workspace/workspace_json_codecs.dart`
  - Owns recast cache compaction, heavy payload removal, sensitive key sanitization, and repaired JSON decode result types.
- `test/data/workspace/workspace_json_codecs_test.dart`
- `lib/core/app_composition.dart`
  - Owns top-level registration and app dependency handles currently spread through `main.dart`.
- `lib/ui/studio_shell/studio_shell_dependencies.dart`
  - Owns Shell page dependency creation and typed adapters used by `StudioShellView`.
- `test/core/app_composition_test.dart`
- `lib/ui/core/operation_status.dart`
  - Owns structured status value for long-running operations.
- `test/ui/core/operation_status_test.dart`

Modify:

- `lib/main.dart`
- `lib/data/workspace/workspace_service.dart`
- `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- `lib/ui/studio_batch/widgets/studio_batch_page.dart`
- `lib/ui/studio_core/widgets/prompt_tag_display.dart`
- `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- `lib/ui/studio_shell/widgets/asset_library_page.dart`
- `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Existing focused tests that assert UI behavior for the touched pages.

## Task 1: Generation Payload Document

**Files:**

- Create: `lib/data/studio/models/generation_payload_document.dart`
- Create: `test/data/studio/models/generation_payload_document_test.dart`
- Modify: `lib/ui/studio_batch/widgets/studio_batch_page.dart`
- Modify: `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- Modify: `lib/ui/studio_core/widgets/prompt_tag_display.dart`

- [ ] **Step 1: Write failing pure data tests**

Add `test/data/studio/models/generation_payload_document_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/generation_payload_document.dart';

void main() {
  group('GenerationPayloadDocument', () {
    test('prefers v4 positive and negative captions from parameters', () {
      final document = GenerationPayloadDocument.fromMap({
        'input': 'legacy positive',
        'parameters': {
          'v4_prompt': {
            'caption': {'base_caption': 'v4 positive'},
          },
          'v4_negative_prompt': {
            'caption': {'base_caption': 'v4 negative'},
          },
          'negative_prompt': 'legacy negative',
        },
      });

      expect(document.positivePrompt, 'v4 positive');
      expect(document.negativePrompt, 'v4 negative');
    });

    test('falls back to legacy prompt fields when v4 captions are missing', () {
      final inputDocument = GenerationPayloadDocument.fromMap({
        'input': 'legacy input',
        'parameters': {'uc': 'legacy uc'},
      });
      final descriptionDocument = GenerationPayloadDocument.fromMap({
        'Description': 'legacy description',
      });

      expect(inputDocument.positivePrompt, 'legacy input');
      expect(inputDocument.negativePrompt, 'legacy uc');
      expect(descriptionDocument.positivePrompt, 'legacy description');
    });

    test('normalizes malformed payload maps to safe empty values', () {
      final document = GenerationPayloadDocument.fromMap({
        'parameters': 'not a map',
        'input': 42,
      });

      expect(document.positivePrompt, '');
      expect(document.negativePrompt, '');
      expect(document.parameters, isEmpty);
      expect(document.visibleParameterGroups, isEmpty);
    });

    test('groups visible parameters and hides large nested values', () {
      final document = GenerationPayloadDocument.fromMap({
        'model': 'nai-diffusion-4',
        'parameters': {
          'width': 832,
          'height': 1216,
          'steps': 28,
          'scale': 5.5,
          'seed': 123,
          'reference_image_multiple': ['large-base64'],
        },
      });

      expect(document.visibleParameterGroups.map((group) => group.id), [
        'core',
        'quality',
        'request',
      ]);
      expect(
        document.visibleParameterGroups
            .expand((group) => group.parameters)
            .map((parameter) => parameter.key),
        containsAll(['model', 'width', 'height', 'steps', 'scale', 'seed']),
      );
      expect(
        document.visibleParameterGroups
            .expand((group) => group.parameters)
            .map((parameter) => parameter.key),
        isNot(contains('reference_image_multiple')),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
flutter test test/data/studio/models/generation_payload_document_test.dart
```

Expected: FAIL because `generation_payload_document.dart` does not exist.

- [ ] **Step 3: Implement the document Module**

Create `lib/data/studio/models/generation_payload_document.dart`:

```dart
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_display.dart';

class GenerationPayloadDocument {
  final Map<String, dynamic> payload;
  final Map<String, dynamic> parameters;

  const GenerationPayloadDocument._({
    required this.payload,
    required this.parameters,
  });

  factory GenerationPayloadDocument.fromMap(Map<String, dynamic> payload) {
    final normalizedPayload = Map<String, dynamic>.unmodifiable(
      payload.map((key, value) => MapEntry(key.toString(), value)),
    );
    return GenerationPayloadDocument._(
      payload: normalizedPayload,
      parameters: _mapValue(normalizedPayload['parameters']),
    );
  }

  String get positivePrompt {
    return _captionPrompt(_mapValue(parameters['v4_prompt'])) ??
        _stringValue(payload['input']) ??
        _stringValue(payload['Description']) ??
        '';
  }

  String get negativePrompt {
    return _captionPrompt(_mapValue(parameters['v4_negative_prompt'])) ??
        _stringValue(parameters['negative_prompt']) ??
        _stringValue(parameters['uc']) ??
        '';
  }

  List<PromptTagDisplayGroup> get positivePromptGroups {
    return promptTagGroupsFromV4Prompt(_mapValue(parameters['v4_prompt']));
  }

  List<PromptTagDisplayGroup> get negativePromptGroups {
    return promptTagGroupsFromV4Prompt(
      _mapValue(parameters['v4_negative_prompt']),
      negative: true,
    );
  }

  List<GenerationParameterGroup> get visibleParameterGroups {
    final byKey = <String, GenerationParameter>{};
    void add(String key, Object? value) {
      if (_hiddenNaiParams.contains(key)) return;
      if (_isLargeOrNestedParameter(value)) return;
      byKey.putIfAbsent(key, () => _visibleParameter(key, value));
    }

    final model = _stringValue(payload['model']);
    if (model != null) add('model', model);
    for (final entry in parameters.entries) {
      add(entry.key, entry.value);
    }

    final byGroup = <String, List<GenerationParameter>>{};
    for (final parameter in byKey.values) {
      byGroup.putIfAbsent(parameter.groupId, () => []).add(parameter);
    }

    return [
      for (final spec in _parameterGroupSpecs)
        if (byGroup[spec.id] case final parameters?)
          GenerationParameterGroup(
            id: spec.id,
            title: spec.title,
            parameters: List.unmodifiable(
              parameters..sort(_compareVisibleParameters),
            ),
          ),
    ];
  }
}

class GenerationParameterGroup {
  final String id;
  final String title;
  final List<GenerationParameter> parameters;

  const GenerationParameterGroup({
    required this.id,
    required this.title,
    required this.parameters,
  });
}

class GenerationParameter {
  final String key;
  final String label;
  final String value;
  final String displayValue;
  final String groupId;
  final bool highlight;
  final bool monospace;

  const GenerationParameter({
    required this.key,
    required this.label,
    required this.value,
    required this.displayValue,
    required this.groupId,
    required this.highlight,
    required this.monospace,
  });
}

class _ParameterGroupSpec {
  final String id;
  final String title;

  const _ParameterGroupSpec(this.id, this.title);
}

const _parameterGroupSpecs = [
  _ParameterGroupSpec('core', '核心参数'),
  _ParameterGroupSpec('quality', '质量参数'),
  _ParameterGroupSpec('request', '请求参数'),
  _ParameterGroupSpec('other', '其他参数'),
];

const _parameterOrder = [
  'model',
  'width',
  'height',
  'steps',
  'scale',
  'cfg_rescale',
  'sampler',
  'seed',
];

const _coreParameterKeys = {
  'model',
  'width',
  'height',
  'sampler',
  'seed',
};

const _qualityParameterKeys = {
  'steps',
  'scale',
  'cfg_rescale',
  'noise_schedule',
};

const _requestParameterKeys = {
  'request_type',
  'action',
};

const _highlightParameterKeys = {
  'model',
  'width',
  'height',
  'steps',
  'scale',
  'sampler',
  'seed',
};

const _hiddenNaiParams = {
  'v4_prompt',
  'v4_negative_prompt',
  'reference_image_multiple',
  'negative_prompt',
  'uc',
};

const _parameterLabels = {
  'model': '模型',
  'width': '宽度',
  'height': '高度',
  'steps': '步数',
  'scale': 'Scale',
  'cfg_rescale': 'CFG Rescale',
  'sampler': '采样器',
  'seed': 'Seed',
};

GenerationParameter _visibleParameter(String key, Object? value) {
  final groupId = _parameterGroupForKey(key);
  final rawValue = _formatParameterValue(value);
  return GenerationParameter(
    key: key,
    label: _parameterLabels[key] ?? key,
    value: rawValue,
    displayValue: _compactParameterValue(rawValue),
    groupId: groupId,
    highlight: _highlightParameterKeys.contains(key),
    monospace: _isTechnicalParameter(key, rawValue),
  );
}

int _compareVisibleParameters(GenerationParameter a, GenerationParameter b) {
  final aIndex = _parameterOrder.indexOf(a.key);
  final bIndex = _parameterOrder.indexOf(b.key);
  if (aIndex != bIndex) {
    if (aIndex == -1) return 1;
    if (bIndex == -1) return -1;
    return aIndex.compareTo(bIndex);
  }
  return a.key.compareTo(b.key);
}

String _parameterGroupForKey(String key) {
  if (_coreParameterKeys.contains(key)) return 'core';
  if (_qualityParameterKeys.contains(key) ||
      key.contains('cfg') ||
      key.contains('sigma') ||
      key.contains('threshold')) {
    return 'quality';
  }
  if (_requestParameterKeys.contains(key) || key.contains('hash')) {
    return 'request';
  }
  return 'other';
}

String _formatParameterValue(Object? value) {
  return switch (value) {
    null => '-',
    bool() => value ? '是' : '否',
    num() => value.toString(),
    _ => value.toString(),
  };
}

String _compactParameterValue(String value) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= 72) return singleLine;
  return '${singleLine.substring(0, 40)}...'
      '${singleLine.substring(singleLine.length - 18)}';
}

bool _isTechnicalParameter(String key, String value) {
  return key.contains('hash') ||
      key.contains('fingerprint') ||
      key.contains('request') ||
      value.length > 32;
}

bool _isLargeOrNestedParameter(Object? value) {
  return value is Map || value is List;
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, child) => MapEntry(key.toString(), child));
  }
  return const {};
}

String? _stringValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String? _captionPrompt(Map<String, dynamic> prompt) {
  final caption = _mapValue(prompt['caption']);
  return _stringValue(caption['base_caption']) ??
      _stringValue(caption['char_caption']);
}
```

- [ ] **Step 4: Replace batch page helper reads**

In `lib/ui/studio_batch/widgets/studio_batch_page.dart`, import the document:

```dart
import 'package:nai_casrand/data/studio/models/generation_payload_document.dart';
```

Then replace `_positivePrompt`, `_negativePrompt`, `_positivePromptGroups`, `_negativePromptGroups`, and `_visibleParameterGroups` implementations with wrappers:

```dart
String _positivePrompt(Map<String, dynamic> payload) {
  return GenerationPayloadDocument.fromMap(payload).positivePrompt;
}

List<PromptTagDisplayGroup> _positivePromptGroups(
  Map<String, dynamic> payload,
) {
  return GenerationPayloadDocument.fromMap(payload).positivePromptGroups;
}

String _negativePrompt(Map<String, dynamic> payload) {
  return GenerationPayloadDocument.fromMap(payload).negativePrompt;
}

List<PromptTagDisplayGroup> _negativePromptGroups(
  Map<String, dynamic> payload,
) {
  return GenerationPayloadDocument.fromMap(payload).negativePromptGroups;
}
```

Keep UI-only icon and tile sizing code inside the page for this task. Convert `GenerationParameterGroup` to the existing `_VisibleParameterGroup` shape at the call site:

```dart
List<_VisibleParameterGroup> _visibleParameterGroups(
  Map<String, dynamic> payload,
) {
  return [
    for (final group
        in GenerationPayloadDocument.fromMap(payload).visibleParameterGroups)
      _VisibleParameterGroup(
        id: group.id,
        title: group.title,
        icon: _parameterGroupIcon(group.id),
        parameters: [
          for (final parameter in group.parameters)
            _VisibleParameter(
              key: parameter.key,
              label: parameter.label,
              value: parameter.value,
              displayValue: parameter.displayValue,
              groupId: parameter.groupId,
              icon: _parameterIconForKey(parameter.key, parameter.value),
              highlight: parameter.highlight,
              monospace: parameter.monospace,
            ),
        ],
      ),
  ];
}
```

- [ ] **Step 5: Use the document in generation digest paths**

In `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`, keep the output map format unchanged, but replace raw prompt fallback helpers with `GenerationPayloadDocument.fromMap(additionalInfo)`. The digest must still remove nested `parameters` after flattening:

```dart
Map<String, dynamic> digestPayloadResult(PayloadResult payloadResult) {
  final additionalInfo = Map<String, dynamic>.from(payloadResult.payload);
  final document = GenerationPayloadDocument.fromMap(additionalInfo);
  final additionalInfoParam = Map<String, dynamic>.from(
    additionalInfo['parameters']! as Map,
  );
  additionalInfo['input'] = document.positivePrompt;
  additionalInfo['negativePrompt'] = document.negativePrompt;
  additionalInfo.addAll(additionalInfoParam.cast<String, dynamic>());
  additionalInfo.remove('parameters');
  return additionalInfo;
}
```

- [ ] **Step 6: Run focused verification**

Run:

```bash
flutter test test/data/studio/models/generation_payload_document_test.dart
flutter test test/ui/studio_batch/studio_batch_page_test.dart --plain-name "shows completed task metadata"
flutter test test/ui/studio_core/prompt_tag_display_test.dart
```

Expected: all focused tests pass. If the `--plain-name` does not match an existing test name, run `flutter test test/ui/studio_batch/studio_batch_page_test.dart` and record the actual passing coverage in Beads.

## Task 2: Script Recast Cache Restore Service

**Files:**

- Create: `lib/data/studio/services/script_recast_cache_restore_service.dart`
- Create: `test/data/studio/services/script_recast_cache_restore_service_test.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify: `lib/data/workspace/workspace_service.dart` only if duplicate fingerprint code can be removed after service adoption.

- [ ] **Step 1: Write cache restore tests**

Add `test/data/studio/services/script_recast_cache_restore_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_recast_cache_restore_service.dart';

void main() {
  group('ScriptRecastCacheRestoreService', () {
    final service = ScriptRecastCacheRestoreService();

    test('chooses exact source fingerprint with newest AI-ready cache', () {
      final script = _script(id: 'script-a', rootPath: 'E:/source/a');
      final oldCache = _cache(
        script,
        updatedAt: DateTime.utc(2026, 1, 1),
        sourceFingerprint: service.sourceFingerprint(script),
      );
      final readyCache = _cache(
        script,
        updatedAt: DateTime.utc(2026, 1, 2),
        sourceFingerprint: service.sourceFingerprint(script),
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(sourceRoleId: 'slot-0', stages: []),
          ],
        ),
      );

      expect(
        service.bestExactCache(
          [oldCache, readyCache],
          script: script,
        ),
        same(readyCache),
      );
    });

    test('matches content fingerprint when root path changes', () {
      final script = _script(id: 'script-a', rootPath: 'E:/source/a');
      final moved = _script(id: 'script-a', rootPath: 'E:/moved/a');
      final cache = _cache(
        script,
        sourceFingerprint: 'old-path-fingerprint',
        sourceContentFingerprint: service.sourceContentFingerprint(script),
      );

      expect(service.cacheHasSourceContentFingerprint(cache, moved), isTrue);
    });

    test('does not match empty or corrupt snapshots', () {
      final script = _script(id: 'script-a', rootPath: 'E:/source/a');
      final cache = _cache(script, scriptSnapshot: const {});

      expect(service.cacheHasFrames(cache), isFalse);
      expect(service.sourceContentFingerprintFromSnapshot(cache), '');
    });
  });
}

Script _script({required String id, required String rootPath}) {
  return Script(
    id: id,
    name: 'Example',
    rootPath: rootPath,
    detectedSchema: ScriptSchema.nai,
    frames: [
      ScriptFrame(
        index: 0,
        fileName: 'p0.json',
        sourcePath: '$rootPath/p0.json',
        rawJson: '{"prompt":"girl"}',
        parseStatus: ScriptFrameParseStatus.parsed,
        parsed: const ParsedScriptFrame(
          prompt: 'girl',
          negativePrompt: '',
          parameters: {},
        ),
      ),
    ],
  );
}

RecastScriptCache _cache(
  Script script, {
  DateTime? updatedAt,
  String sourceFingerprint = '',
  String sourceContentFingerprint = '',
  ScriptAiRoleExtraction extraction = const ScriptAiRoleExtraction(),
  Map<String, dynamic>? scriptSnapshot,
}) {
  return RecastScriptCache(
    scriptId: script.id,
    scriptName: script.name,
    sourceRootPath: script.rootPath,
    sourceFingerprint: sourceFingerprint,
    sourceContentFingerprint: sourceContentFingerprint,
    scriptSnapshot: scriptSnapshot ?? script.toJson(),
    mapping: RecastMapping.defaults(script.id),
    aiRoleExtraction: extraction,
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  );
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
flutter test test/data/studio/services/script_recast_cache_restore_service_test.dart
```

Expected: FAIL because `script_recast_cache_restore_service.dart` does not exist.

- [ ] **Step 3: Implement service Interface**

Create `lib/data/studio/services/script_recast_cache_restore_service.dart`:

```dart
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/tools/stable_id.dart';

class ScriptRecastCacheRestoreService {
  const ScriptRecastCacheRestoreService();

  String sourceFingerprint(Script script) {
    final parts = [
      script.id,
      _normalizeScriptPath(script.rootPath),
      for (final frame in script.frames)
        '${frame.index}:${frame.fileName}:'
            '${_normalizeScriptPath(frame.sourcePath)}:'
            '${stableTextFingerprint(frame.rawJson)}',
    ];
    return parts.join('|');
  }

  String sourceContentFingerprint(Script script) {
    final parts = [
      'schema:${script.detectedSchema.name}',
      'frames:${script.frames.length}',
      for (final frame in script.frames)
        '${frame.index}:${frame.fileName}:${stableTextFingerprint(frame.rawJson)}',
    ];
    return parts.join('|');
  }

  bool cacheHasFrames(RecastScriptCache cache) {
    final snapshot = cache.scriptSnapshot;
    final frames = snapshot['frames'];
    return frames is List && frames.isNotEmpty;
  }

  bool cacheBelongsToScript(RecastScriptCache cache, Script script) {
    return cache.scriptId == script.id || cache.scriptName == script.name;
  }

  bool cacheHasSourceContentFingerprint(
    RecastScriptCache cache,
    Script script,
  ) {
    final expected = sourceContentFingerprint(script);
    if (expected.trim().isEmpty) return false;
    final current = cache.sourceContentFingerprint.trim().isNotEmpty
        ? cache.sourceContentFingerprint
        : sourceContentFingerprintFromSnapshot(cache);
    return current.isNotEmpty && current == expected;
  }

  String sourceContentFingerprintFromSnapshot(RecastScriptCache cache) {
    if (cache.scriptSnapshot.isEmpty) return '';
    try {
      return sourceContentFingerprint(Script.fromJson(cache.scriptSnapshot));
    } catch (_) {
      return '';
    }
  }

  RecastScriptCache? bestExactCache(
    Iterable<RecastScriptCache> caches, {
    required Script script,
  }) {
    final expected = sourceFingerprint(script);
    return bestCache([
      for (final cache in caches)
        if ((cacheBelongsToScript(cache, script) &&
                cache.sourceFingerprint == expected) ||
            cacheHasSourceContentFingerprint(cache, script))
          cache,
    ]);
  }

  RecastScriptCache? bestCache(Iterable<RecastScriptCache> caches) {
    RecastScriptCache? best;
    for (final cache in caches) {
      if (best == null || isBetterCacheCandidate(cache, best)) {
        best = cache;
      }
    }
    return best;
  }

  bool isBetterCacheCandidate(
    RecastScriptCache candidate,
    RecastScriptCache current,
  ) {
    final candidateScore = aiDraftScore(candidate);
    final currentScore = aiDraftScore(current);
    if (candidateScore != currentScore) {
      return candidateScore > currentScore;
    }
    return candidate.updatedAt.isAfter(current.updatedAt);
  }

  int aiDraftScore(RecastScriptCache cache) {
    final extraction = cache.aiRoleExtraction;
    if (extraction.isReady && extraction.roles.isNotEmpty) return 3;
    if (extraction.status != ScriptAiRoleExtractionStatus.idle) return 2;
    if (cache.aiRoleExtractionChunks.isNotEmpty) return 1;
    return 0;
  }
}

String _normalizeScriptPath(String value) {
  return value.trim().replaceAll('\\', '/').toLowerCase();
}
```

- [ ] **Step 4: Inject service into `StudioScriptViewModel`**

Add a constructor field and default:

```dart
final ScriptRecastCacheRestoreService cacheRestoreService;

StudioScriptViewModel({
  this.cacheRestoreService = const ScriptRecastCacheRestoreService(),
  ...
});
```

Then replace private methods `_sourceFingerprint`, `_sourceContentFingerprint`, `_cacheHasSourceContentFingerprint`, `_bestExactCache`, `_isBetterCacheCandidate`, and `_cacheAiDraftScore` with service calls. Example:

```dart
final currentFingerprint = cacheRestoreService.sourceFingerprint(script);
final currentContentFingerprint =
    cacheRestoreService.sourceContentFingerprint(script);
...
final bestCache = cacheRestoreService.bestExactCache(
  await loader(),
  script: script,
);
```

- [ ] **Step 5: Run focused verification**

Run:

```bash
flutter test test/data/studio/services/script_recast_cache_restore_service_test.dart
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "restores cached script"
flutter test test/data/workspace/workspace_service_test.dart --plain-name "loads recast script caches"
```

Expected: new service test passes; existing cache restore tests still pass. If named tests are unavailable, run the full target files and record which assertions covered restore behavior.

## Task 3: Asset Library Query and Edit Documents

**Files:**

- Create: `lib/ui/studio_shell/models/asset_library_query.dart`
- Create: `lib/ui/studio_shell/services/asset_library_edit_document.dart`
- Create: `test/ui/studio_shell/asset_library_query_test.dart`
- Create: `test/ui/studio_shell/asset_library_edit_document_test.dart`
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`

- [ ] **Step 1: Write query tests**

Add `test/ui/studio_shell/asset_library_query_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/studio_shell/models/asset_library_query.dart';

void main() {
  test('codex requests include codex query and reset paging on category change', () {
    final query = AssetLibraryQuery.initial()
        .copyWith(filter: AssetLibraryFilter.codex, text: 'papyrus')
        .selectCodexCategory('artist');

    expect(query.includeLegacyCodex, isTrue);
    expect(query.legacyCodexQuery, 'papyrus');
    expect(query.legacyCodexCategoryKey, 'artist');
    expect(query.legacyCodexLimit, AssetLibraryQuery.legacyCodexPageSize);
  });

  test('non-codex requests never pass text into legacy codex loading', () {
    final query = AssetLibraryQuery.initial().copyWith(text: 'artist');

    expect(query.includeLegacyCodex, isFalse);
    expect(query.legacyCodexQuery, '');
  });

  test('next codex page caps at total count', () {
    final query = AssetLibraryQuery.initial()
        .copyWith(filter: AssetLibraryFilter.codex)
        .nextCodexPage(loadedCount: 48, totalCount: 70);

    expect(query.legacyCodexLimit, 70);
  });
}
```

- [ ] **Step 2: Implement query model**

Create `lib/ui/studio_shell/models/asset_library_query.dart`:

```dart
enum AssetLibraryFilter {
  all,
  character,
  artistChain,
  recipe,
  tag,
  inspiration,
  lora,
  workflow,
  batchPlan,
  codex,
}

class AssetLibraryQuery {
  static const int legacyCodexPageSize = 48;

  final String text;
  final AssetLibraryFilter filter;
  final String? selectedBlock;
  final String? selectedCustomCategory;
  final String legacyCodexCategoryKey;
  final int legacyCodexLimit;

  const AssetLibraryQuery({
    required this.text,
    required this.filter,
    required this.selectedBlock,
    required this.selectedCustomCategory,
    required this.legacyCodexCategoryKey,
    required this.legacyCodexLimit,
  });

  factory AssetLibraryQuery.initial() {
    return const AssetLibraryQuery(
      text: '',
      filter: AssetLibraryFilter.all,
      selectedBlock: null,
      selectedCustomCategory: null,
      legacyCodexCategoryKey: 'all',
      legacyCodexLimit: legacyCodexPageSize,
    );
  }

  bool get includeLegacyCodex => filter == AssetLibraryFilter.codex;
  String get legacyCodexQuery => includeLegacyCodex ? text : '';

  AssetLibraryQuery copyWith({
    String? text,
    AssetLibraryFilter? filter,
    String? selectedBlock,
    String? selectedCustomCategory,
    String? legacyCodexCategoryKey,
    int? legacyCodexLimit,
  }) {
    return AssetLibraryQuery(
      text: text ?? this.text,
      filter: filter ?? this.filter,
      selectedBlock: selectedBlock ?? this.selectedBlock,
      selectedCustomCategory:
          selectedCustomCategory ?? this.selectedCustomCategory,
      legacyCodexCategoryKey:
          legacyCodexCategoryKey ?? this.legacyCodexCategoryKey,
      legacyCodexLimit: legacyCodexLimit ?? this.legacyCodexLimit,
    );
  }

  AssetLibraryQuery selectCodexCategory(String categoryKey) {
    return copyWith(
      filter: AssetLibraryFilter.codex,
      selectedBlock: null,
      selectedCustomCategory: null,
      legacyCodexCategoryKey: categoryKey,
      legacyCodexLimit: legacyCodexPageSize,
    );
  }

  AssetLibraryQuery nextCodexPage({
    required int loadedCount,
    required int totalCount,
  }) {
    final nextLimit = loadedCount + legacyCodexPageSize;
    return copyWith(
      legacyCodexLimit: nextLimit > totalCount ? totalCount : nextLimit,
    );
  }
}
```

- [ ] **Step 3: Write edit document tests**

Add `test/ui/studio_shell/asset_library_edit_document_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_shell/services/asset_library_edit_document.dart';

void main() {
  test('updates character identity prompt and derived identity tags', () {
    final character = CharacterEntry(
      id: 'papyrus',
      name: 'Papyrus',
      traits: const ViewVariantTexts(frontFull: 'old'),
      identityTags: const [],
      source: const SourceRef(type: 'import'),
    );

    final updated = AssetLibraryEditDocument.updateCharacterPrompt(
      character,
      'papyrus_(arknights), white_hair',
    );

    expect(updated.traits.frontFull, 'papyrus_(arknights), white_hair');
    expect(updated.identityTags, contains('papyrus_(arknights)'));
    expect(updated.source.type, 'manual');
  });

  test('updates outfit part prompt and rebuilds full prompt from parts', () {
    final outfit = WorkspaceOutfit(
      id: 'default',
      name: 'Default',
      tags: const ViewVariantTexts(frontFull: 'old outfit'),
      partTags: const WorkspaceOutfitPartTags(),
    );
    final updated = AssetLibraryEditDocument.updateOutfitPromptField(
      outfit,
      AssetLibraryOutfitPromptField.upperClothing,
      'blue jacket, open jacket',
    );

    expect(updated.partTags.upperClothingTags, [
      'blue jacket',
      'open jacket',
    ]);
    expect(updated.tags.frontFull, contains('blue jacket'));
  });
}
```

- [ ] **Step 4: Implement edit document**

Create `lib/ui/studio_shell/services/asset_library_edit_document.dart`:

```dart
import 'package:nai_casrand/data/studio/tools/character_identity_prompt.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

enum AssetLibraryCharacterPromptField { identity, upperBody, lowerBody }

enum AssetLibraryOutfitPromptField {
  full,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
}

class AssetLibraryEditDocument {
  const AssetLibraryEditDocument._();

  static CharacterEntry updateCharacterPrompt(
    CharacterEntry character,
    String prompt,
  ) {
    final trimmed = prompt.trim();
    return _manualizedCharacter(
      character.copyWith(
        traits: character.traits.copyWith(frontFull: trimmed),
        identityTags: characterIdentityTagsFromPrompt(trimmed),
      ),
    );
  }

  static WorkspaceOutfit updateOutfitPromptField(
    WorkspaceOutfit outfit,
    AssetLibraryOutfitPromptField field,
    String prompt,
  ) {
    final trimmed = prompt.trim();
    final tags = _tagValues(trimmed);
    final currentPartTags = outfit.partTags;
    final updatedPartTags = switch (field) {
      AssetLibraryOutfitPromptField.upperBody =>
        currentPartTags.copyWith(upperBodyTags: tags),
      AssetLibraryOutfitPromptField.lowerBody =>
        currentPartTags.copyWith(lowerBodyTags: tags),
      AssetLibraryOutfitPromptField.upperClothing =>
        currentPartTags.copyWith(upperClothingTags: tags),
      AssetLibraryOutfitPromptField.lowerClothing =>
        currentPartTags.copyWith(lowerClothingTags: tags),
      AssetLibraryOutfitPromptField.full => currentPartTags,
    };
    final fullPrompt = field == AssetLibraryOutfitPromptField.full
        ? trimmed
        : _promptFromTags(_outfitPartTags(updatedPartTags));
    return WorkspaceOutfit(
      id: outfit.id,
      name: outfit.name,
      tags: outfit.tags.copyWith(frontFull: fullPrompt),
      partTags: updatedPartTags,
      imageRefs: outfit.imageRefs,
      negativePrompt: outfit.negativePrompt,
      note: outfit.note,
    );
  }
}

CharacterEntry _manualizedCharacter(CharacterEntry character) {
  return character.copyWith(source: const SourceRef(type: 'manual'));
}

List<String> _tagValues(String value) {
  return PromptTagProcessor.splitWorkshopTags(value)
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

List<String> _outfitPartTags(WorkspaceOutfitPartTags partTags) {
  return [
    ...partTags.upperBodyTags,
    ...partTags.upperClothingTags,
    ...partTags.lowerBodyTags,
    ...partTags.lowerClothingTags,
  ];
}

String _promptFromTags(List<String> tags) {
  return tags
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .join(', ');
}
```

- [ ] **Step 5: Adopt incrementally in `AssetLibraryPage`**

In `lib/ui/studio_shell/widgets/asset_library_page.dart`, replace the bodies of `_saveCharacterPrompt`, `_saveOutfitPromptField`, and later `_filterItems` with calls into the new Modules. Preserve the existing `_AssetFilter` enum until the page can be migrated without churn:

```dart
final updatedCharacter = AssetLibraryEditDocument.updateCharacterPrompt(
  character,
  prompt,
);
```

For query adoption, first add a private mapper:

```dart
AssetLibraryFilter _queryFilterFor(_AssetFilter filter) {
  return switch (filter) {
    _AssetFilter.all => AssetLibraryFilter.all,
    _AssetFilter.character => AssetLibraryFilter.character,
    _AssetFilter.artistChain => AssetLibraryFilter.artistChain,
    _AssetFilter.recipe => AssetLibraryFilter.recipe,
    _AssetFilter.tag => AssetLibraryFilter.tag,
    _AssetFilter.inspiration => AssetLibraryFilter.inspiration,
    _AssetFilter.lora => AssetLibraryFilter.lora,
    _AssetFilter.workflow => AssetLibraryFilter.workflow,
    _AssetFilter.batchPlan => AssetLibraryFilter.batchPlan,
    _AssetFilter.codex => AssetLibraryFilter.codex,
  };
}
```

- [ ] **Step 6: Run focused verification**

Run:

```bash
flutter test test/ui/studio_shell/asset_library_query_test.dart
flutter test test/ui/studio_shell/asset_library_edit_document_test.dart
flutter test test/ui/studio_shell/asset_library_page_test.dart
```

Expected: all asset library tests pass.

## Task 4: Workspace JSON Codecs

**Files:**

- Create: `lib/data/workspace/workspace_json_codecs.dart`
- Create: `test/data/workspace/workspace_json_codecs_test.dart`
- Modify: `lib/data/workspace/workspace_service.dart`

- [ ] **Step 1: Write codec tests**

Add `test/data/workspace/workspace_json_codecs_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/workspace_json_codecs.dart';

void main() {
  test('removes heavy payload keys from nested recast snapshots', () {
    final compacted = RecastCacheJsonCodec.compact({
      'scriptSnapshot': {
        'frames': [
          {
            'rawJson': jsonEncode({
              'reference_image_multiple': ['large'],
              'prompt': 'girl',
            }),
            'parsed': {
              'generationParams': {
                'reference_image_multiple': ['large'],
                'steps': 28,
              },
            },
          },
        ],
      },
    });

    expect(compacted.changed, isTrue);
    final rawJson = compacted.value['scriptSnapshot']['frames'][0]['rawJson'];
    expect(rawJson, isNot(contains('reference_image_multiple')));
    expect(
      compacted.value['scriptSnapshot']['frames'][0]['parsed']
          ['generationParams'],
      {'steps': 28},
    );
  });

  test('sanitizes sensitive keys from user controlled maps', () {
    final sanitized = WorkspaceSanitizer.sanitizeMap({
      'safe': 'value',
      'apiKey': 'secret',
      'nested': {'token': 'secret', 'name': 'kept'},
    });

    expect(sanitized, {
      'safe': 'value',
      'nested': {'name': 'kept'},
    });
  });
}
```

- [ ] **Step 2: Implement codec Module**

Create `lib/data/workspace/workspace_json_codecs.dart` by moving the existing private helper behavior from `WorkspaceService` into public classes:

```dart
import 'dart:convert';

class CompactedJsonMap {
  final Map<String, dynamic> value;
  final bool changed;

  const CompactedJsonMap(this.value, this.changed);
}

class RecastCacheJsonCodec {
  const RecastCacheJsonCodec._();

  static CompactedJsonMap compact(Map<String, dynamic> json) {
    var changed = false;
    final result = Map<String, dynamic>.from(json);
    final scriptSnapshot = result['scriptSnapshot'];
    if (scriptSnapshot is Map) {
      final compacted = _compactScriptSnapshot(_jsonMap(scriptSnapshot));
      if (compacted.changed) {
        result['scriptSnapshot'] = compacted.value;
        changed = true;
      }
    }
    return CompactedJsonMap(result, changed);
  }
}

class WorkspaceSanitizer {
  const WorkspaceSanitizer._();

  static Map<String, dynamic> sanitizeMap(Map<String, dynamic> value) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (_isSensitiveKey(entry.key)) continue;
      final sanitized = _sanitizeValue(entry.value);
      if (sanitized != null) result[entry.key] = sanitized;
    }
    return result;
  }
}
```

Move the existing `_compactRecastScriptSnapshot`, `_compactRecastFrameJson`, `_compactRecastPayloadValue`, `_compactRecastCommentValue`, `_compactRecastRawJson`, `_isHeavyRecastPayloadKey`, `_containsHeavyRecastPayloadKey`, `_sanitizeFilterValue`, `_isSensitiveKey`, `_jsonMap`, and related value holder code into this file. Keep names private inside the codec file.

- [ ] **Step 3: Replace `WorkspaceService` private helpers**

In `lib/data/workspace/workspace_service.dart`, import the codec:

```dart
import 'package:nai_casrand/data/workspace/workspace_json_codecs.dart';
```

Then replace calls:

```dart
final compacted = RecastCacheJsonCodec.compact(decoded);
...
RecastCacheJsonCodec.compact(cache.toJson()).value
...
WorkspaceSanitizer.sanitizeMap(filterRules)
...
WorkspaceSanitizer.sanitizeMap(knowledgeBase)
```

Delete the moved private helper definitions from `workspace_service.dart` after all references compile.

- [ ] **Step 4: Run focused verification**

Run:

```bash
flutter test test/data/workspace/workspace_json_codecs_test.dart
flutter test test/data/workspace/workspace_service_test.dart
flutter test test/tool/normalize_script_recast_ai_cache_test.dart
```

Expected: codec tests pass, workspace persistence behavior remains unchanged.

## Task 5: Structured Operation Status

**Files:**

- Create: `lib/ui/core/operation_status.dart`
- Create: `test/ui/core/operation_status_test.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`

- [ ] **Step 1: Write operation status tests**

Add `test/ui/core/operation_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/core/operation_status.dart';

void main() {
  test('status keeps stable kind separate from display message', () {
    const status = OperationStatus.failure(
      code: OperationStatusCode.importFailed,
      message: '导入失败：文件损坏',
      recoverable: true,
    );

    expect(status.kind, OperationStatusKind.failure);
    expect(status.code, OperationStatusCode.importFailed);
    expect(status.message, '导入失败：文件损坏');
    expect(status.recoverable, isTrue);
  });

  test('idle and running helpers have predictable defaults', () {
    expect(const OperationStatus.idle().message, '');
    expect(
      const OperationStatus.running(
        code: OperationStatusCode.cacheRestore,
        message: '正在恢复缓存',
      ).recoverable,
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Implement status value**

Create `lib/ui/core/operation_status.dart`:

```dart
enum OperationStatusKind { idle, running, success, failure }

enum OperationStatusCode {
  none,
  importScript,
  importFailed,
  cacheRestore,
  cacheSave,
  aiExtraction,
  catalogRefresh,
}

class OperationStatus {
  final OperationStatusKind kind;
  final OperationStatusCode code;
  final String message;
  final bool recoverable;

  const OperationStatus._({
    required this.kind,
    required this.code,
    required this.message,
    required this.recoverable,
  });

  const OperationStatus.idle()
      : this._(
          kind: OperationStatusKind.idle,
          code: OperationStatusCode.none,
          message: '',
          recoverable: false,
        );

  const OperationStatus.running({
    required OperationStatusCode code,
    required String message,
  }) : this._(
          kind: OperationStatusKind.running,
          code: code,
          message: message,
          recoverable: false,
        );

  const OperationStatus.success({
    required OperationStatusCode code,
    required String message,
  }) : this._(
          kind: OperationStatusKind.success,
          code: code,
          message: message,
          recoverable: false,
        );

  const OperationStatus.failure({
    required OperationStatusCode code,
    required String message,
    bool recoverable = false,
  }) : this._(
          kind: OperationStatusKind.failure,
          code: code,
          message: message,
          recoverable: recoverable,
        );
}
```

- [ ] **Step 3: Adopt in Script ViewModel without removing old string fields**

Add fields beside existing strings first:

```dart
OperationStatus importOperationStatus = const OperationStatus.idle();
OperationStatus cacheOperationStatus = const OperationStatus.idle();
OperationStatus aiOperationStatus = const OperationStatus.idle();
```

Then update the status writers while preserving old string fields for UI compatibility:

```dart
void _setImportProgress(String message) {
  importOperationStatus = OperationStatus.running(
    code: OperationStatusCode.importScript,
    message: message,
  );
  folderStatus = message;
}
```

Replace failure paths:

```dart
importOperationStatus = OperationStatus.failure(
  code: OperationStatusCode.importFailed,
  message: folderStatus,
  recoverable: true,
);
```

- [ ] **Step 4: Fix the known placeholder status while touching this area**

In `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`, replace:

```dart
analysisStatus = '???????';
```

with:

```dart
analysisStatus = '已从缓存恢复映射';
```

This is a compatibility cleanup tied to status structuring, not a separate localization sweep.

- [ ] **Step 5: Run focused verification**

Run:

```bash
flutter test test/ui/core/operation_status_test.dart
flutter test test/ui/studio_script/studio_script_stage_label_test.dart
flutter test test/code_health/ui_mojibake_test.dart
```

Expected: operation status tests pass and mojibake health remains green.

## Task 6: App Composition and Shell Dependencies

**Files:**

- Create: `lib/core/app_composition.dart`
- Create: `lib/ui/studio_shell/studio_shell_dependencies.dart`
- Create: `test/core/app_composition_test.dart`
- Modify: `lib/main.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`

- [ ] **Step 1: Write composition smoke test**

Add `test/core/app_composition_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/core/app_composition.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  test('registerCoreServices provides stable service handles', () async {
    final services = await AppComposition.registerCoreServices(
      getIt: GetIt.I,
      initializeStudioData: false,
    );

    expect(services.workspaceService, isA<WorkspaceService>());
    expect(GetIt.I<ConfigService>(), same(services.configService));
    expect(GetIt.I<WorkspaceService>(), same(services.workspaceService));
  });
}
```

- [ ] **Step 2: Implement app composition root**

Create `lib/core/app_composition.dart`:

```dart
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class AppCompositionServices {
  final ConfigService configService;
  final WorkspaceService workspaceService;
  final StudioDataService studioDataService;

  const AppCompositionServices({
    required this.configService,
    required this.workspaceService,
    required this.studioDataService,
  });
}

class AppComposition {
  const AppComposition._();

  static Future<AppCompositionServices> registerCoreServices({
    required GetIt getIt,
    bool initializeStudioData = true,
  }) async {
    if (!getIt.isRegistered<ConfigService>()) {
      getIt.registerLazySingleton<ConfigService>(() => ConfigService());
    }
    final workspaceService = WorkspaceService();
    final studioDataService = StudioDataService(
      workspaceService: workspaceService,
    );
    if (initializeStudioData) {
      await studioDataService.initializeForApp();
    }
    getIt.registerSingleton<WorkspaceService>(workspaceService);
    getIt.registerSingleton<StudioDataService>(studioDataService);
    return AppCompositionServices(
      configService: getIt<ConfigService>(),
      workspaceService: workspaceService,
      studioDataService: studioDataService,
    );
  }
}
```

- [ ] **Step 3: Move only the first stable registration slice from `main.dart`**

Replace the initial `ConfigService`, `WorkspaceService`, and `StudioDataService` registration block in `main.dart` with:

```dart
final coreServices = await AppComposition.registerCoreServices(
  getIt: GetIt.instance,
);
final workspaceService = coreServices.workspaceService;
final studioDataService = coreServices.studioDataService;
final configService = coreServices.configService;
```

Keep later registration in `main.dart` for this task. This avoids changing all startup behavior in one step.

- [ ] **Step 4: Introduce Shell dependencies wrapper**

Create `lib/ui/studio_shell/studio_shell_dependencies.dart`:

```dart
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioShellDependencies {
  final GetIt getIt;

  const StudioShellDependencies({required this.getIt});

  ConfigService get configService => getIt<ConfigService>();
  WorkspaceService get workspaceService => getIt<WorkspaceService>();
  StudioAssetCatalogService get catalogService =>
      getIt<StudioAssetCatalogService>();
  StudioWorkbenchAssetService get workbenchAssetService =>
      getIt<StudioWorkbenchAssetService>();
  StudioGalleryService get galleryService => getIt<StudioGalleryService>();
}
```

Modify `StudioShellView` constructor:

```dart
final StudioShellDependencies dependencies;

StudioShellView({
  super.key,
  required this.viewModel,
  StudioShellDependencies? dependencies,
}) : dependencies = dependencies ??
        StudioShellDependencies(getIt: GetIt.I);
```

Then replace direct `GetIt.I<WorkspaceService>()` in `_buildCurrentPage` with `widget.dependencies.workspaceService`.

- [ ] **Step 5: Run focused verification**

Run:

```bash
flutter test test/core/app_composition_test.dart
flutter test test/ui/navigation/novel_studio_navigation_test.dart
flutter analyze
```

Expected: composition smoke test passes, navigation tests pass, analyzer completes. If `flutter analyze` exceeds 120 seconds on this machine, run targeted analyzer on touched files:

```bash
dart analyze lib/core/app_composition.dart lib/ui/studio_shell/studio_shell_dependencies.dart lib/main.dart lib/ui/studio_shell/widgets/studio_shell_view.dart
```

## Task 7: Final Verification and Beads Closeout

**Files:**

- Modify: `.beads/issues.jsonl` through `bd close` only after work is actually complete.

- [ ] **Step 1: Run the focused full slice suite**

Run:

```bash
flutter test test/data/studio/models/generation_payload_document_test.dart
flutter test test/data/studio/services/script_recast_cache_restore_service_test.dart
flutter test test/ui/studio_shell/asset_library_query_test.dart
flutter test test/ui/studio_shell/asset_library_edit_document_test.dart
flutter test test/data/workspace/workspace_json_codecs_test.dart
flutter test test/ui/core/operation_status_test.dart
flutter test test/core/app_composition_test.dart
```

Expected: all new tests pass.

- [ ] **Step 2: Run existing regression targets**

Run:

```bash
flutter test test/ui/studio_shell/asset_library_page_test.dart
flutter test test/ui/studio_batch/studio_batch_page_test.dart
flutter test test/ui/studio_script/studio_script_stage_label_test.dart
flutter test test/data/workspace/workspace_service_test.dart
flutter test test/code_health/ui_mojibake_test.dart
```

Expected: all pass.

- [ ] **Step 3: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: completes successfully. If it times out in this environment, run targeted `dart analyze` on all touched files and record the timeout plus targeted results in `bd update NAI_NEW-6nt7 --notes`.

- [ ] **Step 4: Update Beads**

If all implementation tasks are complete:

```bash
bd close NAI_NEW-6nt7 --reason="Architecture hardening plan implemented and focused regression suite passed"
```

If only the plan is complete and implementation remains:

```bash
bd update NAI_NEW-6nt7 --notes="Plan saved at docs/superpowers/plans/2026-06-15-architecture-hardening-next-slices.md. Implementation remains open."
```

## Self-Review

Spec coverage:

- App composition root is covered by Task 6.
- Script Recast cache/session restore is covered by Task 2.
- Generation payload/metadata document is covered by Task 1.
- Asset library query/edit behavior is covered by Task 3.
- Workspace typed document/codecs are covered by Task 4.
- Structured failures/status are covered by Task 5.
- Verification and Beads closeout are covered by Task 7.

Placeholder scan:

- The plan does not use TODO/TBD placeholders.
- Steps that change code include concrete snippets and exact file paths.
- Any optional fallback is paired with exact verification and Beads notes.

Type consistency:

- `GenerationPayloadDocument`, `ScriptRecastCacheRestoreService`, `AssetLibraryQuery`, `AssetLibraryEditDocument`, `RecastCacheJsonCodec`, `WorkspaceSanitizer`, `OperationStatus`, and `AppComposition` names are used consistently across tests and implementation snippets.
